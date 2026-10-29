# Context

routnix needs to configure values that must not be readable from the repo or
from the Nix store (user passwords, PPPoE/WireGuard credentials, PSKs,
certificates) while RouterOS still needs the plaintext in its config database.
A rendered `.rsc` is a `pkgs.writeText` result, so anything it contains is
world-readable in `/nix/store` forever; it may contain only a reference to a
secret, never the value. RouterOS cannot decrypt anything, so decryption has to
happen outside it. On the RouterOS side a secret is always a string: it renders
to an expression that evaluates to that string at import time, and nothing
distinguishes a secret field from any other field afterwards.

# Decision

Secrets are deploy-time state, not `routeros.config` entries. Nothing about
them goes through the entry reconciliation pipeline, there is no `/file`
resource kind, and the rendered `.rsc` only *dereferences* what the deploy step
put on the router. Uploading the payload is a precondition of `/import`, not
part of it. A `.rsc` is therefore no longer standalone-applicable: importing
one on a router that never received its payload fails in the prologue.

Secrets are committed as a sops document over YAML. Encryption is what makes
the file safe to commit, and per-value encryption keeps additions to a small,
reviewable diff (unlike an `age` blob over the whole file), while YAML stays
usable by hand (unlike `dotenv`, which `sops exec-env` would require). The file
is a `types.path` option, copied into the store as ciphertext, with an eval-time
existence check. Decryption happens on the deploy host, not on the router,
because RouterOS cannot run the equivalent of a sops-nix activation step. The
key location is ambient (`SOPS_AGE_KEY`/`SOPS_AGE_KEY_FILE`, like ssh auth), so
nothing key-shaped ends up in the store or in a flake.

The decrypted document is turned into a single RouterOS literal at upload time
and sent as one file, `routnix-secrets`:

```rsc
:return {"name"="value";"other"="value"}
```

The payload is one file holding one dict, not one file per secret: one upload,
one read, one name to manage, and nothing to sweep when a declaration is
removed. Keys in the literal are declaration names, never YAML paths, so the
`.rsc` side stays stable when the YAML is reorganised. The literal is rendered
by routnix, not committed as plaintext, so the thing at rest stays a normal
YAML document.

A prologue loads the payload once, into a local, ahead of `preCheck` and every
entry:

```rsc
:local secrets [[:parse value=[/file get "routnix-secrets" value-name="contents"]]];
```

Loading it up front fails before anything is checked or changed when the
payload is missing (routnix has no rollback, see
[`../rfc/apply-mechanism.md`](../rfc/apply-mechanism.md)), and leaves the
values ready wherever they are used. `:parse` executes the literal and a
`:global` would stay readable to every script and admin, so a local `:parse`
is used. A payload file is a fixed, prefixed name because `/file` is one flat
namespace shared with user files.

The value type in Nix is a tagged attrset, a custom option type:

```nix
{__routnixSecret = "name";}
```

`renderValue` special-cases it and emits the lookup expression unquoted:

```rsc
($secrets->"name")
```

A magic string prefix was rejected because it is indistinguishable from a
literal that happens to look like one. The parenthesised form is valid both as
an argument value (`set password=($secrets->"name")`) and as the right-hand
side of a `find where` clause (`name=($secrets->"name")`), so `renderArgs` and
`renderQuery` share it unchanged. The name is escaped into RouterOS string
syntax. A secret is never emitted as a quoted literal.

Secrets are declared per entry, each exposing a read-only `.reference`:

```nix
routeros.secrets.file = ./secrets.yaml;
routeros.secrets.entries.mailPassword.key = "mail/password";

routeros.config."/system note".settings.note =
  config.routeros.secrets.entries.mailPassword.reference;
```

A file-level option taking bare key paths was rejected because a per-secret
entry gives a place for metadata, makes the reference discoverable in `nix
repl` and option completion, and makes "referenced but not declared" checkable
at eval time, at the cost of verbosity. The YAML may nest; the Nix side is
always a flat `entries.<name>`, and `key` reaches into the document. `key` is a
`/`-separated string (`"mail/password"`) rather than a list of path
components.

Every secret is a string. YAML scalars that are not strings render as strings,
since the payload dict and RouterOS fields are text anyway, and a value is
passed through as-is: no trimming, no newline stripping, no normalisation.

High-level modules that hand-write `.rsc` inside `create` cannot go through
`renderValue`; they use `lib.routnix.secretRead "name"`, which returns the same
lookup expression. Options that accept a secret value, such as
`users.users.<n>.initialPassword`, accept either the option's literal type or a
reference and render it through `renderValue`.

Per-kind change detection is covered in
[`secret-change-detection.md`](./secret-change-detection.md). The deploy side
is covered in [`secret-deploy.md`](./secret-deploy.md).
