#!/bin/bash

cd "$(dirname "$(readlink -f "$0")")"

PYTHON_BIN="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
if [[ -z "$PYTHON_BIN" ]]; then
   echo "Error: python3 or python is required." >&2
   exit 1
fi

EXCLUDE_RULE_OPTIONS=(
   --exclude-domain-regex 'steam\.cdn\..*'
   --exclude-domain steamcdn-a.akamaihd.net
   --exclude-domain steamcontent.com
   --exclude-domain steamusercontent.com
   --exclude-domain steamstatic.com
   --exclude-domain steam.tv
   --exclude-domain-suffix qtlglb.com
   --exclude-domain edge.steam-dns.top.comcast.net

   --exclude-domain-suffix epicgamescdn.com
   --exclude-domain fastly-download.epicgames.com

   --exclude-domain packagespc.xboxlive.com
   --exclude-domain-suffix riotcdn.net
   --exclude-domain-suffix riotcdn.com

   --exclude-domain-suffix nexoncdn.co.kr

   --exclude-domain-suffix nintendo.net

   --exclude-domain-suffix microsoft.com
)

#    --source "geosite-microsoft" \
#    --source "geosite-bing" \
#    --source "geosite-category-games-!cn" \

"$PYTHON_BIN" ./smartdns-generate-geosite.py \
   --name geosite-proxy-fast \
   --geosite-dir ../vbox/geosite \
   --source geosite-github \
   --source geosite-docker \
   --source geosite-category-container \
   --source geosite-telegram \
   --source geosite-gfw \
   --source "geosite-geolocation-!cn" \
   --source "geosite-category-dev" \
   --source "geosite-azure" \
   --source "geosite-unity" \
   --source "geosite-pinterest" \
   --source "geosite-intercom" \
   --source "geosite-slack" \
   --domain-suffix "nextcloud.com" \
   --domain-suffix "grafana.org" \
   --domain-suffix "github.com" \
   --domain-suffix "acme.zerossl.com" \
   --domain-suffix "sider.ai" \
   --domain-suffix "blackbox.ai" \
   --domain-suffix "monica.im" \
   --domain-suffix "monica-cdn.im" \
   --domain-suffix "profitwell.com" \
   --domain-suffix "ouchyi.bid" \
   --domain-suffix "okx.com" \
   --domain-suffix "canonical.com" \
   --domain-suffix "trafficmanager.net" \
   --domain-suffix "freedif.org" \
   --domain-suffix "servanamanaged.com" \
   --domain-suffix "ossplanet.net" \
   --domain-suffix "copilot-proxy.githubusercontent.com" \
   --domain-suffix "copilot-telemetry.githubusercontent.com" \
   --dns-group proxy_dns \
   --disable-ipv6 \
   --nftset4 inet#sdwan#PROXY_FAST_IPV4 \
   --nftset6 inet#sdwan#PROXY_FAST_IPV6 \
   "${EXCLUDE_RULE_OPTIONS[@]}"

"$PYTHON_BIN" ./smartdns-generate-geosite.py \
   --name geosite-proxy-ai \
   --geosite-dir ../vbox/geosite \
   --source "geosite-ai" \
   --dns-group proxy_dns \
   --disable-ipv6 \
   --nftset4 inet#sdwan#PROXY_AI_IPV4 \
   --nftset6 inet#sdwan#PROXY_AI_IPV6 \
   "${EXCLUDE_RULE_OPTIONS[@]}"
