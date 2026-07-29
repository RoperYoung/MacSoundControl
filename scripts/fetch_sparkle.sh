#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SPARKLE_VERSION="2.9.4"
SPARKLE_ARCHIVE="Sparkle-${SPARKLE_VERSION}.tar.xz"
SPARKLE_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/${SPARKLE_ARCHIVE}"
SPARKLE_SHA256="ce89daf967db1e1893ed3ebd67575ed82d3902563e3191ca92aaec9164fbdef9"
CACHE_ROOT="${SPARKLE_CACHE_DIR:-${ROOT_DIR}/Build/Dependencies}"
DIST_ROOT="${CACHE_ROOT}/Sparkle-${SPARKLE_VERSION}"
FRAMEWORK_PATH="${DIST_ROOT}/Sparkle.framework"
LICENSE_PATH="${DIST_ROOT}/LICENSE"

if [[ -d "${FRAMEWORK_PATH}" && -f "${LICENSE_PATH}" ]]; then
    print -r -- "${DIST_ROOT}"
    exit 0
fi

TEMP_DIR="$(mktemp -d /tmp/MacSoundControl-Sparkle.XXXXXX)"
ARCHIVE_PATH="${TEMP_DIR}/${SPARKLE_ARCHIVE}"

cleanup() {
    rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

print -u2 -- "下载 Sparkle ${SPARKLE_VERSION}…"
curl --fail --location --silent --show-error \
    --output "${ARCHIVE_PATH}" \
    "${SPARKLE_URL}"

ACTUAL_SHA256="$(shasum -a 256 "${ARCHIVE_PATH}" | awk '{print $1}')"
if [[ "${ACTUAL_SHA256}" != "${SPARKLE_SHA256}" ]]; then
    print -u2 -- "Sparkle 校验失败：${ACTUAL_SHA256}"
    exit 1
fi

mkdir -p "${CACHE_ROOT}"
if [[ -e "${DIST_ROOT}" ]]; then
    print -u2 -- "Sparkle 缓存路径已存在但内容不完整：${DIST_ROOT}"
    exit 1
fi
mkdir "${DIST_ROOT}"
tar -xJf "${ARCHIVE_PATH}" -C "${DIST_ROOT}"

if [[ ! -d "${FRAMEWORK_PATH}" || ! -f "${LICENSE_PATH}" ]]; then
    print -u2 -- "Sparkle 发行包结构不完整"
    exit 1
fi

codesign --verify --deep --strict "${FRAMEWORK_PATH}"
print -r -- "${DIST_ROOT}"
