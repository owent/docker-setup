# ==============================================================================
# 阶段 1: 编译环境
# ==============================================================================
FROM debian:bookworm AS builder

# 可通过 --build-arg ATS_VERSION=10.1.0 指定版本，留空则自动获取最新版本
ARG ATS_VERSION=""

# 安装编译依赖 (ATS 10.x 使用 CMake 构建)
RUN echo 'Acquire::https::mirrors.tencent.com::Verify-Peer "false";' > /etc/apt/apt.conf.d/99ignore-ssl && \
  sed -i.bak -r 's#deb.debian.org#mirrors.tencent.com#g' /etc/apt/sources.list.d/debian.sources 2>/dev/null || \
  sed -i.bak -r 's#deb.debian.org#mirrors.tencent.com#g' /etc/apt/sources.list ; \
  apt-get update && apt-get install -y --no-install-recommends \
  # 基础构建工具
  curl \
  ca-certificates \
  build-essential \
  cmake \
  ninja-build \
  pkg-config \
  bzip2 \
  # 必需依赖
  libssl-dev \
  libpcre3-dev \
  libpcre2-dev \
  zlib1g-dev \
  # 可选功能依赖
  libcap-dev \
  libxml2-dev \
  libyaml-dev \
  libhwloc-dev \
  libluajit-5.1-dev \
  libncurses-dev \
  libcurl4-openssl-dev \
  flex \
  # 压缩支持
  libbrotli-dev \
  libzstd-dev \
  liblzma-dev \
  # GeoIP 支持 (maxmind_acl 插件)
  libmaxminddb-dev \
  # io_uring 支持 (高性能异步 IO)
  liburing-dev \
  # 高性能内存分配器
  libmimalloc-dev \
  # URI 签名支持
  libjansson-dev \
  libcjose-dev \
  && rm -rf /var/lib/apt/lists/*

# 获取版本号 (如果未指定)
RUN if [ -z "${ATS_VERSION}" ]; then \
  ATS_VERSION=$(curl -fsSL "https://trafficserver.apache.org/downloads" | \
  sed -nE 's/.*trafficserver-([0-9]+\.[0-9]+\.[0-9]+)\.tar\.bz2.*/\1/p' | \
  head -1); \
  fi; \
  echo "${ATS_VERSION}" > /tmp/ats_version.txt; \
  echo "ATS version: ${ATS_VERSION}"

# 编译 ATS (源码包通过挂载 /download 目录缓存)
# 构建时挂载: docker build -v $(pwd)/download:/download ...
RUN set -ex; \
  ATS_VERSION=$(cat /tmp/ats_version.txt); \
  TARBALL="trafficserver-${ATS_VERSION}.tar.bz2"; \
  CACHE_FILE="/download/${TARBALL}"; \
  # 检查缓存中是否已有源码包
  if [ -f "${CACHE_FILE}" ]; then \
  echo "Using cached source: ${CACHE_FILE}"; \
  cp "${CACHE_FILE}" /tmp/trafficserver-${ATS_VERSION}.tar.bz2; \
  else \
  echo "Downloading ATS ${ATS_VERSION}..."; \
  curl -fsSL "https://downloads.apache.org/trafficserver/${TARBALL}" -o /tmp/trafficserver-${ATS_VERSION}.tar.bz2; \
  # 保存到缓存 (如果目录存在且可写)
  if [ -d "/download" ] && [ -w "/download" ]; then \
  cp /tmp/trafficserver-${ATS_VERSION}.tar.bz2 "${CACHE_FILE}"; \
  fi; \
  fi; \
  echo "Building ATS version: ${ATS_VERSION}"; \
  cd /tmp; \
  tar xjf /tmp/trafficserver-${ATS_VERSION}.tar.bz2; \
  cd trafficserver-${ATS_VERSION}; \
  # 使用 CMake 构建 (ATS 10.x)
  # 注意: ATS 10.x 使用 CMAKE_INSTALL_* 变量控制安装路径
  cmake -B build -G Ninja \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DCMAKE_BUILD_TYPE=Release \
  -DWITH_USER=trafficserver \
  -DWITH_GROUP=trafficserver \
  -DCMAKE_INSTALL_SYSCONFDIR=/etc/trafficserver \
  -DCMAKE_INSTALL_LOCALSTATEDIR=/var \
  -DCMAKE_INSTALL_RUNSTATEDIR=/var/run/trafficserver \
  -DBUILD_EXPERIMENTAL_PLUGINS=ON \
  -DENABLE_MIMALLOC=ON \
  -DENABLE_URI_SIGNING=ON; \
  cmake --build build -j$(nproc); \
  # 安装到临时目录
  DESTDIR=/tmp/ats-install cmake --install build; \
  # 列出安装的目录结构 (调试用)
  echo "=== Installed directories ===" && \
  find /tmp/ats-install -type d -maxdepth 3 && \
  # 清理不需要的文件
  rm -rf /tmp/ats-install/usr/include \
  /tmp/ats-install/usr/lib/pkgconfig \
  /tmp/ats-install/usr/share/doc \
  /tmp/ats-install/usr/share/man

# ==============================================================================
# 阶段 2: 运行环境
# ==============================================================================
FROM debian:bookworm

# 安装运行时依赖
RUN echo 'Acquire::https::mirrors.tencent.com::Verify-Peer "false";' > /etc/apt/apt.conf.d/99ignore-ssl && \
  sed -i.bak -r 's#deb.debian.org#mirrors.tencent.com#g' /etc/apt/sources.list.d/debian.sources 2>/dev/null || \
  sed -i.bak -r 's#deb.debian.org#mirrors.tencent.com#g' /etc/apt/sources.list ; \
  apt-get update && apt-get install -y --no-install-recommends \
  # 基础工具
  ca-certificates \
  tzdata \
  curl \
  dnsutils \
  supervisor \
  # 必需运行时库
  libssl3 \
  libpcre3 \
  libpcre2-8-0 \
  zlib1g \
  # 可选功能运行时库
  libcap2 \
  libxml2 \
  libyaml-0-2 \
  libhwloc15 \
  libluajit-5.1-2 \
  libncurses6 \
  libcurl4 \
  # 压缩支持
  libbrotli1 \
  libzstd1 \
  liblzma5 \
  # GeoIP 支持
  libmaxminddb0 \
  # io_uring 支持
  liburing2 \
  # 高性能内存分配器
  libmimalloc2.0 \
  # URI 签名支持
  libjansson4 \
  libcjose0 \
  && rm -rf /var/lib/apt/lists/* \
  && update-ca-certificates

# 创建 trafficserver 用户和组
RUN groupadd -r trafficserver && \
  useradd -r -g trafficserver -d /var/cache/trafficserver -s /sbin/nologin trafficserver

# 从编译阶段复制 ATS
COPY --from=builder /tmp/ats-install/usr /usr/
COPY --from=builder /tmp/ats-install/etc/trafficserver /etc/trafficserver/
COPY --from=builder /tmp/ats-install/var /var/

# 复制 body_factory 错误页面模板
COPY ./body_factory/ /usr/share/trafficserver/body_factory/

# 复制自定义 CA 证书 (可选)
COPY ./ca-certificates/ /usr/local/share/ca-certificates/
RUN update-ca-certificates || true

# 创建必要的目录并设置权限
RUN mkdir -p /var/cache/trafficserver \
  /var/log/trafficserver \
  /var/run/trafficserver \
  /var/log/supervisor; \
  chown -R trafficserver:trafficserver \
  /var/cache/trafficserver \
  /var/log/trafficserver \
  /var/run/trafficserver \
  /etc/trafficserver \
  /usr/share/trafficserver

# 复制 supervisor 配置
COPY supervisor/supervisord.conf /etc/supervisord.conf

# 暴露端口
# 3126: HTTP 代理端口
EXPOSE 3126

# 使用 supervisor 管理进程
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
