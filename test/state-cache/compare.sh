#!/usr/bin/env bash
# Compares two records written by run.sh: every command's exit code and
# normalized output, and the files the project held afterwards. Prints each
# difference and exits 1 when there is any.
#
# usage: compare.sh <record-a> <record-b>
set -uo pipefail
a=$1
b=$2
status=0
for name in status-before check-before ship-before up status-after check-after ship-after; do
  for ext in rc json; do
    diff -u "$a/$name.$ext" "$b/$name.$ext" || status=1
  done
done
diff -u "$a/tree.txt" "$b/tree.txt" || status=1
if [ "$status" -eq 0 ]; then
  echo "Identical: $a and $b"
fi
exit "$status"
