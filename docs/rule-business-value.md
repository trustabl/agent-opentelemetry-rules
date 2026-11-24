# What each rule catches, and whether it works today

For each of the twelve rules: what it catches, why a security or observability team would care,
and its status on the `feat/openlit-queries-2` branch.

Status words:

- **Works**: the data the rule reads is written by the labels SDK, and the rule's names match.
- **Fires wrongly**: the rule produces alerts that do not mean what they say.
- **Needs other data**: the rule reads something the labels SDK does not write, so it stays
  silent or cannot be judged until another component supplies it.

Eight rules have an OpenLIT query. "Works" does not mean a query exists for your backend
(see the last column).

| Rule | What it catches, and why it matters | Status | OpenLIT query |
|---|---|---|---|
| `tool_loop` | An agent calls the same tool with the same arguments three or more times in its last five calls. It is stuck, burning cost and possibly repeating an action that changes something. | Works | yes |
| `retry_storm` | A single tool call has been retried four or more times. A failing dependency is being hammered, which costs money and can make an outage worse. | Works | yes |
| `false_idempotent` | A tool declared as having no side effects gave different answers to the same question in one run. Its label cannot be trusted, so safeguards that rely on it may be wrong. | Works | yes |
| `policy_absent` | An agent run started with no sandbox and no content-safety policy attached. The agent is running without the guardrails it was meant to have. | Works | yes |
| `handoff_unbound` | One agent handed work to another and the receiving agent has no policy attached. Control that existed before the handoff may not apply after it. | Works | yes |
| `instrumentation_degraded` | A tool call was labelled by the SDK but is missing its step number, so the order of events in the run cannot be rebuilt. Other rules depend on that order. | Works (fixed on the previous branch; before, it fired on every versioned agent span) | yes |
| `dspm_unbound` | An agent run has no data-security policy attached. Sensitive data may be handled with no protection declared. It looks for a data-security policy marked required, so one marked optional does not clear it. It fires on any run without one, whether or not that agent needs one. | Works | yes |
| `policy_drift` | The fingerprint of a policy changed during one run. The rules in force may have been swapped mid-task. It compares per policy, so two different policies in one run are not a change. | Works (the query groups by trace, because the SDK writes the run id only on the root span) | yes |
| `contract_drift` | The contract fingerprint changed during a run. The agent may have been running against different approved terms from one step to the next. Reads `trustabl.contract_hash`, which the labels spec reserves as a resource attribute that the deployment sets; the SDK does not write it. | Needs other data | no |
| `irreversible_unguarded` | A tool call that cannot be undone ran with no limit applied to it. The SDK does not write the limit information, so today it would flag every irreversible call, guarded or not. | Needs other data (would fire wrongly if switched on now) | no |
| `constraint_hit` | A configured limit denied or capped a tool call. Shown for trend-watching only, not as an alert. The limit decision is not written by the SDK. | Needs other data | no |
| `denied_then_answered` | A limit blocked a data lookup, yet the agent still gave a final answer. The answer may rest on data it was not allowed to use. The limit decision is not written by the SDK. | Needs other data | no |

## Notes

- All eight OpenLIT queries were run on synthetic spans only, not on traces from a real
  deployment.
- `policy_absent` and `handoff_unbound` read the same policy events. A handoff span with no
  sandbox and no content-safety policy can trigger both.
