#!/bin/bash

PPP_DEVICE=($(nmcli --fields=DEVICE,TYPE d status | awk '$2 == "ppp"{print $1}'))
BRIDGE_DEVICE=($(nmcli --fields=DEVICE,TYPE d status | awk '$2 == "bridge"{print $1}'))
ETC_DIR="/etc"
ENABLE_IPV5_NDPP_AND_RA=0

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
  IgnoreIfMissing on;
  AdvSendAdvert on;
  #AdvDefaultPreference low;
  #AdvSourceLLAddress off;
";
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
    # Base6Interface $CURRENT_PPP_DEVICE;
  };"
      ENABLE_IPV5_NDPP_AND_RA=1
    done
  done
  RADVD_CFG="$RADVD_CFG
  RDNSS $(ip -o -6 addr show dev $CURRENT_BRIDGE_DEVICE | awk 'match($0, /inet6\s+([0-9a-fA-F:]+)/, ip) { print ip[1] }' | xargs -r echo)
  {
  };
};";
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
      # Add prefix route to route table
      echo "Ignore: ip -6 route add $IPV6_ADDR_PREFIX::/$IPV6_ADDR_BR_SUFFIX dev $CURRENT_BRIDGE_DEVICE"
    done
  NDPPD_CFG="$NDPPD_CFG
}";
  done
done

for CURRENT_PPP_DEVICE in ${PPP_DEVICE[@]}; do
  # Delete prefix route from route table
  echo "Please disable temporary address, Ignore automatically obtained routes and Ignore automatically obtained DNS parameters for this $CURRENT_PPP_DEVICE"
  for OLD_ROUTE in $(ip -6 route | grep -v -E '^(default|[a-zA-Z0-9:]:/0)' | grep -E "dev[[:space:]]+$CURRENT_PPP_DEVICE" | awk '{print $1}'); do
    echo "Run: ip -6 route delete $OLD_ROUTE dev $CURRENT_PPP_DEVICE"
    ip -6 route delete $OLD_ROUTE dev $CURRENT_PPP_DEVICE
  done
  for IPV6_ADDR in $(ip -o -6 addr show dev $CURRENT_PPP_DEVICE | awk 'match($0, /inet6\s+([0-9a-fA-F:]+(\/[0-9]+)?)/, ip) { print ip[1] }'); do
    # Add address route to route table
    echo "Run: ip -6 route add ${IPV6_ADDR%%/*} dev $CURRENT_PPP_DEVICE"
    ip -6 route add ${IPV6_ADDR%%/*} dev $CURRENT_PPP_DEVICE
  done
done

echo "====== RADVD_CFG=$ETC_DIR/radvd.conf====== "
echo "$RADVD_CFG" | tee $ETC_DIR/radvd.conf
echo "====== NDPPD_CFG=$ETC_DIR/ndppd.conf====== "
echo "$NDPPD_CFG" | tee $ETC_DIR/ndppd.conf

if [[ $ENABLE_IPV5_NDPP_AND_RA -ne 0 ]] ; then
  systemctl enable radvd
  systemctl restart radvd
  systemctl enable ndppd
  systemctl restart ndppd
else
  systemctl disable radvd
  systemctl stop radvd
  systemctl disable ndppd
  systemctl stop ndppd
fi
