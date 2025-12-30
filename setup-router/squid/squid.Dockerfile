FROM alpine:latest
RUN sed -i.bak -r 's#dl-cdn.alpinelinux.org#mirrors.tencent.com#g' /etc/apk/repositories ; \
  apk add --no-cache squid ca-certificates tzdata bash vim python3 && update-ca-certificates

RUN set -e; \
  mkdir -p /var/spool/squid /var/cache/squid /var/run/squid /etc/squid/ssl; \
  chown -R squid:squid /var/spool/squid /var/cache/squid /var/log/squid /var/run/squid;

EXPOSE 3128 3128

CMD ["/bin/bash", "-c", "if [[ ! -e '/var/spool/squid/swap.state' ]]; then squid -z -f /etc/squid/squid.conf; fi; rm -f /var/run/squid.pid; exec squid --foreground -f /etc/squid/squid.conf"]
