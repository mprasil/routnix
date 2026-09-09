# RouterOS CHR Versions we test against
#
# Hash can be calculated with nurl:
# nurl -f fetchzip https://download.mikrotik.com/routeros/${VERSION}/chr-${VERSION}.img.zip
#
# Upstream versions available here: https://mikrotik.com/download/chr
rec {
  long-term-v7 = {
    version = "7.23.5";
    hash = "sha256-R2C6PIyi0xXLpJc18OLSn9VdLKUUsbOZngJNdUDPGvI=";
  };
  long-term-v6 = {
    version = "6.49.21";
    hash = "sha256-QiEFah6uOPVUkbJLOlCtoLXt0ogi2MY5B2f1Ll8ArYk=";
  };
  stable-v7 = {
    version = "7.24.2";
    hash = "sha256-NcAgtDE0WBMP6jt65sJb5RzGscrJ7nZaGcvu0zgiCfo=";
  };
  stable-v6 = long-term-v6;
  development-v7 = {
    version = "7.25beta3";
    hash = "sha256-5IxI1iF1YYk2nvvbflhDRm5/pH6+Ff9B5CFhHPHDEfA=";
  };
}
