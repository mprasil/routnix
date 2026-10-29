# Builds the executable that decrypts a router's secret payload and uploads
# it as `routnix-secrets` (see dr/secret-deploy.md). Returns null when the
# router declares no secrets.
{pkgs}: {
  secrets,
  sops ? pkgs.sops,
  curl ? pkgs.curl,
  curlOptions ? [],
}: let
  inherit (pkgs) lib;

  inherit (import ./secret.nix {lib = lib;}) escapeString;

  # sops takes a JSON path, so `mail/password` becomes
  # `["mail"]["password"]`.
  sopsPath = key:
    lib.concatMapStrings (part: "[" + builtins.toJSON part + "]") (lib.splitString "/" key);

  emitCalls =
    lib.concatMapStringsSep "\n"
    (name: "  emit_secret ${lib.escapeShellArg (escapeString name)} ${lib.escapeShellArg (sopsPath secrets.entries.${name}.key)}")
    (lib.attrNames secrets.entries);

  # A separate derivation output so the ciphertext is an input of the
  # uploader derivation, not just a path embedded in its text.
  secretFile = pkgs.runCommand "routnix-secrets.enc" {} ''
    cp ${secrets.file} $out
  '';
in
  if secrets == null || secrets.file == null || secrets.entries == {}
  then null
  else
    pkgs.writeShellApplication {
      name = "routnix-upload-secrets";
      runtimeInputs = [sops curl pkgs.jq pkgs.gnused secretFile];
      text = ''
        if [ "$#" -ne 1 ]; then
          echo "usage: routnix-upload-secrets <user@host>[:port]" >&2
          exit 2
        fi

        target=$1
        secret_file=${lib.escapeShellArg (toString secretFile)}

        emit_secret() {
          local name=$1
          local key=$2
          local json body
          json=$(sops --decrypt --extract "$key" --input-type yaml --output-type binary "$secret_file" | jq -Rs .)
          body=''${json:1:''${#json}-2}
          body=$(printf '%s' "$body" | sed -e 's/\$/\\$/g' -e 's/?/\\?/g')
          printf '"%s"="%s";' "$name" "$body"
        }

        {
          printf ':return {'
        ${emitCalls}
          printf '}'
        } | curl -sSf ${lib.escapeShellArgs curlOptions} -T - "sftp://$target/routnix-secrets"
      '';
    }
