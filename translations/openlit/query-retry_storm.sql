-- trustabl.retry_storm -> OpenLIT / ClickHouse
--
-- Rule source: ../../rules/retry_storm.yaml
-- Fires on every execute_tool span whose trustabl.tool.attempt is >= 4.
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
  TraceId,
  SpanId,
  SpanAttributes['trustabl.run_id']          AS run_id,
  SpanAttributes['gen_ai.tool.name']         AS tool_name,
  toUInt32OrZero(SpanAttributes['trustabl.tool.attempt']) AS attempt,
  SpanAttributes['trustabl.tool.error_class'] AS error_class,
  SpanAttributes['trustabl.step_index']      AS step_index,
  'trustabl.retry_storm' AS rule_id,
  'high'                 AS severity
FROM otel.otel_traces
WHERE
  (SpanAttributes['gen_ai.operation.name'] = 'execute_tool'
    OR SpanName = 'execute_tool' OR startsWith(SpanName, 'execute_tool '))
  AND toUInt32OrZero(SpanAttributes['trustabl.tool.attempt']) >= 4
  AND Timestamp >= now() - INTERVAL 10 MINUTE
ORDER BY attempt DESC;
