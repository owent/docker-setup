# 微软下载域名配置
# 仅包含可安全移除查询参数的下载域名
# API 域名不在此列表中 (参数会影响返回内容)

_STATIC_ASSET_EXTS = (r'css|js|mjs|map|json|'
                      r'png|jpe?g|gif|webp|svg|ico|'
                      r'woff2?|ttf|eot|wasm|'
                      r'zip|tgz|gz|bz2|xz|zst|rpm|deb|'
                      r'nupkg|vsix|vspackage')

MICROSOFT_SAFE_STRIP_DOMAINS = [
    # Windows Update
    r'^https?://download\.microsoft\.com/',
    r'^https?://download\.windowsupdate\.com/',
    r'^https?://dl\.delivery\.mp\.microsoft\.com/',
    # Visual Studio
    r'^https?://download\.visualstudio\.microsoft\.com/',
    r'^https?://download\.visualstudio\.com/',
    # VS Code
    r'^https?://vscode\.download\.prss\.microsoft\.com/',
    # VS Code Marketplace CDN (扩展包下载)
    rf'^https?://[^/]+\.gallerycdn\.vsassets\.io/.*\.(?:{_STATIC_ASSET_EXTS})(?:\?.*)?$',
    rf'^https?://cdn\.vsassets\.io/.*\.(?:{_STATIC_ASSET_EXTS})(?:\?.*)?$',
    # 经典 Microsoft CDN
    rf'^https?://ajax\.aspnetcdn\.com/.*\.(?:{_STATIC_ASSET_EXTS})(?:\?.*)?$',
    rf'^https?://ajax\.microsoft\.com/.*\.(?:{_STATIC_ASSET_EXTS})(?:\?.*)?$',
    # Office CDN
    r'^https?://officecdn\.microsoft\.com/',
    # NuGet 包下载
    r'^https?://globalcdn\.nuget\.org/',
]

# API 域名 (不做 store_id 重写)
# update.code.visualstudio.com - 更新检查 API
# api.nuget.org - API 查询
