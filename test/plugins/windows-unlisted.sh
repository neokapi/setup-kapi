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
# kapi words this refusal in one of two ways. Up to 1.4.0-rc5 it prints
# `no version of plugin "bowrain" ... for platform windows/<arch>`. Later
# versions name the deciding reason: `plugin "bowrain" has no build for
# windows/<arch>`. Any other failure (the network, a kapi too old for every
# listed version) is not the state this script asserts.
earlier() {
  grep -q 'no version of plugin "bowrain"' <<< "${out}" && grep -q 'for platform windows/' <<< "${out}"
}
later() {
  grep -q 'plugin "bowrain" has no build for windows/' <<< "${out}"
}
if ! earlier && ! later; then
  echo "::error::bowrain failed to install on Windows for a reason other than a missing Windows build."
  exit 1
fi
echo "As expected: no bowrain build is listed for Windows."
