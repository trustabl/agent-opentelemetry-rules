# `trustabl.tool_loop` → Arize Phoenix

**This pack is speculative — more so than Grafana, Langfuse, or Datadog.**
The source memo ("Process metadata, portable rules, and a policy control
plane", 30 Aug 2026) gives Phoenix only a one-line description at §5.6:
*"Phoenix: evaluator over span attributes."* No concrete evaluator shape
is given. Everything in [`evaluator.py`](evaluator.py) — the pandas-based
structure, the function signature, the flattened-column naming assumption —
is this pack's own construction, not a memo transcription, and it has not
been run against a real Phoenix instance or a real Phoenix span export.

## Why a Python function, not a query string

Phoenix's evaluator mechanism (per Phoenix's own public docs, not the
memo) typically operates on a dataframe of spans rather than a query
language like Grafana's TraceQL or Datadog's log-query DSL. This evaluator
is deterministic and structural — matching Trustabl's "process metadata,
not content" stance (memo §4.3) — not an LLM-as-judge evaluator, which is
Phoenix's more commonly documented eval pattern.

## The mapping

| Rule IR field (`tool_loop.yaml`) | This evaluator |
|---|---|
| `when.span: execute_tool` | Filters `spans_df` to `attributes.gen_ai.operation.name == "execute_tool"` |
| `when.condition.side_effect_not: none` | Filters out rows where `attributes.trustabl.tool.side_effect == "none"` |
| `when.window: last_5_tool_calls_in_run` | Approximated via `.groupby(run_id).tail(5)` — a true count-based window per run, closer to the rule's actual intent than the time-window approximation used in the Grafana/Datadog packs, but still dependent on `trustabl.step_index` sort order being correct |
| `when.condition.count_same: trustabl.tool.input_fp` | `.groupby([run_id, input_fp]).size()` |
| `when.condition.gte: 3` | `THRESHOLD = 3` |
| `evidence` | Not currently attached to the output rows — a real integration would join `fired` back to `gen_ai.tool.name` / `trustabl.tool.attempt` from the original span rows before surfacing it |

## What this does not capture

- Column names (`attributes.gen_ai.operation.name`, etc.) are a guess at
  how a Phoenix span export flattens OTel attributes — adjust to match
  your actual Phoenix instance's schema.
- No handling of `evidence` field attachment (noted above).
- Not wired into any Phoenix eval-registration API — this is a bare
  function, not a registered Phoenix `Evaluator` object.

## Status

Speculative, hand-authored, unverified. Treat this as a starting sketch of
what a Phoenix translation could look like, not a working integration.
