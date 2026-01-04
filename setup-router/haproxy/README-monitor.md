# HAProxy 后端状态监控

## 功能说明

HAProxy 后端状态监控脚本可以实时检测 HAProxy 后端服务器的状态变更，并通过飞书机器人发送通知。

### 监控的状态变更包括：

- 后端服务器状态变更（UP → DOWN，DOWN → UP 等）
- 新增后端服务器
- 健康检查状态变更

## 安装部署

### 1. 自动部署（推荐）

运行启动脚本会自动部署监控服务：

```bash
./start-haproxy-pods.sh
```

脚本会自动：
- 复制监控脚本到 `~/.config/haproxy/`
- 创建示例配置文件 `~/.config/haproxy-monitor.env`
- 安装 systemd 服务和定时器
- 启动监控定时器

### 2. 手动部署

```bash
# 创建配置目录
mkdir -p ~/.config/haproxy

# 复制监控脚本
cp monitor-haproxy.sh ~/.config/haproxy/
chmod +x ~/.config/haproxy/monitor-haproxy.sh

# 创建环境配置文件
cp haproxy-monitor.env.sample ~/.config/haproxy-monitor.env

# 编辑配置文件，设置飞书 Webhook URL
nano ~/.config/haproxy-monitor.env

# 安装 systemd 服务
mkdir -p ~/.config/systemd/user
cp haproxy-monitor.service ~/.config/systemd/user/
cp haproxy-monitor.timer ~/.config/systemd/user/

# 重载并启动服务
systemctl --user daemon-reload
systemctl --user enable haproxy-monitor.timer
systemctl --user start haproxy-monitor.timer
```

## 配置说明

### 飞书 Webhook 配置

1. 在飞书中创建自定义机器人：
   - 进入飞书群聊
   - 点击群设置 → 群机器人 → 添加机器人
   - 选择"自定义机器人"
   - 复制生成的 Webhook URL

2. 编辑配置文件：

```bash
nano ~/.config/haproxy-monitor.env
```

3. 设置 Webhook URL：

```bash
FEISHU_WEBHOOK_URL=https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_WEBHOOK_TOKEN
```

### 环境变量说明

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| `FEISHU_WEBHOOK_URL` | 飞书机器人 Webhook URL（必需） | 无 |
| `STATE_FILE` | 状态文件存储路径 | `/tmp/haproxy-monitor-state.json` |
| `HAPROXY_SOCKET` | HAProxy Unix Socket 路径 | `/var/run/haproxy.sock` |
| `HAPROXY_STATS_URL` | HAProxy HTTP Stats URL | `http://127.0.0.1:8404/stats` |

## HAProxy 配置

### 启用 Unix Socket（推荐）

在 HAProxy 配置文件中添加：

```haproxy
global
    stats socket /var/run/haproxy.sock mode 660 level admin
    stats timeout 30s
```

### 或启用 HTTP Stats

```haproxy
frontend stats
    mode http
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 10s
    stats admin if LOCALHOST
```

### Docker Compose 配置

确保容器可以访问 socket：

```yaml
services:
  haproxy:
    volumes:
      - ./etc:/etc/haproxy
      - haproxy-socket:/var/run
    # ...

volumes:
  haproxy-socket:
```

## 使用管理

### 查看监控服务状态

```bash
systemctl --user status haproxy-monitor.timer
systemctl --user status haproxy-monitor.service
```

### 查看监控日志

```bash
journalctl --user -u haproxy-monitor.service -f
```

### 手动触发监控检查

```bash
systemctl --user start haproxy-monitor.service
```

### 停止监控

```bash
systemctl --user stop haproxy-monitor.timer
systemctl --user disable haproxy-monitor.timer
```

### 修改检查频率

编辑 `~/.config/systemd/user/haproxy-monitor.timer`：

```ini
[Timer]
# 修改为每 5 分钟检查一次
OnBootSec=5min
OnUnitActiveSec=5min
```

然后重载配置：

```bash
systemctl --user daemon-reload
systemctl --user restart haproxy-monitor.timer
```

## 通知格式

当检测到后端状态变更时，会发送包含以下信息的飞书通知：

- **后端名称**：HAProxy backend 名称
- **服务器名称**：具体的服务器标识
- **状态变更**：旧状态 → 新状态（带图标）
- **健康检查结果**：健康检查的详细状态
- **时间戳**：变更发生的时间

### 状态图标说明

- ✅ 绿色：服务器 UP（正常）
- ❌ 红色：服务器 DOWN（故障）
- ⚠️ 橙色：NOLB（无负载均衡）
- 🔧 黄色：MAINT（维护模式）
- 🆕 蓝色：新增后端

## 依赖要求

监控脚本需要以下工具：

- `bash`
- `jq`：JSON 处理工具
- `curl`：发送 HTTP 请求
- `socat`：Unix Socket 通信（如果使用 socket 方式）
- `podman` 或 `docker`：容器管理（用于从容器获取状态）

安装依赖（CentOS/RHEL）：

```bash
sudo dnf install -y jq curl socat
```

安装依赖（Debian/Ubuntu）：

```bash
sudo apt-get install -y jq curl socat
```

## 故障排查

### 无法获取 HAProxy 状态

1. 检查容器是否运行：
   ```bash
   podman ps | grep haproxy
   ```

2. 检查是否可以连接 socket：
   ```bash
   podman exec haproxy sh -c "echo 'show stat' | socat stdio /var/run/haproxy.sock"
   ```

### 飞书通知发送失败

1. 检查 Webhook URL 是否正确
2. 检查网络连接
3. 查看日志获取详细错误信息：
   ```bash
   journalctl --user -u haproxy-monitor.service -n 50
   ```

### 状态文件权限问题

如果遇到权限问题，可以修改状态文件路径：

```bash
echo "STATE_FILE=$HOME/.cache/haproxy-monitor-state.json" >> ~/.config/haproxy-monitor.env
```

## 高级配置

### 自定义通知模板

编辑监控脚本 `~/.config/haproxy/monitor-haproxy.sh` 中的 `send_feishu_notification` 函数。

### 添加邮件通知

可以在脚本中添加邮件发送功能，与飞书通知并行使用。

### 集成 Prometheus

考虑使用 HAProxy Exporter 配合 Prometheus 和 Alertmanager 实现更完善的监控告警。

## 许可证

遵循项目根目录的 LICENSE 文件。
