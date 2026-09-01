{ lib }:
{
  # Topologically sorts `rosConfig` entries by their `before`/`after`
  # declarations, returning an ordered list of paths.
  #
  # `rosConfig` is expected to be an attrset of the shape produced by
  # `modules/rosConfig.nix`'s `options.rosConfig`, i.e.
  # `{ "<path>" = { before = [...]; after = [...]; ... }; }`.
  sortEntries =
    rosConfig:
    let
      paths = builtins.attrNames rosConfig;

      # `precedes a b == true` means `a` must be rendered before `b` --
      # either because `a` declares `b` in its `before` list, or `b`
      # declares `a` in its `after` list. This matches the semantics
      # `lib.toposort` expects of its comparator.
      precedes =
        a: b:
        builtins.elem b rosConfig.${a}.before || builtins.elem a rosConfig.${b}.after;

      sorted = lib.toposort precedes paths;
    in
    if sorted ? result then
      sorted.result
    else
      throw ''
        routnix: dependency cycle detected among rosConfig entries.
          cycle: ${lib.concatStringsSep " -> " sorted.cycle}
          loops back to: ${lib.concatStringsSep ", " sorted.loops}
      '';
}
