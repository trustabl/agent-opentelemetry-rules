# `trustabl.tool_loop` → Dunetrace

**This pack is more speculative than the Grafana/Langfuse/Datadog ones.**
The source memo ("Process metadata, portable rules, and a policy control
plane", 30 Aug 2026) gives Dunetrace only a one-line description — "Ship
detectors.yml mapping" (§6.3) and "Dunetrace: detectors.yml adapter mapping
trustabl.tool_loop to TOOL_LOOP with the fingerprint field" (§5.6) — with no
concrete schema. [`detectors.yml`](detectors.yml) is this pack's own
construction of what that mapping could look like; it is **not verified**
against Dunetrace's actual, real `detectors.yml` format, which this repo
has no access to.

## Why this is an adapter, not a new rule

Per memo §2.3 and §4.5, Dunetrace (Apache 2.0) already ships its own ~34
zero-LLM structural detectors, including a `TOOL_LOOP` detector for exactly
this pattern. Trustabl's value here isn't a competing rule — it's richer
OTel attributes (`trustabl.tool.input_fp`, `trustabl.step_index`, policy
bindings) that make Dunetrace's *existing* detector exact instead of
approximate when it ingests OTLP. `detectors.yml` is meant to be a mapping
telling Dunetrace's `TOOL_LOOP` detector which trustabl.* field to key on —
not a Trustabl-authored detector Dunetrace would run standalone.

## The mapping (as designed here, not confirmed against Dunetrace)

| Rule IR field (`tool_loop.yaml`) | This adapter's field |
|---|---|
| `id` | `trustabl_rule_id` |
| `when.condition.count_same: trustabl.tool.input_fp` | `fingerprint_field` |
| `when.window` | `window` |
| `when.condition.gte` | `threshold` |
| `when.condition.side_effect_not` | `exclude_side_effect` |
| `severity` | `severity` |
| `evidence` | `evidence` |

## Status

Speculative, hand-authored, unverified against Dunetrace's real schema.
Before this is used for anything real, someone would need to check
Dunetrace's actual `detectors.yml` reference (not available to this repo)
and correct the field names/shape to match.
