# Trustabl Agent OpenTelemetry Rules — v0.1

A small Apache-2.0 OpenTelemetry process-metadata profile (`trustabl.*` span
attributes and events) plus a deterministic runtime rule format, published as
data so any observability backend can evaluate it against live agent trace data.

## What this is not

- **Not loaded, parsed, or evaluated by `trustabl scan`.** The
  [`agent-reliability-analyzer`](https://github.com/trustabl/agent-reliability-analyzer)
  engine never imports or fetches anything from this repository. Nothing here
  is part of that engine's `ScanResult`, `RulesSkipped`, or
  `SupportedSchemaVersion` compatibility contract.
- **Not related to `agent-reliability-rules`**, the engine's own
  static-analysis rule pack repo. Those rules are pulled and evaluated
  *in-process* by the `trustabl` binary against source code it just parsed.
  The rules in this repository are evaluated by third-party observability
  backends (Grafana, Langfuse, Datadog, …) against live OpenTelemetry trace
  data — the `trustabl` binary is never in that loop.

## Layout

- [`attribute-profile.yaml`](attribute-profile.yaml) — the v0.1 `trustabl.*`
  span attribute and event reference.
- [`rule-ir-schema.yaml`](rule-ir-schema.yaml) — the rule YAML shape reference.
- [`rules/`](rules/) — all twelve v0.1 rules, each as a YAML file:
  `tool_loop`, `retry_storm`, `policy_absent`, `policy_drift`,
  `contract_drift`, `irreversible_unguarded`, `constraint_hit` (shadow),
  `false_idempotent`, `handoff_unbound`, `instrumentation_degraded`,
  plus two from the DSPM addendum: `dspm_unbound`, `denied_then_answered`.
- [`translations/`](translations/) — worked translations of the rules into
  vendor-native formats. Confidence varies by backend — see each subdirectory's
  own README for specifics:
  - [`translations/grafana/`](translations/grafana/) — dashboard JSON +
    alerting-rule provisioning YAML, shaped for self-publish to Grafana's
    own catalog.
  - [`translations/langfuse/`](translations/langfuse/) — a score-config JSON.
    Apply against your own Langfuse project via their API.
  - [`translations/datadog/`](translations/datadog/) — a Monitor API JSON
    object. Apply against your own Datadog org.
  - [`translations/dunetrace/`](translations/dunetrace/) — a `detectors.yml`
    adapter mapping onto Dunetrace's existing `TOOL_LOOP` detector.
    **Speculative** — no verified access to Dunetrace's real config format.
  - [`translations/phoenix/`](translations/phoenix/) — a Python span evaluator
    function. **Speculative** — shape inferred from Phoenix's evaluator API.
  - [`translations/langsmith/`](translations/langsmith/) — a saved-filter
    query. **Most speculative of the six** — LangSmith's filter grammar
    cannot fully express the sliding-window condition in one filter.
- [`scripts/`](scripts/) — `create-datadog-monitor.py`: translates any rule
  YAML into a Datadog composite monitor via the Monitors API.

## v0.1 rules

All twelve rules are authored as YAML files in [`rules/`](rules/), each
following the shape defined in [`rule-ir-schema.yaml`](rule-ir-schema.yaml):

| Rule | Severity | Fix class | Shadow |
|------|----------|-----------|--------|
| [`tool_loop`](rules/tool_loop.yaml) | high | `policy.cap_tool` | no |
| [`retry_storm`](rules/retry_storm.yaml) | high | `policy.cap_retries` | no |
| [`policy_absent`](rules/policy_absent.yaml) | high | `policy.require_bundle` | no |
| [`policy_drift`](rules/policy_drift.yaml) | high | `policy.pin_bundle` | no |
| [`contract_drift`](rules/contract_drift.yaml) | high | `policy.pin_contract` | no |
| [`irreversible_unguarded`](rules/irreversible_unguarded.yaml) | critical | `policy.require_constraint` | no |
| [`constraint_hit`](rules/constraint_hit.yaml) | medium | `policy.review_constraint` | **yes** |
| [`false_idempotent`](rules/false_idempotent.yaml) | high | `policy.audit_tool` | no |
| [`handoff_unbound`](rules/handoff_unbound.yaml) | high | `policy.require_bundle_on_handoff` | no |
| [`instrumentation_degraded`](rules/instrumentation_degraded.yaml) | medium | `instrumentation.add_emitter` | no |
| [`dspm_unbound`](rules/dspm_unbound.yaml) | high | `policy.require_bundle` | no |
| [`denied_then_answered`](rules/denied_then_answered.yaml) | high | `policy.require_constraint` | no |

`constraint_hit` is shadow-only: constraint fires are expected behavior, not a
defect — the rule surfaces them for trend analysis without paging anyone.

The Grafana translation in [`translations/grafana/`](translations/grafana/) is
fully worked for `tool_loop`. The other eleven rules follow the same mapping;
translating them is the next translation-pack slice.

## Status

v0.1, first slice. No translator tooling exists yet — every vendor translation
is hand-authored to prove (or, for the three speculative packs, sketch) the
rule-IR-to-vendor-format mapping, not generated. Licensed Apache-2.0.
