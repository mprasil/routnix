# Integration test: boot a RouterOS CHR VM under QEMU and verify that
# routnix-generated .rsc snippets apply as expected.
#
# Run against a single RouterOS version:
#   nix build .#checks.x86_64-linux.routeros-stable-v7 -L
# Run against every version in ros_versions.nix:
#   nix flake check
{
  pkgs,
  lib ? pkgs.lib,
  routnixLib,
  image,
  name,
}: let
  # ------------------------------------------------------------------
  # One rendered .rsc per file in checks/configs/, named after that
  # file (minus ".nix"). routeros_test.py knows the specific set of
  # test names it expects and drives the assertions for each; this side
  # only has to keep every config's *.rsc available to it under that
  # name.
  # ------------------------------------------------------------------
  configsDir = ./configs;
  configNames = builtins.map (lib.removeSuffix ".nix") (
    builtins.filter (lib.hasSuffix ".nix") (builtins.attrNames (builtins.readDir configsDir))
  );

  # `device.platform` (used by e.g. modules/users.nix's `perPlatform`
  # calls) is resolved from this check's own RouterOS version, so each
  # alias's .rsc exercises the branch matching the image it's actually
  # applied to instead of always defaulting to routeros_v7.
  rosVersions = import ../ros_versions.nix;
  majorVersion = builtins.head (lib.splitString "." rosVersions.${name}.version);
  platform =
    if majorVersion == "6"
    then "routeros_v6"
    else if majorVersion == "7"
    then "routeros_v7"
    else throw "routnix: unsupported RouterOS major version ${majorVersion} for ${name}";

  rscFor = configName: let
    evaluated = routnixLib.evalConfig {
      modules = [
        (configsDir + "/${configName}.nix")
        {device.platform = platform;}
      ];
    };
  in
    pkgs.writeText "routnix-${configName}.rsc" evaluated.rsc;

  rscDir = pkgs.linkFarm "routnix-test-configs" (
    builtins.map (n: {
      name = "${n}.rsc";
      path = rscFor n;
    })
    configNames
  );

  testPython = pkgs.python3.withPackages (
    ps: [
      ((ps.toPythonModule pkgs.nixos-test-driver).overrideAttrs {
        # required because nixos-test-driver's pyproject.toml hardcodes version
        # 0.0.0 while its derivation sets 1.1.
        dontCheckPythonMetadata = true;
      })
    ]
  );

  testHelpers = pkgs.runCommand "routeros-test-helpers" {} ''
    mkdir -p "$out"
    cp ${./routeros_machine.py} "$out/routeros_machine.py"
    cp ${./routeros_test.py}   "$out/routeros_test.py"
  '';
in
  pkgs.stdenv.mkDerivation {
    name = "routeros-integration-test-${name}";
    buildCommand = ''
      mkdir -p "$out"

      ${testPython}/bin/python3 ${testHelpers}/routeros_test.py \
        --image   "$(ls ${image}/*.img)" \
        --rsc-dir "${rscDir}" \
        --qemu    "${pkgs.qemu_test}/bin/qemu-system-x86_64" \
        --ssh     "${pkgs.openssh}/bin/ssh" \
        --scp     "${pkgs.openssh}/bin/scp" \
        --platform "${platform}" \
        --out-dir "$out"

      touch "$out/success"
    '';

    meta.description = "routnix integration test against RouterOS CHR image ${name}";
  }
