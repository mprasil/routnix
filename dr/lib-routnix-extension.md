# Context

Modules need access to routnix's own library functions (e.g.
`perPlatform`) without each module having to import specific `lib/*.nix`
files itself.

# Options considered

- Modules import specific `lib/*.nix` files directly wherever they need
  them.
- Extend nixpkgs' `lib` with routnix's own functions under a namespace,
  and pass that extended `lib` as every module's `lib` argument.

# Decision

`evalConfig` calls `evalModules` on the lib built by `lib/extended.nix` —
nixpkgs `lib.extend`-ed with routnix's own functions under `lib.routnix`,
the same mechanism home-manager uses for `lib.hm`. Every module's `lib`
argument already has `lib.routnix.*` available, so modules use e.g.
`lib.routnix.perPlatform` directly rather than importing a specific
`lib/*.nix` file themselves.
