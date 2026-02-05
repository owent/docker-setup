#!/bin/bash

set -ex

eval "INSTALL_DISTRIBUTION=$(cat /etc/os-release | awk 'match($0, "^ID=(.+)", a) {print a[1]}')"
INSTALL_PREFIX=/opt
TOOLS_INSTALL_PREFIX=$INSTALL_PREFIX/tools

CMAKE_VERSION=3.31.4
CMAKE_DOWNLOAD_URL=https://github.com/Kitware/CMake/releases/download/v$CMAKE_VERSION/cmake-$CMAKE_VERSION-linux-x86_64.sh
NINJA_VERSION=v1.12.1
NINJA_DOWNLOAD_URL=https://github.com/ninja-build/ninja/releases/download/$NINJA_VERSION/ninja-linux.zip
BAZEL_VERSION=7.4.1
BAZEL_DOWN_URL=https://github.com/bazelbuild/bazel/releases/download/$BAZEL_VERSION/bazel-$BAZEL_VERSION-installer-linux-x86_64.sh
GCC_INSTALLER_VERSION=14
LLVM_INSTALLER_VERSION=19.1
GCC_INSTALLER_URL=https://raw.githubusercontent.com/owent-utils/bash-shell/main/GCC%20Installer/gcc-$GCC_INSTALLER_VERSION/installer.sh
LLVM_INSTALLER_URL=https://raw.githubusercontent.com/owent-utils/bash-shell/main/LLVM%26Clang%20Installer/$LLVM_INSTALLER_VERSION/installer-bootstrap.sh
if [[ "x$JDK_DOWNLOAD_URL" == "x" ]]; then
  JDK_DOWNLOAD_URL=https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.5%2B11/OpenJDK21U-jdk_x64_linux_hotspot_21.0.5_11.tar.gz
fi
VCPKG_GIT_UTL=https://github.com/microsoft/vcpkg.git
VCPKG_VERSION=2024.11.16
RE2C_VERSION=3.1
RE2C_DOWNLOAD_URL=https://github.com/skvadrik/re2c/releases/download/$RE2C_VERSION/re2c-$RE2C_VERSION.tar.xz
GIT_VERSION=2.47.1
GIT_DOWNLOAD_URL=https://mirrors.edge.kernel.org/pub/software/scm/git/git-$GIT_VERSION.tar.xz
GIT_LFS_VERSION=3.6.0
GIT_LFS_DOWNLOAD_URL=https://github.com/git-lfs/git-lfs/releases/download/v$GIT_LFS_VERSION/git-lfs-linux-amd64-v$GIT_LFS_VERSION.tar.gz
CURL_VERSION=8.11.1
CURL_DOWNLOAD_URL=https://github.com/curl/curl/releases/download/curl-${CURL_VERSION//./_}/curl-$CURL_VERSION.tar.xz
VALGRIND_VERSION=3.24.0
VALGRIND_DOWNLOAD_URL=https://sourceware.org/pub/valgrind/valgrind-$VALGRIND_VERSION.tar.bz2
DISTCC_VERSION=3.4
DISTCC_DOWNLOAD_URL=https://github.com/distcc/distcc/releases/download/v$DISTCC_VERSION/distcc-$DISTCC_VERSION.tar.gz
CCACHE_VERSION=4.10.2
CCACHE_DOWNLOAD_URL=https://github.com/ccache/ccache/releases/download/v$CCACHE_VERSION/ccache-$CCACHE_VERSION.tar.gz
GOLANG_VERSION=1.23.4
# GOLANG_DOWNLOAD_URL=https://golang.org/dl/go$GOLANG_VERSION.linux-amd64.tar.gz
GOLANG_DOWNLOAD_URL=https://gomirrors.org/dl/go/go$GOLANG_VERSION.linux-amd64.tar.gz
HELM_VERSION=v3.16.3
HELM_DOWNLOAD_URL=https://get.helm.sh/helm-$HELM_VERSION-linux-amd64.tar.gz
HELM_DOWNLOAD_PLUGINS=(
  # https://github.com/chartmuseum/helm-push.git
  # https://github.com/chartmuseum/helm-login.git
)

# ============ external packages ============
READLINE_VERSION=8.2
READLINE_DOWNLOAD_URL="https://ftp.gnu.org/gnu/readline/readline-$READLINE_VERSION.tar.gz"
LIBCAP_VERSION=2.73
LIBCAP_DOWNLOAD_URL=https://mirrors.edge.kernel.org/pub/linux/libs/security/linux-privs/libcap2/libcap-$LIBCAP_VERSION.tar.xz
ZSH_VERSION=5.9
ZSH_DOWNLOAD_URL="http://www.zsh.org/pub/zsh-$ZSH_VERSION.tar.xz"
# http://www.zsh.org/pub/zsh-$ZSH_VERSION-doc.tar.xz
NODEJS_VERSION=v22.12.0
NODEJS_DOWNLOAD_URL=https://nodejs.org/dist/$NODEJS_VERSION/node-$NODEJS_VERSION-linux-x64.tar.xz
LIBEVENT_VERSION=2.1.12-stable
LIBEVENT_DOWNLOAD_URL=https://github.com/libevent/libevent/releases/download/release-$LIBEVENT_VERSION/libevent-$LIBEVENT_VERSION.tar.gz
UTF8PROC_VERSION=2.9.0
UTF8PROC_DOWNLOAD_URL=https://github.com/JuliaStrings/utf8proc/archive/refs/tags/v$UTF8PROC_VERSION.tar.gz
TMUX_VERSION=3.5a
TMUX_DOWNLOAD_URL=https://github.com/tmux/tmux/releases/download/$TMUX_VERSION/tmux-$TMUX_VERSION.tar.gz

mkdir -p /opt/setup/
cd /opt/setup/
mkdir -p "$TOOLS_INSTALL_PREFIX/bin"

export PATH="$TOOLS_INSTALL_PREFIX/bin:$TOOLS_INSTALL_PREFIX/sbin:$INSTALL_PREFIX/cmake/bin:$INSTALL_PREFIX/go/bin:$INSTALL_PREFIX/gopath/bin:$PATH"

echo '#!/bin/bash
' >"$TOOLS_INSTALL_PREFIX/load-path.sh"
echo "
OPT_TOOLCHAIN_TOOLS_INSTALL_PREFIX=\"$TOOLS_INSTALL_PREFIX\"
OPT_TOOLCHAIN_INSTALL_PREFIX=\"$INSTALL_PREFIX\"
" >>"$TOOLS_INSTALL_PREFIX/load-path.sh"
echo '
export PATH="$OPT_TOOLCHAIN_TOOLS_INSTALL_PREFIX/bin:$OPT_TOOLCHAIN_TOOLS_INSTALL_PREFIX/sbin:$OPT_TOOLCHAIN_INSTALL_PREFIX/cmake/bin:$OPT_TOOLCHAIN_INSTALL_PREFIX/go/bin:$OPT_TOOLCHAIN_INSTALL_PREFIX/gopath/bin:$OPT_TOOLCHAIN_INSTALL_PREFIX/jdk/current/bin:$OPT_TOOLCHAIN_INSTALL_PREFIX/vcpkg:$PATH"
export GOPROXY=https://mirrors.cloud.tencent.com/go/
' >>"$TOOLS_INSTALL_PREFIX/load-path.sh"

chmod +x "$TOOLS_INSTALL_PREFIX/load-path.sh"

function download_file() {
  PKG_URL="$1"
  if [[ -z "$2" ]]; then
    OUTPUT_FILE="$(basename "$PKG_URL")"
  else
    OUTPUT_FILE="$2"
  fi

  DOWNLOAD_SUCCESS=1
  for ((i = 0; i < 5; ++i)); do
    if [[ $DOWNLOAD_SUCCESS -eq 0 ]]; then
      break
    fi
    DOWNLOAD_SUCCESS=0
    if [[ $i -ne 0 ]]; then
      echo "Retry to download from $PKG_URL to $OUTPUT_FILE again."
      sleep $i || true
    fi
    curl -kL "$PKG_URL" -o "$OUTPUT_FILE" || DOWNLOAD_SUCCESS=1
  done

  if [[ $DOWNLOAD_SUCCESS -ne 0 ]]; then
    echo -e "\\033[31;1mDownload $OUTPUT_FILE from $PKG_URL failed.\\033[39;49;0m"
    rm -f "$OUTPUT_FILE" || true
  fi

  return $DOWNLOAD_SUCCESS
}

# cmake - Install into standalone PATH which will be addedinto default search PATH by cmake
mkdir -p "$INSTALL_PREFIX/cmake"
curl -kL "$CMAKE_DOWNLOAD_URL" -o cmake-linux-x86_64.sh
bash cmake-linux-x86_64.sh --prefix="$INSTALL_PREFIX/cmake" --skip-license

# Ninja
download_file "$NINJA_DOWNLOAD_URL" ninja-linux.zip
unzip -o ninja-linux.zip -d "$TOOLS_INSTALL_PREFIX/bin"

# JDK
if [[ -e "$INSTALL_PREFIX/jdk" ]]; then
  rm -rf "$INSTALL_PREFIX/jdk"
fi
mkdir -p "$INSTALL_PREFIX/jdk"
cd "$INSTALL_PREFIX/jdk"
JDK_BASE_NAME="$(basename \"$JDK_DOWNLOAD_URL\")";
download_file "$JDK_DOWNLOAD_URL" "$JDK_BASE_NAME"
tar -axvf "$JDK_BASE_NAME" && rm -f "$JDK_BASE_NAME"
JAVA_HOME="$(find "$PWD" -name javac)"
JAVA_HOME="$(dirname "$JAVA_HOME")"
JAVA_HOME="$(dirname "$JAVA_HOME")"
if [[ -f "current" ]]; then
  rm -rf "current"
fi
ln -sf "$JAVA_HOME" "$PWD/current"
JAVA_HOME="$PWD/current"
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"
cd /opt/setup

# bazel
download_file "$BAZEL_DOWN_URL" bazel-installer-linux-x86_64.sh
bash bazel-installer-linux-x86_64.sh --prefix=$TOOLS_INSTALL_PREFIX

# gcc
mkdir -p /opt/setup/gcc
cd /opt/setup/gcc
download_file "$GCC_INSTALLER_URL" installer.sh
bash ./installer.sh -p "$INSTALL_PREFIX/gcc-$GCC_INSTALLER_VERSION" -d
if [[ $? -ne 0 ]]; then
  echo -e "\\033[31;1mDownload gcc sources failed.\\033[0m"
  exit 1
fi

bash ./installer.sh -p "$INSTALL_PREFIX/gcc-$GCC_INSTALLER_VERSION"
if [[ -e "$INSTALL_PREFIX/gcc-latest" ]]; then
  rm -rf "$INSTALL_PREFIX/gcc-latest"
fi
ln -sf "$INSTALL_PREFIX/gcc-$GCC_INSTALLER_VERSION" "$INSTALL_PREFIX/gcc-latest"

if [[ "x$LD_LIBRARY_PATH" == "x" ]]; then
  export LD_LIBRARY_PATH="$TOOLS_INSTALL_PREFIX/lib64:$TOOLS_INSTALL_PREFIX/lib"
else
  export LD_LIBRARY_PATH="$TOOLS_INSTALL_PREFIX/lib64:$TOOLS_INSTALL_PREFIX/lib:$LD_LIBRARY_PATH"
fi

source $INSTALL_PREFIX/gcc-latest/load-gcc-envs.sh
ALL_LDFLAGS="-L$TOOLS_INSTALL_PREFIX/lib64 -L$TOOLS_INSTALL_PREFIX/lib"
ALL_LDFLAGS="$ALL_LDFLAGS -L$GCC_HOME_DIR/lib64 -L$GCC_HOME_DIR/lib"
ALL_LDFLAGS="$ALL_LDFLAGS -L$GCC_HOME_DIR/internal-packages/lib64 -L$GCC_HOME_DIR/internal-packages/lib"
ALL_CFLAGS="-I$TOOLS_INSTALL_PREFIX/include -I$GCC_HOME_DIR/internal-packages/include"
if [[ "x$PKG_CONFIG_PATH" == "x" ]]; then
  export PKG_CONFIG_PATH="$TOOLS_INSTALL_PREFIX/lib/pkgconfig:$GCC_HOME_DIR/internal-packages/lib/pkgconfig:$GCC_HOME_DIR/lib64/pkgconfig:$GCC_HOME_DIR/lib/pkgconfig"
else
  export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:$TOOLS_INSTALL_PREFIX/lib/pkgconfig:$GCC_HOME_DIR/internal-packages/lib/pkgconfig:$GCC_HOME_DIR/lib64/pkgconfig:$GCC_HOME_DIR/lib/pkgconfig"
fi

# See https://stackoverflow.com/questions/42344932/how-to-include-correctly-wl-rpath-origin-linker-argument-in-a-makefile
GCC_RPATH_LDFLAGS="-Wl,-rpath=\$ORIGIN/../lib64:\$ORIGIN/../lib:$GCC_HOME_DIR/internal-packages/lib64:$GCC_HOME_DIR/internal-packages/lib:$GCC_HOME_DIR/lib64:$GCC_HOME_DIR/lib"
export ALL_LDFLAGS="$ALL_LDFLAGS $GCC_RPATH_LDFLAGS"
if [[ "x$LDFLAGS" == "x" ]]; then
  export LDFLAGS="$GCC_RPATH_LDFLAGS"
else
  export LDFLAGS="$LDFLAGS $GCC_RPATH_LDFLAGS"
fi
export ORIGIN='$ORIGIN'

# libcurl
cd /opt/setup/
download_file "$CURL_DOWNLOAD_URL" "curl-$CURL_VERSION.tar.xz"
tar -axvf "curl-$CURL_VERSION.tar.xz"
mkdir "curl-$CURL_VERSION/build_jobs_dir"
cd "curl-$CURL_VERSION/build_jobs_dir"
cmake .. "-DCMAKE_INSTALL_PREFIX=$TOOLS_INSTALL_PREFIX" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DBUILD_TESTING=OFF -DCURL_ZSTD=ON -DCMAKE_USE_OPENSSL=ON -DBUILD_SHARED_LIBS=ON \
  -DOPENSSL_ROOT_DIR=$GCC_HOME_DIR/internal-packages \
  "-DCMAKE_FIND_ROOT_PATH=$GCC_HOME_DIR/internal-packages;$GCC_HOME_DIR" \
  "-DCMAKE_PREFIX_PATH=$GCC_HOME_DIR/internal-packages;$GCC_HOME_DIR"

cmake --build . -j || cmake --build . -j2 || cmake --build .
cmake --build . --target install

cd ../..

# git,git-lfs
cd /opt/setup/
if [[ ! -e "re2c-$RE2C_VERSION.tar.xz" ]]; then
  download_file $RE2C_DOWNLOAD_URL re2c-$RE2C_VERSION.tar.xz
  if [[ $? -ne 0 ]]; then
    rm -f re2c-$RE2C_VERSION.tar.xz
  fi
fi
tar -axvf re2c-$RE2C_VERSION.tar.xz
cd re2c-$RE2C_VERSION
env LDFLAGS="${LDFLAGS//\$/\$\$}" ./configure --prefix=$TOOLS_INSTALL_PREFIX --with-pic=yes
env LDFLAGS="${LDFLAGS//\$/\$\$}" make -j || env LDFLAGS="${LDFLAGS//\$/\$\$}" make
env LDFLAGS="${LDFLAGS//\$/\$\$}" make install
cd ..

if [[ ! -e "git-$GIT_VERSION.tar.xz" ]]; then
  download_file $GIT_DOWNLOAD_URL git-$GIT_VERSION.tar.xz
  if [[ $? -ne 0 ]]; then
    rm -f git-$GIT_VERSION.tar.xz
  fi
fi

tar -axvf git-$GIT_VERSION.tar.xz
cd git-$GIT_VERSION
GIT_LDFLAGS="${ALL_LDFLAGS//\$/\$\$} -Wl,-rpath=\$\$ORIGIN/../../lib64:\$\$ORIGIN/../../lib"
env LDFLAGS="$GIT_LDFLAGS" \
  ./configure --prefix=$TOOLS_INSTALL_PREFIX --with-curl=$TOOLS_INSTALL_PREFIX --with-libpcre2 --with-editor=vim \
  --with-openssl=$GCC_HOME_DIR/internal-packages --with-curl=$TOOLS_INSTALL_PREFIX \
  --with-zlib=$GCC_HOME_DIR --with-expat=$GCC_HOME_DIR
env LDFLAGS="$GIT_LDFLAGS" make -j all doc || env LDFLAGS="$GIT_LDFLAGS" make all doc
env LDFLAGS="$GIT_LDFLAGS" make install install-doc install-html
cd contrib/subtree
env LDFLAGS="$GIT_LDFLAGS" make install install-doc install-html
cd ../../../

# git lfs
mkdir -p git-lfs
cd git-lfs
if [[ ! -e "git-lfs-linux-amd64-v$GIT_LFS_VERSION.tar.gz" ]]; then
  download_file $GIT_LFS_DOWNLOAD_URL git-lfs-linux-amd64-v$GIT_LFS_VERSION.tar.gz
  if [[ $? -ne 0 ]]; then
    rm -f git-lfs-linux-amd64-v$GIT_LFS_VERSION.tar.gz
  fi
fi

mkdir git-lfs-v$GIT_LFS_VERSION
cd git-lfs-v$GIT_LFS_VERSION
tar -axvf ../git-lfs-linux-amd64-v$GIT_LFS_VERSION.tar.gz
env PREFIX=$TOOLS_INSTALL_PREFIX ./install.sh

cd ../../

# llvm
mkdir -p /opt/setup/llvm
cd /opt/setup/llvm
download_file "$LLVM_INSTALLER_URL" installer-bootstrap.sh
bash ./installer-bootstrap.sh -p "$INSTALL_PREFIX/llvm-$LLVM_INSTALLER_VERSION" -g "$GCC_HOME_DIR" -d
if [[ $? -ne 0 ]]; then
  echo -e "\\033[31;1mDownload llvm sources failed.\\033[0m"
  exit 1
fi

bash ./installer-bootstrap.sh -p "$INSTALL_PREFIX/llvm-$LLVM_INSTALLER_VERSION" -g "$GCC_HOME_DIR"
if [[ -e "$INSTALL_PREFIX/llvm-latest" ]]; then
  rm -rf "$INSTALL_PREFIX/llvm-latest"
fi
ln -sf "$INSTALL_PREFIX/llvm-$LLVM_INSTALLER_VERSION" "$INSTALL_PREFIX/llvm-latest"

# valgrind
cd /opt/setup/
download_file "$VALGRIND_DOWNLOAD_URL" "valgrind-$VALGRIND_VERSION.tar.bz2"
tar -axvf "valgrind-$VALGRIND_VERSION.tar.bz2"
cd "valgrind-$VALGRIND_VERSION"
env LDFLAGS="${LDFLAGS//\$/\$\$}" ./configure --prefix=$TOOLS_INSTALL_PREFIX --enable-lto --enable-tls --enable-inner
env LDFLAGS="${LDFLAGS//\$/\$\$}" make -j || env LDFLAGS="${LDFLAGS//\$/\$\$}" make
env LDFLAGS="${LDFLAGS//\$/\$\$}" make install
cd ..

# distcc
download_file "$DISTCC_DOWNLOAD_URL" "distcc-$DISTCC_VERSION.tar.gz"
tar -axvf "distcc-$DISTCC_VERSION.tar.gz"
cd "distcc-$DISTCC_VERSION"
env LDFLAGS="${ALL_LDFLAGS//\$/\$\$}" \
  CFLAGS="$ALL_CFLAGS" ./configure --prefix=$TOOLS_INSTALL_PREFIX
env LDFLAGS="${ALL_LDFLAGS//\$/\$\$}" make -j || env LDFLAGS="${ALL_LDFLAGS//\$/\$\$}" make
env LDFLAGS="${ALL_LDFLAGS//\$/\$\$}" make install

if [[ -e "$TOOLS_INSTALL_PREFIX/sbin/update-distcc-symlinks" ]]; then
  "$TOOLS_INSTALL_PREFIX/sbin/update-distcc-symlinks" || true
fi

# ccache
download_file "$CCACHE_DOWNLOAD_URL" "ccache-$CCACHE_VERSION.tar.gz"
tar -axvf "ccache-$CCACHE_VERSION.tar.gz"
mkdir -p ccache-$CCACHE_VERSION/build_jobs_dir
cd "ccache-$CCACHE_VERSION/build_jobs_dir"
env LDFLAGS="$ALL_LDFLAGS" \
  CFLAGS="$ALL_CFLAGS" cmake .. -DENABLE_TESTING=OFF -DHIREDIS_FROM_INTERNET=ON -DCMAKE_INSTALL_PREFIX=$TOOLS_INSTALL_PREFIX \
  "-DCMAKE_PERFIX_PATH=$GCC_HOME_DIR;$GCC_HOME_DIR/internal-packages" \
  "-DCMAKE_FIND_ROOT_PATH=$GCC_HOME_DIR;$GCC_HOME_DIR/internal-packages"

cmake --build . -j || cmake --build . -j2 || cmake --build .
cmake --build . --target install

# golang
download_file "$GOLANG_DOWNLOAD_URL" "go$GOLANG_VERSION.linux-amd64.tar.gz"
tar -axvf "go$GOLANG_VERSION.linux-amd64.tar.gz"
mv -f go "$INSTALL_PREFIX/go"
mkdir -p "$INSTALL_PREFIX/gopath"
env GO111MODULE=on GOPATH="$INSTALL_PREFIX/gopath" go install golang.org/x/tools/...@latest
env GO111MODULE=on GOPATH="$INSTALL_PREFIX/gopath" go install golang.org/x/tools/gopls@latest
env GO111MODULE=on GOPATH="$INSTALL_PREFIX/gopath" go install golang.org/x/tools/cmd/goimports@latest
env GO111MODULE=on GOPATH="$INSTALL_PREFIX/gopath" go install golang.org/x/lint/golint@latest
env GO111MODULE=on GOPATH="$INSTALL_PREFIX/gopath" go install honnef.co/go/tools/cmd/staticcheck@latest
env GO111MODULE=on GOPATH="$INSTALL_PREFIX/gopath" go install github.com/go-delve/delve/cmd/dlv@master
chmod 755 -R "$INSTALL_PREFIX/gopath"

# helm
download_file "$HELM_DOWNLOAD_URL" "helm-$HELM_VERSION-linux-amd64.tar.gz"
tar -axvf "helm-$HELM_VERSION-linux-amd64.tar.gz"
mv -f linux-amd64/helm $TOOLS_INSTALL_PREFIX/bin
for HELM_PLUGIN in ${HELM_DOWNLOAD_PLUGINS[@]}; do
  helm plugin install $HELM_PLUGIN
done

# kubectl
download_file "https://dl.k8s.io/release/stable.txt" "kubectl-stable.txt"
KUBECTL_VERSION=$(cat kubectl-stable.txt)
KUBECTL_DOWNLOAD_URL="https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl"
download_file "$KUBECTL_DOWNLOAD_URL" "$TOOLS_INSTALL_PREFIX/bin/kubectl"
chmod +x "$TOOLS_INSTALL_PREFIX/bin/kubectl"

# vcpkg
cd "$INSTALL_PREFIX"
git clone -b "$VCPKG_VERSION" --depth 1 "$VCPKG_GIT_UTL" "$INSTALL_PREFIX/vcpkg"
cd "$INSTALL_PREFIX/vcpkg"
env LDFLAGS="$ALL_LDFLAGS" CFLAGS="$ALL_CFLAGS" \
  ./bootstrap-vcpkg.sh
if [[ -e buildtrees ]]; then
  rm -rf buildtrees
fi

# alias
cd "$TOOLS_INSTALL_PREFIX/bin"
for ALIAS_BIN in *; do
  if [[ -e "/usr/bin/$ALIAS_BIN" ]]; then
    rm -f "/usr/bin/$ALIAS_BIN"
    ln -sf "$PWD/$ALIAS_BIN" "/usr/bin/$ALIAS_BIN"
  fi
done

echo "$GCC_HOME_DIR/lib64
$GCC_HOME_DIR/internal-packages/lib64
$TOOLS_INSTALL_PREFIX/lib64
$INSTALL_PREFIX/llvm-latest/lib
$GCC_HOME_DIR/lib
$GCC_HOME_DIR/internal-packages/lib
$TOOLS_INSTALL_PREFIX/lib
" >"$TOOLS_INSTALL_PREFIX/share/atframework-toolset-$(uname -m)-ld.so.conf"
# cp -f "$TOOLS_INSTALL_PREFIX/share/atframework-toolset-$(uname -m)-ld.so.conf" "/etc/ld.so.conf.d/atframework-toolset-$(uname -m).conf"
# ldconfig || true

# ============ external packages ============
## GNU readline
cd /opt/setup/
download_file "$READLINE_DOWNLOAD_URL" readline-$READLINE_VERSION.tar.gz
tar -axvf readline-$READLINE_VERSION.tar.gz
cd readline-$READLINE_VERSION
env LDFLAGS="${ALL_LDFLAGS//\$/\$\$} -static" ./configure "--prefix=$TOOLS_INSTALL_PREFIX" \
  --enable-static=yes --enable-shared=no --enable-multibyte --with-curses
env LDFLAGS="${ALL_LDFLAGS//\$/\$\$} -static" make -j || env LDFLAGS="${ALL_LDFLAGS//\$/\$\$} -static" make
env LDFLAGS="${ALL_LDFLAGS//\$/\$\$} -static" make install

## libcap
cd /opt/setup/
download_file "$LIBCAP_DOWNLOAD_URL" libcap-$LIBCAP_VERSION.tar.xz
tar -axvf libcap-$LIBCAP_VERSION.tar.xz
cd libcap-$LIBCAP_VERSION
env LDFLAGS="${ALL_LDFLAGS//\$/\$\$} -static" make RAISE_SETFCAP='no' SHARED='no' prefix=$TOOLS_INSTALL_PREFIX install

## zsh
cd /opt/setup/
download_file "$ZSH_DOWNLOAD_URL" zsh-$ZSH_VERSION.tar.xz
tar -axvf zsh-$ZSH_VERSION.tar.xz
cd zsh-$ZSH_VERSION
if [[ -e "$GCC_HOME_DIR/lib/pkgconfig/ncursesw.pc" ]]; then
  ZSH_NCURSES_LIB="ncursesw"
  ZSH_NCURSES_LINK="$(pkg-config --libs $GCC_HOME_DIR/lib/pkgconfig/ncursesw.pc)"
else
  ZSH_NCURSES_LIB="ncurses"
  ZSH_NCURSES_LINK="$(pkg-config --libs $GCC_HOME_DIR/lib/pkgconfig/ncurses.pc)"
fi

if [[ ! -e "configure" ]] && [[ -e ".preconfig" ]]; then
  env LDFLAGS="${ALL_LDFLAGS//\$/\$\$} $ZSH_NCURSES_LINK" \
    CFLAGS="$ALL_CFLAGS" bash ./.preconfig
fi

env LDFLAGS="${ALL_LDFLAGS//\$/\$\$} $ZSH_NCURSES_LINK" \
  CFLAGS="$ALL_CFLAGS" \
  ./configure \
  "--prefix=$TOOLS_INSTALL_PREFIX" \
  --docdir=/usr/share/doc/zsh \
  --htmldir=/usr/share/doc/zsh/html \
  --enable-etcdir=/etc/zsh \
  --enable-zshenv=/etc/zsh/zshenv \
  --enable-zlogin=/etc/zsh/zlogin \
  --enable-zlogout=/etc/zsh/zlogout \
  --enable-zprofile=/etc/zsh/zprofile \
  --enable-zshrc=/etc/zsh/zshrc \
  --enable-maildir-support \
  --with-term-lib=$ZSH_NCURSES_LIB \
  --enable-multibyte \
  --enable-zsh-secure-free \
  --enable-function-subdirs \
  --enable-pcre=yes \
  --enable-cap=yes \
  --enable-unicode9 \
  --with-tcsetpgrp
#--enable-libc-musl ;
env LDFLAGS="${ALL_LDFLAGS//\$/\$\$} $ZSH_NCURSES_LINK" make -j O='$$O' || env LDFLAGS="${ALL_LDFLAGS//\$/\$\$} $ZSH_NCURSES_LINK" make O='$$O'
env LDFLAGS="${ALL_LDFLAGS//\$/\$\$} $ZSH_NCURSES_LINK" make install O='$$O'

## nodejs
cd /opt/setup/
download_file "$NODEJS_DOWNLOAD_URL" "node-$NODEJS_VERSION-linux-x64.tar.xz"
tar -axvf "node-$NODEJS_VERSION-linux-x64.tar.xz"
cp -rf node-$NODEJS_VERSION-linux-x64/* $TOOLS_INSTALL_PREFIX/

## libevent
cd /opt/setup/
download_file "$LIBEVENT_DOWNLOAD_URL" libevent-$LIBEVENT_VERSION.tar.gz
tar -axvf libevent-$LIBEVENT_VERSION.tar.gz
cd libevent-$LIBEVENT_VERSION
env LDFLAGS="${ALL_LDFLAGS//\$/\$\$}" \
  CFLAGS="$ALL_CFLAGS" \
  ./configure --prefix="$TOOLS_INSTALL_PREFIX" --enable-shared=yes --enable-static=yes --with-pic
env LDFLAGS="${ALL_LDFLAGS//\$/\$\$}" make -j || env LDFLAGS="${ALL_LDFLAGS//\$/\$\$}" make
env LDFLAGS="${ALL_LDFLAGS//\$/\$\$}" make install

## utf8proc
cd /opt/setup/
download_file "$UTF8PROC_DOWNLOAD_URL" utf8proc-$UTF8PROC_VERSION.tar.gz
tar -axvf utf8proc-$UTF8PROC_VERSION.tar.gz
mkdir -p utf8proc-$UTF8PROC_VERSION/build_jobs_dir
cd utf8proc-$UTF8PROC_VERSION/build_jobs_dir
cmake .. -DCMAKE_INSTALL_PREFIX="$TOOLS_INSTALL_PREFIX" -DBUILD_SHARED_LIBS=OFF
cmake --build . -j || cmake --build . -j2 || cmake --build .
cmake --build . --target install

## tmux
cd /opt/setup/
download_file "$TMUX_DOWNLOAD_URL" tmux-$TMUX_VERSION.tar.gz
tar -axvf tmux-$TMUX_VERSION.tar.gz
cd tmux-$TMUX_VERSION
if [[ -e "$GCC_HOME_DIR/lib/pkgconfig/ncursesw.pc" ]]; then
  TMUX_NCURSES_CFLAGS="$(pkg-config --cflags $GCC_HOME_DIR/lib/pkgconfig/ncursesw.pc)"
  TMUX_NCURSES_LINK="$(pkg-config --libs $GCC_HOME_DIR/lib/pkgconfig/ncursesw.pc)"
else
  TMUX_NCURSES_CFLAGS="$(pkg-config --cflags $GCC_HOME_DIR/lib/pkgconfig/ncurses.pc)"
  TMUX_NCURSES_LINK="$(pkg-config --libs $GCC_HOME_DIR/lib/pkgconfig/ncurses.pc)"
fi
env LDFLAGS="${ALL_LDFLAGS//\$/\$\$}" \
  CFLAGS="$ALL_CFLAGS" \
  ./configure --prefix="$TOOLS_INSTALL_PREFIX" \
  --enable-utf8proc \
  PKG_CONFIG_PATH="$TOOLS_INSTALL_PREFIX/lib/pkgconfig" \
  LIBNCURSES_CFLAGS="$TMUX_NCURSES_CFLAGS" \
  LIBNCURSES_LIBS="$TMUX_NCURSES_LINK" \
  LIBEVENT_CFLAGS="$(pkg-config --cflags $TOOLS_INSTALL_PREFIX/lib/pkgconfig/libevent.pc)" \
  LIBEVENT_LIBS="$(pkg-config --libs $TOOLS_INSTALL_PREFIX/lib/pkgconfig/libevent.pc)"
# --enable-static
env LDFLAGS="${ALL_LDFLAGS//\$/\$\$}" make -j || env LDFLAGS="${ALL_LDFLAGS//\$/\$\$}" make
env LDFLAGS="${ALL_LDFLAGS//\$/\$\$}" make install

# cleanup
cd ~
rm -rf /opt/setup/
