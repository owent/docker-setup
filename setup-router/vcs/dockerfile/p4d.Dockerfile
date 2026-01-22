FROM docker.io/library/ubuntu:noble

LABEL maintainer "OWenT <admin@owent.net>"

RUN export DEBIAN_FRONTEND=noninteractive; \
    echo 'Acquire::https::mirrors.tencent.com::Verify-Peer "false";' > /etc/apt/apt.conf.d/99ignore-ssl-mirrors-tencent ; \
    echo 'Acquire::https::mirrors.tencent.com::Verify-Host "false";' >> /etc/apt/apt.conf.d/99ignore-ssl-mirrors-tencent ; \
    sed -i -r 's;security.ubuntu.com/ubuntu;mirrors.ustc.edu.cn/ubuntu;g' /etc/apt/sources.list.d/* ; \
    sed -i -r 's;archive.ubuntu.com/ubuntu;mirrors.ustc.edu.cn/ubuntu;g' /etc/apt/sources.list.d/* ; \
    apt update -y; apt upgrade -y;                                                                              \
    apt install -y procps locales tzdata less iproute2 gawk lsof bash systemd ;                                 \
    apt install -y vim wget curl ca-certificates telnet yq jq gpg logrotate supervisor;                         \
    echo "LANG=en_US.UTF-8" >  /etc/default/locale;                                                             \
    echo "LANGUAGE=en_US.UTF-8" >> /etc/default/locale;                                                         \
    ln -f /usr/share/zoneinfo/Asia/Shanghai /etc/timezone;                                                      \
    mkdir -p /etc/supervisor/conf.d


RUN wget -qO - https://package.perforce.com/perforce.pubkey | gpg --dearmor > /usr/share/keyrings/perforce.gpg; \
    echo 'deb [signed-by=/usr/share/keyrings/perforce.gpg] https://package.perforce.com/apt/ubuntu noble release' > /etc/apt/sources.list.d/perforce.list; \
    apt update -y && apt install -y helix-p4d

COPY ./ca-certificates/* /usr/local/share/ca-certificates/
RUN update-ca-certificates

COPY ./bootstrap-p4d.sh /opt/bootstrap.sh
COPY ./supervisord.conf /etc/supervisor/
COPY ./supervisor-p4d.conf ./supervisor-cron.conf /etc/supervisor/conf.d/

CMD ["/bin/bash", "/opt/bootstrap.sh", "supervisord", "--nodaemon", "-c", "/etc/supervisor/supervisord.conf"]
