#!/bin/bash

for IPSET_NAME in "$@"; do
  ipset list $IPSET_NAME >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    ipset flush $IPSET_NAME
  else
    ipset create $IPSET_NAME hash:ip family inet
  fi

  ipset add $IPSET_NAME "91.108.56.0/22"
  ipset add $IPSET_NAME "95.161.64.0/20"
  ipset add $IPSET_NAME "91.108.4.0/22"
  ipset add $IPSET_NAME "91.108.8.0/22"
  ipset add $IPSET_NAME "149.154.160.0/22"
  ipset add $IPSET_NAME "149.154.164.0/22"
  ipset add $IPSET_NAME "8.8.8.8"
  ipset add $IPSET_NAME "8.8.4.4"
done
