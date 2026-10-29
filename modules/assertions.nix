{lib, ...}: {
  options.assertions = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        assertion = lib.mkOption {type = lib.types.bool;};
        message = lib.mkOption {type = lib.types.str;};
      };
    });
    default = [];
    description = ''
      Conditions the configuration must satisfy. Evaluation stops and
      reports the message of every failing assertion.
    '';
  };
}
