#!/bin/bash

# npm config set registry https://registry.npmmirror.com
npm config set registry http://mirrors.tencent.com/npm/
npm config set strict-ssl false
npm config delete proxy
npm config delete https-proxy

# bun componentsS
bun install -g clawhub@latest
bun install -g mcporter@latest
