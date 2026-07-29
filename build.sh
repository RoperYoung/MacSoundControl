#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_APP="${APP_OUTPUT_PATH:-${ROOT_DIR}/Build/Release/MacSoundControl.app}"
CONTENTS_DIR="${OUTPUT_APP}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
TEMP_BUILD_DIR="$(mktemp -d /tmp/MacSoundControl-Build.XXXXXX)"
MODULE_CACHE_DIR="${TEMP_BUILD_DIR}/ModuleCache"

cleanup() {
  rm -rf "${TEMP_BUILD_DIR}"
}
trap cleanup EXIT

if [[ -z "${OUTPUT_APP}" || "${OUTPUT_APP}" != *.app ]]; then
  echo "APP_OUTPUT_PATH 必须是明确的 .app 路径：${OUTPUT_APP}" >&2
  exit 1
fi

if [[ "${SIGN_IDENTITY}" != "-" ]] && \
   ! security find-identity -v -p codesigning | grep -Fq "\"${SIGN_IDENTITY}\""; then
  echo "缺少签名身份：${SIGN_IDENTITY}" >&2
  exit 1
fi

rm -rf "${OUTPUT_APP}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${MODULE_CACHE_DIR}"

xcrun swiftc \
  -O \
  -warnings-as-errors \
  -swift-version 5 \
  -module-cache-path "${MODULE_CACHE_DIR}" \
  -target arm64-apple-macosx14.0 \
  -framework Accelerate \
  -framework AppKit \
  -framework AudioToolbox \
  -framework AVFoundation \
  -framework CoreMedia \
  -framework CoreAudio \
  -framework ServiceManagement \
  "${ROOT_DIR}/Sources/"*.swift \
  -o "${TEMP_BUILD_DIR}/MacSoundControl-arm64"

xcrun swiftc \
  -O \
  -warnings-as-errors \
  -swift-version 5 \
  -module-cache-path "${MODULE_CACHE_DIR}" \
  -target x86_64-apple-macosx14.0 \
  -framework Accelerate \
  -framework AppKit \
  -framework AudioToolbox \
  -framework AVFoundation \
  -framework CoreMedia \
  -framework CoreAudio \
  -framework ServiceManagement \
  "${ROOT_DIR}/Sources/"*.swift \
  -o "${TEMP_BUILD_DIR}/MacSoundControl-x86_64"

lipo \
  -create \
  "${TEMP_BUILD_DIR}/MacSoundControl-arm64" \
  "${TEMP_BUILD_DIR}/MacSoundControl-x86_64" \
  -output "${MACOS_DIR}/MacSoundControl"

cp "${ROOT_DIR}/Info.plist" "${CONTENTS_DIR}/Info.plist"
cp "${ROOT_DIR}/Assets/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
cp "${ROOT_DIR}/Assets/StatusBarIcon.svg" "${RESOURCES_DIR}/StatusBarIcon.svg"
cp "${ROOT_DIR}/THIRD_PARTY_NOTICES.md" "${RESOURCES_DIR}/THIRD_PARTY_NOTICES.md"
chmod 755 "${MACOS_DIR}/MacSoundControl"

if [[ "${SIGN_IDENTITY}" == "-" ]]; then
  codesign \
    --force \
    --deep \
    --options runtime \
    --entitlements "${ROOT_DIR}/Entitlements.plist" \
    --sign - \
    "${OUTPUT_APP}"
else
  codesign \
    --force \
    --deep \
    --options runtime \
    --entitlements "${ROOT_DIR}/Entitlements.plist" \
    --timestamp \
    --sign "${SIGN_IDENTITY}" \
    "${OUTPUT_APP}"
fi

echo "${OUTPUT_APP}"
