{ lib }:
let
  inherit (lib)
    concatStringsSep
    concatMap
    mapAttrsToList
    genAttrs
    unique
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

  # Renders an attrset of RouterOS fields as a `where`-clause query, e.g.
  # for use after `find`/`print ... where`. Like `renderArgs`, but a
  # `null` value -- used by `deriveFind` below for a field a particular
  # item doesn't set -- renders as `!k`, RouterOS's syntax for "this field
  # isn't set", instead of `k=v`.
  renderQuery =
    fields:
    concatStringsSep " " (
      mapAttrsToList (k: v: if v == null then "!${k}" else "${k}=${renderValue v}") fields
    );

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
      idExpr = i: "[${path} find where ${renderQuery (find i)}]";

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
      query = renderQuery (find item);
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

  # kind = "unordered" with `prune = true`: like `renderGuardedItem`, but
  # also resolves this item's id and records it in `$managed`, so the
  # prune sweep below can tell managed entries apart from foreign ones by
  # id, rather than re-testing every existing entry against every current
  # item's `find`. `$ignore` (built once per path, before any item is
  # processed -- see `renderUnordered`) is also treated as a non-match
  # here: a `find` match that's actually an `ignore`d entry doesn't count
  # as this item already being present, so declaring an item never
  # silently "adopts" an entry the caller asked to leave alone -- a new
  # one is `add`-ed instead. `create`'s result is captured directly as
  # the new id -- a query that matched nothing (or only an ignored entry)
  # before creating one new entry can't possibly match more than one now,
  # so there's nothing to re-check after creating, only before.
  renderManagedItem =
    path: find: create: item:
    let
      query = renderQuery (find item);
      body = concatStringsSep "\n" [
        ":local item [${path} find where ${query}]"
        ''
          :if ([:len $item] > 1) do={
            :error ("routnix: find matched more than one entry in ${path}")
          }''
        ''
          :if ($item = "" || [:find $ignore $item -1] >= 0) do={
            :set item [${create item}]
          }''
        ":set managed ($managed, $item)"
      ];
    in
    ''
      {
      ${indent body}
      }'';

  # kind = "unordered" with `prune = true`: removes existing entries whose
  # id is in neither `$managed` (this run's resolved items, built by
  # `renderManagedItem` above) nor `$ignore` (ids matching an `ignore`
  # predicate, built by `renderUnordered` before any item is processed).
  renderPrune =
    path:
    ''
      :foreach i in=[${path} find] do={
        :if ([:find ($managed,$ignore) $i -1] < 0) do={ ${path} remove $i }
      }'';

  # kind = "unordered": derives `find` from `items` themselves (no
  # explicit `find` for this kind, no escape hatch yet) -- an item's
  # identity is its own declared fields, plus an explicit "not set" for
  # any field some other item in the same list uses but this one doesn't,
  # so e.g. one item having a `comment` and another not doesn't make them
  # indistinguishable from each other.
  deriveFind =
    items:
    let
      allKeys = unique (concatMap builtins.attrNames items);
    in
    item: genAttrs allKeys (k: if item ? ${k} then item.${k} else null);

  # kind = "unordered": without `prune`, a plain add-guard per item (see
  # `renderGuardedItem`). With `prune`, `$ignore` is resolved to ids
  # first (so item creation can see it -- see `renderManagedItem`), then
  # each item is resolved via `renderManagedItem`, recording its id in
  # `$managed`, then `renderPrune` removes existing entries that are
  # neither `$managed` nor in `$ignore`.
  renderUnordered =
    path: find: entry:
    let
      ignoreSetup = concatStringsSep "\n" (
        [ ":local ignore ({})" ]
        ++ map (
          fields: ":set ignore ($ignore, [${path} find where ${renderQuery fields}])"
        ) entry.ignore
      );
      addChunk =
        if entry.prune then
          concatStringsSep "\n" (
            [
              ignoreSetup
              ":local managed ({})"
            ]
            ++ map (renderManagedItem path find entry.create) entry.items
          )
        else if entry.items == [ ] then
          null
        else
          concatStringsSep "\n" (map (renderGuardedItem path find entry.create) entry.items);
      pruneChunk = if entry.prune then renderPrune path else null;
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
    let
      # "ordered"/"effect" require an explicit `find`; "unordered" has no
      # escape hatch yet and always derives its own from `items` instead.
      find = if entry.kind == "unordered" then deriveFind entry.items else entry.find;
      # All three rely on `find` to tell items apart: two items whose
      # `find` produces the same query would silently collapse into a
      # single RouterOS entry instead of two.
      queries = if entry.kind == "settings" then [ ] else map find entry.items;
      duplicate = filter (q: builtins.length (filter (q2: q2 == q) queries) > 1) queries;
    in
    if entry.prune && entry.kind != "unordered" then
      throw ''routnix: `prune = true` is only valid for kind = "unordered" (at ${path})''
    else if (entry.kind == "ordered" || entry.kind == "effect") && entry.find == null then
      throw ''routnix: `find` is required for kind = "${entry.kind}" (at ${path})''
    else if duplicate != [ ] then
      throw ''routnix: `find` doesn't uniquely identify every item in ${path} -- multiple items produce ${renderQuery (builtins.head duplicate)}''
    else if entry.kind == "settings" then
      renderSettings path entry.settings
    else if entry.kind == "ordered" then
      renderOrderedItems path find entry.items
    else if entry.kind == "unordered" then
      renderUnordered path find entry
    else # "effect"
      renderGuardedItems path find entry.create entry.items;
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
