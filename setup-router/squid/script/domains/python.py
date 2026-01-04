# Python PyPI 域名配置
# 包文件和元数据的查询参数可以安全移除（版本信息在路径和文件名中）

PYTHON_SAFE_STRIP_DOMAINS = [
    # PyPI 包文件下载
    # URL: files.pythonhosted.org/packages/xx/xx/hash/package-version.whl
    r'^https?://files\.pythonhosted\.org/packages/',

    # PyPI 元数据/索引页面
    # URL: pypi.org/simple/package/
    # URL: pypi.org/pypi/package/json
    # 这些页面虽然会更新，但通过 refresh_pattern 控制缓存时间
    # 移除查询参数可以提高缓存命中率
    r'^https?://pypi\.org/simple/',
    r'^https?://pypi\.org/pypi/',
    r'^https?://pypi\.python\.org/',
]
