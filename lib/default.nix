{lib}: let
  extendedLib = import ./extended.nix {inherit lib;};

  # Routnix provided modules
  providedModules =
    map (name: ../modules + "/${name}")
    (builtins.attrNames
      (lib.filterAttrs
        (name: type: type == "regular" && lib.hasSuffix ".nix" name)
        (builtins.readDir ../modules)));

  # Copies a ciphertext file into the store when it isn't there yet, so
  # the uploader can always reach it.
  storeFile = file:
    if extendedLib.hasPrefix (builtins.storeDir + "/") (toString file)
    then file
    else builtins.path {path = file; name = "routnix-secrets.enc";};

  # Evaluates a routnix configuration and renders it into a `.rsc` script.
  #
  #   evalConfig { modules = [ ./examples/basic.nix ]; }
  #
  # Returns the result of `lib.evalModules` (so `.config`, `.options`, ...
  # are all available) plus `rsc`, the fully rendered, dependency-ordered
  # `.rsc` text, and `secrets`, the evaluated `routeros.secrets`.
  evalConfig = {modules}: let
    evaluated = extendedLib.evalModules {
      modules = providedModules ++ modules;
    };

    failedAssertions =
      builtins.filter (a: !a.assertion) evaluated.config.assertions;

    checked =
      if failedAssertions == []
      then evaluated
      else
        throw (
          extendedLib.concatMapStringsSep "\n"
          (a: "routnix: assertion failed: ${a.message}")
          failedAssertions
        );

    config = checked.config;
    secrets = config.routeros.secrets;
    secretFile = if secrets.file == null then null else storeFile secrets.file;
    secretPayload =
      if secrets.entries == {}
      then null
      else extendedLib.routnix.secretPayloadFileName;

    order = extendedLib.routnix.sortEntries config.routeros.config;
    rsc = extendedLib.routnix.renderConfig
      config.routeros.config
      order
      config.routeros.preCheck
      secretPayload;
  in
    checked
    // {
      inherit rsc;
      secrets = secrets // {file = secretFile;};
    };
in {
  inherit (extendedLib) routnix;
  inherit evalConfig;

  # Renders one router's `modules` to an `.rsc` package with an `apply`
  # wrapper attached (see `mk_device_config.nix`).
  mkDeviceConfig = import ./mk_device_config.nix {inherit evalConfig;};
}
