#!/bin/bash

echo '#!/bin/bash

export PATH=/opt/git/latest/bin:/opt/git-lfs/latest/bin:/opt/zsh/latest/bin:/opt/tmux/latest/bin:/opt/golang/lastest/bin:/opt/nodejs/latest/bin:/opt/cmake/latest/bin:/opt/ninja-build/latest:$PATH
export setup_devnet_profile=1
' > /etc/profile.d/devnet.sh ;

if [ "x" != "$SETUP_INSTALL_PROXY" ]; then
    echo "
# common
export http_proxy=$SETUP_INSTALL_PROXY
export https_proxy=\$http_proxy
export ftp_proxy=\$http_proxy
export rsync_proxy=\$http_proxy
" >> /etc/profile.d/devnet.sh ;

    if [ "x" != "x$SETUP_INSTALL_NO_PROXY" ]; then
        echo "export no_proxy=$SETUP_INSTALL_NO_PROXY" >> /etc/profile.d/devnet.sh ;
    fi
fi

mkdir -p ~/.ssh ;
chmod 700 ~/.ssh ;
echo "
PATH=/opt/git/latest/bin:/opt/git-lfs/latest/bin:/opt/zsh/latest/bin:/opt/tmux/latest/bin:/opt/golang/lastest/bin:/opt/nodejs/latest/bin:/opt/cmake/latest/bin:/opt/ninja-build/latest:/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:$HOME/.dotnet/tools:$HOME/bin
setup_devnet_profile=1
http_proxy=$SETUP_INSTALL_PROXY
https_proxy=$SETUP_INSTALL_PROXY
ftp_proxy=$SETUP_INSTALL_PROXY
rsync_proxy=$SETUP_INSTALL_PROXY
" > ~/.ssh/environment ;
if [ "x" != "x$SETUP_INSTALL_NO_PROXY" ]; then
    "export no_proxy=$SETUP_INSTALL_NO_PROXY" >> ~/.ssh/environment ;
fi
chmod 600 ~/.ssh/environment ;

echo '
# golang
export GO111MODULE=on
#export GOPROXY=$http_proxy,direct,https://goproxy.io

export PATH=/opt/git/latest/bin:/opt/git-lfs/latest/bin:/opt/zsh/latest/bin:/opt/tmux/latest/bin:/opt/golang/lastest/bin:/opt/nodejs/latest/bin:/opt/cmake/latest/bin:/opt/ninja-build/latest:$PATH
export setup_devnet_profile=1
' >> /etc/profile.d/devnet.sh ;
chmod +x /etc/profile.d/devnet.sh ;

echo '
if [ "x" == "x${setup_devnet_profile}" ]; then
    source /etc/profile.d/devnet.sh
fi
' >> /root/.bashrc ;
