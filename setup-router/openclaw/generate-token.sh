#!/bin/bash

export XDG_RUNTIME_DIR="/run/user/$UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

podman exec openclaw node openclaw.mjs dashboard --no-open
