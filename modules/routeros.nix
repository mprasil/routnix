{ lib, ... }:
let
  inherit (lib) mkOption types;

  inherit (import ../lib/render_rsc.nix { inherit lib; }) renderArgs;

  # RouterOS field value: bool, int, or string.
  itemValueType = types.oneOf [
    types.bool
    types.int
    types.str
  ];

  entryModule = {
    options = {
      kind = mkOption {
        type = types.enum [
          "ordered"
          "unordered"
          "settings"
          "effect"
        ];
        description = ''
          How entries at this path are managed:

          - `"ordered"` (e.g. firewall filter/mangle/nat, routing rules):
            order matters, so items are kept in declared order relative
            to each other -- `find` locates each item, missing ones are
            `add`-ed (anchored via `place-before` where needed) and
            present-but-misplaced ones are repositioned via `move`.
          - `"unordered"` (e.g. routes, address-lists, VLANs): only
            presence matters, so an item is `add`-ed only if it doesn't
            already match an existing entry, by its own declared fields.
          - `"settings"` (e.g. `/ip/dhcp-server/config`): `settings`
            fields are applied as a single `set`.
          - `"effect"` (e.g. `/user/ssh-keys`): like `"unordered"`, but
            `create` runs arbitrary commands instead of a plain `add`.
        '';
      };

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
          For `kind = "ordered"`: fields to `add`, one item per entry,
          kept in declared order relative to each other; also passed to
          `find` to locate each item's existing entry, if any. For
          `"unordered"`/`"effect"`: item data passed to `find` and
          `create`. Ignored for `"settings"` (see `settings`).
        '';
      };

      find = mkOption {
        type = types.nullOr (types.functionTo (types.attrsOf itemValueType));
        default = null;
        description = ''
          For `kind = "ordered" | "effect"`, required: given an item from
          `items`, returns the fields an existing entry must match for
          that item to be considered already present. For `"ordered"`,
          this identity is also used to check the item's position
          relative to its declared neighbors. Ignored for `"unordered"`
          (identity is derived automatically from each item's own fields
          instead) and `"settings"`.
        '';
      };

      create = mkOption {
        type = types.functionTo types.str;
        default = item: "add " + renderArgs item;
        description = ''
          For `kind = "unordered" | "effect"`. Given an item, returns the
          `.rsc` text to run when `find` finds no match, evaluated in this
          entry's path context. A line can start with a different absolute
          path (e.g. `/file add ...`) without changing that context for
          subsequent lines. Ignored for other kinds.
        '';
      };

      settings = mkOption {
        type = types.attrsOf itemValueType;
        default = { };
        description = ''
          For `kind = "settings"`: fields applied as a single `set`.
          Ignored for other kinds.
        '';
      };

      prune = mkOption {
        type = types.bool;
        default = false;
        description = ''
          For `kind = "unordered"`: removes existing entries not matched
          by `find` for any current item and not covered by `ignore`.
          Off by default. Only valid for `kind = "unordered"`.
        '';
      };

      ignore = mkOption {
        type = types.listOf (types.attrsOf itemValueType);
        default = [ ];
        description = ''
          For `kind = "unordered"` with `prune = true`: entries matching
          any of these field predicates are left alone by pruning, even
          if not declared in `items` -- for entries managed by hand or by
          another tool.
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
      different paths is controlled via `before`/`after`, and how entries
      are managed is controlled via `kind`.
    '';
  };
}
