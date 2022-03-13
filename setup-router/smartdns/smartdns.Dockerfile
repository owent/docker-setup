# podman build --build-arg=GITHUB_TOKEN=$GITHUB_TOKEN --layers --force-rm --tag smartdns -f smartdns.Dockerfile .
# docker build --build-arg=GITHUB_TOKEN=$GITHUB_TOKEN --force-rm --tag smartdns -f smartdns.Dockerfile .
FROM debian:latest as builder

# We should build from git source because some release do not support separeted ipset rules

RUN set -x;                                  \
    if [ "x$GITHUB_TOKEN" == "x" ]; then   \
    sed -i.bak -r 's;#?https?://.*/debian-security/?[[:space:]];http://mirrors.aliyun.com/debian-security/ ;g' /etc/apt/sources.list ;  \
    sed -i -r 's;#?https?://.*/debian/?[[:space:]];http://mirrors.aliyun.com/debian/ ;g' /etc/apt/sources.list ;                        \
    fi;                                                                         \
    apt update -y ;                                                             \
    apt install -y curl unzip bash git git-lfs build-essential g++ libssl-dev ; \
    git clone --depth 1 https://github.com/pymumu/smartdns.git ~/smartdns ;     \
    cd ~/smartdns/package ;                                                     \
    bash ./build-pkg.sh bash ./build-pkg.sh --platform linux --arch x86-64 ;    \
    mv -f smartdns.*.tar.gz /tmp/smartdns.x86_64-linux-all.tar.gz;              \
    cd /usr/local/ ; tar -axvf /tmp/smartdns.x86_64-linux-all.tar.gz ;          \
    find /usr/local/smartdns -type f ;                                                                                                             \
    for APT_CACHE in /var/lib/apt/lists/* ; do rm -rf "$APT_CACHE"; done;

FROM debian:latest

LABEL maintainer "OWenT <admin@owent.net>"

COPY --from=builder /usr/local/smartdns/usr/sbin/smartdns        /usr/local/smartdns/bin/
COPY --from=builder /usr/local/smartdns/systemd/smartdns.service /usr/local/smartdns/share/systemd/
COPY --from=builder /usr/local/smartdns/LICENSE                  /usr/local/smartdns/share/
COPY --from=builder /usr/local/smartdns/ReadMe.md                /usr/local/smartdns/share/
COPY --from=builder /usr/local/smartdns/ReadMe_en.md             /usr/local/smartdns/share/
COPY ./smartdns.origin.conf                                      /usr/local/smartdns/etc/smartdns.conf

# sed -i -r 's#dl-cdn.alpinelinux.org#mirrors.tencent.com#g' /etc/apk/repositories ;    \
RUN set -ex ;                                                                           \
    if [ "x$GITHUB_TOKEN" == "x" ]; then   \
    sed -i.bak -r 's;#?https?://.*/debian-security/?[[:space:]];http://mirrors.aliyun.com/debian-security/ ;g' /etc/apt/sources.list ;  \
    sed -i -r 's;#?https?://.*/debian/?[[:space:]];http://mirrors.aliyun.com/debian/ ;g' /etc/apt/sources.list ;                        \
    fi; \
    apt update -y ;                                                             \
    apt install -y ca-certificates tzdata bash iproute2 knot-dnsutils dnsutils procps ipset nftables; \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime ;                           \
    mkdir -p /var/log/smartdns/ ;                                                       \
    chmod +x /usr/local/smartdns/bin/smartdns ;                                         \
    for APT_CACHE in /var/lib/apt/lists/* ; do rm -rf "$APT_CACHE"; done;

ENV PATH /usr/local/smartdns/bin/:$PATH

VOLUME /var/log/smartdns

CMD ["smartdns", "-p", "/var/run/smartdns.pid", "-c", "/usr/local/smartdns/etc/smartdns.conf", "-f"]

# podman run -d --name smartdns -v $SMARTDNS_ETC_DIR:/usr/local/smartdns/etc -v /data/logs/smartdns:/var/log/smartdns -p 53:53/tcp -p 53:53/udp docker.io/owt5008137/smartdns:latest
# podman run -d --name smartdns -v $SMARTDNS_ETC_DIR:/usr/local/smartdns/etc -v /data/logs/smartdns:/var/log/smartdns --cap-add=NET_ADMIN --network=host docker.io/owt5008137/smartdns:latest
# podman generate systemd --name smartdns | tee $SMARTDNS_ETC_DIR/smartdns.service
# systemctl --user enable $SMARTDNS_ETC_DIR/smartdns.service
# systemctl --user  daemon-reload
# systemctl --user restart smartdns
