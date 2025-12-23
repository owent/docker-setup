#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

if [[ -e "$SCRIPT_DIR/../configure-router.sh" ]]; then
  source "$SCRIPT_DIR/../configure-router.sh"
fi

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

DOCKER_EXEC=$((which podman > /dev/null 2>&1 && echo podman) || (which docker > /dev/null 2>&1 && echo docker))

if [[ "x$RUN_USER" == "x" ]]; then
  RUN_USER=$(id -un)
fi
RUN_HOME=$(cat /etc/passwd | awk "BEGIN{FS=\":\"} \$1 == \"$RUN_USER\" { print \$6 }")

if [[ "x$RUN_HOME" == "x" ]]; then
  RUN_HOME="$HOME"
fi

if [[ "x$FREE_RADIUS_AUTH_PORT" == "x" ]]; then
  FREE_RADIUS_AUTH_PORT=1812
fi

if [[ "x$FREE_RADIUS_ACCT_PORT" == "x" ]]; then
  FREE_RADIUS_ACCT_PORT=1813
fi

# FREE_RADIUS_SERVER_CERTS_DIR=
if [[ "x$FREE_RADIUS_SERVER_ETC_DIR" == "x" ]]; then
  FREE_RADIUS_SERVER_ETC_DIR="$SCRIPT_DIR/etc"
fi
mkdir -p "$FREE_RADIUS_SERVER_ETC_DIR"

if [[ "x$FREE_RADIUS_SERVER_CONFIG_DIR" == "x" ]]; then
  FREE_RADIUS_SERVER_CONFIG_DIR="$SCRIPT_DIR/config"
fi
mkdir -p "$FREE_RADIUS_SERVER_CONFIG_DIR"

FREE_RADIUS_SERVER_IMAGE="freeradius/freeradius-server:latest-alpine"
# FREE_RADIUS_SERVER_IMAGE="freeradius/freeradius-server:latest"

if [[ "x$FREE_RADIUS_SERVER_UPDATE" != "x" ]] || [[ "x$FREE_RADIUS_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  $DOCKER_EXEC pull $FREE_RADIUS_SERVER_IMAGE
  if [[ $? -ne 0 ]]; then
    exit 1
  fi
fi

# FreeRadius配置比较复杂，我们复制出来然后重新修改
function copy_freeradius_config_dir() {
  rm -rf "$FREE_RADIUS_SERVER_CONFIG_DIR/"*

  $DOCKER_EXEC run --rm \
    --mount type=bind,source="$FREE_RADIUS_SERVER_CONFIG_DIR",target=/copy-config \
    $FREE_RADIUS_SERVER_IMAGE \
    sh -c "cp -rf /etc/raddb/* /copy-config/"

  if [[ $? -ne 0 ]]; then
    echo "Copy FreeRadius config failed."
    exit 1
  fi

  cd "$FREE_RADIUS_SERVER_CONFIG_DIR/mods-enabled"
  # 启用LDAP
  ln -sf ../mods-available/ldap ldap
  # 关闭不需要的认证源
  rm -f unix digest chap passwd ntlm_auth
  # 关闭不需要的功能: soh (System Health), replicate (集群同步), totp (动态口令)
  rm -f soh replicate totp
  # 移除文本配置的用户
  cd ..
  echo "" > users
}
copy_freeradius_config_dir

if [[ $? -ne 0 ]]; then
  exit 1
fi

# 覆盖自定义配置
cp -rf "$FREE_RADIUS_SERVER_ETC_DIR/"* "$FREE_RADIUS_SERVER_CONFIG_DIR/"

# 方便docker/podman采集日志
sed -i -E 's/destination[[:space:]]*=[[:space:]]*[a-zA-Z0-9"].*/destination = stdout/g' "$FREE_RADIUS_SERVER_CONFIG_DIR/radiusd.conf"
sed -i -E 's/colourise[[:space:]]*=[[:space:]]*[a-zA-Z0-9"].*/colourise = yes/g' "$FREE_RADIUS_SERVER_CONFIG_DIR/radiusd.conf"
sed -i -E 's/auth[[:space:]]*=[[:space:]]*[a-zA-Z0-9"].*/auth = yes/g' "$FREE_RADIUS_SERVER_CONFIG_DIR/radiusd.conf"
sed -i -E 's/auth_badpass[[:space:]]*=[[:space:]]*[a-zA-Z0-9"].*/auth_badpass = yes/g' "$FREE_RADIUS_SERVER_CONFIG_DIR/radiusd.conf"
sed -i -E 's/auth_goodpass[[:space:]]*=[[:space:]]*[a-zA-Z0-9"].*/auth_goodpass = yes/g' "$FREE_RADIUS_SERVER_CONFIG_DIR/radiusd.conf"

systemctl --user --all | grep -F container-freeradius.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-freeradius
  systemctl --user disable container-freeradius
fi

$DOCKER_EXEC container exists freeradius >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  $DOCKER_EXEC stop freeradius
  $DOCKER_EXEC rm -f freeradius
fi

if [[ "x$FREE_RADIUS_SERVER_UPDATE" != "x" ]] || [[ "x$FREE_RADIUS_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  $DOCKER_EXEC image prune -a -f --filter "until=240h"
fi

FREE_RADIUS_SERVER_OPTIONS=(
  -p $FREE_RADIUS_AUTH_PORT:$FREE_RADIUS_AUTH_PORT/udp
  -p $FREE_RADIUS_ACCT_PORT:$FREE_RADIUS_ACCT_PORT/udp
)

if [[ ! -z "$FREE_RADIUS_SERVER_CERTS_DIR" ]]; then
  FREE_RADIUS_SERVER_OPTIONS+=(
    --mount type=bind,source=$FREE_RADIUS_SERVER_CERTS_DIR,target=/etc/raddb/certs
  )
fi

$DOCKER_EXEC run -d --name freeradius --security-opt label=disable \
  -e "TZ=Asia/Shanghai" \
  # -e RADIUS_DEBUG=yes \
  --mount type=bind,source=$FREE_RADIUS_SERVER_CONFIG_DIR,target=/etc/raddb \
  ${FREE_RADIUS_SERVER_OPTIONS[@]} \
  $FREE_RADIUS_SERVER_IMAGE

if [[ $? -ne 0 ]]; then
  echo "Start FreeRadius container failed."
  exit 1
fi

$DOCKER_EXEC stop freeradius

$DOCKER_EXEC generate systemd --name freeradius | tee $FREE_RADIUS_SERVER_ETC_DIR/container-freeradius.service

systemctl --user enable $FREE_RADIUS_SERVER_ETC_DIR/container-freeradius.service
systemctl --user restart container-freeradius