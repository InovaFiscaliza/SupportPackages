# HTTP Transfer Delegation Draft

Status: **draft for review; no custom agents configured**. Exact model
selectors observed in the current `runSubagent` registry are recorded below.

These templates can be pasted into a future request. Optional custom agents
may be created after approval, but no `.agent.md` or `.prompt.md` file is
activated by this draft. The project plan and tracker are the source of scope.

## Proposed Roles

| Role | Responsibility | Permission boundary |
|---|---|---|
| Coordinator | Resolve approvals, assign phases/file leases, integrate findings and record evidence | Delegation only when explicitly requested; no silent requirement changes |
| Transfer Implementer | Implement one bounded task against the approved contracts | Edit only leased files; permitted static checks; no further delegation |
| Transfer Reviewer | Independently inspect diff, contracts, safety and regression risks | Read-only tools; no edits, runtime/network tests, commits or delegation |

When configuring a future custom reviewer, expose only verified read/search/
diagnostic tools. A prose request is not a technical restriction: avoid giving
it terminal/write tools if strict read-only enforcement is needed. Do not
invent tool IDs or claim model availability without checking the installed
VS Code configuration.

## Model Selection

- Use exact provider-qualified model selectors from the live `runSubagent`
  registry. Do not use Auto or silently substitute another model.
- Record the selected model and any routing error. Do not promise cost,
  pricing tier, isolation, or task quality that the tools cannot verify.
- Escalate protocol safety, contradictory contracts, and repeated verification
  failures to the user. Delegates do not approve requirement changes.

### Current Routing Evidence (2026-10-02)

The live `runSubagent` registry exposed these exact selectors for the proposed
roles: `API Anatel DeepSeek V4 Flash (copilot)`,
`API Anatel Qwen3 Coder (copilot)`, `Qwen3.5 9B — Local (customendpoint)`,
`Gemma  4 e4b - Local (customendpoint)`, and `GPT-6 Luna (copilot)`. Each exact
selector returned a unique-token smoke response. This confirms basic
invocation in this session only, not task quality, backend version, or future
availability. Selected-model metadata was not consistently exposed. `Explore`
availability. Selected-model metadata was not consistently exposed. `Explore`
is the only named subagent and is read-only; no write-capable custom agent is
currently installed. These roles are assignment prompts, not installed custom
agents. A smoke token confirms model routing only, not write/test tool access.
Use Qwen/Gemma as primary coding sessions with verified agent-mode workspace
tools for implementation. Use `Explore` with the selected reviewer model for
read-only review. If write-capable subagent delegation is required, configure
and verify a custom implementation agent first.

A bare `Qwen3.5 9B — Local` selector was rejected; the exact
`(customendpoint)` selector worked. Match the live registry exactly,
including provider suffixes and spacing.

Other listed candidates not tested for these roles include
`Gemma  4 12b qat - Local (customendpoint)`,
`Qwen3.8 27B - Local (customendpoint)`, `GPT-5.3-Codex (copilot)`, and
`Claude Sonnet 5.5 (copilot)`. `Auto (copilot)` is not an approved fallback.
Use an alternative only after explicit user confirmation; if a selected route
is unavailable, stop and report the exact error rather than substituting.

For `(copilot)` route failures, check Copilot sign-in, model entitlement or
organization policy, and extension output. For `(customendpoint)` failures,
check that the local provider endpoint is reachable and the exact model is
installed/loaded. Preserve the error and returned model list; never include
secrets in diagnostics.

### Proposed Assignment (2026-10-02)

Availability evidence: see **Current Routing Evidence** above. No
transfer-specific custom-agent definitions were found. The exact model
selectors are live-enumerated, but smoke responses are not benchmarks or
evidence of role quality. A model is the engine; a custom agent supplies its
role, instructions and tools.

| Proposed role | Exact provider-qualified selector | Assigned work | Quality boundary |
|---|---|---|---|
| Transfer Coordinator | `API Anatel DeepSeek V4 Flash (copilot)` | Task decomposition, file leases, tracker updates, consolidation of findings | Escalate contract/safety decisions; cannot approve requirement changes itself |
| Transfer Implementer | `API Anatel Qwen3 Coder (copilot)` | Primary MATLAB/JS implementation, especially manager, HTTP worker, adapters and panel | Separate review and static evidence required for every batch |
| Transfer Reviewer | `API Anatel DeepSeek V4 Flash (copilot)` | Independent read-only correctness, lifecycle and contract review | Fresh context; inspect actual code, not only the implementer's summary |
| Transfer Mechanical Worker | `Qwen3.5 9B — Local (customendpoint)` | Bounded renames, reference inventories and small deterministic edits | No protocol invention or cross-module contract decisions |
| Transfer Documentation Worker | `Gemma  4 e4b - Local (customendpoint)` | Small README/Portuguese UI wording proposals and artifact consistency checks | English identifier preservation and technical review required; do not own complex implementation |
| Transfer Safety Reviewer / Escalation | `GPT-6 Luna (copilot)` | POST replay and cookie safety, identity/history decisions, unresolved reviewer disagreement and stubborn defects; Content-Range is out of scope | Focused evidence packets only; use it instead of other paid Copilot models |

These are provisional task fits, not claims that one model is objectively
stronger in MATLAB. Organizational API model labels do not disclose exact
versions, context limits or tool-call capability. Confirm those before
activation. Local quantization and context settings also affect reliability.

**Phase routing:** use `Gemma  4 e4b - Local (customendpoint)` as a primary
coding session with workspace write tools for the bounded T0 README
translation, with `API Anatel DeepSeek V4 Flash (copilot)` reviewing the
translated technical content read-only through `Explore`. Use
`API Anatel Qwen3 Coder (copilot)` as a primary coding session with workspace
write tools for P0 documentation/API inspection and P1 rename implementation;
DeepSeek reviews each completed slice read-only through `Explore`. For P10,
use these exact Qwen/DeepSeek routes only after backend and testing
authorization. `GPT-6 Luna (copilot)` may serve
as coordinator for a run only when the user explicitly assigns that override;
the default coordinator in this draft remains DeepSeek. Use Luna for high-risk
escalation when explicitly selected, not as an automatic fallback.

**Scheduling and cost rules:**

- At most one `(customendpoint)` local-model task runs at a time. Do not start
  another local invocation until the current one completes; the coordinator
  enforces this explicitly.
- API work may overlap local work only with disjoint file leases and within
  the approved sequential phase. Remote tasks do not consume the local-model
  slot. Do not assume unlimited organization concurrency or quotas.
- Consider time and resource cost as well as model access. Use the
  user-selected `API Anatel Qwen3 Coder (copilot)` for complex implementation
  instead of accumulating unnecessary local-model repair cycles.
- After two unsuccessful repair/review cycles on the same defect, stop and
  escalate with the smallest relevant diff, contract and failure evidence.
- Never add `GPT-6 Luna (copilot)` as an automatic fallback in another role.
  Request it explicitly when escalation is justified and report the selection.
  If unavailable, stop and report; do not silently use another paid model.
- Keep each task self-contained with only relevant contract sections/files.
  Record actual model, elapsed time, review findings and repair count in the
  tracker. Avoid repeated whole-repository prompts and unnecessary delegates.

### Routing Verification And Optional Calibration

Before each invocation, confirm the exact provider-qualified selector in the
live `runSubagent` model list. A model-picker label alone does not guarantee
subagent routing. The 2026-10-02 smoke checks confirm basic invocation only.

The official [VS Code subagent documentation](https://code.visualstudio.com/docs/agents/run/subagents#_select-the-model-for-a-subagent)
describes explicit invocation model selection ahead of custom-agent model
configuration, followed by Auto/inheritance. It also documents cost-tier
checks that can reject a requested model. Use explicit routing, avoid Auto,
and verify selected-model metadata when available. If exact routing fails,
stop with the error; use another session only after explicit user approval and
confirmation of the exact selected model.

No benchmarks were run. An optional future calibration can use the same
three small, read-only tasks for each model: a rename inventory, a review of
seeded callback/identity/replay defects, and a Brazilian Portuguese README
revision that preserves API identifiers. Supply synthetic fixtures rather
than editing production code. Measure factual accuracy, missed serious
defects, tool/schema compliance, latency and coordinator repair effort.
Require zero missed seeded critical defects for safety-review qualification;
do not treat this small sample as general proof of code quality. Any tool or
model-routing failure is reported separately from answer quality.

## Future Coordinator Request

```text
Act as coordinator for docs/plans/http-transfer-upload-plan.md and its
implementation tracker. Read the scoped instructions draft and Appendix A.

Authorization: [review only / implement Phase N only].
Implementation model: [exact available model label].
Independent review model: [exact available model label].

First resolve the affected approval gates with me. Do not change approved
requirements without approval. Do not activate customization files unless
I explicitly authorize activation.

Use separate implementation and read-only review agents. Assign explicit
file leases. Follow the plan's sequential phases; within one phase parallelize
only genuinely independent tasks with disjoint files. Do not launch a review
of an unfinished concurrently changing diff.

Respect deferred runtime/backend tests. No endpoint contact, authentication,
backend configuration, commits, branches or additional phases are authorized.

Repair review findings within scope and repeat focused permitted checks.
Update the tracker with evidence, actual model selections, skipped checks,
blockers and coordinator disposition. Stop after the authorized phase.
```

## Implementation Assignment

```text
Task ID / approved phase:
Approved specification revision / blocker resolutions:
Exact writable paths:
Relevant existing anchors and dependencies:
Required behavior / contracts:
Explicit exclusions:
Permitted verification commands:

Read the approved plan, Appendix A and scoped instructions. Preserve user
changes. Do not expand scope, launch agents, commit or perform live tests.
If a leased-file dependency is missing or ambiguous, report it before editing
outside the lease.

Return: changed files; behavior/contract delta; commands and significant
results; new vs baseline diagnostics; unresolved risks; deferred checks.
Do not claim runtime validation from static evidence.
```

## Independent Review Assignment

```text
Review Task [ID] read-only against the approved plan and Appendix A.
Allowed tools: read/search/diagnostics only.
Scope: [explicit paths and completed implementation delta].
Implementation evidence: [tracker record].

Check correctness, ownership, download regressions, LocalPath/URL identity,
source preservation, callback generations, history fields, HTTP replay/cookie
safety, Portuguese visible messages/READMEs, and permitted verification.

Lead with findings ordered by severity, citing actual file/line references
and a concrete failure scenario. Distinguish confirmed defects from missing
evidence. No implementation, terminal commands, delegation or live tests.
If no findings, say so and list residual unverified requirements.
```

## Completion Rule

The coordinator, not a delegate, closes a task after checking the actual diff,
independent review and permitted evidence. Static acceptance is labeled
`reviewed-static`; runtime validation remains deferred to Phase 10. A draft
or blocked task cannot be marked complete just because an agent returned.