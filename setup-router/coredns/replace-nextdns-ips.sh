#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "x$ROUTER_HOME" == "x" ]]; then
  source "$SCRIPT_DIR/../configure-router.sh"
fi

if [[ "x$RUN_USER" == "x" ]]; then
  RUN_USER=$(id -un)
fi
RUN_HOME=$(cat /etc/passwd | awk "BEGIN{FS=\":\"} \$1 == \"$RUN_USER\" { print \$6 }")

if [[ "x$RUN_HOME" == "x" ]]; then
  RUN_HOME="$HOME"
fi

if [[ "x$COREDNS_ETC_DIR" == "x" ]]; then
  export COREDNS_ETC_DIR="$RUN_HOME/coredns/etc"
fi
mkdir -p "$COREDNS_ETC_DIR"

if [[ ! -e "$COREDNS_ETC_DIR/Corefile" ]]; then
  exit 0
fi

if [[ $? -ne 0 ]]; then
  exit 0
fi

NEXTDNS_IPS=""
function resolve_dns_ips() {
  if [[ $2 -le 0 ]]; then
    return
  fi

  let DEEP=$2-1
  NEXTDNS_IP_LOOKUP="$(dig $1 @119.29.29.29)"
  if [ $? -ne 0 ]; then
    NEXTDNS_IP_LOOKUP="$(dig $1 @223.5.5.5)"
  fi
  if [ $? -ne 0 ]; then
    NEXTDNS_IP_LOOKUP="$(dig $1 @1.0.0.1)"
  fi
  if [ $? -ne 0 ]; then
    NEXTDNS_IP_LOOKUP="$(dig $1 @94.140.14.141)"
  fi

  for CNAME in $(echo "$NEXTDNS_IP_LOOKUP" | awk '/IN\s*CNAME/ {print $5}'); do
    resolve_dns_ips $CNAME $DEEP
  done

  for IP in $(echo "$NEXTDNS_IP_LOOKUP" | awk '/IN\s*(A|AAAA)/ {print $5}'); do
    NEXTDNS_IPS="$NEXTDNS_IPS
$IP"
  done
}

resolve_dns_ips "$NEXTDNS_PRIVATE_TLS_DOMAIN" 3

FINAL_FORWARD_ARGUMENTS="forward ."
HAS_ADDRESS=0
for IP_ADDR in $(echo "$NEXTDNS_IPS" | sort -u); do
  FINAL_FORWARD_ARGUMENTS="$FINAL_FORWARD_ARGUMENTS tls://$IP_ADDR"
  HAS_ADDRESS=1
done
FINAL_FORWARD_ARGUMENTS="$FINAL_FORWARD_ARGUMENTS { # PLACEHOLDER_NEXTDNS_IP"
if [[ $HAS_ADDRESS -eq 0 ]]; then
  exit 0
fi

sed -i.bak -E "s;forward.*PLACEHOLDER_NEXTDNS_IP\$;$FINAL_FORWARD_ARGUMENTS;g" "$COREDNS_ETC_DIR/Corefile"
