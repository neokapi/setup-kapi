#!/usr/bin/env bash
# Unit test of scripts/save-cache-decision.sh over fabricated events.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
decide="$here/scripts/save-cache-decision.sh"
failed=0

check() {
  local want="$1" input="$2" event="$3" ref="$4" default="$5" got
  got="$(INPUT_SAVE_CACHE="$input" EVENT_NAME="$event" REF="$ref" DEFAULT_BRANCH="$default" bash "$decide" 2>/dev/null)" || got="error"
  if [ "$got" = "$want" ]; then
    echo "ok   $input $event $ref default=$default -> $got"
  else
    echo "FAIL $input $event $ref default=$default -> $got, want $want"
    failed=1
  fi
}

check true  true           pull_request refs/pull/1/merge main
check false false          push         refs/heads/main   main
check true  default-branch push         refs/heads/main   main
check true  default-branch push         refs/heads/trunk  trunk
check false default-branch push         refs/heads/main   trunk
check false default-branch pull_request refs/pull/1/merge main
check true  default-branch schedule     refs/heads/main   ""
check false default-branch workflow_run refs/heads/main   ""
check true  default-branch workflow_dispatch refs/heads/main main
check false default-branch workflow_dispatch refs/heads/feature main
check error maybe          push         refs/heads/main   main
exit "$failed"
