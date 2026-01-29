# C++ 文档网站域名配置
#
# 说明:
# - 这些是常用的 C++ 语言参考和文档网站
# - 文档页面内容相对稳定，可以使用中期缓存
# - 静态资源 (CSS, JS, 图片) 可以长期缓存
#
# 主要域名:
#   - en.cppreference.com (C++ 标准库参考，最权威的非官方文档)
#   - cppreference.com (旧版/根域名)
#   - cplusplus.com (另一个流行的 C++ 参考站点)
#   - isocpp.org (ISO C++ 官方网站)
#   - www.boost.org (Boost 库官方文档)
#
# URL 结构:
#   cppreference.com:
#     - /w/cpp/... (C++ 文档)
#     - /w/c/... (C 文档)
#     - /mwiki/... (MediaWiki 资源)
#   cplusplus.com:
#     - /reference/... (标准库参考)
#     - /doc/... (教程)
#   boost.org:
#     - /doc/libs/{version}/... (版本化文档)
#     - /doc/libs/latest/... (最新版文档)

# 静态资源扩展名
_STATIC_ASSET_EXTS = (r'css|js|mjs|map|json|'
                      r'png|jpe?g|gif|webp|svg|ico|'
                      r'woff2?|ttf|eot|wasm')

CPPDOCS_SAFE_STRIP_DOMAINS = [
    # cppreference.com - C/C++ 标准库参考
    # 主要文档页面 (wiki 格式，页面内容相对稳定)
    r'^https?://en\.cppreference\.com/w/',
    r'^https?://cppreference\.com/w/',
    r'^https?://zh\.cppreference\.com/w/',

    # cppreference.com 静态资源
    rf'^https?://(en|zh)?\.?cppreference\.com/.*\.(?:{_STATIC_ASSET_EXTS})(?:\?.*)?$',

    # cplusplus.com - C++ 参考和教程
    r'^https?://(www\.)?cplusplus\.com/reference/',
    r'^https?://(www\.)?cplusplus\.com/doc/',
    rf'^https?://(www\.)?cplusplus\.com/.*\.(?:{_STATIC_ASSET_EXTS})(?:\?.*)?$',

    # isocpp.org - ISO C++ 官方网站
    # 静态页面和资源
    r'^https?://isocpp\.org/std/',
    r'^https?://isocpp\.org/wiki/',
    r'^https?://isocpp\.org/files/',
    rf'^https?://isocpp\.org/.*\.(?:{_STATIC_ASSET_EXTS})(?:\?.*)?$',

    # Boost 文档 - 版本化路径 (可长期缓存)
    # /doc/libs/1_xx_x/... 或 /doc/libs/release/...
    r'^https?://(www\.)?boost\.org/doc/libs/[0-9]+_[0-9]+_[0-9]+/',
    r'^https?://(www\.)?boost\.org/doc/libs/release/',

    # Boost 静态资源
    rf'^https?://(www\.)?boost\.org/.*\.(?:{_STATIC_ASSET_EXTS})(?:\?.*)?$',
]
