{
  lib,
  config,
  ...
}: let
  inherit (lib) mkOption mkIf types concatMap concatStringsSep filter mapAttrs;
  inherit (lib.routnix) perPlatform;

  cfg = config.firewall.filter;

  # RouterOS field value: bool, int, or string.
  itemValueType = types.oneOf [
    types.bool
    types.int
    types.str
  ];

  blockSubmodule = {...}: {
    options = {
      family = mkOption {
        type = types.enum ["ipv4" "ipv6" "both"];
        default =
          if cfg.family == "ipv4only"
          then "ipv4"
          else cfg.family;
        description = ''
          Which filter table(s) this block's rules are added to: `"ipv4"`
          for `/ip firewall filter`, `"ipv6"` for `/ipv6 firewall
          filter`, `"both"` for both. Defaults to `firewall.filter.family`
          (`"ipv4"` when that is `"ipv4only"`).
        '';
      };

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

  # `"ipv4only"` manages the ipv4 table only, so a block targeting ipv6
  # is a configuration error rather than a rule that would go nowhere.
  ipv6BlocksUnderIpv4Only =
    if cfg.family == "ipv4only"
    then filter (name: cfg.rules.${name}.family != "ipv4") blockNames
    else [];

  # Blocks are ordered among themselves by `before`/`after` (block
  # names), the same way `routeros.config` paths are ordered by
  # `before`/`after` (paths).
  orderedBlockNames =
    if unknownNames != []
    then throw ''routnix: firewall.filter.rules references unknown block(s): ${concatStringsSep ", " unknownNames}''
    else if ipv6BlocksUnderIpv4Only != []
    then throw ''routnix: firewall.filter.family is "ipv4only", but these blocks target ipv6: ${concatStringsSep ", " ipv6BlocksUnderIpv4Only}''
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

  # Which table(s) each block contributes to; a `"both"` block
  # contributes to both.
  blockTargetsIPv4 = name: builtins.elem cfg.rules.${name}.family ["ipv4" "both"];
  blockTargetsIPv6 = name: builtins.elem cfg.rules.${name}.family ["ipv6" "both"];

  itemsFor = targets: concatMap blockItems (filter targets orderedBlockNames);

  # Every family but `"ipv4only"` manages both filter tables.
  managesIPv6 = cfg.family != "ipv4only";
in {
  options.firewall.filter.enable = mkOption {
    type = types.bool;
    default = false;
    description = ''
      Whether routnix manages the firewall filter tables (see
      `firewall.filter.family`) from `firewall.filter.rules`. While
      disabled, `firewall.filter.rules` has no effect and the tables are
      left untouched.
    '';
  };

  options.firewall.filter.family = mkOption {
    type = types.enum ["ipv4" "ipv6" "both" "ipv4only"];
    default = "both";
    description = ''
      Which filter tables routnix manages, and the default `family` for
      blocks that don't set their own:

      - `"ipv4"`, `"ipv6"`, `"both"`: both `/ip firewall filter` and
        `/ipv6 firewall filter` are managed -- entries not declared are
        removed -- and blocks default to that family.
      - `"ipv4only"`: only `/ip firewall filter` is managed, and a block
        set to `"ipv6"` or `"both"` is an error.
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
      items = itemsFor blockTargetsIPv4;
    };

    routeros.config."/ipv6 firewall filter" = mkIf managesIPv6 {
      kind = "ordered";
      items = itemsFor blockTargetsIPv6;
    };

    # ipv6 is a separately installable, disableable package on RouterOS v6, but
    # built in on v7.
    routeros.preCheck = mkIf (managesIPv6
      && (perPlatform config {
        routeros_v6 = true;
        routeros_v7 = false;
      })) ''
      :if ([:len [/system package find where name="ipv6" disabled=no]] = 0) do={
        :put "routnix: ipv6 firewall is managed, but ipv6 is not enabled on this router (set firewall.filter.family to ipv4only for an ipv4-only device)"
        :error "routnix-ipv6-firewall-not-enabled"
      }
    '';
  };
}
