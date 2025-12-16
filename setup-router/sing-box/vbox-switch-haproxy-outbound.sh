#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

SOCKET="/var/run/haproxy/haproxy.sock"
COUNT=100                             # 每次发 100 个包
LOSS_THRESHOLD=2                      # 丢包率prefer比fallback超过 2% 认为不健康

BLACKLIST_GROUP_NAME=() # (hk)

PREFER_GROUP_COUNT=1                  # 首选组数量
ORIGIN_PREFER_GROUP_COUNT=$PREFER_GROUP_COUNT
PREFER_GROUP_1_NAME=hk                # 首选组名称
PREFER_GROUP_1_TARGET=( )             # 探测目标，可用你上游服务器 IP
PREFER_GROUP_1_BACKENDS=( bk_vbox_fast/hk_s1 bk_vbox_fast/hk_s2 )

# 备选组前面的优先级高，选中某一个后会关闭前面高优先级的节点
FALLBACK_GROUP_COUNT=2                # 备用组数量
ORIGIN_FALLBACK_GROUP_COUNT=$FALLBACK_GROUP_COUNT
FALLBACK_GROUP_1_NAME=sg              # 备用组数量
FALLBACK_GROUP_1_TARGET=( )           # 探测目标，可用你上游服务器 IP
FALLBACK_GROUP_1_BACKENDS=( bk_vbox_fast/sg_s1 bk_vbox_fast/sg_s2 )
FALLBACK_GROUP_2_NAME=jp
FALLBACK_GROUP_2_TARGET=( )
FALLBACK_GROUP_2_BACKENDS=( bk_vbox_fast/jp_s1 bk_vbox_fast/jp_s2 )

SWITCH_SELECT_GROUP_NAME=""
SWITCH_TEST_MODE=0
while getopts "hs:t" OPTION; do
  case $OPTION in
  h)
    AVAILABLE_GROUP_NAMES=()
    for ((i=1;i<=$PREFER_GROUP_COUNT;i++)); do
      GROUP_NAME_VAR="PREFER_GROUP_${i}_NAME"
      AVAILABLE_GROUP_NAMES+=("${!GROUP_NAME_VAR}")
    done
    for ((i=1;i<=$FALLBACK_GROUP_COUNT;i++)); do
      GROUP_NAME_VAR="FALLBACK_GROUP_${i}_NAME"
      AVAILABLE_GROUP_NAMES+=("${!GROUP_NAME_VAR}")
    done
    echo "usage: $0 [options] "
    echo "options:"
    echo "-h                            help message."
    echo "-s [group name]               available groups: ${AVAILABLE_GROUP_NAMES[@]}"
    echo "-t                            test mode, do not real change backend."
    exit 0
    ;;
  s)
    SWITCH_SELECT_GROUP_NAME=$OPTARG
    ;;
  t)
    SWITCH_TEST_MODE=1
    ;;
  ?)
    break
    ;;
  esac
done

SWITCH_HISTORY_DIR="$SCRIPT_DIR/vbox-switch-haproxy-outbound.group-name"
mkdir -p "$SWITCH_HISTORY_DIR"

if [[ ! -z "$SWITCH_SELECT_GROUP_NAME" ]] && ; then
  if [[ -e "$SWITCH_HISTORY_DIR/check.log" ]]; then
    tail -n 500 "$SWITCH_HISTORY_DIR/check.log" > "$SWITCH_HISTORY_DIR/check.log.tmp"
    mv -f "$SWITCH_HISTORY_DIR/check.log.tmp" "$SWITCH_HISTORY_DIR/check.log"
  fi

  echo "======================== $(date '+%Y-%m-%d %H:%M:%S') ========================" >> "$SWITCH_HISTORY_DIR/check.log"
fi

check_loss() {
  GROUP_NAME="$1"
  shift

  if [[ " ${BLACKLIST_GROUP_NAME[@]} " =~ " ${GROUP_NAME} " ]]; then
    echo "100"
    return
  fi

  # 通过指定源地址发 ping(确保路由走对应出口)
  local total_sent=0
  local total_received=0

  for target_ip in "$@"; do
    local result
    ping_report="$(ping -c "$COUNT" -q "$target_ip" 2>/dev/null)"
    echo -e "------------------------ GROUP_NAME: $GROUP_NAME - $target_ip ------------------------\n$ping_report" >> "$SWITCH_HISTORY_DIR/check.log"
    result=$(echo "$ping_report" | awk '/packets transmitted/ {print $1, $4}')
    
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

function switch_to_backends() {
  GROUP_TYPE="$1"
  ENABLE_GROUP_NAME="$2"
  shift
  shift

  PREVIOUS_GROUP_NAME=""
  if [ -e "$SWITCH_HISTORY_DIR/$GROUP_TYPE.txt" ]; then
    PREVIOUS_GROUP_NAME=$(cat "$SWITCH_HISTORY_DIR/$GROUP_TYPE.txt")
  fi
  if [[ "$PREVIOUS_GROUP_NAME" == "$ENABLE_GROUP_NAME" ]]; then
    echo "[$GROUP_TYPE]: Backends not changed for group $ENABLE_GROUP_NAME, no switch needed."
    return
  fi

  if [[ $SWITCH_TEST_MODE -eq 0 ]]; then
    echo 1 > "$SWITCH_HISTORY_DIR/last-changed.txt"
  fi

  echo "[$GROUP_TYPE]: enable backends of group $ENABLE_GROUP_NAME : $@"
  for backend in "$@"; do
    if [[ $SWITCH_TEST_MODE -ne 0 ]]; then
      continue
    fi
    echo "enable server $backend" | socat stdio "$SOCKET"
  done

  USE_PREFER_GROUP=0
  for ((i=1;i<=$PREFER_GROUP_COUNT;i++)); do
    GROUP_NAME_VAR="PREFER_GROUP_${i}_NAME"
    GROUP_NAME=${!GROUP_NAME_VAR}
    if [ "$GROUP_NAME" == "$ENABLE_GROUP_NAME" ]; then
      USE_PREFER_GROUP=$i
      continue
    fi

    GROUP_BACKENDS_VAR="PREFER_GROUP_${i}_BACKENDS[@]"
    GROUP_BACKENDS=("${!GROUP_BACKENDS_VAR}")

    # 首选组只启用一个
    echo "[$GROUP_TYPE]: disable backends of group $GROUP_NAME: ${GROUP_BACKENDS[@]}"
    for backend in "${GROUP_BACKENDS[@]}"; do
      if [[ $SWITCH_TEST_MODE -ne 0 ]]; then
        continue
      fi
      echo "disable server $backend" | socat stdio "$SOCKET"
    done
  done
  
  USE_FALLBACK_GROUP=0
  for ((i=1;i<=$FALLBACK_GROUP_COUNT;i++)); do
    GROUP_NAME_VAR="FALLBACK_GROUP_${i}_NAME"
    GROUP_NAME=${!GROUP_NAME_VAR}
    if [ "$GROUP_NAME" == "$ENABLE_GROUP_NAME" ]; then
      USE_FALLBACK_GROUP=$i
      continue
    fi

    GROUP_BACKENDS_VAR="FALLBACK_GROUP_${i}_BACKENDS[@]"
    GROUP_BACKENDS=("${!GROUP_BACKENDS_VAR}")

    # 如果启用首选组，backup组全部开启
    # 如果启用backup组，更低优先级的backup组全部开启
    if [[ $USE_PREFER_GROUP -ne 0 ]] || [[ $USE_FALLBACK_GROUP -gt 0 ]]; then
      echo "[$GROUP_TYPE]: enable backends of group $GROUP_NAME: ${GROUP_BACKENDS[@]}"
      for backend in "${GROUP_BACKENDS[@]}"; do
        if [[ $SWITCH_TEST_MODE -ne 0 ]]; then
          continue
        fi
        echo "enable server $backend" | socat stdio "$SOCKET"
      done
    else
      echo "[$GROUP_TYPE]: disable backends of group $GROUP_NAME: ${GROUP_BACKENDS[@]}"
      for backend in "${GROUP_BACKENDS[@]}"; do
        if [[ $SWITCH_TEST_MODE -ne 0 ]]; then
          continue
        fi
        echo "disable server $backend" | socat stdio "$SOCKET"
      done
    fi
  done

  # Shutdown sessions on disabled backends
  for ((i=1;i<=$PREFER_GROUP_COUNT;i++)); do
    GROUP_NAME_VAR="PREFER_GROUP_${i}_NAME"
    GROUP_NAME=${!GROUP_NAME_VAR}
    if [ "$GROUP_NAME" == "$ENABLE_GROUP_NAME" ] || [ "x$GROUP_NAME" == "x$PREVIOUS_GROUP_NAME" ]; then
      continue
    fi

    GROUP_BACKENDS_VAR="PREFER_GROUP_${i}_BACKENDS[@]"
    GROUP_BACKENDS=("${!GROUP_BACKENDS_VAR}")

    echo "[$GROUP_TYPE]: shutdown sessions server of group $GROUP_NAME: ${GROUP_BACKENDS[@]}"
    for backend in "${GROUP_BACKENDS[@]}"; do
      if [[ $SWITCH_TEST_MODE -ne 0 ]]; then
        continue
      fi
      echo "shutdown sessions server $backend" | socat stdio "$SOCKET"
    done
  done
  
  for ((i=1;i<=$FALLBACK_GROUP_COUNT;i++)); do
    GROUP_NAME_VAR="FALLBACK_GROUP_${i}_NAME"
    GROUP_NAME=${!GROUP_NAME_VAR}
    if [ "$GROUP_NAME" == "$ENABLE_GROUP_NAME" ] || [ "x$GROUP_NAME" == "x$PREVIOUS_GROUP_NAME" ]; then
      continue
    fi

    # 启用备选组时，更低优先级的的备选组作为后备，不需要shutdown session
    if [[ $USE_PREFER_GROUP -gt 0 ]]; then
      continue
    fi
    if [[ $USE_FALLBACK_GROUP -gt 0 ]] && [[ $i -ge $USE_FALLBACK_GROUP ]]; then
      continue
    fi

    GROUP_BACKENDS_VAR="FALLBACK_GROUP_${i}_BACKENDS[@]"
    GROUP_BACKENDS=("${!GROUP_BACKENDS_VAR}")

    echo "[$GROUP_TYPE]: shutdown sessions server of group $GROUP_NAME: ${GROUP_BACKENDS[@]}"
    for backend in "${GROUP_BACKENDS[@]}"; do
      if [[ $SWITCH_TEST_MODE -ne 0 ]]; then
        continue
      fi
      echo "shutdown sessions server $backend" | socat stdio "$SOCKET"
    done
  done

  if [[ $SWITCH_TEST_MODE -eq 0 ]]; then
    echo "$ENABLE_GROUP_NAME" > "$SWITCH_HISTORY_DIR/$GROUP_TYPE.txt"
  fi
}

PREFER_GROUP_SELECT_LOSS=20000
PREFER_GROUP_SELECT_NAME=""
PREFER_GROUP_SELECT_BACKENDS=()
for ((i=1;i<=$PREFER_GROUP_COUNT;i++)); do
  GROUP_NAME_VAR="PREFER_GROUP_${i}_NAME"
  GROUP_TARGET_VAR="PREFER_GROUP_${i}_TARGET[@]"
  GROUP_BACKENDS_VAR="PREFER_GROUP_${i}_BACKENDS[@]"
  
  GROUP_NAME=${!GROUP_NAME_VAR}
  GROUP_TARGET=("${!GROUP_TARGET_VAR}")
  GROUP_BACKENDS=("${!GROUP_BACKENDS_VAR}")
  
  if [[ ! -z "$SWITCH_SELECT_GROUP_NAME" ]]; then
    if [[ "$SWITCH_SELECT_GROUP_NAME" == "$GROUP_NAME" ]]; then
      GROUP_LOSS=0
    else
      GROUP_LOSS=$((10000+$i))
    fi
  else
    GROUP_LOSS=$(check_loss "$GROUP_NAME" "${GROUP_TARGET[@]}")
    echo "Prefer group $GROUP_NAME loss: $GROUP_LOSS%"
  fi
  
  if [[ $GROUP_LOSS -lt $PREFER_GROUP_SELECT_LOSS ]]; then
    PREFER_GROUP_SELECT_LOSS=$GROUP_LOSS
    PREFER_GROUP_SELECT_NAME=$GROUP_NAME
    PREFER_GROUP_SELECT_BACKENDS=("${!GROUP_BACKENDS_VAR}")
  fi
done


FALLBACK_GROUP_SELECT_LOSS=20000
FALLBACK_GROUP_SELECT_NAME=""
FALLBACK_GROUP_SELECT_BACKENDS=()
for ((i=1;i<=$FALLBACK_GROUP_COUNT;i++)); do
  GROUP_NAME_VAR="FALLBACK_GROUP_${i}_NAME"
  GROUP_TARGET_VAR="FALLBACK_GROUP_${i}_TARGET[@]"
  GROUP_BACKENDS_VAR="FALLBACK_GROUP_${i}_BACKENDS[@]"
  
  GROUP_NAME=${!GROUP_NAME_VAR}
  GROUP_TARGET=("${!GROUP_TARGET_VAR}")
  GROUP_BACKENDS=("${!GROUP_BACKENDS_VAR}")
  
  if [[ ! -z "$SWITCH_SELECT_GROUP_NAME" ]]; then
    if [[ "$SWITCH_SELECT_GROUP_NAME" == "$GROUP_NAME" ]]; then
      GROUP_LOSS=0
    else
      GROUP_LOSS=$((10000+$i))
    fi
  else
    GROUP_LOSS=$(check_loss "$GROUP_NAME" "${GROUP_TARGET[@]}")
    echo "Fallback group $GROUP_NAME loss: $GROUP_LOSS%"
  fi
  
  if [[ $GROUP_LOSS -lt $FALLBACK_GROUP_SELECT_LOSS ]]; then
    FALLBACK_GROUP_SELECT_LOSS=$GROUP_LOSS
    FALLBACK_GROUP_SELECT_NAME=$GROUP_NAME
    FALLBACK_GROUP_SELECT_BACKENDS=("${!GROUP_BACKENDS_VAR}")
  fi
done

if [[ $SWITCH_TEST_MODE -eq 0 ]]; then
  echo 0 > "$SWITCH_HISTORY_DIR/last-changed.txt"
fi

ORIGIN_GROUP_TYPE="bk_vbox_fast"
if [[ $PREFER_GROUP_SELECT_LOSS -gt $(($FALLBACK_GROUP_SELECT_LOSS+$LOSS_THRESHOLD)) ]]; then
  echo "Prefer backends bad -> switch to fallback backends"
  switch_to_backends "$ORIGIN_GROUP_TYPE" "$FALLBACK_GROUP_SELECT_NAME" "${FALLBACK_GROUP_SELECT_BACKENDS[@]}"
else
  echo "Prefer ok -> switch to prefer backends: $PREFER_GROUP_SELECT_NAME"
  switch_to_backends "$ORIGIN_GROUP_TYPE" "$PREFER_GROUP_SELECT_NAME" "${PREFER_GROUP_SELECT_BACKENDS[@]}"
fi

LAST_RENAME_GROUP_TYPE="$ORIGIN_GROUP_TYPE"
function switch_group_type_to_backends() {
  GROUP_TYPE="$1"
  GROUP_SELECT_NAME="$2"
  shift
  shift
  FROM_GROUP_TYPE="$LAST_RENAME_GROUP_TYPE"
  GROUP_SELECT_BACKENDS=("$@")
  for ((i=1;i<=$ORIGIN_PREFER_GROUP_COUNT;i++)); do
    GROUP_BACKENDS_VAR="PREFER_GROUP_${i}_BACKENDS[@]"
    GROUP_BACKENDS_VALUES=("${!GROUP_BACKENDS_VAR}")
    declare -n ref="PREFER_GROUP_${i}_BACKENDS"
    ref=("${GROUP_BACKENDS_VALUES[@]/$FROM_GROUP_TYPE/$GROUP_TYPE}")
  done
  for ((i=1;i<=$ORIGIN_FALLBACK_GROUP_COUNT;i++)); do
    GROUP_BACKENDS_VAR="FALLBACK_GROUP_${i}_BACKENDS[@]"
    GROUP_BACKENDS_VALUES=("${!GROUP_BACKENDS_VAR}")
    declare -n ref="FALLBACK_GROUP_${i}_BACKENDS"
    ref=("${GROUP_BACKENDS_VALUES[@]/$FROM_GROUP_TYPE/$GROUP_TYPE}")
  done
  switch_to_backends "$GROUP_TYPE" "$GROUP_SELECT_NAME" "${GROUP_SELECT_BACKENDS[@]/$ORIGIN_GROUP_TYPE/$GROUP_TYPE}"

  LAST_RENAME_GROUP_TYPE="$GROUP_TYPE"
}

# PREFER_GROUP_COUNT_BACKUP=$PREFER_GROUP_COUNT  # 首选组数量
# PREFER_GROUP_COUNT=0                    # 首选组数量
# switch_group_type_to_backends "bk_vbox_sg" "$FALLBACK_GROUP_SELECT_NAME" "${FALLBACK_GROUP_SELECT_BACKENDS[@]}"
# PREFER_GROUP_COUNT=$PREFER_GROUP_COUNT_BACKUP

# 用相同的规则，切换 reality 组
if [[ $PREFER_GROUP_SELECT_LOSS -gt $(($FALLBACK_GROUP_SELECT_LOSS+$LOSS_THRESHOLD)) ]]; then
  switch_group_type_to_backends "bk_vbox_reality_fast" "$FALLBACK_GROUP_SELECT_NAME" "${FALLBACK_GROUP_SELECT_BACKENDS[@]}"
else
  switch_group_type_to_backends "bk_vbox_reality_fast" "$PREFER_GROUP_SELECT_NAME" "${PREFER_GROUP_SELECT_BACKENDS[@]}"
fi
# PREFER_GROUP_COUNT_BACKUP=$PREFER_GROUP_COUNT  # 首选组数量
# PREFER_GROUP_COUNT=0                    # 首选组数量
# switch_group_type_to_backends "bk_vbox_reality_sg" "$FALLBACK_GROUP_SELECT_NAME" "${FALLBACK_GROUP_SELECT_BACKENDS[@]}"
# PREFER_GROUP_COUNT=$PREFER_GROUP_COUNT_BACKUP


if [[ $SWITCH_TEST_MODE -eq 0 ]] && [[ $(cat "$SWITCH_HISTORY_DIR/last-changed.txt") -ne 0 ]]; then
  sudo -u tools /bin/bash -i -c "systemctl --user restart container-adguard-home.service"
fi
