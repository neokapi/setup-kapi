#!/usr/bin/env python3
"""Assert that save-cache: 'false' saves no cache.

Every actions/cache step in action.yml must run only when save-cache is not
'false', and have an actions/cache/restore twin, with the same path and key,
that runs when it is. actions/cache saves in its post step;
actions/cache/restore never saves.
"""
import sys

import yaml

steps = yaml.safe_load(open(sys.argv[1] if len(sys.argv) > 1 else "action.yml"))["runs"]["steps"]
saving = [s for s in steps if str(s.get("uses", "")).startswith("actions/cache@")]
restoring = [s for s in steps if str(s.get("uses", "")).startswith("actions/cache/restore@")]
failures = []
if not saving:
    failures.append("no actions/cache step found")
for s in saving:
    name = s.get("name")
    if "inputs.save-cache != 'false'" not in str(s.get("if", "")):
        failures.append(f"{name}: saves even with save-cache 'false' (its if: {s.get('if')!r})")
    twins = [r for r in restoring if r.get("with", {}).get("key") == s.get("with", {}).get("key")
             and r.get("with", {}).get("path") == s.get("with", {}).get("path")]
    if not any("inputs.save-cache == 'false'" in str(r.get("if", "")) for r in twins):
        failures.append(f"{name}: no actions/cache/restore twin that runs with save-cache 'false'")
for f in failures:
    print(f"FAIL {f}")
if failures:
    sys.exit(1)
print(f"ok: {len(saving)} saving cache step(s), each skipped with save-cache 'false' and twinned by a restore-only step")
