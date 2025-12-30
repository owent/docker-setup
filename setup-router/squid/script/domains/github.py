# GitHub 域名配置
# 这些域名的查询参数是 AWS S3 签名，可以安全移除
GITHUB_SAFE_STRIP_DOMAINS = [
    r'^https?://release-assets\.githubusercontent\.com/',
    r'^https?://objects\.githubusercontent\.com/',
    r'^https?://codeload\.github\.com/',
    r'^https?://github\.com/[^/]+/[^/]+/releases/download/',
    r'^https?://github\.com/[^/]+/[^/]+/archive/',
    r'^https?://gist\.githubusercontent\.com/',
    r'^https?://user-attachments\.githubusercontent\.com/',
]
