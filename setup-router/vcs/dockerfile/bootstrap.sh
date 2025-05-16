#!/bin/bash

if [[ ! -z "$P4SSLDIR" ]]; then
    mkdir -p "$P4SSLDIR"
    chmod 700 "$P4SSLDIR"

    if [[ ! -e "$P4SSLDIR/certificate.txt" ]] || [[ ! -e "$P4SSLDIR/privatekey.txt" ]]; then
        p4d -Gc
    fi
fi

exec "$@"
