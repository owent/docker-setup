FROM docker.io/library/alpine:latest

LABEL maintainer "owent <admin@owent.net>"

EXPOSE 139/TCP
EXPOSE 445/TCP
EXPOSE 137/UDP
EXPOSE 138/UDP

COPY smb.conf /etc/samba/smb.conf
COPY setup.sh /opt/setup.sh

RUN sed -i.bak -r 's#dl-cdn.alpinelinux.org#mirrors.tencent.com#g' /etc/apk/repositories ; \
  apk add --no-cache bash ; \
  /opt/setup.sh && rm -f /opt/setup.sh

# CMD ["/usr/sbin/smbd", "-F", "--no-process-group", "-s", "/etc/samba/smb.conf"]
# CMD ["/lib/systemd/systemd"]
CMD ["/bin/bash", "/usr/sbin/start-smbd.sh"]
