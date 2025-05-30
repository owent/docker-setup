#!/bin/bash

DOMAIN_NAME=owent.net
ACMESH_SSL_DIR=/data/website/ssl
REMOTE_DEPLOY_KEY=<path of id_ed25519>

# Update local services
if [[ "x$1" == "xupdate-v2ray" ]] || [[ "x$1" == "xupdate-vproxy" ]] || [[ "x$1" == "xupdate-vbox" ]]; then
    env VBOX_UPDATE=1 bash /data/vbox-server/setup-server.sh
else
    bash /data/vbox-server/update-server.sh
fi

echo "" > sync-to-replications.log
REPLICATION_NODES=(
  "USER@HOST:PORT"
);

for NODE_ADDR in ${REPLICATION_NODES[@]}; do
    NODE_USER=${NODE_ADDR//@*};
    NODE_HOST_PORT=${NODE_ADDR/*@};
    NODE_HOST=${NODE_HOST_PORT//:*};
    NODE_PORT=${NODE_ADDR/*:};

    echo "============ Upload SSL files to $NODE_USER@$NODE_HOST:$NODE_PORT ... " 

    for INSTALL_CERT_DIR in "$ACMESH_SSL_DIR/${DOMAIN_NAME}_ecc" "$ACMESH_SSL_DIR/${DOMAIN_NAME}"; do
        if [[ ! -e "$INSTALL_CERT_DIR/$DOMAIN_NAME.cer" ]]; then
            continue
        fi
        REMOTE_DEPLOY_SSL_PATH=$INSTALL_CERT_DIR
        ssh -p $NODE_PORT -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o User=$NODE_USER -i $REMOTE_DEPLOY_KEY "$NODE_USER@$NODE_HOST" "mkdir -p $REMOTE_DEPLOY_SSL_PATH" 
        scp -P $NODE_PORT -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o User=$NODE_USER -i \
          "$REMOTE_DEPLOY_KEY" "$INSTALL_CERT_DIR/$DOMAIN_NAME.cer"                                         \
          "$INSTALL_CERT_DIR/$DOMAIN_NAME.key" "$INSTALL_CERT_DIR/fullchain.cer"                            \
          "$NODE_USER@$NODE_HOST:$REMOTE_DEPLOY_SSL_PATH"
        ssh -p $NODE_PORT -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o User=$NODE_USER -i "$REMOTE_DEPLOY_KEY" "$NODE_USER@$NODE_HOST" "cd $REMOTE_DEPLOY_SSL_PATH && chmod 640 *"
    done
    # ssh -p $NODE_PORT -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o User=$NODE_USER -i "$REMOTE_DEPLOY_KEY" "$NODE_USER@$NODE_HOST" "cd $REMOTE_DEPLOY_SSL_PATH && chmod 640 *"
done

# Update remote services
for NODE_ADDR in ${REPLICATION_NODES[@]}; do
    NODE_USER=${NODE_ADDR//@*};
    NODE_HOST_PORT=${NODE_ADDR/*@};
    NODE_HOST=${NODE_HOST_PORT//:*};
    NODE_PORT=${NODE_ADDR/*:};

    echo "============ Update $NODE_USER@$NODE_HOST:$NODE_PORT ... " 

    ssh -p $NODE_PORT -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o User=$NODE_USER -i $REMOTE_DEPLOY_KEY $NODE_USER@$NODE_HOST "mkdir -p /data/vbox-server" 

    scp -r -P $NODE_PORT -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o User=$NODE_USER -i \
      "$REMOTE_DEPLOY_KEY" /data/vbox-server/etc /data/vbox-server/*.sh "$NODE_USER@$NODE_HOST:/data/vbox-server/"

    if [[ "x$1" == "xupdate-v2ray" ]] || [[ "x$1" == "xupdate-vproxy" ]] || [[ "x$1" == "xupdate-vbox" ]]; then
        ssh -p $NODE_PORT -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o User=$NODE_USER -i "$REMOTE_DEPLOY_KEY" "$NODE_USER@$NODE_HOST" "env VBOX_UPDATE=1 bash /data/vbox-server/setup-server.sh" 
    else
    ssh -p $NODE_PORT -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o User=$NODE_USER -i "$REMOTE_DEPLOY_KEY" "$NODE_USER@$NODE_HOST" "bash /data/vbox-server/setup-server.sh"
    fi
done