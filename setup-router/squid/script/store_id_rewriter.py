#!/usr/bin/env python3
"""
Squid store_id helper for caching various CDN and download resources.
Removes dynamic query parameters to enable cache hits.

Usage in squid.conf:
    store_id_program /usr/local/bin/store_id_rewriter.py
    store_id_children 10 startup=2 idle=2 concurrency=10
    store_id_access allow <acl>

Directory structure:
    store_id_rewriter.py
    domains/
        __init__.py
        github.py
        cdn.py
        microsoft.py
        unreal_engine.py
"""

from __future__ import annotations

import sys
import os
import re
from urllib.parse import urlparse, urlunparse, parse_qs
from typing import Optional

# 添加脚本所在目录到模块搜索路径
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

# =============================================================================
# 域名分类配置
# =============================================================================

# 完全安全移除参数的域名 (参数仅用于签名/跟踪，不影响内容)
SAFE_STRIP_PATTERNS = [
    # GitHub - 参数是 AWS S3 签名
    re.compile(r'^https?://release-assets\.githubusercontent\.com/'),
    re.compile(r'^https?://objects\.githubusercontent\.com/'),
    re.compile(r'^https?://codeload\.github\.com/'),
    re.compile(r'^https?://github\.com/[^/]+/[^/]+/releases/download/'),
    re.compile(r'^https?://github\.com/[^/]+/[^/]+/archive/'),
    re.compile(r'^https?://gist\.githubusercontent\.com/'),
    re.compile(r'^https?://user-attachments\.githubusercontent\.com/'),
    # CDNJS - 版本在路径中
    re.compile(r'^https?://cdnjs\.cloudflare\.com/ajax/libs/'),
    # Google Fonts 静态资源 - 路径包含哈希
    re.compile(r'^https?://fonts\.gstatic\.com/'),
    # Google AJAX - 版本在路径中
    re.compile(r'^https?://ajax\.googleapis\.com/ajax/libs/'),
    # Bootstrap CDN - 版本在路径中
    re.compile(r'^https?://cdn\.bootcdn\.net/ajax/libs/'),
    re.compile(r'^https?://stackpath\.bootstrapcdn\.com/'),
    re.compile(r'^https?://cdn\.staticfile\.org/'),
    # 微软下载 - 参数是签名/跟踪
    re.compile(r'^https?://download\.microsoft\.com/'),
    re.compile(r'^https?://download\.windowsupdate\.com/'),
    re.compile(r'^https?://dl\.delivery\.mp\.microsoft\.com/'),
    re.compile(r'^https?://emdl\.ws\.microsoft\.com/'),
    re.compile(r'^https?://download\.visualstudio\.microsoft\.com/'),
    re.compile(r'^https?://download\.visualstudio\.com/'),
    re.compile(r'^https?://az764295\.vo\.msecnd\.net/'),
    re.compile(r'^https?://vscode\.download\.prss\.microsoft\.com/'),
    # VS Code 扩展下载 (vsix 文件)
    re.compile(r'^https?://gallery\.vsassets\.io/.*\.vsix'),
    # Unreal Engine
    re.compile(r'^https?://cdn\.unrealengine\.com/'),
    # Unity 下载
    re.compile(r'^https?://download\.unity3d\.com/'),
    re.compile(r'^https?://download\.unity\.com/'),
    re.compile(r'^https?://beta\.unity3d\.com/'),
    re.compile(r'^https?://netstorage\.unity3d\.com/'),
    re.compile(r'^https?://public-cdn\.cloud\.unity3d\.com/'),
    re.compile(r'^https?://cdn-fastly\.unity3d\.com/'),
    re.compile(r'^https?://cdn\.unity\.cn/'),
    re.compile(r'^https?://upm-cdn\.unity\.com/'),
    re.compile(r'^https?://assetstorev1-prd-cdn\.unity3dusercontent\.com/'),
    re.compile(r'^https?://d2ujflorbtfzji\.cloudfront\.net/'),
    # NuGet 包下载 (nupkg 文件)
    re.compile(r'^https?://globalcdn\.nuget\.org/'),
]

# 需要检查路径中是否有版本号的 CDN (有版本号才缓存)
# 匹配 @版本号 或 /版本号/ 格式
VERSION_REQUIRED_PATTERNS = [
    # jsDelivr: /npm/package@version/ 或 /gh/user/repo@version/
    (re.compile(r'^https?://cdn\.jsdelivr\.net/'), re.compile(r'@[\d\w\.\-]+')
     ),
    # unpkg: /package@version/
    (re.compile(r'^https?://(?:www\.)?unpkg\.com/'),
     re.compile(r'@[\d\w\.\-]+')),
]

# 不应处理的域名/路径 (参数会影响返回内容)
# fonts.googleapis.com - family 参数决定返回的 CSS
# api.nuget.org - API 查询参数
# marketplace.visualstudio.com - 除了实际下载外的 API
# update.code.visualstudio.com - 更新检查 API
# packages.unity.com - 元数据 API


def get_store_id(url: str) -> Optional[str]:
    """
    根据 URL 生成 store_id，移除动态查询参数。
    返回 None 表示不修改（保持原参数）。
    """
    try:
        parsed = urlparse(url)

        # 检查完全安全的域名
        for pattern in SAFE_STRIP_PATTERNS:
            if pattern.match(url):
                # 移除查询参数和 fragment
                clean_url = urlunparse((
                    parsed.scheme,
                    parsed.netloc,
                    parsed.path,
                    '',  # params
                    '',  # query (移除)
                    ''  # fragment
                ))
                return clean_url

        # 检查需要版本号的 CDN
        for domain_pattern, version_pattern in VERSION_REQUIRED_PATTERNS:
            if domain_pattern.match(url):
                # 检查路径中是否包含版本号
                if version_pattern.search(parsed.path):
                    # 有版本号，可以安全缓存
                    clean_url = urlunparse((parsed.scheme, parsed.netloc,
                                            parsed.path, '', '', ''))
                    return clean_url
                else:
                    # 无版本号 (如 @latest)，不修改 store_id，让 Squid 使用默认行为
                    # 这样每个 @latest 请求都会重新验证
                    return None

        return None
    except Exception:
        return None


def main():
    # 禁用输出缓冲
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except AttributeError:
        # Python < 3.7 不支持 reconfigure
        import io
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, line_buffering=True)

    while True:
        try:
            line = sys.stdin.readline()
            if not line:
                break  # EOF

            line = line.strip()
            if not line:
                continue

            # Squid 发送格式: channel-ID URL [extras...]
            # 或简单格式: URL
            parts = line.split()
            if not parts:
                print("ERR")
                sys.stdout.flush()
                continue

            # 检测是否有 channel-ID (Squid concurrency 模式)
            if parts[0].isdigit():
                channel_id = parts[0]
                url = parts[1] if len(parts) > 1 else ""
                prefix = f"{channel_id} "
            else:
                channel_id = None
                url = parts[0]
                prefix = ""

            store_id = get_store_id(url)

            if store_id:
                print(f"{prefix}OK store-id={store_id}")
            else:
                print(f"{prefix}ERR")

            sys.stdout.flush()
        except Exception as e:
            # 发生异常时输出 ERR 并继续
            try:
                print("ERR")
                sys.stdout.flush()
            except Exception:
                pass


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
    except Exception:
        sys.exit(1)
