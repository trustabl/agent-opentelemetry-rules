# `trustabl.tool_loop` → Grafana/Tempo

A worked, real translation of one runtime rule ([`../../rules/tool_loop.yaml`](../../rules/tool_loop.yaml))
into Grafana-native artifacts: [`dashboard.json`](dashboard.json) (a
Grafana dashboard JSON model) and [`alert-rule.yaml`](alert-rule.yaml) (a
Grafana alerting-rule provisioning file). Both files are hand-authored, to
prove the rule-IR-to-vendor-format mapping described below is mechanical —
see "Status" at the bottom for what's automated and what isn't.

## The mapping

| Rule IR field (`tool_loop.yaml`) | Grafana/TraceQL concept |
|---|---|
| `when.span: execute_tool` | Span filter: `span.gen_ai.operation.name="execute_tool"` |
| `when.condition.count_same: trustabl.tool.input_fp` | The TraceQL selector keys on `span.trustabl.tool.input_fp != ""`, and the surrounding `count_over_time(...)` aggregates occurrences of it |
| `when.window: last_5_tool_calls_in_run` | Approximated as a Tempo query range — memo §5.6's sketch uses `[5m]`; this is a time-window approximation of a call-count window, not an exact translation (see below) |
| `when.condition.gte: 3` | The alert rule's threshold expression: `type: threshold`, `evaluator: {type: gt, params: [3]}` |
| `title` | Alert rule `title` and dashboard panel `title` |
| `severity: high` | Alert rule `labels.severity` |
| `fix_class` | Alert rule `labels.fix_class` and `annotations.maps_to_static` context |
| `evidence` | Named in the alert's `annotations.description` as what to check on a firing span |

The source memo (§5.6) sketches this TraceQL query:

```
count_over_time({ span.gen_ai.operation.name="execute_tool"
  && span.trustabl.tool.input_fp != "" }[5m])
```

**Verified gap:** `count_over_time({...}[5m])` is a TraceQL *metrics*
aggregation query (Prometheus-style bracket-duration syntax). It requires
Tempo's `metrics_generator` component to be enabled and configured — which
is not the case in a default Tempo install or a minimal local demo stack.
Without `metrics_generator`, this query returns no data (the panel renders
empty, not an error). This was confirmed end-to-end: plain TraceQL search
queries work against the same Tempo instance; only the `count_over_time`
aggregation fails because `metrics_generator` is off.

**Resolution in `dashboard.json` (v2):** the dashboard panel was changed
from `timeseries` + `count_over_time` to a `table` panel using the plain
TraceQL search query:

```
{ span.gen_ai.operation.name="execute_tool" && span.trustabl.tool.input_fp != "" }
```

This works against any Tempo instance, with no metrics_generator required.
It also produces a more useful demo visualization: the table shows the raw
spans with their `input_fp` column, making the repeated-fingerprint loop
signal directly visible (rows 1, 3, 4 share the same value in the demo
trace) rather than just a count.

The `alert-rule.yaml` still uses the `count_over_time` query because alert
rules in a Grafana/Tempo setup that *does* have `metrics_generator` enabled
would correctly use the aggregation form. If your Tempo instance has
`metrics_generator` disabled, replace the alert rule's query with the plain
TraceQL form and trigger on `B threshold > 2` against a reduce expression.

## What this translation does not capture yet

- **`when.condition.side_effect_not: none`** is not expressed in the
  TraceQL query — the memo's own §5.6 sketch doesn't encode it either. A
  more complete query would add `&& span.trustabl.tool.side_effect != "none"`
  to the span filter. Left out to stay consistent with the memo's sketch;
  flagged so it isn't mistaken for a deliberate omission.
- **`when.window: last_5_tool_calls_in_run`** is a call-count window
  ("the last 5 tool calls"). The plain TraceQL search does not enforce this
  window at all — it returns any matching span in the selected time range.
  The `count_over_time` form approximates it as a 5-minute *time* window,
  which is not equivalent: an agent making tool calls faster or slower than
  roughly one per minute will see the approximation drift from the rule's
  actual intent. A true call-count window requires per-run grouping, which
  is not expressible in a single TraceQL query — it would need either a
  Tempo streaming pipeline rule or a Grafana transform over the raw spans.

## Status

Hand-authored, not generated. An actual translator that emits these two
files mechanically from `rules/*.yaml` + `../../attribute-profile.yaml` is
out of scope for this slice — natural follow-up work once there's a second
or third rule to translate and the mapping above is worth encoding as
code rather than prose.

Submitting these artifacts to Grafana's own catalog
(`grafana.com/grafana/dashboards/` or the plugin catalog) — creating/using
a Grafana Cloud org account, running their plugin/dashboard validator,
going through their review — is a separate, later step outside this repo
change. This directory only aims to produce artifacts already in the right
shape for that submission.
