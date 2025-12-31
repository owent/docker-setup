# Node.js npm 域名配置
# 包文件的查询参数可以安全移除（版本信息在路径和文件名中）

NPM_SAFE_STRIP_DOMAINS = [
    # npm 包文件下载
    # URL: registry.npmjs.org/package/-/package-version.tgz
    r'^https?://registry\.npmjs\.org/[^/]+/-/',
    r'^https?://registry\.yarnpkg\.com/[^/]+/-/',
    r'^https?://registry\.npmmirror\.com/[^/]+/-/',
    # cdn.npmmirror.com 包文件
    # URL: cdn.npmmirror.com/package/-/package-version.tgz
    r'^https?://cdn\.npmmirror\.com/',
    # 腾讯云镜像包文件
    # URL: mirrors.cloud.tencent.com/npm/package/-/package-version.tgz
    r'^https?://mirrors\.cloud\.tencent\.com/npm/',
]

# npm 元数据不做 store_id 重写 (需要保持最新)
# - registry.npmjs.org/package (包信息 JSON)
