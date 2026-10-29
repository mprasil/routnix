# Context

The secret payload described in
[`secret-management.md`](./secret-management.md) has to get from the encrypted,
committed sops document onto the router without plaintext ever touching disk,
argv, or the environment. There are two deploy paths, not one: `apply` for a
real router and the VM runner.

# Decision

The deploy step decrypts on the deploy host, builds the RouterOS literal, and
uploads it as `routnix-secrets` with curl over SFTP. `scp` cannot read stdin;
curl can, and `pkgs.curl` is built with libssh2, so this works:

```sh
sops --decrypt --extract '["mail"]["password"]' --output-type binary ./secrets.yaml \
  | jq -Rs . \
  | sed -e 's/\$/\\$/g' -e 's/?/\\?/g' \
  | curl -sSf -T - 'sftp://admin@router/routnix-secrets'
```

The literal is built with one `sops --decrypt --extract` per declared secret,
by its `key`, rather than decrypting the document once and walking it. That
touches only declared secrets, mirrors `key`, and avoids shipping a JSON walk.

Escaping is what makes the payload safe to `:parse`, so each value is rendered
as a RouterOS string: `jq -Rs` handles `\`, `"`, newlines, `\r` and `\t`, and
the `sed` pass adds the `$` and `?` escapes. Names are escaped the same way at
build time. Every value stays out of argv, out of environment variables and off
disk: it moves from `sops` through pipes and shell variables only. There is no
`set -x` and no `curl -v`.

Nothing is uploaded when no secrets are declared. The payload is one file, so
there is no per-secret file name to derive, no collision to resolve, and no
cleanup when a declaration is removed. A second `/import` reuses the payload
that is already on the router.

The upload is one shared shell snippet used by both `mkDeviceConfig.apply` and
the VM runner, which would otherwise duplicate the transport together with
their existing `scp` + `/import` steps. It is a self-contained executable built
from the router's evaluated `secrets` (`file` and `entries`), given the target
as its only argument. `mkDeviceConfig` gains `sops ? pkgs.sops`, `curl ?
pkgs.curl` and `curlOptions ? []` for it; `curlOptions` is escaped with
`lib.escapeShellArgs`, like `sshOptions`/`scpOptions`, rather than being a
`ROUTNIX_CURL_OPTS` environment variable, so options containing spaces
survive.

`apply` keeps its default flow but uploads the payload between the `.rsc` copy
and the import whenever secrets are declared. Two copy modes stop after the
copy:

- `--copy-only` copies the `.rsc` and nothing else. It never uploads secrets,
  so a plain copy cannot put plaintext on a router by accident.
- `--copy-with-secrets` copies the `.rsc` and uploads the payload, without
  importing, so the payload can be staged separately.

The VM runner uploads the payload too, using the same snippet: if the router's
config declares secrets, it is fair to expect the deploy credentials on the
machine running the VM. Its transport options are the VM's own (`-k`, since the
fresh VM's host key is unknown) rather than the user's `curlOptions`.

The decryption key is ambient, like ssh auth: `sops` reads
`SOPS_AGE_KEY`/`SOPS_AGE_KEY_FILE` from the environment. There is no routnix
option for it, so nothing key-shaped can end up in the store or in a flake.

`/file` is one flat namespace shared with user files, so the payload name is
prefixed. Files persist across reboots and are carried into `/system backup`
and `/export`, and `/file` has no `sensitive` attribute, so the payload is
readable by anyone who can read files on the router. routnix assumes deployment
as an account with full rights and does not model per-policy behaviour.
