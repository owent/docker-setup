FROM docker.io/library/ubuntu:noble

LABEL maintainer "OWenT <admin@owent.net>"

RUN export DEBIAN_FRONTEND=noninteractive; \
    sed -i -r 's;security.ubuntu.com/ubuntu;mirrors.tencent.com/ubuntu;g' /etc/apt/sources.list.d/* ; \
    sed -i -r 's;archive.ubuntu.com/ubuntu;mirrors.tencent.com/ubuntu;g' /etc/apt/sources.list.d/* ; \
    cat /etc/apt/sources.list ;                                                                                 \
    apt update -y; apt upgrade -y;                                                                              \
    apt install -y procps locales tzdata less iproute2 gawk lsof bash systemd ;                                 \
    apt install -y vim wget curl ca-certificates telnet yq jq gpg;                                              \
    echo "LANG=en_US.UTF-8" >  /etc/default/locale;                                                             \
    echo "LANGUAGE=en_US.UTF-8" >> /etc/default/locale;                                                         \
    ln -f /usr/share/zoneinfo/Asia/Shanghai /etc/timezone;


RUN wget -qO - https://package.perforce.com/perforce.pubkey | gpg --dearmor > /usr/share/keyrings/perforce.gpg; \
    echo 'deb [signed-by=/usr/share/keyrings/perforce.gpg] https://package.perforce.com/apt/ubuntu noble release' > /etc/apt/sources.list.d/perforce.list; \
    apt update -y && apt install -y helix-p4d

COPY ./bootstrap.sh /opt/

CMD ["/bin/bash", "/opt/bootstrap.sh", "p4d"]
