#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

if [[ "x$RUN_USER" == "x" ]]; then
  RUN_USER=$(id -un)
fi
# sudo loginctl enable-linger $RUN_USER

if [[ "x$RUN_USER" == "x" ]] || [[ "x$RUN_USER" == "xroot" ]]; then
  echo -e "\033[1;32m$0 can not run with\033[0;m \033[1;31m$RUN_USER\033[0;m"
  exit 1
fi

if [[ "x$RUN_HOME" == "x" ]]; then
  RUN_HOME=$(cat /etc/passwd | awk "BEGIN{FS=\":\"} \$1 == \"$RUN_USER\" { print \$6 }")
fi

if [[ "x$RUN_HOME" == "x" ]]; then
  RUN_HOME="$HOME"
fi

if [[ -z "$ADGUARD_HOME_DOCKER_IMAGE" ]]; then
  ADGUARD_HOME_DOCKER_IMAGE="docker.io/adguard/adguardhome:latest"
fi

if [[ -z "$ADGUARD_HOME_ETC_DIR" ]]; then
  ADGUARD_HOME_ETC_DIR="$HOME/adguardhome/etc"
fi
mkdir -p "$ADGUARD_HOME_ETC_DIR"

if [[ -z "$ADGUARD_HOME_DATA_DIR" ]]; then
  ADGUARD_HOME_DATA_DIR="$HOME/adguardhome/data"
fi
mkdir -p "$ADGUARD_HOME_DATA_DIR"

if [[ -z "$ADGUARD_HOME_WEB_DOH_HTTP_PORT" ]]; then
  ADGUARD_HOME_WEB_DOH_HTTP_PORT="6391"
fi
if [[ -z "$ADGUARD_HOME_WEB_DOH_HTTPS_PORT" ]]; then
  ADGUARD_HOME_WEB_DOH_HTTPS_PORT="6392"
fi
if [[ -z "$ADGUARD_HOME_WEB_ADMIN_PORT" ]]; then
  ADGUARD_HOME_WEB_ADMIN_PORT="6393"
fi

if [[ -z "$ADGUARD_HOME_SSL_USE_DOMAIN" ]]; then
  ADGUARD_HOME_SSL_USE_DOMAIN="$ACMESH_SSL_MAIN_DOMAIN"
fi

ADGUARD_HOME_SETTINGS=(
  -v $ADGUARD_HOME_DATA_DIR:/opt/adguardhome/work
  -v $ADGUARD_HOME_ETC_DIR:/opt/adguardhome/conf
)

if [[ ! -z "$ADGUARD_HOME_ENABLE_DNS" ]] && [[ "$ADGUARD_HOME_ENABLE_DNS" != "no" ]] && [[ "$ADGUARD_HOME_ENABLE_DNS" != "0" ]] && [[ "$ADGUARD_HOME_ENABLE_DNS" != "false" ]]; then
  # Plain DNS
  if [[ -z "$ADGUARD_HOME_ENABLE_DNS_PLAIN" ]] || ([[ "$ADGUARD_HOME_ENABLE_DNS_PLAIN" != "no" ]] && [[ "$ADGUARD_HOME_ENABLE_DNS_PLAIN" != "0" ]] && [[ "$ADGUARD_HOME_ENABLE_DNS_PLAIN" != "false" ]]); then
    ADGUARD_HOME_SETTINGS=("${ADGUARD_HOME_SETTINGS[@]}" -p 53:53/tcp -p 53:53/udp)
  fi
  # DNS over TLS
  if [[ -z "$ADGUARD_HOME_ENABLE_DNS_DOT" ]] || ([[ "$ADGUARD_HOME_ENABLE_DNS_DOT" != "no" ]] && [[ "$ADGUARD_HOME_ENABLE_DNS_DOT" != "0" ]] && [[ "$ADGUARD_HOME_ENABLE_DNS_DOT" != "false" ]]); then
    ADGUARD_HOME_SETTINGS=("${ADGUARD_HOME_SETTINGS[@]}" -p 853:853/tcp)
  fi
  # DNS over QUIC
  if [[ -z "$ADGUARD_HOME_ENABLE_DNS_DOQ" ]] || ([[ "$ADGUARD_HOME_ENABLE_DNS_DOQ" != "no" ]] && [[ "$ADGUARD_HOME_ENABLE_DNS_DOQ" != "0" ]] && [[ "$ADGUARD_HOME_ENABLE_DNS_DOQ" != "false" ]]); then
    ADGUARD_HOME_SETTINGS=("${ADGUARD_HOME_SETTINGS[@]}" -p 784:784/udp -p 853:853/udp -p 8853:8853/udp)
  fi
  # DNS over HTTPS
  if [[ -z "$ADGUARD_HOME_ENABLE_DNS_DOH" ]] || ([[ "$ADGUARD_HOME_ENABLE_DNS_DOH" != "no" ]] && [[ "$ADGUARD_HOME_ENABLE_DNS_DOH" != "0" ]] && [[ "$ADGUARD_HOME_ENABLE_DNS_DOH" != "false" ]]); then
    ADGUARD_HOME_SETTINGS=("${ADGUARD_HOME_SETTINGS[@]}"
      -p $ADGUARD_HOME_WEB_DOH_HTTP_PORT:80/tcp
      -p $ADGUARD_HOME_WEB_DOH_HTTPS_PORT:$ADGUARD_HOME_WEB_DOH_HTTPS_PORT/tcp
      -p $ADGUARD_HOME_WEB_DOH_HTTPS_PORT:$ADGUARD_HOME_WEB_DOH_HTTPS_PORT/udp
      -p $ADGUARD_HOME_WEB_ADMIN_PORT:$ADGUARD_HOME_WEB_ADMIN_PORT/tcp
    )
  fi
  # DNSCrypt
  if [[ ! -z "$ADGUARD_HOME_ENABLE_DNS_DNSCRYPT" ]] && [[ "$ADGUARD_HOME_ENABLE_DNS_PLAIN" != "no" ]] && [[ "$ADGUARD_HOME_ENABLE_DNS_PLAIN" != "0" ]] && [[ "$ADGUARD_HOME_ENABLE_DNS_PLAIN" != "false" ]]; then
    ADGUARD_HOME_SETTINGS=("${ADGUARD_HOME_SETTINGS[@]}" -p 5443:5443/tcp -p 5443:5443/udp)
  fi
fi

if [[ ! -z "$ADGUARD_HOME_ENABLE_DHCP" ]] && [[ "$ADGUARD_HOME_ENABLE_DHCP" != "no" ]] && [[ "$ADGUARD_HOME_ENABLE_DHCP" != "0" ]] && [[ "$ADGUARD_HOME_ENABLE_DHCP" != "false" ]]; then
  ADGUARD_HOME_SETTINGS=("${ADGUARD_HOME_SETTINGS[@]}" -p 67:67/udp -p 68:68/tcp -p 68:68/udp)
fi

if [[ "x$ADGUARD_HOME_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image pull $ADGUARD_HOME_DOCKER_IMAGE
fi

systemctl --user --all | grep -F container-adguard-home.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-adguard-home
  systemctl --user disable container-adguard-home
fi

podman container inspect adguard-home 2>&1 >/dev/null

if [[ $? -eq 0 ]]; then
  podman stop adguard-home
  podman rm -f adguard-home
fi

if [[ "x$ADGUARD_HOME_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

if [[ "x" == "x$ADMIN_USENAME" ]]; then
  ADMIN_USENAME=owent
fi
if [[ "x" == "x$ADMIN_TOKEN" ]]; then
  ADMIN_TOKEN=$(openssl rand -base64 32)
fi

echo "$ADMIN_USENAME $ADMIN_TOKEN" | tee "$RUN_HOME/adguard-home/admin-access.log"

if [[ -e "$ACMESH_SSL_DIR/${ADGUARD_HOME_SSL_USE_DOMAIN}_ecc/fullchain.cer" ]]; then
  ADGUARD_HOME_SSL_FULLCHAIN="$ACMESH_SSL_DIR/${ADGUARD_HOME_SSL_USE_DOMAIN}_ecc/fullchain.cer"
  ADGUARD_HOME_SSL_PRIVKEY="$ACMESH_SSL_DIR/${ADGUARD_HOME_SSL_USE_DOMAIN}_ecc/${ADGUARD_HOME_SSL_USE_DOMAIN}.key"
else
  ADGUARD_HOME_SSL_FULLCHAIN="$ACMESH_SSL_DIR/${ADGUARD_HOME_SSL_USE_DOMAIN}/fullchain.cer"
  ADGUARD_HOME_SSL_PRIVKEY="$ACMESH_SSL_DIR/${ADGUARD_HOME_SSL_USE_DOMAIN}/${ADGUARD_HOME_SSL_USE_DOMAIN}.key"
fi

cp -f "$ADGUARD_HOME_SSL_FULLCHAIN" "$ADGUARD_HOME_ETC_DIR/fullchain.pem"
cp -f "$ADGUARD_HOME_SSL_PRIVKEY" "$ADGUARD_HOME_ETC_DIR/privkey.pem"

if [[ ! -e "$ADGUARD_HOME_ETC_DIR/AdGuardHome.yaml" ]]; then
  echo "
http:
  address: 0.0.0.0:$ADGUARD_HOME_WEB_ADMIN_PORT
  session_ttl: 3h
  pprof:
    enabled: true
    port: 6060
users:
  - name: $ADMIN_USENAME
    password: \"$(bcrypt $ADMIN_TOKEN)\" # BCrypt-encrypted password. https://bcrypt.online/
dns:
  upstream_dns:
    # - quic://8.8.8.8:784
    - tls://8.8.8.8
    - tls://1.1.1.1
    - tls://dns.alidns.com
    - tls://dot.pub
    - "/*.shkits.com/223.5.5.5"
    - "/*.x-ha.com/223.5.5.5"
  bootstrap_dns:
    - 223.5.5.5:53
    - 119.29.29.29:53
  fallback_dns:
    - 223.5.5.5:53
    - 119.29.29.29:53
  edns_client_subnet:
    enabled:    true
    use_custom: false
    # custom_ip:  "116.228.111.118" # 上海电信
    custom_ip:  "210.22.70.3" # 上海联通
tls:
  enabled: true
  server_name: adguard-home.x-ha.com
  force_https: false
  port_https: $ADGUARD_HOME_WEB_DOH_HTTPS_PORT
  port_dns_over_tls: 853
  port_dns_over_quic: 853
  port_dnscrypt: 5443
  allow_unencrypted_doh: true
  strict_sni_check: false
  certificate_chain: /opt/adguardhome/conf/fullchain.pem
  private_key: /opt/adguardhome/conf/privkey.pem
" >"$ADGUARD_HOME_ETC_DIR/AdGuardHome.yaml"
fi

podman run -d --name adguard-home \
  --security-opt seccomp=unconfined \
  --security-opt label=disable \
  "${ADGUARD_HOME_SETTINGS[@]}" \
  $ADGUARD_HOME_DOCKER_IMAGE

podman generate systemd --name adguard-home \
  | sed "/ExecStart=/a ExecStartPre=/usr/bin/cp -f $ADGUARD_HOME_SSL_PRIVKEY $ADGUARD_HOME_ETC_DIR/privkey.pem" \
  | sed "/ExecStart=/a ExecStartPre=/usr/bin/cp -f $ADGUARD_HOME_SSL_FULLCHAIN $ADGUARD_HOME_ETC_DIR/fullchain.pem" \
  | tee "$RUN_HOME/adguard-home/container-adguard-home.service"

podman stop adguard-home

systemctl --user enable "$RUN_HOME/adguard-home/container-adguard-home.service"
systemctl --user restart container-adguard-home
