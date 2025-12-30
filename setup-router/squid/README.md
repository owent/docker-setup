# Squid 缓存代理配置

## 目录结构

```
squid/
├── etc/
│   ├── squid.conf              # 主配置文件
│   └── conf.d/                 # 模块化配置目录
│       ├── 00-unreal-engine.conf   # Unreal Engine CDN
│       ├── 10-github.conf          # GitHub 资产
│       ├── 20-cdn.conf             # 主流 CDN (jsDelivr, cdnjs, etc.)
│       ├── 30-microsoft.conf       # 微软下载 (VS, VS Code, Windows Update)
│       ├── 35-unity.conf           # Unity 下载
│       └── 99-deny-store-id.conf   # 默认拒绝 store_id
└── script/
    ├── store_id_rewriter.py    # Store ID 重写程序 (内置所有规则)
    └── domains/                # 域名配置模块 (仅供参考)
        └── ...
```

## 安装

```bash
# 复制配置文件
cp -r etc/squid.conf /etc/squid/
cp -r etc/conf.d /etc/squid/

# 复制脚本 (只需要主程序，不需要 domains 目录)
cp script/store_id_rewriter.py /usr/local/bin/
chmod +x /usr/local/bin/store_id_rewriter.py

# 创建缓存目录
mkdir -p /var/spool/squid
chown squid:squid /var/spool/squid

# 初始化缓存
squid -z

# 验证配置
squid -k parse

# 启动/重载
squid -k reconfigure
```

## Store ID 重写策略

脚本对不同类型的 URL 采用不同策略：

### 1. 安全移除参数的域名

参数仅用于签名/跟踪，不影响返回内容：

| 类型 | 域名示例 | 说明 |
|------|----------|------|
| GitHub | `release-assets.githubusercontent.com` | AWS S3 签名参数 |
| 微软下载 | `download.microsoft.com` | 签名/跟踪参数 |
| Unity | `download.unity3d.com` | CDN 参数 |
| CDNJS | `cdnjs.cloudflare.com` | 版本在路径中 |

### 2. 需要版本号才缓存的 CDN

如 `cdn.jsdelivr.net`, `unpkg.com`：

- `@1.2.3` - 有版本号，长期缓存 (30天-365天)
- `@latest` 或无版本 - **不重写 store_id**，短期缓存 (10分钟-1小时)

### 3. 不处理的 API 端点

参数会影响返回内容，不做 store_id 重写：

- `fonts.googleapis.com` - `family` 参数决定 CSS 内容
- `api.nuget.org` - API 查询
- `update.code.visualstudio.com` - 更新检查
- `packages.unity.com` - 元数据查询

## 添加新的缓存域名

### 1. 添加 Squid ACL 和 refresh_pattern

在 `etc/conf.d/` 下创建新文件，例如 `40-example.conf`:

```squid
# 区分下载和 API
acl example_downloads dstdomain cdn.example.com
acl example_api dstdomain api.example.com

cache allow example_downloads
cache allow example_api

# 只对下载做 store_id 重写
store_id_access allow example_downloads

# 下载: 长期缓存
refresh_pattern -i cdn\.example\.com 10080 100% 43200 override-expire ignore-reload ignore-no-store ignore-private
# API: 短期缓存
refresh_pattern -i api\.example\.com 10 50% 60
```

### 2. 添加 Store ID 重写规则

编辑 `script/store_id_rewriter.py`，在 `SAFE_STRIP_PATTERNS` 中添加：

```python
SAFE_STRIP_PATTERNS = [
    # ... 已有配置 ...
    # Example CDN
    re.compile(r'^https?://cdn\.example\.com/'),
]
```

## 测试 Store ID 重写

```bash
# 测试 GitHub Release (应移除参数)
echo "https://release-assets.githubusercontent.com/xxx?X-Amz-Algorithm=AWS4" | python3 /usr/local/bin/store_id_rewriter.py
# 输出: OK store-id=https://release-assets.githubusercontent.com/xxx

# 测试 jsDelivr 带版本 (应移除参数)
echo "https://cdn.jsdelivr.net/npm/vue@3.2.0/dist/vue.js" | python3 /usr/local/bin/store_id_rewriter.py
# 输出: OK store-id=https://cdn.jsdelivr.net/npm/vue@3.2.0/dist/vue.js

# 测试 jsDelivr @latest (不应重写)
echo "https://cdn.jsdelivr.net/npm/vue@latest/dist/vue.js" | python3 /usr/local/bin/store_id_rewriter.py
# 输出: ERR

# 测试 fonts.googleapis.com (不应重写，参数影响内容)
echo "https://fonts.googleapis.com/css?family=Roboto" | python3 /usr/local/bin/store_id_rewriter.py
# 输出: ERR
```

## 查看缓存命中

```bash
# 查看日志中的缓存状态
tail -f /var/log/squid/accel.log | grep -E 'HIT|MISS'

# 检查缓存内容
squidclient -h 127.0.0.1 -p 3128 mgr:storedir
```
