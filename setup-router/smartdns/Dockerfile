# podman build --build-arg=GITHUB_TOKEN=$GITHUB_TOKEN --layers --force-rm --tag smartdns -f Dockerfile .
# docker build --build-arg=GITHUB_TOKEN=$GITHUB_TOKEN --force-rm --tag smartdns -f Dockerfile .
FROM debian:latest as builder

RUN set -x;                                  \
    if [[ "x$GITHUB_TOKEN" == "x" ]]; then   \
    sed -i.bak -r 's;#?https?://.*/debian-security/?[[:space:]];http://mirrors.aliyun.com/debian-security/ ;g' /etc/apt/sources.list ;  \
    sed -i -r 's;#?https?://.*/debian/?[[:space:]];http://mirrors.aliyun.com/debian/ ;g' /etc/apt/sources.list ;                        \
    fi;                                                                         \
    apt update -y;                                                              \
    apt install curl unzip -y;                                                  \
    if [[ "x$GITHUB_TOKEN" != "x" ]]; then GITHUB_TOKEN_ARGS="-H Authorization: token $GITHUB_TOKEN"; fi;                                            \
    SMARTDNS_LATEST_VERSION=$(curl -L https://api.github.com/repos/pymumu/smartdns/releases/latest | grep -i -o -E 'https://[^"]+\.x86_64-linux-all\.tar.gz' | head -n 1); \
    curl -k -qL "$SMARTDNS_LATEST_VERSION" -o /tmp/smartdns.x86_64-linux-all.tar.gz;        \
    cd /usr/local/ ; tar -axvf /tmp/smartdns.x86_64-linux-all.tar.gz ;                      \
    find /usr/local/smartdns -type f ;                                                                                                             \
    if [[ -e "/var/lib/apt/lists" ]]; then for APT_CACHE in /var/lib/apt/lists/* ; do rm -rf "$APT_CACHE"; done; fi

FROM docker.io/alpine:latest

LABEL maintainer "OWenT <admin@owent.net>"

COPY --from=builder /usr/local/smartdns/usr/sbin/smartdns        /usr/local/smartdns/bin/
COPY --from=builder /usr/local/smartdns/systemd/smartdns.service /usr/local/smartdns/share/systemd/
COPY --from=builder /usr/local/smartdns/LICENSE                  /usr/local/smartdns/share/
COPY --from=builder /usr/local/smartdns/ReadMe.md                /usr/local/smartdns/share/
COPY --from=builder /usr/local/smartdns/ReadMe_en.md             /usr/local/smartdns/share/
COPY ./smartdns.conf                                             /usr/local/smartdns/etc/

# sed -i -r 's#dl-cdn.alpinelinux.org#mirrors.tencent.com#g' /etc/apk/repositories ;    \
RUN set -ex ;                                                                           \
    sed -i -r 's#dl-cdn.alpinelinux.org#mirrors.aliyun.com#g' /etc/apk/repositories ;   \
    apk --no-cache add ca-certificates tzdata ;                                         \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime ;                           \
    mkdir -p /var/log/smartdns/ ;                                                       \
    chmod +x /usr/local/smartdns/bin/smartdns ;

ENV PATH /usr/local/smartdns/bin/:$PATH

VOLUME /var/log/smartdns

CMD ["smartdns", "-p", "/var/run/smartdns.pid", "-c", "/usr/local/smartdns/etc/smartdns.conf", "-f"]

# podman run -d --name smartdns -v /etc/smartdns:/usr/local/smartdns/etc -v /data/logs/smartdns:/var/log/smartdns --network=host docker.io/owt5008137/smartdns:latest
# podman generate systemd smartdns | sudo tee /lib/systemd/system/smartdns.service
# sudo systemctl daemon-reload
