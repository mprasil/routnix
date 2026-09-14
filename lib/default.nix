{lib}: let
  extendedLib = import ./extended.nix {inherit lib;};

  # Routnix provided modules
  providedModules =
    map (name: ../modules + "/${name}")
    (builtins.attrNames
      (lib.filterAttrs
        (name: type: type == "regular" && lib.hasSuffix ".nix" name)
        (builtins.readDir ../modules)));
in {
  inherit (extendedLib) routnix;

  # Evaluates a routnix configuration and renders it into a `.rsc` script.
  #
  #   evalConfig { modules = [ ./examples/basic.nix ]; }
  #
  # Returns the result of `lib.evalModules` (so `.config`, `.options`, ...
  # are all available) plus `rsc`, the fully rendered, dependency-ordered
  # `.rsc` text.
  evalConfig = {modules}: let
    evaluated = extendedLib.evalModules {
      modules = providedModules ++ modules;
    };
    order = extendedLib.routnix.sortEntries evaluated.config.routeros.config;
  in
    evaluated // {rsc = extendedLib.routnix.renderConfig evaluated.config.routeros.config order;};
}
