# `trustabl.tool_loop` → Datadog

A worked translation of [`../../rules/tool_loop.yaml`](../../rules/tool_loop.yaml)
into a Datadog log-alert monitor. The `query` field in
[`monitor.json`](monitor.json) is transcribed verbatim from the source memo
("Process metadata, portable rules, and a policy control plane", 30 Aug
2026, §5.6); the surrounding Monitor API object (`name`, `message`, `tags`,
`options.thresholds`, `priority`) is this pack's own construction, needed
to make the query a submittable monitor rather than a bare query fragment.

## The mapping

| Rule IR field (`tool_loop.yaml`) | Datadog concept |
|---|---|
| `when.span: execute_tool` | `logs("@gen_ai.operation.name:execute_tool")` |
| `when.condition.count_same: trustabl.tool.input_fp` | `.rollup("count").by("@trustabl.tool.input_fp","@gen_ai.agent.name")` — group and count by the fingerprint (plus agent, so loops aren't conflated across agents) |
| `when.window: last_5_tool_calls_in_run` | Approximated as `.last("5m")` — same call-count-vs-time-window caveat as the Grafana translation |
| `when.condition.gte: 3` | `> 3` in the query, and `options.thresholds.critical: 3` |
| `title` | Monitor `name` |
| `severity: high` | `tags: ["severity:high"]` and `priority: 2` |
| `fix_class` | `tags: ["fix_class:policy.cap_tool"]` |
| `evidence` | Named in `message` as what to check on a firing log |

Same omission as the Grafana translation: `when.condition.side_effect_not: none`
is not expressed in the query — filtering by `@trustabl.tool.side_effect`
would need an additional clause the memo's own sketch doesn't include either.

## How this is actually used

Unlike Grafana, Datadog has no self-service community catalog for
individual monitors. A monitor like this is created **in your own Datadog
org** — via the UI, the Monitors API (`POST /api/v1/monitor` with the
contents of `monitor.json`), or Terraform (`datadog_monitor` resource).
Datadog does have a public "Integrations" marketplace, but that's a much
heavier, partnership-gated process for shipping an official Datadog
integration — out of scope here, and not what "self-publish" means for
this pack.

## Status

Hand-authored, not generated. No translator tooling exists yet to emit
`monitor.json` mechanically from `rules/tool_loop.yaml` — same gap noted in
the Grafana and Langfuse packs.
