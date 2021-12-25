#!/bin/bash

PPP_DEVICE=($(nmcli --fields=DEVICE,TYPE d status | awk '$2 == "ppp"{print $1}'))
BRIDGE_DEVICE=($(nmcli --fields=DEVICE,TYPE d status | awk '$2 == "bridge"{print $1}'))
ETC_DIR="/etc"
BRIDGE_IPV6_TAIL="010a"

# for CURRENT_BRIDGE_DEVICE in ${BRIDGE_DEVICE[@]}; do
#   for old_ipv6_address in $(ip -o -6 addr show dev $CURRENT_BRIDGE_DEVICE scope global | awk 'match($0, /inet6\s+([0-9a-fA-F:]+(\/[0-9]+)?)/, ip) { print ip[1] }'); do
#     ip -6 addr del "$old_ipv6_address" dev $CURRENT_BRIDGE_DEVICE
#   done
# done

NDPPD_CFG=""
RADVD_CFG=""

for CURRENT_BRIDGE_DEVICE in ${BRIDGE_DEVICE[@]}; do
  RADVD_CFG="$RADVD_CFG
interface $CURRENT_BRIDGE_DEVICE
{
  AdvSendAdvert on;
  AdvDefaultPreference low;
";
  for CURRENT_PPP_DEVICE in ${PPP_DEVICE[@]}; do
    IPV6_ADDR="$(ip -o -6 addr show dev $CURRENT_PPP_DEVICE scope global | awk 'match($0, /inet6\s+([0-9a-fA-F:]+(\/[0-9]+)?)/, ip) { print ip[1] }' | head -n 1)";
    IPV6_ADDR_SUFFIX=$(echo "$IPV6_ADDR" | grep -o -E '[0-9]+$')
    let IPV6_ADDR_BR_SUFFIX=$IPV6_ADDR_SUFFIX+8
    IPV6_ADDR_PREFIX=""
    for IPV6_ADDR_PREFIX_SEGMENT in ${IPV6_ADDR//:/ }; do
      if [[ $IPV6_ADDR_SUFFIX -le 0 ]]; then
        break;
      fi
      if [[ -z "$IPV6_ADDR_PREFIX" ]]; then
        IPV6_ADDR_PREFIX="$IPV6_ADDR_PREFIX_SEGMENT"
      else
        IPV6_ADDR_PREFIX="$IPV6_ADDR_PREFIX:$IPV6_ADDR_PREFIX_SEGMENT"
      fi
      let IPV6_ADDR_SUFFIX=$IPV6_ADDR_SUFFIX-16
    done
    RADVD_CFG="$RADVD_CFG
  prefix $IPV6_ADDR_PREFIX::/$IPV6_ADDR_BR_SUFFIX
  {
    AdvOnLink on;
    AdvAutonomous on;
    AdvRouterAddr off;
    Base6Interface $CURRENT_PPP_DEVICE;
  };"
  done
  RADVD_CFG="$RADVD_CFG
};";
done

for CURRENT_PPP_DEVICE in ${PPP_DEVICE[@]}; do
  IPV6_ADDR="$(ip -o -6 addr show dev $CURRENT_PPP_DEVICE scope global | awk 'match($0, /inet6\s+([0-9a-fA-F:]+(\/[0-9]+)?)/, ip) { print ip[1] }' | head -n 1)";
  IPV6_ADDR_SUFFIX=$(echo "$IPV6_ADDR" | grep -o -E '[0-9]+$')
  let IPV6_ADDR_BR_SUFFIX=$IPV6_ADDR_SUFFIX+8
  IPV6_ADDR_PREFIX=""
  for IPV6_ADDR_PREFIX_SEGMENT in ${IPV6_ADDR//:/ }; do
    if [[ $IPV6_ADDR_SUFFIX -le 0 ]]; then
      break;
    fi
    if [[ -z "$IPV6_ADDR_PREFIX" ]]; then
      IPV6_ADDR_PREFIX="$IPV6_ADDR_PREFIX_SEGMENT"
    else
      IPV6_ADDR_PREFIX="$IPV6_ADDR_PREFIX:$IPV6_ADDR_PREFIX_SEGMENT"
    fi
    let IPV6_ADDR_SUFFIX=$IPV6_ADDR_SUFFIX-16
  done
  NDPPD_CFG="$NDPPD_CFG
proxy $CURRENT_PPP_DEVICE {
  autowire yes
  "
  for CURRENT_BRIDGE_DEVICE in ${BRIDGE_DEVICE[@]}; do
    NDPPD_CFG="$NDPPD_CFG
  rule $IPV6_ADDR_PREFIX::/$IPV6_ADDR_BR_SUFFIX {
    iface $CURRENT_BRIDGE_DEVICE
  }
";
  done
  NDPPD_CFG="$NDPPD_CFG
}";
done

echo "====== RADVD_CFG=$ETC_DIR/radvd.conf====== "
echo "$RADVD_CFG"
echo "====== NDPPD_CFG=$ETC_DIR/ndppd.conf====== "
echo "$NDPPD_CFG"
