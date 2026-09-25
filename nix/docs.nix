# Renders routnix's option tree to HTML. Option declarations are reported
# relative to the routnix source tree.
{
  lib,
  pkgs,
  routnixLib,
}: let
  src = ./..;
  evaluatedConfig = routnixLib.evalConfig {modules = [];};
  docs = pkgs.nixosOptionsDoc {
    inherit (evaluatedConfig) options;
    transformOptions = opt:
      opt
      # nixpkgs declares `_module.args` visible at the root of the option
      # tree (lib/modules.nix); it isn't part of routnix's API.
      // lib.optionalAttrs (lib.head opt.loc == "_module") {visible = false;}
      // {
        # Declarations are the absolute store paths the modules were loaded
        # from; report them relative to the routnix source instead.
        declarations = map (decl: {name = lib.removePrefix "${toString src}/" (toString decl);}) opt.declarations;
      };
  };
in
  pkgs.runCommand "routnix docs" {} ''
    cp ${docs.optionsAsciiDoc} routnix.adoc
    ${pkgs.asciidoctor}/bin/asciidoctor -D $out routnix.adoc
  ''
