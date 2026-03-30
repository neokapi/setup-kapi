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

case "${GOOS}" in
  windows) ARCHIVE_EXT="zip" ;;
  *)       ARCHIVE_EXT="tar.gz" ;;
esac

export GOOS GOARCH ARCHIVE_EXT
