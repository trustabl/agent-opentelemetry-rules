-- trustabl.goal_abandonment -> OpenLIT / ClickHouse
--
-- Fires when a run stopped using tools, then made 4 or more more chat calls,
-- and did not end with exit_reason = final_answer.
-- Same conventions as query.sql (tool_loop): table otel.otel_traces written by
-- the OpenTelemetry ClickHouse Exporter; adjust the database/table if yours
-- differs; the 10 minute lookback is a tunable, not part of the rule.
-- A run is a trace (TraceId). The root invoke_agent span only exports when it
-- ends, so a row here means the run has finished.
-- Spans are matched by SpanName or gen_ai.operation.name, whichever the
-- instrumentation sets.
--
-- Rule source: ../../rules/goal_abandonment.yaml
-- Schema reference: ../../attribute-profile.yaml

WITH roots AS (
  SELECT
    TraceId,
    SpanAttributes['trustabl.run_id']      AS run_id,
    SpanAttributes['trustabl.exit_reason'] AS exit_reason,
    SpanAttributes['gen_ai.agent.name']    AS agent_name
  FROM otel.otel_traces
  WHERE
    (SpanName = 'invoke_agent' OR SpanAttributes['gen_ai.operation.name'] = 'invoke_agent')
    AND SpanAttributes['trustabl.run_id'] != ''
    AND SpanAttributes['trustabl.exit_reason'] != 'final_answer'
    AND Timestamp >= now() - INTERVAL 10 MINUTE
),

last_tool AS (
  SELECT TraceId, max(Timestamp) AS last_tool_ts
  FROM otel.otel_traces
  WHERE
    (SpanName = 'execute_tool' OR SpanAttributes['gen_ai.operation.name'] = 'execute_tool')
    AND Timestamp >= now() - INTERVAL 10 MINUTE
  GROUP BY TraceId
),

chats AS (
  SELECT c.TraceId AS TraceId, count(*) AS chats_after_last_tool
  FROM otel.otel_traces AS c
  INNER JOIN last_tool AS t ON c.TraceId = t.TraceId
  WHERE
    (c.SpanName = 'chat' OR c.SpanAttributes['gen_ai.operation.name'] = 'chat')
    AND c.Timestamp > t.last_tool_ts
  GROUP BY c.TraceId
)

SELECT
  r.run_id,
  r.agent_name,
  r.exit_reason,
  c.chats_after_last_tool,
  'trustabl.goal_abandonment' AS rule_id,
  'medium'                    AS severity
FROM roots AS r
INNER JOIN chats AS c ON r.TraceId = c.TraceId
WHERE c.chats_after_last_tool >= 4
ORDER BY c.chats_after_last_tool DESC;
