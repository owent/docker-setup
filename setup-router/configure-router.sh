#!/bin/bash

export RUN_USER=tools
export ROUTER_HOME=/home/router

export DNSMASQ_DNS_PORT=6053

export GEOIP_GEOSITE_ETC_DIR=$ROUTER_HOME/etc/v2ray

export SMARTDNS_DNS_PORT=53
export SMARTDNS_ETC_DIR=$ROUTER_HOME/etc/smartdns
export SMARTDNS_LOG_DIR=/data/logs/smartdns

export NAT_SETUP_SKIP_IPV6=1

"$@"
