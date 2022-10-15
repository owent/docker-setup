#!/bin/bash

# @see https://linux.die.net/man/8/pppd
#
# When the ppp link comes up, this script is called with the following
# parameters
#       $1      the interface name used by pppd (e.g. ppp3)
#       $2      the tty device name
#       $3      the tty device speed
#       $4      the local IP address for the interface
#       $5      the remote IP address
#       $6      the parameter specified by the 'ipparam' option to pppd
#

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

# Using journalctl -t router-ppp to see this log
echo "[$(date "+%F %T")]: $0 $@" | systemd-cat -t router-ppp -p info

# ip -6 route delete ::/0 via $IPREMOTE dev $IFNAME ;
