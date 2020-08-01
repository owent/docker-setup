# podman build --layers --force-rm --tag local-v2ray -f v2ray.Dockerfile .
# docker build --force-rm --tag local-v2ray -f v2ray.Dockerfile .
FROM debian:latest as builder

RUN sed -i.bak -r 's;#?https?://.*/debian-security/?[[:space:]];http://mirrors.aliyun.com/debian-security/ ;g' /etc/apt/sources.list ; \
    sed -i -r 's;#?https?://.*/debian/?[[:space:]];http://mirrors.aliyun.com/debian/ ;g' /etc/apt/sources.list ; \
    apt update -y;                                          \
    apt install curl -y;                                    \
    curl -k -L --retry 10 --retry-max-time 1800 -o /tmp/go.sh https://install.direct/go.sh;     \
    chmod +x /tmp/go.sh;                                    \
    bash /tmp/go.sh;                                        \
    curl -k -qL "https://github.com/owent/update-geoip-geosite/releases/download/latest/geoip.dat" -o /usr/bin/v2ray/geoip.dat ;      \
    curl -k -qL "https://github.com/owent/update-geoip-geosite/releases/download/latest/geosite.dat" -o /usr/bin/v2ray/geosite.dat ;  \
    if [ -e "/var/lib/apt/lists" ]; then for APT_CACHE in /var/lib/apt/lists/* ; do rm -rf "$APT_CACHE"; done fi

FROM docker.io/alpine:latest

LABEL maintainer "OWenT <admin@owent.net>"

COPY --from=builder /usr/bin/v2ray/v2ray /usr/bin/v2ray/
COPY --from=builder /usr/bin/v2ray/v2ctl /usr/bin/v2ray/
COPY --from=builder /usr/bin/v2ray/geoip.dat /usr/bin/v2ray/
COPY --from=builder /usr/bin/v2ray/geosite.dat /usr/bin/v2ray/
COPY --from=builder /etc/v2ray/config.json /etc/v2ray/config.json

# sed -i -r 's#dl-cdn.alpinelinux.org#mirrors.tencent.com#g' /etc/apk/repositories ; \
RUN set -ex ;                                       \
    sed -i -r 's#dl-cdn.alpinelinux.org#mirrors.aliyun.com#g' /etc/apk/repositories ; \
    apk --no-cache add ca-certificates tzdata ;     \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime ; \
    mkdir /var/log/v2ray/ ;                         \
    chmod +x /usr/bin/v2ray/v2ctl ;                 \
    chmod +x /usr/bin/v2ray/v2ray ;

ENV PATH /usr/bin/v2ray:$PATH

VOLUME /data/logs/v2ray

CMD ["v2ray", "-config=/etc/v2ray/config.json"]

# podman run -d --name v2ray -v /etc/v2ray:/etc/v2ray -v /data/logs/v2ray:/data/logs/v2ray --cap-add=NET_ADMIN --network=host localhost/local-v2ray v2ray -config=/etc/v2ray/config.json
# podman generate systemd v2ray | sudo tee /lib/systemd/system/v2ray.service
# sudo systemctl daemon-reload