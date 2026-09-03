{ lib }:
let
  inherit (lib)
    concatStringsSep
    mapAttrsToList
    filter
    splitString
    removeSuffix
    imap0
    drop
    ;

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

  # kind = "ordered": reconciles items against existing entries by
  # identity (`find`) and relative order, using `add`/`add place-before=`
  # for items that aren't there yet and `move` for ones that are but are
  # out of order -- so reapplying neither duplicates entries nor disturbs
  # ones already correctly placed. Only order *relative to other declared
  # items* is enforced: entries `find` doesn't match (foreign or
  # unmanaged ones) can sit interleaved among them untouched.
  #
  # For each item, in a fresh scope (so `dest`/`id`/`ok` don't collide
  # across items):
  #   - resolves `dest` to the id of the nearest declared item *after*
  #     this one that already exists (trying each in declared order,
  #     first non-empty wins), or "" if none do (i.e. anchor to the end);
  #   - looks up this item's own id via `find`;
  #   - if missing, `add`s it (anchored to `dest` via `place-before` if
  #     resolved);
  #   - if present, checks whether it already comes after `$anchor` (the
  #     previous item) in the path's current order, `move`-ing it to
  #     `dest` only if it doesn't;
  #   - carries its own id forward as `$anchor` for the next item.
  renderOrderedItem =
    path: find: item: laterItems:
    let
      idExpr = i: "[${path} find where ${renderArgs (find i)}]";

      destLines = [ ":local dest \"\"" ] ++ map (l: ":if ($dest = \"\") do={ :set dest ${idExpr l} }") laterItems;

      addBlock = ''
        :if ($dest = "") do={
        ${indent "add ${renderArgs item}"}
        } else={
        ${indent "add place-before=$dest ${renderArgs item}"}
        }'';

      addBranch = addBlock + "\n:set id ${idExpr item}";

      moveLine = ":if ($dest = \"\") do={ move $id } else={ move $id destination=$dest }";

      foreachBody = ''
        :if ($j = $anchor) do={ :set ok true }
        :if ($j = $id) do={ :if (!$ok) do={
        ${indent moveLine}
        } }'';

      foreachBlock = ''
        :local ok false
        :foreach j in=[${path} find] do={
        ${indent foreachBody}
        }'';

      moveBranch = ''
        :if ($anchor != "") do={
        ${indent foreachBlock}
        }'';

      idCheck = ''
        :if ($id = "") do={
        ${indent addBranch}
        } else={
        ${indent moveBranch}
        }'';

      body = concatStringsSep "\n" (destLines ++ [
        ":local id ${idExpr item}"
        idCheck
        ":set anchor $id"
      ]);
    in
    ''
      {
      ${indent body}
      }'';

  renderOrderedItems =
    path: find: items:
    if items == [ ] then
      null
    else
      let
        blocks = imap0 (i: item: renderOrderedItem path find item (drop (i + 1) items)) items;
      in
      concatStringsSep "\n" ([ path ":local anchor \"\"" ] ++ blocks);

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
      renderOrderedItems path entry.find entry.items
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
