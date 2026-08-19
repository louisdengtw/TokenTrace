#!/bin/bash
# Build TokenTrace.app from the Swift Package, copy resources, and code-sign.
#
# Pure build: produces build/TokenTrace.app and stops. Installation and
# launch live in the Makefile (`make install`, `make run`).
#
# Behavior:
#   - swift build -c release for arm64 + x86_64 (lipo'd into a universal binary)
#   - assembles TokenTrace.app/Contents/{MacOS,Resources}
#   - copies Info.plist + .icns
#   - signs with self-signed cert if available, else ad-hoc

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

APP_NAME="${APP_NAME:-TokenTrace}"
BUNDLE_ID="${BUNDLE_ID:-dev.louisdeng.tokentrace}"
EXECUTABLE_TARGET="TokenTraceApp"
SIGN_CERT_HASH="F690B9DA81D392695487D52D35F6B37E7A362495"

BUILD_DIR="${REPO_ROOT}/build"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_PATH}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RES_DIR="${CONTENTS}/Resources"

echo "==> Building ${APP_NAME} (universal arm64 + x86_64)…"

# Build for each arch separately so we can lipo into a universal binary.
# `swift build --arch a --arch b` is supported, but we want explicit control over the bin path.
swift build -c release --arch arm64 --arch x86_64

UNIVERSAL_BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/${EXECUTABLE_TARGET}"

if [ ! -f "${UNIVERSAL_BIN}" ]; then
    echo "ERROR: expected universal binary at ${UNIVERSAL_BIN} not found" >&2
    exit 1
fi

echo "==> Assembling ${APP_PATH}"
rm -rf "${APP_PATH}"
mkdir -p "${MACOS_DIR}" "${RES_DIR}"

cp "${UNIVERSAL_BIN}" "${MACOS_DIR}/${APP_NAME}"
chmod 755 "${MACOS_DIR}/${APP_NAME}"

cp "${REPO_ROOT}/Resources/Info.plist" "${CONTENTS}/Info.plist"

# Identity keys are env-overridable so a side-by-side dev build is possible
# (no-op when APP_NAME/BUNDLE_ID are at their defaults).
plutil -replace CFBundleIdentifier  -string "${BUNDLE_ID}" "${CONTENTS}/Info.plist"
plutil -replace CFBundleName        -string "${APP_NAME}"  "${CONTENTS}/Info.plist"
plutil -replace CFBundleDisplayName -string "${APP_NAME}"  "${CONTENTS}/Info.plist"
plutil -replace CFBundleExecutable  -string "${APP_NAME}"  "${CONTENTS}/Info.plist"
plutil -replace CFBundleIconFile    -string "${APP_NAME}"  "${CONTENTS}/Info.plist"

if [ -f "${REPO_ROOT}/Resources/${APP_NAME}.icns" ]; then
    cp "${REPO_ROOT}/Resources/${APP_NAME}.icns" "${RES_DIR}/${APP_NAME}.icns"
fi

# SPM emits resources for the executable target as a sibling bundle named
# <Module>_<Target>.bundle. `Bundle.module` looks for it inside the app's
# Resources dir at runtime — must be copied in, or the report exporter
# crashes on first Save (Bundle.module assertion failure).
SPM_BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
SPM_RESOURCE_BUNDLE="${SPM_BIN_DIR}/${EXECUTABLE_TARGET}_${EXECUTABLE_TARGET}.bundle"
if [ -d "${SPM_RESOURCE_BUNDLE}" ]; then
    cp -R "${SPM_RESOURCE_BUNDLE}" "${RES_DIR}/"
else
    echo "WARNING: SPM resource bundle not found at ${SPM_RESOURCE_BUNDLE}" >&2
fi

printf 'APPL????' > "${CONTENTS}/PkgInfo"

# Strip extended attributes that confuse codesign on case-insensitive filesystems.
xattr -cr "${APP_PATH}"

echo "==> Signing"
# Just attempt the signature rather than pre-checking for the identity:
# `security find-identity -v` hides certs whose trust settings were reset,
# but `codesign` signs with them fine, so a pre-check only produces false
# negatives and a silent downgrade to ad-hoc.
if codesign --force --deep --sign "${SIGN_CERT_HASH}" "${APP_PATH}" 2>/dev/null; then
    echo "    signed with self-signed cert ${SIGN_CERT_HASH}"
else
    echo "    self-signed cert ${SIGN_CERT_HASH} unusable — using ad-hoc signature"
    codesign --force --deep --sign - "${APP_PATH}"
fi

codesign --verify --deep --strict "${APP_PATH}" || {
    echo "WARNING: codesign --verify reported issues" >&2
}

echo "==> Done: ${APP_PATH}"
