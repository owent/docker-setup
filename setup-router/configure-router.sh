#!/bin/bash

RUN_USER=tools
export ROUTER_HOME=/home/router
export ROUTER_DOMAIN=home.shkits.com
ROUTER_INTERNAL_IPV4=172.23.1.10
ROUTER_DATA_ROOT_DIR=/data
ROUTER_LOG_ROOT_DIR=$ROUTER_DATA_ROOT_DIR/logs
ROUTER_LOCAL_LAN_INTERFACE='{ lo, br0, enp2s0 , vlan0 }'
ROUTER_IPV6_RADVD_NDP_DEVICE=(enp2s0 vlan0)
#sysctl -w net.ipv6.conf.${ROUTER_IPV6_RADVD_NDP_DEVICE[@]}.proxy_ndp=1
#sysctl -w net.ipv6.conf.${ROUTER_IPV6_RADVD_NDP_DEVICE[@]}.accept_ra=2
# Edit $ROUTER_HOME/vlan/vlan-setup-bridge.sh to make sure bridge and vlan tag will be set correctly

ROUTER_INTERNAL_SERVICE_PRIVATE_PORT_TCP="53,80,139,443,445,853,6800"
ROUTER_INTERNAL_SERVICE_PUBLIC_PORT_TCP="6349,6443,6881,6882,6883,8371,8372,8373,36000"
ROUTER_INTERNAL_SERVICE_PRIVATE_PORT_UDP="53,67,68,80,137,138,443,547,6800"
ROUTER_INTERNAL_SERVICE_PUBLIC_PORT_UDP="6349,6443,6881,6882,6883,8371,8372,8373"
ROUTER_INTERNAL_SERVICE_PORT_TCP="${ROUTER_INTERNAL_SERVICE_PRIVATE_PORT_TCP},${ROUTER_INTERNAL_SERVICE_PUBLIC_PORT_TCP}"
ROUTER_INTERNAL_SERVICE_PORT_UDP="${ROUTER_INTERNAL_SERVICE_PRIVATE_PORT_UDP},${ROUTER_INTERNAL_SERVICE_PUBLIC_PORT_UDP}"
ROUTER_INTERNAL_SERVICE_PORT_ALL="$(echo "${ROUTER_INTERNAL_SERVICE_PORT_TCP//,/ } ${ROUTER_INTERNAL_SERVICE_PORT_UDP//,/ }" | xargs -r -n 1 echo | sort -u -n)"
ROUTER_INTERNAL_SERVICE_PORT_ALL="$(echo "$ROUTER_INTERNAL_SERVICE_PORT_ALL" | tr '\n' ',' | sed -E 's;,*$;;g' | sed -E 's;^,*;;g')"
# NTP Port: 123
ROUTER_INTERNAL_DIRECTLY_VISIT_UDP_DPORT="123"

DNSMASQ_DNS_PORT=6053
DNSMASQ_ENABLE_DNS=0
DNSMASQ_ENABLE_DHCP=1
DNSMASQ_ENABLE_IPV6_NDP=0
DNSMASQ_ENABLE_DHCP_EXCEPT_INTERFACE=(ppp0 ppp1)

GEOIP_GEOSITE_ETC_DIR=$ROUTER_HOME/etc/v2ray

SMARTDNS_ENABLE=0
SMARTDNS_DNS_PORT=6153
SMARTDNS_ETC_DIR=$ROUTER_HOME/etc/smartdns
SMARTDNS_LOG_DIR=$ROUTER_LOG_ROOT_DIR/smartdns
SMARTDNS_APPEND_CONFIGURE=""

COREDNS_DNS_PORT=53
NEXTDNS_PRIVATE_TLS_DOMAIN=steering.nextdns.io

# Use radvd and ndp and disable NAT6
NAT_SETUP_SKIP_IPV6=1

ACMESH_SSL_DIR=$ROUTER_HOME/acme.sh/ssl
SAMBA_DATA_DIR=$ROUTER_DATA_ROOT_DIR/samba
POSTGRESQL_ADMIN_USER=owent
POSTGRESQL_DATA_DIR=$SAMBA_DATA_DIR/postgresql/data
POSTGRESQL_SHM_SIZE=1024 # MB
POSTGRESQL_MAX_CONNECTIONS=200
POSTGRESQL_PORT=5432
NEXTCLOUD_DATA_DIR=$SAMBA_DATA_DIR/nextcloud/data
NEXTCLOUD_APPS_DIR=$SAMBA_DATA_DIR/nextcloud/apps
NEXTCLOUD_ETC_DIR=$SAMBA_DATA_DIR/nextcloud/etc
NEXTCLOUD_EXTERNAL_DIR=$SAMBA_DATA_DIR/nextcloud/external
NEXTCLOUD_REVERSE_ROOT_DIR="" # Set non empty and use fpm docker image when success
NEXTCLOUD_TRUSTED_DOMAINS=""  # nextcloud domains and IPs

TPROXY_SETUP_USING_GEOIP=0
TPROXY_SETUP_IPSET=0
TPROXY_SETUP_SMARTDNS=0
TPROXY_SETUP_DNSMASQ=0
TPROXY_SETUP_COREDNS=1
TPROXY_SETUP_WITHOUT_IPV6=1

TPROXY_SETUP_COREDNS_WITH_NFTABLES=1
TPROXY_SETUP_NFTABLES=1 # Set 1 to use iptables/ebtables
TPROXY_WHITELIST_IPV4=("91.108.56.0/22" "95.161.64.0/20" "91.108.4.0/22" "91.108.8.0/22" "149.154.160.0/22" "149.154.164.0/22" "8.8.8.8" "8.8.4.4")
TPROXY_WHITELIST_IPV6=("2001:4860:4860::8888" "2001:4860:4860::8844")

# Syncthing
if [[ -e "$ROUTER_HOME/syncthing/configure-server.sh" ]]; then
  source "$ROUTER_HOME/syncthing/configure-server.sh"
elif [[ -e "$(dirname "$0")/syncthing/configure-server.sh" ]]; then
  source "$(dirname "$0")/syncthing/configure-server.sh"
fi

[ -e "/opt/podman" ] && export PATH="/opt/podman/bin:/opt/podman/libexec:$PATH"
export PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/sbin"

"$@"
