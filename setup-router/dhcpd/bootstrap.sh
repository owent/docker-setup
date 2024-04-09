#!/bin/bash

set -x

mkdir -p /run/kea /run/lock/kea /var/lib/kea /var/log/supervisor /etc/supervisor/conf.d

chmod 775 -R /run/kea /run/lock/kea /var/lib/kea

if [[ "x$KEA_USER" == "x" ]]; then
  KEA_USER=$(id -u -n)
fi

chown $KEA_USER -R /run/kea /run/lock/kea /var/lib/kea

exec "$@"
