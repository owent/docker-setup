# rclone configure

## GUI - systemd

### `rclone-gui.service`

```systemd
[Unit]
Description=rclone gui service
Wants=network.target
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/rclone rcd --log-systemd --rc-web-gui --rc-web-gui-no-open-browser --rc-user guest --rc-pass owent --rc-serve --rc-addr :5572
```

## mount - systemd

```systemd
[Unit]
Description=rclone gui service
Wants=network.target
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/rclone mount remote:path /path/to/mountpoint --log-systemd --allow-other --allow-root --attr-timeout 1h --max-read-ahead 8M --vfs-cache-mode full --vfs-cache-max-age 24h --vfs-cache-max-size 16G 
```

### VFS Options

```bash
--allow-other             \
--allow-root              \
--attr-timeout 1h         \
--max-read-ahead 8M       \
--vfs-cache-mode full     \
--vfs-cache-max-age 24h   \
--vfs-cache-max-size 16G  \
```
