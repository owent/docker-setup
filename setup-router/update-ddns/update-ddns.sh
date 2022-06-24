#!/bin/bash

if [[ -e "/opt/nftables/sbin" ]]; then
  export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

SET_IP_PARAMETERS=()

for PPP_INTERFACE in $(nmcli --fields NAME,TYPE connection show | awk '{if($2=="pppoe"){print $1}}'); do
  for PPP_IP in $(ip -o -4 addr show scope global dev $PPP_INTERFACE | awk 'match($0, /inet\s+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/, ip) { print ip[1] }'); do
    SET_IP_PARAMETERS=(${SET_IP_PARAMETERS[@]} "$PPP_IP")
  done
  for PPP_IP in $(ip -o -6 addr show scope global dev $PPP_INTERFACE | awk 'match($0, /inet6\s+([0-9a-fA-F:]+)/, ip) { print ip[1] }'); do
    SET_IP_PARAMETERS=(${SET_IP_PARAMETERS[@]} "$PPP_IP")
  done
done

echo "PPP ip(s): ${SET_IP_PARAMETERS[@]}" | systemd-cat -t router-ddns -p info

# Update ddns to cloudflare
podman run --rm --network=host docker.io/owt5008137/ddns-cli /usr/local/ddns-cli/bin/ddns-cli \
  --ip ${SET_IP_PARAMETERS[@]} --ip-no-link-local --ip-no-loopback --ip-no-multicast --ip-no-private --ip-no-shared \
  --cf-token <cloudflare token> \
  --cf-domain <domain> --cf-zone-id <cloudflare zone id>

# Update ddns to nextdns
#   Find report URL on https://my.nextdns.io/<租户ID>/setup
curl -L https://link-ip.nextdns.io/...
