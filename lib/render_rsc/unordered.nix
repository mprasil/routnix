{lib}: let
  inherit
    (lib)
    concatStringsSep
    concatMap
    genAttrs
    unique
    ;
  inherit (import ./common.nix {inherit lib;}) renderQuery;

  # Derives `find` from each item's own fields: an explicit "not set"
  # for any field some other item in the list uses but this one
  # doesn't, so the two aren't otherwise indistinguishable.
  deriveFind = items: let
    allKeys = unique (concatMap builtins.attrNames items);
  in
    item:
      genAttrs allKeys (k:
        if item ? ${k}
        then item.${k}
        else null);

  # Resolves one item's id -- creating it if `find` matches nothing (or
  # only an `ignore`d entry) -- and records it in `$managed`.
  renderManagedItem = path: find: create: item: let
    query = renderQuery (find item);
    body = ''
      {
        :local item [${path} find where ${query}]
        :if ([:len $item] > 1) do={
            :error ("routnix: find matched more than one entry in ${path}")
        }
        :if ($item = "" || [:find $ignore $item -1] >= 0) do={
            :set item [${create item}]
        }
        :set managed ($managed, $item)
      }'';
  in
    body;

  # Removes existing entries whose id is in neither `$managed` (this
  # run's resolved items) nor `$ignore`.
  renderPrune = path: ''
    :foreach i in=[${path} find] do={
      :if ([:find ($managed,$ignore) $i -1] < 0) do={ ${path} remove $i }
    }'';

  # Resolves `ignore` to ids first, resolves each item via
  # `renderManagedItem`, then sweeps unmanaged entries via `renderPrune`.
  renderUnordered = path: find: entry: let
    ignoreSetup = concatStringsSep "\n" (
      [":local ignore ({})"]
      ++ map (
        fields: ":set ignore ($ignore, [${path} find where ${renderQuery fields}])"
      )
      entry.ignore
    );
  in
    if entry.items == []
    then null
    else
      concatStringsSep "\n" (
        [path ignoreSetup ":local managed ({})"]
        ++ map (renderManagedItem path find entry.create) entry.items
        ++ [(renderPrune path)]
      );
in {
  inherit deriveFind renderUnordered;
}
