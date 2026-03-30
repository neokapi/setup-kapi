#!/usr/bin/env bash
# Resolve kapi CLI version.
#
# Usage: resolve-version.sh <version>
# If <version> is "latest", queries the GitHub API for the latest release tag.
# Otherwise, strips a leading "v" and echoes the version.
#
# Requires: GH_TOKEN environment variable for private repo access.

set -euo pipefail

VERSION="${1:?Usage: resolve-version.sh <version>}"

if [ "${VERSION}" = "latest" ]; then
  TAG=$(gh api repos/neokapi/neokapi/releases/latest --jq .tag_name 2>/dev/null) || {
    echo "::error::Failed to query latest release. Check that GH_TOKEN has read access to neokapi/neokapi." >&2
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
