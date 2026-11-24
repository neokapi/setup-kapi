#!/usr/bin/env python3
"""Assert that a run that resolves save-cache to "no" saves no cache.

Every actions/cache step in action.yml must run only when the Resolve
save-cache step said yes, and have an actions/cache/restore twin, with the same
path and key, that runs otherwise. actions/cache saves in its post step;
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
    if "steps.save.outputs.save == 'true'" not in str(s.get("if", "")):
        failures.append(f"{name}: saves without the save-cache decision (its if: {s.get('if')!r})")
    twins = [r for r in restoring if r.get("with", {}).get("key") == s.get("with", {}).get("key")
             and r.get("with", {}).get("path") == s.get("with", {}).get("path")]
    if not any("steps.save.outputs.save != 'true'" in str(r.get("if", "")) for r in twins):
        failures.append(f"{name}: no actions/cache/restore twin that runs when save-cache says no")
text = open(sys.argv[1] if len(sys.argv) > 1 else "action.yml").read()
inputs = yaml.safe_load(text)["inputs"]
for name, spec in inputs.items():
    # GitHub refuses to load an action whose input description holds an
    # expression, or whose default holds one beyond `${{ github.token }}`.
    if "${{" in str(spec.get("description", "")):
        failures.append(f"input {name}: its description holds an expression, which GitHub refuses to load")
    default = str(spec.get("default", ""))
    if "${{" in default and default.strip() != "${{ github.token }}":
        failures.append(f"input {name}: its default holds an expression, which GitHub refuses to load")
for f in failures:
    print(f"FAIL {f}")
if failures:
    sys.exit(1)
print(f"ok: {len(saving)} saving cache step(s), each gated on the save-cache decision and twinned by a restore-only step")
