# Coredns

Wrap `/etc/ppp/ip-up.d/00-dns.sh` with:

```bash
  /use/bin/grep 'generated.*docker-setup.*coredns'/etc/resolv.conf > /dev/null 2>&1
  if [ $? -ne 0 ]; then
  fi
```
