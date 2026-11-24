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
  backends (Grafana, Langfuse, Datadog, OpenLIT, …) against live OpenTelemetry trace
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
    query. **Most speculative of the seven** — LangSmith's filter grammar
    cannot fully express the sliding-window condition in one filter.
  - [`translations/openlit/`](translations/openlit/) — ClickHouse SQL
    detection queries against OpenLIT's `otel_traces` table, for `tool_loop`,
    `retry_storm`, `false_idempotent`, `policy_absent`, `handoff_unbound`,
    `instrumentation_degraded`, `dspm_unbound` and `policy_drift`.
    `tool_loop` uses an exact call-count window via `row_number()` — closer to
    the rule's intent than the time-window approximation in the Grafana/Datadog
    packs.
- [`scripts/`](scripts/) — `create-datadog-monitor.py` posts the `tool_loop` monitor JSON
  ([`translations/datadog/monitor.json`](translations/datadog/monitor.json)) to the Datadog
  Monitors API; it does not read rule YAML and handles no other rule.
  `check-otel-names.py` checks every `trustabl.*` name against the labels spec.

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

The Grafana, Datadog, Langfuse, Dunetrace, Phoenix and LangSmith packs translate
`tool_loop` only. The Grafana mapping table describes `tool_loop`; the other rules do not
follow it. The OpenLIT pack covers eight rules (see above), each with its own reading
documented in its SQL header.

## Names

Attribute and event names follow the labels spec (`spec/keys.json` in
`agent-reliability-otel-labels`); `scripts/check-otel-names.py` enforces it. Contract identity
is `trustabl.contract_id` and `trustabl.contract_hash`: the spec reserves both as **resource**
attributes that the deployment sets through `OTEL_RESOURCE_ATTRIBUTES`; the SDK does not write
them. `trustabl.contract.version` and the `trustabl.constraint.*` names are not in the spec and
are allowlisted in `scripts/otel-names-allowlist.txt` until the tech leads decide them. Event
conditions (`absent_binding_type`, `absent_event`, `value_drift` per key) are defined in
`rule-ir-schema.yaml`.

## Rule status

"Works" means the data the rule reads is written by the labels SDK and the names match the
spec. Checked by reading the SDK; OpenLIT queries were run on synthetic spans only.

| Rule | Status | OpenLIT query |
|------|--------|---------------|
| `tool_loop` | works | yes |
| `retry_storm` | works | yes |
| `false_idempotent` | works | yes |
| `policy_absent` | works | yes |
| `handoff_unbound` | works | yes |
| `instrumentation_degraded` | works | yes |
| `dspm_unbound` | works | yes |
| `policy_drift` | works | yes |
| `contract_drift` | needs deployment to set the resource attributes | no |
| `irreversible_unguarded` | needs constraint data (policy emitter); fires wrongly if enabled now | no |
| `constraint_hit` | needs constraint data (policy emitter) | no |
| `denied_then_answered` | needs constraint data (policy emitter) | no |

What each rule catches and whether it works today:
[`docs/rule-business-value.md`](docs/rule-business-value.md).

## Status

v0.1, first slice. No translator tooling exists yet — every vendor translation
is hand-authored to prove (or, for the three speculative packs, sketch) the
rule-IR-to-vendor-format mapping, not generated. Licensed Apache-2.0.
