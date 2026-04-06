#!/bin/bash

SUPERVISOR_CONF_DIR=/etc/supervisor/conf.d
mkdir -p "$SUPERVISOR_CONF_DIR"

# Generate openclaw supervisor config from command-line arguments
OPENCLAW_CMD="$*"
if [[ -z "$OPENCLAW_CMD" ]]; then
  OPENCLAW_CMD="node openclaw.mjs gateway --allow-unconfigured --bind lan --port 18789"
fi

cat >"$SUPERVISOR_CONF_DIR/openclaw.conf" <<EOFCFG
[program:openclaw]
command=$OPENCLAW_CMD
directory=/app
autostart=true
autorestart=true
startsecs=5
startretries=3
stderr_logfile=/dev/stderr
stdout_logfile=/dev/stdout
EOFCFG

# OPENCLAW_REDIR_PROXY: comma-separated socat redirections
# Format: LOCAL_PORT=REMOTE_HOST:REMOTE_PORT[,...]
# Example: OPENCLAW_REDIR_PROXY="4000=litellm:4000,8080=proxy:8080"
# This creates socat forwarding from 127.0.0.1:LOCAL_PORT to REMOTE_HOST:REMOTE_PORT
# Useful when openclaw only allows loopback proxy connections
if [[ -n "$OPENCLAW_REDIR_PROXY" ]]; then
  IFS=',' read -ra PROXY_ENTRIES <<< "$OPENCLAW_REDIR_PROXY"
  for entry in "${PROXY_ENTRIES[@]}"; do
    entry="$(echo "$entry" | xargs)" # trim whitespace
    LOCAL_PORT="${entry%%=*}"
    REMOTE_ADDR="${entry#*=}"
    if [[ -n "$LOCAL_PORT" ]] && [[ -n "$REMOTE_ADDR" ]]; then
      cat >"$SUPERVISOR_CONF_DIR/socat-redir-${LOCAL_PORT}.conf" <<EOFCFG
[program:socat-redir-${LOCAL_PORT}]
command=socat TCP-LISTEN:${LOCAL_PORT},bind=127.0.0.1,fork,reuseaddr TCP:${REMOTE_ADDR}
autostart=true
autorestart=true
startsecs=1
startretries=10
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
EOFCFG
      echo "Configured socat redirect: 127.0.0.1:${LOCAL_PORT} -> ${REMOTE_ADDR}"
    fi
  done
fi

exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
