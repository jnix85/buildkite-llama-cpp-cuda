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
- **Automated Upstream Release Tracker (`scripts/auto-update-llama.sh`)**:
  - Automatically detects new release tags on `ggerganov/llama.cpp`.
  - Compares against the currently installed system package.
  - Compiles, packages, upgrades with `apt`, and restarts `llama-server.service` automatically.
- **Systemd Timer & Service (`systemd/`)**:
  - Automated daily background check (`llama-updater.timer`).

---

## Directory Structure

```
buildkite-llama-cpp-cuda/
├── Dockerfile                   # Multi-stage BuildKit Dockerfile (builder, packager, export-deb, runtime)
├── docker-bake.hcl              # Declarative BuildKit Bake configuration
├── .buildkite/
│   └── pipeline.yml             # Buildkite CI/CD pipeline definition
├── scripts/
│   └── auto-update-llama.sh     # Upstream release detection & auto-upgrade script
├── systemd/
│   ├── llama-updater.service    # Oneshot updater service unit
│   └── llama-updater.timer      # Daily execution timer
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
```
The generated `.deb` package will be placed directly in `./dist/llama-server-cuda_<tag>_amd64.deb`.

### 2. Install the Package on Sigrun
```bash
sudo apt install -y ./dist/llama-server-cuda_*.deb
```

### 3. Build Standalone Docker Runtime Image
```bash
docker buildx bake image
```

---

## Automated Upstream Release Tracking

### Run the Release Tracker Manually:
```bash
./scripts/auto-update-llama.sh
```

### Install the Daily Systemd Timer:
```bash
sudo cp systemd/llama-updater.* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now llama-updater.timer

# Check timer status
systemctl list-timers llama-updater.timer

# View execution logs
journalctl -u llama-updater.service -f
```

---

## Buildkite CI Integration

In Buildkite:
1. Connect repository `git@github.com:jnix85/buildkite-llama-cpp-cuda.git`.
2. The pipeline `.buildkite/pipeline.yml` runs on the hosted queue `linux-medium` (`agents: { queue: "linux-medium" }`) and executes `docker buildx bake deb` and publishes the `.deb` file as a Buildkite artifact.
3. Schedule nightly builds or configure a webhook trigger to build upon new tags.
