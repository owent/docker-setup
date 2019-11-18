# docker setup script

ENV:

+ SETUP_INSTALL_PROXY="http proxy"
+ SETUP_INSTALL_PREFIX
+ SETUP_WORK_DIR


## 启动命令备注

```bash
# 带systemd
podman/docker run docker run -d --cap-add=SYS_ADMIN -v /sys/fs/cgroup:/sys/fs/cgroup IMAGE /sbin/init

# 路由
podman/docker run docker run -d --cap-add=SYS_ADMIN --cap-add=NET_ADMIN -v /sys/fs/cgroup:/sys/fs/cgroup IMAGE /sbin/init

# @see https://docs.docker.com/engine/reference/builder/#entrypoint for detail about CMD and ENTRYPOINT
```
