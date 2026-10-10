{lib}: let
  inherit (lib) concatStringsSep substring;
  inherit (import ./common.nix {inherit lib;}) renderArgs renderQuery;

  # The `comment` tag written into every entry routnix creates here:
  # `shape` hashes the item's sorted field names, `value` hashes its
  # rendered field values (the user comment text included, the tag
  # itself excluded). Comparing an entry's stored tag against this
  # recomputed one decides whether it's already in sync.
  tagFor = item': let
    shape = substring 0 8 (builtins.hashString "md5" (concatStringsSep "," (builtins.attrNames item')));
    value = substring 0 8 (builtins.hashString "md5" (renderArgs item'));
  in {
    inherit shape value;
    tag = "routnix:${shape}:${value}";
  };

  # Locates one item's entry by `key` and reconciles it: `add` when
  # absent, left alone when the stored tag already matches, `set` when
  # only values drifted, and remove-and-re-add when the field set
  # changed or the entry is foreign/untagged. Records the resolved id
  # in `$managed`.
  renderItem = path: key: item: let
    item' = item // {comment = item.comment or "";};
    inherit (tagFor item') shape value tag;
    tagText = tag + (if item'.comment == "" then "" else " " + item'.comment);
    rendered = renderArgs (item' // {comment = tagText;});
    query = renderQuery (key item);
  in ''
    {
      :local match [${path} find where ${query}]
      :if ([:len $match] > 1) do={
        :put "routnix: key matched more than one entry in ${path}"
        :error "routnix-key-matched-multiple-entries"
      }
      :if ([:len $match] = 1 && [:find $ignore ($match->0) -1] >= 0) do={
        :put "routnix: ${path}: declared key is occupied by an ignored entry"
        :error "routnix-key-occupied-by-ignored-entry"
      }
      :if ([:len $match] = 0) do={
        :set managed ($managed, [add ${rendered}])
      } else={
        :local item ($match->0)
        :local cur [get $item comment]
        :if ($cur ~ "^routnix:${shape}:${value}") do={
          :set managed ($managed, $match)
        } else={
          :if ($cur ~ "^routnix:${shape}:") do={
            set $item ${rendered}
            :set managed ($managed, $match)
          } else={
            remove $item
            :set managed ($managed, [add ${rendered}])
          }
        }
      }
    }'';

  # Removes existing entries whose id is in neither `$managed` (this
  # run's resolved items) nor `$ignore`.
  renderPrune = path: ''
    :foreach i in=[${path} find] do={
      :if ([:find ($managed,$ignore) $i -1] < 0) do={ ${path} remove $i }
    }'';

  # Resolves `ignore` to ids first, reconciles each item via
  # `renderItem`, then sweeps unmanaged entries via `renderPrune`.
  # Pruning is mandatory regardless of how many items are declared, so
  # an empty `items` list still emits the `ignore`-resolution and prune
  # sweep, just without any per-item resolve step.
  renderKeyed = path: key: entry: let
    ignoreSetup = concatStringsSep "\n" (
      [":local ignore ({})"]
      ++ map (
        fields: ":set ignore ($ignore, [${path} find where ${renderQuery fields}])"
      ) entry.ignore
    );
  in
    concatStringsSep "\n" (
      [path ignoreSetup ":local managed ({})"]
      ++ map (renderItem path key) entry.items
      ++ [(renderPrune path)]
    );
in {
  inherit renderKeyed;
}
