# Pure-Nix unit tests for modules/*.nix (modules/tests/, run via
# lib.runTests): what each module compiles its own options down to in
# `routeros.config`, independent of lib/render_rsc.nix's rendering
# (covered separately by render-unit-tests).
#
#   nix build .#checks.x86_64-linux.module-unit-tests
{
  pkgs,
  lib ? pkgs.lib,
}: let
  # modules/tests/ throws (listing the failing test names, expected vs.
  # actual) if any test failed, and evaluates to `null` otherwise.
  result = import ../modules/tests {inherit pkgs lib;};
in
  pkgs.runCommand "routnix-module-unit-tests" {} ''
    : ${builtins.seq result ""}
    touch "$out"
  ''
