-- trustabl.tool_avoidance -> OpenLIT / ClickHouse
--
-- Fires when a run declared expected tools, ended with a final answer, and
-- called none of them. A run with no execute_tool span at all counts.
-- Same conventions as query.sql (tool_loop): table otel.otel_traces written by
-- the OpenTelemetry ClickHouse Exporter; adjust the database/table if yours
-- differs; the 10 minute lookback is a tunable, not part of the rule.
-- A run is a trace (TraceId). The root invoke_agent span only exports when it
-- ends, so a row here means the run has finished.
-- Spans are matched by SpanName or gen_ai.operation.name, whichever the
-- instrumentation sets.
--
-- Rule source: ../../rules/tool_avoidance.yaml
-- Schema reference: ../../attribute-profile.yaml

WITH roots AS (
  SELECT
    TraceId,
    SpanAttributes['trustabl.run_id']   AS run_id,
    SpanAttributes['gen_ai.agent.name'] AS agent_name,
    arrayDistinct(JSONExtract(SpanAttributes['trustabl.expected_tools'], 'Array(String)')) AS expected
  FROM otel.otel_traces
  WHERE
    (SpanName = 'invoke_agent' OR SpanAttributes['gen_ai.operation.name'] = 'invoke_agent')
    AND SpanAttributes['trustabl.exit_reason'] = 'final_answer'
    AND SpanAttributes['trustabl.expected_tools'] != ''
    AND Timestamp >= now() - INTERVAL 10 MINUTE
),

used AS (
  SELECT TraceId, groupUniqArray(SpanAttributes['gen_ai.tool.name']) AS used_tools
  FROM otel.otel_traces
  WHERE
    (SpanName = 'execute_tool' OR SpanAttributes['gen_ai.operation.name'] = 'execute_tool')
    AND Timestamp >= now() - INTERVAL 10 MINUTE
  GROUP BY TraceId
)

SELECT
  r.run_id,
  r.agent_name,
  r.expected AS expected_tools,
  'trustabl.tool_avoidance' AS rule_id,
  'medium'                  AS severity
FROM roots AS r
LEFT JOIN used AS u ON r.TraceId = u.TraceId
WHERE
  length(r.expected) > 0
  AND length(arrayIntersect(r.expected, u.used_tools)) = 0;
