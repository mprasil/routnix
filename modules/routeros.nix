{ lib, ... }:
let
  inherit (lib) mkOption types;

  inherit (import ../lib/render.nix { inherit lib; }) renderArgs;

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
      kind = mkOption {
        type = types.enum [
          "ordered"
          "unordered"
          "settings"
          "effect"
        ];
        description = ''
          How this path's entries should be managed. Required, no default --
          picking a kind is a meaningful decision, not something to fall
          back on silently:

          - `"ordered"`: position matters (firewall filter/mangle/nat,
            routing rules, queue trees). `items` are rendered as a plain,
            unconditional `add` per item, in declared order. There is no
            identity check and no positional reconciliation yet
            (`place-before`/`move` is planned, *not* remove-then-readd) --
            reapplying currently duplicates entries.
          - `"unordered"`: presence, not position, matters (routes,
            address-lists, VLANs). Each item in `items` is only `add`-ed
            if `find` doesn't already match an existing entry.
          - `"settings"`: a non-table, singleton config object (e.g.
            `/ip/dhcp-server/config`). `settings` fields are rendered as a
            single `set`, inherently idempotent -- no `items`, `find`, or
            `create`.
          - `"effect"`: items realized via one or more RouterOS commands
            that aren't a plain `add` of the item's own fields (e.g.
            `/user/ssh-keys import`, possibly preceded by preparation
            steps like writing a file). Same `find`-guarded per-item model
            as `"unordered"`, but `create` returns arbitrary `.rsc` text
            instead of relying on the default `add`.
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
          Item data for `kind = "ordered" | "unordered" | "effect"` (unused
          for `"settings"`, see `settings`). For `"ordered"`, each item is
          rendered directly as `add` of its own fields. For
          `"unordered"`/`"effect"`, each item is passed to `find` and
          `create` rather than rendered directly.
        '';
      };

      find = mkOption {
        type = types.functionTo (types.attrsOf itemValueType);
        description = ''
          `kind = "unordered" | "effect"` only, required. Given one item
          (from `items`), returns the fields used to look up whether it
          already exists (rendered as `print count-only where k=v ...`,
          compared against `0`), so `create` only runs when there isn't a
          match. Deliberately has no default
          -- an "always add unconditionally" fallback would silently
          duplicate entries on reapply, so every unordered/effect resource
          has to state its identity explicitly. Unused (never evaluated,
          so safe to omit) for `"ordered"`/`"settings"`.
        '';
      };

      create = mkOption {
        type = types.functionTo types.str;
        default = item: "add " + renderArgs item;
        description = ''
          `kind = "unordered" | "effect"` only. Given one item, returns the
          raw `.rsc` text to run when `find` doesn't match. Runs under this
          entry's own path context; prefix a line with a different
          absolute path (e.g. `/file add ...`) to act elsewhere first
          without losing that context for subsequent lines -- useful for
          `"effect"` entries that need preparation before their main
          action. Defaults to a plain `add` of the item's own fields, which
          is normally all `"unordered"` needs. Unused (never evaluated) for
          `"ordered"`/`"settings"`.
        '';
      };

      settings = mkOption {
        type = types.attrsOf itemValueType;
        default = { };
        description = ''
          `kind = "settings"` only: fields to `set` on this path. Unused
          for other kinds.
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
      are rendered/managed is controlled via `kind`.
    '';
  };
}
