# HTTP Transfer Scoped Instructions Draft

Status: **inactive draft for review**. This file is intentionally outside
`.github/instructions` and is not an active customization.

Proposed destination after approval:
`.github/instructions/http-transfer.instructions.md`.
Use the following frontmatter and body as the approved file content; omit
this draft introduction when activating it.

```yaml
---
description: "Use when implementing or reviewing the HTTP download/upload transfer migration, TransferManager, TransferPanel, workers, adapters, or transfer history."
applyTo: "src/General/+download/**,src/General/+datatransfer/**,src/General/+ui/DownloadPanel.m,src/General/+ui/TransferPanel.m,src/General/+ui/html/*DownloadAvatar.html,src/General/+ui/html/pingTransferAvatar.html,src/General/icons/download-*.svg,src/General/icons/transfer-*.svg,src/Anatel/+ws/+auth/**,tests/downloads/**,tests/transfers/**,tests/auth/**,docs/plans/http-transfer*.md"
---
```

## Authority And Scope

- Read `docs/plans/http-transfer-upload-plan.md`, including Appendix A,
  and `docs/plans/http-transfer-implementation-tracker.md` before editing.
- Work only on the authorized phase and explicit file lease. Draft artifacts
  do not authorize implementation, agent launches, or activation of agents.
- Approved user decisions outrank draft clarifications. Stop the affected
  task when a contract is ambiguous; report the tracker blocker ID rather
  than silently inventing a protocol or migration policy.
- Preserve user edits. Do not commit, create branches, contact endpoints,
  authenticate, configure a backend, or delegate further unless authorized.

## Naming And Documentation

- Follow the plan's exact naming map: PascalCase classes/app files,
  lowercase class-holding packages, camelCase functions/function-only
  packages. Shared operations use transfer; direction-specific ones retain
  download or upload. No compatibility wrappers.
- Code identifiers, comments, docstrings and agent artifacts use English.
  READMEs and user-facing labels/tooltips/errors use Brazilian Portuguese.
  Error identifiers stay English in the approved namespace.
- Public classes/methods/functions get a concise uppercase-name H1 help
  line before the arguments block. Document input/output and side effects;
  preserve local method separators. Comments explain only non-obvious
  constraints and stay short.
- Update affected documentation/packaging in the same phase, within the
  assigned file lease. Do not add unrelated documentation or abstractions.

## Contracts And Boundaries

- `HTTPFileTransfer.prepare` is the sole upload preflight owner and calls
  `uploadCapabilities` before body submission. Workers require a resolved
  protocol and never issue a second OPTIONS request.
- Use `Direction`, `LocalPath`, `URL`. Downloads target LocalPath; uploads
  read it. Derive the download target folder instead of storing an alias.
- Default logical ID hashes URL alone for downloads, canonical LocalPath
  alone for uploads. Include direction in comparisons. Logical identity,
  live-task deduplication and history-row grouping are distinct concepts.
  Group terminal history by Direction + exact URL + canonical LocalPath;
  keep active tasks separate by TaskID and aggregate attempt timestamps by
  that history-row key.
- Keep SchemaVersion 1; do not migrate or alias the legacy history fields.
  The new default is `transfer-history.json`; old-format history is corrupt
  and must be deleted without restoring old partials.
- Manager owns lifecycle/history, workers own transfer mechanics, adapters
  own async execution/auth hooks, and UI owns presentation. No UI calls in
  datatransfer; no F5 session inspection in generic code or the panel.
- Preserve silent-task notifications, attempt timestamps, download conflict
  behavior, publication and partial-file handling. Upload cancellation and
  history deletion never delete the caller's LocalPath.
- Default MaxUploadBytes is 200 * 1024^2 and configurable. webApp requires
  an explicit LocalPath; no fixed upload root and no desktop dialogs there.
- Hide pause/play for non-resumable uploads; retain restart and cancel.
  Do not change the optional orbit avatar or its harness content.

## HTTP Safety

- Cookies remain exact-host HTTPS only and transient. Never log/persist
  secrets or pass session handles to workers.
- Do not automatically redirect/replay body-bearing requests after possible
  submission, including after an auth response. Set `OutcomeUncertain` and
  require in-panel confirmation before manual restart. Reauthenticate/retry
  preflight before the body; resume tus only after `HEAD` confirms the offset.
- OPTIONS is feature discovery, not proof that a body operation is authorized.
  Content-Range uploads are unsupported. Do not send an empty PUT probe,
  infer partial-upload support from Accept-Ranges, or treat 308 as an upload
  acknowledgement. Tus 1.0.0 is the only resumable upload protocol.
- Stream files, bound response reception, sanitize headers/remote filenames,
  and persist only the approved response summary. Confirm server offsets
  before resumable retry; never infer successful completion from sent bytes.

## Verification And Reporting

- Phases 1-9 use static checks. P0 is offline-only; defer executable runtime,
  network, and F5 checks to Phase 10. No Phase 0 network spikes.
- `datatransfer.UploadProgressMonitor` is a separate same-named class file.
  Static help does not prove `backgroundPool`/DataQueue execution; verify that
  only in Phase 10.
- Compare MATLAB analyzer/editor diagnostics to the baseline. Report tooling
  unavailable rather than claiming a check passed. `which` alone is not
  proof a class instantiates or a worker runs.
- After edits, perform the cheapest permitted focused check; repair local
  defects and repeat it. Record commands, evidence, skipped checks and risks
  in the tracker. Use an independent read-only reviewer before closing a task.