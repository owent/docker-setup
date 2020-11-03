#!/bin/bash

if [ -e "/opt/nftables/sbin" ]; then
    export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

if [[ "root" == "$(whoami)" ]]; then
    SYSTEMD_SERVICE_DIR=/lib/systemd/system ;
else
    SYSTEMD_SERVICE_DIR="$HOME/.config/systemd/user" ;
    mkdir -p "$SYSTEMD_SERVICE_DIR";
fi

if [[ "$SYSTEMD_SERVICE_DIR" == "/lib/systemd/system" ]]; then
   systemctl restart nginx.service ;
else
    export XDG_RUNTIME_DIR="/run/user/$UID"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

    # Maybe need run from host: loginctl enable-linger tools
    # see https://wiki.archlinux.org/index.php/Systemd/User
    # sudo loginctl enable-linger $RUN_USER
    systemctl --user restart nginx.service
fi
