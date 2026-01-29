# CMake 官方网站域名配置
#
# 说明:
# - cmake.org 是 CMake 构建工具的官方站点
# - 下载文件和文档都包含版本号，可以长期缓存
# - 主页和动态页面使用短期缓存
#
# 主要 URL 结构:
#   下载文件 (版本号在路径中，长期缓存):
#     - cmake.org/files/v{major}.{minor}/cmake-{version}-{platform}.tar.gz
#     - cmake.org/files/v{major}.{minor}/cmake-{version}-{platform}.zip
#     - cmake.org/files/v{major}.{minor}/cmake-{version}-{platform}.msi
#     - cmake.org/files/v{major}.{minor}/cmake-{version}-{platform}.dmg
#     - cmake.org/files/v{major}.{minor}/cmake-{version}-{platform}.sh
#     - cmake.org/files/v{major}.{minor}/cmake-{version}-SHA-256.txt
#     - cmake.org/files/v{major}.{minor}/cmake-{version}-files-v1.json
#
#   文档 (版本号在路径中，长期缓存):
#     - cmake.org/cmake/help/v{version}/...
#     - cmake.org/cmake/help/latest/... (latest 指向最新稳定版)
#     - cmake.org/cmake/help/git-master/... (开发版)
#
#   动态路径 (短期缓存):
#     - cmake.org/download/
#     - cmake.org/documentation/
#     - cmake.org/files/ (目录列表)
#     - cmake.org/files/dev/ (nightly builds)

# 静态资源扩展名
_STATIC_ASSET_EXTS = (r'css|js|mjs|map|json|'
                      r'png|jpe?g|gif|webp|svg|ico|'
                      r'woff2?|ttf|eot|wasm')

# 下载文件扩展名
_DOWNLOAD_EXTS = r'tar\.gz|zip|msi|dmg|sh|txt|asc|qch'

CMAKE_SAFE_STRIP_DOMAINS = [
    # 版本化下载文件: /files/v{major}.{minor}/cmake-{version}.*
    # 版本号格式: cmake-X.Y.Z 或 cmake-X.Y.Z-rc1
    rf'^https?://cmake\.org/files/v[0-9]+\.[0-9]+/cmake-[0-9]+\.[0-9]+\.[0-9]+[^/]*\.(?:{_DOWNLOAD_EXTS})(?:\?.*)?$',

    # 版本化文档: /cmake/help/v{version}/...
    # 包含 HTML, CSS, JS 等静态资源
    rf'^https?://cmake\.org/cmake/help/v[0-9]+\.[0-9]+/',

    # latest 文档 (通常指向最新稳定版，可短期缓存)
    # 注意: latest 会随版本更新而变化，但文档页面本身是静态的
    rf'^https?://cmake\.org/cmake/help/latest/',

    # 静态资源 (CSS, JS, 图片等)
    rf'^https?://cmake\.org/.*\.(?:{_STATIC_ASSET_EXTS})(?:\?.*)?$',
]
