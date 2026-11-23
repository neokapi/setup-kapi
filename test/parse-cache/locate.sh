#!/usr/bin/env bash
# Runs scripts/parse-cache-dir.sh against the kapi stub in stub/ for each
# answer `kapi state path` can give, and asserts the mode and path it prints
# and what it leaves on disk. An answer the script does not accept must leave
# the file system as it was. With KAPI set to a kapi binary, it also runs the
# script against that binary on test/fixture and prints the mode it chose.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
root="$(cd "${here}/../.." && pwd -P)"
script="${root}/scripts/parse-cache-dir.sh"
work="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${work}"' EXIT

failures=0
fail() {
  echo "FAIL $1: $2"
  failures=$((failures + 1))
}
value() {
  sed -n "s/^$1=//p" "$2" | tail -n 1
}
# snapshot DIR lists everything beneath DIR, links included.
snapshot() {
  (cd "$1" && find . -not -name out -not -name err | LC_ALL=C sort)
}

key=0123456789abcdef0123456789abcdef

# run_case NAME OUTPUT [SET] [RUNNER_OS]: the stub prints OUTPUT (SET=0 makes
# it fail like a kapi without `state path`). The data root is NAME/data.
run_case() {
  local name="$1" output="$2" set="${3:-1}" os="${4:-Linux}"
  mkdir -p "${work}/${name}/project" "${work}/${name}/data"
  env PATH="${here}/stub:${PATH}" KAPI_STUB_STATE_SET="${set}" KAPI_STUB_STATE_OUTPUT="${output}" \
    KAPI_DATA_DIR="${work}/${name}/data" RUNNER_OS="${os}" \
    "${script}" "${work}/${name}/project" "${work}/${name}/fixed" \
    > "${work}/${name}/out" 2> "${work}/${name}/err" || fail "${name}" "exit code $?"
}

# expect_skip NAME OUTPUT [PREPARE]: the script carries no cache, prints a
# warning, and changes nothing on disk.
expect_skip() {
  local name="$1" output="$2"
  mkdir -p "${work}/${name}/data" "${work}/${name}/project"
  local before
  before="$(snapshot "${work}/${name}")"
  run_case "${name}" "${output}"
  [ "$(value mode "${work}/${name}/out")" = none ] || fail "${name}" "mode: $(cat "${work}/${name}/out")"
  [ -z "$(value path "${work}/${name}/out")" ] || fail "${name}" "printed a path"
  grep -q '::warning' "${work}/${name}/err" || fail "${name}" "printed no warning"
  [ "$(snapshot "${work}/${name}")" = "${before}" ] || fail "${name}" "changed the file system"
  [ ! -e "${work}/${name}/fixed" ] || fail "${name}" "created the fixed directory"
}

# A good path: the state directory's parse cache links to the fixed
# directory, and a write through it lands there.
state="${work}/good/data/checkouts/${key}"
run_case good "${state}"
[ "$(value mode "${work}/good/out")" = state ] || fail good "mode: $(cat "${work}/good/out")"
[ "$(value path "${work}/good/out")" = "${work}/good/fixed" ] || fail good "path: $(cat "${work}/good/out")"
[ -L "${state}/work/cache/docs" ] || fail good "work/cache/docs is not a link"
echo entry > "${state}/work/cache/docs/index.db"
[ -f "${work}/good/fixed/index.db" ] || fail good "a write through the link did not reach the fixed directory"
[ ! -e "${work}/good/project/.kapi" ] || fail good "wrote into the checkout"

# A kapi without `state path`: the parse cache stays in the checkout.
run_case tree "" 0
[ "$(value mode "${work}/tree/out")" = tree ] || fail tree "mode: $(cat "${work}/tree/out")"
[ "$(value path "${work}/tree/out")" = "${work}/tree/project/.kapi/work/cache/docs" ] || fail tree "path: $(cat "${work}/tree/out")"
[ ! -e "${work}/tree/fixed" ] || fail tree "created the fixed directory"

# Answers that are refused without touching anything.
expect_skip empty ""
expect_skip two-lines "${work}/two-lines/data/checkouts/${key}
${work}/two-lines/data/checkouts/${key}"
expect_skip relative "data/checkouts/${key}"
expect_skip outside "${work}/outside/elsewhere/checkouts/${key}"
expect_skip not-a-checkout "${work}/not-a-checkout/data/checkouts/../../.."
expect_skip control "${work}/control/data/checkouts/${key}$(printf '\t')"
mkdir -p "${work}/link/real/checkouts/${key}" "${work}/link/data"
ln -s "${work}/link/real/checkouts" "${work}/link/data/checkouts"
expect_skip link "${work}/link/data/checkouts/${key}"

# A link an earlier run left behind is replaced.
stale="${work}/stale/data/checkouts/${key}"
mkdir -p "${stale}/work/cache"
ln -s "${work}/elsewhere" "${stale}/work/cache/docs"
run_case stale "${stale}"
[ "$(value mode "${work}/stale/out")" = state ] || fail stale "mode: $(cat "${work}/stale/out")"
[ "$(readlink "${stale}/work/cache/docs")" = "${work}/stale/fixed" ] || fail stale "link: $(readlink "${stale}/work/cache/docs")"

# A parse cache the runner already holds is left alone and not restored over.
kept="${work}/kept/data/checkouts/${key}"
mkdir -p "${kept}/work/cache/docs"
echo entry > "${kept}/work/cache/docs/index.db"
run_case kept "${kept}"
[ "$(value mode "${work}/kept/out")" = none ] || fail kept "mode: $(cat "${work}/kept/out")"
[ -z "$(value path "${work}/kept/out")" ] || fail kept "printed a path"
[ -f "${kept}/work/cache/docs/index.db" ] && [ ! -L "${kept}/work/cache/docs" ] || fail kept "changed the existing cache"

# Windows: no link is made, and no cache is carried.
run_case windows "${work}/windows/data/checkouts/${key}" 1 Windows
[ "$(value mode "${work}/windows/out")" = none ] || fail windows "mode: $(cat "${work}/windows/out")"
[ ! -e "${work}/windows/data/checkouts" ] || fail windows "created the state directory"

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
