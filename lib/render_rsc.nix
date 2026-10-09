{lib}: let
  inherit (lib) concatStringsSep filter trim;

  inherit (import ./render_rsc/common.nix {inherit lib;}) renderValue renderArgs renderQuery;
  inherit (import ./render_rsc/ordered.nix {inherit lib;}) renderOrderedItems;
  inherit (import ./render_rsc/unordered.nix {inherit lib;}) deriveFind renderUnordered;
  inherit (import ./render_rsc/keyed.nix {inherit lib;}) renderKeyed;
  inherit (import ./render_rsc/effect.nix {inherit lib;}) renderEffect;
  inherit (import ./render_rsc/inventory.nix {inherit lib;}) renderInventory;

  # A single `set` of all declared fields.
  renderSettings = path: settings:
    if settings == {}
    then null
    else "${path}\nset ${renderArgs settings}";

  # Puts an entry's `preScript` ahead of everything the entry itself
  # renders, including the path header: the entry's own path may not
  # exist on the router yet (e.g. `/ipv6 firewall filter` while ipv6 is
  # disabled). Trimmed, since freehand text written as an indented
  # string literal carries a trailing newline.
  renderPreScript = preScript: body:
    let
      script = trim preScript;
    in
      if script == ""
      then body
      else if body == null
      then script
      else script + "\n\n" + body;

  renderEntry = path: entry: let
    # "ordered"/"unordered" derive their own identity from `items`,
    # folding in `ignore`'s fields too, since both always prune;
    # "keyed" uses the declared `key`; the rest use an explicit `find`.
    identity =
      if entry.kind == "ordered" || entry.kind == "unordered"
      then deriveFind (entry.items ++ entry.ignore)
      else if entry.kind == "keyed"
      then entry.key
      else entry.find;
    # Every kind but "settings" relies on identity to tell items apart:
    # two items with the same identity would collapse into one entry.
    queries =
      if entry.kind == "settings"
      then []
      else map identity entry.items;
    duplicate = filter (q: builtins.length (filter (q2: q2 == q) queries) > 1) queries;
    identityOption =
      if entry.kind == "keyed"
      then "key"
      else "find";

    body =
      if (entry.kind == "effect" || entry.kind == "inventory") && entry.find == null
      then throw ''routnix: `find` is required for kind = "${entry.kind}" (at ${path})''
      else if entry.kind == "keyed" && entry.key == null
      then throw ''routnix: `key` is required for kind = "keyed" (at ${path})''
      else if entry.kind == "inventory" && entry.configure == null
      then throw ''routnix: `configure` is required for kind = "inventory" (at ${path})''
      else if duplicate != []
      then throw ''routnix: `${identityOption}` doesn't uniquely identify every item in ${path} -- multiple items produce ${renderQuery (builtins.head duplicate)}''
      else if entry.kind == "settings"
      then renderSettings path entry.settings
      else if entry.kind == "ordered"
      then renderOrderedItems path identity entry.items entry.ignore
      else if entry.kind == "unordered"
      then renderUnordered path identity entry
      else if entry.kind == "keyed"
      then renderKeyed path identity entry
      else if entry.kind == "inventory"
      then renderInventory path identity entry
      else # "effect"
        renderEffect path identity entry;
  in
    renderPreScript entry.preScript body;
in {
  inherit renderValue renderArgs;

  # Renders `rosConfig` (as produced by `modules/routeros.nix`) into a
  # single `.rsc` script: `preCheck` (freehand `.rsc`, possibly empty)
  # ahead of the entries emitted in `order`.
  renderConfig = rosConfig: order: preCheck: let
    chunks =
      filter (c: c != null && c != "")
      ([ (trim preCheck) ]
        ++ map (path: renderEntry path rosConfig.${path}) order);
  in
    concatStringsSep "\n\n" chunks + "\n";
}
