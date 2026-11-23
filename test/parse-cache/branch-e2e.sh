#!/usr/bin/env bash
# TEMPORARY: cold and warm runs of a kapi that reads KAPI_PARSE_CACHE_DIR,
# through setup-kapi. Removed before merging.
#
#   branch-e2e.sh cold <results>
#   branch-e2e.sh warm <cold-results> <results>
#   branch-e2e.sh refuse <results>      (expects every kapi command to fail)
#
# The action has already set KAPI_PARSE_CACHE_DIR; kapi on PATH is the build
# under test; the project is test/fixture.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
mode="$1"
shift

pc="${KAPI_PARSE_CACHE_DIR:?KAPI_PARSE_CACHE_DIR is not set}"

# These jobs install release 1.4.0-rc5 and then run the #3804 build, so the
# cache key names 1.4.0-rc5 and the restore can bring the in-tree cache another
# job saved with the real 1.4.0-rc5. Remove it, so the check below sees only
# what this build writes.
if [ -e test/fixture/.kapi/work ]; then
  echo "note: removed test/fixture/.kapi/work, restored from a 1.4.0-rc5 in-tree cache"
  rm -rf test/fixture/.kapi/work
fi

mode_of() {
  if stat -c '%a' "$1" > /dev/null 2>&1; then stat -c '%a %U' "$1"; else stat -f '%Lp %Su' "$1"; fi
}

# snapshot DIR: each file under DIR with its digest, and the index rows.
snapshot() {
  (cd "$1" && find . -type f ! -name 'index.db*' | LC_ALL=C sort | while read -r f; do
    printf '%s  %s\n' "$(shasum -a 256 < "$f" | cut -d' ' -f1)" "$f"
  done)
  python3 - "$1/index.db" <<'PY'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
for row in db.execute("select path, build, config_key, content_hash, parts_ref, parts_digest from documents order by path, config_key"):
    print("row", *row)
PY
}

# normalize RECORD: drop timestamps that differ between any two runs.
normalize() {
  local out="$1.norm"
  mkdir -p "$out"
  for f in "$1"/*.json; do
    jq -c 'del(.. | .at?)' "$f" > "$out/$(basename "$f")" 2> /dev/null || cp "$f" "$out/"
  done
  cp "$1"/*.rc "$1/tree.txt" "$out/"
}

check_layout() {
  local results="$1"
  kapi version | tee "${results}/version.txt"
  kapi state path -p test/fixture --json | tee "${results}/state-path.json"
  local state got
  state="$(jq -r .path "${results}/state-path.json")"
  got="$(jq -r .parse_cache "${results}/state-path.json")"
  [ "${got}" = "${pc}" ] || { echo "::error::kapi resolved the parse cache to ${got}, not ${pc}"; exit 1; }
  [ ! -e "${state}/work/cache/docs" ] || { echo "::error::the state directory holds a parse cache"; exit 1; }
  [ ! -e test/fixture/.kapi/work ] || { echo "::error::the checkout holds .kapi/work"; exit 1; }
  echo "parse cache directory: ${pc} ($(mode_of "${pc}"))" | tee -a "${results}/summary.txt"
  [ "$(mode_of "${pc}" | cut -d' ' -f1)" = 700 ] || { echo "::error::the parse cache directory is not 0700"; exit 1; }
  find "${pc}" -type f | sed "s|${pc}|<pc>|" | LC_ALL=C sort | tee "${results}/pc-files.txt"
}

case "${mode}" in
  cold)
    results="$1"
    mkdir -p "${results}"
    [ ! -e "${pc}" ] || { echo "::error::the cold run found ${pc} already present"; exit 1; }
    "${root}/test/state-cache/run.sh" test/fixture "${results}/run"
    check_layout "${results}"
    snapshot "${pc}" > "${results}/snapshot.txt"
    echo "entries: $(grep -c '^row ' "${results}/snapshot.txt"), part files: $(grep -vc '^row ' "${results}/snapshot.txt")" | tee -a "${results}/summary.txt"
    ;;

  warm)
    cold="$1"
    results="$2"
    mkdir -p "${results}"
    # What the restore brought: only the parse cache directory.
    [ -s "${pc}/index.db" ] || { echo "::error::no parse cache was restored into ${pc}"; exit 1; }
    echo "restored: ${pc} ($(mode_of "${pc}"))" | tee -a "${results}/summary.txt"
    [ "$(mode_of "${pc}" | cut -d' ' -f1)" = 700 ] || { echo "::error::the restored directory is not 0700"; exit 1; }
    [ ! -e test/fixture/.kapi/work ] || { echo "::error::the restore wrote into the checkout"; exit 1; }
    snapshot "${pc}" > "${results}/before.txt"
    diff -u "${cold}/snapshot.txt" "${results}/before.txt"

    if command -v strace > /dev/null; then
      strace -f -qq -e trace=openat -o "${results}/openat.txt" \
        "${root}/test/state-cache/run.sh" test/fixture "${results}/run"
      opened="$(grep -c "${pc}/parts-[^\"]*\.log\", O_RDONLY" "${results}/openat.txt" || true)"
      echo "the warm run opened recorded part files for reading ${opened} times" | tee -a "${results}/summary.txt"
      [ "${opened}" -gt 0 ] || { echo "::error::the warm run read no recorded part file"; exit 1; }
    else
      "${root}/test/state-cache/run.sh" test/fixture "${results}/run"
    fi
    check_layout "${results}"
    snapshot "${pc}" > "${results}/after.txt"
    python3 - "${pc}/index.db" <<'PY' | tee -a "${results}/summary.txt"
import sqlite3, sys
for path, checkout in sqlite3.connect(sys.argv[1]).execute("select path, checkout from documents order by path"):
    print(f"entry {path}: recorded for checkout {checkout}")
PY
    if diff -u "${results}/before.txt" "${results}/after.txt"; then
      echo "the warm run wrote no entry: every file it parsed came from the cache" | tee -a "${results}/summary.txt"
    else
      echo "::error::the warm run changed the parse cache"
      exit 1
    fi

    # A cold run of a fresh copy with its own empty parse cache and data root.
    "${root}/test/state-cache/cold-copy.sh" "${RUNNER_TEMP}/cold"
    (cd "${RUNNER_TEMP}/cold" && KAPI_PARSE_CACHE_DIR="${RUNNER_TEMP}/cold-parse" KAPI_DATA_DIR="${RUNNER_TEMP}/cold-data" \
      "${root}/test/state-cache/run.sh" test/fixture "${results}/cold-here")
    normalize "${results}/run"
    normalize "${results}/cold-here"
    normalize "${cold}/run"
    "${root}/test/state-cache/compare.sh" "${results}/cold-here.norm" "${results}/run.norm"
    "${root}/test/state-cache/compare.sh" "${cold}/run.norm" "${results}/run.norm"

    # Control: with one recorded part file damaged, kapi must notice and parse
    # that file again, which shows the warm run's entries were read and checked.
    ctl="${RUNNER_TEMP}/control-parse"
    rm -rf "${ctl}"
    cp -Rp "${pc}" "${ctl}"
    chmod 700 "${ctl}"
    # The entry for the source file every command reads; one byte changed.
    victim="$(python3 -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("select parts_ref from documents where path = ?", ("locales/en.json",)).fetchone()[0])' "${ctl}/index.db")"
    python3 -c 'import sys; p=sys.argv[1]; b=bytearray(open(p,"rb").read()); i=len(b)//2; b[i] = ord("Z") if b[i] != ord("Z") else ord("Y"); open(p,"wb").write(b)' "${ctl}/${victim}"
    snapshot "${ctl}" > "${results}/control-before.txt"
    "${root}/test/state-cache/cold-copy.sh" "${RUNNER_TEMP}/control"
    (cd "${RUNNER_TEMP}/control" && KAPI_PARSE_CACHE_DIR="${ctl}" KAPI_DATA_DIR="${RUNNER_TEMP}/control-data" \
      kapi status -p test/fixture/kapi.yaml --json > /dev/null)
    snapshot "${ctl}" > "${results}/control-after.txt"
    if diff -q "${results}/control-before.txt" "${results}/control-after.txt" > /dev/null; then
      echo "::error::kapi accepted a damaged part file"
      exit 1
    fi
    echo "control: with ${victim} damaged, kapi parsed that file again:" | tee -a "${results}/summary.txt"
    diff "${results}/control-before.txt" "${results}/control-after.txt" | tee -a "${results}/summary.txt" || true
    ;;

  refuse)
    results="$1"
    mkdir -p "${results}"
    for cmd in "status -p test/fixture/kapi.yaml" "up -p test/fixture/kapi.yaml --json"; do
      rc=0
      # shellcheck disable=SC2086  # the command is a word list
      kapi ${cmd} > "${results}/out.txt" 2>&1 || rc=$?
      echo "kapi ${cmd}: exit ${rc}" | tee -a "${results}/summary.txt"
      sed 's/^/  | /' "${results}/out.txt" | tail -n 5 | tee -a "${results}/summary.txt"
      [ "${rc}" -ne 0 ] || { echo "::error::kapi ${cmd} accepted the parse cache directory"; exit 1; }
    done
    ;;
esac
