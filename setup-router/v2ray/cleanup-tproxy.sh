#!/bin/bash

if [[ -e "/opt/nftables/sbin" ]]; then
    export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

## Cleanup hooks
FWMARK_LOOPUP_TABLE_IDS=($(ip -4 rule show fwmark 0x0e/0x0f lookup 100 | awk 'END {print $NF}'));
for TABLE_ID in ${FWMARK_LOOPUP_TABLE_IDS[@]}; do
    ip -4 rule delete fwmark 0x0e/0x0f lookup $TABLE_ID ;
    ip -4 route delete local 0.0.0.0/0 dev lo table $TABLE_ID ;
done

FWMARK_LOOPUP_TABLE_IDS=($(ip -6 rule show fwmark 0x0e/0x0f lookup 100 | awk 'END {print $NF}'));
for TABLE_ID in ${FWMARK_LOOPUP_TABLE_IDS[@]}; do
    ip -6 rule delete fwmark 0x0e/0x0f lookup $TABLE_ID ;
    ip -6 route delete local ::/0 dev lo table $TABLE_ID ;
done

# Cleanup ipv4
iptables -t mangle -D PREROUTING -p tcp -j V2RAY > /dev/null 2>&1 ;
while [[ $? -eq 0 ]]; do
    iptables -t mangle -D PREROUTING -p tcp -j V2RAY > /dev/null 2>&1;
done
iptables -t mangle -D PREROUTING -p udp -j V2RAY > /dev/null 2>&1 ;
while [[ $? -eq 0 ]]; do
    iptables -t mangle -D PREROUTING -p udp -j V2RAY > /dev/null 2>&1;
done
iptables -t mangle -D OUTPUT -p tcp -j V2RAY_MASK > /dev/null 2>&1 ;
while [[ $? -eq 0 ]]; do
    iptables -t mangle -D OUTPUT -p tcp -j V2RAY_MASK > /dev/null 2>&1;
done
iptables -t mangle -D OUTPUT -p tcp -j V2RAY_MASK > /dev/null 2>&1 ;
while [[ $? -eq 0 ]]; do
    iptables -t mangle -D OUTPUT -p tcp -j V2RAY_MASK > /dev/null 2>&1;
done
iptables -t mangle -F V2RAY > /dev/null 2>&1;
iptables -t mangle -X V2RAY > /dev/null 2>&1;
iptables -t mangle -F V2RAY_MASK > /dev/null 2>&1;
iptables -t mangle -X V2RAY_MASK > /dev/null 2>&1;


# Cleanup ipv6
ip6tables -t mangle -D PREROUTING -p tcp -j V2RAY > /dev/null 2>&1 ;
while [[ $? -eq 0 ]]; do
    ip6tables -t mangle -D PREROUTING -p tcp -j V2RAY > /dev/null 2>&1;
done
ip6tables -t mangle -D PREROUTING -p udp -j V2RAY > /dev/null 2>&1 ;
while [[ $? -eq 0 ]]; do
    ip6tables -t mangle -D PREROUTING -p udp -j V2RAY > /dev/null 2>&1;
done
ip6tables -t mangle -D OUTPUT -p tcp -j V2RAY_MASK > /dev/null 2>&1 ;
while [[ $? -eq 0 ]]; do
    ip6tables -t mangle -D OUTPUT -p tcp -j V2RAY_MASK > /dev/null 2>&1;
done
ip6tables -t mangle -D OUTPUT -p udp -j V2RAY_MASK > /dev/null 2>&1 ;
while [[ $? -eq 0 ]]; do
    ip6tables -t mangle -D OUTPUT -p udp -j V2RAY_MASK > /dev/null 2>&1;
done
ip6tables -t mangle -F V2RAY > /dev/null 2>&1;
ip6tables -t mangle -X V2RAY > /dev/null 2>&1;
ip6tables -t mangle -F V2RAY_MASK > /dev/null 2>&1;
ip6tables -t mangle -X V2RAY_MASK > /dev/null 2>&1;

# Cleanup bridge
ebtables -t broute -D BROUTING -p ipv4 --ip-proto tcp -j V2RAY_BRIDGE > /dev/null 2>&1 ;
while [[ $? -eq 0 ]]; do
    ebtables -t broute -D BROUTING -p ipv4 --ip-proto tcp -j V2RAY_BRIDGE > /dev/null 2>&1;
done
ebtables -t broute -D BROUTING -p ipv4 --ip-proto udp -j V2RAY_BRIDGE > /dev/null 2>&1 ;
while [[ $? -eq 0 ]]; do
    ebtables -t broute -D BROUTING -p ipv4 --ip-proto udp -j V2RAY_BRIDGE > /dev/null 2>&1;
done
ebtables -t broute -D BROUTING -p ipv6 --ip6-proto tcp -j V2RAY_BRIDGE > /dev/null 2>&1 ;
while [[ $? -eq 0 ]]; do
    ebtables -t broute -D BROUTING -p ipv6 --ip-proto tcp -j V2RAY_BRIDGE > /dev/null 2>&1;
done
ebtables -t broute -D BROUTING -p ipv6 --ip-proto udp -j V2RAY_BRIDGE > /dev/null 2>&1 ;
while [[ $? -eq 0 ]]; do
    ebtables -t broute -D BROUTING -p ipv6 --ip-proto udp -j V2RAY_BRIDGE > /dev/null 2>&1;
done
ebtables -t broute -F V2RAY_BRIDGE > /dev/null 2>&1;
ebtables -t broute -X V2RAY_BRIDGE > /dev/null 2>&1;

rm -f /etc/NetworkManager/dispatcher.d/up.d/99-setup-tproxy.ebtables.sh > /dev/null 2>&1;
rm -f "$SETUP_TPROXY_EBTABLES_SCRIPT" /etc/NetworkManager/dispatcher.d/down.d/99-setup-tproxy.ebtables.sh > /dev/null 2>&1;
