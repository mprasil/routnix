{lib}: let
  inherit (lib) concatStringsSep filter;

  inherit (import ./render_rsc/common.nix {inherit lib;}) renderValue renderArgs renderQuery;
  inherit (import ./render_rsc/ordered.nix {inherit lib;}) renderOrderedItems;
  inherit (import ./render_rsc/unordered.nix {inherit lib;}) deriveFind renderUnordered;
  inherit (import ./render_rsc/effect.nix {inherit lib;}) renderEffect;

  # A single `set` of all declared fields.
  renderSettings = path: settings:
    if settings == {}
    then null
    else "${path}\nset ${renderArgs settings}";

  renderEntry = path: entry: let
    # "effect" requires an explicit `find`; "ordered"/"unordered"
    # always derive their own from `items` instead, folding in
    # `ignore`'s fields too, since both kinds always prune.
    find =
      if entry.kind == "ordered" || entry.kind == "unordered"
      then deriveFind (entry.items ++ entry.ignore)
      else entry.find;
    # All three rely on `find` to tell items apart: two items whose
    # `find` produces the same query would collapse into one entry.
    queries =
      if entry.kind == "settings"
      then []
      else map find entry.items;
    duplicate = filter (q: builtins.length (filter (q2: q2 == q) queries) > 1) queries;
  in
    if entry.kind == "effect" && entry.find == null
    then throw ''routnix: `find` is required for kind = "effect" (at ${path})''
    else if duplicate != []
    then throw ''routnix: `find` doesn't uniquely identify every item in ${path} -- multiple items produce ${renderQuery (builtins.head duplicate)}''
    else if entry.kind == "settings"
    then renderSettings path entry.settings
    else if entry.kind == "ordered"
    then renderOrderedItems path find entry.items entry.ignore
    else if entry.kind == "unordered"
    then renderUnordered path find entry
    else # "effect"
      renderEffect path find entry;
in {
  inherit renderValue renderArgs;

  # Renders `rosConfig` (as produced by `modules/routeros.nix`) into a
  # single `.rsc` script, with entries emitted in `order`.
  renderConfig = rosConfig: order: let
    chunks = filter (c: c != null) (map (path: renderEntry path rosConfig.${path}) order);
  in
    concatStringsSep "\n\n" chunks + "\n";
}
