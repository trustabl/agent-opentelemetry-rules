# Trustabl rules → OpenLIT / ClickHouse

Detection queries for five rules, one SQL file each:

| Rule | Query |
|---|---|
| `tool_loop` | [`query.sql`](query.sql) |
| `retry_storm` | [`query-retry_storm.sql`](query-retry_storm.sql) |
| `false_idempotent` | [`query-false_idempotent.sql`](query-false_idempotent.sql) |
| `policy_absent` | [`query-policy_absent.sql`](query-policy_absent.sql) |
| `handoff_unbound` | [`query-handoff_unbound.sql`](query-handoff_unbound.sql) |

The rest of this page describes the `tool_loop` query
([`../../rules/tool_loop.yaml`](../../rules/tool_loop.yaml)); the others follow the same
pattern and carry their own notes in the SQL header. Table layout is taken from OpenLIT's
`assets/clickhouse-init.sh` at commit `463a1c1b3cd72a94fab4155efe0f28d90d87fe95`. Span events
(the `trustabl.policy.binding` events that `policy_absent` and `handoff_unbound` read) are
stored as the parallel arrays `Events.Name` / `Events.Attributes`.

The queries target OpenLIT's ClickHouse backend. OpenLIT stores OTel span data via the
standard [OpenTelemetry ClickHouse Exporter](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/exporter/clickhouseexporter),
so the translation is a SQL query against `otel.otel_traces`.

## The mapping

| Rule IR field (`tool_loop.yaml`) | This query |
|---|---|
| `when.span: execute_tool` | `WHERE SpanName = 'execute_tool'` |
| `when.condition.side_effect_not: pure` | `AND SpanAttributes['trustabl.tool.side_effect'] != 'pure'` |
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

Hand-authored, not generated. All five queries were run against a ClickHouse engine (chdb
4.5.1, embedded, not Docker: the Docker daemon was not running) using OpenLIT's exact
`otel_traces` DDL and synthetic spans, one fire case and one silent case per rule; each fired
only on its fire case. Not run against a live OpenLIT deployment or a real SDK trace.

`policy_absent` reads `absent_binding_type: [sandbox, content_safety]` as "neither type is
present" (see the SQL header). It therefore also fires on a handoff span that has only, say, a
`custom` binding. The queries accept span names `execute_tool` / `execute_tool <tool>` and
`invoke_agent` / `invoke_agent <agent>`, or `gen_ai.operation.name` set to the same.
