-- trustabl.instrumentation_degraded -> OpenLIT / ClickHouse
--
-- Rule source: ../../rules/instrumentation_degraded.yaml
-- Fires on an execute_tool span that has trustabl.tool.attempt (the one key the
-- SDK always writes on a tool span it labelled) and no trustabl.step_index.
-- The SDK writes step_index only when the caller passes it, so a caller that
-- never passes it trips this on every tool span. A tool span the SDK never
-- touched (no attempt) is not flagged.
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
  SpanAttributes['gen_ai.tool.name']      AS tool_name,
  SpanAttributes['trustabl.tool.attempt'] AS attempt,
  SpanAttributes['trustabl.run_id']       AS run_id,
  'trustabl.instrumentation_degraded' AS rule_id,
  'medium'                            AS severity
FROM otel.otel_traces
WHERE
  (SpanAttributes['gen_ai.operation.name'] = 'execute_tool'
    OR SpanName = 'execute_tool' OR startsWith(SpanName, 'execute_tool '))
  AND mapContains(SpanAttributes, 'trustabl.tool.attempt')
  AND NOT mapContains(SpanAttributes, 'trustabl.step_index')
  AND Timestamp >= now() - INTERVAL 10 MINUTE;
