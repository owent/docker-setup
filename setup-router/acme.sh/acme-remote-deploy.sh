#!/bin/bash

INSTALL_CERT_DIR=/home/tools/bitwarden/ssl
REMOTE_DEPLOY_KEY=<path of id_ed25519>
REMOTE_DEPLOY_SSL_PATH=/home/website/ssl/

# Update local services
if [[ "x$1" == "xupdate-v2ray" ]] || [[ "x$1" == "xupdate-vproxy" ]]; then
    env V2RAY_UPDATE=1 bash /data/vproxy/setup.sh ;
else
    bash /data/vproxy/update.sh ;
fi

echo "" > sync-to-replications.log ;
REPLICATION_NODES=(
  "USER@HOST:PORT"
);

for NODE_ADDR in ${REPLICATION_NODES[@]}; do
    NODE_USER=${NODE_ADDR//@*};
    NODE_HOST_PORT=${NODE_ADDR/*@};
    NODE_HOST=${NODE_HOST_PORT//:*};
    NODE_PORT=${NODE_ADDR/*:};

    echo "============ Upload SSL files to $NODE_USER@$NODE_HOST:$NODE_PORT ... " 

    ssh -p $NODE_PORT -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o User=$NODE_USER -i $REMOTE_DEPLOY_KEY "$NODE_USER@$NODE_HOST" "mkdir -p $REMOTE_DEPLOY_SSL_PATH" 
    scp -P $NODE_PORT -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o User=$NODE_USER -i \
      "$REMOTE_DEPLOY_KEY" "$INSTALL_CERT_DIR/$DOMAIN_NAME.cer"                                         \
      "$INSTALL_CERT_DIR/$DOMAIN_NAME.key" "$INSTALL_CERT_DIR/fullchain.cer"                            \
      "$NODE_USER@$NODE_HOST:$REMOTE_DEPLOY_SSL_PATH"
    ssh -p $NODE_PORT -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o User=$NODE_USER -i "$REMOTE_DEPLOY_KEY" "$NODE_USER@$NODE_HOST" "cd $REMOTE_DEPLOY_SSL_PATH && chmod 640 *"
done

# Update remote services
for NODE_ADDR in ${REPLICATION_NODES[@]}; do
    NODE_USER=${NODE_ADDR//@*};
    NODE_HOST_PORT=${NODE_ADDR/*@};
    NODE_HOST=${NODE_HOST_PORT//:*};
    NODE_PORT=${NODE_ADDR/*:};

    echo "============ Update $NODE_USER@$NODE_HOST:$NODE_PORT ... " 

    ssh -p $NODE_PORT -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o User=$NODE_USER -i $REMOTE_DEPLOY_KEY $NODE_USER@$NODE_HOST "mkdir -p /data/vproxy" 

    scp -r -P $NODE_PORT -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o User=$NODE_USER -i \
      "$REMOTE_DEPLOY_KEY" /data/vproxy/etc /data/vproxy/*.sh "$NODE_USER@$NODE_HOST:/data/vproxy/"

    if [[ "x$1" == "xupdate-v2ray" ]] || [[ "x$1" == "xupdate-vproxy" ]]; then
        ssh -p $NODE_PORT -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o User=$NODE_USER -i "$REMOTE_DEPLOY_KEY" "$NODE_USER@$NODE_HOST" "env V2RAY_UPDATE=1 bash /data/vproxy/setup.sh" 
    else
    ssh -p $NODE_PORT -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o User=$NODE_USER -i "$REMOTE_DEPLOY_KEY" "$NODE_USER@$NODE_HOST" "bash /data/vproxy/update.sh"
    fi
done