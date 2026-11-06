# F5 Browser Bridge Toolbar

## Goal And Decisions

- Target MATLAB R2024a. Match appAnalise's dark toolbar, 34px icon-only native buttons, 5px separators, and flexible URL field.
- Use exactly one MATLAB `uihtml`: the shared `matlabJSBridge`. No separate avatar or response-view `uihtml` controls.
- Use bridge-injected SVG for profile/transfer indicators and a bridge-created sandboxed iframe for response documents. Preserve HTML/CSS and relative-resource behavior without exposing the parent app to response scripts/styles.
- Profile states: disconnected, connected with initial, connected with PNG photo. Retain connect/profile popup/sign-out behavior.
- Transfer states: idle, upload, download, both directions, and paused/pending/conflict attention. Attention overlays active animation. Silent transfers contribute to toolbar status.
- Migrate existing GET -> 405 -> PUT -> POST behavior into `TransferPanel`; only a confirmed PUT 405 with certain non-submission permits the POST attempt. Link both attempts in history. Never replay uncertain uploads.
- Shared API changes are authorized; backwards compatibility is not required. Preserve legacy avatar assets and tests; add new avatar assets rather than repurposing old ones.

## Architecture Evidence

- `appAnalise/src/winAppAnalise_exported.m` creates the dark nav bar and state buttons; it does not explicitly set the rounded button outlines.
- `src/General/+appEngine/matlabJSBridge/js/matlabJSBridge.js` has `initializeComponents`, `tabNavigator` inline-SVG support, renderer notification, and base CSS. Its `tab-navigator-button` rule only sets cursor and hover border color.
- `src/General/+ui/TransferPanel.m` currently owns an `AvatarHTML`, waits for its readiness to open restored transfers, positions its popup relative to that HTML control, and publishes per-task rate/progress state.
- `src/General/+ui/ProfilePanel.m` accepts a generic `Anchor`; it can anchor to a native button.
- `src/General/+ui/TextView.m` renders inside the parent app DOM and has no isolated document or per-view base URL. Do not put untrusted response HTML or `<base>` into the parent document.
- `src/General/+ui/TransferPanel.m:addUpload` supports method/protocol, but not `ContentType`. The manager supports raw PUT/POST and treats response certainty explicitly.
- `TransferManager.failTask` invokes `ErrorFcn` before removing a failed task, while duplicate detection ignores method. Defer POST enqueue until the failed PUT callback unwinds.
- `HTTPFileTransfer` currently drops worker response details at the failure callback boundary. Only forward capped transient response headers/body/truncation; never persist bodies or credentials.
- Preserve the user's current uncommitted changes in `tests/auth/F5BrowserTestApp.m`: they removed the placeholder upload UI and introduced the GET/405 -> PUT/POST flow. Refactor that workflow, do not revert it.

## Implementation Plan

### 1. Bridge Contract And Runtime Probe

1. Initialize one shared bridge locally; do not adopt full `appEngine.boot/activate` lifecycle.
2. Probe R2024a desktop for inline SVG CSS animation, PNG clipping/initial rendering, iframe sandbox behavior, DOM selectors, and bridge renderer/reload behavior. Try SMIL if CSS animation fails. If both fail, stop and ask before relaxing the no-fallback/no-extra-HTML constraints.
3. Add idempotent bridge events for initialize/update/dispose of profile SVG, aggregate transfer SVG, and response iframe. Keep latest UI state across renderer reloads; do not rely on `renderer` alone as proof every target was initialized.
4. Use distinct bridge APIs/styles from the tab navigator's selected-icon recoloring. Namespace IDs/classes and avoid duplicate listeners.

### 2. Toolbar, Profile, And Response Surface

5. Rebuild `F5BrowserTestApp.createComponents` with a dark toolbar containing execution/debug/silent state buttons, separators, flexible URL dropdown, transfer button, and profile button. Keep stable 34px button geometry, 24px artwork, tooltips, and native button borders.
6. Add new parameterized SVG assets at `src/General/+ui/html/profileStatusAvatar.svg` and `transferStatusAvatar.svg`. Update state through bridge data, not many static variants. Escape initials with text nodes and validate PNG input.
7. Anchor `ProfilePanel` to a native profile button. Remove profile-avatar HTML readiness/state plumbing while retaining authentication events, initials/photo fallback, and sign-out/session reset.
8. Replace `HTMLView` with a native host whose response iframe is created by the bridge. Keep text/JSON/raw responses and sanitized HTML within the isolated iframe. Disallow scripts, forms, top navigation, popups, and same-origin privilege. Resolve relative resources against the captured request URL, never mutate the parent document base/styles. Prevent stale responses from overwriting later navigation.

### 3. Transfer Panel Presentation

9. Replace the panel-owned `AvatarHTML` with a caller-owned native anchor and shared bridge. Preserve queue rows/history, controls, conflicts, destination/source selection, outside-click handling, popup geometry, and cleanup. Panel deletion must not delete caller-owned controls.
10. Replace avatar-readiness gating with anchor/bridge readiness while retaining a show request for restored history/conflicts until layout is valid.
11. Publish aggregate state from all nonterminal tasks, including silent tasks: active upload, active download, and attention. Pending/queued/preparing/paused/conflicts count as attention but do not count as active. Completed/failed/cancelled history alone is idle. Attention badge overlays active orbit; when no active task, show attention-only.
12. Do not overwrite manager `SnapshotFcn`; only notify on aggregate state changes. Use CSS animation, not rate-driven JavaScript frame loops. Stop/pause motion when inactive, hidden, or disposed; retain accessible status text/tooltips.
13. Preserve `pingTransferAvatar.html`, `orbitDownloadAvatar.html`, and legacy tests. Add new production-state checks separately; if existing tests depend on removed panel `AvatarHTML`, isolate a legacy fixture rather than weakening their assertions.

### 4. Queued Upload Migration

14. Add `ContentType` to `TransferPanel.addUpload` and request normalization. Queue raw octet-stream PUT using the existing GET/405 detection and captured URL/source. Keep picker cancellation behavior and source validation.
15. Forward capped transient `ResponseHeaders`, `ResponseBody`, and `ResponseTruncated` from worker errors to the app callback; preserve HTTP status and `OutcomeUncertain`. Do not persist payloads or credentials.
16. Track operation identity, URL, source path, GET response, attempt evidence, navigation generation, and deferred retry state. Register operation context before `addUpload`, since preparation failures may callback synchronously.
17. On confirmed PUT HTTP405 and `OutcomeUncertain=false` only, enqueue exactly one POST after the failed task has unwound. Keep both attempts as linked history entries. Never fallback/retry for cancellation, authentication/redirect/transport/5xx or uncertain outcomes. Cancel deferred work on app close/sign-out.
18. Make completion/error handling direction-aware. Suppress the expected PUT405 alert while fallback is scheduled. Preserve GET/PUT/POST response summaries and truncation status; do not let old operations replace a newer response.

### 5. Tests, Docs, And Validation

19. Update auth/transfer harnesses for the bridge and caller-owned native anchors. Preserve legacy avatar assets/tests; add deterministic tests for every aggregate status and attention combination.
20. Test profile disconnected/initial/PNG/fallback, popup anchor/outside click, bridge reload, and cleanup. Test idle/upload/download/both with and without attention, silent transfers, queued/conflict/paused states, and terminal cleanup.
21. Test upload cancellation, PUT success, PUT405->POST success/failure, preparation callback ordering, deduplication, concurrent operations, and no fallback for all non-405 or uncertain failures. Verify Content-Type and capped response evidence.
22. Test response text/JSON/raw/HTML/CSS/relative URLs and ensure scripts/forms/top navigation, parent base/style changes, and stale response replacement are blocked.
23. Update `tests/auth/README.md` and `tests/transfers/README.md` for the single bridge, response sandbox, upload fallback, R2024a support, and retained legacy harnesses.
24. Run `checkTransferManager`, `checkTransferSilent`, `checkTransferPanelDestination`, `checkUploadPreflight`, `checkUploadHttp`, `checkTransferPanel`, paused-avatar regression, `checkPingTransferHtml`, and `checkOrbitDownloadHtml` where MATLAB/runtime/network prerequisites permit. Run `checkcode` and JavaScript syntax checks. Manually verify animation, sandbox and deployment behavior on R2024a desktop; Web App deployment separately when available.

## Main Files

- Modify: `tests/auth/F5BrowserTestApp.m`
- Modify: `src/General/+ui/TransferPanel.m`
- Modify: `src/General/+appEngine/matlabJSBridge/js/matlabJSBridge.js`
- Modify: `src/General/+datatransfer/HTTPFileTransfer.m`
- Modify focused transfer/auth tests and their READMEs.
- Add: `src/General/+ui/html/profileStatusAvatar.svg`
- Add: `src/General/+ui/html/transferStatusAvatar.svg`
- Do not modify appAnalise or `.mlapp` files.

## Risks And Scope

- MATLAB R2024a DOM and CSS/SMIL behavior is unverified; the probe is an early gate.
- Sandboxed iframe response rendering must preserve relative assets while preventing privilege escalation; no remote script execution.
- Keep uncertainty safety: no automatic replay if a request may already have been submitted.
- Preserve user-local F5 edits and all legacy avatar resources/tests. No unrelated auth/protocol redesign, no full appEngine lifecycle adoption, and no proliferation of static icon files.
