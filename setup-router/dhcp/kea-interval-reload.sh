#!/bin/bash

export PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# systemctl reload kea-ctrl-agent
systemctl reload kea-dhcp4
systemctl reload kea-dhcp6
