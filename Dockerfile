# syntax=docker/dockerfile:1
ARG CUDA_VERSION=12.4.1
ARG UBUNTU_VERSION=22.04

# ==============================================================================
# Stage 1: Build llama.cpp with CUDA Support
# ==============================================================================
FROM nvidia/cuda:${CUDA_VERSION}-devel-ubuntu${UBUNTU_VERSION} AS builder

ARG LLAMA_TAG=master
ARG CUDA_ARCH=75
ARG BUILD_THREADS=8

ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    ninja-build \
    ccache \
    pkg-config \
    ca-certificates

WORKDIR /workspace

# Clone specific release tag or branch
RUN git clone --depth 1 --branch ${LLAMA_TAG} https://github.com/ggerganov/llama.cpp.git /workspace/llama.cpp

WORKDIR /workspace/llama.cpp

# Prepare CUDA driver stubs for build-time linking without host GPU driver
RUN ln -sf /usr/local/cuda/lib64/stubs/libcuda.so /usr/local/cuda/lib64/stubs/libcuda.so.1 && \
    echo "/usr/local/cuda/lib64/stubs" > /etc/ld.so.conf.d/cuda-stubs.conf && \
    ldconfig

# Compile with CUDA acceleration targeting specified architecture (Default: CC 7.5 Turing)
RUN --mount=type=cache,target=/root/.cache/ccache \
    cmake -B build -G Ninja \
      -DGGML_CUDA=ON \
      -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCH} \
      -DCMAKE_BUILD_TYPE=Release \
      -DLLAMA_BUILD_TESTS=OFF \
      -DLLAMA_BUILD_EXAMPLES=ON && \
    cmake --build build --config Release -j${BUILD_THREADS}

# ==============================================================================
# Stage 2: Assemble Native Debian Package (.deb)
# ==============================================================================
FROM ubuntu:${UBUNTU_VERSION} AS packager

ARG LLAMA_TAG=master
WORKDIR /packager

RUN apt-get update && apt-get install -y --no-install-recommends binutils ca-certificates && rm -rf /var/lib/apt/lists/*

COPY --from=builder /workspace/llama.cpp/build/bin /staging/opt/llama.cpp
COPY --from=builder /workspace/llama.cpp/LICENSE /staging/opt/llama.cpp/LICENSE

RUN mkdir -p /staging/DEBIAN \
             /staging/usr/local/bin \
             /staging/etc/ld.so.conf.d \
             /staging/etc/default \
             /staging/etc/systemd/system \
             /dist

# Register library path
RUN echo "/opt/llama.cpp" > /staging/etc/ld.so.conf.d/llama-cpp.conf

# Control file
RUN PKG_VER=$(echo "${LLAMA_TAG}" | tr -d "v") && \
    cat << CONTROL_EOF > /staging/DEBIAN/control
Package: llama-server-cuda
Version: ${PKG_VER}
Section: science
Priority: optional
Architecture: amd64
Depends: libc6 (>= 2.34), libstdc++6 (>= 11), libgomp1, nvidia-cuda-toolkit | libcudart12
Maintainer: Sigrun Systems <osadmin@sigrun>
Description: High-performance llama.cpp server and CLI tools compiled with CUDA Turing (CC 7.5) support.
 Built via BuildKit for automated deployment.
CONTROL_EOF

# Maintainer scripts
RUN cat << 'POSTINST_EOF' > /staging/DEBIAN/postinst
#!/bin/sh
set -e
ldconfig
ln -sf /opt/llama.cpp/llama-server /usr/local/bin/llama-server
ln -sf /opt/llama.cpp/llama-cli /usr/local/bin/llama-cli
ln -sf /opt/llama.cpp/llama-bench /usr/local/bin/llama-bench
exit 0
POSTINST_EOF

RUN cat << 'PRERM_EOF' > /staging/DEBIAN/prerm
#!/bin/sh
set -e
if systemctl is-active --quiet llama-server 2>/dev/null; then
    systemctl stop llama-server 2>/dev/null || true
fi
rm -f /usr/local/bin/llama-server /usr/local/bin/llama-cli /usr/local/bin/llama-bench
exit 0
PRERM_EOF

RUN cat << 'POSTRM_EOF' > /staging/DEBIAN/postrm
#!/bin/sh
set -e
ldconfig
exit 0
POSTRM_EOF

RUN chmod 755 /staging/DEBIAN/postinst /staging/DEBIAN/prerm /staging/DEBIAN/postrm

# Build debian package
RUN PKG_VER=$(echo "${LLAMA_TAG}" | tr -d "v") && \
    dpkg-deb --build --root-owner-group /staging /dist/llama-server-cuda_${PKG_VER}_amd64.deb

# ==============================================================================
# Stage 3: Direct Exporter (Exports .deb to host via BuildKit --output)
# ==============================================================================
FROM scratch AS export-deb
COPY --from=packager /dist/*.deb /

# ==============================================================================
# Stage 4: Standalone Container Runtime Image
# ==============================================================================
FROM nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu${UBUNTU_VERSION} AS runtime

COPY --from=packager /dist/*.deb /tmp/
RUN apt-get update && \
    apt-get install -y --no-install-recommends libgomp1 /tmp/*.deb && \
    rm -rf /var/lib/apt/lists/* /tmp/*.deb

ENV HOST=0.0.0.0
ENV PORT=8080

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/llama-server"]
CMD ["--help"]
