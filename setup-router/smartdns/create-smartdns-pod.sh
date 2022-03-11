#!/bin/bash

# Maybe need in /etc/ssh/sshd_config
#     DenyUsers tools
#     DenyGroups tools

if [ -e "/opt/nftables/sbin" ]; then
    export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd)"

if [[ "x$ROUTER_HOME" == "x" ]]; then
    source "$SCRIPT_DIR/../configure-router.sh"
fi

if [[ "x$RUN_USER" == "x" ]]; then
    RUN_USER=tools;
fi
RUN_HOME=$(cat /etc/passwd | awk "BEGIN{FS=\":\"} \$1 == \"$RUN_USER\" { print \$6 }")

if [[ "x$RUN_HOME" == "x" ]]; then
    RUN_HOME="$HOME";
    RUN_USER=$(whoami);
fi

if [[ "root" == "$(whoami)" ]]; then
    SYSTEMD_SERVICE_DIR=/lib/systemd/system ;
else
    SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user" ;
    mkdir -p "$SYSTEMD_SERVICE_DIR";
fi

if [[ "x$SMARTDNS_DNS_PORT" == "x" ]]; then
    SMARTDNS_DNS_PORT=53;
fi

if [[ "x$SMARTDNS_ETC_DIR" == "x" ]]; then
    export SMARTDNS_ETC_DIR="$RUN_HOME/smartdns/etc"
fi
mkdir -p "$SMARTDNS_ETC_DIR"

if [[ "x$SMARTDNS_LOG_DIR" == "x" ]]; then
    export SMARTDNS_LOG_DIR="$RUN_HOME/smartdns/log"
fi
mkdir -p "$SMARTDNS_LOG_DIR"

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
    systemctl --all | grep -F smartdns.service > /dev/null 2>&1 ;
    if [ $? -eq 0 ]; then
        systemctl stop smartdns.service
        systemctl disable smartdns.service
    fi
else
    export XDG_RUNTIME_DIR="/run/user/$UID"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

    # Maybe need run from host: loginctl enable-linger tools
    # see https://wiki.archlinux.org/index.php/Systemd/User
    # sudo loginctl enable-linger $RUN_USER
    systemctl --user --all | grep -F smartdns.service > /dev/null 2>&1 ;
    if [ $? -eq 0 ]; then
        systemctl --user stop smartdns.service
        systemctl --user disable smartdns.service
    fi
fi

podman container inspect smartdns > /dev/null 2>&1
if [[ $? -eq 0 ]]; then
    podman stop smartdns
    podman rm -f smartdns
fi

if [[ "x$V2RAY_UPDATE" != "x" ]]; then
    podman image inspect docker.io/owt5008137/smartdns:latest > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        podman image rm -f docker.io/owt5008137/smartdns:latest ;
    fi
fi

bash "$SCRIPT_DIR/merge-configure.sh"

podman run -d --name smartdns                                               \
    --mount type=bind,source=$SMARTDNS_ETC_DIR,target=/usr/local/smartdns/etc  \
    --mount type=bind,source=$SMARTDNS_LOG_DIR,target=/var/log/smartdns     \
    -p $SMARTDNS_DNS_PORT:$SMARTDNS_DNS_PORT/tcp                            \
    -p $SMARTDNS_DNS_PORT:$SMARTDNS_DNS_PORT/udp                            \
    docker.io/owt5008137/smartdns:latest

podman generate systemd smartdns | tee "$SYSTEMD_SERVICE_DIR/smartdns.service"

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
    systemctl daemon-reload
    systemctl enable smartdns.service
    systemctl start smartdns.service
else
    systemctl --user daemon-reload
    systemctl --user enable "$SYSTEMD_SERVICE_DIR/smartdns.service"
    systemctl --user start smartdns.service
fi

