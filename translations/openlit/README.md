# `trustabl.tool_loop` → OpenLIT / ClickHouse

A detection query for the `tool_loop` rule ([`../../rules/tool_loop.yaml`](../../rules/tool_loop.yaml))
targeting OpenLIT's ClickHouse backend. OpenLIT stores OTel span data via the
standard [OpenTelemetry ClickHouse Exporter](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/exporter/clickhouseexporter),
so the translation is a SQL query against `otel.otel_traces`.

## The mapping

| Rule IR field (`tool_loop.yaml`) | This query |
|---|---|
| `when.span: execute_tool` | `WHERE SpanName = 'execute_tool'` |
| `when.condition.side_effect_not: none` | `AND SpanAttributes['trustabl.tool.side_effect'] != 'none'` |
| `when.window: last_5_tool_calls_in_run` | `row_number() OVER (PARTITION BY run_id ORDER BY step_index DESC)` sliced to `rn <= 5` — an **exact** call-count window, not a time-window approximation |
| `when.condition.count_same: trustabl.tool.input_fp` | `GROUP BY run_id, input_fp` + `count(*)` |
| `when.condition.gte: 3` | `WHERE call_count >= 3` |
| `evidence` fields | `tool_name`, `attempt`, `input_fp`, `step_index` all selected |

**Window fidelity:** the ClickHouse `row_number()` window is a closer translation
of `last_5_tool_calls_in_run` than the Grafana or Datadog packs, which both
approximate it as a 5-minute time window. The ClickHouse query slices by call
count within the run — provided `trustabl.step_index` is monotonic and present
on every `execute_tool` span.

## How to use

Run [`query.sql`](query.sql) against the ClickHouse instance your OpenLIT
deployment writes to. Rows returned = rule fired; zero rows = clean.

```bash
clickhouse-client --query "$(cat query.sql)"
```

Adjust the `FROM` clause if your deployment uses a different database or table
name (common alternatives: `default.otel_traces`, `openlit.traces`). The
`INTERVAL 10 MINUTE` lookback window is a tunable — narrow it for a live
alert, widen it for a batch audit.

## Alerting

OpenLIT's built-in alert UI targets standard `gen_ai.*` cost/token metrics.
Custom span-attribute conditions like `trustabl.*` are not yet expressible
through the alert builder. The options:

1. **Schedule this query** as a ClickHouse scheduled task or a cron job that
   pages on non-empty results.
2. **Wire it into Grafana** (which can query ClickHouse directly via the
   ClickHouse data source plugin) and use the Grafana alert rule from
   [`../grafana/`](../grafana/) as the alerting layer.
3. **Use OpenLIT's API** if a future release adds custom-condition alert
   creation — the query above is the predicate to encode.

## Known gaps

- Table/database name varies by deployment — adjust the `FROM` clause.
- The `INTERVAL 10 MINUTE` lookback is a tunable, not part of the rule
  definition. Choose a value that fits your agent's expected run duration.
- `evidence` fields (`trustabl.tool.attempt`, `trustabl.step_index`) are
  selected but not joined back to the original span rows — a real integration
  would enrich the output with the full span context before surfacing it.

## Status

Hand-authored, not generated. Verified SQL syntax; not run against a live
OpenLIT instance. Confidence is **medium**: the ClickHouse OTel schema is
standardized and the query is straightforward SQL — higher confidence than
the Phoenix or LangSmith packs, lower than Grafana/Datadog because we haven't
confirmed against a real OpenLIT deployment.
