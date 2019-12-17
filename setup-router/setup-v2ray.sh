#!/bin/bash

# nftables
# Quick: https://wiki.nftables.org/wiki-nftables/index.php/Performing_Network_Address_Translation_(NAT)
# Quick(CN): https://wiki.archlinux.org/index.php/Nftables_(%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87)#Masquerading
# List all tables/chains/rules/matches/statements: https://wiki.nftables.org/wiki-nftables/index.php/Quick_reference-nftables_in_10_minutes#Rules
# man 8 nft: 
#    https://www.netfilter.org/projects/nftables/manpage.html
#    https://www.mankier.com/8/nft
# IP http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest

cat delegated-apnic-latest | awk 'BEGIN{FS="|"}{if($2 == "CN" && $3 != "asn"){print $3 " " $4 " " $5}}'
# ipv4 <start> <count> => ipv4 58.42.0.0 65536
# ipv6 <prefix> <bits> => ipv6 2407:c380:: 32

curl -L -o generate_dnsmasq_chinalist.sh https://github.com/cokebar/openwrt-scripts/raw/master/generate_dnsmasq_chinalist.sh
chmod +x generate_dnsmasq_chinalist.sh
sh generate_dnsmasq_chinalist.sh -d 114.114.114.114 -p 53 -s ss_spec_dst_bp -o /etc/dnsmasq.d/accelerated-domains.china.conf

export PATH=/opt/nftables/sbin:$PATH;

## proxy
### Setup - kernel
###   using ```find /lib/modules/$(uname -r) -type f -name '*.ko*' | xargs basename -a | sort | uniq``` to see all available modules
###   See https://www.kernel.org/doc/Documentation/networking/tproxy.txt
###   See http://man7.org/linux/man-pages/man5/modules-load.d.5.html
modprobe nf_tproxy_ipv4
modprobe nf_tproxy_ipv6
modprobe nf_socket_ipv4
modprobe nf_socket_ipv6
modprobe xt_socket
#### kernel modules required for nft (kernel 4.19 or upper, see https://wiki.nftables.org/wiki-nftables/index.php/Supported_features_compared_to_xtables#TPROXY)
modprobe nft_socket
modprobe nft_tproxy
echo "
nf_tproxy_ipv4
nf_tproxy_ipv6
nf_socket_ipv4
nf_socket_ipv6
xt_socket
nft_socket
nft_tproxy
" > /etc/modules-load.d/tproxy.conf
V2RAY_HOST_IPV4=
V2RAY_PORT=3371

### Setup mangle xtable rule and policy routing
### ip rule { add | del } SELECTOR ACTION
### default table-> local: 255 , main: 254 , default: 253
### 策略路由，所有 fwmark = 1 的包走 table:100
ip rule add fwmark 1 lookup 100
ip route add local 0.0.0.0/0 dev lo table 100
ip -6 route add local ::/0 dev lo table 100

nft add table filter

### See https://toutyrater.github.io/app/tproxy.html

### Setup - ipv4
nft add chain filter v2ray { type filter hook prerouting priority 1 \; }
nft flush chain filter v2ray

### ipv4 - skip link-locak and broadcast address
nft add rule filter v2ray ip daddr {127.0.0.1/32, 224.0.0.0/4, 255.255.255.255/32} return
### ipv4 - skip private network and UDP of DNS
nft add rule filter v2ray meta l4proto tcp ip daddr 172.18.0.0/16 return
nft add rule filter v2ray ip daddr 172.18.0.0/16 udp dport != 53 return

### ipv4 - forward to v2ray's listen address if not marked by v2ray
# nft add rule filter v2ray tcp sport != 22 log prefix '"######tproxy"' level debug flags all
nft add rule filter v2ray mark 255 return # make sure v2ray's outbounds.*.streamSettings.sockopt.mark = 255
# tproxy ip to $V2RAY_HOST_IPV4:$V2RAY_PORT
# nft add rule filter v2ray tcp sport != 22 log prefix '">>>>>>tproxy"' level debug flags all
nft add rule filter v2ray meta l4proto tcp mark set 1 tproxy to :$V2RAY_PORT # -j TPROXY --on-port $V2RAY_PORT  # mark tcp package with 1 and forward to $V2RAY_PORT
nft add rule filter v2ray meta l4proto udp mark set 1 tproxy to :$V2RAY_PORT # -j TPROXY --on-port $V2RAY_PORT  # mark tcp package with 1 and forward to $V2RAY_PORT

# Setup - ipv4 local
nft add chain mangle v2ray_mask { type route hook output priority 1 \; }
nft flush chain mangle v2ray_mask
nft add rule mangle v2ray_mask ip daddr {224.0.0.0/4, 255.255.255.255/32} return
nft add rule mangle v2ray_mask meta l4proto tcp ip daddr 172.18.0.0/16 return
nft add rule mangle v2ray_mask ip daddr 172.18.0.0/16 udp dport != 53 return
# nft add rule mangle v2ray_mask tcp sport != 22 log prefix '"######mark 1"' level debug flags all
nft add rule mangle v2ray_mask mark 255 return
nft add rule mangle v2ray_mask mark != 1 meta l4proto {tcp, udp} mark set 1 accept
# nft add rule mangle v2ray_mask tcp sport != 22 log prefix '"++++++mark 1"' level debug flags all

## Setup - ipv6
nft add chain ip6 filter v2ray { type filter hook prerouting priority 1 \; }
nft flush chain ip6 filter v2ray

### ipv6 - skip link-locak and multicast
nft add rule ip6 filter v2ray daddr {::1/128, fe80::/10, ff00::/8} return

### ipv6 - skip private network and UDP of DNS
nft add rule ip6 filter v2ray meta l4proto tcp ip daddr fd27:32d6:ac12::/48 return
nft add rule ip6 filter v2ray ip daddr fd27:32d6:ac12::/48 udp dport != 53 return

### ipv4 - forward to v2ray's listen address if not marked by v2ray
nft add rule ip6 filter v2ray mark 255 return # make sure v2ray's outbounds.*.streamSettings.sockopt.mark = 255
# nft add rule ip6 filter v2ray log prefix '">>>>>>v2ray-tproxy"' level debug flags all
# tproxy ip6 to $V2RAY_HOST_IPV6:$V2RAY_PORT
nft add rule ip6 filter v2ray meta l4proto tcp mark set 1 tproxy to :$V2RAY_PORT # -j TPROXY --on-port $V2RAY_PORT  # mark tcp package with 1 and forward to $V2RAY_PORT
nft add rule ip6 filter v2ray meta l4proto udp mark set 1 tproxy to :$V2RAY_PORT # -j TPROXY --on-port $V2RAY_PORT  # mark tcp package with 1 and forward to $V2RAY_PORT

# Setup - ipv6 local
nft add chain ip6 mangle v2ray_mask { type route hook output priority 1 \; }
nft flush chain ip6 mangle v2ray_mask
nft add rule ip6 mangle v2ray_mask ip daddr {::1/128, fe80::/10, ff00::/8} return
nft add rule ip6 mangle v2ray_mask meta l4proto tcp ip daddr fd27:32d6:ac12::/48 return
nft add rule ip6 mangle v2ray_mask ip daddr fd27:32d6:ac12::/48 udp dport != 53 return
nft add rule ip6 mangle v2ray_mask mark 255 return
# nft add rule ip6 mangle v2ray_mask log prefix '"++++++mark 1"' level debug flags all
nft add rule ip6 mangle v2ray_mask mark != 1 meta l4proto {tcp, udp} mark set 1 accept


# podman & systemd
podman run -d --name v2ray -v /etc/v2ray:/etc/v2ray \
    --cap-add=NET_ADMIN --network=host              \
    docker.io/v2ray/official:latest                 \
    v2ray -config=/etc/v2ray/config.json
podman generate systemd v2ray
