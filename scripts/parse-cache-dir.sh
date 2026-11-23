#!/usr/bin/env bash
# Decide which directory setup-kapi carries as kapi's parse cache, and prepare
# it before the cache is restored.
#
# Usage: parse-cache-dir.sh <project-dir> <fixed-dir>
# Prints: mode=<state|tree|none> and path=<directory to cache>, one per line,
#         for $GITHUB_OUTPUT. Notes for the job log go to stderr.
#
# A kapi that keeps each checkout's state outside the checkout answers
# `kapi state path -p <project-dir>` with that checkout's state directory. Its
# name comes from the checkout folder's identity, so a fresh runner gets a
# different one on every run, and actions/cache saves (in its post step) the
# path it was given at restore time. The cache therefore lives at a fixed
# directory under runner.temp, and the state directory's work/cache/docs is a
# link to it: kapi reads and writes the parse cache through the link, and the
# post step saves the fixed directory.
#
# A kapi without that command (1.3 and earlier) keeps the parse cache in the
# checkout, at <project-dir>/.kapi/work/cache/docs, and that path is cached.
set -euo pipefail

project_dir="$1"
fixed_dir="$2"

state_dir=""
if out="$(kapi state path -p "${project_dir}" 2> /dev/null)"; then
  state_dir="$(printf '%s\n' "${out}" | sed '/^[[:space:]]*$/d' | tail -n 1)"
fi

if [ -z "${state_dir}" ]; then
  echo "mode=tree"
  echo "path=${project_dir}/.kapi/work/cache/docs"
  exit 0
fi

case "${state_dir}" in
  /* | [A-Za-z]:[\\/]*) ;;
  *)
    echo "::warning title=setup-kapi::kapi state path printed '${state_dir}', which is not an absolute path; the parse cache is not carried." >&2
    echo "mode=none"
    exit 0
    ;;
esac

if [ "${RUNNER_OS:-}" = "Windows" ]; then
  echo "setup-kapi: the parse cache is not carried on Windows with a kapi that keeps its state outside the checkout." >&2
  echo "mode=none"
  exit 0
fi

docs="${state_dir}/work/cache/docs"
if [ -L "${docs}" ]; then
  # A link an earlier setup-kapi run left on a runner that keeps its data.
  rm "${docs}"
elif [ -e "${docs}" ]; then
  # A runner that keeps kapi's data between jobs already holds the cache.
  echo "setup-kapi: ${docs} already exists on this runner, so the parse cache is not restored over it." >&2
  echo "mode=none"
  exit 0
fi

mkdir -p "${fixed_dir}" "${state_dir}/work/cache"
ln -s "${fixed_dir}" "${docs}"
echo "setup-kapi: kapi keeps this checkout's state in ${state_dir}; its parse cache is carried through ${fixed_dir}." >&2
echo "mode=state"
echo "path=${fixed_dir}"
