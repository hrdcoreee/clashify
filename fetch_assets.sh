#!/usr/bin/env bash
# fetch_assets.sh - Download upstream Mihomo binary and Web UI for iOS 14 package
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="${SCRIPT_DIR}/pkg_root"
BIN_DIR="${PKG_ROOT}/usr/local/bin"
UI_DIR="${PKG_ROOT}/var/mobile/Library/Mihomo/ui"

MIHOMO_TAG="v1.18.10"
MIHOMO_URL="https://github.com/MetaCubeX/mihomo/releases/download/${MIHOMO_TAG}/mihomo-darwin-arm64-${MIHOMO_TAG}.gz"
ZASHBOARD_URL="https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip"

echo "[*] Initializing asset fetch..."
mkdir -p "${BIN_DIR}" "${UI_DIR}"

# Create isolated temporary workspace for downloads
TMP_WORK="$(mktemp -d -t mihomo_fetch_XXXXXX)"
cleanup() {
    echo "[*] Cleaning temporary files..."
    rm -rf "${TMP_WORK}"
}
trap cleanup EXIT

# 1. Fetch Mihomo Darwin arm64 binary
echo "[*] Downloading Mihomo ${MIHOMO_TAG} (darwin-arm64)..."
MIHOMO_TMP_DIR="${TMP_WORK}/mihomo_dl"
mkdir -p "${MIHOMO_TMP_DIR}"

curl -fSL --retry 3 "${MIHOMO_URL}" -o "${MIHOMO_TMP_DIR}/mihomo.gz"

echo "[*] Extracting Mihomo binary to ${BIN_DIR}/mihomo..."
gzip -dc "${MIHOMO_TMP_DIR}/mihomo.gz" > "${BIN_DIR}/mihomo"
chmod 755 "${BIN_DIR}/mihomo"

# Patch Mach-O platform from macOS to iOS and ad-hoc sign with entitlements
echo "[*] Patching Mach-O platform (macOS -> iOS 14) and ad-hoc signing..."
python3 "${SCRIPT_DIR}/patch_macho.py" "${BIN_DIR}/mihomo" "${SCRIPT_DIR}/entitlements.xml"

# Quick verification of Mach-O binary
if file "${BIN_DIR}/mihomo" 2>/dev/null; then
    file "${BIN_DIR}/mihomo"
fi

# 2. Fetch Zashboard Web UI
echo "[*] Fetching latest Zashboard Web UI (dist.zip)..."
UI_TMP_DIR="${TMP_WORK}/ui_dl"
mkdir -p "${UI_TMP_DIR}"

curl -fSL --retry 3 "${ZASHBOARD_URL}" -o "${UI_TMP_DIR}/dist.zip"

echo "[*] Extracting Zashboard to ${UI_DIR}..."
rm -rf "${UI_DIR:?}"/*
unzip -q -o "${UI_TMP_DIR}/dist.zip" -d "${UI_TMP_DIR}/extracted"

# Handle root or nested dist structure
if [ -d "${UI_TMP_DIR}/extracted/dist" ]; then
    cp -r "${UI_TMP_DIR}/extracted/dist/"* "${UI_DIR}/"
else
    cp -r "${UI_TMP_DIR}/extracted/"* "${UI_DIR}/"
fi

# Verify WebUI
if [ -f "${UI_DIR}/index.html" ]; then
    echo "[+] Zashboard Web UI installed successfully: $(du -sh "${UI_DIR}" | cut -f1)"
else
    echo "[-] Error: index.html not found in ${UI_DIR}" >&2
    exit 1
fi

echo "[+] All upstream assets fetched successfully!"
