#!/usr/bin/env bash

SOCKET="/var/run/haproxy.sock"
TARGET=( )                            # 探测目标，可用你上游服务器 IP
COUNT=100                             # 每次发 100 个包
LOSS_THRESHOLD=5                      # 丢包率超过 5% 认为不健康

PREFER_BACKENDS=( bk_vbox_fast/hk_s1 bk_vbox_fast/hk_s2 )
FALLBACK_BACKENDS=( bk_vbox_fast/sg_s1 bk_vbox_fast/sg_s2 )

check_loss() {
  # 通过指定源地址发 ping(确保路由走对应出口)
  local total_sent=0
  local total_received=0
  
  for target_ip in "${TARGET[@]}"; do
    local result
    result=$(ping -c "$COUNT" -q "$target_ip" 2>/dev/null \
             | awk '/packets transmitted/ {print $1, $4}')
    
    if [ -n "$result" ]; then
      local sent=$(echo "$result" | awk '{print $1}')
      local received=$(echo "$result" | awk '{print $2}')
      total_sent=$((total_sent + sent))
      total_received=$((total_received + received))
    fi
  done
  
  if [ "$total_sent" -eq 0 ]; then
    echo "100"
  else
    local loss=$((100 - (total_received * 100 / total_sent)))
    echo "$loss"
  fi
}

function switch_to_prefer_backends() {
  for backend in "${PREFER_BACKENDS[@]}"; do
    echo "enable server $$backend" | socat stdio "$SOCKET"
  done
  for backend in "${FALLBACK_BACKENDS[@]}"; do
    echo "disable server $$backend" | socat stdio "$SOCKET"
  done
}

function switch_to_fallback_backends() {
  for backend in "${FALLBACK_BACKENDS[@]}"; do
    echo "enable server $$backend" | socat stdio "$SOCKET"
  done
  for backend in "${PREFER_BACKENDS[@]}"; do
    echo "disable server $$backend" | socat stdio "$SOCKET"
  done
}

loss_prefer=$(check_loss)

echo "Prefer loss: $loss_prefer%"

if [ "$loss_prefer" -gt "$LOSS_THRESHOLD" ]; then
  echo "Prefer backends bad -> switch to fallback backends"
  switch_to_fallback_backends
else
  echo "Prefer ok -> switch to prefer backends"
  switch_to_prefer_backends
fi
