{
  lib,
  config,
  ...
}: let
  inherit (lib) mkOption mkIf types;
  inherit (lib) concatMap concatStringsSep filter mapAttrs;

  cfg = config.firewall.filter;

  # RouterOS field value: bool, int, or string.
  itemValueType = types.oneOf [
    types.bool
    types.int
    types.str
  ];

  blockSubmodule = {...}: {
    options = {
      chain = mkOption {
        type = types.str;
        description = ''
          The chain every rule in this block is added to
          (e.g. `"input"`, `"forward"`).
        '';
      };

      rules = mkOption {
        type = types.listOf (types.attrsOf itemValueType);
        default = [];
        description = ''
          Rules to add, kept in declared order relative to each other.
          Fields are passed through as-is; `chain` comes from the block.
        '';
      };

      before = mkOption {
        type = types.listOf types.str;
        default = [];
        description = ''
          Names of other `firewall.filter.rules` blocks whose rules must
          come after this block's.
        '';
      };

      after = mkOption {
        type = types.listOf types.str;
        default = [];
        description = ''
          Names of other `firewall.filter.rules` blocks whose rules must
          come before this block's.
        '';
      };
    };
  };

  blockNames = builtins.attrNames cfg.rules;

  referencedNames =
    concatMap (block: block.before ++ block.after)
    (builtins.attrValues cfg.rules);

  unknownNames = filter (name: !(builtins.elem name blockNames)) referencedNames;

  # Blocks are ordered among themselves by `before`/`after` (block
  # names), the same way `routeros.config` paths are ordered by
  # `before`/`after` (paths).
  orderedBlockNames =
    if unknownNames != []
    then throw ''routnix: firewall.filter.rules references unknown block(s): ${concatStringsSep ", " unknownNames}''
    else
      lib.routnix.sortEntries
      (mapAttrs (_: block: {inherit (block) before after;}) cfg.rules);

  # Each block contributes its `rules` in declared order, with the
  # block's `chain` applied to every one.
  blockItems = name: let
    block = cfg.rules.${name};
  in
    map (rule:
      if rule ? chain
      then throw ''routnix: firewall.filter.rules.${name}: a rule sets `chain`; it is set for the whole block''
      else rule // {inherit (block) chain;})
    block.rules;
in {
  options.firewall.filter.enable = mkOption {
    type = types.bool;
    default = false;
    description = ''
      Whether routnix manages the `/ip firewall filter` table from
      `firewall.filter.rules`. While disabled, `firewall.filter.rules`
      has no effect and the table is left untouched.
    '';
  };

  options.firewall.filter.rules = mkOption {
    type = types.attrsOf (types.submodule blockSubmodule);
    default = {};
    description = ''
      Named blocks of firewall filter rules. Each block's rules are
      kept in declared order relative to each other; blocks are placed
      relative to each other with `before`/`after`, keyed by block name.
    '';
  };

  config = mkIf cfg.enable {
    routeros.config."/ip firewall filter" = {
      kind = "ordered";
      items = concatMap blockItems orderedBlockNames;
    };
  };
}
