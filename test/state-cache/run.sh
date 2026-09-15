#!/usr/bin/env bash
# Runs a fixed kapi command sequence over a project and records what each
# command reported and which files the project holds afterwards, normalized so
# that two runs can be compared with compare.sh.
#
# usage: run.sh <project-dir> <record-dir>
set -uo pipefail

project=$(cd "$1" && pwd) || exit 1
mkdir -p "$2"
record=$(cd "$2" && pwd) || exit 1

sha() {
  if command -v sha256sum > /dev/null; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi
}

cd "$project" || exit 1
find .kapi/work/cache/docs -type f 2> /dev/null | LC_ALL=C sort > "$record/docs-before.txt"

# Durations and timings differ between runs, so they are removed before the
# output is recorded. Exit codes are recorded as they are.
strip='del(.. | .duration_ms?) | del(.. | .timings?)'
run() {
  local name=$1
  shift
  kapi "$@" > "$record/$name.raw" 2> "$record/$name.err"
  echo $? > "$record/$name.rc"
  jq -c "$strip" "$record/$name.raw" > "$record/$name.json" 2> /dev/null || cp "$record/$name.raw" "$record/$name.json"
}

run status-before status -p kapi.yaml --json
run check-before check -p kapi.yaml --output-format json
run ship-before check --ship -p kapi.yaml --output-format json
run up up -p kapi.yaml --json
run status-after status -p kapi.yaml --json
run check-after check -p kapi.yaml --output-format json
run ship-after check --ship -p kapi.yaml --output-format json

find .kapi/work/cache/docs -type f 2> /dev/null | LC_ALL=C sort > "$record/docs-after.txt"

# Every file outside .kapi/work, hashed. The unit-state record stamps each unit
# with the time it was written, so that field is removed before hashing.
find . -type f -not -path './.kapi/work/*' | LC_ALL=C sort | while read -r f; do
  case "$f" in
    ./.kapi/state/*) h=$(sed -E 's/"updated":"[^"]*",?//g' "$f" | sha) ;;
    *) h=$(sha < "$f") ;;
  esac
  echo "$h  $f"
done > "$record/tree.txt"
