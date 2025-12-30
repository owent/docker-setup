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
        unity.py
        golang.py
        maven.py
"""

from __future__ import annotations

import sys
import os
import re
from urllib.parse import urlparse, urlunparse
from typing import Optional, List, Tuple, Pattern

# 添加脚本所在目录到模块搜索路径
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

# 从 domains 模块导入配置
from domains import (
    ALL_SAFE_STRIP_PATTERNS,
    ALL_VERSION_REQUIRED_PATTERNS,
    ALL_EXCLUDE_PATTERNS,
)

# =============================================================================
# 编译正则表达式
# =============================================================================

# 完全安全移除参数的域名 (参数仅用于签名/跟踪，不影响内容)
SAFE_STRIP_PATTERNS: List[Pattern[str]] = [
    re.compile(pattern) for pattern in ALL_SAFE_STRIP_PATTERNS
]

# 需要检查路径中是否有版本号的 CDN (有版本号才缓存)
VERSION_REQUIRED_PATTERNS: List[Tuple[Pattern[str], Pattern[str]]] = [
    (re.compile(domain_pattern), re.compile(version_pattern))
    for domain_pattern, version_pattern in ALL_VERSION_REQUIRED_PATTERNS
]

# 排除模式 (匹配这些模式的 URL 不做 store_id 重写)
EXCLUDE_PATTERNS: List[Pattern[str]] = [
    re.compile(pattern) for pattern in ALL_EXCLUDE_PATTERNS
]


def get_store_id(url: str) -> Optional[str]:
    """
    根据 URL 生成 store_id，移除动态查询参数。
    返回 None 表示不修改（保持原参数）。
    """
    try:
        parsed = urlparse(url)

        # 首先检查排除模式 (如 -SNAPSHOT)
        for pattern in EXCLUDE_PATTERNS:
            if pattern.search(url):
                return None

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
