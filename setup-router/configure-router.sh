#!/bin/bash

export RUN_USER=tools
export ROUTER_HOME=/home/router
export ROUTER_DATA_ROOT_DIR=/data
export ROUTER_LOG_ROOT_DIR=$ROUTER_DATA_ROOT_DIR/logs

export DNSMASQ_DNS_PORT=6053

export GEOIP_GEOSITE_ETC_DIR=$ROUTER_HOME/etc/v2ray

export SMARTDNS_DNS_PORT=6153
export SMARTDNS_ETC_DIR=$ROUTER_HOME/etc/smartdns
export SMARTDNS_LOG_DIR=$ROUTER_LOG_ROOT_DIR/smartdns
export SMARTDNS_APPEND_CONFIGURE=""

export COREDNS_DNS_PORT=53

# Use radvd and ndp and disable NAT6
export NAT_SETUP_SKIP_IPV6=1

export ACMESH_SSL_DIR=$ROUTER_HOME/acme.sh/ssl
export SAMBA_DATA_DIR=$ROUTER_DATA_ROOT_DIR/samba
export NEXTCLOUD_DATA_DIR=$SAMBA_DATA_DIR/nextcloud

"$@"
