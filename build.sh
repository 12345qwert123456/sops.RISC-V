#!/usr/bin/env bash
# =============================================================================
# build.sh — Build SOPS for RISC-V (linux/riscv64)
# =============================================================================
# Supports three modes:
#   ./build.sh binary        → cross-compile a static riscv64 binary locally
#   ./build.sh docker        → build Debian-based Docker image for riscv64
#   ./build.sh docker-alpine → build Alpine-based Docker image for riscv64
#   ./build.sh all           → binary + both Docker images
#
# Requirements for 'binary' mode:
#   - Go 1.25+ installed and in PATH
#
# Requirements for 'docker' / 'docker-alpine' mode:
#   - Docker with BuildKit + buildx
#   - docker buildx create --use  (or a binfmt_misc-enabled host)
#   - Network access to download source from GitHub
# =============================================================================

set -euo pipefail

SOPS_VERSION="${SOPS_VERSION:-v3.12.2}"
IMAGE_REPO="${IMAGE_REPO:-ghcr.io/YOUR_ORG/sops-riscv64}"
OUTPUT_DIR="${OUTPUT_DIR:-./dist}"

# ── Helpers ───────────────────────────────────────────────────────────────────

log()  { echo "[build.sh] $*"; }
die()  { echo "[build.sh] ERROR: $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" &>/dev/null || die "'$1' not found in PATH — please install it"
}

# ── Mode: binary ──────────────────────────────────────────────────────────────

build_binary() {
  require_cmd go

  local go_version
  go_version=$(go version | awk '{print $3}' | sed 's/go//')
  log "Using Go ${go_version}"

  # Enforce minimum Go version 1.25
  local major minor
  IFS='.' read -r major minor _ <<< "${go_version}"
  if [[ "${major}" -lt 1 ]] || { [[ "${major}" -eq 1 ]] && [[ "${minor}" -lt 25 ]]; }; then
    die "Go 1.25+ required (found ${go_version})"
  fi

  log "Downloading SOPS ${SOPS_VERSION} source..."
  local src_dir
  src_dir=$(mktemp -d)
  trap 'rm -rf "${src_dir}"' EXIT

  curl -fsSL \
    "https://github.com/getsops/sops/archive/refs/tags/${SOPS_VERSION}.tar.gz" \
    | tar -xz --strip-components=1 -C "${src_dir}"

  log "Downloading Go module dependencies..."
  (cd "${src_dir}" && go mod download)

  mkdir -p "${OUTPUT_DIR}"
  local out="${OUTPUT_DIR}/sops-${SOPS_VERSION}.linux.riscv64"

  log "Cross-compiling SOPS ${SOPS_VERSION} for linux/riscv64..."
  (
    cd "${src_dir}"
    CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=riscv64 \
    go build \
      -trimpath \
      -ldflags="-s -w -X github.com/getsops/sops/v3/version.Version=${SOPS_VERSION}" \
      -o "${OLDPWD}/${out}" \
      ./cmd/sops
  )

  log "Verifying binary architecture..."
  if command -v file &>/dev/null; then
    file "${out}"
    file "${out}" | grep -q "RISC-V" \
      || die "Produced binary does not appear to be riscv64 — check your Go toolchain"
  fi

  local sha256
  if command -v sha256sum &>/dev/null; then
    sha256=$(sha256sum "${out}" | awk '{print $1}')
  elif command -v shasum &>/dev/null; then
    sha256=$(shasum -a 256 "${out}" | awk '{print $1}')
  fi

  log "Binary written to: ${out}"
  [[ -n "${sha256:-}" ]] && log "SHA256: ${sha256}"
  log "Size: $(du -sh "${out}" | awk '{print $1}')"
}

# ── Mode: docker ──────────────────────────────────────────────────────────────

build_docker() {
  local dockerfile="${1:-Dockerfile}"
  local tag_suffix="${2:-}"
  require_cmd docker

  # Ensure buildx is available
  docker buildx version &>/dev/null || die "docker buildx not available — install Docker 19.03+ with BuildKit"

  local tag="${IMAGE_REPO}:${SOPS_VERSION}${tag_suffix}"
  local latest_tag="${IMAGE_REPO}:latest${tag_suffix}"

  log "Building Docker image: ${tag}"
  log "  Platform : linux/riscv64"
  log "  Dockerfile: ${dockerfile}"

  docker buildx build \
    --platform linux/riscv64 \
    --build-arg SOPS_VERSION="${SOPS_VERSION}" \
    --tag "${tag}" \
    --tag "${latest_tag}" \
    --file "${dockerfile}" \
    --load \
    .

  log "Image built: ${tag}"
  log ""
  log "To test (requires QEMU binfmt_misc for riscv64):"
  log "  docker run --rm --platform linux/riscv64 ${tag} --version"
  log ""
  log "To push:"
  log "  docker push ${tag}"
  log "  docker push ${latest_tag}"
}

# ── Main ──────────────────────────────────────────────────────────────────────

MODE="${1:-binary}"

case "${MODE}" in
  binary)
    build_binary
    ;;
  docker)
    build_docker "Dockerfile" ""
    ;;
  docker-alpine)
    build_docker "Dockerfile.alpine" "-alpine"
    ;;
  all)
    build_binary
    build_docker "Dockerfile" ""
    build_docker "Dockerfile.alpine" "-alpine"
    ;;
  *)
    echo "Usage: $0 [binary|docker|docker-alpine|all]"
    echo "  binary        — cross-compile riscv64 static binary (requires Go 1.25+)"
    echo "  docker        — build Debian-based riscv64 Docker image"
    echo "  docker-alpine — build Alpine-based riscv64 Docker image"
    echo "  all           — all of the above"
    echo ""
    echo "Environment variables:"
    echo "  SOPS_VERSION  (default: v3.12.2)"
    echo "  IMAGE_REPO    (default: ghcr.io/YOUR_ORG/sops-riscv64)"
    echo "  OUTPUT_DIR    (default: ./dist)"
    exit 1
    ;;
esac
