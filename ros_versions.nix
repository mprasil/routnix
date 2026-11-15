# RouterOS CHR Versions we test against
#
# Hash can be calculated with nurl:
# nurl -f fetchzip https://download.mikrotik.com/routeros/${VERSION}/chr-${VERSION}.img.zip
#
# Upstream versions available here: https://mikrotik.com/download/chr
rec {
  long-term-v7 = {
    version = "7.24.6";
    hash = "sha256-jti66+BCalm8xcLjAP4JaKY9FOYPBgIF385r011mKJg=";
  };
  long-term-v6 = {
    version = "6.49.23";
    hash = "sha256-5rQSFDNiHR+4P7tjnZNImYTG9+XY+v60DXCPeoTaGyA=";
  };
  stable-v7 = {
    version = "7.25.1";
    hash = "sha256-cgrfHP4yREZm1++kH1bbd8frMOznD45utq1XkgntOLE=";
  };
  stable-v6 = long-term-v6;
  development-v7 = {
    version = "7.26beta5";
    hash = "sha256-YdlQkRD/3RxilVa6qnwWOWPbQX/fKS2dyjloFyQzhjU=";
  };
}
