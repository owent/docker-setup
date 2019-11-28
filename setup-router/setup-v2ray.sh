#!/bin/bash

# IP http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest

cat delegated-apnic-latest | awk 'BEGIN{FS="|"}{if($2 == "CN" && $3 != "asn"){print $3 " " $4 " " $5}}'
# ipv4 <start> <count> => ipv4 58.42.0.0 65536
# ipv6 <prefix> <bits> => ipv6 2407:c380:: 32

curl -L -o generate_dnsmasq_chinalist.sh https://github.com/cokebar/openwrt-scripts/raw/master/generate_dnsmasq_chinalist.sh
chmod +x generate_dnsmasq_chinalist.sh
sh generate_dnsmasq_chinalist.sh -d 114.114.114.114 -p 53 -s ss_spec_dst_bp -o /etc/dnsmasq.d/accelerated-domains.china.conf
