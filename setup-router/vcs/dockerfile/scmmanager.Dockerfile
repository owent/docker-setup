FROM scmmanager/scm-manager:latest

LABEL maintainer "OWenT <admin@owent.net>"

USER root:root

RUN sed -i.bak -r 's#dl-cdn.alpinelinux.org#mirrors.ustc.edu.cn#g' /etc/apk/repositories ; \
    apk update ; apk upgrade ;                                                             \
    apk add --no-cache --no-check-certificate procps tzdata less iproute2 gawk lsof bash ; \
    apk add --no-cache --no-check-certificate vim wget curl ca-certificates inetutils-telnet yq jq gpg logrotate supervisor; \
    apk cache clean -f ; \
    echo "export LANG=en_US.UTF-8" | tee -a /etc/profile;                                                      \
    echo "export LC_ALL=en_US.UTF-8" | tee -a /etc/profile;                                                    \
    ln -f /usr/share/zoneinfo/Asia/Shanghai /etc/timezone;                                                     \
    mkdir -p /etc/supervisor/conf.d

COPY ./ca-certificates/* /usr/local/share/ca-certificates/
RUN update-ca-certificates

# COPY ./supervisord.conf /etc/supervisor/
# CMD ["/bin/bash", "/opt/bootstrap.sh", "supervisord", "--nodaemon", "-c", "/etc/supervisor/supervisord.conf"]


