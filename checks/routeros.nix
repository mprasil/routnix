# Integration test: boot a RouterOS CHR VM under QEMU and verify that the
# routnix-generated .rsc can be imported and produces the expected config.
#
# Requires KVM on the build host (requiredSystemFeatures = ["kvm"]).
# Run against a single RouterOS version:
#   nix build .#checks.x86_64-linux.routeros-stable-v7 -L
# Run against every version in ros_versions.nix:
#   nix flake check
{
  pkgs,
  routnixLib,
  image,
  name,
}: let
  # ------------------------------------------------------------------
  # routnix output: the .rsc generated from the basic example config
  # ------------------------------------------------------------------
  example = routnixLib.evalConfig {modules = [../examples/basic.nix];};
  rscFile = pkgs.writeText "routnix-example.rsc" example.rsc;

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

    nativeBuildInputs = [
      pkgs.qemu_test
      pkgs.openssh
      testPython
    ];

    buildCommand = ''
      mkdir -p "$out"

      # Our helper scripts; test_driver itself and its Python deps come
      # from testPython's own site-packages.
      export PYTHONPATH="${testHelpers}"

      ${testPython}/bin/python3 ${testHelpers}/routeros_test.py \
        --image   "$(ls ${image}/*.img)" \
        --rsc     "${rscFile}" \
        --qemu    "$(command -v qemu-system-x86_64)" \
        --ssh     "$(command -v ssh)" \
        --scp     "$(command -v scp)" \
        --out-dir "$out"

      touch "$out/success"
    '';

    meta.description = "routnix integration test against RouterOS CHR image ${name}";
  }
