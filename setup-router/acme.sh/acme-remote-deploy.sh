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
  "USER@HOST:PORT:SSL_KEY_PATH"
);

# # Squid certs
# SQUID_CERT_UPDATE_WEEKNO=-100
# set -x
# cd /data/cfssl
# if [[ -e squid-cert.datetime ]]; then
#   SQUID_CERT_UPDATE_WEEKNO=$(cat squid-cert.datetime)
# fi
# NOW_WEEKNO=$(date +%W)
# if [[ ${NOW_WEEKNO:0:1} == 0 ]]; then
#   NOW_WEEKNO=${NOW_WEEKNO:1}
# fi
# if [[ $(($SQUID_CERT_UPDATE_WEEKNO-$NOW_WEEKNO)) -gt 2 ]] || [[ $(($NOW_WEEKNO-$SQUID_CERT_UPDATE_WEEKNO)) -gt 2 ]]; then
#   ./gen_squid.sh
#   scp -P 36000 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o User=tools -i \
#       "$REMOTE_DEPLOY_KEY" squid-cert-key.pem squid-fullchain.pem \
#       "tools@10.64.5.1:/data/squid/etc/ssl/"
# fi
# cd -
# set +x

for NODE_ADDR in ${REPLICATION_NODES[@]}; do
    NODE_USER="${NODE_ADDR%%@*}"
    NODE_REMAINDER="${NODE_ADDR#*@}"
    IFS=':' read -r NODE_HOST NODE_PORT NODE_KEY <<< "$NODE_REMAINDER"

    LOCAL_DEPLOY_KEY="$REMOTE_DEPLOY_KEY"
    if [[ -n "$NODE_KEY" ]]; then
        LOCAL_DEPLOY_KEY="$NODE_KEY"
    fi

    echo "============ Upload SSL files to $NODE_USER@$NODE_HOST:$NODE_PORT ... " 

    for INSTALL_CERT_DIR in "$ACMESH_SSL_DIR/${DOMAIN_NAME}_ecc" "$ACMESH_SSL_DIR/${DOMAIN_NAME}"; do
        if [[ ! -e "$INSTALL_CERT_DIR/$DOMAIN_NAME.cer" ]]; then
            continue
        fi
        REMOTE_DEPLOY_SSL_PATH=$INSTALL_CERT_DIR
        ssh -p $NODE_PORT -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o User=$NODE_USER -i "$LOCAL_DEPLOY_KEY" "$NODE_USER@$NODE_HOST" "mkdir -p $REMOTE_DEPLOY_SSL_PATH" 
        scp -P $NODE_PORT -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o User=$NODE_USER -i \
          "$LOCAL_DEPLOY_KEY" "$INSTALL_CERT_DIR/$DOMAIN_NAME.cer"                                         \
          "$INSTALL_CERT_DIR/$DOMAIN_NAME.key" "$INSTALL_CERT_DIR/fullchain.cer"                            \
          "$NODE_USER@$NODE_HOST:$REMOTE_DEPLOY_SSL_PATH"
        ssh -p $NODE_PORT -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o User=$NODE_USER -i "$LOCAL_DEPLOY_KEY" "$NODE_USER@$NODE_HOST" "cd $REMOTE_DEPLOY_SSL_PATH && chmod 640 *"
    done
done

# Update remote services
for NODE_ADDR in ${REPLICATION_NODES[@]}; do
    NODE_USER="${NODE_ADDR%%@*}"
    NODE_REMAINDER="${NODE_ADDR#*@}"
    IFS=':' read -r NODE_HOST NODE_PORT NODE_KEY <<< "$NODE_REMAINDER"

    LOCAL_DEPLOY_KEY="$REMOTE_DEPLOY_KEY"
    if [[ -n "$NODE_KEY" ]]; then
        LOCAL_DEPLOY_KEY="$NODE_KEY"
    fi

    echo "============ Update $NODE_USER@$NODE_HOST:$NODE_PORT ... " 

    ssh -p $NODE_PORT -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o User=$NODE_USER -i "$LOCAL_DEPLOY_KEY" "$NODE_USER@$NODE_HOST" "mkdir -p /data/vbox-server" 

    scp -r -P $NODE_PORT -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o User=$NODE_USER -i \
      "$LOCAL_DEPLOY_KEY" /data/vbox-server/etc /data/vbox-server/*.sh "$NODE_USER@$NODE_HOST:/data/vbox-server/"

    if [[ "x$1" == "xupdate-v2ray" ]] || [[ "x$1" == "xupdate-vproxy" ]] || [[ "x$1" == "xupdate-vbox" ]]; then
        ssh -p $NODE_PORT -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o User=$NODE_USER -i "$LOCAL_DEPLOY_KEY" "$NODE_USER@$NODE_HOST" "env VBOX_UPDATE=1 bash /data/vbox-server/setup-server.sh" 
    else
        ssh -p $NODE_PORT -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o User=$NODE_USER -i "$LOCAL_DEPLOY_KEY" "$NODE_USER@$NODE_HOST" "bash /data/vbox-server/setup-server.sh"
    fi
done