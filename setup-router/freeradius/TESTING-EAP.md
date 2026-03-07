# FreeRADIUS EAP 认证测试指南

本文档详细介绍如何测试 FreeRADIUS 的 EAP 认证功能。

## 目录

1. [环境准备](#环境准备)
2. [基础测试工具](#基础测试工具)
3. [测试 EAP-TTLS/PAP](#测试-eap-ttlspap)
4. [使用 eapol_test 进行完整测试](#使用-eapol_test-进行完整测试)
5. [调试模式](#调试模式)
6. [常见问题排查](#常见问题排查)

---

## 环境准备

### 1. 安装测试工具

```bash
# Debian/Ubuntu
sudo apt-get install freeradius-utils wpa-supplicant

# CentOS/RHEL
sudo yum install freeradius-utils wpa_supplicant

# Alpine
apk add freeradius-client wpa_supplicant
```

### 2. 获取客户端密钥

从 `etc/clients.conf` 中获取客户端密钥（默认）:
```
secret = "Xy9-mP2@kL_5vR!z"
```

### 3. 获取服务器地址

```bash
# 查看 FreeRADIUS 容器/服务状态
podman ps | grep freeradius

# 获取容器IP或使用主机网络模式
RADIUS_HOST="127.0.0.1"
AUTH_PORT=1812
ACCT_PORT=1813
```

---

## 基础测试工具

### radtest - 简单 PAP 认证测试

```bash
# 测试基本 PAP 认证（需要 LDAP 中有用户）
radtest -x username password@realm $RADIUS_HOST $AUTH_PORT "$secret"

# 示例
radtest -x testuser password123 127.0.0.1 1812 "Xy9-mP2@kL_5vR!z"
```

### radclient - 发送原始 RADIUS 包

```bash
# 测试 Access-Request
echo "User-Name = testuser, User-Password = password123" | \
    radclient -x $RADIUS_HOST:$AUTH_PORT auth "$secret"

# 测试 Accounting
echo "User-Name = testuser, Acct-Status-Type = Start" | \
    radclient -x $RADIUS_HOST:$ACCT_PORT acct "$secret"
```

---

## 测试 EAP-TTLS/PAP

### 方法1: 使用 eapol_test (推荐)

`eapol_test` 是最完整的 EAP 测试工具，可以模拟完整的 802.1X 认证流程。

#### 1. 创建 EAP-TTLS/PAP 测试配置文件

```bash
cat > eap-ttls-test.conf << 'EOF'
network={
    ssid="test-ssid"
    key_mgmt=WPA-EAP
    # EAP 方法: TTLS
    eap=TTLS
    # 身份信息 (真实用户名)
    identity="testuser@realm"
    # 匿名外层身份 (保护隐私)
    anonymous_identity="anonymous"
    # 密码
    password="password123"
    # 阶段 2 身份验证: PAP
    phase2="auth=PAP"
    # 证书验证 (测试环境可跳过)
    # ca_cert="/path/to/ca-cert.pem"
}
EOF
```

#### 2. 运行测试

```bash
# 使用 Docker 运行 eapol_test (推荐)
docker run --rm -it \
    --network host \
    -v $(pwd)/eap-ttls-test.conf:/test.conf \
    w1f9a2n/eapol_test \
    eapol_test -c /test.conf -s $RADIUS_HOST -a $AUTH_PORT -M 00:11:22:33:44:55

# 或者直接使用系统工具（如果已安装）
eapol_test -c eap-ttls-test.conf -s 127.0.0.1 -a 1812 \
    -M 00:11:22:33:44:55 -N 20:s00:00:00:00:00:00
```

#### 3. 成功输出示例

```
EAP: EAP entering state RECEIVED
EAP: EAP authentication completed successfully
EAP method: TTLS (21)
Result: Successful
Authentication completed.
```

#### 3. 使用预共享密钥测试（简化版）

```bash
# 创建简化配置文件
cat > simple-eap-test.conf << 'EOF'
network={
    ssid="test"
    key_mgmt=WPA-EAP
    eap=TTLS
    identity="anonymous"
    anonymous_identity="anonymous"
    password="testpassword"
    phase2="auth=PAP"
}
EOF

eapol_test -c simple-eap-test.conf -s 127.0.0.1 -a 1812 -M 00:11:22:33:44:55
```

### 方法3: 使用 wpa_supplicant 命令行测试 (推荐)

使用 `wpa_supplicant` 进行完整的 EAP-TTLS/PAP 测试，这是最接近真实客户端的方式。

#### 1. 创建 wpa_supplicant 配置文件

```bash
cat > wpa-ttls-pap.conf << 'EOF'
ctrl_interface=/var/run/wpa_supplicant
ap_scan=0

network={
    ssid="test-ssid"
    key_mgmt=WPA-EAP
    eap=TTLS
    identity="testuser@domain.com"
    anonymous_identity="anonymous"
    password="your_password"
    phase2="auth=PAP"
    
    # 测试环境可以跳过证书验证
    # 生产环境建议配置正确的 CA 证书
    # ca_cert="/etc/ssl/certs/ca-certificates.crt"
    # verify_cert=1
    
    # 强制使用指定身份验证方法
    phase1="tls_disable_tlsv1_3=1"
}
EOF
```

#### 2. 创建测试脚本

```bash
#!/bin/bash
# test-wpa-supplicant.sh

RADIUS_HOST="${RADIUS_HOST:-127.0.0.1}"
RADIUS_SECRET="${RADIUS_SECRET:-Xy9-mP2@kL_5vR!z}"

echo "=== EAP-TTLS/PAP 测试 (wpa_supplicant) ==="
echo "服务器: $RADIUS_HOST:1812"
echo ""

# 创建临时配置文件
TEMP_CONF=$(mktemp)
cat > "$TEMP_CONF" << EOF
ctrl_interface=/tmp/wpa_supplicant
ap_scan=0

network={
    ssid="test"
    key_mgmt=WPA-EAP
    eap=TTLS
    identity="testuser"
    anonymous_identity="anonymous"
    password="password123"
    phase2="auth=PAP"
}
EOF

# 启动 wpa_supplicant（后台）
wpa_supplicant -c "$TEMP_CONF" -i lo -D radius  &
WPA_PID=$!

# 等待一下让 wpa_supplicant 初始化
sleep 2

# 使用 wpa_cli 触发认证
echo "触发认证..."
echo "AP_SCAN=0" | wpa_cli -i lo

# 清理
kill $WPA_PID 2>/dev/null
rm -f "$TEMP_CONF"

echo "测试完成"
```

### 方法4: 使用 radtest + 模拟 EAP 消息

对于简单的连通性测试，可以使用以下脚本：

```bash
#!/bin/bash
# test-eap-ttls.sh

RADIUS_HOST="${RADIUS_HOST:-127.0.0.1}"
RADIUS_SECRET="${RADIUS_SECRET:-Xy9-mP2@kL_5vR!z}"
USER_IDENTITY="${USER_IDENTITY:-testuser@domain.com}"
USER_PASSWORD="${USER_PASSWORD:-password123}"

echo "=== EAP-TTLS/PAP 测试 ==="
echo "服务器: $RADIUS_HOST:1812"
echo "用户: $USER_IDENTITY"
echo ""

# 创建测试请求文件
cat > /tmp/eap-test.txt << EOF
User-Name := "$USER_IDENTITY",
User-Password := "$USER_PASSWORD",
NAS-IP-Address := 127.0.0.1,
NAS-Port-Type := Wireless-802.11,
EAP-Message := 0x02ac000d1900170104020a0aac000d1603010a010001060130130203000930110200002400
EOF

# 发送请求
radclient -x -f /tmp/eap-test.txt $RADIUS_HOST auth "$RADIUS_SECRET"

echo ""
echo "=== 测试完成 ==="
```

---

## 使用 eapol_test 进行完整测试

### 完整的测试配置模板

```bash
cat > full-eap-test.conf << 'EOF'
# 网络配置
network={
    # 基本设置
    ssid="WPA2-Enterprise"
    scan_ssid=1
    
    # EAP 类型 - TTLS
    eap=TTLS
    
    # 身份信息
    identity="user@domain.com"
    anonymous_identity="anonymous"
    
    # 密码
    password="your_password"
    
    # 内部认证协议 - PAP
    phase2="auth=PAP"
    
    # 证书验证（生产环境需要）
    # ca_cert="/etc/ssl/certs/ca-certificates.crt"
    # verify_cert=1
    
    # 可选：其他内部协议
    # phase2="auth=MSCHAPV2"
}

# 快速测试模式（简化配置）
quick_eap={
    eap=TTLS
    identity="test"
    password="test"
    phase2="auth=PAP"
}
EOF
```

### 运行完整测试

```bash
# 基本测试
eapol_test -c full-eap-test.conf -s 127.0.0.1 -a 1812 \
    -M 00:11:22:33:44:55 -N 25:s00:00:00:00:00:00

# 详细输出
eapol_test -c full-eap-test.conf -s 127.0.0.1 -a 1812 \
    -M 00:11:22:33:44:55 -N 25:s00:00:00:00:00:00 -v

# 测试成功输出示例:
# Authentication completed.
# EAP method: TTLS (21)
# Result: Successful
```

---

## 调试模式

### 1. 启动 FreeRADIUS 调试模式

```bash
# 停止当前服务
systemctl --user stop container-freeradius

# 以前台模式运行 FreeRADIUS（查看实时日志）
podman exec -it freeradius radiusd -X

# 或者使用 docker
docker exec -it freeradius radiusd -X
```

### 2. 实时查看日志

```bash
# 使用 podman/docker logs
podman logs -f freeradius

# 查看实时认证日志
podman logs freeradius 2>&1 | grep -i "auth\|accept\|reject"
```

### 3. 启用调试模式（持久配置）

在 `create-pod-systemd.sh` 中取消注释:
```bash
-e RADIUS_DEBUG=yes \
```

---

## 常见问题排查

### 问题1: EAP握手失败

**症状**: 认证被拒绝，无法完成 TLS 握手

**排查步骤**:
1. 检查证书是否有效:
   ```bash
   # 查看证书
   openssl x509 -in /path/to/certificate.crt -text -noout
   
   # 检查证书有效期
   openssl x509 -in /path/to/certificate.crt -dates
   ```

2. 检查 CA 证书是否正确配置

3. 在调试模式查看详细错误信息

### 问题2: LDAP 认证失败

**症状**: TLS 握手成功，但 Inner-Tunnel 认证失败

**排查步骤**:
1. 确认 LDAP 服务器可访问
2. 检查用户 DN 是否正确
3. 验证 LDAP 绑定密码
4. 查看 freeradius 日志中的 LDAP 错误

### 问题3: 客户端配置问题

**症状**: 客户端无法连接

**排查步骤**:
1. 检查防火墙规则:
   ```bash
   # 确认端口开放
   sudo firewall-cmd --list-all
   sudo iptables -L -n
   ```

2. 检查 SELinux/AppArmor 设置

3. 验证客户端时间同步（证书验证需要）

### 问题4: 匿名身份问题

**症状**: 外层使用 anonymous，但被拒绝

**排查方案**:
确保 `default` 服务器的 authorize 部分允许 anonymous 身份:
```plaintext
# 在 authorize 部分添加或确认:
if (!EAP-Message && User-Name == "anonymous") {
    # 允许匿名外层身份
}
```

---

## 测试脚本示例

### 一键测试脚本

```bash
#!/bin/bash
# test-freeradius-eap.sh

set -e

RADIUS_HOST="${RADIUS_HOST:-127.0.0.1}"
RADIUS_SECRET="${RADIUS_SECRET:-Xy9-mP2@kL_5vR!z}"
TEST_USER="${TEST_USER:-testuser}"
TEST_PASS="${TEST_PASS:-password123}"

echo "========================================"
echo "FreeRADIUS EAP 认证测试"
echo "========================================"
echo "服务器: $RADIUS_HOST:1812"
echo "测试用户: $TEST_USER"
echo ""

# 测试1: 基本连通性
echo "[1/4] 测试基本连通性..."
if nc -z -w3 $RADIUS_HOST 1812; then
    echo "✓ 端口 1812 可达"
else
    echo "✗ 端口 1812 不可达"
    exit 1
fi

# 测试2: PAP 认证
echo ""
echo "[2/4] 测试 PAP 认证..."
if echo "User-Name = $TEST_USER, User-Password = $TEST_PASS" | \
    radclient -x $RADIUS_HOST:1812 auth "$RADIUS_SECRET" 2>&1 | \
    grep -q "Access-Accept"; then
    echo "✓ PAP 认证成功"
else
    echo "✗ PAP 认证失败"
fi

# 测试3: 检查服务状态
echo ""
echo "[3/4] 检查服务状态..."
if podman ps | grep -q freeradius; then
    echo "✓ FreeRADIUS 容器运行中"
else
    echo "✗ FreeRADIUS 容器未运行"
fi

# 测试4: EAP-TTLS 配置检查
echo ""
echo "[4/4] 检查 EAP 配置..."
if podman exec freeradius test -f /etc/raddb/mods-enabled/eap; then
    echo "✓ EAP 模块已启用"
else
    echo "✗ EAP 模块未启用"
fi

echo ""
echo "========================================"
echo "测试完成"
echo "========================================"
```

---

## 客户端配置示例

### Windows 11

1. 设置 → 网络和 Internet → Wi-Fi → 管理已知网络
2. 添加新网络
3. 选择 "WPA3-Enterprise" 或 "WPA2-Enterprise"
4. 配置:
   - 安全类型: WPA2-Enterprise (WPA3-Enterprise)
   - 身份验证方法: PEAP 或 TTLS
   - 服务器验证: 使用证书或跳过验证（测试环境）
   - 用户名/密码: 填写 LDAP 用户凭证

### Android

1. 设置 → 网络和互联网 → Wi-Fi
2. 添加网络
3. 配置:
   - EAP 方法: TTLS
   - 阶段 2 身份验证: PAP
   - 证书: 跳过或选择 CA 证书
   - 身份: 用户名@域名
   - 密码: 密码

### iOS/macOS

1. 系统偏好设置 → 网络 → Wi-Fi → 高级
2. 添加 802.1X 配置
3. 配置:
   - 接口: Wi-Fi
   - Wi-Fi 网络名称: SSID
   - 认证类型: TTLS
   - 用户名/密码: LDAP 凭证

---

## 参考资料

- [FreeRADIUS 官方文档](https://freeradius.org/documentation/)
- [EAP 协议详解](https://docs.freeradius.org/protocols/eap.html)
- [wpa_supplicant eapol_test](https://w1.fi/cgit/hostap/plain/tests/eapol_test/)

