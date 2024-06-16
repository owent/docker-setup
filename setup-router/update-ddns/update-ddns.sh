#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

SET_IP_PARAMETERS=()
BAN_INERFACES=( ppp1 ) # ppp0 ppp1

function check_available() {
  for CHECK_INERFACE in ${BAN_INERFACES[@]}; do
    if [[ "$1" == "$CHECK_INERFACE" ]]; then
      return 1
    fi
  done
  return 0
}

for PPP_INTERFACE in $(nmcli --fields NAME,TYPE connection show | awk '{if($2=="pppoe"){print $1}}'); do
  IGNORE_INTERFACE=0
  check_available "$PPP_INTERFACE" || IGNORE_INTERFACE=1
  [[ $IGNORE_INTERFACE -ne 0 ]] && continue

  # Need gawk
  for PPP_IP in $(ip -o -4 addr show scope global dev $PPP_INTERFACE 2>/dev/null | awk 'match($0, /inet\s+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/, ip) { print ip[1] }'); do
    SET_IP_PARAMETERS=(${SET_IP_PARAMETERS[@]} "$PPP_IP")
  done
  for PPP_IP in $(ip -o -6 addr show scope global dev $PPP_INTERFACE 2>/dev/null | awk 'match($0, /inet6\s+([0-9a-fA-F:]+)/, ip) { print ip[1] }'); do
    SET_IP_PARAMETERS=(${SET_IP_PARAMETERS[@]} "$PPP_IP")
  done
done

if [[ ${#SET_IP_PARAMETERS[@]} -le 0 ]]; then
  for TRY_GET_MY_IP_URL in "https://ifconfig.me" "https://api.myip.la" "https://ifconfig.io" "https://myip.biturl.top" "https://api.ipify.org"; do
    MY_IPV4=$(curl -4 -sL "$TRY_GET_MY_IP_URL")
    if [[ -n "$MY_IPV4" ]]; then
      SET_IP_PARAMETERS=(${SET_IP_PARAMETERS[@]} "$MY_IPV4")
      MY_IPV6=$(curl -6 -sL "$TRY_GET_MY_IP_URL")
      if [[ -n "$MY_IPV4" ]]; then
        SET_IP_PARAMETERS=(${SET_IP_PARAMETERS[@]} "$MY_IPV6")
      fi
      break
    fi
  done
fi

echo "Public ip(s): ${SET_IP_PARAMETERS[@]}" | systemd-cat -t router-ddns -p info

if [[ ${#SET_IP_PARAMETERS[@]} -le 0 ]]; then
  exit 0
fi

# Update ddns to cloudflare
podman run --rm --network=host ghcr.io/owent/ddns-cli /usr/local/ddns-cli/bin/ddns-cli \
  --ip ${SET_IP_PARAMETERS[@]} --ip-no-link-local --ip-no-loopback --ip-no-multicast --ip-no-private --ip-no-shared \
  --cf-token <cloudflare token> \
  --cf-domain <domain> --cf-zone-id <cloudflare zone id>

# Update ddns to nextdns
#   Find report URL on https://my.nextdns.io/<租户ID>/setup
curl -L https://link-ip.nextdns.io/...
