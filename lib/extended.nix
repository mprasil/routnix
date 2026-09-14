{lib}:
# Extends nixpkgs' `lib` with routnix's own functions under `lib.routnix`,
# the same way e.g. home-manager extends it with `lib.hm`. Modules are
# evaluated via this extended lib's `evalModules` (see `evalConfig` in
# `default.nix`), so every module's `lib` module argument already
# includes `lib.routnix` -- no separate per-file imports needed.
lib.extend (self: super: {
  routnix = {
    inherit (import ./per_platform.nix {lib = self;}) perPlatform;
    inherit (import ./render_rsc.nix {lib = self;}) renderValue renderArgs renderConfig;
    inherit (import ./toposort.nix {lib = self;}) sortEntries;
  };
})
