# Unity 下载域名配置
# 仅包含可安全移除查询参数的下载域名
# API 域名不在此列表中 (参数会影响返回内容)
UNITY_SAFE_STRIP_DOMAINS = [
    # Unity 编辑器下载
    r'^https?://download\.unity3d\.com/',
    r'^https?://beta\.unity3d\.com/',
    r'^https?://netstorage\.unity3d\.com/',
    # Unity CDN
    r'^https?://public-cdn\.cloud\.unity3d\.com/',
]

# API 域名 (不做 store_id 重写)
# packages.unity.com - Package Manager 元数据 API
