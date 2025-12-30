# 主流 CDN 域名配置

# 完全安全移除参数的 CDN (版本号在路径中)
CDN_SAFE_STRIP_DOMAINS = [
    # CDNJS - /ajax/libs/package/version/file
    r'^https?://cdnjs\.cloudflare\.com/ajax/libs/',
    # 静态文件
    r'^https?://cdn\.staticfile\.org/',
    # Google Fonts 静态资源 - 路径包含哈希
    r'^https?://fonts\.gstatic\.com/',
    # Google AJAX - /ajax/libs/package/version/file
    r'^https?://ajax\.googleapis\.com/ajax/libs/',
    # Bootstrap CDN - 版本在路径中
    r'^https?://cdn\.bootcdn\.net/ajax/libs/',
    r'^https?://stackpath\.bootstrapcdn\.com/',
]

# 需要检查版本号的 CDN (有 @version 才缓存，@latest 不缓存)
CDN_VERSION_REQUIRED_DOMAINS = [
    # jsDelivr: /npm/package@version/
    (r'^https?://cdn\.jsdelivr\.net/', r'@[\d\w\.\-]+'),
    # unpkg: /package@version/
    (r'^https?://(?:www\.)?unpkg\.com/', r'@[\d\w\.\-]+'),
]

# 不做 store_id 重写的域名 (参数会影响返回内容)
# fonts.googleapis.com - family 参数决定返回的 CSS
