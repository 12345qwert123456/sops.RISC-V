# syntax=docker/dockerfile:1.7
# ============================================================
# SOPS v3.12.2 — RISC-V (linux/riscv64) Debian image
# ============================================================
# Build strategy: native Go cross-compilation via BuildKit's
# BUILDPLATFORM/TARGETPLATFORM split.
#
# The builder stage always runs on the host platform (amd64/arm64)
# with GOOS=linux GOARCH=riscv64 CGO_ENABLED=0.
# No QEMU is used during compilation.
#
# Usage (cross-build from any amd64/arm64 host):
#   docker buildx build \
#     --platform linux/riscv64 \
#     --tag ghcr.io/<owner>/sops-riscv64:v3.12.2 \
#     --file Dockerfile \
#     .
# ============================================================

ARG SOPS_VERSION=v3.12.2
ARG GO_IMAGE=golang:1.24-bookworm
ARG RUNTIME_IMAGE=ubuntu:24.04

# ── Stage 1: Builder (runs on host platform, cross-compiles for riscv64) ──────
FROM --platform=$BUILDPLATFORM ${GO_IMAGE} AS builder

ARG SOPS_VERSION
ARG TARGETOS
ARG TARGETARCH

WORKDIR /workspace

# Download source archive (no git clone needed, saves ~1 GB of history)
ADD https://github.com/getsops/sops/archive/refs/tags/${SOPS_VERSION}.tar.gz /tmp/sops.tar.gz
RUN tar -xzf /tmp/sops.tar.gz --strip-components=1 -C /workspace

# Pre-download Go module dependencies (cached layer)
RUN go mod download

# Cross-compile a fully static binary for riscv64
# CGO_ENABLED=0 → pure Go, no C toolchain required
# -trimpath   → removes local paths from binary (reproducible builds)
# -ldflags    → strips debug symbols, embeds version
RUN CGO_ENABLED=0 \
    GOOS=${TARGETOS:-linux} \
    GOARCH=${TARGETARCH:-riscv64} \
    go build \
      -trimpath \
      -ldflags="-s -w -X github.com/getsops/sops/v3/version.Version=${SOPS_VERSION}" \
      -o /workspace/sops \
      ./cmd/sops

# Smoke-check: verify the produced ELF is for riscv64
RUN readelf -h /workspace/sops | grep -q "RISC-V" || \
    (echo "ERROR: binary is not riscv64" && readelf -h /workspace/sops && exit 1)


# ── Stage 2: Runtime image (linux/riscv64) ────────────────────────────────────
FROM ${RUNTIME_IMAGE}

ARG SOPS_VERSION

# Install runtime dependencies available on riscv64 in Debian bookworm-slim.
# NOTE: awscli and azure-cli are intentionally omitted — they are not packaged
# for riscv64 in Debian bookworm, and SOPS communicates with AWS/Azure via its
# embedded Go SDKs (not via these CLI tools).
RUN apt-get update && apt-get install --no-install-recommends -y \
      ca-certificates \
      gnupg \
      curl \
      vim \
    && rm -rf /var/lib/apt/lists/*

ENV EDITOR=vim

COPY --from=builder /workspace/sops /usr/local/bin/sops

# Verify the binary executes inside the container at build time
RUN sops --version

LABEL org.opencontainers.image.title="sops" \
      org.opencontainers.image.description="SOPS: Secrets OPerationS — riscv64 community build" \
      org.opencontainers.image.version="${SOPS_VERSION}" \
      org.opencontainers.image.url="https://github.com/getsops/sops" \
      org.opencontainers.image.source="https://github.com/getsops/sops" \
      org.opencontainers.image.licenses="MPL-2.0" \
      org.opencontainers.image.architecture="riscv64"

ENTRYPOINT ["sops"]
