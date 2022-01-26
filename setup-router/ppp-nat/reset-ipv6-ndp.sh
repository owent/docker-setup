#!/bin/bash

PPP_DEVICE=($(nmcli --fields=DEVICE,TYPE d status | awk '$2 == "ppp"{print $1}'))
BRIDGE_DEVICE=($(nmcli --fields=DEVICE,TYPE d status | awk '$2 == "bridge"{print $1}'))
ETC_DIR="/etc"
ENABLE_IPV5_NDPP_AND_RA=0

if [[ "x" == "x$ETC_DIR" ]]; then
  ETC_DIR=250
fi

if [[ "x" == "x$ROUTE_TABLE_ID" ]]; then
  ROUTE_TABLE_ID=250
fi

if [[ "x" == "x$SETUP_NDPP_RULE_PRIORITY" ]]; then
  SETUP_NDPP_RULE_PRIORITY=5001
fi

# for CURRENT_BRIDGE_DEVICE in ${BRIDGE_DEVICE[@]}; do
#   for old_ipv6_address in $(ip -o -6 addr show dev $CURRENT_BRIDGE_DEVICE scope global | awk 'match($0, /inet6\s+([0-9a-fA-F:]+(\/[0-9]+)?)/, ip) { print ip[1] }'); do
#     ip -6 addr del "$old_ipv6_address" dev $CURRENT_BRIDGE_DEVICE
#   done
# done

NDPPD_CFG=""
RADVD_CFG=""
ip -6 route flush table $ROUTE_TABLE_ID

for CURRENT_BRIDGE_DEVICE in ${BRIDGE_DEVICE[@]}; do
  RADVD_CFG="$RADVD_CFG
interface $CURRENT_BRIDGE_DEVICE
{
  IgnoreIfMissing on;
  AdvSendAdvert on;
  #AdvDefaultPreference low;
  #AdvSourceLLAddress off;
"
  for CURRENT_PPP_DEVICE in ${PPP_DEVICE[@]}; do
    for IPV6_ADDR in $(ip -o -6 addr show dev $CURRENT_PPP_DEVICE scope global | awk 'match($0, /inet6\s+([0-9a-fA-F:]+(\/[0-9]+)?)/, ip) { print ip[1] }'); do
      IPV6_ADDR_SUFFIX=$(echo "$IPV6_ADDR" | grep -o -E '[0-9]+$')
      if [[ $IPV6_ADDR_SUFFIX -lt 64 ]]; then
        let IPV6_ADDR_BR_SUFFIX=64
      else
        let IPV6_ADDR_BR_SUFFIX=$IPV6_ADDR_SUFFIX
      fi
      IPV6_ADDR_PREFIX=""
      for IPV6_ADDR_PREFIX_SEGMENT in ${IPV6_ADDR//:/ }; do
        if [[ $IPV6_ADDR_SUFFIX -le 0 ]]; then
          break
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
    # Base6Interface $CURRENT_PPP_DEVICE;
  };"
      ENABLE_IPV5_NDPP_AND_RA=1
    done
  done

  CURRENT_BRIDGE_IPV6=()
  RETRY_TIME=0
  while [[ $RETRY_TIME -lt 12 ]]; do
    let RETRY_TIME=$RETRY_TIME+1
    echo "$CURRENT_BRIDGE_DEVICE : $RETRY_TIME times to get ipv6 address"
    ip -o -6 addr show dev $CURRENT_BRIDGE_DEVICE
    CURRENT_BRIDGE_IPV6=($(ip -o -6 addr show dev $CURRENT_BRIDGE_DEVICE | awk 'match($0, /inet6\s+([0-9a-fA-F:]+)/, ip) { print ip[1] }'))
    if [[ ${#CURRENT_BRIDGE_IPV6[@]} -gt 0 ]]; then
      break
    fi
    sleep 20 || usleep 20000000
  done

  RADVD_CFG="$RADVD_CFG
  RDNSS ${CURRENT_BRIDGE_IPV6[@]}
  {
  };
};"
done

for CURRENT_PPP_DEVICE in ${PPP_DEVICE[@]}; do
  for IPV6_ADDR in $(ip -o -6 addr show dev $CURRENT_PPP_DEVICE scope global | awk 'match($0, /inet6\s+([0-9a-fA-F:]+(\/[0-9]+)?)/, ip) { print ip[1] }'); do
    IPV6_ADDR_SUFFIX=$(echo "$IPV6_ADDR" | grep -o -E '[0-9]+$')
    if [[ $IPV6_ADDR_SUFFIX -lt 64 ]]; then
      let IPV6_ADDR_BR_SUFFIX=64
    else
      let IPV6_ADDR_BR_SUFFIX=$IPV6_ADDR_SUFFIX
    fi
    IPV6_ADDR_PREFIX=""
    for IPV6_ADDR_PREFIX_SEGMENT in ${IPV6_ADDR//:/ }; do
      if [[ $IPV6_ADDR_SUFFIX -le 0 ]]; then
        break
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
"
      # Add prefix route to route table
      echo "Run: ip -6 route add $IPV6_ADDR_PREFIX::/$IPV6_ADDR_BR_SUFFIX dev $CURRENT_BRIDGE_DEVICE table $ROUTE_TABLE_ID"
      ip -6 route add $IPV6_ADDR_PREFIX::/$IPV6_ADDR_BR_SUFFIX dev $CURRENT_BRIDGE_DEVICE table $ROUTE_TABLE_ID
    done
    NDPPD_CFG="$NDPPD_CFG
}"
  done
done

echo "====== RADVD_CFG=$ETC_DIR/radvd.conf====== "
echo "$RADVD_CFG" | tee $ETC_DIR/radvd.conf
echo "====== NDPPD_CFG=$ETC_DIR/ndppd.conf====== "
echo "$NDPPD_CFG" | tee $ETC_DIR/ndppd.conf

set -x
if [[ $ENABLE_IPV5_NDPP_AND_RA -ne 0 ]]; then
  ip -6 rule add priority $SETUP_NDPP_RULE_PRIORITY lookup $ROUTE_TABLE_ID
  systemctl enable radvd
  systemctl restart radvd
  systemctl enable ndppd
  systemctl restart ndppd
else
  ip -6 rule del priority $SETUP_NDPP_RULE_PRIORITY lookup $ROUTE_TABLE_ID
  systemctl disable radvd
  systemctl stop radvd
  systemctl disable ndppd
  systemctl stop ndppd
fi
