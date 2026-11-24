-- trustabl.policy_absent -> OpenLIT / ClickHouse
--
-- Rule source: ../../rules/policy_absent.yaml
-- AMBIGUITY: the rule says absent_binding_type: [sandbox, content_safety].
-- Two readings: (a) fire when EITHER type is missing, (b) fire when NEITHER is
-- present. This query takes (b), "none of these types is present", which is
-- the reading handoff_unbound.yaml states for the same predicate and matches
-- the title "no policy binding bound". Under (a), change the AND of the two
-- NOT-exists tests below to OR. The binding's `required` flag is not read.
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
  SpanAttributes['trustabl.exit_reason']  AS exit_reason,
  SpanAttributes['gen_ai.agent.name']     AS agent_name,
  'trustabl.policy_absent' AS rule_id,
  'high'                   AS severity
FROM otel.otel_traces
WHERE
  (SpanAttributes['gen_ai.operation.name'] = 'invoke_agent'
    OR SpanName = 'invoke_agent' OR startsWith(SpanName, 'invoke_agent '))
  AND NOT arrayExists(
        i -> `Events.Name`[i] = 'trustabl.policy.binding'
             AND `Events.Attributes`[i]['trustabl.policy.binding.type'] = 'sandbox',
        arrayEnumerate(`Events.Name`))
  AND NOT arrayExists(
        i -> `Events.Name`[i] = 'trustabl.policy.binding'
             AND `Events.Attributes`[i]['trustabl.policy.binding.type'] = 'content_safety',
        arrayEnumerate(`Events.Name`))
  AND Timestamp >= now() - INTERVAL 10 MINUTE;
