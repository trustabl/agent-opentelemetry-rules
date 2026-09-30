# `trustabl.tool_loop` → Langfuse

A worked translation of [`../../rules/tool_loop.yaml`](../../rules/tool_loop.yaml)
into a Langfuse score config. [`score-config.json`](score-config.json) is
transcribed verbatim from the source memo ("Process metadata, portable
rules, and a policy control plane", 30 Aug 2026, §5.6) — it is not an
extrapolation.

## The mapping

| Rule IR field (`tool_loop.yaml`) | Langfuse concept |
|---|---|
| `id` | Score config `name` |
| `when.condition.gte: 3` within `when.window: last_5_tool_calls_in_run` | Score config `comment` (Langfuse score configs don't carry a query language of their own — the condition text is documentation for whoever posts the score, not an executable filter) |
| A boolean "did this fire" outcome | `dataType: BOOLEAN`, `minValue: 0`, `maxValue: 1` |

## How this is actually used (unlike Grafana, there is no catalog to publish to)

Langfuse scores are evaluated **outside Langfuse** — by whatever is
watching the trace data (the translation pack's mechanical mapping in
theory, a human today) — and then *posted* to Langfuse against a specific
trace:

1. **Create the score config once**, against your own Langfuse project, via
   `POST /api/public/score-configs` with the contents of
   [`score-config.json`](score-config.json). This registers `trustabl.tool_loop`
   as a known score type in that project — it does not evaluate anything by
   itself.
2. **Post a score event per firing trace**, via `POST /api/public/scores`:
   ```json
   {
     "traceId": "<the trace where the loop was observed>",
     "name": "trustabl.tool_loop",
     "value": 1,
     "configId": "<the id returned when the score config was created>"
   }
   ```

Unlike Grafana, there is no public catalog to self-publish this to —
Langfuse scores are project-scoped, created against your own (or a
customer's) Langfuse instance, not submitted anywhere public. "Self-publish"
as a concept doesn't apply here.

## Status

Hand-authored, not generated. No translator tooling exists yet to actually
detect a firing `trustabl.tool_loop` condition and POST the score
automatically — that's the same follow-up gap noted in the Grafana pack,
just for a different backend.
