# `trustabl.tool_loop` — LangSmith saved filter

**Speculative**, same caveat as the Phoenix and Dunetrace packs: the source
memo ("Process metadata, portable rules, and a policy control plane",
30 Aug 2026) gives LangSmith only "saved filter plus optional Insights
input" (§5.6), with no concrete filter string. The filter below is this
pack's approximation of LangSmith's documented filter-query grammar
(`and()` / `eq()` / `gt()` / `has()` style functions over run fields and
metadata), not a verified, tested-against-a-real-LangSmith-project query.
Field names for custom metadata in particular may not match your actual
LangSmith project's schema — verify against LangSmith's current filter
query documentation before using this for real.

## The filter

```
and(
  eq(run_type, "tool"),
  eq(metadata_key.gen_ai.tool.name, metadata_value),
  gte(metadata_key.trustabl.tool.attempt, 1)
)
```

Intent: runs of type `tool`, filtered down (manually, in the LangSmith UI,
by grouping/sorting on the `trustabl.tool.input_fp` metadata column) to
find repeats — LangSmith's filter grammar does not have a native
"count-same-value >= N in a window" primitive the way Grafana's TraceQL or
a Datadog rollup query do, so this is a **starting filter to narrow down
to candidate runs**, not a complete automated match for
`rules/tool_loop.yaml`'s condition. A human (or the optional "Insights"
clustering LangSmith offers) does the final "is this actually >= 3 in a
5-call window" judgment.

## The mapping

| Rule IR field (`tool_loop.yaml`) | LangSmith concept |
|---|---|
| `when.span: execute_tool` | `eq(run_type, "tool")` |
| `evidence: gen_ai.tool.name` | `metadata_key.gen_ai.tool.name` filter clause |
| `evidence: trustabl.tool.attempt` | `metadata_key.trustabl.tool.attempt` filter clause |
| `when.condition.count_same` / `gte: 3` | **Not expressible as a single filter** — left to manual review or LangSmith's Insights feature, per the memo's own framing ("saved filter *plus optional* Insights input") |

## Why this stays this thin — memo §6.4's explicit constraint

> "LangSmith | Filters Engine can read; we do not replace Engine | Custom
> metadata on runs if customers emit them"

LangSmith Engine already reads traces, clusters issues, and opens PRs
(memo §6.7). This pack deliberately does not try to replicate that — it's
a saved filter a human uses to narrow down candidates, not an automated
detector.
