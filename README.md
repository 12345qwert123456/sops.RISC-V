# SOPS for RISC-V (`linux/riscv64`)

> Community-maintained build of [SOPS (Secrets OPerationS)](https://github.com/getsops/sops) — the file encryption tool — targeting the **RISC-V 64-bit** architecture.

[![Build Status](https://github.com/YOUR_ORG/sops-riscv64/actions/workflows/build.yml/badge.svg)](https://github.com/YOUR_ORG/sops-riscv64/actions/workflows/build.yml)

---

## Why does this exist?

The official SOPS project publishes binaries and container images for `linux/amd64` and `linux/arm64` only. As RISC-V hardware (SiFive boards, Milk-V Pioneer, StarFive VisionFive 2, QEMU VMs) becomes more common in server and edge deployments, a first-class riscv64 build fills that gap.

No patches to the upstream SOPS source are required — Go's native cross-compilation (`GOARCH=riscv64 CGO_ENABLED=0`) produces a fully static binary.

---

## Quick Start

### Download the pre-built binary

```bash
SOPS_VERSION=v3.12.2
curl -LO https://github.com/YOUR_ORG/sops-riscv64/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.riscv64
chmod +x sops-${SOPS_VERSION}.linux.riscv64
sudo mv sops-${SOPS_VERSION}.linux.riscv64 /usr/local/bin/sops
sops --version
```

### Use the Docker image

```bash
# Debian-based (includes gnupg, curl, vim)
docker pull ghcr.io/YOUR_ORG/sops-riscv64:v3.12.2

# Alpine-based (minimal, ~12 MB)
docker pull ghcr.io/YOUR_ORG/sops-riscv64:v3.12.2-alpine

# Run
docker run --rm \
  --platform linux/riscv64 \
  -v "$HOME/.config/sops:/root/.config/sops" \
  ghcr.io/YOUR_ORG/sops-riscv64:v3.12.2 \
  --version
```

---

## Build It Yourself

### Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| Go | ≥ 1.25.0 | Binary cross-compilation |
| Docker + BuildKit | ≥ 24.0 | Docker image builds |
| `docker buildx` | any | Multi-platform builds |
| `binfmt_misc` + QEMU | optional | Running riscv64 containers locally |

### Cross-compile a static binary

```bash
# Using the provided script
./build.sh binary

# Or manually (works on any Linux/macOS/Windows host with Go 1.25+):
CGO_ENABLED=0 GOOS=linux GOARCH=riscv64 \
  go build \
    -trimpath \
    -ldflags="-s -w" \
    -o sops \
    github.com/getsops/sops/v3/cmd/sops@v3.12.2
```

The resulting `sops` binary is a **statically-linked ELF** for `riscv64`. No shared libraries, no C runtime — copy it to any riscv64 Linux system.

### Build Docker images

```bash
# Set up a multi-platform builder (one-time)
docker buildx create --name riscv-builder --use

# Debian variant (with gnupg)
./build.sh docker

# Alpine variant (minimal)
./build.sh docker-alpine

# Everything at once
./build.sh all
```

Environment variables you can override:

```bash
SOPS_VERSION=v3.12.2 IMAGE_REPO=myregistry.io/sops OUTPUT_DIR=./dist ./build.sh all
```

---

## Image Variants

| Tag | Base | Size (approx.) | Includes |
|---|---|---|---|
| `v3.12.2` | `debian:bookworm-slim` | ~45 MB | `gnupg`, `curl`, `vim`, `ca-certificates` |
| `v3.12.2-alpine` | `alpine:3.23` | ~15 MB | `ca-certificates`, `vim` |

**Note on AWS CLI / Azure CLI:** The upstream Debian image bundles `awscli` and `azure-cli` as convenience tools for testing. These packages are **not available for `riscv64`** in Debian bookworm. They are omitted here without functional impact — SOPS communicates with AWS KMS and Azure Key Vault through its embedded Go SDKs, not through these CLI tools.

---

## Architecture & Build Details

### Why no QEMU during the build?

This project uses Docker BuildKit's `--platform=$BUILDPLATFORM` / `--platform=$TARGETPLATFORM` split:

```
CI runner (linux/amd64 or linux/arm64)
 └── Builder stage  [--platform=$BUILDPLATFORM]
       golang:1.25.9-bookworm (native, fast)
       GOOS=linux GOARCH=riscv64 CGO_ENABLED=0
       → produces static riscv64 ELF binary
 └── Runtime stage  [--platform=$TARGETPLATFORM = linux/riscv64]
       debian:bookworm-slim
       COPY binary from builder   ← no code execution in this stage
```

The Go compiler handles cross-compilation entirely. No QEMU is invoked for the compilation itself.

### Why `CGO_ENABLED=0`?

All SOPS dependencies are pure Go. Disabling CGO:
- Enables true cross-compilation without a C cross-toolchain
- Produces a fully static binary with no shared library dependencies
- Matches the upstream SOPS release build configuration

### `cloudflare/circl` on RISC-V

`circl` (used by the `ProtonMail/go-crypto` dependency chain) provides hand-written assembly for amd64, arm64, and x86. On riscv64, the Go build system automatically selects the **pure-Go fallback implementations**. No source patches are needed.

---

## Version Matrix

| This repo tag | SOPS upstream | Go toolchain |
|---|---|---|
| `v3.12.2` | `v3.12.2` | `go1.25.9` |

---

## Staying Up to Date

The GitHub Actions workflow (`/.github/workflows/build.yml`) runs on:
- Every push to `main`
- Weekly schedule (Monday 02:00 UTC) to catch upstream SOPS releases
- Manual dispatch

To update to a new SOPS release, update `SOPS_VERSION` in [`.github/workflows/build.yml`](.github/workflows/build.yml) and push.

---

## License

- **SOPS source code**: [Mozilla Public License 2.0](https://github.com/getsops/sops/blob/main/LICENSE)
- **Build scripts and Dockerfiles in this repository**: [MIT License](LICENSE)

This project is not affiliated with or endorsed by the SOPS maintainers.

---

## Contributing

Pull requests are welcome. When opening a PR, please:
1. Keep `SOPS_VERSION` pinned to a specific tag (not `main`)
2. Test with `./build.sh binary` on a machine with Go 1.25+
3. Document any upstream patches in `research-report.md`
