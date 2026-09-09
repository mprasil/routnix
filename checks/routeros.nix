# Integration test: boot a RouterOS CHR VM under QEMU and verify that the
# routnix-generated .rsc can be imported and produces the expected config.
#
# Requires KVM on the build host (requiredSystemFeatures = ["kvm"]).
# Run with:
#   nix build .#checks.x86_64-linux.routeros -L
#   nix flake check
{
  pkgs,
  routnixLib,
}: let
  routerOsVersion = "7.24.2";

  chrImage = pkgs.fetchzip {
    name = "routeros-image-${routerOsVersion}";
    url = "https://download.mikrotik.com/routeros/${routerOsVersion}/chr-${routerOsVersion}.img.zip";
    hash = "sha256-NcAgtDE0WBMP6jt65sJb5RzGscrJ7nZaGcvu0zgiCfo=";
    stripRoot = false;
  };

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
    name = "routeros-integration-test";

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
        --image   "${chrImage}/chr-${routerOsVersion}.img" \
        --rsc     "${rscFile}" \
        --qemu    "$(command -v qemu-system-x86_64)" \
        --ssh     "$(command -v ssh)" \
        --scp     "$(command -v scp)" \
        --out-dir "$out"

      touch "$out/success"
    '';

    meta.description = "routnix integration test against RouterOS ${routerOsVersion} CHR";
  }
