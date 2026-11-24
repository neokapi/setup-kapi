#!/usr/bin/env bash
# Decide whether this run saves the caches, from the save-cache input.
#
#   true             saves on every run
#   false            never saves (restore only)
#   default-branch   saves on a run of the default branch: a push or dispatch
#                    whose ref is refs/heads/<default branch>, or a schedule
#                    run, which GitHub runs on the default branch only and
#                    whose payload names no repository. Any run where the
#                    branch cannot be told does not save.
#
# Reads INPUT_SAVE_CACHE, EVENT_NAME, REF and DEFAULT_BRANCH; prints true or
# false. Exits 2 on any other input value.
set -euo pipefail

case "${INPUT_SAVE_CACHE:-}" in
  true) echo true ;;
  false) echo false ;;
  default-branch)
    if [ "${EVENT_NAME:-}" = schedule ]; then
      echo true
    elif [ -n "${DEFAULT_BRANCH:-}" ] && [ "${REF:-}" = "refs/heads/${DEFAULT_BRANCH}" ]; then
      echo true
    else
      echo false
    fi
    ;;
  *)
    echo "save-cache must be true, false or default-branch, not '${INPUT_SAVE_CACHE:-}'" >&2
    exit 2
    ;;
esac
