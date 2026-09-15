#!/usr/bin/env bash
# Extracts the committed fixture into a fresh directory, so a cold run sees
# exactly what a checkout holds and no state from any earlier run.
#
# usage: cold-copy.sh <dest>   (the project lands in <dest>/test/fixture)
set -euo pipefail
rm -rf "$1"
mkdir -p "$1"
git archive HEAD test/fixture | tar -x -C "$1"
