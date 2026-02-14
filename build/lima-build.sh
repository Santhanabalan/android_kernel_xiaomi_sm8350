#!/usr/bin/env bash
# ============================================================================
# lima-build.sh — Build Bankai Kernel inside a Lima VM & produce AnyKernel3 zip
#
# Usage:
#   bash build/lima-build.sh                    # default (weebx)
#   bash build/lima-build.sh --clang=weebx      # WeebX Clang 19.1.5 (x86_64 via Rosetta)
#   bash build/lima-build.sh --clang=aosp       # AOSP Clang r522817 (+pgo +bolt +lto)
#   bash build/lima-build.sh --clang=upstream   # Upstream LLVM/Clang 20 (native arm64)
#   bash build/lima-build.sh --shell            # drop into VM shell
#   bash build/lima-build.sh -r|--regen         # regenerate defconfig only
#
# Environment variables (all optional):
#   TARGET_PRODUCT   — device codename (default: vili)
#   VARIANT          — qgki | qgki-debug | gki (default: qgki)
#   JOBS             — parallel make jobs (default: VM auto-detects via nproc)
# ============================================================================
set -euo pipefail
SECONDS=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${KERNEL_DIR}"

KERNEL_NAME="Bankai"
DEVICE="vili"
VM_NAME="bankai"
VM_CONFIG="build/lima.yaml"

# ── Parse flags ─────────────────────────────────────────────────────────────
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

# ── Map clang choice → PATH prefix + label ─────────────────────────────────
# NOTE: We prepend the toolchain bin/ to PATH explicitly inside the VM shell.
#       Nothing goes in /etc/profile.d/ to avoid all-toolchains-on-PATH leaks.
case "${CLANG_CHOICE}" in
    aosp)
        CLANG_PATH_PREFIX="/opt/aosp-clang/bin"
        VARIANT_LABEL="AOSP Clang r522817 (+pgo +bolt +lto +mlgo)"
        ;;
    weebx)
        CLANG_PATH_PREFIX="/opt/weebx-clang/bin"
        VARIANT_LABEL="WeebX Clang 19.1.5"
        ;;
    upstream)
        CLANG_PATH_PREFIX=""  # upstream is default on PATH via update-alternatives
        VARIANT_LABEL="Upstream LLVM/Clang 20 (native arm64)"
        ;;
    *)
        echo "[!] Unknown clang: '${CLANG_CHOICE}'"
        echo "    Valid options: upstream, aosp, weebx"
        exit 1
        ;;
esac

echo "============================================"
echo "  Toolchain: ${VARIANT_LABEL}"
echo "============================================"

# ── Ensure Lima is installed ───────────────────────────────────────────────
if ! command -v limactl &>/dev/null; then
    echo "[!] Lima not found. Install with:"
    echo "    brew install lima"
    exit 1
fi

# ── Ensure VM is created & running ─────────────────────────────────────────
if limactl list -q 2>/dev/null | grep -qx "${VM_NAME}"; then
    # VM exists — check if it's running
    VM_STATUS="$(limactl list --format '{{.Name}}:{{.Status}}' 2>/dev/null | grep "^${VM_NAME}:" | cut -d: -f2)"
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
    echo "[*] Dropping into VM shell — kernel source at ${KERNEL_DIR}"
    limactl shell --workdir "${KERNEL_DIR}" "${VM_NAME}"
    exit 0
fi

# ── Build inside the VM ───────────────────────────────────────────────────
# The kernel source dir is mounted writable via /Volumes — build in-place.

BUILD_ARGS=""
if ${REGEN_MODE}; then
    BUILD_ARGS="--regen"
fi

echo "[*] Running kernel build inside '${VM_NAME}' …"
limactl shell --workdir "${KERNEL_DIR}" "${VM_NAME}" -- bash -c "
    export CLANG_PREFIX='${CLANG_PATH_PREFIX}'
    export TARGET_PRODUCT='${TARGET_PRODUCT:-vili}'
    export VARIANT='${VARIANT:-qgki}'
    ${JOBS:+export JOBS='${JOBS}'}

    bash build/build.sh ${BUILD_ARGS}
"

# ── Exit early for regen mode ─────────────────────────────────────────────
if ${REGEN_MODE}; then
    echo "[✓] Defconfig regenerated"
    exit 0
fi

# ── Verify artifacts ───────────────────────────────────────────────────────
# build.sh already verifies, packages the AnyKernel3 zip, and cleans up
# boot artifacts — so we just check the exit code (set -e) and look for
# the produced zip on the host.

ZIP_PATTERN="${KERNEL_NAME}-${DEVICE}-*.zip"
LATEST_ZIP="$(ls -t "${ZIP_PATTERN}" 2>/dev/null | head -1 || true)"

if [[ -z "${LATEST_ZIP}" || ! -s "${LATEST_ZIP}" ]]; then
    echo "[✗] Build failed — no flashable zip found"
    exit 1
fi

# ── Summary ────────────────────────────────────────────────────────────────
echo "========================================="
echo "  Toolchain: ${VARIANT_LABEL}"
echo "  Completed in $((SECONDS / 60))m $((SECONDS % 60))s"
echo "  Zip: ${LATEST_ZIP}  ($(du -h "${LATEST_ZIP}" | cut -f1))"
echo "========================================="
