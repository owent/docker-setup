FROM docker.io/caddy:builder AS builder

RUN xcaddy build --with github.com/caddy-dns/cloudflare --with github.com/caddy-dns/dnspod

FROM docker.io/caddy:latest

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
COPY Caddyfile /etc/caddy/Caddyfile

EXPOSE 80
EXPOSE 443

# 容器启动命令
CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
