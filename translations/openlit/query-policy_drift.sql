-- trustabl.policy_drift -> OpenLIT / ClickHouse
--
-- Rule source: ../../rules/policy_drift.yaml
-- Fires when one binding id (trustabl.policy.binding.id) carries more than one
-- distinct trustabl.policy.binding.sha256 across the invoke_agent spans of a
-- run. The comparison is per binding id, so two different bindings in one run
-- (each with its own hash) are not drift (rule predicate value_drift with
-- `per`, see ../../rule-ir-schema.yaml). Events with an empty id or sha256 are
-- ignored: no value is "unknown", not "different".
-- RUN KEY: the rule says same_run_id, but the SDK writes trustabl.run_id only
-- on the root span (Run.mark_start), so child invoke_agent spans have none to
-- group on. This query groups by TraceId, which assumes one run is one trace.
-- run_id is reported from whichever span carries it.
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
  binding_id,
  uniqExact(binding_sha256)         AS distinct_hashes,
  groupUniqArray(binding_sha256)    AS hashes,
  anyIf(run_id, run_id != '')       AS run_id,
  count(*)                          AS binding_events,
  'trustabl.policy_drift' AS rule_id,
  'high'                  AS severity
FROM (
  SELECT
    TraceId,
    SpanAttributes['trustabl.run_id']                  AS run_id,
    ev_attrs['trustabl.policy.binding.id']             AS binding_id,
    ev_attrs['trustabl.policy.binding.sha256']         AS binding_sha256
  FROM otel.otel_traces
  ARRAY JOIN `Events.Name` AS ev_name, `Events.Attributes` AS ev_attrs
  WHERE
    (SpanAttributes['gen_ai.operation.name'] = 'invoke_agent'
      OR SpanName = 'invoke_agent' OR startsWith(SpanName, 'invoke_agent '))
    AND ev_name = 'trustabl.policy.binding'
    AND Timestamp >= now() - INTERVAL 10 MINUTE
)
WHERE binding_id != '' AND binding_sha256 != ''
GROUP BY TraceId, binding_id
HAVING distinct_hashes > 1
ORDER BY distinct_hashes DESC;
