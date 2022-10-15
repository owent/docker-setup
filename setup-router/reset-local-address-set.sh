#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/configure-router.sh"

while getopts "hi:n:" OPTION; do
  case $OPTION in
    h)
      echo "usage: $0 [options] "
      echo "options:"
      echo "-h                            help message."
      echo "-i [ipset prefix]             "
      echo "-n [table name of nftable]    "
      exit 0
      ;;
    i)
      ROUTER_NET_LOCAL_IPSET_PREFIX=$OPTARG
      ;;
    n)
      ROUTER_NET_LOCAL_NFTABLE_NAME=$OPTARG
      ;;
    ?)
      break
      ;;
  esac
done

ROUTER_LOCAL_NET_IPV4=(
  "169.254.0.0/16" "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16"
  $(ip -o -4 addr | awk 'match($0, /inet\s+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(\/[0-9]+)?)/, ip) { print ip[1] }')
  $(ip -o -4 addr | awk 'match($0, /peer\s+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(\/[0-9]+)?)/, ip) { print ip[1] }')
)

ROUTER_LOCAL_NET_IPV6=(
  "fe80::/10" "fc00::/7"
  $(ip -o -6 addr | awk 'match($0, /inet6\s+([0-9a-fA-F:]+(\/[0-9]+)?)/, ip) { print ip[1] }')
  $(ip -o -6 addr | awk 'match($0, /peer\s+([0-9a-fA-F:]+(\/[0-9]+)?)/, ip) { print ip[1] }')
)

ROUTER_DEFAULT_ROUTE_IPV4=()
ROUTER_DEFAULT_ROUTE_DEVICE=(
  $(ip -o -4 route show exact default | awk 'match($0, /dev\s+([^[:space:]]+)/, ip) { print ip[1] }')
)
for IPV4_DEVIDE in ${ROUTER_DEFAULT_ROUTE_DEVICE[@]}; do
  ROUTER_DEFAULT_ROUTE_IPV4=(
    ${ROUTER_DEFAULT_ROUTE_IPV4[@]}
    $(ip -o -4 addr show dev $IPV4_DEVIDE | awk 'match($0, /inet\s+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(\/[0-9]+)?)/, ip) { print ip[1] }')
  )
done
ROUTER_DEFAULT_ROUTE_IPV6=()
ROUTER_DEFAULT_ROUTE_DEVICE=(
  $(ip -o -6 route show exact default | awk 'match($0, /dev\s+([^[:space:]]+)/, ip) { print ip[1] }')
)
for IPV6_DEVIDE in ${ROUTER_DEFAULT_ROUTE_DEVICE[@]}; do
  ROUTER_DEFAULT_ROUTE_IPV6=(
    ${ROUTER_DEFAULT_ROUTE_IPV6[@]}
    $(ip -o -6 addr show dev $IPV6_DEVIDE | awk 'match($0, /inet6\s+([0-9a-fA-F:]+(\/[0-9]+)?)/, ip) { print ip[1] }')
  )
done

# ipset
if [[ "x$ROUTER_NET_LOCAL_IPSET_PREFIX" != "x" ]]; then
  ipset list "${IPSET_NAME}_LOCAL_IPV4" >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    ipset create "${IPSET_NAME}_LOCAL_IPV4" hash:net family inet
  else
    ipset flush "${IPSET_NAME}_LOCAL_IPV4"
  fi

  ipset list "${IPSET_NAME}_LOCAL_IPV6" >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    ipset create "${IPSET_NAME}_LOCAL_IPV6" hash:net family inet6
  else
    ipset flush "${IPSET_NAME}_LOCAL_IPV6"
  fi

  ipset list "${IPSET_NAME}_DEFAULT_ROUTE_IPV4" >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    ipset create "${IPSET_NAME}_DEFAULT_ROUTE_IPV4" hash:net family inet
  else
    ipset flush "${IPSET_NAME}_DEFAULT_ROUTE_IPV4"
  fi

  ipset list "${IPSET_NAME}_DEFAULT_ROUTE_IPV6" >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    ipset create "${IPSET_NAME}_DEFAULT_ROUTE_IPV6" hash:net family inet6
  else
    ipset flush "${IPSET_NAME}_DEFAULT_ROUTE_IPV6"
  fi

  for IPSET_NAME in ${ROUTER_NET_LOCAL_IPSET_PREFIX//,/ }; do
    for IP_ADDR in ${ROUTER_LOCAL_NET_IPV4[@]}; do
      ipset add "${IPSET_NAME}_LOCAL_IPV4" "$IP_ADDR"
    done

    for IP_ADDR in ${ROUTER_LOCAL_NET_IPV6[@]}; do
      ipset add "${IPSET_NAME}_LOCAL_IPV6" "$IP_ADDR"
    done

    for IP_ADDR in ${ROUTER_DEFAULT_ROUTE_IPV4[@]}; do
      ipset add "${IPSET_NAME}_DEFAULT_ROUTE_IPV4" "$IP_ADDR"
    done

    for IP_ADDR in ${ROUTER_DEFAULT_ROUTE_IPV6[@]}; do
      ipset add "${IPSET_NAME}_DEFAULT_ROUTE_IPV6" "$IP_ADDR"
    done
  done
fi

# nftables
function nftables_reset_local_address_ipv4() {
  FAMILY_NAME="$1"
  TABLE_NAME="$2"

  nft list table $FAMILY_NAME "$TABLE_NAME" >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add table $FAMILY_NAME "$TABLE_NAME"
  fi

  nft list set $FAMILY_NAME "$TABLE_NAME" LOCAL_IPV4 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set $FAMILY_NAME "$TABLE_NAME" LOCAL_IPV4 '{ type ipv4_addr; flags interval; auto-merge ; }'
  else
    nft flush set $FAMILY_NAME "$TABLE_NAME" LOCAL_IPV4
  fi

  for IP_ADDR in ${ROUTER_LOCAL_NET_IPV4[@]}; do
    nft add element $FAMILY_NAME "$TABLE_NAME" LOCAL_IPV4 "{ $IP_ADDR }"
  done

  nft list set $FAMILY_NAME "$TABLE_NAME" DEFAULT_ROUTE_IPV4 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set $FAMILY_NAME "$TABLE_NAME" DEFAULT_ROUTE_IPV4 '{ type ipv4_addr; flags interval; auto-merge ; }'
  else
    nft flush set $FAMILY_NAME "$TABLE_NAME" DEFAULT_ROUTE_IPV4
  fi

  for IP_ADDR in ${ROUTER_DEFAULT_ROUTE_IPV4[@]}; do
    nft add element $FAMILY_NAME "$TABLE_NAME" DEFAULT_ROUTE_IPV4 "{ $IP_ADDR }"
  done
}

function nftables_reset_local_address_ipv6() {
  FAMILY_NAME="$1"
  TABLE_NAME="$2"

  nft list table $FAMILY_NAME "$TABLE_NAME" >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add table $FAMILY_NAME "$TABLE_NAME"
  fi

  nft list set $FAMILY_NAME "$TABLE_NAME" LOCAL_IPV6 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set $FAMILY_NAME "$TABLE_NAME" LOCAL_IPV6 '{ type ipv6_addr; flags interval; auto-merge ; }'
  else
    nft flush set $FAMILY_NAME "$TABLE_NAME" LOCAL_IPV6
  fi

  for IP_ADDR in ${ROUTER_LOCAL_NET_IPV6[@]}; do
    nft add element $FAMILY_NAME "$TABLE_NAME" LOCAL_IPV6 "{ $IP_ADDR }"
  done

  nft list set $FAMILY_NAME "$TABLE_NAME" DEFAULT_ROUTE_IPV6 >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    nft add set $FAMILY_NAME "$TABLE_NAME" DEFAULT_ROUTE_IPV6 '{ type ipv6_addr; flags interval; auto-merge ; }'
  else
    nft flush set $FAMILY_NAME "$TABLE_NAME" DEFAULT_ROUTE_IPV6
  fi

  for IP_ADDR in ${ROUTER_DEFAULT_ROUTE_IPV6[@]}; do
    nft add element $FAMILY_NAME "$TABLE_NAME" DEFAULT_ROUTE_IPV6 "{ $IP_ADDR }"
  done
}

if [[ "x$ROUTER_NET_LOCAL_NFTABLE_NAME" != "x" ]]; then
  for TABLE_NAME_ORIGIN in ${ROUTER_NET_LOCAL_NFTABLE_NAME//,/ }; do
    TABLE_NAME="${TABLE_NAME_ORIGIN%%:*}"
    if [[ ! "$TABLE_NAME_ORIGIN" =~ ":" ]]; then
      SELECT_ALL_FAMILY_NAME=1
    else
      SELECT_ALL_FAMILY_NAME=0
    fi
    if [[ $SELECT_ALL_FAMILY_NAME -eq 1 ]] || [[ "$TABLE_NAME_ORIGIN" =~ :ip(:|$) ]]; then
      nftables_reset_local_address_ipv4 ip "$TABLE_NAME"
    fi
    if [[ $SELECT_ALL_FAMILY_NAME -eq 1 ]] || [[ "$TABLE_NAME_ORIGIN" =~ :ip6(:|$) ]]; then
      nftables_reset_local_address_ipv6 ip6 "$TABLE_NAME"
    fi
    if [[ $SELECT_ALL_FAMILY_NAME -eq 1 ]] || [[ "$TABLE_NAME_ORIGIN" =~ :inet(:|$) ]]; then
      nftables_reset_local_address_ipv4 inet "$TABLE_NAME"
      nftables_reset_local_address_ipv6 inet "$TABLE_NAME"
    fi
    if [[ $SELECT_ALL_FAMILY_NAME -eq 1 ]] || [[ "$TABLE_NAME_ORIGIN" =~ :bridge(:|$) ]]; then
      nftables_reset_local_address_ipv4 bridge "$TABLE_NAME"
      nftables_reset_local_address_ipv6 bridge "$TABLE_NAME"
    fi
  done
fi
