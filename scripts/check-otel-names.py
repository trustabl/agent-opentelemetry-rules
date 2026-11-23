#!/usr/bin/env python3
"""Fail if this repo uses a trustabl.* name that the labels spec does not define.

The labels SDK repo (trustabl/agent-reliability-otel-labels) owns spec/keys.json,
the contract every SDK binding tests against. This repo's rules, attribute
profile and translations must only name attributes and events that file defines.

Checks:
  1. Every trustabl.* token in rules/, attribute-profile.yaml, translations/ and
     scripts/ is defined in keys.json (attributes, events, event_attributes,
     not_emitted_here), is a rule id (rules/<id>.yaml), or is listed in
     scripts/otel-names-allowlist.txt with a reason.
  2. Allowlist entries need a reason, and fail once keys.json defines the name
     (a stale entry hides nothing and should be removed).
  3. Enum values: the attribute profile's enums for the keys.json enums must match
     exactly, and no side_effect line may use the old value "none".

Usage:
  LABELS_REPO=../agent-reliability-otel-labels python3 scripts/check-otel-names.py
Exit: 0 ok, 1 findings, 2 labels repo or keys.json not found.
"""
import json
import os
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
labels = Path(os.environ.get("LABELS_REPO", root.parent / "agent-reliability-otel-labels"))
keys_path = labels / "spec" / "keys.json"
if not keys_path.is_file():
    print(f"error: {keys_path} not found (set LABELS_REPO)", file=sys.stderr)
    sys.exit(2)

spec = json.loads(keys_path.read_text())
defined = set(spec["attributes"]) | set(spec["events"].values()) | set(spec["event_attributes"])
defined |= {k for k in spec["not_emitted_here"] if k.startswith("trustabl.")}
enums = spec["enums"]

# Allowlist: "name  # reason" or "prefix.*  # reason".
allow = {}
problems = []
allow_file = root / "scripts" / "otel-names-allowlist.txt"
for n, line in enumerate(allow_file.read_text().splitlines(), 1) if allow_file.exists() else []:
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    name, _, reason = line.partition("#")
    name, reason = name.strip(), reason.strip()
    if not reason:
        problems.append(f"allowlist line {n}: '{name}' has no reason")
    if name in defined:
        problems.append(f"allowlist line {n}: '{name}' is now in keys.json; remove the entry")
    allow[name] = reason

rule_ids = {f"trustabl.{p.stem}" for p in (root / "rules").glob("*.yaml")}
files = sorted(
    [p for d in ("rules", "translations", "scripts") for p in (root / d).rglob("*") if p.is_file()]
    + [root / "attribute-profile.yaml"]
)
files = [p for p in files if p.suffix not in (".pyc",) and p != Path(__file__).resolve()
         and p != allow_file]

token = re.compile(r"trustabl\.[A-Za-z0-9_.]*[A-Za-z0-9_]")
used = set()
for p in files:
    for n, line in enumerate(p.read_text(errors="replace").splitlines(), 1):
        for t in token.findall(line):
            if t in defined or t in rule_ids:
                continue
            if t in allow or any(a.endswith(".*") and t.startswith(a[:-1]) for a in allow):
                used.add(t)
                continue
            problems.append(f"{p.relative_to(root)}:{n}: '{t}' is not defined in {keys_path.name}")
        if re.search(r"side_effect", line) and re.search(r"""(?<![\w-])none(?![\w-])""", line) \
                and "non-" not in line.split("none")[0][-5:]:
            problems.append(f"{p.relative_to(root)}:{n}: side_effect uses 'none'; "
                            f"the spec value is 'pure'")

# Profile enums vs keys.json enums.
ENUM_FOR = {
    "trustabl.tool.side_effect": "side_effect",
    "trustabl.tool.error_class": "error_class",
    "trustabl.exit_reason": "exit_reason",
    "trustabl.policy.binding.type": "binding_type",
    "trustabl.policy.binding.source": "binding_source",
}
current = None
for n, line in enumerate((root / "attribute-profile.yaml").read_text().splitlines(), 1):
    m = re.match(r"\s*-?\s*name:\s*(\S+)", line)
    if m:
        current = m.group(1)
    m = re.match(r"\s*enum:\s*\[(.*)\]", line)
    if m and current in ENUM_FOR:
        got = {v.strip() for v in m.group(1).split(",")}
        want = set(enums[ENUM_FOR[current]])
        if got != want:
            problems.append(f"attribute-profile.yaml:{n}: {current} enum {sorted(got)} != "
                            f"keys.json {sorted(want)}")

for a in allow:
    if not any(t == a or (a.endswith(".*") and t.startswith(a[:-1])) for t in used):
        print(f"note: allowlist entry '{a}' is not used", file=sys.stderr)

if problems:
    print("\n".join(problems), file=sys.stderr)
    print(f"\n{len(problems)} problem(s). Names must come from {keys_path} "
          "or be allowlisted with a reason.", file=sys.stderr)
    sys.exit(1)
print(f"ok: {len(files)} files checked against {keys_path.name} "
      f"({len(defined)} defined names, {len(allow)} allowlisted)")
