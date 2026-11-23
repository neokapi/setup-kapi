#!/usr/bin/env bash
# Runs scripts/parse-cache-dir.sh against the kapi stub in stub/ for each case
# it handles, and asserts the mode and path it prints and what it leaves on
# disk. With KAPI set to a kapi binary, it also runs the script against that
# binary on test/fixture and prints the mode it chose.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
script="${root}/scripts/parse-cache-dir.sh"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

failures=0
fail() {
  echo "FAIL $1: $2"
  failures=$((failures + 1))
}
value() {
  sed -n "s/^$1=//p" "$2" | tail -n 1
}

# run_case NAME STATE_DIR [RUNNER_OS] runs the script with the stub printing
# STATE_DIR (empty: the stub fails like a kapi without `state path`).
run_case() {
  local name="$1" state="$2" os="${3:-Linux}"
  mkdir -p "${work}/${name}/project"
  env PATH="${here}/stub:${PATH}" KAPI_STUB_STATE_DIR="${state}" RUNNER_OS="${os}" \
    "${script}" "${work}/${name}/project" "${work}/${name}/fixed" \
    > "${work}/${name}/out" 2> "${work}/${name}/err" || fail "${name}" "exit code $?"
}

# A kapi that keeps state outside the checkout: the state directory's parse
# cache links to the fixed directory, and a write through it lands there.
state="${work}/state/data/checkouts/abc"
run_case state "${state}"
[ "$(value mode "${work}/state/out")" = state ] || fail state "mode: $(cat "${work}/state/out")"
[ "$(value path "${work}/state/out")" = "${work}/state/fixed" ] || fail state "path: $(cat "${work}/state/out")"
[ -L "${state}/work/cache/docs" ] || fail state "work/cache/docs is not a link"
echo entry > "${state}/work/cache/docs/index.db"
[ -f "${work}/state/fixed/index.db" ] || fail state "a write through the link did not reach the fixed directory"
[ ! -e "${work}/state/project/.kapi" ] || fail state "wrote into the checkout"

# A kapi without `state path`: the parse cache stays in the checkout.
run_case tree ""
[ "$(value mode "${work}/tree/out")" = tree ] || fail tree "mode: $(cat "${work}/tree/out")"
[ "$(value path "${work}/tree/out")" = "${work}/tree/project/.kapi/work/cache/docs" ] || fail tree "path: $(cat "${work}/tree/out")"
[ ! -e "${work}/tree/fixed" ] || fail tree "created the fixed directory"

# A link an earlier run left behind is replaced.
stale="${work}/stale/data/checkouts/abc"
mkdir -p "${stale}/work/cache"
ln -s "${work}/elsewhere" "${stale}/work/cache/docs"
run_case stale "${stale}"
[ "$(value mode "${work}/stale/out")" = state ] || fail stale "mode: $(cat "${work}/stale/out")"
[ "$(readlink "${stale}/work/cache/docs")" = "${work}/stale/fixed" ] || fail stale "link: $(readlink "${stale}/work/cache/docs")"

# A parse cache the runner already holds is left alone and not restored over.
kept="${work}/kept/data/checkouts/abc"
mkdir -p "${kept}/work/cache/docs"
echo entry > "${kept}/work/cache/docs/index.db"
run_case kept "${kept}"
[ "$(value mode "${work}/kept/out")" = none ] || fail kept "mode: $(cat "${work}/kept/out")"
[ -z "$(value path "${work}/kept/out")" ] || fail kept "printed a path"
[ -f "${kept}/work/cache/docs/index.db" ] && [ ! -L "${kept}/work/cache/docs" ] || fail kept "changed the existing cache"

# A relative answer is not trusted.
run_case relative "data/checkouts/abc"
[ "$(value mode "${work}/relative/out")" = none ] || fail relative "mode: $(cat "${work}/relative/out")"
[ -z "$(value path "${work}/relative/out")" ] || fail relative "printed a path"

# Windows: no link is made, and no cache is carried.
run_case windows "${work}/windows/data/checkouts/abc" Windows
[ "$(value mode "${work}/windows/out")" = none ] || fail windows "mode: $(cat "${work}/windows/out")"
[ ! -e "${work}/windows/data" ] || fail windows "created the state directory"

if [ -n "${KAPI:-}" ]; then
  bin="${work}/bin"
  mkdir -p "${bin}"
  ln -s "${KAPI}" "${bin}/kapi"
  cp -R "${root}/test/fixture" "${work}/real"
  PATH="${bin}:${PATH}" "${script}" "${work}/real" "${work}/real-fixed" | sed "s|${work}|<tmp>|; s/^/real kapi: /"
fi

if [ "${failures}" -gt 0 ]; then
  echo "${failures} assertion(s) failed"
  exit 1
fi
echo "all parse cache locations passed"
