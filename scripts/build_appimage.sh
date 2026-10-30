#!/usr/bin/env bash
# Builds the Linux release bundle and packages it as an AppImage.
# Output: build/appimage/Woxxy-<arch>.AppImage
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="$(uname -m)"
OUT_DIR="${ROOT_DIR}/build/appimage"
APP_DIR="${OUT_DIR}/AppDir"
TOOL_PATH="${OUT_DIR}/appimagetool-${ARCH}.AppImage"
TOOL_URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${ARCH}.AppImage"

case "${ARCH}" in
  x86_64) BUNDLE_ARCH="x64" ;;
  aarch64) BUNDLE_ARCH="arm64" ;;
  *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;;
esac
BUNDLE_DIR="${ROOT_DIR}/build/linux/${BUNDLE_ARCH}/release/bundle"

# Downloads appimagetool once and caches it in the output folder.
fetch_tool() {
  [ -x "${TOOL_PATH}" ] && return
  echo "Downloading appimagetool..."
  curl -fL --retry 3 -o "${TOOL_PATH}" "${TOOL_URL}"
  chmod +x "${TOOL_PATH}"
}

cd "${ROOT_DIR}"
flutter build linux --release
[ -x "${BUNDLE_DIR}/woxxy" ] || { echo "Missing bundle: ${BUNDLE_DIR}/woxxy" >&2; exit 1; }

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/usr/bin" "${APP_DIR}/usr/share/icons/hicolor/48x48/apps"
cp -a "${BUNDLE_DIR}/." "${APP_DIR}/usr/bin/"
cp linux/woxxy.desktop "${APP_DIR}/woxxy.desktop"
cp assets/icons/head.png "${APP_DIR}/woxxy.png"
cp assets/icons/head.png "${APP_DIR}/usr/share/icons/hicolor/48x48/apps/woxxy.png"
ln -s usr/bin/woxxy "${APP_DIR}/AppRun"

fetch_tool
# --appimage-extract-and-run avoids the FUSE requirement of the tool itself
ARCH="${ARCH}" "${TOOL_PATH}" --appimage-extract-and-run --no-appstream \
  "${APP_DIR}" "${OUT_DIR}/Woxxy-${ARCH}.AppImage"

echo "Created ${OUT_DIR}/Woxxy-${ARCH}.AppImage"
