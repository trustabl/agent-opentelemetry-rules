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
- [`rules/`](rules/) — twenty-four rules, each as a YAML file: the twelve v0.1 rules:
  `tool_loop`, `retry_storm`, `policy_absent`, `policy_drift`,
  `contract_drift`, `irreversible_unguarded`, `constraint_hit` (shadow),
  `false_idempotent`, `handoff_unbound`, `instrumentation_degraded`,
  plus two from the DSPM addendum: `dspm_unbound`, `denied_then_answered`;
  and twelve P1 rules (five active, seven shadow), listed in the P1 table below.
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
    detection queries against OpenLIT's `otel_traces` table: `tool_loop` plus
    the five active P1 rules. `tool_loop` uses an exact call-count window via
    `row_number()` — closer to the rule's intent than the time-window
    approximation in the Grafana/Datadog packs.
- [`scripts/`](scripts/) — `create-datadog-monitor.py`: translates any rule
  YAML into a Datadog composite monitor via the Monitors API.

## v0.1 rules

The first twelve rules are authored as YAML files in [`rules/`](rules/), each
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

## P1 rules

Twelve more rules, from the OpenLIT integration plan. The five active ones use
only names the labels spec defines (three were added to it: `trustabl.expected_tools`,
`trustabl.retrieval.result_count`, `trustabl.progress_marker`) and have an
[OpenLIT query](translations/openlit/). The seven **shadow** rules need labels or
policy data that nothing emits yet; their names are proposed, not defined, and
are listed in [`scripts/otel-names-allowlist.txt`](scripts/otel-names-allowlist.txt).

| Rule | Severity | Fix class | Shadow |
|------|----------|-----------|--------|
| [`goal_abandonment`](rules/goal_abandonment.yaml) | medium | `agent.cap_steps` | no |
| [`premature_termination`](rules/premature_termination.yaml) | medium | `agent.complete_expected_steps` | no |
| [`no_progress`](rules/no_progress.yaml) | high | `agent.cap_steps` | no |
| [`empty_retrieval_answered`](rules/empty_retrieval_answered.yaml) | high | `agent.require_grounding` | no |
| [`tool_avoidance`](rules/tool_avoidance.yaml) | medium | `agent.require_tool_use` | no |
| [`ungrounded_destination`](rules/ungrounded_destination.yaml) | high | `policy.require_grounded_destination` | **yes** |
| [`sensitive_read_external_send`](rules/sensitive_read_external_send.yaml) | critical | `policy.restrict_egress` | **yes** |
| [`untrusted_input_privileged_call`](rules/untrusted_input_privileged_call.yaml) | high | `policy.gate_privileged_call` | **yes** |
| [`repeated_policy_denials`](rules/repeated_policy_denials.yaml) | high | `policy.stop_on_repeated_denial` | **yes** |
| [`denied_then_allowed_sink`](rules/denied_then_allowed_sink.yaml) | critical | `policy.close_sink_bypass` | **yes** |
| [`agent_edits_own_config`](rules/agent_edits_own_config.yaml) | critical | `policy.protect_agent_config` | **yes** |
| [`delegation_trust_escalation`](rules/delegation_trust_escalation.yaml) | high | `policy.narrow_delegation` | **yes** |

That makes 24 rules, 8 of them shadow (the 7 above and `constraint_hit`).

## Status

v0.1, first slice. No translator tooling exists yet — every vendor translation
is hand-authored to prove (or, for the three speculative packs, sketch) the
rule-IR-to-vendor-format mapping, not generated. Licensed Apache-2.0.
