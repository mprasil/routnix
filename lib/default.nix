{ lib }:
let
  toposort = import ./toposort.nix { inherit lib; };
  render = import ./render_rsc.nix { inherit lib; };
in
{
  inherit (toposort) sortEntries;
  inherit (render) renderConfig;

  # Evaluates a routnix configuration and renders it into a `.rsc` script.
  #
  #   evalConfig { modules = [ ./examples/basic.nix ]; }
  #
  # Returns the result of `lib.evalModules` (so `.config`, `.options`, ...
  # are all available) plus `rsc`, the fully rendered, dependency-ordered
  # `.rsc` text.
  evalConfig =
    { modules }:
    let
      evaluated = lib.evalModules { modules = [ ../modules/routeros.nix ] ++ modules; };
      order = toposort.sortEntries evaluated.config.routeros.config;
    in
    evaluated // { rsc = render.renderConfig evaluated.config.routeros.config order; };
}
