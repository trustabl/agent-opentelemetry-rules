-- trustabl.no_progress -> OpenLIT / ClickHouse
--
-- Fires when 3 consecutive tool steps in a run carry the same progress marker.
-- Consecutive means adjacent in trustabl.step_index order, so a step with a
-- different marker between them resets it. Needs step_index and progress_marker
-- on every execute_tool span; spans without a marker are ignored.
-- Same conventions as query.sql (tool_loop): table otel.otel_traces written by
-- the OpenTelemetry ClickHouse Exporter; adjust the database/table if yours
-- differs; the 10 minute lookback is a tunable, not part of the rule.
-- A run is a trace (TraceId). The root invoke_agent span only exports when it
-- ends, so a row here means the run has finished.
-- Spans are matched by SpanName or gen_ai.operation.name, whichever the
-- instrumentation sets.
--
-- Rule source: ../../rules/no_progress.yaml
-- Schema reference: ../../attribute-profile.yaml

WITH steps AS (
  SELECT
    TraceId,
    SpanAttributes['trustabl.run_id']          AS run_id,
    SpanAttributes['trustabl.progress_marker'] AS marker,
    SpanAttributes['gen_ai.tool.name']         AS tool_name,
    toUInt64OrZero(SpanAttributes['trustabl.step_index']) AS step_index
  FROM otel.otel_traces
  WHERE
    (SpanName = 'execute_tool' OR SpanAttributes['gen_ai.operation.name'] = 'execute_tool')
    AND SpanAttributes['trustabl.progress_marker'] != ''
    AND Timestamp >= now() - INTERVAL 10 MINUTE
),

flagged AS (
  SELECT
    run_id,
    marker,
    tool_name,
    step_index,
    lagInFrame(marker, 1) OVER w AS m1,
    lagInFrame(marker, 2) OVER w AS m2
  FROM steps
  WINDOW w AS (
    PARTITION BY TraceId ORDER BY step_index
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
  )
)

SELECT
  run_id,
  marker AS progress_marker,
  step_index AS third_step_index,
  tool_name,
  'trustabl.no_progress' AS rule_id,
  'high'                 AS severity
FROM flagged
WHERE marker = m1 AND marker = m2
ORDER BY run_id, step_index;
