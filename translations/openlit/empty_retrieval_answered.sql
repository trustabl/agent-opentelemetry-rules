-- trustabl.empty_retrieval_answered -> OpenLIT / ClickHouse
--
-- Fires when a run's last retrieval returned zero results and the run still
-- ended with a final answer. A later retrieval with results clears it, because
-- only the latest retrieval is looked at. Retrieval spans are joined to the run
-- by TraceId, so they need no trustabl label other than result_count.
-- Same conventions as query.sql (tool_loop): table otel.otel_traces written by
-- the OpenTelemetry ClickHouse Exporter; adjust the database/table if yours
-- differs; the 10 minute lookback is a tunable, not part of the rule.
-- A run is a trace (TraceId). The root invoke_agent span only exports when it
-- ends, so a row here means the run has finished.
-- Spans are matched by SpanName or gen_ai.operation.name, whichever the
-- instrumentation sets.
--
-- Rule source: ../../rules/empty_retrieval_answered.yaml
-- Schema reference: ../../attribute-profile.yaml

WITH roots AS (
  SELECT
    TraceId,
    SpanAttributes['trustabl.run_id'] AS run_id
  FROM otel.otel_traces
  WHERE
    (SpanName = 'invoke_agent' OR SpanAttributes['gen_ai.operation.name'] = 'invoke_agent')
    AND SpanAttributes['trustabl.exit_reason'] = 'final_answer'
    AND Timestamp >= now() - INTERVAL 10 MINUTE
),

last_retrieval AS (
  SELECT
    TraceId,
    argMax(toUInt64OrZero(SpanAttributes['trustabl.retrieval.result_count']), Timestamp) AS result_count,
    count(*) AS retrievals
  FROM otel.otel_traces
  WHERE
    (SpanName = 'retrieval' OR SpanAttributes['gen_ai.operation.name'] = 'retrieval')
    AND SpanAttributes['trustabl.retrieval.result_count'] != ''
    AND Timestamp >= now() - INTERVAL 10 MINUTE
  GROUP BY TraceId
)

SELECT
  r.run_id,
  l.result_count,
  l.retrievals,
  'trustabl.empty_retrieval_answered' AS rule_id,
  'high'                              AS severity
FROM roots AS r
INNER JOIN last_retrieval AS l ON r.TraceId = l.TraceId
WHERE l.result_count = 0;
