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
  [ ! -e "${temp}" ] || fail "${name}" "created a directory"
  if [ "${failures}" = "${before}" ]; then
    echo "ok   ${name}"
  fi
}

run_case unset "" "${temp}/kapi-parse-cache" "KAPI_PARSE_CACHE_DIR=${temp}/kapi-parse-cache" no
run_case preset-temp "${temp}/mine" "${temp}/mine" "" no
run_case preset-workspace "${workspace}/.cache/kapi" "${workspace}/.cache/kapi" "" no
run_case preset-outside "/home/runner/.cache/kapi" "" "" yes
run_case preset-relative "kapi-parse-cache" "" "" yes
run_case preset-dotdot "${temp}/../elsewhere" "" "" yes
run_case preset-prefix "${temp}-other/cache" "" "" yes

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
