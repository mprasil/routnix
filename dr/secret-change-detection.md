# Context

A secret renders to a fixed expression (`password=($secrets->"name")`), so the
rendered `.rsc` is byte-identical before and after a rotation. Each resource
kind reconciles differently, and the kind that updates entries in place has to
notice that the plaintext behind the expression changed without being able to
see it.

# Decision

Per kind, with a secret in the item:

| kind | secret rotation |
| --- | --- |
| `settings` | works, unconditional `set` |
| `inventory` | works, unconditional `configure`; a secret in `find` turns a rotation into `routnix-no-entry-matching-find` |
| `unordered` / `ordered` | works, as a replace, like any field change |
| `keyed` | silently skipped unless something else changes |
| `effect` | not reconciled, unless the secret is part of `find` |

`unordered`, `ordered`, `settings` and `inventory` need nothing. They either
always write or derive identity from every field, and neither renderer emits a
`set`, so a changed value is a replace rather than an update for every field,
secret or not.

`effect` needs nothing secret-specific either. `create` runs only when `find`
misses, so a value change that is not part of `find` is never reconciled; that
is the kind's existing behaviour and is identical for a secret and a literal.

`keyed` gates its in-place `set` on a tag computed at eval time and stored in
`comment`:

```nix
value = substring 0 8 (builtins.hashString "md5" (renderArgs item'));
```

A secret renders to a fixed expression, so `value`, the rendered `set` body and
the whole `.rsc` are unchanged by a rotation. The comparison succeeds, nothing
is emitted, and the router keeps the old credential.

The comparison is correct and stays: it is a router-side check, and replacing
it with a static "always re-apply" decision would drop the no-op property
entirely. What is missing is an input: the expected tag has to change when the
secret does. `comment` is part of the hashed text, so the payload hash goes
there and the existing comparison does the rest.

The hash is injected per path: every item in a path that has any secret-bearing
item carries the payload hash in its `comment`, so a payload change re-`set`s
the whole path. Missing an item becomes impossible; the cost is re-`set`ting
items in that path whose own values did not change. Modules that render
secret-bearing `keyed` items use `lib.routnix.withSecretHash hash items`, which
appends the hash to each item's `comment` when any item in the list carries a
secret. No current module needs it, so it is a helper rather than behaviour
baked into the renderer.

The hash is the first 7 characters of the SHA-256 of the encrypted sops file
(`routeros.secrets.hash`). It is short because it ends up in the stored
`comment`. Hashing the ciphertext means re-encrypting the payload (a new
recipient, say) re-`set`s the path even though no secret changed; that is the
safe direction. The error direction of the whole scheme is also the safe one:
it can re-`set` an entry whose own secret did not change, but it cannot leave
one stale.

The low level also `trace`s a warning when a `keyed` item contains a secret
reference and has no `comment`, since that item stays stale unless its module
injects the payload hash. The warning is short and names the path; the policy
lives in the module, not in `keyed`.
