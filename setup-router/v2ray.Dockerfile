# podman build --build-arg=GITHUB_TOKEN=$GITHUB_TOKEN --layers --force-rm --tag proxy-with-geo -f v2ray.Dockerfile .
# docker build --build-arg=GITHUB_TOKEN=$GITHUB_TOKEN --force-rm --tag proxy-with-geo -f v2ray.Dockerfile .
FROM debian:latest as builder

RUN set -x;                                  \
    [ "x$GITHUB_TOKEN" = "x" ] || (          \
    sed -i.bak -r 's;#?https?://.*/debian-security/?[[:space:]];http://mirrors.aliyun.com/debian-security/ ;g' /etc/apt/sources.list ;  \
    sed -i -r 's;#?https?://.*/debian/?[[:space:]];http://mirrors.aliyun.com/debian/ ;g' /etc/apt/sources.list ;                        \
    );                                                                          \
    apt update -y;                                                              \
    apt install curl unzip -y;                                                  \
    [ "x$GITHUB_TOKEN" = "x" ] || GITHUB_TOKEN_ARGS="-H Authorization: token $GITHUB_TOKEN";                                                    \
    V2RAY_LATEST_VERSION=$(curl -L $GITHUB_TOKEN_ARGS 'https://api.github.com/repos/v2fly/v2ray-core/releases/latest' | grep tag_name | grep -E -o 'v[0-9]+[0-9\.]+' | head -n 1); \
    curl -k -qL https://github.com/v2fly/v2ray-core/releases/download/$V2RAY_LATEST_VERSION/v2ray-linux-64.zip -o /tmp/v2ray-linux-64.zip;      \
    mkdir -p /usr/local/v2ray/etc ; mkdir -p /usr/local/v2ray/bin ; mkdir -p /usr/local/v2ray/share ;                                           \
    cd /usr/local/v2ray/bin ; unzip /tmp/v2ray-linux-64.zip; rm -f /tmp/v2ray-linux-64.zip;                                                     \
    cp -f config.json /usr/local/v2ray/etc;                                                                                                     \
    curl -k -qL "https://github.com/owent/update-geoip-geosite/releases/download/latest/geoip.dat" -o /usr/local/v2ray/bin/geoip.dat ;          \
    curl -k -qL "https://github.com/owent/update-geoip-geosite/releases/download/latest/geosite.dat" -o /usr/local/v2ray/bin/geosite.dat ;      \
    curl -k -qL "https://github.com/owent/update-geoip-geosite/releases/download/latest/all.tar.gz" -o /usr/local/v2ray/share/geo-all.tar.gz ;  \
    find /usr/local/v2ray -type f ;                                                                                                             \
    [ -e "/var/lib/apt/lists" ] || for APT_CACHE in /var/lib/apt/lists/* ; do rm -rf "$APT_CACHE"; done;

FROM docker.io/alpine:latest

LABEL maintainer "OWenT <admin@owent.net>"

COPY --from=builder /usr/local/v2ray/bin/v2ray            /usr/local/v2ray/bin/
COPY --from=builder /usr/local/v2ray/etc/config.json      /usr/local/v2ray/etc/
COPY --from=builder /usr/local/v2ray/share/geo-all.tar.gz /usr/local/v2ray/share/
COPY --from=builder /usr/local/v2ray/bin/geoip.dat        /usr/local/v2ray/bin/
COPY --from=builder /usr/local/v2ray/bin/geosite.dat      /usr/local/v2ray/bin/
COPY --from=builder /usr/local/v2ray/bin/geoip-only-cn-private.dat /usr/local/v2ray/bin/

# sed -i -r 's#dl-cdn.alpinelinux.org#mirrors.aliyun.com#g' /etc/apk/repositories ;        \
RUN set -ex ;                                                                               \
    sed -i -r 's#dl-cdn.alpinelinux.org#mirrors.cloud.tencent.com#g' /etc/apk/repositories ;       \
    apk --no-cache add ca-certificates tzdata ;                                             \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime ;                               \
    mkdir -p /var/log/v2ray/ ;                                                              \
    mkdir -p /usr/local/vproxy/bin ; mkdir -p /usr/local/vproxy/etc ; /var/log/vproxy/ ;    \
    ln $(find /usr/local/v2ray/bin -type f) /usr/local/vproxy/bin;                          \
    ln $(find /usr/local/v2ray/etc -type f) /usr/local/vproxy/etc;                          \
    ln /usr/local/vproxy/bin/v2ray /usr/local/vproxy/bin/vproxyd;                           \
    chmod +x /usr/local/v2ray/bin/v2ray /usr/local/vproxy/bin/vproxyd;

ENV PATH /usr/local/vproxy/bin/:$PATH

VOLUME /var/log/vproxy

CMD ["vproxyd", "run" "-c", "/usr/local/vproxy/etc/config.json"]

# podman run -d --name vproxy -v /etc/vproxy:/usr/local/vproxy/etc -v /data/logs/vproxy:/var/log/vproxy --cap-add=NET_ADMIN --network=host docker.io/owt5008137/proxy-with-geo vproxy -config=/usr/local/vproxy/etc/config.json
# podman generate systemd vproxy | sudo tee /lib/systemd/system/v2ray.service
# sudo systemctl daemon-reload
