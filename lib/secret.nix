{lib}: let
  inherit (lib) types;

  # Name of the file on the router holding the secret payload.
  payloadFileName = "routnix-secrets";

  marker = "__routnixSecret";

  isSecret = v:
    builtins.isAttrs v
    && v ? ${marker}
    && builtins.isString v.${marker};

  secretName = v: v.${marker};

  # A secret reference value, as exposed by `routeros.secrets.entries.<name>.reference`.
  reference = name: {${marker} = name;};

  # Escapes a value into RouterOS double-quoted string syntax.
  escapeString = builtins.replaceStrings
    ["\\" "\"" "$" "?" "\n" "\r" "\t"]
    ["\\\\" "\\\"" "\\$" "\\?" "\\n" "\\r" "\\t"];

  # The RouterOS expression that reads a secret from the loaded payload.
  readExpression = name: "($secrets->\"${escapeString name}\")";

  referenceType = types.addCheck (types.attrsOf types.str) isSecret;

  # Appends the payload hash to every item's `comment` when any item in
  # the list carries a secret, so a changed payload moves a `keyed`
  # item's tag.
  withSecretHash = hash: items: let
    hasSecret = item: lib.any isSecret (builtins.attrValues item);
  in
    if hash == "" || !(lib.any hasSecret items)
    then items
    else
      map (item: item
        // {
          comment =
            if (item.comment or "") == ""
            then hash
            else "${item.comment} ${hash}";
        })
      items;
in {
  inherit
    payloadFileName
    isSecret
    secretName
    reference
    escapeString
    readExpression
    referenceType
    withSecretHash
    ;
}
