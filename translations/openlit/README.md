# `trustabl.tool_loop` → OpenLIT / ClickHouse

A detection query for the `tool_loop` rule ([`../../rules/tool_loop.yaml`](../../rules/tool_loop.yaml))
targeting OpenLIT's ClickHouse backend. OpenLIT stores OTel span data via the
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

## P1 rule queries

Five more queries, one per active P1 rule. There is none for the shadow rules,
since no data exists for them yet. Each is a standalone file; run it like
`query.sql`. A run is a trace (`TraceId`); the root `invoke_agent` span only
exports when it ends, so a returned row means the run finished.

| Query | Rule | Fires when |
|---|---|---|
| [`goal_abandonment.sql`](goal_abandonment.sql) | `goal_abandonment` | 4 or more `chat` spans after the last `execute_tool` and `exit_reason` is not `final_answer` |
| [`premature_termination.sql`](premature_termination.sql) | `premature_termination` | `final_answer`, at least one but not all of `trustabl.expected_tools` called |
| [`no_progress.sql`](no_progress.sql) | `no_progress` | 3 consecutive tool steps (by `step_index`) with the same `trustabl.progress_marker` |
| [`empty_retrieval_answered.sql`](empty_retrieval_answered.sql) | `empty_retrieval_answered` | `final_answer` and the run's last retrieval has `trustabl.retrieval.result_count` = 0 |
| [`tool_avoidance.sql`](tool_avoidance.sql) | `tool_avoidance` | `final_answer`, expected tools declared, none called |

Notes:

- `trustabl.expected_tools` is an array attribute; the ClickHouse exporter
  stores it as a JSON string in the `SpanAttributes` map, so the queries use
  `JSONExtract(..., 'Array(String)')`. Confirm that on your deployment.
- Spans are matched by `SpanName` or `gen_ai.operation.name`.
- `goal_abandonment` and the chat count assume chat spans share the run's trace.
  Parent-child comparison, set difference and cross-span ordering are not in
  the rule IR, so the rule files name them as gaps and the SQL implements them.
- Tests: `tests/run_queries.py` loads synthetic spans (a fire and a silent case
  per rule, plus edge cases) into an embedded ClickHouse ([chdb](https://pypi.org/project/chdb/))
  using the exporter's table layout, and checks which runs each query returns.
  This is not OpenLIT's own deployment or a Docker ClickHouse server.

## Status

Hand-authored, not generated. The five P1 queries ran against synthetic
spans in chdb 4.5.1 (ClickHouse 26.11); `tool_loop` has verified SQL syntax only. Nothing
was run against a live OpenLIT instance. Confidence is **medium**: the ClickHouse OTel schema is
standardized and the query is straightforward SQL — higher confidence than
the Phoenix or LangSmith packs, lower than Grafana/Datadog because we haven't
confirmed against a real OpenLIT deployment.
