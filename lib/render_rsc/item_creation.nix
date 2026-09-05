{ lib }:
let
  inherit (lib) concatStringsSep;
  inherit (import ./common.nix { inherit lib; }) renderQuery indent;

  # Guards `create item`'s text behind a check that `find item` matches
  # no existing entry yet, so it only runs once.
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
in
{
  inherit renderGuardedItem renderGuardedItems;
}
