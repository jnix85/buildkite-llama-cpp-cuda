#!/usr/bin/env bash
# ==============================================================================
# llama.cpp Host Debian Packaging Script
# Target: Sigrun (Overclocked i9-9900K 8C | RTX 2070 Super CC 7.5 | Ubuntu 26.04)
# ==============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_DIR}"

SRC_DIR="${1:-${HOME}/src/apps/llama.cpp}"
BIN_DIR=""
if [ -d "${SRC_DIR}/build/bin" ]; then
    BIN_DIR="${SRC_DIR}/build/bin"
elif [ -f "${SRC_DIR}/llama-server" ]; then
    BIN_DIR="${SRC_DIR}"
elif [ -d "/opt/llama.cpp" ] && [ -f "/opt/llama.cpp/llama-server" ]; then
    BIN_DIR="/opt/llama.cpp"
else
    echo "ERROR: Compiled binaries not found in ${SRC_DIR}/build/bin or /opt/llama.cpp"
    echo "Please build llama.cpp first, e.g.:"
    echo "  cmake -B build -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=75"
    echo "  cmake --build build --config Release -j8"
    exit 1
fi

VERSION="0.4.0"
COMMIT="$(git -C "${SRC_DIR}" rev-parse --short HEAD 2>/dev/null || echo "local")"
PKG_VERSION="${VERSION}-${COMMIT}"
PKG_NAME="llama-server-cuda_${PKG_VERSION}_amd64"
BUILD_ROOT="./dist/${PKG_NAME}"

echo "==> Staging Debian package: ${PKG_NAME}..."
rm -rf "${BUILD_ROOT}"
mkdir -p "${BUILD_ROOT}/DEBIAN" \
         "${BUILD_ROOT}/opt/llama.cpp/bin" \
         "${BUILD_ROOT}/usr/local/bin" \
         "${BUILD_ROOT}/etc/ld.so.conf.d" \
         "${BUILD_ROOT}/etc/default" \
         "${BUILD_ROOT}/lib/systemd/system" \
         "./dist"

cp -a "${BIN_DIR}/"* "${BUILD_ROOT}/opt/llama.cpp/"
if [ -f "${SRC_DIR}/LICENSE" ]; then
    cp "${SRC_DIR}/LICENSE" "${BUILD_ROOT}/opt/llama.cpp/"
elif [ -f "/opt/llama.cpp/LICENSE" ]; then
    cp "/opt/llama.cpp/LICENSE" "${BUILD_ROOT}/opt/llama.cpp/"
fi
echo "/opt/llama.cpp" > "${BUILD_ROOT}/etc/ld.so.conf.d/llama-cpp.conf"

# Stage systemd service unit, environment configuration template, and launcher
cp "${REPO_DIR}/systemd/llama-server.service" "${BUILD_ROOT}/lib/systemd/system/llama-server.service"
cp "${REPO_DIR}/systemd/llama-server.default" "${BUILD_ROOT}/etc/default/llama-server"
cp "${REPO_DIR}/systemd/llama-server-launcher.sh" "${BUILD_ROOT}/opt/llama.cpp/bin/llama-server-launcher"

cat << 'EOF' > "${BUILD_ROOT}/DEBIAN/conffiles"
/etc/default/llama-server
/etc/ld.so.conf.d/llama-cpp.conf
EOF

cat << EOF > "${BUILD_ROOT}/DEBIAN/control"
Package: llama-server-cuda
Version: ${PKG_VERSION}
Section: science
Priority: optional
Architecture: amd64
Depends: libc6 (>= 2.34), libstdc++6 (>= 11), libgomp1, libnccl2, libcublas12, libssl3 | libssl3t64, nvidia-cuda-toolkit | libcudart12
Maintainer: Sigrun Systems <osadmin@sigrun>
Description: High-performance llama.cpp server and CLI tools with CUDA Turing (CC 7.5) support.
 Includes llama-server, llama-cli, and modular GGML CUDA compute shared libraries.
EOF

cat << 'EOF' > "${BUILD_ROOT}/DEBIAN/postinst"
#!/bin/sh
set -e
ldconfig
ln -sf /opt/llama.cpp/llama-server /usr/local/bin/llama-server
ln -sf /opt/llama.cpp/llama-cli /usr/local/bin/llama-cli
ln -sf /opt/llama.cpp/llama-bench /usr/local/bin/llama-bench
ln -sf /opt/llama.cpp/bin/llama-server-launcher /usr/local/bin/llama-server-launcher
if [ ! -d /models ]; then
    mkdir -p /models
    chown -R osadmin:osadmin /models 2>/dev/null || true
    chmod 775 /models 2>/dev/null || true
fi
if [ -d /run/systemd/system ]; then
    systemctl daemon-reload >/dev/null 2>&1 || true
fi
exit 0
EOF

cat << 'EOF' > "${BUILD_ROOT}/DEBIAN/prerm"
#!/bin/sh
set -e
if [ -d /run/systemd/system ] && systemctl is-active --quiet llama-server 2>/dev/null; then
    systemctl stop llama-server 2>/dev/null || true
fi
rm -f /usr/local/bin/llama-server /usr/local/bin/llama-cli /usr/local/bin/llama-bench /usr/local/bin/llama-server-launcher
exit 0
EOF

cat << 'EOF' > "${BUILD_ROOT}/DEBIAN/postrm"
#!/bin/sh
set -e
ldconfig
if [ -d /run/systemd/system ]; then
    systemctl daemon-reload >/dev/null 2>&1 || true
fi
exit 0
EOF

chmod 755 "${BUILD_ROOT}/DEBIAN/postinst" "${BUILD_ROOT}/DEBIAN/prerm" "${BUILD_ROOT}/DEBIAN/postrm" "${BUILD_ROOT}/opt/llama.cpp/bin/llama-server-launcher"
chmod 644 "${BUILD_ROOT}/DEBIAN/control" "${BUILD_ROOT}/DEBIAN/conffiles" "${BUILD_ROOT}/lib/systemd/system/llama-server.service" "${BUILD_ROOT}/etc/default/llama-server" "${BUILD_ROOT}/etc/ld.so.conf.d/llama-cpp.conf"

echo "==> Assembling .deb package..."
dpkg-deb --build --root-owner-group "${BUILD_ROOT}"
echo "==> Package ready: dist/${PKG_NAME}.deb"

