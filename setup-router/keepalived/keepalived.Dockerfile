FROM alpine:latest

# podman build --layers --force-rm --tag local-keepalived -f keepalived.Dockerfile .
# docker build --force-rm --tag local-keepalived -f keepalived.Dockerfile .

LABEL maintainer "OWenT <admin@owent.net>"

RUN set -ex ; \
    sed -i.bak -r 's#dl-cdn.alpinelinux.org#mirrors.tencent.com#g' /etc/apk/repositories; \
    apk add --no-cache bash vim keepalived iputils iproute2; \
    adduser -s /bin/bash -S keepalived_password keepalived_script

CMD ["keepalived", "--dont-fork", "--log-console", "-f", "/etc/keepalived/keepalived.conf"]