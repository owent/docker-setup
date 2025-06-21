#!/bin/bash

if [[ -z "$CFSSL_LATEST_VERSION" ]]; then
    CFSSL_LATEST_VERSION=$(curl -L $GITHUB_TOKEN_ARGS 'https://api.github.com/repos/cloudflare/cfssl/releases/latest' | grep tag_name | grep -E -o 'v[0-9]+[0-9\.]+' | head -n 1)
fi

CFSSL_LATEST_VERSION_NO="${CFSSL_LATEST_VERSION#v}"

ARCH_SUFFIX=linux_amd64
mkdir -p "$CFSSL_LATEST_VERSION"
mkdir -p "$CFSSL_LATEST_VERSION.tmp"

trap "rm -rf $CFSSL_LATEST_VERSION.tmp" EXIT

for bin_name in cfssl-bundle cfssl-certinfo cfssl-newkey cfssl_scan cfssljson cfssl mkbundle multirootca; do
    if [[ ! -e "$CFSSL_LATEST_VERSION/$bin_name" ]]; then
        echo "Downloading: $bin_name"
        curl --retry 3 -L "https://github.com/cloudflare/cfssl/releases/download/${CFSSL_LATEST_VERSION}/${bin_name}_${CFSSL_LATEST_VERSION_NO}_${ARCH_SUFFIX}" -o "$CFSSL_LATEST_VERSION.tmp/$bin_name"
        if [[ $? -ne 0 ]]; then
            echo "Failed to download $bin_name for version $CFSSL_LATEST_VERSION"
            continue
        fi
        mv -f "$CFSSL_LATEST_VERSION.tmp/$bin_name" "$CFSSL_LATEST_VERSION/$bin_name"
        chmod +x "$CFSSL_LATEST_VERSION/$bin_name"
        echo "Downloaded: $bin_name"
    else
        echo "Skipping download for $bin_name, already exists."
    fi
done

ln -sf "./$CFSSL_LATEST_VERSION/"* "$PWD/"
