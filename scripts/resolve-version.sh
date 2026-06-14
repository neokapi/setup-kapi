#!/usr/bin/env bash
# Resolve kapi CLI version.
#
# Usage: resolve-version.sh <version>
# If <version> is "latest", queries the GitHub API for the latest release tag.
# Otherwise, strips a leading "v" and echoes the version.
#
# Requires: GH_TOKEN for the `gh` CLI (API rate limits). The built-in
# GITHUB_TOKEN suffices now that neokapi/neokapi is public.

set -euo pipefail

VERSION="${1:?Usage: resolve-version.sh <version>}"

if [ "${VERSION}" = "latest" ]; then
  TAG=$(gh api repos/neokapi/neokapi/releases/latest --jq .tag_name 2>/dev/null) || {
    echo "::error::Failed to query the latest neokapi/neokapi release." >&2
    exit 1
  }
  VERSION="${TAG#v}"
else
  VERSION="${VERSION#v}"
fi

if [ -z "${VERSION}" ]; then
  echo "::error::Could not resolve version." >&2
  exit 1
fi

echo "${VERSION}"
