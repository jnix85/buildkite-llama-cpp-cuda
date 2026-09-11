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
- **Systemd Service & Timers (`systemd/`)**:
  - `llama-server.service`: Headless daemon service unit packaged directly into the `.deb` (`/lib/systemd/system/llama-server.service`).
  - `llama-server.default`: Environment configuration template packaged into `/etc/default/llama-server` (conffile).
  - `llama-updater.timer` & `llama-updater.service`: Automated daily background upstream release tracker.

---

## Directory Structure

```
buildkite-llama-cpp-cuda/
├── Dockerfile                   # Multi-stage BuildKit Dockerfile (builder, packager, export-deb, runtime)
├── docker-bake.hcl              # Declarative BuildKit Bake configuration
├── .buildkite/
│   └── pipeline.yml             # Buildkite CI/CD pipeline definition
├── scripts/
│   ├── auto-update-llama.sh     # Upstream release detection & auto-upgrade script
│   ├── build-deb.sh             # Host-native Debian packaging script
│   └── download-model.sh        # GGUF model download helper for /models/
├── systemd/
│   ├── llama-server.service     # Headless inference server service unit
│   ├── llama-server-launcher.sh # Pre-flight validation & dynamic arg launcher
│   ├── llama-server.default     # Default environment configuration template (/etc/default/llama-server)
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
