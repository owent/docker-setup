#!/bin/bash


echo "
noauth
refuse-eap
user '<PPPOE USERNAME>'
password '<PPPOE PASSWORD>'
nomppe nomppc
plugin rp-pppoe.so nic-eth0
mru 1492 mtu 1492
persist
holdoff 10
maxfail 0
usepeerdns
ipcp-accept-remote ipcp-accept-local noipdefault
ktune
default-asyncmap nopcomp noaccomp
novj nobsdcomp nodeflate
lcp-echo-interval 30
lcp-echo-failure 3
lcp-echo-adaptive
unit 0
linkname wan0
+ipv6
"