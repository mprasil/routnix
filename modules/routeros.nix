{ lib, ... }:
let
  inherit (lib) mkOption types;

  # Loose value type for RouterOS fields. Kept intentionally simple for now;
  # stricter types (CIDR, MAC, port-lists, ...) are expected to live in
  # higher-level, device-agnostic modules built on top of this, not here.
  itemValueType = types.oneOf [
    types.bool
    types.int
    types.str
  ];

  entryModule = {
    options = {
      before = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          Paths of other `routeros.config` entries that must be configured
          *after* this one, e.g. `[ "/ip/firewall/filter" ]`.
        '';
      };

      after = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          Paths of other `routeros.config` entries that must be configured
          *before* this one.
        '';
      };

      items = mkOption {
        type = types.listOf (types.attrsOf itemValueType);
        default = [ ];
        description = ''
          RouterOS entries to `add` under this path, rendered in the given
          order.
        '';
      };
    };
  };
in
{
  options.routeros.config = mkOption {
    type = types.attrsOf (types.submodule entryModule);
    default = { };
    description = ''
      RouterOS configuration, keyed by full RouterOS path (e.g.
      `"/ip/firewall/filter"`). This is the low-level, path-granularity,
      RouterOS-specific building block of routnix; ordering between
      different paths is controlled via `before`/`after`.
    '';
  };
}
