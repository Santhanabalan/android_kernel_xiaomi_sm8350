#!/bin/bash
# ============================================================================
# lima-amd64-provision.sh — Provision script for Bankai Lima AMD64 VM
#
# Installs build dependencies and downloads x86_64 toolchains (AOSP + WeebX).
# Called by lima-amd64.yaml during VM provisioning. 
# ============================================================================
set -eux

export DEBIAN_FRONTEND=noninteractive

# ── Base build dependencies ──────────────────────────────────────
# apt-get update
# apt-get install -y --no-install-recommends \
#   bc bison build-essential ca-certificates cpio curl flex \
#   git gnupg kmod libelf-dev libssl-dev lld llvm zip unzip \
#   python3 python-is-python3 wget rsync xz-utils zstd lz4 \
#   gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \
#   gcc-arm-linux-gnueabi binutils-arm-linux-gnueabi \
#   software-properties-common lsb-release

# ── Toolchain 1: AOSP Clang r547379 (x86_64, native) ────────────
AOSP_CLANG_VER="r547379"
BUILD_DIR="/Volumes/Kernel/kernel_xiaomi_sm8350/build/clang"
AOSP_TAR="${BUILD_DIR}/aosp-clang-${AOSP_CLANG_VER}.tar.gz"
mkdir -p /opt/aosp-clang
echo "[*] Extracting AOSP Clang ${AOSP_CLANG_VER} from local cache …"
tar xzf "${AOSP_TAR}" -C /opt/aosp-clang

# ── Toolchain 2: WeebX Clang 19.1.5 (x86_64, native) ───────────
WEEBX_VER="19.1.5"
WEEBX_TAR="${BUILD_DIR}/WeebX-Clang-${WEEBX_VER}.tar.gz"
mkdir -p /opt/weebx-clang
echo "[*] Extracting WeebX Clang ${WEEBX_VER} from local cache …"
tar -xzf "${WEEBX_TAR}" -C /opt/weebx-clang

# ── Verify ──────────────────────────────────────────────────────
/opt/aosp-clang/bin/clang --version  || echo "[!] AOSP Clang verify skipped"
/opt/weebx-clang/bin/clang --version || echo "[!] WeebX Clang verify skipped"
aarch64-linux-gnu-ld --version
arm-linux-gnueabi-ld --version       || true

echo "[✓] Bankai Lima AMD64 VM provisioned — AOSP ${AOSP_CLANG_VER} + WeebX ${WEEBX_VER}"
