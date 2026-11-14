#!/usr/bin/env bash
# build_deb.sh - Build com.hrdcoreee.clashify debian package for iOS 14
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="${SCRIPT_DIR}/pkg_root"
OUTPUT_DEB="${SCRIPT_DIR}/com.hrdcoreee.clashify_1.0.0_iphoneos-arm.deb"

echo "=========================================================="
echo " Building iOS 14 Rootful Jailbreak Package: Clashify      "
echo "=========================================================="

# 1. Verify required artifacts
if [ ! -f "${PKG_ROOT}/usr/local/bin/mihomo" ]; then
    echo "[-] Error: ${PKG_ROOT}/usr/local/bin/mihomo not found!" >&2
    echo "[-] Please run ./fetch_assets.sh first." >&2
    exit 1
fi

if [ ! -f "${PKG_ROOT}/var/mobile/Library/Mihomo/ui/index.html" ]; then
    echo "[-] Error: WebUI assets not found in ${PKG_ROOT}/var/mobile/Library/Mihomo/ui/!" >&2
    echo "[-] Please run ./fetch_assets.sh first." >&2
    exit 1
fi

# Ensure Mach-O binary targets iOS (platform 2) and is ad-hoc signed
echo "[*] Patching Mach-O binary for iOS (platform 2) and updating Page 0 CodeDirectory hash..."
python3 "${SCRIPT_DIR}/patch_macho.py" "${PKG_ROOT}/usr/local/bin/mihomo"

# Also include patch_macho utility in package
cp "${SCRIPT_DIR}/patch_macho.py" "${PKG_ROOT}/usr/local/bin/mihomo-patch-macho"
chmod 755 "${PKG_ROOT}/usr/local/bin/mihomo-patch-macho"

# 2. Normalize and validate permissions
echo "[*] Normalizing file permissions for dpkg staging..."
chmod 755 "${PKG_ROOT}/DEBIAN"
chmod 755 "${PKG_ROOT}/DEBIAN/postinst" "${PKG_ROOT}/DEBIAN/prerm"
chmod 644 "${PKG_ROOT}/DEBIAN/control"

chmod 755 "${PKG_ROOT}/usr/local/bin/mihomo"
chmod 755 "${PKG_ROOT}/usr/local/bin/mihomo-ctl"

chmod 755 "${PKG_ROOT}/Library/LaunchDaemons"
if [ -f "${PKG_ROOT}/Library/LaunchDaemons/com.hrdcoreee.clashify.plist" ]; then
    chmod 644 "${PKG_ROOT}/Library/LaunchDaemons/com.hrdcoreee.clashify.plist"
fi

chmod 755 "${PKG_ROOT}/var/mobile/Library/Mihomo"
chmod 644 "${PKG_ROOT}/var/mobile/Library/Mihomo/config.yaml"
chmod 644 "${PKG_ROOT}/var/mobile/Library/Mihomo/entitlements.xml"

if [ -d "${PKG_ROOT}/var/mobile/Library/Mihomo/src_app" ]; then
    chmod -R 755 "${PKG_ROOT}/var/mobile/Library/Mihomo/src_app"
fi

if [ -d "${PKG_ROOT}/var/mobile/Library/Mihomo/src_ctl" ]; then
    chmod -R 755 "${PKG_ROOT}/var/mobile/Library/Mihomo/src_ctl"
fi

if [ -d "${PKG_ROOT}/Applications/Mihomo.app" ]; then
    chmod -R 755 "${PKG_ROOT}/Applications/Mihomo.app"
    chmod 644 "${PKG_ROOT}/Applications/Mihomo.app/Info.plist" 2>/dev/null || true
fi

chmod -R 755 "${PKG_ROOT}/var/mobile/Library/WebClips/MihomoWebUI.webclip"
chmod 644 "${PKG_ROOT}/var/mobile/Library/WebClips/MihomoWebUI.webclip/Info.plist"
chmod 644 "${PKG_ROOT}/var/mobile/Library/WebClips/MihomoWebUI.webclip/icon.png"

# Remove any unwanted files
find "${PKG_ROOT}" -name ".DS_Store" -delete 2>/dev/null || true

# 3. Build debian package with gzip compression (crucial for iOS 14 dpkg compatibility)
echo "[*] Packaging with dpkg-deb (-Zgzip)..."
rm -f "${OUTPUT_DEB}"

# Use fakeroot if available, otherwise standard dpkg-deb
if command -v fakeroot >/dev/null 2>&1; then
    fakeroot dpkg-deb -Zgzip -b "${PKG_ROOT}" "${OUTPUT_DEB}"
else
    dpkg-deb -Zgzip -b "${PKG_ROOT}" "${OUTPUT_DEB}"
fi

echo "[+] Successfully built: ${OUTPUT_DEB} ($(du -sh "${OUTPUT_DEB}" | cut -f1))"

# 4. Inspect package information
echo ""
echo "=== Package Control Information ==="
dpkg-deb -I "${OUTPUT_DEB}"

echo ""
echo "=== Package File List (first 25 entries) ==="
dpkg-deb -c "${OUTPUT_DEB}" > "${SCRIPT_DIR}/.pkg_files.tmp"
head -n 25 "${SCRIPT_DIR}/.pkg_files.tmp"
echo "... [total files: $(wc -l < "${SCRIPT_DIR}/.pkg_files.tmp")]"
rm -f "${SCRIPT_DIR}/.pkg_files.tmp"

echo ""
echo "[✓] Build complete and verified!"
