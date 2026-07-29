#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_APP="${APP_OUTPUT_PATH:-${ROOT_DIR}/Build/Release/MacSoundControl.app}"
CONTENTS_DIR="${OUTPUT_APP}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
TEMP_BUILD_DIR="$(mktemp -d /tmp/MacSoundControl-Build.XXXXXX)"
MODULE_CACHE_DIR="${TEMP_BUILD_DIR}/ModuleCache"
APP_ENTITLEMENTS="${ROOT_DIR}/Entitlements.plist"

if [[ -n "${SPARKLE_ROOT:-}" ]]; then
  SPARKLE_DISTRIBUTION_ROOT="${SPARKLE_ROOT}"
else
  SPARKLE_DISTRIBUTION_ROOT="$("${ROOT_DIR}/scripts/fetch_sparkle.sh")"
fi
SPARKLE_FRAMEWORK="${SPARKLE_DISTRIBUTION_ROOT}/Sparkle.framework"
SPARKLE_LICENSE="${SPARKLE_DISTRIBUTION_ROOT}/LICENSE"

cleanup() {
  rm -rf "${TEMP_BUILD_DIR}"
}
trap cleanup EXIT

if [[ -z "${OUTPUT_APP}" || "${OUTPUT_APP}" != *.app ]]; then
  echo "APP_OUTPUT_PATH 必须是明确的 .app 路径：${OUTPUT_APP}" >&2
  exit 1
fi

if [[ ! -d "${SPARKLE_FRAMEWORK}" || ! -f "${SPARKLE_LICENSE}" ]]; then
  echo "Sparkle 发行目录不完整：${SPARKLE_DISTRIBUTION_ROOT}" >&2
  exit 1
fi

if [[ "${SIGN_IDENTITY}" != "-" ]] && \
   ! security find-identity -v -p codesigning | grep -Fq "\"${SIGN_IDENTITY}\""; then
  echo "缺少签名身份：${SIGN_IDENTITY}" >&2
  exit 1
fi

rm -rf "${OUTPUT_APP}"
mkdir -p \
  "${MACOS_DIR}" \
  "${RESOURCES_DIR}" \
  "${FRAMEWORKS_DIR}" \
  "${MODULE_CACHE_DIR}"

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
  -F "${SPARKLE_DISTRIBUTION_ROOT}" \
  -framework Sparkle \
  -Xlinker -rpath \
  -Xlinker "@executable_path/../Frameworks" \
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
  -F "${SPARKLE_DISTRIBUTION_ROOT}" \
  -framework Sparkle \
  -Xlinker -rpath \
  -Xlinker "@executable_path/../Frameworks" \
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
cp "${SPARKLE_LICENSE}" "${RESOURCES_DIR}/Sparkle-LICENSE.txt"
ditto "${SPARKLE_FRAMEWORK}" "${FRAMEWORKS_DIR}/Sparkle.framework"
chmod 755 "${MACOS_DIR}/MacSoundControl"

sign_component() {
  local component_path="$1"
  local preserve_entitlements="${2:-0}"
  local sign_arguments=(--force --options runtime)

  if [[ "${SIGN_IDENTITY}" == "-" ]]; then
    sign_arguments+=(--sign -)
  else
    sign_arguments+=(--timestamp --sign "${SIGN_IDENTITY}")
  fi
  if [[ "${preserve_entitlements}" == "1" ]]; then
    sign_arguments+=(--preserve-metadata=entitlements)
  fi

  codesign "${sign_arguments[@]}" "${component_path}"
}

SPARKLE_EMBEDDED="${FRAMEWORKS_DIR}/Sparkle.framework/Versions/B"
sign_component "${SPARKLE_EMBEDDED}/XPCServices/Installer.xpc"
sign_component "${SPARKLE_EMBEDDED}/XPCServices/Downloader.xpc" 1
sign_component "${SPARKLE_EMBEDDED}/Autoupdate"
sign_component "${SPARKLE_EMBEDDED}/Updater.app"
sign_component "${FRAMEWORKS_DIR}/Sparkle.framework"

if [[ "${SIGN_IDENTITY}" == "-" ]]; then
  APP_ENTITLEMENTS="${TEMP_BUILD_DIR}/AdHocEntitlements.plist"
  cp "${ROOT_DIR}/Entitlements.plist" "${APP_ENTITLEMENTS}"
  /usr/libexec/PlistBuddy \
    -c "Add :com.apple.security.cs.disable-library-validation bool true" \
    "${APP_ENTITLEMENTS}"
fi

APP_SIGN_ARGUMENTS=(
  --force
  --options runtime
  --entitlements "${APP_ENTITLEMENTS}"
)
if [[ "${SIGN_IDENTITY}" == "-" ]]; then
  APP_SIGN_ARGUMENTS+=(--sign -)
else
  APP_SIGN_ARGUMENTS+=(--timestamp --sign "${SIGN_IDENTITY}")
fi
codesign "${APP_SIGN_ARGUMENTS[@]}" "${OUTPUT_APP}"

codesign --verify --deep --strict --verbose=2 "${OUTPUT_APP}"

echo "${OUTPUT_APP}"
