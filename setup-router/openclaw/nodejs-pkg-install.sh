#!/bin/bash

# npm config set registry https://registry.npmmirror.com
npm config set registry http://mirrors.tencent.com/npm/
npm config set strict-ssl false
npm config delete proxy
npm config delete https-proxy

echo '#!/bin/bash
export PNPM_HOME=/app/pnpm
export PATH=$PNPM_HOME:$PATH
' > /etc/profile.d/pnpm.sh
chmod +x /etc/profile.d/pnpm.sh

source /etc/profile.d/pnpm.sh

# npx components
pnpm install -g clawhub@latest
pnpm install -g mcporter@latest
