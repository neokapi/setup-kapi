#!/usr/bin/env bash
# Download kapi CLI archive, verify SHA-256 checksum, and extract.
#
# Usage: download-verify.sh <version> <os> <arch> <ext> <dest>
# Requires: GH_TOKEN for the `gh` CLI (release download + API rate limits). The
# built-in GITHUB_TOKEN suffices now that neokapi/neokapi is public.

set -euo pipefail

VERSION="${1:?Usage: download-verify.sh <version> <os> <arch> <ext> <dest>}"
OS="${2:?}"
ARCH="${3:?}"
EXT="${4:?}"
DEST="${5:?}"

TAG="v${VERSION}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT

# The CLI archive was renamed for 1.2.0: kapi_<ver>_<os>_<arch>.<ext> became
# kapi-cli_<ver>_<os>_<arch>.<ext> (scripts/package-cli.sh mirrors the
# Homebrew naming, where the CLI toolchain is kapi-cli). Resolve the actual
# name from checksums.txt — the release's own asset manifest — so the action
# installs both eras: 1.1.0 and earlier ship kapi_, 1.2.0-rc1 and later ship
# kapi-cli_.
echo "Fetching checksums.txt from release ${TAG}..."
gh release download "${TAG}" \
  --repo neokapi/neokapi \
  --pattern "checksums.txt" \
  --dir "${TMPDIR}"

cd "${TMPDIR}"
ARCHIVE=""
for candidate in "kapi-cli_${VERSION}_${OS}_${ARCH}.${EXT}" "kapi_${VERSION}_${OS}_${ARCH}.${EXT}"; do
  if awk -v name="${candidate}" '$2 == name { found = 1 } END { exit !found }' checksums.txt; then
    ARCHIVE="${candidate}"
    break
  fi
done
if [ -z "${ARCHIVE}" ]; then
  echo "::error::Release ${TAG} has neither kapi-cli_${VERSION}_${OS}_${ARCH}.${EXT} nor kapi_${VERSION}_${OS}_${ARCH}.${EXT} in checksums.txt" >&2
  exit 1
fi

echo "Downloading ${ARCHIVE} from release ${TAG}..."
gh release download "${TAG}" \
  --repo neokapi/neokapi \
  --pattern "${ARCHIVE}" \
  --dir "${TMPDIR}"

# Verify checksum
EXPECTED=$(awk -v name="${ARCHIVE}" '$2 == name { print $1 }' checksums.txt)
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
