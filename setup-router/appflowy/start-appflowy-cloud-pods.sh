#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

if [[ -z "$RUSTUP_DIST_SERVER" ]]; then
  export RUSTUP_DIST_SERVER="https://rsproxy.cn"
  # export RUSTUP_DIST_SERVER=https://mirrors.ustc.edu.cn/rust-static
  # export RUSTUP_DIST_SERVER=https://mirrors.tuna.tsinghua.edu.cn/rustup
fi
if [[ -z "$RUSTUP_UPDATE_ROOT" ]]; then
  export RUSTUP_UPDATE_ROOT="https://rsproxy.cn/rustup"
  # export RUSTUP_UPDATE_ROOT=https://mirrors.ustc.edu.cn/rust-static/rustup
  # export RUSTUP_UPDATE_ROOT=https://mirrors.tuna.tsinghua.edu.cn/rustup/rustup
fi

if [[ -z "$RUN_USER" ]]; then
  export RUN_USER=$(id -un)
fi

# sudo loginctl enable-linger $RUN_USER

if [[ -z "$RUN_USER" ]] || [[ "$RUN_USER" == "root" ]]; then
  echo -e "\033[1;32m$0 can not run with\033[0;m \033[1;31m$RUN_USER\033[0;m"
  exit 1
fi

RUN_HOME=$(awk -F: -v user="$RUN_USER" '$1 == user { print $6 }' /etc/passwd)

if [[ -z "$RUN_HOME" ]]; then
  RUN_HOME="$HOME"
fi

cd "$SCRIPT_DIR"

COMPOSE_CONFIGURE=docker-compose.yml
COMPOSE_ENV_FILE=.env
APPFLOWY_VERSION=
APPFLOWY_GIT_URL=https://github.com/AppFlowy-IO/AppFlowy-Cloud.git
APPFLOWY_MINIO_VOLUME_NAME=appflowy_minio_data
if [[ -z "$APPFLOWY_MINIO_VOLUME_PATH" ]]; then
  APPFLOWY_MINIO_VOLUME_PATH="$RUN_HOME/appflowy/minio/data"
fi
mkdir -p "$APPFLOWY_MINIO_VOLUME_PATH"

if [[ "x$APPFLOWY_ETC_DIR" == "x" ]]; then
  APPFLOWY_ETC_DIR="$RUN_HOME/appflowy/etc"
fi
mkdir -p "$APPFLOWY_ETC_DIR"

if [[ ! -z "$APPFLOWY_UPDATE" ]] || [[ ! -z "$ROUTER_IMAGE_UPDATE" ]] || [[ ! -e "appflowy.version" ]]; then
  GITHUB_TOKEN_ARGS=""
  if [[ ! -z "$GITHUB_TOKEN" ]]; then
    GITHUB_TOKEN_ARGS="-H Authorization: token $GITHUB_TOKEN"
  fi
  APPFLOWY_VERSION=$(curl -L $GITHUB_TOKEN_ARGS 'https://api.github.com/repos/AppFlowy-IO/AppFlowy-Cloud/releases/latest' | grep tag_name | grep -E -o '[0-9]+[0-9\.]+' | head -n 1)
  if [[ -z "$APPFLOWY_VERSION" ]]; then
    echo "Error: Unable to retrieve AppFlowy version"
    exit 1
  fi

  echo $APPFLOWY_VERSION >appflowy.version
else
  APPFLOWY_VERSION=$(cat appflowy.version)
fi

sed -i -E "s;[[:space:]]*APPFLOWY_CLOUD_VERSION=.*;APPFLOWY_CLOUD_VERSION=$APPFLOWY_VERSION;" .env

#if [[ ! -e "AppFlowy-Cloud" ]]; then
#  git clone --depth 1000 -b $APPFLOWY_VERSION "$APPFLOWY_GIT_URL" AppFlowy-Cloud
#  if [[ $? -ne 0 ]]; then
#    echo "Error: Unable to clone AppFlowy repository"
#    rm -rf AppFlowy-Cloud
#    exit 1
#  fi
#  cd AppFlowy-Cloud
#  git apply -c core.autocrlf=true ../mirror.patch
#  cp -f ../cargo-config ./
#  cd ..
#elif [[ ! -z "$APPFLOWY_UPDATE" ]] || [[ ! -z "$ROUTER_IMAGE_UPDATE" ]] || [[ ! -e "appflowy.version" ]]; then
#  cd AppFlowy-Cloud
#  git fetch --depth 1000 origin $APPFLOWY_VERSION
#  git reset --hard FETCH_HEAD
#  if [[ $? -ne 0 ]]; then
#    echo "Error: Unable to checkout AppFlowy version $APPFLOWY_VERSION"
#    exit 1
#  fi
#  git apply -c core.autocrlf=true ../mirror.patch
#  cp -f ../cargo-config ./
#  cd ..
#fi

if [[ ! -z "$APPFLOWY_UPDATE" ]] || [[ ! -z "$ROUTER_IMAGE_UPDATE" ]]; then
  podman-compose -f $COMPOSE_CONFIGURE pull
  if [[ $? -ne 0 ]]; then
    echo "Error: Unable to pull AppFlowy images"
    exit 1
  fi
  #podman-compose -f $COMPOSE_CONFIGURE build
  #if [[ $? -ne 0 ]]; then
  #  echo "Error: Unable to build AppFlowy images"
  #  exit 1
  #fi
fi

systemctl --user --all | grep -F container-appflowy-cloud.service

if [[ $? -eq 0 ]]; then
  systemctl --user stop container-appflowy-cloud
  systemctl --user disable container-appflowy-cloud
fi

podman-compose -f $COMPOSE_CONFIGURE down

podman volume inspect $APPFLOWY_MINIO_VOLUME_NAME >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  podman volume create --label app=appflowy --driver local --opt type=none --opt o=bind --opt device=${APPFLOWY_MINIO_VOLUME_PATH} $APPFLOWY_MINIO_VOLUME_NAME
fi

if [[ ! -z "$APPFLOWY_UPDATE" ]] || [[ ! -z "$ROUTER_IMAGE_UPDATE" ]]; then
  podman image prune -a -f --filter "until=240h"
fi

echo "[Unit]
Description=container-appflowy-cloud
After=network.target

[Service]
Type=simple
ExecStart=podman-compose -f $SCRIPT_DIR/$COMPOSE_CONFIGURE up
ExecStop=podman-compose -f $SCRIPT_DIR/$COMPOSE_CONFIGURE down

[Install]
WantedBy=default.target
" | tee $APPFLOWY_ETC_DIR/container-appflowy-cloud.service

systemctl --user enable $APPFLOWY_ETC_DIR/container-appflowy-cloud.service
systemctl --user daemon-reload
systemctl --user restart container-appflowy-cloud.service
