#!/bin/bash


# nftables
# Quick: https://wiki.nftables.org/wiki-nftables/index.php/Performing_Network_Address_Translation_(NAT)
# Quick(CN): https://wiki.archlinux.org/index.php/Nftables_(%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87)#Masquerading
# List all tables/chains/rules/matches/statements: https://wiki.nftables.org/wiki-nftables/index.php/Quick_reference-nftables_in_10_minutes#Rules
# man 8 nft: 
#    https://www.netfilter.org/projects/nftables/manpage.html
#    https://www.mankier.com/8/nft
# IP http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest
#    ipv4 <start> <count> => ipv4 58.42.0.0 65536
#    ipv6 <prefix> <bits> => ipv6 2407:c380:: 32
# Netfilter: https://en.wikipedia.org/wiki/Netfilter
#            http://inai.de/images/nf-packet-flow.svg

if [ -e "/opt/nftables/sbin" ]; then
    export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

### ==================================== v2ray nftables rules begin ====================================
### ----------------------------------- /home/router/v2ray/setup-tproxy.sh -----------------------------------

### Setup v2ray xtable rule and policy routing
### ip rule { add | del } SELECTOR ACTION
### default table/rule-> local(ID: 255)/Priority: 0 , main(ID: 254)/Priority: 32766 , default(ID: 253)/Priority: 32766
### 策略路由，所有 fwmark = 1 的包走 table:100

if [ "x" == "x$V2RAY_HOST_IPV4" ]; then
    V2RAY_HOST_IPV4=
fi

if [ "x" == "x$V2RAY_PORT" ]; then
    V2RAY_PORT=3371
fi

if [ "x" == "x$SETUP_WITH_INTERNAL_SERVICE_PORT" ]; then
    SETUP_WITH_INTERNAL_SERVICE_PORT="22,53,6881,6882,6883,8371,8372,36000"
fi

if [ "x" == "x$SETUP_WITH_DEBUG_LOG" ]; then
    SETUP_WITH_DEBUG_LOG=0
fi

ip -4 route add local 0.0.0.0/0 dev lo table 100
ip -6 route add local ::/0 dev lo table 100
FWMARK_LOOPUP_TABLE_100=$(ip -4 rule show fwmark 1 lookup 100 | awk 'END {print NF}')
while [ 0 -ne $FWMARK_LOOPUP_TABLE_100 ] ; do
    ip -4 rule delete fwmark 1 lookup 100
    FWMARK_LOOPUP_TABLE_100=$(ip -4 rule show fwmark 1 lookup 100 | awk 'END {print NF}')
done

FWMARK_LOOPUP_TABLE_100=$(ip -6 rule show fwmark 1 lookup 100 | awk 'END {print NF}')
while [ 0 -ne $FWMARK_LOOPUP_TABLE_100 ] ; do
    ip -6 rule delete fwmark 1 lookup 100
    FWMARK_LOOPUP_TABLE_100=$(ip -6 rule show fwmark 1 lookup 100 | awk 'END {print NF}')
done
ip -4 rule add fwmark 1 lookup 100
ip -6 rule add fwmark 1 lookup 100
# ip route show table 100

### See https://toutyrater.github.io/app/tproxy.html

### Setup - ipv4
ipset list V2RAY_BLACKLIST_IPV4 > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    ipset create V2RAY_BLACKLIST_IPV4 hash:ip family inet;
fi

iptables -t mangle -L V2RAY > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    iptables -t mangle -N V2RAY ;
else
    iptables -t mangle -F V2RAY ;
fi

iptables -t mangle -L V2RAY_MASK > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    iptables -t mangle -N V2RAY_MASK ;
else
    iptables -t mangle -F V2RAY_MASK ;
fi

### ipv4 - skip internal services
iptables -t mangle -A V2RAY -p tcp -m multiport --sports $SETUP_WITH_INTERNAL_SERVICE_PORT -j RETURN
iptables -t mangle -A V2RAY -p udp -m multiport --sports $SETUP_WITH_INTERNAL_SERVICE_PORT -j RETURN
if [ $SETUP_WITH_DEBUG_LOG -ne 0 ]; then
    iptables -t mangle -A V2RAY -p tcp -m multiport ! --dports $SETUP_WITH_INTERNAL_SERVICE_PORT -j LOG --log-level debug --log-prefix "###TCP4#PREROU:"
fi

### ipv4 - skip link-local and broadcast address
iptables -t mangle -A V2RAY -d 127.0.0.1/32,224.0.0.0/4,255.255.255.255/32 -j RETURN
iptables -t mangle -A V2RAY -m mark --mark 0xff -j RETURN
### ipv4 - skip private network and UDP of DNS
iptables -t mangle -A V2RAY -d 192.168.0.0/16,172.16.0.0/12,10.0.0.0/8 -j RETURN
# if dns service and V2RAY are on different server, use rules below
# iptables -t mangle -A V2RAY -p tcp -d 192.168.0.0/16,172.16.0.0/12,10.0.0.0/8 -j RETURN
# iptables -t mangle -A V2RAY -p udp -d 192.168.0.0/16,172.16.0.0/12,10.0.0.0/8 ! --dport 53 -j RETURN
# iptables -t mangle -A V2RAY -p tcp -d $GATEWAY_ADDRESSES -j RETURN

# ipv4 skip package from outside
iptables -t mangle -A V2RAY -p tcp -m set --match-set V2RAY_BLACKLIST_IPV4 dst -j RETURN
iptables -t mangle -A V2RAY -p udp -m set --match-set V2RAY_BLACKLIST_IPV4 dst -j RETURN
### ipv4 - forward to v2ray's listen address if not marked by v2ray
# tproxy ip to $V2RAY_HOST_IPV4:$V2RAY_PORT
if [ $SETUP_WITH_DEBUG_LOG -ne 0 ]; then
    iptables -t mangle -A V2RAY -p tcp -m multiport ! --dports $SETUP_WITH_INTERNAL_SERVICE_PORT -j TRACE
    iptables -t mangle -A V2RAY -p tcp -m multiport ! --dports $SETUP_WITH_INTERNAL_SERVICE_PORT LOG --log-level debug --log-prefix ">>>TCP4>tproxy:"
fi

iptables -t mangle -A V2RAY -p tcp -j TPROXY --on-port $V2RAY_PORT --tproxy-mark 1 # mark tcp package with 1 and forward to $V2RAY_PORT
iptables -t mangle -A V2RAY -p udp -j TPROXY --on-port $V2RAY_PORT --tproxy-mark 1 # mark tcp package with 1 and forward to $V2RAY_PORT
iptables -t mangle -D PREROUTING -j V2RAY > /dev/null 2>&1 ;
while [ $? -eq 0 ]; do
    iptables -t mangle -D PREROUTING -j V2RAY > /dev/null 2>&1;
done
iptables -t mangle -A PREROUTING -j V2RAY # apply rules

# Setup - ipv4 local
### ipv4 - skip internal services
iptables -t mangle -A V2RAY_MASK -p tcp -m multiport --sports $SETUP_WITH_INTERNAL_SERVICE_PORT -j RETURN
iptables -t mangle -A V2RAY_MASK -p udp -m multiport --sports $SETUP_WITH_INTERNAL_SERVICE_PORT -j RETURN
if [ $SETUP_WITH_DEBUG_LOG -ne 0 ]; then
    iptables -t mangle -A V2RAY_MASK -p tcp -m multiport ! --dports $SETUP_WITH_INTERNAL_SERVICE_PORT LOG --log-level debug --log-prefix "###TCP4#OUTPUT:"
fi

iptables -t mangle -A V2RAY_MASK -d 127.0.0.1/32,224.0.0.0/4,255.255.255.255/32 -j RETURN
iptables -t mangle -A V2RAY_MASK -m mark --mark 0xff -j RETURN
### ipv4 - skip private network and UDP of DNS
iptables -t mangle -A V2RAY_MASK -d 192.168.0.0/16,172.16.0.0/12,10.0.0.0/8 -j RETURN
# if dns service and V2RAY_MASK are on different server, use rules below
# iptables -t mangle -A V2RAY_MASK -p tcp -d 192.168.0.0/16,172.16.0.0/12,10.0.0.0/8 -j RETURN
# iptables -t mangle -A V2RAY_MASK -p udp -d 192.168.0.0/16,172.16.0.0/12,10.0.0.0/8 ! --dport 53 -j RETURN
# iptables -t mangle -A V2RAY_MASK -p tcp -d $GATEWAY_ADDRESSES -j RETURN

if [ $SETUP_WITH_DEBUG_LOG -ne 0 ]; then
    iptables -t mangle -A V2RAY_MASK -p tcp -m multiport ! --dports $SETUP_WITH_INTERNAL_SERVICE_PORT -j TRACE
    iptables -t mangle -A V2RAY_MASK -p tcp -m multiport ! --dports $SETUP_WITH_INTERNAL_SERVICE_PORT LOG --log-level debug --log-prefix "+++TCP4+mark 1:"
fi
# ipv4 skip package from outside
iptables -t mangle -A V2RAY_MASK -p udp -j MARK --set-mark 1
iptables -t mangle -A V2RAY_MASK -p tcp -j MARK --set-mark 1

iptables -t mangle -D OUTPUT -j V2RAY_MASK > /dev/null 2>&1 ;
while [ $? -eq 0 ]; do
    iptables -t mangle -D OUTPUT -j V2RAY_MASK > /dev/null 2>&1;
done
iptables -t mangle -A OUTPUT -j V2RAY_MASK # apply rules

## Setup - ipv6
ipset list V2RAY_BLACKLIST_IPV6 > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    ipset create V2RAY_BLACKLIST_IPV6 hash:ip family inet6;
fi

ip6tables -t mangle -L V2RAY > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    ip6tables -t mangle -N V2RAY ;
else
    ip6tables -t mangle -F V2RAY ;
fi

ip6tables -t mangle -L V2RAY_MASK > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    ip6tables -t mangle -N V2RAY_MASK ;
else
    ip6tables -t mangle -F V2RAY_MASK ;
fi

### ipv6 - skip internal services
ip6tables -t mangle -A V2RAY -p tcp -m multiport --sports $SETUP_WITH_INTERNAL_SERVICE_PORT -j RETURN
ip6tables -t mangle -A V2RAY -p udp -m multiport --sports $SETUP_WITH_INTERNAL_SERVICE_PORT -j RETURN
if [ $SETUP_WITH_DEBUG_LOG -ne 0 ]; then
    ip6tables -t mangle -A V2RAY -p tcp -m multiport ! --dports $SETUP_WITH_INTERNAL_SERVICE_PORT -j LOG --log-level debug --log-prefix "###TCP6#PREROU:"
fi

### ipv6 - skip link-locak and multicast
ip6tables -t mangle -A V2RAY -d ::1/128,fc00::/7,fe80::/10,ff00::/8 -j RETURN
ip6tables -t mangle -A V2RAY -m mark --mark 0xff -j RETURN
### ipv6 - skip private network and UDP of DNS
# if dns service and V2RAY are on different server, use rules below
# ip6tables -t mangle -A V2RAY -p tcp -d ::1/128,fc00::/7,fe80::/10,ff00::/8 -j RETURN
# ip6tables -t mangle -A V2RAY -p udp -d ::1/128,fc00::/7,fe80::/10,ff00::/8 ! --dport 53 -j RETURN
# ip6tables -t mangle -A V2RAY -p tcp -d $GATEWAY_ADDRESSES -j RETURN

# ipv6 skip package from outside
ip6tables -t mangle -A V2RAY -p tcp -m set --match-set V2RAY_BLACKLIST_IPV6 dst -j RETURN
ip6tables -t mangle -A V2RAY -p udp -m set --match-set V2RAY_BLACKLIST_IPV6 dst -j RETURN
### ipv6 - forward to v2ray's listen address if not marked by v2ray
# tproxy ip to $V2RAY_HOST_IPV4:$V2RAY_PORT
if [ $SETUP_WITH_DEBUG_LOG -ne 0 ]; then
    ip6tables -t mangle -A V2RAY -p tcp -m multiport ! --dports $SETUP_WITH_INTERNAL_SERVICE_PORT -j TRACE
    ip6tables -t mangle -A V2RAY -p tcp -m multiport ! --dports $SETUP_WITH_INTERNAL_SERVICE_PORT LOG --log-level debug --log-prefix ">>>TCP6>tproxy:"
fi

ip6tables -t mangle -A V2RAY -p tcp -j TPROXY --on-port $V2RAY_PORT --tproxy-mark 1 # mark tcp package with 1 and forward to $V2RAY_PORT
ip6tables -t mangle -A V2RAY -p udp -j TPROXY --on-port $V2RAY_PORT --tproxy-mark 1 # mark tcp package with 1 and forward to $V2RAY_PORT
ip6tables -t mangle -D PREROUTING -j V2RAY > /dev/null 2>&1 ;
while [ $? -eq 0 ]; do
    ip6tables -t mangle -D PREROUTING -j V2RAY > /dev/null 2>&1;
done
ip6tables -t mangle -A PREROUTING -j V2RAY # apply rules

# Setup - ipv6 local
### ipv6 - skip internal services
ip6tables -t mangle -A V2RAY_MASK -p tcp -m multiport --sports $SETUP_WITH_INTERNAL_SERVICE_PORT -j RETURN
ip6tables -t mangle -A V2RAY_MASK -p udp -m multiport --sports $SETUP_WITH_INTERNAL_SERVICE_PORT -j RETURN
if [ $SETUP_WITH_DEBUG_LOG -ne 0 ]; then
    ip6tables -t mangle -A V2RAY_MASK -p tcp -m multiport ! --dports $SETUP_WITH_INTERNAL_SERVICE_PORT LOG --log-level debug --log-prefix "###TCP6#OUTPUT:"
fi

ip6tables -t mangle -A V2RAY_MASK -d ::1/128,fc00::/7,fe80::/10,ff00::/8 -j RETURN
ip6tables -t mangle -A V2RAY_MASK -m mark --mark 0xff -j RETURN
### ipv6 - skip private network and UDP of DNS
# if dns service and V2RAY_MASK are on different server, use rules below
# ip6tables -t mangle -A V2RAY_MASK -p tcp -d ::1/128,fc00::/7,fe80::/10,ff00::/8 -j RETURN
# ip6tables -t mangle -A V2RAY_MASK -p udp -d ::1/128,fc00::/7,fe80::/10,ff00::/8 ! --dport 53 -j RETURN
# ip6tables -t mangle -A V2RAY_MASK -p tcp -d $GATEWAY_ADDRESSES -j RETURN

if [ $SETUP_WITH_DEBUG_LOG -ne 0 ]; then
    ip6tables -t mangle -A V2RAY_MASK -p tcp -m multiport ! --dports $SETUP_WITH_INTERNAL_SERVICE_PORT -j TRACE
    ip6tables -t mangle -A V2RAY_MASK -p tcp -m multiport ! --dports $SETUP_WITH_INTERNAL_SERVICE_PORT LOG --log-level debug --log-prefix "+++TCP6+mark 1:"
fi
# ipv6 skip package from outside
ip6tables -t mangle -A V2RAY_MASK -p udp -j MARK --set-mark 1
ip6tables -t mangle -A V2RAY_MASK -p tcp -j MARK --set-mark 1

ip6tables -t mangle -D OUTPUT -j V2RAY_MASK > /dev/null 2>&1 ;
while [ $? -eq 0 ]; do
    ip6tables -t mangle -D OUTPUT -j V2RAY_MASK > /dev/null 2>&1;
done
ip6tables -t mangle -A OUTPUT -j V2RAY_MASK # apply rules


## Setup - bridge
ebtables -t broute -L V2RAY_BRIDGE > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    ebtables -t broute -N V2RAY_BRIDGE ;
else
    ebtables -t broute -F V2RAY_BRIDGE ;
fi

for SKIP_PORT in $(echo $SETUP_WITH_INTERNAL_SERVICE_PORT | sed 's/,/ /g'); do
    ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-proto tcp --ip-sport $SKIP_PORT -j RETURN
    ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-proto udp --ip-sport $SKIP_PORT -j RETURN
    ebtables -t broute -A V2RAY_BRIDGE -p ipv6 --ip6-proto tcp --ip6-sport $SKIP_PORT -j RETURN
    ebtables -t broute -A V2RAY_BRIDGE -p ipv6 --ip6-proto udp --ip6-sport $SKIP_PORT -j RETURN
done


### bridge - skip link-local and broadcast address
ebtables -t broute -A V2RAY_BRIDGE --mark 0xff -j RETURN
ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-dst 127.0.0.1/32 -j RETURN
ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-dst 224.0.0.0/4 -j RETURN
ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-dst 255.255.255.255/32 -j RETURN
ebtables -t broute -A V2RAY_BRIDGE -p ipv6 --ip6-dst ::1/128 -j RETURN
ebtables -t broute -A V2RAY_BRIDGE -p ipv6 --ip6-dst fc00::/7 -j RETURN
ebtables -t broute -A V2RAY_BRIDGE -p ipv6 --ip6-dst fe80::/10 -j RETURN
ebtables -t broute -A V2RAY_BRIDGE -p ipv6 --ip6-dst ff00::/8 -j RETURN

### bridge - skip private network and UDP of DNS
ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-dst 192.168.0.0/16 -j RETURN
ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-dst 172.16.0.0/12 -j RETURN
ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-dst 10.0.0.0/8 -j RETURN

if [ $SETUP_WITH_DEBUG_LOG -ne 0 ]; then
    ebtables -t broute -A V2RAY_BRIDGE --log-ip --log-level debug --log-prefix "---BRIDGE-DROP: "
fi

### ipv4 - forward to v2ray's listen address if not marked by v2ray
# tproxy ip to $V2RAY_HOST_IPV4:$V2RAY_PORT
ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-proto tcp -j redirect --redirect-target DROP
ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-proto udp -j redirect --redirect-target DROP
ebtables -t broute -A V2RAY_BRIDGE -p ipv6 --ip6-proto tcp -j redirect --redirect-target DROP
ebtables -t broute -A V2RAY_BRIDGE -p ipv6 --ip6-proto udp -j redirect --redirect-target DROP

ebtables -t broute -D BROUTING -j V2RAY_BRIDGE > /dev/null 2>&1 ;
while [ $? -eq 0 ]; do
    ebtables -t broute -D BROUTING -j V2RAY_BRIDGE > /dev/null 2>&1;
done
ebtables -t broute -A BROUTING -j V2RAY_BRIDGE
