#!/bin/bash

if [ -e /etc/resolv.conf.bak ]; then
  cp -f /etc/resolv.conf.bak /etc/resolv.conf
fi
