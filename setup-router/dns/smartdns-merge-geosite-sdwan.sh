#!/bin/bash

cd "$(dirname "$(readlink -f "$0")")"

./smartdns-generate-geosite.sh \
   --name geosite-proxy-fast \
   --geosite-dir ../vbox/geosite \
   --source geosite-github \
   --source geosite-docker \
   --source geosite-category-container \
   --source geosite-telegram \
   --source geosite-gfw \
   --source "geosite-geolocation-!cn" \
   --source "geosite-microsoft" \
   --source "geosite-category-dev" \
   --source "geosite-azure" \
   --source "geosite-unity" \
   --source "geosite-pinterest" \
   --source "geosite-bing" \
   --source "geosite-category-games-!cn" \
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


./smartdns-generate-geosite.sh \
   --name geosite-proxy-ai \
   --geosite-dir ../vbox/geosite \
   --source "geosite-ai" \
   --dns-group proxy_dns \
   --disable-ipv6 \
   --nftset4 inet#sdwan#PROXY_AI_IPV4 \
   --nftset6 inet#sdwan#PROXY_AI_IPV6 \
