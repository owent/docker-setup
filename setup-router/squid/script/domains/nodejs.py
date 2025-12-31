# Node.js npm 域名配置
# 包文件的查询参数可以安全移除（版本信息在路径和文件名中）

NPM_SAFE_STRIP_DOMAINS = [
    # npm 包文件下载
    # URL: registry.npmjs.org/package/-/package-version.tgz
    r'^https?://registry\.npmjs\.org/[^/]+/-/',
    r'^https?://registry\.yarnpkg\.com/[^/]+/-/',
    r'^https?://registry\.npmmirror\.com/[^/]+/-/',
]

# npm 元数据不做 store_id 重写 (需要保持最新)
# - registry.npmjs.org/package (包信息 JSON)
