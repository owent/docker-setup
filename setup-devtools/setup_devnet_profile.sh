#!/bin/bash

echo "#!/bin/bash

export PATH=$SETUP_INSTALL_PREFIX/bin:\$PATH
export setup_devnet_profile=1
" > /etc/profile.d/devnet.sh ;

if [ "x" != "$SETUP_INSTALL_PROXY" ]; then
    echo "
# common
export http_proxy=$SETUP_INSTALL_PROXY
export https_proxy=\$http_proxy
export ftp_proxy=\$http_proxy
export rsync_proxy=\$http_proxy
" >> /etc/profile.d/devnet.sh ;

    if [ "x" != "$SETUP_INSTALL_NO_PROXY" ]; then
        echo "export no_proxy=$SETUP_INSTALL_NO_PROXY" >> /etc/profile.d/devnet.sh ;
    fi
fi

echo '
# golang
export GO111MODULE=on
#export GOPROXY=$http_proxy,direct,https://goproxy.io
' >> /etc/profile.d/devnet.sh ;
chmod +x /etc/profile.d/devnet.sh ;

echo '
if [ "x" == "x${setup_devnet_profile}" ]; then
    source /etc/profile.d/devnet.sh
fi
' >> /root/.bashrc ;
