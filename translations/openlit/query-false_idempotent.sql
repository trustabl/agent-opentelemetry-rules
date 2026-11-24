-- trustabl.false_idempotent -> OpenLIT / ClickHouse
--
-- Rule source: ../../rules/false_idempotent.yaml
-- Fires when, inside one run (window: same_run_id), a tool declared
-- side_effect=pure was called with the same input fingerprint and produced
-- more than one distinct output fingerprint.
-- Spans without an output_fp are ignored: the SDK omits the key when the
-- result has no canonical form, which means "unknown", not "different".
-- Schema: OpenLIT ClickHouse init script, assets/clickhouse-init.sh at
--   github.com/openlit/openlit commit 463a1c1b3cd72a94fab4155efe0f28d90d87fe95
--   (table `otel_traces`, the OpenTelemetry ClickHouse exporter layout).
-- Types: SpanAttributes is Map(String, String), so integers and booleans are
--   strings; cast with toUInt32OrZero(). Span events are stored as parallel
--   arrays: `Events.Name` and `Events.Attributes` (Array(Map(String,String))),
--   one entry per event, same index. Read one with arrayExists(i -> ..., arrayEnumerate(`Events.Name`)).
-- Span match: the rule says span "execute_tool"/"invoke_agent" (gen_ai.operation.name).
--   Instrumentors name the span either "execute_tool" or "execute_tool <tool>", so
--   both the attribute and the name are accepted.
-- Table name: adjust `otel.otel_traces` if your deployment differs.

SELECT
  run_id,
  input_fp,
  uniqExact(output_fp)       AS distinct_outputs,
  count(*)                   AS call_count,
  any(tool_name)             AS tool_name,
  min(step_index)            AS first_step_index,
  'trustabl.false_idempotent' AS rule_id,
  'high'                      AS severity
FROM (
  SELECT
    SpanAttributes['trustabl.run_id']        AS run_id,
    SpanAttributes['trustabl.tool.input_fp']  AS input_fp,
    SpanAttributes['trustabl.tool.output_fp'] AS output_fp,
    SpanAttributes['gen_ai.tool.name']        AS tool_name,
    toUInt64OrZero(SpanAttributes['trustabl.step_index']) AS step_index
  FROM otel.otel_traces
  WHERE
    (SpanAttributes['gen_ai.operation.name'] = 'execute_tool'
      OR SpanName = 'execute_tool' OR startsWith(SpanName, 'execute_tool '))
    AND SpanAttributes['trustabl.tool.side_effect'] = 'pure'
    AND SpanAttributes['trustabl.run_id']        != ''
    AND SpanAttributes['trustabl.tool.input_fp']  != ''
    AND SpanAttributes['trustabl.tool.output_fp'] != ''
    AND Timestamp >= now() - INTERVAL 10 MINUTE
)
GROUP BY run_id, input_fp
HAVING distinct_outputs > 1
ORDER BY distinct_outputs DESC;
