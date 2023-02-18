# Redis

注意： 可以通过容器网络隔离来实现redis隔离.

```bash
REDIS_PRIVATE_GATEWAY_IP=$(echo $REDIS_PRIVATE_NETWORK_IP | sed -E 's;[0-9]+$;1;')
podman network create --driver bridge --ipam-driver host-local \
  --disable-dns --dns $ROUTER_INTERNAL_IPV4 --subnet 10.85.0.0/16            \
  $REDIS_PRIVATE_NETWORK_NAME
```
