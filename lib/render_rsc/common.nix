{lib}: let
  inherit
    (lib)
    concatStringsSep
    mapAttrsToList
    splitString
    removeSuffix
    ;

  # Renders a single RouterOS scalar value into its `.rsc` textual form.
  renderValue = v:
    if builtins.isBool v
    then
      (
        if v
        then "yes"
        else "no"
      )
    else ''"${toString v}"'';

  # Renders an attrset of RouterOS fields into `k=v k=v ...` form.
  renderArgs = args: concatStringsSep " " (mapAttrsToList (k: v: "${k}=${renderValue v}") args);

  # Like `renderArgs`, but for a `where`-clause query: a `null` value
  # renders as `!k` (RouterOS's "this field isn't set") instead of `k=v`.
  renderQuery = fields:
    concatStringsSep " " (
      mapAttrsToList (k: v:
        if v == null
        then "!${k}"
        else "${k}=${renderValue v}")
      fields
    );

  # Indents every line of `text` by two spaces, for embedding inside a
  # `:if (...) do={ }` block.
  indent = text: concatStringsSep "\n" (map (l: "  " + l) (splitString "\n" (removeSuffix "\n" text)));
in {
  inherit
    renderValue
    renderArgs
    renderQuery
    indent
    ;
}
