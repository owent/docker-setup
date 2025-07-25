#!/bin/bash

INTERNAL_FRONTEND_IPV4_CIDR="10.91.0.0/16"
INTERNAL_FRONTEND_IPV4_GATEWAY="10.91.0.1"
INTERNAL_FRONTEND_IPV6_CIDR="fd02:0:0:1:1::/96"
INTERNAL_FRONTEND_IPV6_GATEWAY="fd02:0:0:1:1::1"

INTERNAL_BACKEND_IPV4="10.92.1.0/16"
INTERNAL_BACKEND_GATEWAY="10.92.0.1"
INTERNAL_BACKEND_IPV6_CIDR="fd02:0:0:1:2::/96"
INTERNAL_BACKEND_IPV6_GATEWAY="fd02:0:0:1:2::1"

podman network exists internal-frontend >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  podman network create --driver bridge --ipam-driver host-local \
    --ipv6 --subnet $INTERNAL_FRONTEND_IPV6_CIDR --gateway $INTERNAL_FRONTEND_IPV6_GATEWAY \
    --subnet $INTERNAL_FRONTEND_IPV4_CIDR --gateway $INTERNAL_FRONTEND_IPV4_GATEWAY \
    internal-frontend
fi

podman network exists internal-backend >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  podman network create --driver bridge --ipam-driver host-local \
    --ipv6 --subnet $INTERNAL_BACKEND_IPV6_CIDR --gateway $INTERNAL_BACKEND_IPV6_GATEWAY \
    --subnet $INTERNAL_BACKEND_IPV4 --gateway $INTERNAL_BACKEND_GATEWAY \
    internal-backend
fi

# 开启DNS
# apt install containernetworking-plugins golang-github-containernetworking-plugin-dnsname -y
# Test DNS
# podman run --network internal-backend --rm alpine nslookup live-frontend
