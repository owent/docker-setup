#!/bin/bash

PPP_DEVICE=($(nmcli --fields=DEVICE,TYPE d status | awk '$2 == "ppp"{print $1}'))
BRIDGE_DEVICE=($(nmcli --fields=DEVICE,TYPE d status | awk '$2 == "bridge"{print $1}'))
ETC_DIR="/etc"
ENABLE_IPV6_NDPP_AND_RA=0

if [[ "x" == "x$ETC_DIR" ]]; then
  ETC_DIR=250
fi

# Local route
if [[ "x" == "x$LOCAL_ROUTE_TABLE_ID" ]]; then
  LOCAL_ROUTE_TABLE_ID=250
fi

if [[ "x" == "x$LOCAL_ROUTE_RULE_PRIORITY" ]]; then
  LOCAL_ROUTE_RULE_PRIORITY=5001
fi

# For mwan
if [[ "x" == "x$MWAN_DEFAULT_ROUTE_RULE_PRIORITY" ]]; then
  MWAN_DEFAULT_ROUTE_RULE_PRIORITY=32701
fi
if [[ "x" == "x$MWAN_DEFAULT_ROUTE_TABLE_ID" ]]; then
  MWAN_DEFAULT_ROUTE_TABLE_ID=251
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
      ENABLE_IPV6_NDPP_AND_RA=1
    done
  done

  CURRENT_BRIDGE_IPV6=()
  RETRY_TIME=0
  while [[ $RETRY_TIME -lt 12 ]]; do
    let RETRY_TIME=$RETRY_TIME+1
    echo "$CURRENT_BRIDGE_DEVICE : $RETRY_TIME times to get ipv6 address"
    ip -o -6 addr show dev $CURRENT_BRIDGE_DEVICE
    CURRENT_BRIDGE_IPV6=($(ip -o -6 addr show dev $CURRENT_BRIDGE_DEVICE | awk 'match($0, /inet6\s+([0-9a-fA-F:]+)/, ip) { print ip[1] }' | tail -n 3))
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

# For mwan
# Cleanup default route rule
PPP_IPV6_MWAN_LOOPUP_TABLE=$(ip -6 rule show lookup $MWAN_DEFAULT_ROUTE_TABLE_ID | awk 'END {print NF}')
while [[ 0 -ne $PPP_IPV6_MWAN_LOOPUP_TABLE ]]; do
  ip -6 rule delete lookup $MWAN_DEFAULT_ROUTE_TABLE_ID
  PPP_IPV6_MWAN_LOOPUP_TABLE=$(ip -6 rule show lookup $MWAN_DEFAULT_ROUTE_TABLE_ID | awk 'END {print NF}')
done
# Cleanup default route table
ip -6 route flush table $MWAN_DEFAULT_ROUTE_TABLE_ID
PPP_IPV6_MWAN_LOOPUP_RULE_SETUP=0

for CURRENT_PPP_DEVICE in ${PPP_DEVICE[@]}; do
  if [[ ${#PPP_DEVICE[@]} -gt 1 ]]; then
    for IPV6_ADDR in $(ip -o -6 addr show dev $CURRENT_PPP_DEVICE | awk 'match($0, /inet6\s+([0-9a-fA-F:]+(\/[0-9]+)?)/, ip) { print ip[1] }'); do
      # Setup ip rule
      if [[ 0 -eq $PPP_IPV6_MWAN_LOOPUP_RULE_SETUP ]]; then
        ip -6 rule add priority $MWAN_DEFAULT_ROUTE_RULE_PRIORITY lookup $MWAN_DEFAULT_ROUTE_TABLE_ID
        PPP_IPV6_MWAN_LOOPUP_RULE_SETUP=1
      fi

      CURRENT_DEFAULT_ROUTE_VIA_IP="$(ip -6 route show default dev $CURRENT_PPP_DEVICE | awk 'match($0, /via\s+([0-9a-fA-F:]+(\/[0-9]+)?)/, ip) { print ip[1] }')"
      if [[ "X$CURRENT_DEFAULT_ROUTE_VIA_IP" == "x" ]]; then
        continue
      fi
      IPV6_ADDR_SUFFIX=$(echo "$IPV6_ADDR" | awk '{if(match($0, /\/([0-9]+)/, suffix)) { print suffix[1]; } else { print 128; } }')
      if [[ $IPV6_ADDR_SUFFIX -ge 128 ]]; then
        echo "Run: ip -6 route add default via "$CURRENT_DEFAULT_ROUTE_VIA_IP" from "$IPV6_ADDR" dev $CURRENT_PPP_DEVICE table $MWAN_DEFAULT_ROUTE_TABLE_ID"
        ip -6 route add default via "$CURRENT_DEFAULT_ROUTE_VIA_IP" from "$IPV6_ADDR" dev $CURRENT_PPP_DEVICE table $MWAN_DEFAULT_ROUTE_TABLE_ID
      else
        IPV6_ADDR_PREFIX=""
        let IPV6_ADDR_BR_SUFFIX=$IPV6_ADDR_SUFFIX
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
        echo "Run: ip -6 route add default via "$CURRENT_DEFAULT_ROUTE_VIA_IP" from "$IPV6_ADDR_PREFIX::/$IPV6_ADDR_BR_SUFFIX" dev $CURRENT_PPP_DEVICE table $MWAN_DEFAULT_ROUTE_TABLE_ID"
        ip -6 route add default via "$CURRENT_DEFAULT_ROUTE_VIA_IP" from "$IPV6_ADDR_PREFIX::/$IPV6_ADDR_BR_SUFFIX" dev $CURRENT_PPP_DEVICE table $MWAN_DEFAULT_ROUTE_TABLE_ID
      fi
    done
  fi

  for IPV6_ADDR in $(ip -o -6 addr show dev $CURRENT_PPP_DEVICE scope global | awk 'match($0, /inet6\s+([0-9a-fA-F:]+(\/[0-9]+)?)/, ip) { print ip[1] }'); do
    IPV6_ADDR_SUFFIX=$(echo "$IPV6_ADDR" | awk '{if(match($0, /\/([0-9]+)/, suffix)) { print suffix[1]; } else { print 128; } }')
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
      # Change prefix route to route table
      echo "Run: ip -6 route add $IPV6_ADDR_PREFIX::/$IPV6_ADDR_BR_SUFFIX dev $CURRENT_BRIDGE_DEVICE table $LOCAL_ROUTE_TABLE_ID"
      ip -6 route add "$IPV6_ADDR_PREFIX::/$IPV6_ADDR_BR_SUFFIX" dev $CURRENT_BRIDGE_DEVICE table $LOCAL_ROUTE_TABLE_ID
    done
    NDPPD_CFG="$NDPPD_CFG
}"
    # Add specify route to route table
    echo "Run: ip -6 route add $IPV6_ADDR dev $CURRENT_PPP_DEVICE table $LOCAL_ROUTE_TABLE_ID"
    ip -6 route add $IPV6_ADDR dev $CURRENT_PPP_DEVICE table $LOCAL_ROUTE_TABLE_ID
  done
done

echo "====== RADVD_CFG=$ETC_DIR/radvd.conf====== "
echo "$RADVD_CFG" | tee $ETC_DIR/radvd.conf
echo "====== NDPPD_CFG=$ETC_DIR/ndppd.conf====== "
echo "$NDPPD_CFG" | tee $ETC_DIR/ndppd.conf

set -x
if [[ $ENABLE_IPV6_NDPP_AND_RA -ne 0 ]]; then
  ip -6 rule add priority $LOCAL_ROUTE_RULE_PRIORITY lookup $LOCAL_ROUTE_TABLE_ID
  systemctl enable radvd
  systemctl restart radvd
  systemctl enable ndppd
  systemctl restart ndppd
else
  ip -6 rule del priority $LOCAL_ROUTE_RULE_PRIORITY lookup $LOCAL_ROUTE_TABLE_ID
  systemctl disable radvd
  systemctl stop radvd
  systemctl disable ndppd
  systemctl stop ndppd
fi
