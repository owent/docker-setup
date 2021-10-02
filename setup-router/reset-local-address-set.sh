#!/bin/bash

if [[ -e "/opt/nftables/sbin" ]]; then
  export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

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
  $(ip -o -4 addr | awk 'match($0, /inet\s+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(\/[0-9]+)?)/, ip) { print ip[1] }')
  $(ip -o -4 addr | awk 'match($0, /peer\s+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(\/[0-9]+)?)/, ip) { print ip[1] }')
)

ROUTER_LOCAL_NET_IPV6=(
  $(ip -o -6 addr | awk 'match($0, /inet6\s+([0-9a-fA-F:]+(\/[0-9]+)?)/, ip) { print ip[1] }')
)

# ipset
if [[ "x$ROUTER_NET_LOCAL_IPSET_PREFIX" != "x" ]]; then
  for IPSET_NAME in ${ROUTER_NET_LOCAL_IPSET_PREFIX//,/ }; do
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

    for IP_ADDR in ${ROUTER_LOCAL_NET_IPV4[@]}; do
      ipset add "${IPSET_NAME}_LOCAL_IPV4" "$IP_ADDR"
    done

    for IP_ADDR in ${ROUTER_LOCAL_NET_IPV6[@]}; do
      ipset add "${IPSET_NAME}_LOCAL_IPV6" "$IP_ADDR"
    done
  done
fi

# nftables
if [[ "x$ROUTER_NET_LOCAL_NFTABLE_NAME" != "x" ]]; then
  for TABLE_NAME in ${ROUTER_NET_LOCAL_NFTABLE_NAME//,/ }; do
    nft list table ip "$TABLE_NAME" >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
      nft add table ip "$TABLE_NAME"
    fi

    nft list table ip6 "$TABLE_NAME" >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
      nft add table ip6 "$TABLE_NAME"
    fi

    nft list table inet "$TABLE_NAME" >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
      nft add table inet "$TABLE_NAME"
    fi

    nft list table bridge "$TABLE_NAME" >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
      nft add table bridge "$TABLE_NAME"
    fi

    nft list set ip "$TABLE_NAME" LOCAL_IPV4 >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
      nft add set ip "$TABLE_NAME" LOCAL_IPV4 '{ type ipv4_addr; flags interval; auto-merge ; }'
    else
      nft flush set ip "$TABLE_NAME" LOCAL_IPV4
    fi

    nft list set ip6 "$TABLE_NAME" LOCAL_IPV6 >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
      nft add set ip6 "$TABLE_NAME" LOCAL_IPV6 '{ type ipv6_addr; flags interval; auto-merge ; }'
    else
      nft flush set ip6 "$TABLE_NAME" LOCAL_IPV6
    fi

    nft list set inet "$TABLE_NAME" LOCAL_IPV4 >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
      nft add set inet "$TABLE_NAME" LOCAL_IPV4 '{ type ipv4_addr; flags interval; auto-merge ; }'
    else
      nft flush set inet "$TABLE_NAME" LOCAL_IPV4
    fi
    nft list set inet "$TABLE_NAME" LOCAL_IPV6 >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
      nft add set inet "$TABLE_NAME" LOCAL_IPV6 '{ type ipv6_addr; flags interval; auto-merge ; }'
    else
      nft flush set inet "$TABLE_NAME" LOCAL_IPV6
    fi

    nft list set bridge "$TABLE_NAME" LOCAL_IPV4 >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
      nft add set bridge "$TABLE_NAME" LOCAL_IPV4 '{ type ipv4_addr; flags interval; auto-merge ; }'
    else
      nft flush set bridge "$TABLE_NAME" LOCAL_IPV4
    fi
    nft list set bridge "$TABLE_NAME" LOCAL_IPV6 >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
      nft add set bridge "$TABLE_NAME" LOCAL_IPV6 '{ type ipv6_addr; flags interval; auto-merge ; }'
    else
      nft flush set bridge "$TABLE_NAME" LOCAL_IPV6
    fi

    for IP_ADDR in ${ROUTER_LOCAL_NET_IPV4[@]}; do
      nft add element ip "$TABLE_NAME" LOCAL_IPV4 "{ $IP_ADDR }"
      nft add element bridge "$TABLE_NAME" LOCAL_IPV4 "{ $IP_ADDR }"
      nft add element inet "$TABLE_NAME" LOCAL_IPV4 "{ $IP_ADDR }"
    done

    for IP_ADDR in ${ROUTER_LOCAL_NET_IPV6[@]}; do
      nft add element ip6 "$TABLE_NAME" LOCAL_IPV6 "{ $IP_ADDR }"
      nft add element bridge "$TABLE_NAME" LOCAL_IPV6 "{ $IP_ADDR }"
      nft add element inet "$TABLE_NAME" LOCAL_IPV6 "{ $IP_ADDR }"
    done
  done
fi
