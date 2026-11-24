-- trustabl.handoff_unbound -> OpenLIT / ClickHouse
--
-- Rule source: ../../rules/handoff_unbound.yaml
-- Fires on an invoke_agent span that carries trustabl.handoff_id and has no
-- trustabl.policy.binding event of any of the six binding types. The rule's
-- absent_binding_type list is read as "none of these types is present"
-- (the rule's own comment says so). An inherited binding (source='inherited')
-- is still a binding event and clears the rule, as the SDK docs intend.
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
  SpanAttributes['trustabl.handoff_id'] AS handoff_id,
  SpanAttributes['trustabl.run_id']     AS run_id,
  'trustabl.handoff_unbound' AS rule_id,
  'high'                     AS severity
FROM otel.otel_traces
WHERE
  (SpanAttributes['gen_ai.operation.name'] = 'invoke_agent'
    OR SpanName = 'invoke_agent' OR startsWith(SpanName, 'invoke_agent '))
  AND SpanAttributes['trustabl.handoff_id'] != ''
  AND NOT arrayExists(
        i -> `Events.Name`[i] = 'trustabl.policy.binding'
             AND `Events.Attributes`[i]['trustabl.policy.binding.type']
                 IN ('sandbox', 'content_safety', 'tool_grants', 'retention', 'data_security', 'custom'),
        arrayEnumerate(`Events.Name`))
  AND Timestamp >= now() - INTERVAL 10 MINUTE;
