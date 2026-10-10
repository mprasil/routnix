{lib}: let
  inherit (lib) concatStringsSep imap0;
  inherit (import ./common.nix {inherit lib;}) renderQuery renderArgs indent;

  # Resolves `ignore` field predicates to ids once, before any item is
  # processed.
  renderIgnoreSetup = ignore:
    concatStringsSep "\n" (
      [":local ignore ({})"]
      ++ map (fields: ":set ignore ($ignore, [find where ${renderQuery fields}])") ignore
    );

  # The statement(s) that create declared item `i` and capture its id as
  # `$item`: the first declared item is placed at the front of the table
  # (or added plainly if the table is empty so there's nothing to place
  # it before); every other item is placed right after the previous
  # declared item's already-resolved id, via that item's `.nextid`.
  addStatement = i: item:
    if i == 0
    then ''
      :if ([print count-only] > 0) do={
        :set item [add place-before=([find]->0) ${renderArgs item}]
      } else={
        :set item [add ${renderArgs item}]
      }''
    else ''
      :set item [add place-before=([get ($managed->${toString (i - 1)})]->".nextid") ${renderArgs item}]'';

  # Resolves one item's id -- creating it via `addStatement` if `find`
  # matches nothing (or only an `ignore`d entry) -- and records it in
  # `$managed`.
  renderResolveItem = path: find: i: item: let
    query = renderQuery (find item);
    body = ''
      {
        :local item [find where ${query}]
        :if ([:len $item] > 1) do={
          :put "routnix: find matched more than one entry in ${path}"
          :error "routnix-find-matched-multiple-entries"
        }
        :if ($item = "" || [:find $ignore $item -1] >= 0) do={
        ${indent (addStatement i item)}
        }
        :set managed ($managed, $item)
      }
    '';
  in
    body;

  # Fixes up declared order among the resolved ids in `$managed`: forces
  # the first declared item to be the table's first entry, then walks
  # the rest with a running `$prev`, moving anything not already
  # immediately following its predecessor.
  renderReorderPass = ''
    {
      :local first ($managed->0)
      :local firstExisting ([find]->0)
      :if ($first != $firstExisting) do={
        move $first destination=$firstExisting
      }
      :if ([:len $managed] > 1) do={
        :local prev $first
        :for i from=1 to=([:len $managed] - 1) do={
          :local cur ($managed->$i)
          :local dest ([get $prev]->".nextid")
          :if ($cur != $dest) do={
            move $cur destination=$dest
          }
          :set prev $cur
        }
      }
    }'';

  # Removes existing entries whose id is in neither `$managed` (this
  # run's resolved items) nor `$ignore`.
  renderPrune = ''
    :foreach i in=[find] do={
      :if ([:find ($managed,$ignore) $i -1] < 0) do={ remove $i }
    }'';
in {
  # Renders a whole `kind = "ordered"` path: resolves each declared item
  # in turn (adding missing ones already placed as close to their
  # correct position as possible), fixes up any remaining order drift in
  # a final pass, then always prunes anything left over that isn't
  # declared or `ignore`d. An empty `items` list still emits the
  # `ignore`-resolution and prune sweep -- pruning is mandatory
  # regardless of how many items are declared -- just without the
  # per-item resolve/reorder steps, which have nothing to do.
  renderOrderedItems = path: find: items: ignore:
    if items == []
    then
      concatStringsSep "\n" [
        path
        (renderIgnoreSetup ignore)
        ":local managed ({})"
        renderPrune
      ]
    else
      concatStringsSep "\n" (
        [
          path
          (renderIgnoreSetup ignore)
          ":local managed ({})"
        ]
        ++ imap0 (i: item: renderResolveItem path find i item) items
        ++ [
          renderReorderPass
          renderPrune
        ]
      );
}
