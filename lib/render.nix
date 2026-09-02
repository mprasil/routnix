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

  # kind = "ordered": a plain, unconditional `add` per item, in declared
  # order. No identity check -- reapplying currently duplicates entries;
  # positional reconciliation (`place-before`/`move`) is not implemented
  # yet.
  renderPlainItems =
    path: items:
    if items == [ ] then
      null
    else
      concatStringsSep "\n" ([ path ] ++ map (item: "add " + renderArgs item) items);

  # kind = "unordered" | "effect": one `find`-guarded block per item --
  # `create`'s text only runs if `find`'s query doesn't already match an
  # existing entry. Uses `print count-only where ...` (a plain number)
  # rather than `find where ...` (an id-or-empty-string) to check
  # existence -- less brittle, since it sidesteps how `find` behaves when
  # a query matches more than one entry.
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

  # kind = "settings": a single `set` of all declared fields. Inherently
  # idempotent, no identity/ordering needed.
  renderSettings =
    path: settings:
    if settings == { } then
      null
    else
      "${path}\nset ${renderArgs settings}";

  renderEntry =
    path: entry:
    if entry.kind == "settings" then
      renderSettings path entry.settings
    else if entry.kind == "ordered" then
      renderPlainItems path entry.items
    else # "unordered" | "effect"
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
