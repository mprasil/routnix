{lib}: let
  inherit (lib) concatStringsSep;
  inherit (import ./common.nix {inherit lib;}) renderQuery indent;

  # Locates one item's existing entry -- erroring unless `find` matches
  # exactly one -- and runs `configure`'s commands against it.
  renderItem = path: find: configure: item: let
    query = renderQuery (find item);
  in ''
    {
      :local item [${path} find where ${query}]
      :if ($item = "") do={
        :error ("routnix: no entry matching find in ${path}")
      }
      :if ([:len $item] > 1) do={
        :error ("routnix: find matched more than one entry in ${path}")
      }
    ${indent (configure item)}
    }'';

  # Renders a whole `kind = "inventory"` path. Nothing is ever added or
  # removed, so an empty `items` list renders nothing at all.
  renderInventory = path: find: entry:
    if entry.items == []
    then null
    else concatStringsSep "\n" ([path] ++ map (renderItem path find entry.configure) entry.items);
in {
  inherit renderInventory;
}