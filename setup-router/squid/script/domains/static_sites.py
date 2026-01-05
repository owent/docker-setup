# GitHub Pages / 静态站点域名配置
#
# 说明:
# - 这里只针对“静态资源/包文件”做 store_id 参数抹除（移除全部 query）。
# - HTML/无扩展名路径不在此列，避免把不同 query 的页面内容错误合并。
#
# 适用域名:
#   - *.github.io (所有 GitHub Pages 子域名)
#   - *.jenkins.io
#   - *.goharbor.io
#   - *.rancher.io

_STATIC_ASSET_EXTS = (r'css|js|mjs|map|json|'
                      r'png|jpe?g|gif|webp|svg|ico|'
                      r'woff2?|ttf|eot|wasm|'
                      r'tgz|zip|gz|bz2|xz|zst|rpm|deb')

STATIC_SITES_SAFE_STRIP_DOMAINS = [
    # GitHub Pages: 任意 <owner>.github.io 静态资源
    rf'^https?://[^/]+\.github\.io/.*\.(?:{_STATIC_ASSET_EXTS})(?:\?.*)?$',

    # 其它静态站点/发布站点（只对资源后缀生效）
    rf'^https?://([^/]+\.jenkins\.io|[^/]+\.goharbor\.io|[^/]+\.rancher\.io)/.*\.(?:{_STATIC_ASSET_EXTS})(?:\?.*)?$',

    # 镜像站点（仅对资源后缀生效）
    rf'^https?://(mirror\.freedif\.org|mirror\.ossplanet\.net)/.*\.(?:{_STATIC_ASSET_EXTS})(?:\?.*)?$',
]
