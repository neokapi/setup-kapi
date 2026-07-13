#!/usr/bin/env bash
# Map runner.os and runner.arch to GoReleaser archive naming.
#
# Usage: source platform.sh
# Requires: RUNNER_OS, RUNNER_ARCH environment variables (set by GitHub Actions).
# Exports:  GOOS, GOARCH, ARCHIVE_EXT

set -euo pipefail

case "${RUNNER_OS}" in
  Linux)  GOOS="linux" ;;
  macOS)  GOOS="darwin" ;;
  Windows) GOOS="windows" ;;
  *) echo "::error::Unsupported OS: ${RUNNER_OS}" >&2; exit 1 ;;
esac

case "${RUNNER_ARCH}" in
  X64)   GOARCH="amd64" ;;
  ARM64) GOARCH="arm64" ;;
  *) echo "::error::Unsupported architecture: ${RUNNER_ARCH}" >&2; exit 1 ;;
esac

# The CLI ships darwin_arm64 only — there is no Intel-mac archive to download, so
# say that plainly here instead of failing later with a 404 on a release asset.
if [ "${GOOS}" = "darwin" ] && [ "${GOARCH}" = "amd64" ]; then
  echo "::error::kapi does not publish an Intel-macOS (darwin_amd64) build. Use an arm64 macOS runner (macos-14 or newer, or macos-latest)." >&2
  exit 1
fi

case "${GOOS}" in
  windows) ARCHIVE_EXT="zip" ;;
  *)       ARCHIVE_EXT="tar.gz" ;;
esac

export GOOS GOARCH ARCHIVE_EXT
