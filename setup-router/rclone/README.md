# rclone configure

## GUI - systemd

### `rclone-gui.service`

```systemd
[Unit]
Description=rclone gui service
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/rclone rcd --log-systemd --rc-web-gui --rc-web-gui-no-open-browser --rc-user guest --rc-pass owent --rc-serve --rc-addr :5572
```

## mount - systemd

```systemd
[Unit]
Description=rclone gui service
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/rclone mount remote:path /path/to/mountpoint --log-systemd --buffer-size 256M --allow-other --attr-timeout 1h --max-read-ahead 8M --vfs-cache-mode full --vfs-cache-max-age 2160h --vfs-cache-max-size 16G 
```

### VFS Options

```bash
--buffer-size 256M        \
--allow-other             \
--allow-non-empty         \
--attr-timeout 1h         \
--max-read-ahead 8M       \
--vfs-cache-mode full     \
--vfs-cache-max-age 2160h \
--vfs-cache-max-size 16G  \
--vfs-cache-max-size 2G   \
```

```bash
--buffer-size 256M            \
--allow-other                 \
--allow-non-empty             \
--attr-timeout 86400          \
--max-read-ahead 8388608      \
--vfs-cache-mode full         \
--vfs-cache-max-age 7776000   \
--vfs-cache-max-size 2147483648
```
