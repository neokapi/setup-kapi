#!/usr/bin/env bash
# Checks that each named plugin the action left installed is the version the
# kapi on PATH installs into an empty plugin root, and exits 1 when one is not.
#
# usage: matches-fresh.sh <plugin>...
set -euo pipefail

installed_root="${HOME}/.local/share/kapi/plugins"
fresh_data="$(mktemp -d)"
trap 'rm -rf "${fresh_data}"' EXIT

recorded_version() {
  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1/installed.json" | head -n 1
}

status=0
for plugin in "$@"; do
  XDG_DATA_HOME="${fresh_data}" kapi plugin install "${plugin}" > /dev/null
  want=$(recorded_version "${fresh_data}/kapi/plugins/${plugin}")
  got=$(recorded_version "${installed_root}/${plugin}")
  echo "${plugin}: installed ${got:-<none>}, a fresh install by $(kapi version 2>&1 | head -n 1) picks ${want}"
  if [ -z "${want}" ] || [ "${got}" != "${want}" ]; then
    echo "::error::${plugin} ${got:-<none>} is installed, but this kapi installs ${want:-<nothing>} fresh."
    status=1
  fi
done
exit "${status}"
