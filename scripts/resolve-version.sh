#!/usr/bin/env bash
# Resolve kapi CLI version.
#
# Usage: resolve-version.sh <version>
# If <version> is "latest", resolves the newest STABLE kapi CLI release.
# Otherwise, strips a leading "v" and echoes the version.
#
# Requires: GH_TOKEN for the `gh` CLI (API rate limits). The built-in
# GITHUB_TOKEN suffices now that neokapi/neokapi is public.

set -euo pipefail

VERSION="${1:?Usage: resolve-version.sh <version>}"

if [ "${VERSION}" = "latest" ]; then
  # NOT `releases/latest`. One repository publishes the CLI, the desktop apps,
  # the bowrain server, and every plugin, so its releases are a mix of tags:
  #   v1.1.0            ← the CLI (what we want)
  #   check-v0.1.0      ← the kapi-check plugin
  #   asr-v0.1.1        ← the kapi-asr plugin
  #   bowrain-v1.2.0-rc8
  #   v1.2.0-rc9        ← a CLI prerelease
  # GitHub's "latest" flag lands on whichever of those was published last — as of
  # writing, a plugin (check-v0.1.0). Asking for it yielded VERSION=check-v0.1.0,
  # a download of `kapi_check-v0.1.0_linux_amd64.tar.gz` from tag `vcheck-v0.1.0`,
  # and a 404. So resolve the CLI ourselves: tags of the exact shape vX.Y.Z,
  # excluding drafts, prereleases, and every plugin/app tag prefix.
  VERSION=$(
    gh api "repos/neokapi/neokapi/releases?per_page=100" --paginate \
      --jq '.[] | select(.draft == false and .prerelease == false) | .tag_name' 2>/dev/null |
      grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' |
      sed 's/^v//' |
      sort -V |
      tail -n 1
  ) || {
    echo "::error::Failed to query neokapi/neokapi releases." >&2
    exit 1
  }
  if [ -z "${VERSION}" ]; then
    echo "::error::No stable kapi CLI release (vX.Y.Z) found in neokapi/neokapi." >&2
    exit 1
  fi
else
  VERSION="${VERSION#v}"
fi

if [ -z "${VERSION}" ]; then
  echo "::error::Could not resolve version." >&2
  exit 1
fi

echo "${VERSION}"
