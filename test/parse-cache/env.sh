#!/usr/bin/env bash
# Runs the action's "Set kapi parse cache directory" step, read out of
# action.yml, for each value KAPI_PARSE_CACHE_DIR can have when the step
# starts, and asserts what it exports and outputs. Then it asserts that both
# parse cache steps carry the directory the step names and the in-tree path a
# kapi up to 1.3 uses. Needs yq (v4).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

yq '.runs.steps[] | select(.id == "parse-cache-dir") | .run' "${root}/action.yml" > "${work}/step.sh"
if ! grep -q KAPI_PARSE_CACHE_DIR "${work}/step.sh"; then
  echo "could not read the parse-cache-dir step out of action.yml" >&2
  exit 1
fi

failures=0
fail() {
  echo "FAIL $1: $2"
  failures=$((failures + 1))
}

temp="${work}/runner-temp"
workspace="${work}/workspace"

# run_case NAME PRESET WANT_DIR WANT_ENV WANT_WARNING: PRESET is the value of
# KAPI_PARSE_CACHE_DIR before the step ("" for unset). WANT_ENV is the line the
# step must append to GITHUB_ENV ("" for none). WANT_WARNING is "yes" or "no".
run_case() {
  local name="$1" preset="$2" want_dir="$3" want_env="$4" want_warning="$5"
  local dir="${work}/cases/${name}"
  mkdir -p "${dir}"
  : > "${dir}/env"
  : > "${dir}/output"
  local rc=0
  if [ -n "${preset}" ]; then
    env KAPI_PARSE_CACHE_DIR="${preset}" FIXED_DIR="${temp}/kapi-parse-cache" \
      RUNNER_TEMP="${temp}" GITHUB_WORKSPACE="${workspace}" \
      GITHUB_ENV="${dir}/env" GITHUB_OUTPUT="${dir}/output" \
      bash -e "${work}/step.sh" > "${dir}/stdout" 2>&1 || rc=$?
  else
    env -u KAPI_PARSE_CACHE_DIR FIXED_DIR="${temp}/kapi-parse-cache" \
      RUNNER_TEMP="${temp}" GITHUB_WORKSPACE="${workspace}" \
      GITHUB_ENV="${dir}/env" GITHUB_OUTPUT="${dir}/output" \
      bash -e "${work}/step.sh" > "${dir}/stdout" 2>&1 || rc=$?
  fi
  local before="${failures}"
  [ "${rc}" = 0 ] || fail "${name}" "exit code ${rc}"
  local got
  got="$(sed -n 's/^dir=//p' "${dir}/output")"
  [ "${got}" = "${want_dir}" ] || fail "${name}" "dir: got '${got}', want '${want_dir}'"
  got="$(cat "${dir}/env")"
  [ "${got}" = "${want_env}" ] || fail "${name}" "GITHUB_ENV: got '${got}', want '${want_env}'"
  if [ "${want_warning}" = yes ]; then
    grep -q '^::warning' "${dir}/stdout" || fail "${name}" "printed no warning"
  else
    ! grep -q '^::warning' "${dir}/stdout" || fail "${name}" "unexpected warning: $(cat "${dir}/stdout")"
  fi
  if [ -z "${want_dir}" ] && [ -s "${dir}/output" ]; then
    fail "${name}" "wrote outputs: $(cat "${dir}/output")"
  fi
  [ ! -e "${temp}" ] || fail "${name}" "created a directory"
  if [ "${failures}" = "${before}" ]; then
    echo "ok   ${name}"
  fi
}

run_case unset "" "${temp}/kapi-parse-cache" "KAPI_PARSE_CACHE_DIR=${temp}/kapi-parse-cache" no
run_case preset-temp "${temp}/mine" "${temp}/mine" "" no
run_case preset-workspace "${workspace}/.cache/kapi" "" "" yes
run_case preset-outside "/home/runner/.cache/kapi" "" "" yes
run_case preset-relative "kapi-parse-cache" "" "" yes
run_case preset-dotdot "${temp}/../elsewhere" "" "" yes
run_case preset-prefix "${temp}-other/cache" "" "" yes
run_case preset-newline "${temp}/x
dir=/etc/ssl" "" "" yes
run_case preset-cr "${temp}/x$(printf '\r')" "" "" yes
run_case preset-temp-itself "${temp}" "" "" yes
run_case preset-temp-slash "${temp}/" "" "" yes
run_case preset-temp-dot "${temp}/." "" "" yes
run_case preset-temp-dots "${temp}/./" "" "" yes
run_case preset-temp-nested "${temp}/a/./b" "${temp}/a/./b" "" no

# The auth step writes each value with a random delimiter, so a line break in
# a token cannot add another variable.
yq '.runs.steps[] | select(.name == "Configure auth") | .run' "${root}/action.yml" > "${work}/auth.sh"
: > "${work}/auth.env"
env INPUT_AUTH_TOKEN="tok
BASH_ENV=/tmp/evil" INPUT_SERVER="https://example.invalid" GITHUB_ENV="${work}/auth.env" \
  bash -e "${work}/auth.sh" > /dev/null
names="$(awk 'd != "" { if ($0 == d) d = ""; next } /<</ { i = index($0, "<<"); print substr($0, 1, i - 1); d = substr($0, i + 2); next } /=/ { print substr($0, 1, index($0, "=") - 1) }' "${work}/auth.env" | tr '\n' ' ')"
if [ "${names}" = "BOWRAIN_AUTH_TOKEN BOWRAIN_SERVER_URL " ]; then
  echo "ok   auth: a line break in the token sets no other variable"
else
  fail auth "variables set: ${names}"
fi
masks="$(env INPUT_AUTH_TOKEN="tok
BASH_ENV=/tmp/evil
" INPUT_SERVER="" GITHUB_ENV=/dev/null bash -e "${work}/auth.sh" | grep '^::add-mask::' | tr '\n' ' ')"
if [ "${masks}" = "::add-mask::tok ::add-mask::BASH_ENV=/tmp/evil " ]; then
  echo "ok   auth: each line of the token is masked"
else
  fail auth-mask "mask commands: '${masks}'"
fi

# parse-cache and cache-tm turn the cache off on 'false' in any case, as v1's
# expression did, and on nothing else.
yq '.runs.steps[] | select(.id == "parse-cache") | .run' "${root}/action.yml" > "${work}/enabled.sh"
# enabled_case PARSE_CACHE CACHE_TM WANT
enabled_case() {
  : > "${work}/enabled.out"
  env INPUT_PARSE_CACHE="$1" INPUT_CACHE_TM="$2" GITHUB_OUTPUT="${work}/enabled.out" \
    bash -e "${work}/enabled.sh" > /dev/null
  local got
  got="$(cat "${work}/enabled.out")"
  if [ "${got}" = "enabled=$3" ]; then
    echo "ok   parse-cache='$1' cache-tm='$2': $3"
  else
    fail enabled "parse-cache='$1' cache-tm='$2': got '${got}', want 'enabled=$3'"
  fi
}
for value in false False FALSE; do
  enabled_case "${value}" "" false
  enabled_case true "${value}" false
done
enabled_case true "" true
enabled_case false true true
enabled_case "no" "" true


# Both parse cache steps carry the directory the step names and the in-tree
# path, as fixed strings.
for name in "Restore kapi parse cache" "Restore kapi parse cache (no save)"; do
  paths="$(NAME="${name}" yq '.runs.steps[] | select(.name == strenv(NAME)) | .with.path' "${root}/action.yml")"
  # shellcheck disable=SC2016  # the literal expression text in action.yml
  want='${{ steps.parse-cache-dir.outputs.dir }}
${{ inputs.project-dir }}/.kapi/work/cache/docs'
  if [ "${paths}" = "${want}" ]; then
    echo "ok   ${name}: both paths"
  else
    fail "${name}" "path: got '${paths}'"
  fi
done

if [ "${failures}" -gt 0 ]; then
  echo "${failures} assertion(s) failed"
  exit 1
fi
echo "all parse cache directory cases passed"
