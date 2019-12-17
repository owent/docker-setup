#!/bin/bash

GEOIP_DAT_URL="https://github.com/v2ray/geoip/releases/latest/download/geoip.dat";
GFWLIST_ORIGIN_URL="https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt";
GFWLIST_GEN_SCRIPT_URL="https://raw.githubusercontent.com/cokebar/gfwlist2dnsmasq/master/gfwlist2dnsmasq.sh";
MYIP=$(curl https://myip.biturl.top/ 2>/dev/null);
