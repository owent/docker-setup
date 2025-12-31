# Python PyPI 域名配置
# 包文件的查询参数可以安全移除（版本信息在路径和文件名中）

PYTHON_SAFE_STRIP_DOMAINS = [
    # PyPI 包文件下载
    # URL: files.pythonhosted.org/packages/xx/xx/hash/package-version.whl
    r'^https?://files\.pythonhosted\.org/packages/',
]

# PyPI 元数据不做 store_id 重写 (需要保持最新)
# - pypi.org/simple/package/
# - pypi.org/pypi/package/json
