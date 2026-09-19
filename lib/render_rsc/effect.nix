{lib}: let
  inherit (lib) concatStringsSep;
  inherit (import ./common.nix {inherit lib;}) renderQuery indent;

  # Resolves one item's id -- running `create`'s (arbitrary) commands if
  # `find` matches nothing (or only an `ignore`d entry), then re-`find`ing
  # to capture the id those commands left behind, since unlike a plain
  # `add`, `create`'s text can't be relied on to evaluate to that id
  # itself -- and records it in `$managed`.
  renderManagedItem = path: find: create: item: let
    query = renderQuery (find item);
  in ''
    {
      :local item [${path} find where ${query}]
      :if ([:len $item] > 1) do={
        :error ("routnix: find matched more than one entry in ${path}")
      }
      :if ($item = "" || [:find $ignore $item -1] >= 0) do={
      ${indent (create item)}
        :set item [${path} find where ${query}]
        :if ($item = "") do={
          :error ("routnix: create for ${path} didn't produce an entry matching find")
        }
        :if ([:len $item] > 1) do={
          :error ("routnix: find matched more than one entry in ${path}")
        }
      }
      :set managed ($managed, $item)
    }'';

  # Removes existing entries whose id is in neither `$managed` (this
  # run's resolved items) nor `$ignore`.
  renderPrune = path: ''
    :foreach i in=[${path} find] do={
      :if ([:find ($managed,$ignore) $i -1] < 0) do={ ${path} remove $i }
    }'';

  # Resolves `ignore` to ids first, resolves each item via
  # `renderManagedItem`, then sweeps unmanaged entries via `renderPrune`.
  # Pruning is mandatory regardless of how many items are declared, so
  # an empty `items` list still emits the `ignore`-resolution and prune
  # sweep, just without any per-item resolve step.
  renderEffect = path: find: entry: let
    ignoreSetup = concatStringsSep "\n" (
      [":local ignore ({})"]
      ++ map (
        fields: ":set ignore ($ignore, [${path} find where ${renderQuery fields}])"
      )
      entry.ignore
    );
  in
    concatStringsSep "\n" (
      [path ignoreSetup ":local managed ({})"]
      ++ map (renderManagedItem path find entry.create) entry.items
      ++ [(renderPrune path)]
    );
in {
  inherit renderEffect;
}
