# emby 硬件加速

PVE 9+ 配置:

文件 `/etc/pve/lxc/<CTID>.conf`:

```text
# AMD核显
# dev0: /dev/dri/renderD128,gid=<容器内这个文件的GID>,mode=0666
# dev1: /dev/dri/card0,gid=<容器内这个文件的GID>,mode=0666
features: nesting=1,keyctl=1

# cgroup2 设备白名单（PVE 9 统一语法）
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir 0 0

# 挂载 tun 设备到 CT
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file,optional 0 0
```

文件 `/etc/udev/rules.d/99-dri-permissions.rules`

```text
SUBSYSTEM=="drm", KERNEL=="renderD*", MODE="0666", GROUP="render"
SUBSYSTEM=="drm", KERNEL=="card*", MODE="0666", GROUP="video"
KERNEL=="kfd", SUBSYSTEM=="kfd", MODE="0666", GROUP="video"
```
