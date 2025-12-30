# Maven 仓库域名配置
# 这些域名的查询参数可以安全移除（版本信息在路径中）
MAVEN_SAFE_STRIP_DOMAINS = [
    # Maven Central - 稳定版本路径: /maven2/group/artifact/version/file
    r'^https?://repo1\.maven\.org/maven2/',
    r'^https?://repo\.maven\.apache\.org/maven2/',
    # Gradle Plugin Portal
    r'^https?://plugins\.gradle\.org/',
]

# Maven 需要检查版本号的模式
# -SNAPSHOT 版本不应该永久缓存（每次构建可能不同）
# 使用元组: (域名正则, 排除正则) - 匹配排除正则的不缓存
MAVEN_EXCLUDE_PATTERNS = [
    # 包含 -SNAPSHOT 的路径不做 store_id 重写
    r'[-]SNAPSHOT',
]
