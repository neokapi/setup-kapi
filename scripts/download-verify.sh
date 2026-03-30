#!/usr/bin/env bash
# Download kapi CLI archive, verify SHA-256 checksum, and extract.
#
# Usage: download-verify.sh <version> <os> <arch> <ext> <dest>
# Requires: GH_TOKEN environment variable for private repo access.

set -euo pipefail

VERSION="${1:?Usage: download-verify.sh <version> <os> <arch> <ext> <dest>}"
OS="${2:?}"
ARCH="${3:?}"
EXT="${4:?}"
DEST="${5:?}"

ARCHIVE="kapi-cli_${VERSION}_${OS}_${ARCH}.${EXT}"
TAG="v${VERSION}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT

echo "Downloading ${ARCHIVE} from release ${TAG}..."
gh release download "${TAG}" \
  --repo neokapi/neokapi \
  --pattern "${ARCHIVE}" \
  --pattern "checksums.txt" \
  --dir "${TMPDIR}"

# Verify checksum
cd "${TMPDIR}"
EXPECTED=$(grep "${ARCHIVE}" checksums.txt | awk '{print $1}')
if [ -z "${EXPECTED}" ]; then
  echo "::error::Archive ${ARCHIVE} not found in checksums.txt" >&2
  exit 1
fi

if command -v sha256sum &>/dev/null; then
  ACTUAL=$(sha256sum "${ARCHIVE}" | awk '{print $1}')
else
  ACTUAL=$(shasum -a 256 "${ARCHIVE}" | awk '{print $1}')
fi

if [ "${EXPECTED}" != "${ACTUAL}" ]; then
  echo "::error::Checksum mismatch for ${ARCHIVE}" >&2
  echo "  expected: ${EXPECTED}" >&2
  echo "  actual:   ${ACTUAL}" >&2
  exit 1
fi
echo "Checksum verified: ${ACTUAL}"

# Extract
mkdir -p "${DEST}"
if [ "${EXT}" = "zip" ]; then
  unzip -o "${ARCHIVE}" -d "${DEST}"
else
  tar xzf "${ARCHIVE}" -C "${DEST}"
fi

# Ensure binary is executable
if [ "${OS}" != "windows" ]; then
  chmod +x "${DEST}/kapi"
fi

echo "Installed kapi ${VERSION} to ${DEST}"
