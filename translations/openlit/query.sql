-- trustabl.tool_loop -> OpenLIT / ClickHouse
--
-- Detection query for the tool_loop rule against OpenLIT's ClickHouse backend.
-- OpenLIT stores OTel span data via the standard OpenTelemetry ClickHouse
-- Exporter. Adjust the database/table prefix if your deployment differs from
-- the default `otel.otel_traces`.
--
-- The window translation here (row_number() OVER PARTITION BY run_id) is an
-- exact call-count window -- closer to the rule's intent than the time-window
-- approximation used in the Grafana/Datadog packs.
--
-- Rule source: ../../rules/tool_loop.yaml
-- Schema reference: ../../attribute-profile.yaml

WITH ranked AS (
  SELECT
    TraceId,
    SpanId,
    SpanAttributes['trustabl.run_id']           AS run_id,
    SpanAttributes['trustabl.tool.input_fp']    AS input_fp,
    SpanAttributes['trustabl.tool.side_effect'] AS side_effect,
    SpanAttributes['gen_ai.tool.name']          AS tool_name,
    SpanAttributes['trustabl.tool.attempt']     AS attempt,
    SpanAttributes['trustabl.step_index']       AS step_index,
    -- Rank spans newest-first within each run so we can slice the last N calls.
    row_number() OVER (
      PARTITION BY SpanAttributes['trustabl.run_id']
      ORDER BY toUInt64OrZero(SpanAttributes['trustabl.step_index']) DESC
    ) AS rn
  FROM otel.otel_traces
  WHERE
    SpanName = 'execute_tool'
    AND SpanAttributes['trustabl.tool.side_effect'] != 'none'
    AND SpanAttributes['trustabl.tool.input_fp']    != ''
    AND Timestamp >= now() - INTERVAL 10 MINUTE
),

-- Enforce the last_5_tool_calls_in_run window from the rule definition.
windowed AS (
  SELECT *
  FROM ranked
  WHERE rn <= 5
),

-- Count identical-fingerprint calls per run.
counts AS (
  SELECT
    run_id,
    input_fp,
    count(*)       AS call_count,
    any(tool_name) AS tool_name,
    any(attempt)   AS attempt
  FROM windowed
  GROUP BY run_id, input_fp
)

SELECT
  run_id,
  input_fp,
  call_count,
  tool_name,
  attempt,
  'trustabl.tool_loop' AS rule_id,
  'high'               AS severity
FROM counts
WHERE call_count >= 3
ORDER BY call_count DESC;
