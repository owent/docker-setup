# podman build --build-arg=GITHUB_TOKEN=$GITHUB_TOKEN --layers --force-rm --tag proxy-with-geo -f v2ray.Dockerfile .
# docker build --build-arg=GITHUB_TOKEN=$GITHUB_TOKEN --force-rm --tag proxy-with-geo -f v2ray.Dockerfile .
FROM debian:latest as builder

RUN sed -i.bak -r 's;#?https?://.*/debian-security/?[[:space:]];http://mirrors.aliyun.com/debian-security/ ;g' /etc/apt/sources.list ; \
    sed -i -r 's;#?https?://.*/debian/?[[:space:]];http://mirrors.aliyun.com/debian/ ;g' /etc/apt/sources.list ; \
    apt update -y;                                                              \
    apt install curl unzip -y;                                                  \
    if [ ! -z "$GITHUB_TOKEN" ]; then GITHUB_TOKEN_ARGS="-H Authorization: token $GITHUB_TOKEN"; fi;                                            \
    V2RAY_LATEST_VERSION=$(curl -L $GITHUB_TOKEN_ARGS 'https://api.github.com/repos/v2fly/v2ray-core/releases/latest' | grep 'tag_name' | awk -F '"' '{print $4}');    \
    curl -k -qL https://github.com/v2fly/v2ray-core/releases/download/$V2RAY_LATEST_VERSION/v2ray-linux-64.zip -o /opt/v2ray-linux-64.zip;      \
    mkdir /opt/v2ray/ ; cd /opt/v2ray/ ; unzip ../v2ray-linux-64.zip; rm -f ../v2ray-linux-64.zip; mkdir -p /usr/local/v2ray/etc;               \
    mkdir -p /usr/local/v2ray/share; mkdir -p /usr/local/v2ray/bin; cp -f config.json /usr/local/v2ray/etc;                                     \
    curl -k -qL "https://github.com/owent/update-geoip-geosite/releases/download/latest/geoip.dat" -o /usr/local/v2ray/bin/geoip.dat ;          \
    curl -k -qL "https://github.com/owent/update-geoip-geosite/releases/download/latest/geosite.dat" -o /usr/local/v2ray/bin/geosite.dat ;      \
    curl -k -qL "https://github.com/owent/update-geoip-geosite/releases/download/latest/all.tar.gz" -o /usr/local/v2ray/share/geo-all.tar.gz ;  \
    if [ -e "/var/lib/apt/lists" ]; then for APT_CACHE in /var/lib/apt/lists/* ; do rm -rf "$APT_CACHE"; done; fi

FROM docker.io/alpine:latest

LABEL maintainer "OWenT <admin@owent.net>"

COPY --from=builder /opt/v2ray/v2ray                      /usr/local/v2ray/bin/
COPY --from=builder /opt/v2ray/v2ctl                      /usr/local/v2ray/bin/
COPY --from=builder /opt/v2ray/config.json                /usr/local/v2ray/etc/
COPY --from=builder /usr/local/v2ray/share/geo-all.tar.gz /usr/local/v2ray/share/
COPY --from=builder /usr/local/v2ray/bin/geoip.dat        /usr/local/v2ray/bin/
COPY --from=builder /usr/local/v2ray/bin/geosite.dat      /usr/local/v2ray/bin/

# sed -i -r 's#dl-cdn.alpinelinux.org#mirrors.tencent.com#g' /etc/apk/repositories ;    \
RUN set -ex ;                                                                           \
    sed -i -r 's#dl-cdn.alpinelinux.org#mirrors.aliyun.com#g' /etc/apk/repositories ;   \
    apk --no-cache add ca-certificates tzdata ;                                         \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime ;                           \
    mkdir -p /var/log/v2ray/ ;                                                          \
    chmod +x /usr/local/v2ray/bin/v2ctl ;                                               \
    chmod +x /usr/local/v2ray/bin/v2ray ;

ENV PATH /usr/local/v2ray/bin/:$PATH

VOLUME /var/log/v2ray

CMD ["v2ray", "-config=/usr/local/v2ray/etc/config.json"]

# podman run -d --name v2ray -v /etc/v2ray:/usr/local/v2ray/etc -v /data/logs/v2ray:/var/log/v2ray --cap-add=NET_ADMIN --network=host docker.io/owt5008137/proxy-with-geo v2ray -config=/usr/local/v2ray/etc/config.json
# podman generate systemd v2ray | sudo tee /lib/systemd/system/v2ray.service
# sudo systemctl daemon-reload
