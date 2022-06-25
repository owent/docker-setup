FROM docker.io/alpine:latest

# podman build --layers --force-rm --tag local-aria2 -f aria2.Dockerfile .
# docker build --force-rm --tag local-aria2 -f aria2.Dockerfile .

LABEL maintainer "OWenT <admin@owent.net>"

# echo '#!/bin/bash' >> aria2c_with_session.sh
# echo 'if [ -e "/data/aria2/session/aria2.session" ]; then aria2 --input-file=/data/aria2/session/aria2.session "$@"; else aria2 "$@"; fi' > aria2c_with_session.sh
COPY aria2c_with_session.sh /usr/bin/aria2c_with_session.sh

# sed -i -r 's#dl-cdn.alpinelinux.org#mirrors.tencent.com#g' /etc/apk/repositories ;  \
RUN set -ex ;                                                                         \
    sed -i -r 's#dl-cdn.alpinelinux.org#mirrors.aliyun.com#g' /etc/apk/repositories ; \
    apk --no-cache add ca-certificates tzdata aria2 bash;                             \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime ;                         \
    chmod +x /usr/bin/aria2c_with_session.sh ;                                        \
    chmod +x /usr/bin/aria2c ;

# EXPOSE 6800
# EXPOSE 6881
# EXPOSE 6882
# EXPOSE 6883

# VOLUME /var/log/aria2
# VOLUME /data/aria2

# CMD ["aria2c", "--log=/var/log/aria2/aria2.log", "--dir=/data/aria2/download", "--save-session=/data/aria2/session/aria2.session", "--rpc-listen-port=6880", "--listen-port=6881,6882,6883", "--dht-listen-port=6881,6882,6883"]
CMD ["aria2c"]

# podman run -d --name aria2                                                            \
#     --mount type=bind,source=/home/tools/aria2/etc,target=/etc/aria2                  \
#     --mount type=bind,source=/home/tools/aria2/log,target=/var/log/aria2              \
#     --mount type=bind,source=/data/aria2,target=/data/aria2                           \
#     -p 6800:6800/tcp -p 6881-6999:6881-6883/tcp -p 6881-6999:6881-6883/udp            \
#     local-aria2 /usr/bin/aria2c_with_session.sh --conf-path=/etc/aria2/aria2.conf
# mkdir -p ~/.config/systemd/user/ ;
# podman generate systemd aria2 | tee ~/.config/systemd/user/aria2.service
# systemctl --user daemon-reload
# systemctl --user enable aria2.service
# systemctl --user start aria2.service


# Maybe need run from host: loginctl enable-linger tools