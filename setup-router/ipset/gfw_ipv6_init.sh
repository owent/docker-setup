#!/bin/bash

for IPSET_NAME in "$@"; do
  ipset list $IPSET_NAME >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    ipset flush $IPSET_NAME
  else
    ipset create $IPSET_NAME hash:ip family inet6
  fi

  ipset add $IPSET_NAME 2001:4860:4860::8888
  ipset add $IPSET_NAME 2001:4860:4860::8844
done
