FROM alpine:latest

# podman build --layers --force-rm --tag local-aria2 -f aria2.Dockerfile .
# docker build --force-rm --tag local-aria2 -f aria2.Dockerfile .

LABEL maintainer "OWenT <admin@owent.net>"

VOLUME ["/etc/kea", "/var/lib/kea/"]

RUN set -ex ; \
  sed -i.bak -r 's#dl-cdn.alpinelinux.org#mirrors.tencent.com#g' /etc/apk/repositories; \
  apk add --no-cache bash kea kea-dhcp4 kea-dhcp6 kea-ctrl-agent kea-hooks kea-hook-lease-query; \
  apk add --no-cache kea-hook-limits kea-hook-ha kea-hook-host-cmds kea-hook-host-cache kea-hook-lease-cmds; \
  apk add --no-cache kea-hook-host-cmds kea-hook-lease-query kea-hook-stat-cmds kea-hook-subnet-cmds ; \
  apk add --no-cache kea-hook-class-cmds kea-hook-flex-id kea-hook-flex-option kea-hook-host-cache ; \
  apk add --no-cache kea-hook-perfmon kea-hook-run-script supervisor

RUN set -ex ; \
  mkdir -p /run/kea /var/kea /var/run/kea /run/lock/kea /var/log/supervisor /etc/supervisor/conf.d ; \
  touch /run/kea/logger_lockfile; chmod -R 777 /run/kea /run/lock/kea; chown -R kea /run/kea /run/lock/kea; \
  chmod 777 -R /var/lib/kea/; chown -R kea /var/lib/kea/

COPY bootstrap.sh /usr/sbin/bootstrap.sh
COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY supervisor-kea-dhcp4.conf /etc/supervisor/conf.d/kea-dhcp4.conf
# COPY supervisor-kea-agent.conf /etc/supervisor/conf.d/kea-agent.conf

EXPOSE 67/tcp 67/udp

ENV KEA_LOCKFILE_DIR=/run/lock/kea

CMD ["/bin/bash", "/usr/sbin/bootstrap.sh", "/usr/sbin/kea-dhcp4", "-c", "/etc/kea/kea-dhcp4.conf"]
# CMD ["/bin/bash", "/usr/sbin/bootstrap.sh", "supervisord", "-c", "/etc/supervisor/supervisord.conf"]
# HEALTHCHECK CMD [ "supervisorctl", "status" ]
