# HTTP Transfer Implementation Tracker

Status: **execution authorized for T0, P0, and P1-P9; Phase 10 is not authorized**.

Specification: [plan and contract appendix](http-transfer-upload-plan.md).
Instructions: [inactive draft](http-transfer-instructions-draft.md).
Delegation: [roles and task templates](http-transfer-delegation-draft.md).

This tracker began as a readiness-review draft. The current user authorization
covers T0, P0, and P1-P9 sequentially; Phase 10 remains unauthorized. Entries
below are work allocation and evidence, not runtime validation.

## Approval Gates

The coordinator must obtain a decision for each blocker before starting the
affected phase. Record approved edits in the specification, not only here.

| ID | Affected phase | Conflict or risk | Proposed resolution for review | Status |
|---|---|---|---|---|
| B1 | 0 | Phase 0 runs public-network spikes despite D9 deferring runtime tests | Approved: offline documentation/API inspection with MATLAB R2024a Update 7; move all executable spikes to Phase 10 | Resolved |
| B2 | 3, 4 | `Accept-Ranges` and an empty PUT cannot safely establish partial-upload support | Approved: remove Content-Range uploads; tus is the only resumable protocol. No empty PUT probe or `Accept-Ranges` inference | Resolved |
| B3 | 2 | Renamed fields make old history entries incompatible with the new schema | Approved: no compatibility or migration. Use `transfer-history.json`; treat old-format entries as corrupt and delete them. Guarded workspace-root cleanup found no `download-history.json` | Resolved |
| B4 | 3, 4, 5 | A body-bearing request may be committed despite a missing/auth response | Approved: never automatically replay after possible submission. Persist `OutcomeUncertain`, require in-panel confirmation before manual restart, and recover tus chunks only from HEAD-confirmed offsets | Resolved |
| B5 | 2, 6 | Logical identity differs from deduplication and history-row grouping | Approved: group terminal history and attempt timestamps by Direction + exact URL + canonical LocalPath. Keep active rows per TaskID and live duplicate keys separate | Resolved |
| B6 | 4 | ProgressMonitor subclass placement and background support | Approved: add `datatransfer.UploadProgressMonitor` as a separate class file. R2024a syntax/API inspected; backgroundPool/DataQueue proof is a Phase 10 runtime check | Resolved |
| B7 | 1, 2 | Phase 1 mixed renames with contract changes and new components; `addTransfer` appeared in both phases | Approved: P1 renames existing symbols only, including `addDownload` → `addTransfer` once. P2 applies field/schema/Direction behavior; new components stay in their owning phases | Resolved |
| B8 | 6, 9 | Existing English README prose and UI examples conflict with D8 | Resolved by D8: translate all English README prose to Brazilian Portuguese before P0; use Portuguese for visible UI text and new READMEs, retaining English identifiers/docstrings | Resolved |

## Work Allocation

States: `not-started`, `blocked`, `in-progress`, `implemented-unverified`,
`reviewed-static`, `validated-runtime`. Static review is not runtime validation.
The existing plan requires sequential phases; do not relax that ordering
without approval. Parallel work inside a phase requires disjoint file leases.

| Task | Scope and file ownership | Dependencies | Acceptance evidence | State |
|---|---|---|---|---|
| R0 | Coordinator: specification and artifacts only | User review | Approved contracts and blocker dispositions recorded; readiness review complete | reviewed-static |
| T0 | README translation owner; writes only `src/General/+download/README.md` and `tests/auth/README.md` after inventory of all five current README files | R0 | English prose translated; identifiers, code and technical meaning preserved; path/link changes deferred to P1 | reviewed-static |
| P0 | MATLAB feasibility inspection; no network or runtime spikes until authorized | R0, B1, T0 | Supported API/syntax evidence; limitations recorded | reviewed-static |
| P1 | Rename owner: existing package/auth/UI/test symbols and paths only | P0 | Rename inventory, reference check, static diagnostics; no new components or behavior changes | reviewed-static |
| P2 | Contract owner: manager, history store, necessary fake/call-site updates | P1 | Direction, LocalPath/URL, hashes, schema 1, size-limit checks in diff | reviewed-static |
| P3 | HTTP owner; coordinator-assigned exact P3 write lease: `src/General/+datatransfer/sendHTTPRequest.m; new src/General/+datatransfer/uploadCapabilities.m; src/General/+datatransfer/downloadFileWorker.m; src/General/+datatransfer/downloadSourceMetadata.m; src/General/+datatransfer/transferFileName.m; src/General/+datatransfer/TransferManager.m (ONLY replace P2 local upload filename sanitizer call with the new shared sanitizer; no other manager behavior); src/General/+datatransfer/README.md; tests/transfers/README.md; src/Anatel/+ws/+auth/README.md. No other files. NOT in lease: F5Session.m, FileTransfer.m, TransferHistoryStore.m, TransferPanel.m, tests/auth/README.md, checkDownloadHttp.m, tests/transfers harnesses, icons/avatar, plan/todo, any P4 worker/monitor or any other new class/function.` | P2 reviewed-static; user authorization 2026-10-05 | Helper signature and safe method/body/redirect/cookie/header behavior per plan; capability discovery per §6.1 with optional sender function handle; download worker/metadata callsites updated; shared remote-name sanitizer used by manager; P3 static checks | reviewed-static |
| P4 | Upload owner; coordinator-assigned exact write lease: `new src/General/+datatransfer/uploadFileWorker.m; new src/General/+datatransfer/UploadProgressMonitor.m; new src/General/+datatransfer/UploadFileProvider.m (same-named subclass of matlab.net.http.io.FileProvider; overrides getData only for source-file reads and exact payload-byte notification to UploadProgressMonitor; must not alter source paths, request protocol, HTTP headers, or other behavior); new MATLAB ContentConsumer class src/General/+datatransfer/UploadResponseBodyConsumer.m (captures at most 64 KiB during reception and tracks BodyTruncated); src/General/+datatransfer/sendHTTPRequest.m (only add optional name-value ResponseConsumer and pass it as RequestMessage.send's third argument; preserve all P3 request/security behavior); src/General/+datatransfer/README.md (only update module table and current upload-transport status required by §3.5 after P4 adds worker/monitor; no broad rewrite). No other files.` The package README is included only because §3.5 requires affected README updates. `tests/transfers/README.md` and `src/Anatel/+ws/+auth/README.md` are excluded (no harness or adapter contract change in P4). | P3 reviewed-static; user authorization 2026-10-05 after P3 | Exact file-payload byte progress for raw and multipart uploads via `UploadFileProvider` and `UploadProgressMonitor` (not request/envelope estimates); streaming, confirmed tus offsets, source preservation, upload callback-only response body capped at 64 KiB during reception by `UploadResponseBodyConsumer`, with `BodyTruncated` reported in completion info and neither body nor truncation status persisted; package README limited to module table and current §3.5 upload-transport status after worker/monitor are added; backgroundPool/DataQueue runtime proof in Phase 10 | reviewed-static |
| File lease (explicit paths): new src/General/+datatransfer/uploadFileWorker.m; new src/General/+datatransfer/UploadProgressMonitor.m; new src/General/+datatransfer/UploadFileProvider.m (same-named subclass of matlab.net.http.io.FileProvider; overrides getData only for source-file reads and exact payload-byte notification to UploadProgressMonitor; must not alter source paths, request protocol, HTTP headers, or other behavior); new MATLAB ContentConsumer class src/General/+datatransfer/UploadResponseBodyConsumer.m (captures at most 64 KiB during reception and tracks BodyTruncated); src/General/+datatransfer/sendHTTPRequest.m (only add optional name-value ResponseConsumer and pass it as RequestMessage.send's third argument; preserve all P3 request/security behavior); src/General/+datatransfer/README.md (only update module table and current upload-transport status required by §3.5 after P4 adds worker/monitor; no broad rewrite). No other files.
| P5 | Adapter owner; exact implementer lease: new `src/General/+datatransfer/HTTPFileTransfer.m`; `src/Anatel/+ws/+auth/FileTransfer.m`; `src/Anatel/+ws/+auth/F5Session.m` only if required by approved request-context methods; `src/General/+datatransfer/TransferManager.m`; `src/General/+datatransfer/README.md`; `src/Anatel/+ws/+auth/README.md`. README rationale: package and auth READMEs document adapter ownership and currently describe the old download-only boundary. Explicit exclusions: `tests/transfers/README.md` and `tests/auth/README.md` (P5 changes no harness, fake, or app contract); all other source, tests, UI, panel, fake, plan, and asset files. Tracker is coordinator evidence, not implementer lease. Observed Git state: branch `auth`, clean worktree, up to date with `origin/auth`; HEAD `39a21b56e7923c01080e9b33c010351bf2281b5a`, parent `073b739d4f7d43d8735da8c8853fdc55dbd3e02a` (user-supplied expected HEAD `073b739` is one commit behind); annotated `transfer-management-refactor-stage-1` targets `f1959bb2bc249e30e38c270427baea5495ad4040`; annotated `transfer-management-refactor-stage-2` targets `b5aada52b8259eaadd651a1eda29bb547e024e03`; `transfer-management-refactor-p5` absent. | P4 | Direction-neutral async lifecycle and worker-generation guards; safe pre-body reauthentication and HEAD-confirmed Tus offset recovery; protocol/IsResumable StateFcn publication and manager persistence; normalized upload TotalBytes; non-resumable pause no-op; launch-failure cleanup. Static DoD and fresh independent read-only review passed. Runtime remains deferred to Phase 10. | reviewed-static |
| P6 | UI owner; exact write lease: `src/General/+ui/TransferPanel.m`; `tests/transfers/TransferPanelFakeTransfer.m`; new `src/General/icons/transfer-download.svg`; new `src/General/icons/transfer-upload.svg`; `src/General/+datatransfer/README.md`; `tests/transfers/README.md`; `src/Anatel/+ws/+auth/README.md`; `src/General/+datatransfer/TransferManager.m` ONLY initialize `IsResumable` as true for downloads and for uploads only when `ResolvedProtocol='tus'` and `UploadURL` is nonempty; no other manager behavior. | P5 reviewed-static; commit/tag `efc7c1786579a0c6f21736878e6b21196cded8df` / `transfer-management-refactor-p5`. User authorization 2026-10-06 extends P6 lease to clear the restored-Tus-resumability blocker and permits one focused deterministic local regression check. | README rationale: package and transfer-test READMEs document panel APIs/rows; auth README documents TransferPanel usage. Exclusions: `tests/auth/README.md` (P8 owns F5BrowserTestApp integration); `pingTransferAvatar.html` and its harness (P7 owns them); every other source, test, UI asset, fake, harness, plan, and todo file. Contract review: §§4.2 and Phase 6 require adapter `IsResumable` state to drive the panel action; no plan edit is needed. Observed before this tracker edit: branch `auth`; HEAD `efc7c1786579a0c6f21736878e6b21196cded8df`, parent `39a21b56e7923c01080e9b33c010351bf2281b5a`; one commit ahead of `origin/auth`; stage-1 tag targets `f1959bb2bc249e30e38c270427baea5495ad4040`; stage-2 tag targets `b5aada52b8259eaadd651a1eda29bb547e024e03`; annotated P5 tag targets HEAD; P6 tag absent. Initial worktree already had tracker plus seven P6 files modified/untracked; authorship and validation unknown. Earlier supplied HEAD `073b739` was behind `39a21b5`; never rewrite history. Implementer: Transfer Implementer, GPT-6 Luna (copilot), read/search/edit/execute. Reviewer: Transfer Reviewer, GPT-6 Luna (copilot), read/search only. Coordinator: Transfer Coordinator, GPT-6 Luna (copilot). No nested delegation. Prior P6 findings were repaired within lease: interrupted upload history requires confirmation; fake preserves Tus URL/offset and publishes resumability. Manager fix: initial task state is resumable for downloads and only for uploads with resolved Tus protocol plus nonempty upload URL. Independent read-only review found no confirmed defects and approved the manager change against §§4.2/Phase 6. Editor diagnostics: no errors in `TransferManager.m`; prior panel/fake diagnostics also clean. MATLAB `which` resolved `datatransfer.TransferManager`. `checkcode` ran and reported five loop-growth warnings at untouched lines 472, 530, 996, 1033, and 1036; no analyzer errors. Disposable MATLAB `-batch` regression passed: restored Tus upload is an `awaitingConflictDecision` partial snapshot with `IsResumable=true`; history preserves confirmed `UploadOffset=4`. No network, authentication, backend setup, UI harness, unrelated tests, or broad Phase 10 work ran. P6 `reviewed-static`; do not push or start P7. | reviewed-static |
| P7 | Asset owner; exact lease: `src/General/+ui/html/pingTransferAvatar.html`; `tests/transfers/checkPingTransferHtml.m`; `tests/transfers/README.md`. README rationale: translate only stale download-only harness/payload prose per D8; package README already documents direction and P7 ownership; auth README only documents asset path and is excluded. Exclusions: `orbitDownloadAvatar.html`, `checkOrbitDownloadHtml.m`, `TransferPanel`, all other UI assets/tests, `F5BrowserTestApp`, other READMEs, plan, todo. | P6 reviewed-static, commit/tag `fc6ed26e3f9ef54cea31d63741d5e833e42b420b` / `transfer-management-refactor-p6`; parent/P5 tag `efc7c1786579a0c6f21736878e6b21196cded8df`. Observed: `auth`, clean, HEAD `fc6ed26e3f9ef54cea31d63741d5e833e42b420b` aligned with `origin/auth`; stage-1 `f1959bb2bc249e30e38c270427baea5495ad4040`; stage-2 `b5aada52b8259eaadd651a1eda29bb547e024e03`; P7 tag absent. | §5.5 only: require `direction` exactly `download`/`upload`; reject missing/invalid values and emit `pingTransferAvatarError`; preserve 23 coordinates; distinct upload color; glyphs ↓/↑/↕ by visible direction; keep nonzero upload-rate sentinel and ready/click events. Harness includes direction and dispatches via `HTMLEventName`/`HTMLEventData` only; remove legacy/payload-type fallbacks. Implementer: Transfer Implementer, GPT-6 Luna (copilot), read/search/edit/execute. Reviewer: Transfer Reviewer, GPT-6 Luna (copilot), read/search only. No nested delegation. Editor diagnostics and static HTML/harness review only; no harness/tests, runtime/project checks, network, auth, backend, or Phase 10 work. | reviewed-static |
| P8 | Integration owner; exact implementer write lease: `tests/auth/F5BrowserTestApp.m`; `tests/auth/README.md`. Tracker is coordinator-owned evidence, outside the implementer lease. Explicit exclusions: `src/General/+ui/html/pingTransferAvatar.html` (dirty user edit); all other UI assets; all `tests/transfers` files; other READMEs; plan; todo; P9; Phase 10. Implementer: Transfer Implementer, GPT-6 Luna (copilot), read/search/edit/execute. Reviewer: Transfer Reviewer, GPT-6 Luna (copilot), read/search only. No nested delegation. | P7 reviewed-static, commit/tag `50a09d3e77829ab2cecef3c3d0d9ad89065e663a` / `transfer-management-refactor-p7`; parent and P6 tag `fc6ed26e3f9ef54cea31d63741d5e833e42b420b`. Observed at dispatch: branch `auth`; HEAD `50a09d3e77829ab2cecef3c3d0d9ad89065e663a`; `origin/auth` `fc6ed26e3f9ef54cea31d63741d5e833e42b420b`; one commit ahead. P5 tag `efc7c1786579a0c6f21736878e6b21196cded8df`; stage-1 `f1959bb2bc249e30e38c270427baea5495ad4040`; stage-2 `b5aada52b8259eaadd651a1eda29bb547e024e03`; P8 tag absent. Only pre-existing dirty file was `src/General/+ui/html/pingTransferAvatar.html`, an attribute line-wrap; preserved and excluded. `tests/transfers/target` was absent; fixed app reference uses `target/upload-test.txt`; fixture creation excluded. | Added upload image, mode-aware source selection, explicit webApp `LocalPath`, POST `/post` and PUT `/put`, inert protected-F5 placeholder, exact `@(request) ws.auth.FileTransfer(app.Session, request)` factory, and affected README prose in Brazilian Portuguese. Initial independent review found inaccurate README navigation/read routing prose; repaired and reviewed. Coordinator pass found and fixed `/put` defaulting to POST; reviewer rechecked final mapping. Static: app editor diagnostics report no errors; implementer reports `checkcode` without new warnings, `which` resolved app/adapter/panel, 12 relative links validated, and `git diff --check` passed. No app/harness/runtime/network/auth/backend checks run; Phase 10 deferred. The webApp fixture is absent and must be supplied before that mode can run. Fresh read-only review: no confirmed defects. | reviewed-static |
| P9 | Documentation owner: affected READMEs/packaging and stale links | P8 | Portuguese READMEs, correct package/asset paths, no premature completed status | Not-started |
| P10 | Validation owner and independent reviewer: planned harnesses and backend evidence | P9, configured backend, explicit testing authorization | Plan section 8 results; skipped/unavailable gates remain visible | Not-started |

## Ownership Rules

- Coordinator assigns one write owner per file and includes related call
  sites in the lease. Shared manager/adapter interfaces are not independently
  edited by two agents.
- Agents cannot expand a lease, delegate further, commit, create branches,
  configure backend services, or change approved contracts on their own.
- In the same worktree, use separate read-only review after an implementation
  batch completes; never review a concurrently changing diff as final evidence.
- A documentation agent owns only its leased files. Implementers report doc
  changes to that owner instead of competing over README edits.

## Evidence Record Template

Duplicate this record for each completed task; leave placeholders until used.

```text
Task / approved phase:
Specification revision and approved blocker decisions:
Implementation agent and actual selected model:
Reviewer agent and actual selected model:
File lease (explicit paths):
Existing user changes preserved:
Changes / contract impact:
Static commands, exit codes and significant output:
Editor diagnostics (baseline vs new):
Runtime/backend checks: deferred / authorized results:
Review findings (severity, file and line):
Repairs and repeated focused checks:
Unverified assumptions / blockers:
Final state and coordinator disposition:
```

## Deferred Cases

Preserve the plan's section 8 matrix and add direction isolation, exact
download-URL hash, canonical upload-path hash, distinct terminal history rows
for the same URL at different LocalPaths, active rows sharing a LogicalFileID,
uncertain POST outcomes and restart confirmation, request-body limits including
multipart overhead, confirmed tus offsets, exactly one upload preflight per
`prepare`, rejection of an unprepared worker request, ProgressMonitor/DataQueue
operation in `backgroundPool`, stale callback rejection, and upload source
preservation on cancel/history removal. Do not build these harnesses before
the authorized validation phase.

## Initial Readiness Review (2026-10-02)

Initial authorization was readiness review only. The subsequent B6
authorization covers offline MATLAB API/syntax inspection only. B1-B8 are
resolved and R0 is reviewed-static. T0 and P0 remain not-started; no
implementation phase has started. No production or test
files were changed, and no tests were executed. No endpoints, authentication,
backend services, branches, or commits were used.

### Routing Evidence

- The session exposed one named agent, `Explore`; no transfer-specific custom
  agent was available in the invocation list. No nested delegation was used.
- The live `runSubagent` model list exposed these exact provider-qualified
  selectors for the proposed roles: `API Anatel DeepSeek V4 Flash (copilot)`,
  `API Anatel Qwen3 Coder (copilot)`, `Qwen3.5 9B — Local (customendpoint)`,
  `Gemma  4 e4b - Local (customendpoint)`, and `GPT-6 Luna (copilot)`.
- Sequential smoke calls using each exact selector returned the expected
  unique token. This confirms basic invocation in this session, not role
  quality, backend version, or future availability. Exact selected-model
  metadata was not consistently exposed. No Auto selection or substitution
  was used.
- A bare `Qwen3.5 9B — Local` selector was rejected; the tool returned its
  available-model list. Adding `(customendpoint)` made the exact route pass.
  Match the live list exactly, including provider suffixes and spacing.
- Other currently listed candidates include `Gemma  4 12b qat - Local
  (customendpoint)`, `Qwen3.8 27B - Local (customendpoint)`,
  `GPT-5.3-Codex (copilot)`, and `Claude Sonnet 5.5 (copilot)`. They were not
  probed or assigned. Require the user's explicit model choice before any
  substitution; if a route is unavailable, report the exact error and stop.

### Findings And Evidence

1. **Resolved — B2, Content-Range excluded.** The user approved removing
  Content-Range uploads. Tus 1.0.0 is the only resumable protocol; the plan
  prohibits empty PUT probes, `Accept-Ranges` inference, and `308` upload
  acknowledgements. No probe was run. See
  [plan](http-transfer-upload-plan.md#L489).
2. **Resolved — B4, ambiguous body operation.** The user approved no
  automatic replay after possible submission, including auth/missing-response
  outcomes. The plan persists `OutcomeUncertain`, requires in-panel
  confirmation before manual restart, and uses `HEAD` to confirm tus offsets
  after interrupted `PATCH` requests. No backend idempotency contract is
  assumed. See [plan](http-transfer-upload-plan.md#L477).
3. **Resolved — B3, legacy history disposal.** The user approved no
  compatibility or migration; old-format entries are treated as corrupt and
  deleted, and legacy partial-transfer state is not restored. A guarded
  PowerShell check for `C:\GitHub\SupportPackages\download-history.json`
  found no file, so no deletion occurred. See the policy in
  [plan](http-transfer-upload-plan.md#L356). The existing store currently
  quarantines malformed history, so implementation must delete the identified
  old entry shape instead.
4. **Resolved — B5, identity and row grouping.** The user approved terminal
  history grouping by `Direction` + exact `URL` + canonical `LocalPath`, with
  attempt timestamps per row key and active rows per `TaskID`. Live duplicate
  keys remain separate as specified in §5.1. The current panel groups by
  `LogicalFileID` + `SourceURL`, so the approved key prevents same-URL downloads
  to different local paths from replacing each other's terminal rows. See
  [plan](http-transfer-upload-plan.md#L323),
  [current history grouping](../../src/General/+ui/DownloadPanel.m#L720), and
  [current identity helper](../../src/General/+ui/DownloadPanel.m#L1461).
5. **Resolved — B7, phase boundaries.** The user approved P1 as existing-symbol
  and path renames only, with `addDownload` → `addTransfer` performed once.
  P2 owns direction/field/schema behavior and later phases own new components.
  The plan retains sequential ordering; P0 is offline-only but remains
  not-started until R0 closes. See [Phase 1 and Phase 2](http-transfer-upload-plan.md#L570).
6. **Resolved — B6, progress monitor syntax.** The user approved a separate
  `datatransfer.UploadProgressMonitor` class file for Phase 4. MATLAB
  24.1.0.2837808 (R2024a Update 7) help confirms `classdef` requires a
  same-named file and `ProgressMonitor` is abstract with required `Direction`
  and `Value` properties. The help-only commands were
  `matlab.exe -batch 'help classdef'` and
  `matlab.exe -batch 'help matlab.net.http.ProgressMonitor'`. R2024b is not
  installed. No backgroundPool/DataQueue execution was attempted; that runtime
  proof remains deferred to Phase 10. No code was implemented.
7. **Resolved — B8, language and translation scope.** D8 is sufficient:
  READMEs and visible UI text are in Brazilian Portuguese; identifiers,
  comments, and docstrings remain English. Inventory found five current
  READMEs: `src/General/+download/README.md` is English and `tests/auth/README.md`
  contains English prose; the other three are already Portuguese. T0 translates
  those two before P0, preserving technical content and deferring path changes
  to P1. The new package README is Portuguese. No README translation has been
  executed in this review.
8. **Resolved — preflight ownership.** The user approved
  `HTTPFileTransfer.prepare` as the sole `uploadCapabilities` caller. The
  worker requires a resolved protocol and returns
  `datatransfer:uploadFileWorker:unpreparedRequest` instead of issuing another
  OPTIONS request. Exactly-one-preflight and rejection behavior are deferred
  to Phase 10 harness validation.

### Delegate Reconciliation

- DeepSeek correctly identified the P0/D9, Content-Range, POST replay,
  history, and Phase 1 scope conflicts. Its B8 conclusion that the plan is
  already consistent with D8 is not supported: Phase 9 explicitly says the
  package README is English, while D8 and the instructions cover READMEs.
- Qwen correctly confirmed that the current HTTP helper accepts only GET and
  HEAD, and that the current architecture is download-only. Its claim that
  the history store rejects extra upload fields is inaccurate: normalization
  ignores undeclared fields, but rejects missing required fields. Its
  "complete rewrite" conclusion is not established by the inspected code;
  the proposed phased design is an implementation scope, not evidence of
  impossibility.
- Confirmed current-code facts: cookie attachment is restricted to the
  configured exact host over HTTPS; download worker retries follow exceptions
  and the F5 adapter can reauthenticate/restart a download. Those GET-specific
  paths must not be carried over to body-bearing POST replay without the B4
  safety rule. See
  [HTTP helper](../../src/General/+download/downloadHTTPResponse.m#L56),
  [download worker](../../src/General/+download/downloadFileWorker.m#L103),
  and [F5 adapter](../../src/Anatel/+ws/+auth/FileDownload.m#L234).

## Execution Record

### T0 — README translation (2026-10-02)

```text
Task / approved phase: T0, initial README translation
Specification revision and approved blocker decisions: Revision 3; B1-B8 resolved
Implementation agent and actual selected model: Transfer Implementer; API Anatel Qwen3 Coder (copilot)
Reviewer agent and actual selected model: Explore (read-only); API Anatel DeepSeek V4 Flash (copilot)
File lease (explicit paths): src/General/+download/README.md; tests/auth/README.md
Existing user changes preserved: Yes; pre-existing untracked .github/agents/ and docs/ artifacts were not modified
Changes / contract impact: Translated English explanatory prose to Brazilian Portuguese; completed the final package README sentence; identifiers, paths, links, code examples, and behavior unchanged
Static commands, exit codes and significant output: No executable command run; two read-only content reviews performed. The first found untranslated auth TODO prose and an incomplete package README sentence; both were repaired. The repeat review found no remaining issues.
Editor diagnostics (baseline vs new): Not applicable to README prose; no code diagnostics requested
Runtime/backend checks: Deferred; none run
Review findings (severity, file and line): Initial findings were limited to the T0 translation lease and repaired before closure; no findings on repeat review
Repairs and repeated focused checks: Translated the three auth README TODO items and completed the package README sentence; repeated DeepSeek read-only review passed
Unverified assumptions / blockers: None for the translation-only scope
Final state and coordinator disposition: reviewed-static; T0 closed
```

### P0 — MATLAB feasibility inspection (2026-10-02)

```text
Task / approved phase: P0, offline MATLAB documentation/API inspection
Specification revision and approved blocker decisions: Revision 3; B1-B8 resolved
Implementation agent and actual selected model: Transfer Implementer; API Anatel Qwen3 Coder (copilot)
Reviewer agent and actual selected model: Explore (read-only); API Anatel DeepSeek V4 Flash (copilot)
File lease (explicit paths): docs/plans/http-transfer-upload-plan.md (Appendix B and authorization status only)
Existing user changes preserved: Yes; the existing untracked plan and other docs were preserved; only the authorized plan file was edited
Changes / contract impact: Added Appendix B with MATLAB 24.1.0.2837808 (R2024a Update 7) help/API facts, exact successful commands, implementation interpretation, and runtime-only limitations. No approved contract changed. Plan status now reflects T0/P0/P1-P9 authorization and Phase 10 deferral.
Static commands, exit codes and significant output: Get-Command resolved C:\Program Files\MATLAB\R2024a\bin\matlab.exe. Two `matlab.exe -batch` help/API queries succeeded and reported the exact release, API facts, and RequestMethod members. `help matlab.net.http.GenericField` returned not found. The first shell attempt for query 2 failed at PowerShell parsing before MATLAB launched; retry via `matlab.exe` on PATH succeeded. The terminal tool did not expose numeric exit codes.
Editor diagnostics (baseline vs new): No code diagnostics applicable to plan prose; tracker diagnostics report no errors
Runtime/backend checks: No project code, scripts, transfer logic, tests, network, authentication, endpoint, benchmark, background execution, or wire behavior ran; deferred to Phase 10
Review findings (severity, file and line): Initial review found the appendix absent after the first implementation report; actual file inspection confirmed no edit. After evidence-backed repair, reviewer requested clearer Direction fact/interpretation separation; wording was clarified. Final DeepSeek review found no remaining issues.
Repairs and repeated focused checks: Reassigned the same exact Qwen route with raw help evidence, confirmed Appendix B was actually present, clarified no-project-code wording, listed successful commands, and separated documented Direction behavior from the implementation interpretation. Final read-only review passed.
Unverified assumptions / blockers: Documentation does not establish memory-bound streaming, MultipartFormProvider wire framing, progress callback threading, backgroundPool/DataQueue behavior, server behavior, cookie/authentication handling, or live transport behavior.
Final state and coordinator disposition: reviewed-static; P0 closed; runtime/backend evidence remains Phase 10 only
```

### P1 — mechanical rename (blocked before edits, 2026-10-02)

```text
Task / approved phase: P1, existing-symbol/path renames only
Specification revision and approved blocker decisions: Revision 3; B1-B8 resolved; P0 completed
Implementation agent and actual selected model: Transfer Implementer route accepted; API Anatel Qwen3 Coder (copilot)
Reviewer agent and actual selected model: Not invoked; no completed diff existed to review
File lease (explicit paths): Existing src/General/+download/**, src/General/+ui/DownloadPanel.m, src/General/+ui/html/pingDownloadAvatar.html, five existing src/General/icons/download-*.svg files, src/Anatel/+ws/+auth/FileDownload.m, F5Session.m, tests/downloads/**, tests/auth/F5BrowserTestApp.m and README.md, src/Anatel/+ws/+auth/README.md, todo.md
Existing user changes preserved: Yes; no P1 files were modified
Changes / contract impact: None. Worktree and source search confirm `DownloadManager.m` remains in +download and its manager `addDownload` declaration is unchanged; no +datatransfer destination exists.
Static commands, exit codes and significant output: `mcp_gitkraken_cli_git_status` showed only T0 README modifications and existing untracked .github/agents/ and docs/. `file_search` found the old manager file and no TransferManager destination. `grep_search` confirmed `function taskID = addDownload(obj, request)` remains at the old path.
Editor diagnostics (baseline vs new): No P1 source files changed
Runtime/backend checks: Not run; unauthorized/deferred
Review findings (severity, file and line): No reviewer launched because there was no completed implementation diff
Repairs and repeated focused checks: Not applicable
Unverified assumptions / blockers: The implementation response stated: “I'll use the insert_edit_into_file tool to create the TransferManager.m file” but produced no edit result or explicit tool error. `insert_edit_into_file` is not an available tool in this session; the response did not invoke the agent's declared `edit` tool. The exact missing-tool error object was not surfaced.
Final state and coordinator disposition: blocked before edits. Stopped per the user’s routing/write-tool rule; no fallback editor was used.
```

### P1 — implementation start (2026-10-02)

```text
Task / approved phase: P1 continuation; existing-symbol/path renames only
Specification revision and approved blocker decisions: Revision 3; B1-B8 resolved; P0 completed
Implementation agent and actual selected model: Transfer Implementer not yet dispatched. Coordinator selector: Transfer Coordinator, model GPT-6 Luna (copilot); no substitution.
Reviewer agent and actual selected model: Transfer Reviewer is read-only; correctly declined write access during tool checks
File lease (explicit paths): Existing src/General/+download/**, src/General/+ui/DownloadPanel.m, src/General/+ui/html/pingDownloadAvatar.html, five existing src/General/icons/download-*.svg files, src/Anatel/+ws/+auth/FileDownload.m, F5Session.m, tests/downloads/**, tests/auth/F5BrowserTestApp.m and README.md, src/Anatel/+ws/+auth/README.md, todo.md
Existing user changes preserved: Pre-existing T0 Brazilian Portuguese translations in src/General/+download/README.md and tests/auth/README.md overlap the lease and must be preserved while P1 references are updated. Existing untracked .github/agents/ and docs/ are also preserved. The user-provided pre-edit inventory confirmed leased source/test paths exist, planned destination paths do not exist, and no smoke files remain.
Changes / contract impact: P1 implementation is starting. No implementation changes are evidenced by the tool checks below; retain P1's historical blocked-before-edits record above. No contract changes authorized.
Static commands, exit codes and significant output: Transfer Implementer created a probe file, edited it to add a first-line MATLAB comment, verified it, then discarded it. Transfer Coordinator passed create/edit smoke tests and cleaned its probe. Both smoke-test files are absent.
Editor diagnostics (baseline vs new): Not applicable to tool checks; no phase source changes evidenced
Runtime/backend checks: Not run; unauthorized/deferred
Review findings (severity, file and line): Transfer Reviewer correctly declined writes because the role is read-only; no implementation diff was reviewed
Repairs and repeated focused checks: Smoke-test probes were discarded; user confirmed both files are absent
Unverified assumptions / blockers: Smoke tests establish tool availability only, not P1 implementation evidence. Transfer Implementer dispatch is pending because no agent-dispatch tool is exposed in this session. Preserve the exact lease; do not expand it.
Final state and coordinator disposition: in-progress; implementation kickoff is recorded, but implementer dispatch remains pending. Do not mark implemented-unverified or reviewed-static until implementation and its required evidence are complete.
```

### P1 — mechanical rename (completed 2026-10-05)

```text
Task / approved phase: P1, existing-symbol/path renames only. Spec rev 3; B1-B8 resolved; P0 reviewed-static.
Specification revision and approved blocker decisions: Revision 3; B1-B8 resolved
Implementation agent and actual selected model: Transfer Implementer; GPT-6 Luna (copilot). Agent routes after the model change (all smoke-tested 2026-10-05): Coordinator = Transfer Coordinator, Claude Sonnet 5.5 (copilot), replied COORDINATOR_OK; Implementer = Transfer Implementer, GPT-6 Luna (copilot), created/edited/verified/deleted a probe file (IMPLEMENTER_OK, probe absent afterwards). Prior routes (Qwen3 Coder implementer, DeepSeek V4 Flash reviewer) produced an incomplete first pass: the earlier implementer runs ended mid-sentence with a partial move (renamed paths, but stale package/class refs, old `download:` error ids, manager still `addDownload`/`DownloaderFactory`, F5Session methods with rewritten bodies, FileDownload.m edited in place plus a divergent FileTransfer.m). Subsequent work reset those files to HEAD-derived content with renames only.
Reviewer agent and actual selected model: Transfer Reviewer; GPT-6 Luna (copilot), read-only, smoke-tested 2026-10-05 (REVIEWER_OK)
File lease (explicit paths): Unchanged and explicit: src/General/+download/** (now +datatransfer), src/General/+ui/DownloadPanel.m, src/General/+ui/html/pingDownloadAvatar.html, five src/General/icons/download-*.svg, src/Anatel/+ws/+auth/FileDownload.m, F5Session.m, tests/downloads/** (now tests/transfers), tests/auth/F5BrowserTestApp.m and README.md, src/Anatel/+ws/+auth/README.md, todo.md
Existing user changes preserved: T0 Portuguese README translations kept (package README and tests/auth/README.md); untracked .github/agents/ and docs/ untouched; nothing staged, committed, branched, reset or reverted
Changes / contract impact: package src/General/+download -> +datatransfer (TransferManager, TransferHistoryStore, sendHTTPRequest, transferFileName; download-only downloadFileWorker/downloadSourceMetadata/downloadContentDispositionFileName/moveToTrash kept); DownloadPanel -> TransferPanel (TransferFactory option, member/method renames Download->Transfer, addDownload retained on the panel); manager addDownload -> addTransfer once with all internal callers; pingDownloadAvatar.html -> pingTransferAvatar.html with events transferAvatarReady/transferAvatarClick and pingTransferAvatar* identifiers; icons transfer-{start,pause,continue,restart,trash}.svg; FileDownload -> ws.auth.FileTransfer; F5Session getDownloadContext/authenticateForDownload/validateDownloadURL -> getRequestContext/authenticateForRequest/validateRequestURL; tests/downloads -> tests/transfers with renamed checkTransferManager/Silent/Panel/PanelDestination/PanelPausedAvatarRate, checkPingTransferHtml, TransferManagerFakeTransfer, TransferPanelFakeTransfer (checkDownloadHttp and checkOrbitDownloadHtml kept); error ids to datatransfer:*/ui:TransferPanel:*/ws:auth:FileTransfer:*; F5BrowserTestApp updated; READMEs (package, tests/transfers, tests/auth, src/Anatel/+ws/+auth with which('ui.TransferPanel') and pingTransferAvatar.html packaging snippet) and todo.md updated; todo item `Refresh stale download documentation and links` ticked with the downloadStatus.html reference kept as a future proposal. No new components, field/schema/Direction/LocalPath/TargetFolder behavior changes (P2 owns them); default history file name `download-history.json` unchanged (P2 owns it).
Static commands, exit codes and significant output: (a) per-file comparison of each moved/renamed file against `git show HEAD:` text after applying only the rename map: identical except the approved T0 README prose; (b) `checkcode -id` message-ID lists for 22 renamed/moved .m files equal their HEAD originals (no new warnings; baseline extracted from git archive zip to a temp folder, later deleted); (c) `which` resolved datatransfer.TransferManager/TransferHistoryStore/sendHTTPRequest/transferFileName/downloadFileWorker/downloadSourceMetadata/downloadContentDispositionFileName/moveToTrash, ui.TransferPanel, ws.auth.FileTransfer/F5Session/DownloadProgressMonitor; (d) editor diagnostics: no errors in src and tests; (e) relative markdown links in the five edited docs: 0 broken; (f) Phase 1 DoD stale-name search over src and tests: only retained download-only names remain (TransferPanel.addDownload and its call sites, checkOrbitDownloadHtml.m comment text); a stale search-index hit for the already-deleted FileDownload.m was disproved by direct filesystem check (file absent); (g) checkOrbitDownloadHtml.m SHA256 DDB1ACAB26D25ED2918FC68BA44F541A5A5C6D25F79B6C99B08565D0D4286968 equals HEAD; orbitDownloadAvatar.html unchanged; harness asset paths derive from tests/transfers to the repo root and the assets exist; old src/General/+download, tests/downloads, FileDownload.m and old-named harness/fake files are absent. Note: the MATLAB static checks used `matlab -batch` for checkcode/which only; no project code, harness, network, authentication or backend ran.
Editor diagnostics (baseline vs new): No errors in src and tests (see static item (d))
Runtime/backend checks: Not run; Phase 10 unauthorized
Review findings (severity, file and line): Transfer Reviewer (GPT-6 Luna (copilot), read-only) first review found 3 Low items: (1) tests/transfers/README.md line 49 wrongly said the orbit harness emits transferAvatarClick (the unchanged orbit asset emits downloadAvatarClick); (2) wording `ui.download*` in src/General/+datatransfer/README.md is a verbatim carry-over of the HEAD sentence; (3) English UI strings `Pause download`/`Downloads` in TransferPanel.m predate P1 (present in HEAD DownloadPanel.m lines 370, 552, 889).
Repairs and repeated focused checks: (1) repaired within the lease; (2) retained as a verbatim HEAD carry-over; (3) not P1 scope, carried to P6 as a D8 translation follow-up (recorded in the P6 row). Focused re-review: no remaining actionable findings.
Unverified assumptions / blockers: Runtime behavior, MATLAB execution of harnesses, backgroundPool/DataQueue, live F5 behavior (all Phase 10); reviewer could not run checkcode/which (coordinator ran them).
Final state and coordinator disposition: reviewed-static; P1 closed. Next: P2, whose explicit file lease must be recorded before dispatch (tracker row currently names only phase ownership: manager, history store, necessary fake/call-site updates).
```

### P2 — direction-neutral contracts (started 2026-10-05)

```text
Task / approved phase: P2 (plan rev 3 Phase 2 + Appendix A contracts where consistent). B1-B8 resolved; P1 reviewed-static. Routes: Coordinator = Transfer Coordinator, Claude Sonnet 5.5 (copilot); Implementer = Transfer Implementer, GPT-6 Luna (copilot); Reviewer = Transfer Reviewer, GPT-6 Luna (copilot) (all smoke-tested 2026-10-05). User authorized continuing to P2 on 2026-10-05 after P1 closed reviewed-static.
Specification revision and approved blocker decisions: Revision 3; B1-B8 resolved
Implementation agent and actual selected model: Transfer Implementer; GPT-6 Luna (copilot) (planned; dispatch pending)
Reviewer agent and actual selected model: Transfer Reviewer; GPT-6 Luna (copilot), read-only (planned; fresh review after each implementation batch)
File lease (explicit paths): Coordinator-defined; includes call sites that carry the renamed fields; not expandable without approval: src/General/+datatransfer/TransferManager.m; src/General/+datatransfer/TransferHistoryStore.m; src/General/+datatransfer/downloadFileWorker.m (field renames only); src/General/+datatransfer/README.md; src/General/+ui/TransferPanel.m; src/Anatel/+ws/+auth/FileTransfer.m (field renames only; hierarchy/IsResumable adapter work stays P5); src/Anatel/+ws/+auth/README.md; tests/transfers/{TransferManagerFakeTransfer.m, TransferPanelFakeTransfer.m, checkTransferManager.m, checkTransferSilent.m, checkTransferPanel.m, checkTransferPanelDestination.m, checkTransferPanelPausedAvatarRate.m, checkDownloadHttp.m, README.md}; tests/auth/F5BrowserTestApp.m; tests/auth/README.md. NOT in lease: checkOrbitDownloadHtml.m, orbitDownloadAvatar.html, pingTransferAvatar.html, transferFileName.m, sendHTTPRequest.m, F5Session.m, the plan, todo.md, and any new class/function/icon.
Existing user changes preserved: Pre-edit baseline: lease files copied to %TEMP%\p2base (outside the repo) at the verified post-P1 state, including user/formatter edits to TransferManager.m, TransferPanel.m and icons/transfer-trash.svg made after P1 review (all three: no diagnostics, line counts 1187/1475/40, no stale names, single addTransfer). Worktree: branch auth; modified F5Session.m, READMEs, F5BrowserTestApp.m, todo.md; untracked .github/agents, docs, +datatransfer, TransferPanel.m, FileTransfer.m, pingTransferAvatar.html, transfer-*.svg, tests/transfers. Preserve all.
Changes / contract impact: Planned scope (no source change evidenced yet): Direction mandatory; LocalPath replaces FinalPath/TargetPath/SourcePath and TargetFolder is no longer stored; SourceURL -> URL; ReceivedBytes/BytesReceived/DownloadedBytes -> TransferredBytes; LogicalFileID per direction (exact URL for downloads, canonical LocalPath for uploads); live duplicate keys (download URL + case-insensitive FileName; upload LocalPath + exact URL) kept separate from the terminal history-row key (Direction + exact URL + canonical LocalPath); history SchemaVersion 1 redefined with the new fields, default file transfer-history.json, old-shape entries treated as corrupt and deleted (no migration); upload request validation including MaxUploadBytes (default 200*1024^2, error uploadTooLarge), field names, sanitized remote file name; IsResumable in task/snapshot with pause/resume no-op when false; fake gains Direction/IsResumable. Out of scope: HTTP layer (P3), upload worker (P4), adapter hierarchy/IsResumable adapter property/prepare (P5), panel upload UI and TransferPanel.MaxUploadBytes (P6), avatar (P7), any harness execution or new test cases (Phase 10).
Static commands, exit codes and significant output: None yet
Editor diagnostics (baseline vs new): Baseline: no diagnostics in TransferManager.m, TransferPanel.m, icons/transfer-trash.svg at post-P1 state; new: pending
Runtime/backend checks: Not run; Phase 10 unauthorized
Review findings (severity, file and line): None yet
Repairs and repeated focused checks: None yet
Unverified assumptions / blockers: Delegation plan: implementation in batches (history store + manager; worker + adapter + panel; fakes/harnesses/app; docs), each verified by the coordinator, then a fresh read-only review. Implementer dispatch pending.
Final state and coordinator disposition: in-progress. Do not mark implemented-unverified or reviewed-static until evidence is complete.
```

### P2 — direction-neutral contracts (completed 2026-10-05)

```text
Task / approved phase: P2 (plan rev 3 Phase 2 + Appendix A contracts where consistent).
Specification revision and approved blocker decisions: Revision 3; B1-B8 resolved
Implementation agent and actual selected model: Transfer Implementer; GPT-6 Luna (copilot). Routes: Coordinator Claude Sonnet 5.5 (copilot); Reviewer Transfer Reviewer GPT-6 Luna (copilot, read-only). Implementer runs sometimes returned an empty report; every claim was re-verified by file reads, diagnostics and static MATLAB checks instead.
Reviewer agent and actual selected model: Transfer Reviewer; GPT-6 Luna (copilot), read-only
File lease (explicit paths): As recorded in the started entry; no expansion.
Existing user changes preserved: User/formatter edits to TransferManager.m, TransferPanel.m and icons/transfer-trash.svg made after P1 were preserved. Nothing staged, committed or branched.
Changes / contract impact: Direction mandatory; LocalPath replaces FinalPath/TargetPath; TargetFolder and SourcePath not stored; SourceURL -> URL; ReceivedBytes/BytesReceived/DownloadedBytes -> TransferredBytes across manager, store, worker, adapter, panel, fakes, harnesses and app. LogicalFileID per direction (exact URL hash with prefix `url-` for downloads; canonical LocalPath hash for uploads). Live duplicate keys (download URL + case-insensitive FileName; upload LocalPath + exact URL) are separate from the terminal history-row key (Direction + exact URL + canonical LocalPath, also used for AttemptedTimestamps and restore dedup; active rows stay per TaskID). History entry schema redefined under SchemaVersion 1 (adds Direction, Protocol, UploadURL, UploadOffset, LocalBytes, LocalModifiedAt, Response; LocalPath canonicalized on load); default panel history file `transfer-history.json`; legacy-shape history (SourceURL/TargetPath/DownloadedBytes) deleted without migration (warning if deletion fails), other malformed JSON still quarantined. Upload request validation: existing regular file, Protocol/Method/FormFieldName regex/FormFields/ContentType/ChunkSize defaults, ResolvedProtocol never `auto`, sanitized remote FileName with LocalPath untouched. Public `MaxUploadBytes` (default 200*1024^2, positive, Inf allowed) with `datatransfer:TransferManager:uploadTooLarge` raised before task creation. IsResumable in task/snapshot with pause/resume no-ops when false. Upload source preserved on cancel/failure/restart/history delete/cleanup; no target pre-check for uploads. Restored interrupted uploads become partial conflicts (resume removed and status shown when LocalBytes/LocalModifiedAt changed; missing source fails via `datatransfer:TransferManager:sourceUnavailable`). Upload Response summary (FileName, CompletedAt, Success, StatusCode, Message, OutcomeUncertain) without bodies/headers/cookies. History restart reuses the saved remote filename. Download source-metadata renames gated by AllowSourceFilename in manager and adapter. Manager method restoreInterruptedDownloads renamed restoreInterruptedTransfers. H1 docstrings added for TransferManager public methods and TransferHistoryStore. TransferPanel skips non-download snapshots/history entries until P6. FileTransfer accepts only Direction 'download' (error ws:auth:FileTransfer:invalidRequest otherwise). Fakes gained Direction/IsResumable (manager fake never touches an upload source). READMEs (package, tests/transfers, tests/auth, src/Anatel/+ws/+auth) updated in Portuguese. No new classes/files/icons, no new test cases, no HTTP/upload worker/adapter hierarchy/panel upload UI.
Static commands, exit codes and significant output: Editor diagnostics clean for src and tests. `checkcode -id` message counts for all 14 changed .m files compared with a pre-P2 copy of the same files (taken after P1 review, held in a temp folder outside the repo and deleted afterwards): no new warnings (TransferManager.m 6->5, TransferPanel.m 1->0; two intermediate new AGROW warnings and one ISCL warning were repaired). `which` resolves datatransfer.TransferManager/TransferHistoryStore/downloadFileWorker, ui.TransferPanel, ws.auth.FileTransfer. checkOrbitDownloadHtml.m SHA256 DDB1ACAB26D25ED2918FC68BA44F541A5A5C6D25F79B6C99B08565D0D4286968 unchanged; orbitDownloadAvatar.html has no diff. Relative links in the four READMEs resolve. Stale-name scans clean except allowed items (DestinationResolver TargetFolder result contract, panel TargetPath option, legacy-shape detector, worker local variables); the search index returned a stale hit for the deleted FileDownload.m, disproved by filesystem check. MATLAB was launched with `matlab -batch` only for checkcode/which; no project code, harness, network, authentication or backend ran.
Editor diagnostics (baseline vs new): Baseline none; new: clean for src and tests
Runtime/backend checks: Not run; Phase 10 unauthorized
Review findings (severity, file and line): Partial manager/store review found 5 issues, all repaired (download filename override ignoring AllowSourceFilename; non-canonical history LocalPath; silent legacy-delete failure; `auto` accepted as ResolvedProtocol; upload restart dereferencing a vanished source). Fresh full review found 0 Critical/High, 2 Medium, 2 Low: (a) Medium: restored interrupted upload rendered with download labels/actions; (b) Medium: history restart lost a custom upload remote name; (c) Low: manager fake could overwrite an upload source; (d) Low: missing H1 docstrings.
Repairs and repeated focused checks: (a) guarded in P2 by skipping non-download rows in TransferPanel (reviewer rejected pure deferral; the guard was re-reviewed PASS) and carried to P6; (b) repaired using the saved Response.FileName (non-terminal entries fall back to the local basename; no history field added); (c) repaired; (d) docstrings added. Focused re-reviews: no remaining actionable findings.
Unverified assumptions / blockers: Runtime behavior, MATLAB execution of harnesses, JSON round-trip of empty Response/LocalBytes, upload source preservation at runtime, legacy-history deletion at runtime, and absence of upload-specific / legacy-shape cases in checkTransferManager (all Phase 10; no new test cases per D9). Carry-forwards: P3 shared remote-name sanitizer (§3.6); P5 adapter IsResumable and StateFcn wiring; P6 direction-aware rows (remove the panel guard) and translating English visible strings; P6 panel MaxUploadBytes; the manager exposes `TusMaxSize`/ResolvedProtocol only through prepare info, wiring is P5.
Final state and coordinator disposition: reviewed-static; P2 closed. Next: P3, whose explicit file lease must be recorded before dispatch.
```

### P3 — HTTP layer (started 2026-10-05)

```text
Task / approved phase: P3, HTTP layer; user authorized P3 on 2026-10-05 after P2 reached reviewed-static. Stop before P4.
Specification revision and approved blocker decisions: Revision 3; B1-B8 resolved; P2 reviewed-static; P3 authorization dated 2026-10-05.
Implementation agent and actual selected model: Transfer Implementer; Gemma  4 e4b - Local (customendpoint), assigned; no implementation yet.
Reviewer agent and actual selected model: Transfer Reviewer; GPT-6 Luna (copilot), assigned for a fresh read-only review after implementation. Current routes: Coordinator = Transfer Coordinator, GPT-6 Luna (copilot); Implementer = Transfer Implementer, Gemma  4 e4b - Local (customendpoint); Reviewer = Transfer Reviewer, GPT-6 Luna (copilot).
File lease (explicit paths): src/General/+datatransfer/sendHTTPRequest.m; new src/General/+datatransfer/uploadCapabilities.m; src/General/+datatransfer/downloadFileWorker.m; src/General/+datatransfer/downloadSourceMetadata.m; src/General/+datatransfer/transferFileName.m; src/General/+datatransfer/TransferManager.m (ONLY replace P2 local upload filename sanitizer call with the new shared sanitizer; no other manager behavior); src/General/+datatransfer/README.md; tests/transfers/README.md; src/Anatel/+ws/+auth/README.md. No other files. NOT in lease: F5Session.m, FileTransfer.m, TransferHistoryStore.m, TransferPanel.m, tests/auth/README.md, checkDownloadHttp.m, tests/transfers harnesses, icons/avatar, plan/todo, any P4 worker/monitor or any other new class/function.
Existing user changes preserved: Pre-edit worktree branch auth; P1/P2 changes and other existing user changes preserved. Nothing staged, committed, or branched.
Changes / contract impact: No implementation yet; no contract changes.
Static commands, exit codes and significant output: No P3 implementation or static checks yet.
Editor diagnostics (baseline vs new): No P3 source changes; pending implementation.
Runtime/backend checks: Deferred; no P3 runtime/backend checks run. Phase 10 prohibited.
Review findings (severity, file and line): None; implementation has not been completed and no review has been performed.
Repairs and repeated focused checks: None; not applicable before implementation.
Unverified assumptions / blockers: Implementation and P3 static checks remain pending; maintain the exact lease and do no P4 work.
Final state and coordinator disposition: in-progress; P3 is authorized and its exact lease and routes are assigned. No implementation yet; stop before P4.
```

### P3 — HTTP layer (completed 2026-10-05)

```text
Task / approved phase: P3, HTTP layer; user authorized P3 after P2 reached reviewed-static. Stop before P4.
Specification revision and approved blocker decisions: Revision 3; B1-B8 resolved; P2 reviewed-static; user authorized P3; stop before P4.
Implementation agent and actual selected model: Transfer Implementer; GPT-6 Luna (copilot). Current routes: Coordinator = Transfer Coordinator, GPT-6 Luna (copilot); Implementer = Transfer Implementer, GPT-6 Luna (copilot); Reviewer = Transfer Reviewer, GPT-6 Luna (copilot), read-only. The prior dispatch using Gemma  4 e4b - Local (customendpoint) failed with client request 8aa28247-df58-4e36-bccb-e1adf5300131 and exact error `Response contained no choices`. After switching the model to GPT-6 Luna, the implementation route succeeded. No substitution; the earlier P3 started record above is preserved.
Reviewer agent and actual selected model: Transfer Reviewer; GPT-6 Luna (copilot), read-only. Fresh final review returned exactly `no remaining actionable findings`.
File lease (explicit paths): src/General/+datatransfer/sendHTTPRequest.m; new src/General/+datatransfer/uploadCapabilities.m; src/General/+datatransfer/downloadFileWorker.m; src/General/+datatransfer/downloadSourceMetadata.m; src/General/+datatransfer/transferFileName.m; src/General/+datatransfer/TransferManager.m (ONLY replace P2 local upload filename sanitizer call with the new shared sanitizer; no other manager behavior); src/General/+datatransfer/README.md; tests/transfers/README.md; src/Anatel/+ws/+auth/README.md. No other files. NOT in lease: F5Session.m, FileTransfer.m, TransferHistoryStore.m, TransferPanel.m, tests/auth/README.md, checkDownloadHttp.m, tests/transfers harnesses, icons/avatar, plan/todo, any P4 worker/monitor or any other new class/function.
Existing user changes preserved: P1/P2 and all unrelated dirty/untracked work preserved. No P4/P5/P6 files touched. Nothing staged, committed, or branched.
Changes / contract impact: sendHTTPRequest now accepts name-value options (Range, Headers, Body, FollowRedirects, ProgressMonitor), supports required methods, and implements safe redirect/no-body behavior, exact-host HTTPS cookie handling, caller-header allowlisting, and RequestMessage body/progress-factory construction using the documented R2024a API. uploadCapabilities adds OPTIONS/HEAD discovery, optional ResponseMessage/sender seam, true Tus/Allow parsing, protocol priority/fallback, size handling, and redirect/auth rules. Download call sites use the options API. transferFileName SanitizeOnly accepts arbitrary filenames and preserves the two-argument URL/fallback behavior. TransferManager has only the two sanitizer substitutions and removal of its local helper. The affected package and auth READMEs were updated; tests/transfers README was unchanged because its existing helper description remained accurate. P3 does not implement uploadFileWorker or UploadProgressMonitor.
Static commands, exit codes and significant output: get_errors reported no errors in all nine leased files. Code Analyzer comparison against %TEMP%\p3base found no new message IDs or counts in existing touched .m files: sendHTTPRequest 0/0; downloadFileWorker 4/4; downloadSourceMetadata 0/0; transferFileName 2/2; TransferManager 5/5; new uploadCapabilities 0 warnings. `which` resolved sendHTTPRequest, uploadCapabilities, downloadFileWorker, downloadSourceMetadata, and transferFileName. README relative-link check found zero broken links.
Editor diagnostics (baseline vs new): No errors in the nine leased files.
Runtime/backend checks: Not run; Phase 10 explicitly unauthorized. No HTTP sends, network/auth activity, or harnesses run.
Review findings (severity, file and line): Initial review found three issues: name-value API usage, external OPTIONS redirects falling into fallback, and broad catches failing open. Focused review then found invalid sender NeedsAuthentication handling and malformed URL/host errors falling back. All were repaired. Fresh final read-only review returned exactly `no remaining actionable findings`; reviewer ran no commands or runtime checks.
Repairs and repeated focused checks: Repaired the initial three findings and the two focused-review findings. Fresh final read-only review passed with no remaining actionable findings.
Unverified assumptions / blockers: Background progress threading, live wire-level header/cookie/redirect/auth behavior, and actual F5/server behavior remain unverified; defer to Phase 10.
Final state and coordinator disposition: reviewed-static; P3 closed. Next phase is P4, not started. Stop before P4.
```

### P4 — upload worker (started 2026-10-05)

```text
Task / approved phase: P4, upload worker; plan rev3; P3 reviewed-static; user authorized P4 on 2026-10-05 after P3. Phase 10 is explicitly prohibited. Final target: stop before P5.
Specification revision and approved blocker decisions: Plan revision 3; B1-B8 resolved; P3 reviewed-static; user authorization after P3 on 2026-10-05. P3 checkpoint commit/tag: f1959bb / transfer-management-refactor-stage-1.
Implementation agent and actual selected model: Transfer Implementer; GPT-6 Luna (copilot), route selector GPT-6 Luna (copilot); assigned, no P4 implementation yet.
Reviewer agent and actual selected model: Transfer Reviewer; GPT-6 Luna (copilot), route selector GPT-6 Luna (copilot); read-only, fresh review pending after implementation. Route selectors: Coordinator = GPT-6 Luna (copilot); Implementer = GPT-6 Luna (copilot); Reviewer = GPT-6 Luna (copilot), read-only.
File lease (explicit paths): new src/General/+datatransfer/uploadFileWorker.m; new src/General/+datatransfer/UploadProgressMonitor.m; new MATLAB ContentConsumer class src/General/+datatransfer/UploadResponseBodyConsumer.m (captures at most 64 KiB during reception and tracks BodyTruncated); src/General/+datatransfer/sendHTTPRequest.m (only add optional name-value ResponseConsumer and pass it as RequestMessage.send's third argument; preserve all P3 request/security behavior); src/General/+datatransfer/README.md (only update module table and current upload-transport status required by §3.5 after P4 adds worker/monitor; no broad rewrite). No other files.
Lease rationale: P0 local MATLAB R2024a help confirms ContentConsumer receives payload in buffers; a P4 worker relying only on the completed ResponseMessage body cannot meet the 64 KiB cap during reception. sendHTTPRequest.m is included only to expose the optional consumer to RequestMessage.send, without changing P3 request/security behavior. Installed MATLAB R2024a source confirms FileProvider.BytesSent is private; multipart request totals include framing/FormFields, so request.Value/request.Max is only an envelope estimate. UploadFileProvider is included only for source-file reads and exact-byte notification to UploadProgressMonitor; it must not alter source paths, request protocol, HTTP headers, or other behavior.
Lease/contract note: UploadResponseBodyConsumer is internal upload response handling only, not a new public endpoint or protocol.
Existing user changes preserved: Pre-edit branch auth; clean worktree. P3 checkpoint commit/tag f1959bb / transfer-management-refactor-stage-1.
Changes / contract impact: No P4 implementation yet; no P4 contract changes. Carry-forward: P4 lease expanded for exact payload progress because multipart totals include framing/FormFields and MATLAB R2024a FileProvider.BytesSent is private; no plan/API change.
Static commands, exit codes and significant output: No P4 implementation or static checks yet.
Editor diagnostics (baseline vs new): No P4 source changes; pending implementation.
Runtime/backend checks: Phase 10 explicitly prohibited; no P4 runtime/backend checks run.
Review findings (severity, file and line): None; P4 implementation has not started and no review has been performed.
Repairs and repeated focused checks: None; not applicable before implementation.
Unverified assumptions / blockers: P4 implementation, static checks, and fresh read-only review remain pending; maintain the exact lease and do not begin P5.
Final state and coordinator disposition: in-progress; P4 is authorized and its exact lease and routes are assigned. No implementation yet. Stop before P5; Phase 10 remains prohibited.
```

### P4 — upload worker (completed 2026-10-05)

```text
Task / approved phase: P4, upload worker; plan revision 3; P3 reviewed-static; user authorized P4 on 2026-10-05; stop before P5; Phase 10 prohibited.
Specification revision and approved blocker decisions: Plan revision 3; B1-B8 resolved; P3 reviewed-static; user authorization to proceed to P4 on 2026-10-05; stop before P5.
Implementation agent and actual selected model: Transfer Implementer; GPT-6 Luna (copilot). Routes: Coordinator = Transfer Coordinator, GPT-6 Luna (copilot); Implementer = Transfer Implementer, GPT-6 Luna (copilot); Reviewer = Transfer Reviewer, GPT-6 Luna (copilot), read-only. All three exact routes were smoke-tested during this session.
Reviewer agent and actual selected model: Transfer Reviewer; GPT-6 Luna (copilot), read-only; fresh review completed after implementation.
File lease (explicit paths): new src/General/+datatransfer/uploadFileWorker.m; new src/General/+datatransfer/UploadProgressMonitor.m; new MATLAB ContentConsumer class src/General/+datatransfer/UploadResponseBodyConsumer.m (captures at most 64 KiB during reception and tracks BodyTruncated); src/General/+datatransfer/sendHTTPRequest.m (only add optional name-value ResponseConsumer and pass it as RequestMessage.send's third argument; preserve all P3 request/security behavior); src/General/+datatransfer/README.md (only update module table and current upload-transport status required by §3.5 after P4 adds worker/monitor; no broad rewrite). No other files.
Lease rationale: P0 local MATLAB R2024a help confirms ContentConsumer receives payload in buffers; a P4 worker relying only on the completed ResponseMessage body cannot meet the 64 KiB cap during reception. sendHTTPRequest.m is included only to expose the optional consumer to RequestMessage.send, without changing P3 request/security behavior. Installed MATLAB R2024a source confirms FileProvider.BytesSent is private; multipart request totals include framing/FormFields, so request.Value/request.Max is only an envelope estimate. UploadFileProvider is included only for source-file reads and exact-byte notification to UploadProgressMonitor; it must not alter source paths, request protocol, HTTP headers, or other behavior.
Existing user changes preserved: Yes; pre-existing working-tree changes were preserved. No tests or files outside the coordinator-authorized P4 scope were touched. Nothing staged, committed, or branched.
Changes / contract impact: Implemented the uploadFileWorker signature. Raw POST/PUT and multipart POST stream through FileProvider/MultipartFormProvider. The sanitized remote FileName is set in the multipart part's Content-Disposition header without mutating FileProvider.Filename or LocalPath; additional scalar fields are sent as text fields. Pre-send checks validate resolved protocol, size, and source size/modification time. Requests are one-shot with no replay after possible submission. Tus creation POST is not replayed without Location; the resource is checked to remain same-host; PATCH reads from the confirmed offset; HEAD runs before resume and after ambiguous PATCH; only server-confirmed offsets count as progress and offsets are validated as monotonic. No Content-Range upload or 308 acknowledgement is used. Added P4 errors/results and status, header, and body completion fields. UploadResponseBodyConsumer drains the response during reception while retaining only capped data and reporting truncation. UploadFileProvider counts actual source-file bytes only; UploadProgressMonitor emits only Request-direction progress. The package README module table and current upload-transport status were updated. P4 did not wire adapter/manager/cancellation callbacks; those are P5. No worker tests were added or run (Phase 10).
Static commands, exit codes and significant output: get_errors reported no errors in the five leased .m files. MATLAB checkcode -id reported zero warnings in uploadFileWorker, UploadProgressMonitor, UploadFileProvider, UploadResponseBodyConsumer, and sendHTTPRequest (the P3 baseline for sendHTTPRequest was also zero). which resolved the three P4 classes/functions. README link check found zero broken links; git diff --check was clean. Source searches found no source writes/copy/delete in the P4 worker/provider and no fileread, Content-Range, or 308 acknowledgement. Installed MATLAB R2024a help/source inspection confirmed FileProvider.FileSize is publicly writable; the FileProvider.Filename setter changes the source and was therefore never used; MultipartFormProvider preserves the part Content-Disposition filename and adds the control name; and ContentConsumer has a streaming reception lifecycle. These were documentation/source inspections, not runtime checks.
Editor diagnostics (baseline vs new): get_errors reported no errors in all five leased .m files; no new diagnostics reported.
Runtime/backend checks: No MATLAB project execution, tests/harnesses, HTTP sends, network, authentication, backend, or Phase 10 activity. Runtime proof remains deferred.
Review findings (severity, file and line): Initial fresh read-only review by Transfer Reviewer found six issues: multipart payload progress estimated from the envelope; PATCH status overwritten by HEAD; response lost on redirect exceptions; uncertain-outcome false positives; stale README transport status; and missing H1 docstrings. A focused review found one README phrasing issue. Final reviewer result: `PASS: no remaining P4 README finding`, with no actionable findings. Actual OS exception cause formats are not runtime-proven.
Repairs and repeated focused checks: UploadFileProvider now reports exact source bytes for raw and multipart bodies while tus progress remains offset-confirmed; PATCH evidence is stored/restored across HEAD; bounded consumer response metadata is harvested in catches; known nested Java connect/DNS/TLS pre-submission failures are not uncertain while generic send failures remain uncertain; README transport status was corrected; H1 docstrings were added. The focused README wording was corrected to `O worker de upload de corpo foi implementado na P4`. Final read-only review returned `PASS: no remaining P4 README finding` and no actionable findings.
Unverified assumptions / blockers: Actual OS exception cause formats are not runtime-proven. Deferred to authorized validation: ProgressMonitor/DataQueue/backgroundPool behavior; multipart wire encoding; ContentConsumer body-cap behavior across transfers/encodings; server responses; tus offset/recovery; source preservation under real errors; and cancellation/DELETE integration (P5).
Final state and coordinator disposition: reviewed-static; P4 closed. P5 is next but NOT started. Stop before P5; Phase 10 remains prohibited.
```

### P5 — Adapters (completed 2026-10-06)

```text
Task / approved phase: P5, Adapters; plan revision 3; P4 reviewed-static; stop before P6; Phase 10 remains unauthorized.
Specification revision and approved blocker decisions: Revision 3; B1-B8 resolved.
Implementation agent and actual selected model: Transfer Implementer; GPT-6 Luna (copilot).
Reviewer agent and actual selected model: Transfer Reviewer; GPT-6 Luna (copilot), fresh independent read-only review; final review found no actionable findings.
File lease (explicit paths): new src/General/+datatransfer/HTTPFileTransfer.m; src/Anatel/+ws/+auth/FileTransfer.m; src/Anatel/+ws/+auth/F5Session.m only if required (unchanged); src/General/+datatransfer/TransferManager.m; src/General/+datatransfer/README.md; src/Anatel/+ws/+auth/README.md. Excluded tests/transfers/README.md, tests/auth/README.md, and all other source, tests, UI, panel, fake, plan, and asset files.
Existing user changes preserved: P5 baseline recorded clean on branch auth, up to date with origin/auth; HEAD 39a21b56e7923c01080e9b33c010351bf2281b5a, parent 073b739d4f7d43d8735da8c8853fdc55dbd3e02a; supplied expected HEAD 073b739 was one commit behind. No reset, rebase, checkout, or history rewrite. At pre-commit verification, changed paths were src/Anatel/+ws/+auth/FileTransfer.m; src/Anatel/+ws/+auth/README.md; src/General/+datatransfer/TransferManager.m; src/General/+datatransfer/README.md; new src/General/+datatransfer/HTTPFileTransfer.m; and this tracker. F5Session.m was unchanged and no out-of-lease changes were detected. At that check nothing was staged or committed; stage-1/2 tags were unchanged and the P5 tag was absent. No push occurred or is authorized.
Changes / contract impact: Lifecycle moved into direction-neutral HTTPFileTransfer. prepare branches between download metadata and the sole uploadCapabilities preflight, returns resolved protocol/TusMaxSize, and handles authentication only before body submission or after HEAD confirms authoritative Tus offset. Tus retries use the copied/published worker offset and never replay one-shot or uncertain body operations. Upload TotalBytes comes from normalized LocalBytes before worker start. IsResumable and non-resumable pause no-op are wired; StateFcn publishes scalar protocol state, and the manager persists Protocol plus Tus URL/offset with callback-generation guards and cleanup. Initial and auth-retry launch failures reset state and cancel partial futures. FileTransfer overrides only acquireContext/reauthenticate; F5Session is unchanged. Package/auth READMEs document schemas, hooks, manager callbacks, payload/error/cancel semantics, history mapping, and safe Tus auth recovery.
Static commands, exit codes and significant output: get_errors reported no errors in HTTPFileTransfer, FileTransfer, TransferManager, and both READMEs. MATLAB checkcode(file,'-id'): HTTPFileTransfer 0; FileTransfer 0; TransferManager 5 AGROW messages in unchanged loops, matching the P2 reviewed-static baseline. which resolved all three classes to repository paths. git diff --check succeeded. Tool output did not expose numerical process exit codes.
Editor diagnostics (baseline vs new): No errors in the five checked implementation/documentation files.
Runtime/backend checks: No tests/harnesses, project runtime, network, authentication, backend, or Phase 10 checks ran; deferred and unauthorized.
Review findings (severity, file and line): Initial/focused review findings covered README inaccuracies, state schemas, Tus auth retry offset propagation, missing upload TotalBytes, and launch-failure cleanup. Final fresh independent read-only review found no actionable findings.
Repairs and repeated focused checks: Corrected README details and state schemas; propagated confirmed Tus offsets; set TotalBytes before worker launch; added initial/auth-retry launch-failure cleanup. Focused diagnostics and repeated read-only reviews passed.
Unverified assumptions / blockers: backgroundPool/DataQueue behavior and live HTTP, Tus, F5, and authentication behavior remain unverified for authorized Phase 10 only.
Final state and coordinator disposition: reviewed-static; P5 closed; stop before P6; Phase 10 remains unauthorized.
```
### P7 - Avatar asset (completed 2026-10-06)

```text
Task / approved phase: P7, Avatar asset; plan revision 3; P6 reviewed-static and closed. Stop before P8; Phase 10 remains unauthorized.
Specification revision and approved blocker decisions: Revision 3; B1-B8 resolved; §5.5 applied without contract changes.
Implementation agent and actual selected model: Transfer Implementer; GPT-6 Luna (copilot).
Reviewer agent and actual selected model: Transfer Reviewer; GPT-6 Luna (copilot), read/search only. Fresh final review found no findings.
File lease (explicit paths): src/General/+ui/html/pingTransferAvatar.html; tests/transfers/checkPingTransferHtml.m; tests/transfers/README.md. Tracker was coordinator-owned. Exclusions remained unchanged: orbit avatar/harness, TransferPanel, other UI assets/tests, F5BrowserTestApp, other READMEs, plan, and todo.
Existing user changes preserved: Initial worktree was clean. After implementation, status showed only the three leased files and this tracker modified; no unrelated or staged changes.
Changes / contract impact: Avatar requires exact download/upload direction; validates every supplied item, including items beyond the 23 visible slots; validation failures emit pingTransferAvatarError. Existing 23 coordinates remain. Upload indicators use a distinct color; the arrow reflects visible directions. The panel's nonzero upload-rate sentinel and ready/click events remain. Harness data includes direction modes and reads only HTMLEventName/HTMLEventData. Affected test README prose is Brazilian Portuguese and no longer says support belongs to P7. No contract changed.
Static commands, exit codes and significant output: Editor get_errors reported no errors in all three leased files, before and after the README repair. git diff --check produced no output. git status showed exactly the three leased files plus tracker. Tool output did not expose numeric exit codes. No MATLAB Code Analyzer, harness, test, or project code ran.
Editor diagnostics (baseline vs new): No errors in the three leased files.
Runtime/backend checks: Deferred to Phase 10; no harnesses/tests, runtime/project checks, network, authentication, or backend activity.
Review findings (severity, file and line): First fresh review found one P3 stale forward-looking README sentence. After repair, fresh independent review found no findings. Reviewer confirmed direction validation beyond the render cap, coordinate preservation, colors/arrows, sentinel compatibility, events, harness dispatch, and README scope/language.
Repairs and repeated focused checks: Replaced the stale P7-forward-looking README sentence with present-tense behavior. Re-ran editor diagnostics on all three leased files (no errors) and obtained a clean fresh read-only review.
Unverified assumptions / blockers: Browser rendering and actual uihtml event delivery remain unverified by design; Phase 10 only.
Final state and coordinator disposition: reviewed-static; eligible for the authorized P7 commit and annotated tag; do not push or start P8.
```
