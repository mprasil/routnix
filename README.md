# routnix

Declarative RouterOS (MikroTik) configuration using the Nix module system,
rendered to idempotent `.rsc` scripts — entirely in Nix, with no external
tool/build step for ordering or rendering.

> [!WARNING]
> Very early and experimental. The low-level DSL shown below works, but
> most of the design (ownership tracking, idempotent updates, high-level
> modules, actually applying config to a router) is still unimplemented or
> unsettled. See [`DESIGN.md`](./DESIGN.md) for the full picture — what's
> actually built vs. what's still open design space.

## Example

```nix
{
  routeros.config."/ip/firewall/address-list" = {
    kind = "unordered";
    items = [
      { address = "192.168.1.0/24"; list = "trusted-ips"; }
    ];
  };

  routeros.config."/ip/firewall/filter" = {
    kind = "ordered";
    after = [ "/ip/firewall/address-list" ];
    items = [
      { chain = "input"; action = "accept"; protocol = "icmp"; }
      { chain = "input"; action = "accept"; "connection-state" = "established,related"; }
      { chain = "input"; action = "accept"; protocol = "tcp"; "dst-port" = 22; "src-address-list" = "trusted-ips"; }
      { chain = "input"; action = "drop"; }
    ];
  };
}
```

`after`/`before` declare ordering between RouterOS paths (needed since some
config depends on other config existing first, e.g. an address-list before
a firewall rule referencing it); routnix topologically sorts them and
renders a single `.rsc` script in the right order.

## Try it

```console
$ nix build .#example && cat result
```

See `examples/` for the source of that config, and `examples/cycle.nix` /
`.#cycle-example` for what a dependency-cycle error looks like.

## Status

RouterOS-only, no plans otherwise (see `DESIGN.md` for the naming
rationale). Nothing here should be pointed at a real router yet — there's
no apply mechanism, no idempotent update logic, and no ownership tracking
implemented.

## Inspirations

- [`mikrotik.nix`](https://github.com/nrabulinski/mikrotik.nix) — declarative
  RouterOS configuration via a Nix module system, rendering of rsc script is
  done in Rust code rather than pure nix.
