"""
trustabl.tool_loop -> Arize Phoenix evaluator.

SPECULATIVE, more so than the Grafana/Langfuse/Datadog packs. The source
memo ("Process metadata, portable rules, and a policy control plane",
30 Aug 2026) gives Phoenix only a one-line description at S5.6: "Phoenix:
evaluator over span attributes." No concrete evaluator shape is given in
the memo -- everything below (the pandas-based structure, function
signature, column-naming assumptions) is this pack's own construction, not
a memo transcription, and has not been run against a real Phoenix
instance.

Phoenix's evaluator mechanism (as this pack understands it, from Phoenix's
public docs, not from the memo) operates on a dataframe of spans -- one row
per span, with span attributes flattened into columns. This is a
deterministic, structural evaluator (matching Trustabl's "process metadata,
not content" stance from memo S4.3) -- it is NOT an LLM-as-judge evaluator,
which is Phoenix's more common eval pattern.

Mapping from rules/tool_loop.yaml:
  when.span                        -> filter spans_df to execute_tool rows
  when.condition.count_same        -> group by (run_id, tool.input_fp)
  when.window (last_5_tool_calls)  -> approximated by looking at the last N
                                       execute_tool spans per run_id, not a
                                       real sliding window -- see the
                                       "What this does not capture" note in
                                       README.md
  when.condition.gte               -> threshold parameter
  when.condition.side_effect_not   -> side_effect column filter
"""

from __future__ import annotations

import pandas as pd

RULE_ID = "trustabl.tool_loop"
WINDOW_SIZE = 5     # approximates when.window: last_5_tool_calls_in_run
THRESHOLD = 3        # when.condition.gte
EXCLUDED_SIDE_EFFECT = "none"  # when.condition.side_effect_not


def evaluate_tool_loop(spans_df: pd.DataFrame) -> pd.DataFrame:
    """
    Evaluate the trustabl.tool_loop condition over a Phoenix span dataframe.

    Expects one row per span, with at least these columns (flattened
    attribute names -- adjust to however your Phoenix export actually
    names them):
      - "attributes.gen_ai.operation.name"
      - "attributes.trustabl.run_id"
      - "attributes.trustabl.step_index"
      - "attributes.trustabl.tool.input_fp"
      - "attributes.trustabl.tool.side_effect"
      - "attributes.gen_ai.tool.name"

    Returns a dataframe of one row per (run_id, input_fp) group that fired
    the rule, with the evidence fields named in rules/tool_loop.yaml.
    """
    tool_spans = spans_df[
        spans_df["attributes.gen_ai.operation.name"] == "execute_tool"
    ].copy()

    tool_spans = tool_spans[
        tool_spans["attributes.trustabl.tool.side_effect"] != EXCLUDED_SIDE_EFFECT
    ]

    tool_spans = tool_spans.sort_values("attributes.trustabl.step_index")
    windowed = tool_spans.groupby("attributes.trustabl.run_id", group_keys=False).tail(
        WINDOW_SIZE
    )

    counts = (
        windowed.groupby(
            ["attributes.trustabl.run_id", "attributes.trustabl.tool.input_fp"]
        )
        .size()
        .reset_index(name="count")
    )

    fired = counts[counts["count"] >= THRESHOLD].copy()
    fired["rule_id"] = RULE_ID
    fired["label"] = True

    return fired
