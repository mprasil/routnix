{ lib }:
let
  inherit (lib) concatStringsSep mapAttrsToList filter;

  # Renders a single RouterOS scalar value into its `.rsc` textual form.
  renderValue =
    v:
    if builtins.isBool v then
      (if v then "yes" else "no")
    else if builtins.isInt v then
      toString v
    else
      ''"${v}"'';

  renderItem =
    item: "add " + concatStringsSep " " (mapAttrsToList (k: v: "${k}=${renderValue v}") item);

  renderEntry =
    path: entry:
    if entry.items == [ ] then
      null
    else
      concatStringsSep "\n" ([ path ] ++ map renderItem entry.items);
in
{
  # Renders `rosConfig` (as produced by `modules/rosConfig.nix`) into a
  # single `.rsc` script, with entries emitted in `order`.
  renderConfig =
    rosConfig: order:
    let
      chunks = filter (c: c != null) (map (path: renderEntry path rosConfig.${path}) order);
    in
    concatStringsSep "\n\n" chunks + "\n";
}
