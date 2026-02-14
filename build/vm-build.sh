#!/usr/bin/env bash
# ============================================================================
# build.sh — Build script for Bankai Kernel (Xiaomi 11T Pro / vili / lahaina)
#
# Intended to run inside an Ubuntu VM with AOSP or WeebX Clang toolchain.
#
# Usage:
#   bash build/build.sh              # full build (defconfig + compile + zip)
#   bash build/build.sh -r|--regen   # regenerate defconfig only
#   bash build/build.sh -s|--setup   # install build prerequisites (Ubuntu)
#
# Environment variables (all optional — sane defaults provided):
#   TARGET_PRODUCT   — device codename fragment config (default: vili)
#   VARIANT          — qgki | qgki-debug | gki  (default: qgki)
#   CLANG_VARIANT    — aosp | weebx              (default: aosp)
#   JOBS             — parallel make jobs        (default: $(nproc))
#   OUT_DIR          — build output directory     (default: out)
# ============================================================================
set -euo pipefail
SECONDS=0

# ── Install prerequisites ───────────────────────────────────────────────────
install_prerequisites() {
    echo "[*] Installing build prerequisites …"

    if ! command -v apt-get &>/dev/null; then
        echo "[!] apt-get not found — this flag is for Ubuntu/Debian only"
        exit 1
    fi

    sudo apt-get update -qq

    # Core build tools
    sudo apt-get install -y --no-install-recommends \
        bc bison build-essential ca-certificates cpio curl \
        flex git gnupg kmod libelf-dev libssl-dev lz4 \
        python3 python-is-python3 zip unzip wget \
        software-properties-common

    # GCC cross-compilers (needed for vDSO / compat builds)
    sudo apt-get install -y --no-install-recommends \
        gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \
        gcc-arm-linux-gnueabi binutils-arm-linux-gnueabi

    # ── AOSP Clang prebuilt ──
    local _aosp_ver="r547379"
    local _aosp_dir="${HOME}/toolchains/clang-${_aosp_ver}"
    local _aosp_url="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/clang-${_aosp_ver}.tar.gz"

    if [[ ! -d "${_aosp_dir}" ]]; then
        echo "[*] Downloading AOSP Clang ${_aosp_ver} …"
        mkdir -p "${_aosp_dir}"
        curl -fsSL "${_aosp_url}" | tar xz -C "${_aosp_dir}"
    fi

    # ── WeebX Clang prebuilt ──
    local _weebx_ver="19.1.5"
    local _weebx_dir="${HOME}/toolchains/weebx-clang-${_weebx_ver}"
    local _weebx_url="https://github.com/XSans0/WeebX-Clang/releases/download/WeebX-Clang-${_weebx_ver}-release/WeebX-Clang-${_weebx_ver}.tar.gz"

    if [[ ! -d "${_weebx_dir}" ]]; then
        echo "[*] Downloading WeebX Clang ${_weebx_ver} …"
        mkdir -p "${_weebx_dir}"
        wget -q --show-progress "${_weebx_url}" -O /tmp/weebx-clang.tar.gz
        tar -xzf /tmp/weebx-clang.tar.gz -C "${_weebx_dir}"
        rm -f /tmp/weebx-clang.tar.gz
    fi

    echo "[✓] All prerequisites installed"
    echo "    AOSP clang : $("${_aosp_dir}/bin/clang" --version 2>/dev/null | head -1)"
    echo "    WeebX clang: $("${_weebx_dir}/bin/clang" --version 2>/dev/null | head -1)"
    echo "    aarch64    : $(aarch64-linux-gnu-ld --version 2>/dev/null | head -1)"
    echo "    arm32      : $(arm-linux-gnueabi-ld --version 2>/dev/null | head -1)"
    exit 0
}

if [[ "${1:-}" == "-s" || "${1:-}" == "--setup" ]]; then
    install_prerequisites
fi

# ── Paths ───────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${KERNEL_DIR}"

# ── Tunables ────────────────────────────────────────────────────────────────
ARCH=arm64
SUBARCH=arm64
TARGET_PRODUCT="${TARGET_PRODUCT:-vili}"
VARIANT="${VARIANT:-qgki}"
PLATFORM=lahaina
JOBS="${JOBS:-$(nproc --all)}"
OUT_DIR="${OUT_DIR:-out}"
KERNEL_NAME="Bankai"
DEVICE="vili"
ANYKERNEL_DIR="AnyKernel3"

# DTB to include in the flashable zip (lahaina v2.1 for vili)
DTB_NAME="lahaina-v2.1.dtb"

# ── Toolchain ──────────────────────────────────────────────────────────────
# Select toolchain via CLANG_VARIANT: "aosp" (default) or "weebx".
# Both are downloaded during --setup and cached under ~/toolchains.
# LLVM=1 tells kbuild to use clang/lld/llvm-* for everything.
CLANG_VARIANT="${CLANG_VARIANT:-aosp}"

AOSP_CLANG_VER="r547379"
AOSP_CLANG_DIR="${HOME}/toolchains/clang-${AOSP_CLANG_VER}"

WEEBX_CLANG_VER="19.1.5"
WEEBX_CLANG_DIR="${HOME}/toolchains/weebx-clang-${WEEBX_CLANG_VER}"

case "${CLANG_VARIANT}" in
    aosp)  CLANG_DIR="${AOSP_CLANG_DIR}" ;;
    weebx) CLANG_DIR="${WEEBX_CLANG_DIR}" ;;
    *)
        echo "[!] Unknown CLANG_VARIANT='${CLANG_VARIANT}' — use 'aosp' or 'weebx'"
        exit 1
        ;;
esac

if [[ ! -d "${CLANG_DIR}/bin" ]]; then
    echo "[!] Toolchain not found at ${CLANG_DIR} — run 'bash build/vm-build.sh --setup' first"
    exit 1
fi

export PATH="${CLANG_DIR}/bin:${PATH}"

if ! command -v clang &>/dev/null; then
    echo "[!] clang not found after adding toolchain to PATH — aborting"
    exit 1
fi
echo "[*] Using clang (${CLANG_VARIANT}): $(clang --version | head -1)"

# GCC cross-compilers (needed by kernel vDSO / compat builds)
if command -v aarch64-linux-gnu-ld &>/dev/null; then
    GCC64_PREFIX=aarch64-linux-gnu-
else
    echo "[!] No aarch64 GCC cross-compiler found"
    exit 1
fi

if command -v arm-linux-gnueabi-ld &>/dev/null; then
    GCC32_PREFIX=arm-linux-gnueabi-
else
    GCC32_PREFIX=""
    echo "[*] No arm32 GCC found (optional, continuing)"
fi

# ── Make arguments ──────────────────────────────────────────────────────────
MAKE_ARGS=(
    O="${OUT_DIR}"
    ARCH="${ARCH}"
    SUBARCH="${SUBARCH}"
    LLVM=1
    LLVM_IAS=1
    CROSS_COMPILE="${GCC64_PREFIX}"
    CLANG_TRIPLE=aarch64-linux-gnu-
)

[[ -n "${GCC32_PREFIX}" ]] && MAKE_ARGS+=(CROSS_COMPILE_ARM32="${GCC32_PREFIX}" CROSS_COMPILE_COMPAT="${GCC32_PREFIX}")

# ── Kernel build identity (shown in /proc/version & kernel managers) ────────
export KBUILD_BUILD_USER="Santhanabalan"
export KBUILD_BUILD_HOST="Ubuntu"

export ARCH SUBARCH TARGET_PRODUCT

# ── Generate defconfig (mirrors Qualcomm's GKI build system) ────────────────
DEFCONFIG="vendor/${PLATFORM}-${VARIANT}_defconfig"

mkdir -p "${OUT_DIR}"

echo "============================================"
echo "  Kernel   : ${KERNEL_NAME}"
echo "  Platform : ${PLATFORM}"
echo "  Variant  : ${VARIANT}"
echo "  Device   : ${TARGET_PRODUCT}"
echo "  Clang    : ${CLANG_VARIANT}"
echo "  Jobs     : ${JOBS}"
echo "  Out      : ${OUT_DIR}"
echo "============================================"

echo "[*] Generating defconfig: ${DEFCONFIG}"
# Clean stale host-built kconfig tools (may lack execute permission in Lima/VM)
rm -f scripts/kconfig/conf scripts/kconfig/*.o scripts/basic/fixdep 2>/dev/null || true

# Use the kernel's own generate_defconfig.sh so all QGKI / GKI / Xiaomi
# config fragments are merged exactly as the OEM intended.
bash scripts/gki/generate_defconfig.sh "${DEFCONFIG}"

# The script drops the merged defconfig into arch/arm64/configs/vendor/
# Now apply it via make.
make "${MAKE_ARGS[@]}" "${DEFCONFIG}"
make "${MAKE_ARGS[@]}" olddefconfig

# ── Regen mode ──────────────────────────────────────────────────────────────
if [[ "${1:-}" == "-r" || "${1:-}" == "--regen" ]]; then
    cp "${OUT_DIR}/.config" "arch/${ARCH}/configs/${DEFCONFIG}"
    echo "[✓] Regenerated defconfig: arch/${ARCH}/configs/${DEFCONFIG}"
    exit 0
fi

# ── Build ───────────────────────────────────────────────────────────────────
echo "[*] Building kernel Image + DTBs …"

make -j"${JOBS}" "${MAKE_ARGS[@]}" Image dtbs 2>&1 | tee "${OUT_DIR}/build.log"

# ── Verify output ──────────────────────────────────────────────────────────
BOOT_DIR="${OUT_DIR}/arch/${ARCH}/boot"
DTS_DIR="${BOOT_DIR}/dts/vendor/qcom"
IMAGE="${BOOT_DIR}/Image"
DTBO="${DTS_DIR}/dtbo.img"
DTB="${DTS_DIR}/${DTB_NAME}"

if [[ ! -f "${IMAGE}" ]]; then
    echo "[✗] Build failed — no Image produced"
    tail -50 "${OUT_DIR}/build.log" 2>/dev/null
    exit 1
fi

if [[ ! -f "${DTBO}" ]]; then
    echo "[✗] Build failed — no dtbo.img produced"
    exit 1
fi

echo "[✓] Kernel compiled successfully! ($(du -h "${IMAGE}" | cut -f1))"

# ── Package AnyKernel3 zip ─────────────────────────────────────────────────
echo "[*] Zipping up …"

TIMESTAMP=$(date +%Y%m%d-%H%M)
ZIP_NAME="${KERNEL_NAME}-${DEVICE}-${TIMESTAMP}.zip"
STAGING="${KERNEL_DIR}/ak3-staging"

rm -rf "${STAGING}"
cp -r "${ANYKERNEL_DIR}" "${STAGING}"
rm -rf "${STAGING}/.git" "${STAGING}/.github"

# Custom anykernel.sh
cp build/anykernel.sh "${STAGING}/anykernel.sh"

# Kernel Image
cp "${IMAGE}" "${STAGING}/"

# DTB
if [[ -f "${DTB}" ]]; then
    mkdir -p "${STAGING}/dtb"
    cp "${DTB}" "${STAGING}/dtb/"
fi

# DTBO
cp "${DTBO}" "${STAGING}/"

cd "${STAGING}"
zip -r9 "${KERNEL_DIR}/${ZIP_NAME}" . -x '*.git*' 'README.md' 'LICENSE'
cd "${KERNEL_DIR}"
rm -rf "${STAGING}"

# ── Cleanup boot artifacts for next build ──────────────────────────────────
rm -rf "${BOOT_DIR}"

# ── Summary ─────────────────────────────────────────────────────────────────
echo "========================================="
echo "  Completed in $((SECONDS / 60))m $((SECONDS % 60))s"
echo "  Zip: ${ZIP_NAME}  ($(du -h "${ZIP_NAME}" | cut -f1))"
echo "========================================="
echo "  Version: $(make -s "${MAKE_ARGS[@]}" kernelrelease)"
echo "========================================="
