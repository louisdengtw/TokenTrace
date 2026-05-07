#!/bin/bash
# Build ClaudeUsage.app from the Swift Package, copy resources, and code-sign.
#
# Behavior:
#   - swift build -c release for arm64 + x86_64 (lipo'd into a universal binary)
#   - assembles ClaudeUsage.app/Contents/{MacOS,Resources}
#   - copies Info.plist + .icns
#   - signs with self-signed cert if available, else ad-hoc
#   - pass --open to launch the app afterward (kills any prior instance first)

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

APP_NAME="ClaudeUsage"
BUNDLE_ID="dev.louisdeng.claudeusage"
EXECUTABLE_TARGET="ClaudeUsageApp"
SIGN_CERT_HASH="F690B9DA81D392695487D52D35F6B37E7A362495"

BUILD_DIR="${REPO_ROOT}/build"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_PATH}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RES_DIR="${CONTENTS}/Resources"

OPEN_AFTER=0
for arg in "$@"; do
    case "${arg}" in
        --open) OPEN_AFTER=1 ;;
    esac
done

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
if [ -f "${REPO_ROOT}/Resources/${APP_NAME}.icns" ]; then
    cp "${REPO_ROOT}/Resources/${APP_NAME}.icns" "${RES_DIR}/${APP_NAME}.icns"
fi

printf 'APPL????' > "${CONTENTS}/PkgInfo"

# Strip extended attributes that confuse codesign on case-insensitive filesystems.
xattr -cr "${APP_PATH}"

echo "==> Signing"
if security find-certificate -Z -c "${SIGN_CERT_HASH}" >/dev/null 2>&1 \
   || security find-identity -p codesigning -v 2>/dev/null | grep -qi "${SIGN_CERT_HASH}"; then
    if codesign --force --deep --sign "${SIGN_CERT_HASH}" "${APP_PATH}" 2>/dev/null; then
        echo "    signed with self-signed cert ${SIGN_CERT_HASH}"
    else
        echo "    self-signed cert lookup matched but signing failed — falling back to ad-hoc"
        codesign --force --deep --sign - "${APP_PATH}"
    fi
else
    echo "    self-signed cert ${SIGN_CERT_HASH} not present — using ad-hoc signature"
    codesign --force --deep --sign - "${APP_PATH}"
fi

codesign --verify --deep --strict "${APP_PATH}" || {
    echo "WARNING: codesign --verify reported issues" >&2
}

echo "==> Done: ${APP_PATH}"

if [ "${OPEN_AFTER}" -eq 1 ]; then
    echo "==> Killing any running ${APP_NAME} (open(1) won't replace a live instance)"
    pkill -x "${APP_NAME}" 2>/dev/null || true
    sleep 0.3
    open "${APP_PATH}"
fi
