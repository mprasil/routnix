{lib, ...}: let
  inherit (lib) mkOption types;

  inherit (lib.routnix) renderArgs;

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
          "inventory"
        ];
        description = ''
          How entries at this path are managed:

          - `"ordered"` (e.g. firewall filter/mangle/nat, routing rules):
            order matters, so items are kept in declared order relative
            to each other -- identity is derived automatically from each
            item's own fields (like `"unordered"`), missing items are
            `add`-ed already placed as close to their declared position
            as possible, and present-but-misplaced ones are repositioned
            via `move`. Existing entries that are no longer declared are
            always removed.
          - `"unordered"` (e.g. routes, address-lists, VLANs): only
            presence matters, so an item is `add`-ed only if it doesn't
            already match an existing entry, by its own declared fields.
            Existing entries that are no longer declared, and not
            covered by `ignore`, are always removed.
          - `"settings"` (e.g. `/ip dhcp-server config`): `settings`
            fields are applied as a single `set`.
          - `"effect"` (e.g. `/user ssh-keys`): like `"unordered"`, but
            `create` runs arbitrary commands instead of a plain `add`.
          - `"inventory"` (e.g. `/interface ethernet`,
            `/system package`): entries that already exist, bound to the
            hardware or firmware, and can be adjusted but never added or
            removed. Each item is located by `find`, and `configure` runs
            against it. Nothing at the path is ever removed, and a
            declared item `find` doesn't locate is an error.
        '';
      };

      preScript = mkOption {
        type = types.lines;
        default = "";
        description = ''
          Freehand `.rsc` commands run before this entry's configuration,
          e.g. enabling a feature the path's entries depend on. They run
          before the path is entered, so they need to use absolute paths.
          They are expected to succeed: one that fails stops the run and
          leaves the router partly configured, so this isn't a way to bail
          out on a router that isn't ready.
        '';
      };

      before = mkOption {
        type = types.listOf types.str;
        default = [];
        description = ''
          Paths of other `routeros.config` entries that must be configured
          *after* this one, e.g. `[ "/ip firewall filter" ]`.
        '';
      };

      after = mkOption {
        type = types.listOf types.str;
        default = [];
        description = ''
          Paths of other `routeros.config` entries that must be configured
          *before* this one.
        '';
      };

      items = mkOption {
        type = types.listOf (types.attrsOf itemValueType);
        default = [];
        description = ''
          For `kind = "ordered"`: fields to `add`, one item per entry,
          kept in declared order relative to each other; also passed to
          `find` to locate each item's existing entry, if any. For
          `"unordered"`/`"effect"`: item data passed to `find` and
          `create`. For `"inventory"`: item data passed to `find` and
          `configure`. Ignored for `"settings"` (see `settings`).
        '';
      };

      find = mkOption {
        type = types.nullOr (types.functionTo (types.attrsOf itemValueType));
        default = null;
        description = ''
          For `kind = "effect"` or `"inventory"`, required: given an
          item from `items`, returns the fields an existing entry must
          match to be that item. Ignored for
          `"ordered"`/`"unordered"` (identity is derived automatically
          from each item's own fields instead) and `"settings"`.
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

          For `kind = "effect"`, running these commands must leave
          behind an entry `find` matches -- applying errors otherwise.
        '';
      };

      configure = mkOption {
        type = types.nullOr (types.functionTo types.str);
        default = null;
        description = ''
          For `kind = "inventory"`, required: given an item from
          `items`, returns the `.rsc` text to run against that item's
          existing entry, e.g. `item: "set $item name=" + item.name` or
          `item: "enable $item"`. `$item` is the entry `find` located
          for the item. A line can start with a different absolute path
          (e.g. `/file add ...`) without changing that context for
          subsequent lines. Ignored for other kinds.
        '';
      };

      settings = mkOption {
        type = types.attrsOf itemValueType;
        default = {};
        description = ''
          For `kind = "settings"`: fields applied as a single `set`.
          Ignored for other kinds.
        '';
      };

      ignore = mkOption {
        type = types.listOf (types.attrsOf itemValueType);
        default = [];
        description = ''
          For `kind = "unordered"`, `"ordered"`, or `"effect"` (all
          three always remove existing entries no longer declared):
          entries matching any of these field predicates are left alone,
          even if not declared in `items` -- for entries managed by hand
          or by another tool. Ignored for `"settings"` and `"inventory"`.
        '';
      };
    };
  };
in {
  options.routeros.preCheck = mkOption {
    type = types.lines;
    default = "";
    description = ''
      Freehand `.rsc` commands run before any configuration is applied.
      Intended for preconditions, e.g. checking that ipv6 is enabled
      before ipv6 firewall rules are applied. They run before any
      configuration change, so they can only inspect state the router
      already has, not anything routnix itself sets up. A failing check
      stops the run before anything is configured.
    '';
  };

  options.routeros.config = mkOption {
    type = types.attrsOf (types.submodule entryModule);
    default = {};
    description = ''
      RouterOS configuration, keyed by full RouterOS path, space-separated
      after the leading slash (e.g. `"/ip firewall filter"`). This is the
      low-level, path-granularity, RouterOS-specific building block of
      routnix; ordering between different paths is controlled via
      `before`/`after`, and how entries are managed is controlled via
      `kind`.
    '';
  };
}
