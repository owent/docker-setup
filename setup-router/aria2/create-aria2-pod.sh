#!/bin/bash

# Maybe need in /etc/ssh/sshd_config
#     DenyUsers tools
#     DenyGroups tools

if [[ -e "/opt/nftables/sbin" ]]; then
  export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../configure-router.sh"

if [[ "x$ARIA2_DATA_ROOT" == "x" ]]; then
  if [[ ! -z "$SAMBA_DATA_DIR" ]]; then
    ARIA2_DATA_ROOT="$SAMBA_DATA_DIR/download"
  elif [[ ! -z "$ROUTER_DATA_ROOT_DIR" ]]; then
    ARIA2_DATA_ROOT="$ROUTER_DATA_ROOT_DIR/aria2/download"
  else
    ARIA2_DATA_ROOT="$HOME/aria2/download"
  fi
fi
mkdir -p "$ARIA2_DATA_ROOT"

if [[ "x$RUN_USER" == "x" ]]; then
  RUN_USER=$(id -un)
fi
RUN_HOME=$(cat /etc/passwd | awk "BEGIN{FS=\":\"} \$1 == \"$RUN_USER\" { print \$6 }")

if [[ "x$RUN_HOME" == "x" ]]; then
  RUN_HOME="$HOME"
fi

if [[ "root" == "$(id -un)" ]]; then
  SYSTEMD_SERVICE_DIR=/lib/systemd/system
else
  SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_SERVICE_DIR"
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl --all | grep -F aria2.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl stop aria2.service
    systemctl disable aria2.service
  fi
else
  export XDG_RUNTIME_DIR="/run/user/$UID"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

  # Maybe need run from host: loginctl enable-linger tools
  # see https://wiki.archlinux.org/index.php/Systemd/User
  # sudo loginctl enable-linger $RUN_USER
  systemctl --user --all | grep -F aria2.service >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    systemctl --user stop aria2.service
    systemctl --user disable aria2.service
  fi
fi

podman container inspect aria2 >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  podman stop aria2
  podman rm -f aria2
fi

if [[ "x$ARIA2_UPDATE" != "x" ]] || [[ "x$ROUTER_IMAGE_UPDATE" != "x" ]]; then
  podman image inspect local-aria2 >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    podman image rm -f local-aria2
  fi
fi

mkdir -p "$RUN_HOME/aria2/etc"
mkdir -p "$RUN_HOME/aria2/log"
mkdir -p "$ARIA2_DATA_ROOT/download"
mkdir -p "$ARIA2_DATA_ROOT/session"

curl -qsSL "https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_best.txt" -o "$RUN_HOME/aria2/etc/trackers_best.txt"

echo "
dir=$ARIA2_DATA_ROOT/download
log=/var/log/aria2/aria2.log
save-session=$ARIA2_DATA_ROOT/session/aria2.session
save-session-interval=60
# debug, info, notice, warn or error
log-level=warn
max-concurrent-downloads=5
continue=true
" >$RUN_HOME/aria2/etc/aria2.conf

echo '
# HTTP/FTP/SFTP
split=20
max-tries=5
max-connection-per-server=10
connect-timeout=60
timeout=60
min-split-size=1M

# HTTP
http-accept-gzip=true
user-agent=owent-downloader/1.0
check-certificate=false

# BT/Metalink
# show-files=true # 这个会导致启动不了
enable-dht=true
bt-enable-lpd=true
enable-peer-exchange=true
' >>$RUN_HOME/aria2/etc/aria2.conf

ARIA2_BT_TRACKER=""
for BT_SVR in $(cat "$RUN_HOME/aria2/etc/trackers_best.txt"); do
  if [ ! -z "$ARIA2_BT_TRACKER" ]; then
    ARIA2_BT_TRACKER="$ARIA2_BT_TRACKER,$BT_SVR"
  else
    ARIA2_BT_TRACKER="$BT_SVR"
  fi
done

echo "
bt-tracker=$ARIA2_BT_TRACKER
" >>$RUN_HOME/aria2/etc/aria2.conf

echo '
# Advance
optimize-concurrent-downloads=true
auto-save-interval=600
disk-cache=256M
piece-length=1M

# Set max overall download speed in bytes/sec. 0 means unrestricted. You can append K or M (1K = 1024, 1M = 1024K).
max-overall-download-limit=0
# Set max download speed per each download in bytes/sec. 0 means unrestricted. You can append K or M (1K = 1024, 1M = 1024K)
max-download-limit=0
max-download-result=120

# enable-mmap=false
# epoll, kqueue, port, poll, select
# event-poll=epoll
# none, prealloc, trunc, fallo
# file-allocation=prealloc
# human-readable=true

# SSLv3, TLSv1, TLSv1.1, TLSv1.2
# min-tls-version=TLSv1

listen-port=6881,6882,6883
dht-listen-port=6881,6882,6883

# RPC
enable-rpc=true
pause=false
rpc-listen-all=true 
rpc-allow-origin-all=true 
rpc-listen-port=6800 
# client secret => token:MYPASSWORD
rpc-secret=MYPASSWORD 
rpc-max-request-size=2M

rpc-secure=false
# rpc-certificate=<FILE>
# rpc-private-key=<FILE>
' >>$RUN_HOME/aria2/etc/aria2.conf

chmod 775 "$RUN_HOME/aria2/etc"
chmod 775 "$RUN_HOME/aria2/log"
chmod 775 "$ARIA2_DATA_ROOT/download"
chmod 775 "$ARIA2_DATA_ROOT/session"

chown $RUN_USER -R "$RUN_HOME/aria2/etc"
chown $RUN_USER -R "$RUN_HOME/aria2/log"
chown $RUN_USER -R "$ARIA2_DATA_ROOT/download"
chown $RUN_USER -R "$ARIA2_DATA_ROOT/session"

cd "$(dirname "${BASH_SOURCE[0]}")"

echo '#!/bin/bash
' >aria2c_with_session.sh
echo "
if [[ -e \"$ARIA2_DATA_ROOT/session/aria2.session\" ]]; then
    aria2c --input-file=$ARIA2_DATA_ROOT/session/aria2.session \"\$@\";
else
    aria2c \"\$@\";
fi" >>aria2c_with_session.sh

chmod +x aria2c_with_session.sh
chown $RUN_USER aria2c_with_session.sh

podman build --layers --force-rm --tag local-aria2 -f aria2.Dockerfile .

podman --log-level debug run -d --name aria2 \
  --security-opt label=disable \
  --mount type=bind,source=$RUN_HOME/aria2/etc,target=/etc/aria2 \
  --mount type=bind,source=$RUN_HOME/aria2/log,target=/var/log/aria2 \
  --mount type=bind,source=$ARIA2_DATA_ROOT,target=$ARIA2_DATA_ROOT \
  -p 6800:6800/tcp -p 6881-6883:6881-6883/tcp -p 6881-6883:6881-6883/udp \
  local-aria2 bash /usr/bin/aria2c_with_session.sh --conf-path=/etc/aria2/aria2.conf

podman generate systemd aria2 | tee "$SYSTEMD_SERVICE_DIR/aria2.service"
podman container stop aria2

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
  systemctl daemon-reload
  systemctl enable aria2.service
  systemctl start aria2.service
else
  systemctl --user daemon-reload
  systemctl --user enable "$SYSTEMD_SERVICE_DIR/aria2.service"
  systemctl --user start aria2.service
fi
