# Review TODO

The auth worker forwarding shim has been removed because the package was not
released or used and no in-repository code called it. The remaining items are
follow-up decisions or implementations; README updates remain deferred.

- [ ] **Implement duplicate-task promotion, retry timestamp rules, and panel focus.**
  **Function and current use:**
  [`DownloadPanel.m`](src/General/+ui/DownloadPanel.m) registers
  `onManagerTaskReordered` as the `DownloadManager.TaskReorderedFcn`, but the
  handler returns without updating UI state. The manager emits this callback
  when a duplicate request is added; it returns the existing task ID instead of
  starting a second transfer. The current key is exact URL plus case-insensitive
  `FileName`, with an additional requirement that `DisplayMode` also match; it
  does not compare `TargetFolder` / `FinalPath`. Silent-task callbacks are
  suppressed unless `IncludeSilentTasks` is enabled. `F5BrowserTestApp` can reach
  this path when the same URL is submitted again. No other panel method promotes
  the existing row or focuses the panel: `sortDownloadOrder` sorts by lifecycle
  group while preserving order inside each group (paused/conflict rows precede
  active rows), and the callback handler is empty. A plain array move may
  therefore be undone by the next sort unless promotion is represented in the
  sort priority. Also, when `AllowSourceFilename` is true,
  `FileDownload.prepare` can replace `FileName` using `Content-Disposition`
  after the manager's duplicate lookup. A later request may still carry the
  panel's cached URL-fallback name, so a duplicate with the same eventual target
  filename can be missed. `show()` does raise the panel and bring it to the top,
  but the duplicate callback does not call it.
  **Expected function:** Keep deduplication based on source URL and target
  filename, no other feature, promote the existing task to the top of the visible list when it is recalled as a duplicate, and focus or raise the panel so the user can see which row was matched. A duplicate
  submission is not itself a retry and must not add an `AttemptedTimestamps`
  value; timestamp changes should remain tied to actual retry/start transitions. Resume is not counted as a retry.
  **Proposed change:** Implement `onManagerTaskReordered` to locate the existing
  row from the snapshot, update the display order so it remains at the absolute
  top after lifecycle sorting and later snapshots, refresh the panel, and call
  the panel's focus/show behavior. Align `findDuplicate` with the specified
  identity key. Display mode should not remain part of the key. Target filename is the selected filename, not the full target path. Deduplication is essentially based on the URL resolution. The target filename is a consequence of allowing the user to define alternative target names in desktop mode. Thus relying on `URL` and `FileName` for deduplication is appropriate. Preserve the current no-new-attempt-
  timestamp behavior for duplicate submissions.

- [ ] **Review duplicate HTML event compatibility handling.**
  **Function and current use:** The profile and download HTML assets send a
  named event (for example, `profileAvatarClick` or `downloadAvatarReady`) and
  a payload that repeats the event kind as `type: click` or `type: ready`.
  MATLAB handlers accept either the named event or payload type. The helper
  `eventProperty` also accepts alternate MATLAB event-object property names
  (`HTMLEventName` / `EventName` and `HTMLEventData` / `Data`). Similar parsing
  is repeated in [`F5BrowserTestApp.m`](tests/auth/F5BrowserTestApp.m),
  [`DownloadPanel.m`](src/General/+ui/DownloadPanel.m), and the isolated HTML
  harnesses.
  **MATLAB documentation findings (R2024a and R2025a):** MathWorks documents
  `HTMLEventReceivedFcn` as available since R2023a. Its callback receives an
  `HTMLEventReceivedData` object with `HTMLEventName`, `HTMLEventData`, `Source`,
  and `EventName`; `EventName` is the generic string `HTMLEventReceived`, not the
  JavaScript event name. `Data` is not listed as a property of this event object.
  The documented event name/data properties are consistent in both releases.
  See the [R2024a `uihtml` documentation](https://www.mathworks.com/help/releases/R2024a/matlab/ref/uihtml.html)
  and [R2025a `uihtml` documentation](https://www.mathworks.com/help/releases/R2025a/matlab/ref/uihtml.html).
  **Possible intended function:** The property fallbacks may have been added to
  tolerate an undocumented event shape, but they are not supported by the
  documented contract for R2024a+. The payload `type` fallback is separate: it
  duplicates the event kind that the HTML sends as `HTMLEventName` and could be
  an intentional app-level protocol fallback.
  **Proposed review/change:** For the stated R2024a+ support range, prefer the
  documented `HTMLEventName` and `HTMLEventData` properties. Treat fallback to
  `EventName` or `Data` as unnecessary unless runtime testing on an officially
  supported environment proves otherwise. Decide separately whether to retain
  payload-type dispatch; if removed, update the HTML assets and harnesses to use
  only named events and test ready/click delivery in R2024a and later.
  **Possible effects:** Removing undocumented property fallbacks simplifies
  dispatch and avoids mistaking generic `EventName` (`HTMLEventReceived`) for a
  custom event. Removing payload fallback can break any internally maintained
  asset that sends a payload type without the expected event name, so keep the
  event contract changes coordinated.

- [ ] **Refresh stale download documentation and links.**
  **Function and current use:** These READMEs provide setup, test-running,
  ownership, and packaging guidance, but several details no longer match the
  checked-in tree. [`src/Anatel/+ws/+auth/README.md`](src/Anatel/+ws/+auth/README.md)
  links `checkDownloadHtml.m` under `tests/auth`, although the file is in
  `tests/downloads`; it also describes the deleted auth worker shim and old
  `downloadAvatar.html` name. [`tests/downloads/README.md`](tests/downloads/README.md)
  titles the folder `tests/ui`, tells users to add `tests/ui` to the MATLAB path,
  and still names `downloadAvatar.html`. The download package README's
  architecture listing omits the current
  [`DownloadHistoryStore.m`](src/General/+download/DownloadHistoryStore.m) and
  [`moveToTrash.m`](src/General/+download/moveToTrash.m) modules, describes the
  deleted worker shim as a compatibility wrapper, refers to the old avatar path,
  and mentions `downloadStatus.html`, which is not present in the repository.
  **Possible intended function:** The folder names, links, and asset notes likely
  describe an earlier test layout or planned download-status feature; the module
  lists were intended to document the package structure and compiler inputs.
  **Proposed review/change:** No README files were changed in this task. Later,
  correct paths and commands to the present `tests/downloads` location, point
  the retained orbit harness/docs at `orbitDownloadAvatar.html`, remove the
  deleted worker shim from package descriptions, update architecture/module
  lists to match actual files, and either remove the `downloadStatus.html`
  packaging reference or mark it as a future proposal rather than a current
  asset. Verify local links and MATLAB commands after editing.
  **Possible effects:** This is documentation-only and should not change runtime
  behavior. Correcting it prevents test setup failures, broken navigation, and
  attempts to package a nonexistent file; removing a future-feature reference
  could erase roadmap context unless it is recorded elsewhere.

- [ ] **Evaluate `F5Session.readBytes` against the reusable download pipeline.**
  **Function and current use:** `F5Session.readBytes` calls the private
  `fetch`/`sendRequest` path with `ConvertResponse = false`, returning the full
  response body as `uint8`. When a progress callback is provided,
  `sendRequest` attaches `ws.auth.DownloadProgressMonitor` to MATLAB's HTTP
  request. No in-repository caller of `readBytes` was found; it remains a
  documented public method for small binary payloads and diagnostics.
  Separately, `ws.auth.FileDownload` obtains a host-scoped request context from
  `F5Session`, performs metadata/authentication handling, and invokes the
  provider-neutral `download.downloadFileWorker` in `backgroundPool`. That path
  supports range/chunk transfer, retry, partial-file resume, staging, and final
  publication; `F5BrowserTestApp` reaches it through `ui.DownloadPanel`.
  **Possible intended function:** `readBytes` is an in-memory request API, while
  `FileDownload` is the large-file-to-disk API. `DownloadProgressMonitor` is
  therefore not a duplicate of worker progress; it reports progress for a
  synchronous `matlab.net.http.RequestMessage.send` operation.
  **Proposed review/change:** Keep `readBytes` for bounded responses where the
  caller needs bytes and an HTTP response object. Directly replacing it with
  `downloadFileWorker` would change synchronous/in-memory semantics to
  asynchronous/file-path semantics. For large authenticated files, direct
  callers toward `FileDownload` (or add a clearly named `F5Session` convenience
  facade that delegates to it, if a session-level API is required). Consider a
  documented size/use boundary and tests for authentication expiry, progress,
  cancellation, and returned-vs-published data before any API change.
  **Possible effects:** Using the worker for large files reduces peak MATLAB
  memory use and gains retry/resume/staging behavior, but requires a target path,
  background execution, and the worker's task lifecycle. Changing `readBytes`
  itself would break callers expecting immediate `uint8` output or its response
  metadata. Retaining the monitor preserves that API, although its current
  callback path appears unused inside this repository.

## Checked, Not Flagged

- `DownloadProgressMonitor` remains wired to the public `F5Session.readBytes`
  progress callback. It is distinct from the worker's `DataQueue` path, even
  though no in-repository caller of `readBytes` was found.