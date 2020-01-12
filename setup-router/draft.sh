if [ -e "/lib/systemd/system" ]; then
    export SETUP_SYSTEMD_SYSTEM_DIR=/lib/systemd/system;
elif [ -e "/usr/lib/systemd/system" ]; then
    export SETUP_SYSTEMD_SYSTEM_DIR=/usr/lib/systemd/system;
elif [ -e "/etc/systemd/system" ]; then
    export SETUP_SYSTEMD_SYSTEM_DIR=/etc/systemd/system;
**fi**
fi


podman kill -f =>  podman kill