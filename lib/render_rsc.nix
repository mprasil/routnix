{ lib }:
let
  inherit (lib) concatStringsSep mapAttrsToList filter splitString removeSuffix;

  # Renders a single RouterOS scalar value into its `.rsc` textual form.
  renderValue =
    v:
    if builtins.isBool v then
      (if v then "yes" else "no")
    else if builtins.isInt v then
      toString v
    else
      ''"${v}"'';

  # Renders an attrset of RouterOS fields into `k=v k=v ...` form, e.g. for
  # use after `add`/`set`, or inside a `print count-only where ...` query.
  renderArgs = args: concatStringsSep " " (mapAttrsToList (k: v: "${k}=${renderValue v}") args);

  # Indents every line of `text` by two spaces, for embedding inside a
  # `:if (...) do={ }` block.
  indent =
    text: concatStringsSep "\n" (map (l: "  " + l) (splitString "\n" (removeSuffix "\n" text)));

  # kind = "ordered": one `add` per item, in declared order.
  renderPlainItems =
    path: items:
    if items == [ ] then
      null
    else
      concatStringsSep "\n" ([ path ] ++ map (item: "add " + renderArgs item) items);

  # kind = "unordered" | "effect": one guard block per item -- `create`'s
  # text only runs if `find`'s query matches no existing entry.
  renderGuardedItem =
    path: find: create: item:
    let
      query = renderArgs (find item);
      body = create item;
    in
    ''
      :if ([${path} print count-only where ${query}] = 0) do={
      ${indent body}
      }'';

  renderGuardedItems =
    path: find: create: items:
    if items == [ ] then
      null
    else
      concatStringsSep "\n" ([ path ] ++ map (renderGuardedItem path find create) items);

  # Renders `fields` as a RouterOS boolean expression testing `$i`'s
  # values at `path`, e.g. `[<path> get $i address]="1.2.3.0/24" and ...`.
  renderFieldMatch =
    path: fields:
    concatStringsSep " and " (
      mapAttrsToList (k: v: "[${path} get $i ${k}]=${renderValue v}") fields
    );

  # kind = "unordered" with `prune = true`: removes existing entries that
  # neither match an `ignore` predicate nor `find` for any current item.
  renderPrune =
    path: find: ignore: items:
    let
      check = setVar: fields: ":if (${renderFieldMatch path fields}) do={ :set ${setVar} true }";
      body = concatStringsSep "\n" (
        [ ":local ignored false" ]
        ++ map (check "ignored") ignore
        ++ [ ":local keep false" ]
        ++ map (item: check "keep" (find item)) items
        ++ [ ":if (!$ignored and !$keep) do={ ${path} remove $i }" ]
      );
    in
    ''
      :foreach i in=[${path} find] do={
      ${indent body}
      }'';

  # kind = "unordered": add-guard per item, then (if `prune`) remove
  # existing entries `find` doesn't match for any current item and that
  # `ignore` doesn't cover.
  renderUnordered =
    path: entry:
    let
      addChunk =
        if entry.items == [ ] then
          null
        else
          concatStringsSep "\n" (map (renderGuardedItem path entry.find entry.create) entry.items);
      pruneChunk = if entry.prune then renderPrune path entry.find entry.ignore entry.items else null;
      body = filter (c: c != null) [
        addChunk
        pruneChunk
      ];
    in
    if body == [ ] then null else concatStringsSep "\n" ([ path ] ++ body);

  # kind = "settings": a single `set` of all declared fields.
  renderSettings =
    path: settings:
    if settings == { } then
      null
    else
      "${path}\nset ${renderArgs settings}";

  renderEntry =
    path: entry:
    if entry.prune && entry.kind != "unordered" then
      throw ''routnix: `prune = true` is only valid for kind = "unordered" (at ${path})''
    else if entry.kind == "settings" then
      renderSettings path entry.settings
    else if entry.kind == "ordered" then
      renderPlainItems path entry.items
    else if entry.kind == "unordered" then
      renderUnordered path entry
    else # "effect"
      renderGuardedItems path entry.find entry.create entry.items;
in
{
  inherit renderValue renderArgs;

  # Renders `rosConfig` (as produced by `modules/routeros.nix`) into a
  # single `.rsc` script, with entries emitted in `order`.
  renderConfig =
    rosConfig: order:
    let
      chunks = filter (c: c != null) (map (path: renderEntry path rosConfig.${path}) order);
    in
    concatStringsSep "\n\n" chunks + "\n";
}
