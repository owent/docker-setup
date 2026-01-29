#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# 创建下载缓存目录
mkdir -p download

if [[ -e "/usr/local/share/ca-certificates" ]]; then
  cp -r /usr/local/share/ca-certificates ./
else
  mkdir -p ca-certificates
fi

# 使用 -v 挂载 download 目录到构建环境
docker build \
  -v "$SCRIPT_DIR/download:/download" \
  -f trafficserver.Dockerfile \
  -t trafficserver-cache \
  "$@" \
  .
