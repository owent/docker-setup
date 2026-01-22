#!/bin/bash

if [[ ! -z "$P4SSLDIR" ]]; then
    mkdir -p "$P4SSLDIR"
    chmod 700 "$P4SSLDIR"

    if [[ ! -e "$P4SSLDIR/certificate.txt" ]] || [[ ! -e "$P4SSLDIR/privatekey.txt" ]]; then
        p4d -Gc
    fi
fi

if [[ ! -z "$P4LOG" ]]; then
    LOGDIR="$(dirname "$P4LOG")"
elif [[ ! -z "$P4JOURNAL" ]]; then
    LOGDIR="$(dirname "$P4JOURNAL")"
elif [[ ! -z "$P4ROOT" ]]; then
    mkdir -p "$P4ROOT/log" && chmod 777 "$P4ROOT/log" && LOGDIR="$P4ROOT/log"
fi

if [[ ! -z "$LOGDIR" ]]; then
    if [[ ! -e "$LOGDIR/supervisor" ]]; then
        mkdir -p "$LOGDIR/supervisor"
        chmod 777 "$LOGDIR/supervisor"
    fi

    if [[ "$LOGDIR/supervisor" != "/var/log/supervisor" ]]; then
        if [[ -e "/var/log/supervisor" ]]; then
            rm -rf /var/log/supervisor
        fi
        ln -s "$LOGDIR/supervisor" /var/log/supervisor
    fi
else
    mkdir -p /var/log/supervisor
fi

if [[ ! -z "$P4LOG" ]]; then
    cat <<EOF >> /etc/logrotate.d/p4d
$P4LOG
{
  rotate 15
  daily
  minsize 1M
  maxsize 50M

  nocopy
  compress
  delaycompress
  missingok
}

EOF
fi

# Install cron job to rotate journal
if [[ ! -z "$P4JOURNAL" ]]; then
    LOGDIR="$(dirname "$P4JOURNAL")"
    echo '#!/bin/bash' > /opt/p4d-rotate-journal.sh
    echo "export PATH=$PATH" >> /opt/p4d-rotate-journal.sh
    for ENV_KV in $(env | grep P4); do
        echo "export $ENV_KV" >> /opt/p4d-rotate-journal.sh
    done
    echo "$(which p4d) -jj $LOGDIR/journal.bak" >> /opt/p4d-rotate-journal.sh
    echo "find $LOGDIR/ -name 'journal.bak*' -mtime +15 -exec rm -f '{}' \;" >> /opt/p4d-rotate-journal.sh
    chmod +x /opt/p4d-rotate-journal.sh
    crontab -l | grep p4d-rotate-journal || echo '0 */4 * * * /bin/bash /opt/p4d-rotate-journal.sh' | crontab -
fi
# Install cron job for logrotate if not already present
crontab -l | grep logrotate || echo '0 */4 * * * /usr/sbin/logrotate /etc/logrotate.conf' | crontab -

exec "$@"
