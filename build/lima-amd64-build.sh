#!/usr/bin/env bash
# ============================================================================
# lima-amd64-build.sh — Build Bankai Kernel inside a Lima x86_64 VM
#
# Standalone script. Manages the VM, then runs the full kernel build
# (defconfig → compile → AnyKernel3 zip) inside it. No other build scripts
# are called.
#
# Usage:
#   ./build/lima-amd64-build.sh                    # default (weebx clang)
#   ./build/lima-amd64-build.sh --clang=aosp       # AOSP Clang r547379
#   ./build/lima-amd64-build.sh --clang=weebx      # WeebX Clang 19.1.5
#   ./build/lima-amd64-build.sh --shell            # drop into VM shell
#   ./build/lima-amd64-build.sh -r|--regen         # regenerate defconfig only
#
# Environment variables (all optional):
#   TARGET_PRODUCT   — device codename (default: vili)
#   VARIANT          — qgki | qgki-debug | gki (default: qgki)
#   JOBS             — parallel make jobs (default: VM nproc)
# ============================================================================
set -euo pipefail
SECONDS=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${KERNEL_DIR}"

# ── Constants ──────────────────────────────────────────────────────────────
KERNEL_NAME="Bankai"
DEVICE="vili"
PLATFORM="lahaina"
DTB_NAME="lahaina-v2.1.dtb"
ANYKERNEL_DIR="AnyKernel3"
OUT_DIR="out"

VM_NAME="bankai-amd64"
VM_CONFIG="build/lima-amd64.yaml"

TARGET_PRODUCT="${TARGET_PRODUCT:-vili}"
VARIANT="${VARIANT:-qgki}"
JOBS="${JOBS:-}"

# ── Parse flags ────────────────────────────────────────────────────────────
CLANG_CHOICE="weebx"
SHELL_MODE=false
REGEN_MODE=false

for arg in "$@"; do
    case "${arg}" in
        --clang=*)   CLANG_CHOICE="${arg#--clang=}" ;;
        --shell)     SHELL_MODE=true ;;
        -r|--regen)  REGEN_MODE=true ;;
    esac
done

# ── Toolchain paths (inside the VM) ────────────────────────────────────────
case "${CLANG_CHOICE}" in
    aosp)
        CLANG_PATH="/opt/aosp-clang/bin"
        CLANG_LABEL="AOSP Clang r547379"
        ;;
    weebx)
        CLANG_PATH="/opt/weebx-clang/bin"
        CLANG_LABEL="WeebX Clang 19.1.5"
        ;;
    *)
        echo "[!] Unknown clang: '${CLANG_CHOICE}' (valid: aosp, weebx)"
        exit 1
        ;;
esac

echo "============================================"
echo "  VM        : ${VM_NAME} (x86_64 / QEMU)"
echo "  Toolchain : ${CLANG_LABEL}"
echo "============================================"

# ── Helper: run a command inside the VM ────────────────────────────────────
vm_run() {
    limactl shell --workdir "${KERNEL_DIR}" "${VM_NAME}" /bin/bash "$@"
}

# ── Ensure Lima is installed ───────────────────────────────────────────────
if ! command -v limactl &>/dev/null; then
    echo "[!] Lima not found. Install with:  brew install lima"
    exit 1
fi

# ── Ensure VM is created & running ─────────────────────────────────────────
if limactl list -q 2>/dev/null | grep -qx "${VM_NAME}"; then
    VM_STATUS="$(limactl list --format '{{.Name}}:{{.Status}}' 2>/dev/null \
        | grep "^${VM_NAME}:" | cut -d: -f2)"
    if [[ "${VM_STATUS}" == "Running" ]]; then
        echo "[*] Lima VM '${VM_NAME}' is already running"
    else
        echo "[*] Starting Lima VM '${VM_NAME}' …"
        limactl start "${VM_NAME}"
    fi
else
    echo "[*] Creating & starting Lima VM '${VM_NAME}' …"
    limactl create --name="${VM_NAME}" "${VM_CONFIG}"
    limactl start "${VM_NAME}"
fi

# ── Interactive shell mode ─────────────────────────────────────────────────
if ${SHELL_MODE}; then
    echo "[*] Dropping into VM shell (kernel source at ${KERNEL_DIR})"
    limactl shell --workdir "${KERNEL_DIR}" "${VM_NAME}"
    exit 0
fi

# ── Build (everything below runs inside the VM via heredoc) ────────────────
DEFCONFIG="vendor/${PLATFORM}-${VARIANT}_defconfig"
REGEN_FLAG="${REGEN_MODE}"

echo "[*] Running kernel build inside '${VM_NAME}' …"

vm_run -c "
set -euo pipefail
SECONDS=0

# ── Toolchain ──────────────────────────────────────────────────────────────
export PATH='${CLANG_PATH}':\${PATH}
if ! command -v clang &>/dev/null; then
    echo '[!] clang not found — run provision script first'
    exit 1
fi
echo \"[*] clang: \$(clang --version | head -1)\"

# ── GCC cross-compilers ───────────────────────────────────────────────────
GCC64=aarch64-linux-gnu-
if ! command -v \${GCC64}ld &>/dev/null; then
    echo '[!] aarch64 GCC cross-compiler not found'; exit 1
fi

GCC32=arm-linux-gnueabi-
if ! command -v \${GCC32}ld &>/dev/null; then
    GCC32=''; echo '[*] arm32 GCC not found (optional, continuing)'
fi

# ── Make arguments ─────────────────────────────────────────────────────────
JOBS=${JOBS:-\$(nproc --all)}
MAKE_ARGS=(
    O='${OUT_DIR}'
    ARCH=arm64
    SUBARCH=arm64
    LLVM=1
    LLVM_IAS=1
    CROSS_COMPILE=\"\${GCC64}\"
    CLANG_TRIPLE=aarch64-linux-gnu-
)
[[ -n \"\${GCC32}\" ]] && MAKE_ARGS+=(CROSS_COMPILE_ARM32=\"\${GCC32}\" CROSS_COMPILE_COMPAT=\"\${GCC32}\")

export KBUILD_BUILD_USER='Santhanabalan'
export KBUILD_BUILD_HOST='Ubuntu'
export ARCH=arm64 SUBARCH=arm64 TARGET_PRODUCT='${TARGET_PRODUCT}'

# ── Defconfig ──────────────────────────────────────────────────────────────
DEFCONFIG='${DEFCONFIG}'
mkdir -p '${OUT_DIR}'

echo '============================================'
echo '  Kernel   : ${KERNEL_NAME}'
echo '  Platform : ${PLATFORM}'
echo '  Variant  : ${VARIANT}'
echo '  Device   : ${TARGET_PRODUCT}'
echo '  Clang    : ${CLANG_CHOICE}'
echo \"  Jobs     : \${JOBS}\"
echo '  Out      : ${OUT_DIR}'
echo '============================================'

echo \"[*] Generating defconfig: \${DEFCONFIG}\"
rm -f scripts/kconfig/conf scripts/kconfig/*.o scripts/basic/fixdep 2>/dev/null || true
/bin/bash scripts/gki/generate_defconfig.sh \"\${DEFCONFIG}\"
make \"\${MAKE_ARGS[@]}\" \"\${DEFCONFIG}\"
make \"\${MAKE_ARGS[@]}\" olddefconfig

# ── Regen-only mode ───────────────────────────────────────────────────────
if [[ '${REGEN_FLAG}' == 'true' ]]; then
    cp '${OUT_DIR}/.config' 'arch/arm64/configs/'\"\${DEFCONFIG}\"
    echo \"[✓] Regenerated defconfig: arch/arm64/configs/\${DEFCONFIG}\"
    exit 0
fi

# ── Compile ────────────────────────────────────────────────────────────────
echo '[*] Building kernel Image + DTBs …'
make -j\"\${JOBS}\" \"\${MAKE_ARGS[@]}\" Image dtbs 2>&1 | tee '${OUT_DIR}/build.log'

# ── Verify ─────────────────────────────────────────────────────────────────
BOOT_DIR='${OUT_DIR}/arch/arm64/boot'
DTS_DIR=\"\${BOOT_DIR}/dts/vendor/qcom\"
IMAGE=\"\${BOOT_DIR}/Image\"
DTBO=\"\${DTS_DIR}/dtbo.img\"
DTB=\"\${DTS_DIR}/${DTB_NAME}\"

if [[ ! -f \"\${IMAGE}\" ]]; then
    echo '[✗] Build failed — no Image produced'
    tail -50 '${OUT_DIR}/build.log' 2>/dev/null; exit 1
fi
if [[ ! -f \"\${DTBO}\" ]]; then
    echo '[✗] Build failed — no dtbo.img produced'; exit 1
fi
echo \"[✓] Kernel compiled! (\$(du -h \"\${IMAGE}\" | cut -f1))\"

# ── Package AnyKernel3 zip ────────────────────────────────────────────────
TIMESTAMP=\$(date +%Y%m%d-%H%M)
ZIP_NAME='${KERNEL_NAME}-${DEVICE}'-\"\${TIMESTAMP}\".zip
STAGING='${KERNEL_DIR}/ak3-staging'

rm -rf \"\${STAGING}\"
cp -r '${ANYKERNEL_DIR}' \"\${STAGING}\"
rm -rf \"\${STAGING}/.git\" \"\${STAGING}/.github\"
cp build/anykernel.sh \"\${STAGING}/anykernel.sh\"
cp \"\${IMAGE}\" \"\${STAGING}/\"
if [[ -f \"\${DTB}\" ]]; then
    mkdir -p \"\${STAGING}/dtb\"
    cp \"\${DTB}\" \"\${STAGING}/dtb/\"
fi
cp \"\${DTBO}\" \"\${STAGING}/\"

cd \"\${STAGING}\"
zip -r9 '${KERNEL_DIR}/'\"\${ZIP_NAME}\" . -x '*.git*' 'README.md' 'LICENSE'
cd '${KERNEL_DIR}'
rm -rf \"\${STAGING}\"
rm -rf \"\${BOOT_DIR}\"

echo '========================================='
echo \"  Completed in \$((SECONDS / 60))m \$((SECONDS % 60))s\"
echo \"  Zip: \${ZIP_NAME}  (\$(du -h \"\${ZIP_NAME}\" | cut -f1))\"
echo \"  Version: \$(make -s \"\${MAKE_ARGS[@]}\" kernelrelease)\"
echo '========================================='
"

# ── Host-side: exit early for regen ────────────────────────────────────────
if ${REGEN_MODE}; then
    echo "[✓] Defconfig regenerated"
    exit 0
fi

# ── Host-side: verify zip ──────────────────────────────────────────────────
LATEST_ZIP="$(ls -t ${KERNEL_NAME}-${DEVICE}-*.zip 2>/dev/null | head -1 || true)"

if [[ -z "${LATEST_ZIP}" || ! -s "${LATEST_ZIP}" ]]; then
    echo "[✗] Build failed — no flashable zip found"
    exit 1
fi

echo "========================================="
echo "  VM        : ${VM_NAME} (x86_64 / QEMU)"
echo "  Toolchain : ${CLANG_LABEL}"
echo "  Total     : $((SECONDS / 60))m $((SECONDS % 60))s"
echo "  Zip       : ${LATEST_ZIP}  ($(du -h "${LATEST_ZIP}" | cut -f1))"
echo "========================================="
