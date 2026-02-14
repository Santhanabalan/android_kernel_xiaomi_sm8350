#!/usr/bin/env bash
# ============================================================================
# build.sh — Build script for Bankai Kernel (Xiaomi 11T Pro / vili / lahaina)
#
# Usage:
#   bash build/build.sh              # full build (defconfig + compile + zip)
#   bash build/build.sh -r|--regen   # regenerate defconfig only
#
# Environment variables (all optional — sane defaults provided):
#   TARGET_PRODUCT   — device codename fragment config (default: vili)
#   VARIANT          — qgki | qgki-debug | gki  (default: qgki)
#   JOBS             — parallel make jobs        (default: $(nproc))
#   OUT_DIR          — build output directory     (default: out)
# ============================================================================
set -euo pipefail
SECONDS=0

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

# ── Toolchain discovery ────────────────────────────────────────────────────
# CLANG_PREFIX can point to a toolchain's bin/ dir (e.g. /opt/weebx-clang/bin).
# We set CC/HOSTCC explicitly rather than modifying PATH, so that system
# binutils (as, ld) aren't shadowed by the toolchain's bundled copies.
if [[ -n "${CLANG_PREFIX:-}" && -x "${CLANG_PREFIX}/clang" ]]; then
    CLANG_BIN="${CLANG_PREFIX}/clang"
    echo "[*] Using clang: $(${CLANG_BIN} --version | head -1)"
elif command -v clang &>/dev/null; then
    CLANG_BIN="$(command -v clang)"
    CLANG_PREFIX=""
    echo "[*] Using clang: $(clang --version | head -1)"
else
    echo "[!] clang not found — aborting"
    exit 1
fi

# GCC cross-compilers (needed by kernel vDSO / compat builds)
if command -v aarch64-linux-android-ld &>/dev/null; then
    GCC64_PREFIX=aarch64-linux-android-
elif command -v aarch64-linux-gnu-ld &>/dev/null; then
    GCC64_PREFIX=aarch64-linux-gnu-
else
    echo "[!] No aarch64 GCC cross-compiler found"
    exit 1
fi

if command -v arm-linux-androideabi-ld &>/dev/null; then
    GCC32_PREFIX=arm-linux-androideabi-
elif command -v arm-linux-gnueabi-ld &>/dev/null; then
    GCC32_PREFIX=arm-linux-gnueabi-
else
    GCC32_PREFIX=""
    echo "[*] No arm32 GCC found (optional, continuing)"
fi

# ── Make arguments ──────────────────────────────────────────────────────────
# HOSTCC must always be the native (arm64) system compiler — host tools like
# fixdep/conf run on the build machine, not the target device.
# CC is the selected toolchain clang for cross-compiling the kernel itself.
HOSTCC_BIN="$(command -v clang-20 2>/dev/null || command -v clang)"

MAKE_ARGS=(
    O="${OUT_DIR}"
    ARCH="${ARCH}"
    SUBARCH="${SUBARCH}"
    LLVM=1
    LLVM_IAS=1
    CC="${CLANG_BIN}"
    HOSTCC="${HOSTCC_BIN}"
    CROSS_COMPILE="${GCC64_PREFIX}"
    CLANG_TRIPLE=aarch64-linux-gnu-
)

# If using a non-system toolchain, set AR/NM etc. to its LLVM copies.
# LD stays as the system ld.lld (native arm64, supports aarch64 erratum flags).
if [[ -n "${CLANG_PREFIX:-}" ]]; then
    MAKE_ARGS+=(
        AR="${CLANG_PREFIX}/llvm-ar"
        NM="${CLANG_PREFIX}/llvm-nm"
        STRIP="${CLANG_PREFIX}/llvm-strip"
        OBJCOPY="${CLANG_PREFIX}/llvm-objcopy"
        OBJDUMP="${CLANG_PREFIX}/llvm-objdump"
        READELF="${CLANG_PREFIX}/llvm-readelf"
    )
fi

[[ -n "${GCC32_PREFIX}" ]] && MAKE_ARGS+=(CROSS_COMPILE_ARM32="${GCC32_PREFIX}" CROSS_COMPILE_COMPAT="${GCC32_PREFIX}")

# ── Kernel build identity (shown in /proc/version & kernel managers) ────────
export KBUILD_BUILD_USER="Santhanabalan"
export KBUILD_BUILD_HOST="Bankai"

export ARCH SUBARCH TARGET_PRODUCT

# ── Generate defconfig (mirrors Qualcomm's GKI build system) ────────────────
DEFCONFIG="vendor/${PLATFORM}-${VARIANT}_defconfig"

mkdir -p "${OUT_DIR}"

echo "============================================"
echo "  Kernel   : ${KERNEL_NAME}"
echo "  Platform : ${PLATFORM}"
echo "  Variant  : ${VARIANT}"
echo "  Device   : ${TARGET_PRODUCT}"
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
echo "  Version: $(make -s "${MAKE_ARGS[@]}" kernelrelease)"
echo "========================================="
