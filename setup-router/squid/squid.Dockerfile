FROM alpine:latest

RUN sed -i.bak -r 's#dl-cdn.alpinelinux.org#mirrors.tencent.com#g' /etc/apk/repositories ; \
  apk add --no-cache squid ca-certificates tzdata bash vim python3 supervisor curl bind-tools && update-ca-certificates

RUN set -e; \
  mkdir -p /var/spool/squid /var/cache/squid /var/run/squid /etc/squid/ssl /var/log/supervisor; \
  chown -R squid:squid /var/spool/squid /var/cache/squid /var/log/squid /var/run/squid;

# 复制 supervisor 配置
COPY supervisor/supervisord.conf /etc/supervisord.conf

EXPOSE 3128 3128

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
