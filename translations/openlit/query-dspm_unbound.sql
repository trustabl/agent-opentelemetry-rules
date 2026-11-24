-- trustabl.dspm_unbound -> OpenLIT / ClickHouse
--
-- Rule source: ../../rules/dspm_unbound.yaml
-- Fires on an invoke_agent span with no trustabl.policy.binding event that has
-- binding.type = 'data_security' AND binding.required = 'true' (rule predicate
-- absent_event, see ../../rule-ir-schema.yaml). A data_security binding marked
-- required=false does not satisfy the rule. Event booleans arrive as the
-- strings 'true'/'false'; lower() guards against 'True'. To ignore the flag and
-- fire only when no data_security binding exists, drop the required test.
-- Like the rule, this fires on any run without one, whether or not the agent
-- needs one.
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
  SpanAttributes['trustabl.run_id']       AS run_id,
  SpanAttributes['gen_ai.agent.name']     AS agent_name,
  SpanAttributes['trustabl.exit_reason']  AS exit_reason,
  'trustabl.dspm_unbound' AS rule_id,
  'high'                  AS severity
FROM otel.otel_traces
WHERE
  (SpanAttributes['gen_ai.operation.name'] = 'invoke_agent'
    OR SpanName = 'invoke_agent' OR startsWith(SpanName, 'invoke_agent '))
  AND NOT arrayExists(
        i -> `Events.Name`[i] = 'trustabl.policy.binding'
             AND `Events.Attributes`[i]['trustabl.policy.binding.type'] = 'data_security'
             AND lower(`Events.Attributes`[i]['trustabl.policy.binding.required']) = 'true',
        arrayEnumerate(`Events.Name`))
  AND Timestamp >= now() - INTERVAL 10 MINUTE;
