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

# skip REASON: carry no parse cache, touch nothing, and say why.
skip() {
  echo "::warning title=setup-kapi::The parse cache is not carried: $1" >&2
  echo "mode=none"
  exit 0
}

# data_root prints the data root kapi uses, by the rule kapi applies:
# KAPI_DATA_DIR, then XDG_DATA_HOME/kapi, then the platform default.
data_root() {
  if [ -n "${KAPI_DATA_DIR:-}" ]; then
    printf '%s\n' "${KAPI_DATA_DIR%/}"
  elif [ -n "${XDG_DATA_HOME:-}" ]; then
    printf '%s\n' "${XDG_DATA_HOME%/}/kapi"
  elif [ "${RUNNER_OS:-}" = "macOS" ] || [ "$(uname -s)" = "Darwin" ]; then
    printf '%s\n' "${HOME%/}/Library/Application Support/kapi"
  else
    printf '%s\n' "${HOME%/}/.local/share/kapi"
  fi
}

if ! out="$(kapi state path -p "${project_dir}" 2> /dev/null)"; then
  # A kapi without the command keeps the parse cache in the checkout.
  echo "mode=tree"
  echo "path=${project_dir}/.kapi/work/cache/docs"
  exit 0
fi

if [ "${RUNNER_OS:-}" = "Windows" ]; then
  echo "setup-kapi: the parse cache is not carried on Windows with a kapi that keeps its state outside the checkout." >&2
  echo "mode=none"
  exit 0
fi

# Accept the answer only when it names this checkout's state directory under
# kapi's data root: one line, an absolute path without control characters,
# shaped <data root>/checkouts/<32 hex digits>, with no link on the way.
if [ -z "${out}" ]; then
  skip "kapi state path printed nothing."
fi
if [ "$(printf '%s\n' "${out}" | wc -l | tr -d ' ')" != 1 ]; then
  skip "kapi state path printed more than one line."
fi
state_dir="${out}"
if printf '%s' "${state_dir}" | LC_ALL=C grep -q '[[:cntrl:]]'; then
  skip "kapi state path printed a control character."
fi
case "${state_dir}" in
  /*) ;;
  *) skip "kapi state path printed a path that is not absolute." ;;
esac
root="$(data_root)"
case "${state_dir}" in
  "${root}/checkouts/"*) ;;
  *) skip "kapi state path printed a directory outside kapi's data root (${root})." ;;
esac
name="${state_dir#"${root}/checkouts/"}"
if ! printf '%s' "${name}" | LC_ALL=C grep -Eqx '[0-9a-f]{32}'; then
  skip "kapi state path printed a directory that is not a checkout's state directory."
fi
check="${state_dir}/work/cache/docs"
while [ -n "${check}" ] && [ "${check}" != "/" ]; do
  if [ -L "${check}" ] && [ "${check}" != "${state_dir}/work/cache/docs" ]; then
    skip "${check} is a symbolic link."
  fi
  check="$(dirname "${check}")"
done

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
