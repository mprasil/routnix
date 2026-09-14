{lib}: {
  # Picks the value for `config.device.platform` out of `results` (an
  # attrset keyed by platform name), e.g.:
  #
  #   perPlatform config {
  #     routeros_v6 = "[:passwdgen]";
  #     routeros_v7 = "[:rndstr]";
  #   }
  #
  # Throws if `config.device.platform` isn't one of `results`'s keys.
  perPlatform = config: results: let
    platform = config.device.platform;
  in
    if results ? ${platform}
    then results.${platform}
    else
      throw ''
        routnix: platform "${platform}" is not supported here -- expected one of: ${lib.concatStringsSep ", " (builtins.attrNames results)}
      '';
}
