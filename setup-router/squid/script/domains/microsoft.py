# 微软下载域名配置
# 仅包含可安全移除查询参数的下载域名
# API 域名不在此列表中 (参数会影响返回内容)
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
    # NuGet 包下载
    r'^https?://globalcdn\.nuget\.org/',
]

# API 域名 (不做 store_id 重写)
# update.code.visualstudio.com - 更新检查 API
# api.nuget.org - API 查询
