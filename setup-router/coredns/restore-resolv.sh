#!/bin/bash

if [ -e /etc/resolv.conf.coredns ]; then
  cp -f /etc/resolv.conf.coredns /etc/resolv.conf
fi
