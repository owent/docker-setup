# Golang 模块代理域名配置
# 这些域名的查询参数可以安全移除（版本信息在路径中）
GOLANG_SAFE_STRIP_DOMAINS = [
    # Go Module Proxy - /@v/version.info, /@v/version.mod, /@v/version.zip
    r'^https?://proxy\.golang\.org/',
    # Go Checksum Database - /lookup/module@version
    r'^https?://sum\.golang\.org/',
]
