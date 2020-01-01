# podman build --layers --force-rm --tag local-v2ray -f v2ray.Dockerfile
# docker build --layers --force-rm --tag local-v2ray -f v2ray.Dockerfile
FROM debian:latest as builder

RUN sed -i.bak -r 's;#?https?://.*/debian-security/?[[:space:]];http://mirrors.tencent.com/debian-security/ ;g' /etc/apt/sources.list ; \
    sed -i -r 's;#?https?://.*/debian/?[[:space:]];http://mirrors.tencent.com/debian/ ;g' /etc/apt/sources.list ; \
    apt-get update;                                         \
    apt-get install curl -y;                                \
    curl -L -o /tmp/go.sh https://install.direct/go.sh;     \
    chmod +x /tmp/go.sh;                                    \
    /tmp/go.sh;                                             \
    curl -k -qsL "https://github.com/owent/update-geoip-geosite/releases/download/latest/geoip.dat" -o /usr/bin/v2ray/geoip.dat ;      \
    curl -k -qsL "https://github.com/owent/update-geoip-geosite/releases/download/latest/geosite.dat" -o /usr/bin/v2ray/geosite.dat ;  \
    if [ -e "/var/lib/apt/lists" ]; then for APT_CACHE in /var/lib/apt/lists/* ; do rm -rf "$APT_CACHE"; done fi

FROM alpine:latest

LABEL maintainer "OWenT <admin@owent.net>"

COPY --from=builder /usr/bin/v2ray/v2ray /usr/bin/v2ray/
COPY --from=builder /usr/bin/v2ray/v2ctl /usr/bin/v2ray/
COPY --from=builder /usr/bin/v2ray/geoip.dat /usr/bin/v2ray/
COPY --from=builder /usr/bin/v2ray/geosite.dat /usr/bin/v2ray/
COPY --from=builder /etc/v2ray/config.json /etc/v2ray/config.json

RUN set -ex && \
    apk --no-cache add ca-certificates && \
    mkdir /var/log/v2ray/ &&\
    chmod +x /usr/bin/v2ray/v2ctl && \
    chmod +x /usr/bin/v2ray/v2ray

ENV PATH /usr/bin/v2ray:$PATH

VOLUME /data/logs/v2ray

CMD ["v2ray", "-config=/etc/v2ray/config.json"]

# podman run -d --name v2ray -v /etc/v2ray:/etc/v2ray -v /data/logs/v2ray:/data/logs/v2ray --cap-add=NET_ADMIN --network=host localhost/local-v2ray v2ray -config=/etc/v2ray/config.json
# podman generate systemd v2ray | sudo tee /lib/systemd/system/v2ray.service
# sudo systemctl daemon-reload