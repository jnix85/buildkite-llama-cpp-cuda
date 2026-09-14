# buildkite-llama-cpp-cuda

Automated, containerized BuildKit & Buildkite CI/CD pipeline for building, packaging, and deploying CUDA-accelerated `llama.cpp` Debian packages (`.deb`) and container images.

Optimized for **Sigrun** (Intel Core i9-9900K | NVIDIA GeForce RTX 2070 Super Turing CC 7.5).

---

## Features

- **Docker BuildKit Multi-Stage Build**:
  - Compiles `llama.cpp` using NVIDIA CUDA 12 development images with Ninja and ccache caching.
  - Automatically targets Turing Compute Capability 7.5 (`-DCMAKE_CUDA_ARCHITECTURES=75`).
  - Packages binaries and modular shared libraries (`libggml-cuda.so`, `libllama.so`, `libllama-server-impl.so`) into standard Debian packages (`.deb`).
  - Uses BuildKit direct exporter (`type=local,dest=./dist`) to output `.deb` packages directly to the host filesystem without running a container.
- **Declarative BuildKit Bake (`docker-bake.hcl`)**:
  - Single command `docker buildx bake deb` to compile and export `.deb` packages.
  - Support for custom release tags (`LLAMA_TAG=b4850`).
- **Buildkite CI/CD Pipeline (`.buildkite/pipeline.yml`)**:
  - Automated build on push, release tag, or scheduled cron trigger.
  - Uploads generated `.deb` packages as pipeline artifacts.
- **Systemd Service & Timers (`systemd/`)**:
  - `llama-server.service`: Headless daemon service unit packaged directly into the `.deb` (`/lib/systemd/system/llama-server.service`).
  - `llama-server.default`: Environment configuration template packaged into `/etc/default/llama-server` (conffile).

---

## Directory Structure

```
buildkite-llama-cpp-cuda/
├── Dockerfile                   # Multi-stage BuildKit Dockerfile (builder, packager, export-deb, runtime)
├── docker-bake.hcl              # Declarative BuildKit Bake configuration
├── .buildkite/
│   └── pipeline.yml             # Buildkite CI/CD pipeline definition
├── scripts/
│   ├── build-deb.sh             # Host-native Debian packaging script
│   └── download-model.sh        # GGUF model download helper for /models/
├── systemd/
│   ├── llama-server.service     # Headless inference server service unit
│   ├── llama-server-launcher.sh # Pre-flight validation & dynamic arg launcher
│   └── llama-server.default     # Default environment configuration template (/etc/default/llama-server)
└── README.md
```

---

## Quickstart

### 1. Build Latest Debian Package Locally with BuildKit
```bash
# Build package from latest master:
docker buildx bake deb

# Or build a specific release tag (e.g., b4800):
LLAMA_TAG=b4800 docker buildx bake deb

# Or build on host from local binaries:
./scripts/build-deb.sh
```
The generated `.deb` package will be placed directly in `./dist/llama-server-cuda_<tag>_amd64.deb`.

### 2. Install the Package on Sigrun
```bash
sudo apt install -y ./dist/llama-server-cuda_*.deb
```
**What this installs:**
- Binaries in `/opt/llama.cpp/` with `/usr/local/bin` symlinks (`llama-server`, `llama-cli`, `llama-bench`).
- Dynamic shared libraries with `/etc/ld.so.conf.d/llama-cpp.conf`.
- Service launcher `/opt/llama.cpp/bin/llama-server-launcher` with pre-flight port and model checks.
- Systemd service unit in `/lib/systemd/system/llama-server.service`.
- Default environment configuration template in `/etc/default/llama-server` (binds to port 8000).
- Automatic creation of `/models/` directory with proper permissions.

### 3. Configure and Start the llama-server Service
1. **Download or place your GGUF model** in `/models/`:
```bash
# Helper script to download Qwen3.8-27B-Uncensored (~16.8 GB):
./scripts/download-model.sh
```
*(Or specify `HF_REPO="JonathanColetti/Qwen3.8-27B-Uncensored-GGUF:Q4_K_M"` in `/etc/default/llama-server` for automatic download).*

2. **Edit your configuration** (port defaults to 8000 to avoid conflicting with local Docker services):
```bash
sudo nano /etc/default/llama-server
```

3. **Enable and start the daemon**:
```bash
sudo systemctl enable --now llama-server
sudo systemctl status llama-server
```

4. **View server logs**:
```bash
journalctl -u llama-server -f -o cat
```

### 4. Build Standalone Docker Runtime Image
```bash
docker buildx bake image
```

---

## Buildkite CI Integration

In Buildkite:
1. Connect repository `git@github.com:jnix85/buildkite-llama-cpp-cuda.git`.
2. The pipeline `.buildkite/pipeline.yml` runs on the hosted queue `linux-medium` (`agents: { queue: "linux-medium" }`) and executes `docker buildx bake deb` and publishes the `.deb` file as a Buildkite artifact.
3. Schedule nightly builds or configure a webhook trigger to build upon new tags.

For a dedicated artifact-publishing pipeline, configure a second Buildkite pipeline to use `.buildkite/pipeline-artifact-upload.yml`. It builds and verifies the `.deb`, explicitly uploads it with `buildkite-agent artifact upload`, and confirms it can be downloaded from the resulting Buildkite build. Buildkite artifacts are stored against builds rather than in a separate package repository; consumers can retrieve them with `buildkite-agent artifact download`.

To run both Buildkite pipelines in sequence, configure a third pipeline to use `.buildkite/pipeline-meta.yml`. It synchronously triggers the main build pipeline first, then triggers the artifact-upload pipeline only when the first pipeline succeeds. The default pipeline slugs are `buildkite-llama-cpp-cuda` and `buildkite-llama-cpp-cuda-artifact-upload`; update `BUILD_PIPELINE_SLUG` and `ARTIFACT_PIPELINE_SLUG` in the meta pipeline if the configured slugs differ.

## GitHub Actions and Packages

The workflow `.github/workflows/build-and-publish.yml` provides the equivalent GitHub Actions flow:

- Builds the Debian package with `docker buildx bake deb`.
- Uploads the `.deb` as a 30-day GitHub Actions artifact.
- Downloads and inspects the artifact with `dpkg`.
- Builds and publishes the runtime image with `docker buildx bake image` to GitHub Container Registry (`ghcr.io/<owner>/<repository>`).

Pull requests run the build and verification jobs but do not publish packages. Pushes to `main`, `v*` tags, and manual workflow runs publish the image. The repository's Actions settings must allow `GITHUB_TOKEN` to write packages. GitHub Packages does not provide a native Debian repository, so `.deb` files are stored as workflow artifacts rather than published to GHCR.
