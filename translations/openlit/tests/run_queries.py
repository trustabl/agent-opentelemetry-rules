#!/usr/bin/env python3
"""Run each OpenLIT query against synthetic spans: one run that must fire, one
that must stay silent. Uses chdb (embedded ClickHouse) with the table layout of
the OpenTelemetry ClickHouse Exporter (the one OpenLIT writes to).

  python3 translations/openlit/tests/run_queries.py   # needs: pip install chdb
Exit 0 when every case behaves, 1 otherwise.
"""
import json
import sys
from pathlib import Path

from chdb import session

HERE = Path(__file__).resolve().parent.parent

DDL = """
CREATE TABLE otel.otel_traces (
  Timestamp DateTime64(9) CODEC(Delta, ZSTD(1)),
  TraceId String, SpanId String, ParentSpanId String, TraceState String,
  SpanName LowCardinality(String), SpanKind LowCardinality(String),
  ServiceName LowCardinality(String),
  ResourceAttributes Map(LowCardinality(String), String),
  ScopeName String, ScopeVersion String,
  SpanAttributes Map(LowCardinality(String), String),
  Duration Int64, StatusCode LowCardinality(String), StatusMessage String
) ENGINE = MergeTree ORDER BY (ServiceName, SpanName, toDateTime(Timestamp))
"""

rows = []
_n = [0]


def span(trace, name, offset_ms, attrs=None, parent=""):
    _n[0] += 1
    rows.append((trace, f"s{_n[0]}", parent, name, offset_ms, attrs or {}))


def root(trace, run, exit_reason=None, expected=None, offset=100000):
    a = {"trustabl.run_id": run, "gen_ai.agent.name": "agent"}
    if exit_reason:
        a["trustabl.exit_reason"] = exit_reason
    if expected is not None:
        a["trustabl.expected_tools"] = json.dumps(expected)
    span(trace, "invoke_agent", offset, a)


def tool(trace, run, step, name, offset, marker=None):
    a = {"trustabl.run_id": run, "trustabl.step_index": str(step), "gen_ai.tool.name": name}
    if marker:
        a["trustabl.progress_marker"] = marker
    span(trace, "execute_tool", offset, a)


# goal_abandonment
root("ga_fire", "ga_fire", "max_steps")
tool("ga_fire", "ga_fire", 0, "search", 1000)
for i in range(4):
    span("ga_fire", "chat", 2000 + i)
root("ga_ok", "ga_ok", "final_answer")          # same shape but ended cleanly
tool("ga_ok", "ga_ok", 0, "search", 1000)
for i in range(4):
    span("ga_ok", "chat", 2000 + i)
root("ga_few", "ga_few", "max_steps")           # only 3 chats after the last tool
tool("ga_few", "ga_few", 0, "search", 1000)
for i in range(3):
    span("ga_few", "chat", 2000 + i)

# premature_termination
root("pt_fire", "pt_fire", "final_answer", ["search", "book"])
tool("pt_fire", "pt_fire", 0, "search", 1000)
root("pt_ok", "pt_ok", "final_answer", ["search", "book"])
tool("pt_ok", "pt_ok", 0, "search", 1000)
tool("pt_ok", "pt_ok", 1, "book", 1001)
root("pt_none", "pt_none", "final_answer", ["search", "book"])  # none used: tool_avoidance's case
tool("pt_none", "pt_none", 0, "other", 1000)

# tool_avoidance
root("ta_fire", "ta_fire", "final_answer", ["search"])           # no tool spans at all
root("ta_ok", "ta_ok", "final_answer", ["search"])
tool("ta_ok", "ta_ok", 0, "search", 1000)
root("ta_noexp", "ta_noexp", "final_answer")                      # no expectation declared

# empty_retrieval_answered
root("er_fire", "er_fire", "final_answer")
span("er_fire", "retrieval", 1000, {"trustabl.retrieval.result_count": "0"})
root("er_ok", "er_ok", "final_answer")
span("er_ok", "retrieval", 1000, {"trustabl.retrieval.result_count": "5"})
root("er_retry", "er_retry", "final_answer")                      # empty, then a retry with results
span("er_retry", "retrieval", 1000, {"trustabl.retrieval.result_count": "0"})
span("er_retry", "retrieval", 2000, {"trustabl.retrieval.result_count": "3"})

# no_progress
root("np_fire", "np_fire", "final_answer")
for i, m in enumerate(["aaaa", "bbbb", "bbbb", "bbbb"]):
    tool("np_fire", "np_fire", i, "edit", 1000 + i, m)
root("np_ok", "np_ok", "final_answer")                            # a change in between resets it
for i, m in enumerate(["aaaa", "aaaa", "bbbb", "aaaa", "aaaa"]):
    tool("np_ok", "np_ok", i, "edit", 1000 + i, m)

CASES = {  # query file -> (run ids that must fire)
    "goal_abandonment": {"ga_fire"},
    "premature_termination": {"pt_fire"},
    # pt_none: expected tools declared, none used, so tool_avoidance fires on it too
    "tool_avoidance": {"ta_fire", "pt_none"},
    "empty_retrieval_answered": {"er_fire"},
    "no_progress": {"np_fire"},
}

def main():
    s = session.Session()
    s.query("CREATE DATABASE otel")
    s.query(DDL)
    for trace, sid, parent, name, off, attrs in rows:
        m = "map(" + ",".join(f"'{k}','{v.replace(chr(39), chr(92) + chr(39))}'" for k, v in attrs.items()) + ")"
        if not attrs:
            m = "map()"
        s.query(
            f"INSERT INTO otel.otel_traces (Timestamp, TraceId, SpanId, ParentSpanId, SpanName, "
            f"SpanAttributes) VALUES (now64(9) - INTERVAL 5 MINUTE + toIntervalMillisecond({off}), "
            f"'{trace}', '{sid}', '{parent}', '{name}', {m})"
        )
    bad = 0
    for rule, want in CASES.items():
        sql = (HERE / f"{rule}.sql").read_text()
        out = s.query(sql, "JSONEachRow").bytes().decode().strip().splitlines()
        got = {json.loads(line)["run_id"] for line in out}
        ok = got == want
        bad += not ok
        print(f"{'PASS' if ok else 'FAIL'} {rule}: fired {sorted(got)}, expected {sorted(want)}")
    sys.exit(1 if bad else 0)


main()
