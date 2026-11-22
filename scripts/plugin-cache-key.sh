#!/usr/bin/env bash
# Print the cache key component for a set of kapi plugins.
#
# Usage: plugin-cache-key.sh <kapi-version> <plugins-input>
#
# `kapi plugin install <ref>` picks a version from three things: the ref
# (name, constraint, channel), the running kapi's version (a registry entry
# can set min_kapi_version) and the plugin's entry in the registry index. The
# key is a hash of all three, so a cached plugin set is restored only when a
# fresh install by this kapi would choose the same versions. A new kapi, a
# new plugin release, or a withdrawn one changes the key.
#
# The registry index is read from $KAPI_REGISTRY_URL, as kapi reads it, or
# from kapi's default. With jq, only the requested plugins' entries are
# hashed; without it, the whole index is, which misses the cache more often
# but never restores a stale plugin. When the index cannot be fetched, the
# key is unique to the run, so the cache misses and the install step runs.

set -euo pipefail

KAPI_VERSION="${1:?Usage: plugin-cache-key.sh <kapi-version> <plugins-input>}"
INPUT_PLUGINS="${2:-}"
INDEX_URL="${KAPI_REGISTRY_URL:-https://neokapi.github.io/registry/manifest-plugins.json}"

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

# The same normalisation the install step applies: commas to newlines,
# trimmed, empty lines dropped, the 'kapi-' binary prefix stripped. Sorted, so
# the order of the input does not split the cache.
PLUGINS=$(printf '%s\n' "${INPUT_PLUGINS}" | tr ',' '\n' |
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^kapi-//' | grep -v '^$' | LC_ALL=C sort -u || true)

INDEX_FILE=$(mktemp)
trap 'rm -f "${INDEX_FILE}"' EXIT

if ! curl -fsSL --retry 3 --retry-delay 2 -o "${INDEX_FILE}" "${INDEX_URL}"; then
  echo "::warning::Could not read the plugin registry at ${INDEX_URL}; the plugin cache is skipped for this run." >&2
  printf 'unresolved-%s-%s-%s\n' "${GITHUB_RUN_ID:-local}" "${GITHUB_RUN_ATTEMPT:-0}" "$(date +%s)"
  exit 0
fi

{
  printf 'kapi=%s\n' "${KAPI_VERSION}"
  printf 'index=%s\n' "${INDEX_URL}"
  printf 'plugins=%s\n' "${PLUGINS}"
  if command -v jq >/dev/null 2>&1; then
    while IFS= read -r ref; do
      [ -n "${ref}" ] || continue
      name="${ref%%@*}"
      printf 'entry %s=' "${name}"
      jq -cS --arg n "${name}" '.plugins[$n] // null' "${INDEX_FILE}"
    done <<< "${PLUGINS}"
  else
    printf 'index-sha256='
    sha256 < "${INDEX_FILE}"
  fi
} | sha256
