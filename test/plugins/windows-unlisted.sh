#!/usr/bin/env bash
# Asserts that the registry lists no bowrain plugin build for Windows: a
# default install fails and names the platform. registry#6 left Windows
# without a listed build until the next kapi release, by decision. When this
# script fails because the install succeeds, a Windows build is listed again:
# restore the default `plugins` input in the Windows jobs and delete this
# script.
set -uo pipefail

out="$(kapi plugin install bowrain 2>&1)"
rc=$?
echo "${out}"
if [ "${rc}" -eq 0 ]; then
  echo "::error::bowrain installed on Windows, so a Windows build is listed again. Restore the default plugins input in the Windows jobs and delete test/plugins/windows-unlisted.sh."
  exit 1
fi
if ! grep -q 'no version of plugin "bowrain"' <<< "${out}" || ! grep -q 'for platform windows/' <<< "${out}"; then
  echo "::error::bowrain failed to install on Windows for a reason other than a missing Windows build."
  exit 1
fi
echo "As expected: no bowrain build is listed for Windows."
