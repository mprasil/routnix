# Pure-Nix unit tests for lib/render_rsc.nix and lib/toposort.nix
# (lib/tests.nix, run via lib.runTests).
#
#   nix build .#checks.x86_64-linux.render-unit-tests
{
  pkgs,
  lib ? pkgs.lib,
}: let
  # lib/tests.nix throws (listing the failing test names, expected vs.
  # actual) if any test failed, and evaluates to `null` otherwise.
  result = import ../lib/tests.nix {inherit pkgs lib;};
in
  pkgs.runCommand "routnix-render-unit-tests" {} ''
    : ${builtins.seq result ""}
    touch "$out"
  ''
