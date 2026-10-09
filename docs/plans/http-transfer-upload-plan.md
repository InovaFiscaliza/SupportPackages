# Plan: HTTP content transfer management (download + upload)

Status: **revision 3 approved; Phase 10 LAN/Tus validation authorized and in progress; protected F5 validation remains deferred**.
Audience: coding agents and reviewers.

This plan turns the download subsystem (`download.DownloadManager`,
`ui.DownloadPanel`, `ws.auth.FileDownload`) into a direction-neutral HTTP
transfer subsystem that also uploads files. Uploads reuse the same F5 BIG-IP
APM session (`ws.auth.F5Session`) for protected hosts, and also work with
public endpoints such as an nginx `POST`/`PUT` location, a tus server, or
similar services that need no authentication.

Follow the phases in order. Each phase ends with a verifiable *Definition of
done* (DoD). Do not start a phase until the previous one is merged and its DoD
holds. Runtime tests and backend validation are deferred to Phase 10 (D9).

---

## 1. Decisions already taken

| # | Topic | Decision |
|---|---|---|
| D1 | Compatibility | No compatibility wrappers or deprecated aliases. Nothing outside this repository uses these components. Rename everything in one step per phase. |
| D2 | Naming | Classes and app files: `PascalCase`. Namespace folders that hold classes ("modules"): all-lowercase. Namespace folders that hold only functions: `camelCase` (existing examples: `+getSimilarString`, `+appEngine`). Function files: `camelCase`. |
| D3 | Package | `src/General/+download` becomes `src/General/+datatransfer` (lowercase, per D2: it contains classes). `download.DownloadManager` becomes `datatransfer.TransferManager`. `ui.DownloadPanel` becomes `ui.TransferPanel`. |
| D4 | Upload wire formats | Three formats: (a) `multipart/form-data` `POST` in one request; (b) raw body `PUT` or `POST` in one request; (c) chunked resumable upload using **tus 1.0.0**. In `auto` mode, HTTP `OPTIONS` discovers tus capability and allowed one-shot methods; it does not prove that sending a body is authorized. |
| D5 | Pause for uploads | Pause/resume exists only for resumable tus uploads. For non-resumable uploads the play/pause `uiimage` is **hidden**. Only the **Reiniciar** and **Cancelar** actions are shown. |
| D6 | Upload source | Desktop modes (`desktopStandaloneApp`, `MATLABEnvironment`): `uigetfile` when the caller gives no source path. `webApp`: the caller must supply a server-side source path. The panel never opens a dialog in `webApp`. |
| D7 | Upload response | A response summary is persisted in the history JSON: file name, completion timestamp, success/error indication (status code and message). The full response body is not persisted. It is returned, size-capped, in the completion info only. |
| D8 | Language | Use English for agent-related files and code identifiers, comments, and docstrings. Use Brazilian Portuguese for all README explanatory prose and user-visible UI labels, tooltips, status text, confirmations, and errors. |
| D9 | Testing | The backend for upload is not configured yet. Phases 1–9 end with static checks only. New harnesses, harness execution, live endpoints, and F5 validation all happen in Phase 10. Do not over-engineer tests in the early phases. |

## 2. Resolved questions

| # | Resolution | Applied in |
|---|---|---|
| Q1 | Content-Range uploads are unsupported. Tus 1.0.0 is the only resumable upload protocol. Do not infer partial-upload support from `Accept-Ranges`, send an empty `PUT` probe, or treat `308` as an upload acknowledgement. | §3.6, §5.1, §6.1, §6.4 |
| Q2 | `MaxUploadBytes` defaults to **200 MiB** (`200 * 1024^2` = 209 715 200 bytes). It is a public, runtime-settable property, so an application can later fetch a server-defined limit with a `GET` and assign it. | §5.6 |
| Q3 | No root-folder confinement. In `webApp`, `addUpload` must be called with an explicit `LocalPath`. The panel never opens a dialog there. | §3.6, Phase 2, Phase 6 |
| Q4 | `orbitDownloadAvatar.html` and `checkOrbitDownloadHtml.m` are not changed. The harness only moves with its folder. | §3.1.1, Phase 1 |
| Q5 | Components reused by both directions are renamed with "transfer". Download-only components keep "download". Upload-only components are new and use "upload". The complete list is in §3.1.1. | §3.1.1 |
| Q6 | `SchemaVersion` stays `1`. Nothing has been released, so the field set is redefined in place and no migration code is written. | §5.3 |
| Q7 | Local and remote locations use one pair of fields for both directions: `LocalPath` (the file on this machine) and `URL` (the remote address). `Direction` tells which one is the source and which is the target. `LogicalFileID` is computed per direction: a hash of `URL` for downloads, a hash of `LocalPath` for uploads. | §3.1.1, §5.1–§5.4, §6.5 |

---

## 3. Coding standards (mandatory for every phase)

### 3.1 Naming

- Classes: `PascalCase` (`TransferManager`, `TransferHistoryStore`,
  `HTTPFileTransfer`, `TransferPanel`, `FileTransfer`).
- Class-holding namespace folders: lowercase (`+datatransfer`, `+ui`, `+auth`).
- Function-only namespace folders and function files: `camelCase`
  (`uploadFileWorker.m`, `sendHTTPRequest.m`, `uploadCapabilities.m`).
- Properties and public methods: keep the current repository style.
  Properties are `PascalCase`. Methods are `camelCase`. The existing
  `executionMode` property stays lower-camel.
- Local variables: descriptive `camelCase`. Avoid single letters except loop
  counters in very short loops.
- HTML assets: `camelCase.html`. Icons: `kebab-case.svg`.
- Test harness functions: `check<Subject>.m`. Test doubles: `PascalCase`
  classes (`TransferPanelFakeTransfer`).
- Word choice (Q5): use `transfer` for anything used by both directions,
  `download` for download-only components, and `upload` for upload-only
  components. Do not rename download-only code just for uniformity.

### 3.1.1 Naming map (authoritative)

**Shared by both directions: renamed with "transfer"**

| Current | New |
|---|---|
| `src/General/+download/` | `src/General/+datatransfer/` |
| `download.DownloadManager` | `datatransfer.TransferManager` |
| `download.DownloadHistoryStore` | `datatransfer.TransferHistoryStore` |
| `download.downloadHTTPResponse` | `datatransfer.sendHTTPRequest` (generic verb; supports every method) |
| `download.downloadFileName` | `datatransfer.transferFileName` (also sanitizes upload remote names) |
| `download.moveToTrash` | `datatransfer.moveToTrash` (name unchanged) |
| — | `datatransfer.HTTPFileTransfer` (new, no-auth adapter) |
| — | `datatransfer.UploadProgressMonitor` (new upload request progress monitor) |
| `ws.auth.FileDownload` | `ws.auth.FileTransfer` |
| `F5Session.getDownloadContext` | `F5Session.getRequestContext` |
| `F5Session.authenticateForDownload` | `F5Session.authenticateForRequest` |
| `F5Session.validateDownloadURL` | `F5Session.validateRequestURL` |
| `ui.DownloadPanel` | `ui.TransferPanel` |
| `+ui/html/pingDownloadAvatar.html` | `+ui/html/pingTransferAvatar.html` |
| `icons/download-{start,pause,continue,restart,trash}.svg` | `icons/transfer-{start,pause,continue,restart,trash}.svg` |
| — | `icons/transfer-download.svg`, `icons/transfer-upload.svg` (direction badges) |
| `DownloaderFactory` (option/property) | `TransferFactory` |
| `DownloadManager.addDownload(request)` | `TransferManager.addTransfer(request)` |
| Snapshot `ReceivedBytes`; adapter `BytesReceived`; history `DownloadedBytes` | `TransferredBytes` everywhere |
| History `SourceURL` | `URL` |
| Request/snapshot/adapter `FinalPath`; history `TargetPath`; proposed upload `SourcePath` | `LocalPath` everywhere (Q7) |
| Request `TargetFolder` | Not stored; derive with `fileparts(LocalPath)` |
| Proposed upload `SourceBytes`, `SourceModifiedAt` | `LocalBytes`, `LocalModifiedAt` |
| `TransferPanel.addUpload` option `SourcePath` | `LocalPath` |
| Default history file `download-history.json` | `transfer-history.json` |
| Panel private members `DownloadDialog`, `DownloadHeader`, `DownloadTitleLabel`, `DownloadContent`, `DownloadStack`, `DownloadTasks`, `DownloadOrder`, and methods `ensureDownloadContainer`, `refreshDownloadContainer`, `positionDownloadContainer`, `updateDownloadAvatar`, … | Same names with `Transfer` replacing `Download` |
| Avatar events `downloadAvatarReady`, `downloadAvatarClick` | `transferAvatarReady`, `transferAvatarClick` |
| `tests/downloads/` | `tests/transfers/` |
| `checkDownloadManager`, `checkDownloadSilent`, `checkDownloadPanel`, `checkDownloadPanelDestination`, `checkDownloadPanelPausedAvatarRate`, `checkPingDownloadHtml` | `checkTransferManager`, `checkTransferSilent`, `checkTransferPanel`, `checkTransferPanelDestination`, `checkTransferPanelPausedAvatarRate`, `checkPingTransferHtml` |
| `DownloadManagerFakeDownloader`, `DownloadPanelFakeDownloader` | `TransferManagerFakeTransfer`, `TransferPanelFakeTransfer` |

**Download-only: keep "download"**

`datatransfer.downloadFileWorker`, `datatransfer.downloadSourceMetadata`,
`datatransfer.downloadContentDispositionFileName`,
`ws.auth.DownloadProgressMonitor` (used only by `F5Session.readBytes`),
`orbitDownloadAvatar.html`, `checkOrbitDownloadHtml` (content unchanged, Q4),
`checkDownloadHttp`, `TransferPanel.addDownload`,
`TransferPanel.DestinationResolver`, the panel cache `DownloadFileNames`, and
the staging fields `TemporaryPath`/`PartialPath`, `ChunkPath`, `BackupPath`.

**Upload-only: new, named "upload"**

`datatransfer.uploadFileWorker`, `datatransfer.uploadCapabilities`,
`datatransfer.UploadProgressMonitor`,
`TransferPanel.addUpload`, `TransferPanel.SourceResolver`,
`TransferManager.MaxUploadBytes` / `TransferPanel.MaxUploadBytes`, the request
fields `UploadURL` and `UploadOffset`, and the harnesses `checkUploadHttp` and
`checkUploadPreflight` (Phase 10).

### 3.2 Error identifiers

Use the form `<namespace>:<Component>:<reason>`, with `reason` in lowerCamel:

- `datatransfer:TransferManager:invalidRequest`
- `datatransfer:uploadFileWorker:httpError`
- `datatransfer:uploadFileWorker:httpError`
- `datatransfer:uploadFileWorker:unpreparedRequest`
- `ui:TransferPanel:missingUploadSource`
- `datatransfer:TransferManager:uploadTooLarge`
- `ws:auth:FileTransfer:authenticationRequired`

Never reuse `download:*` or `ui:DownloadPanel:*` after Phase 1.

### 3.3 Docstrings

Every class, public method, and file-level function gets an H1 line. Follow
the existing style in `DownloadPanel.m` and `ProfilePanel.m`:

```matlab
classdef TransferManager < handle

    % TRANSFERMANAGER Provider-neutral HTTP transfer orchestration.
    %
    % One or two short paragraphs: responsibility, what it does NOT own.
    %
    %   manager = datatransfer.TransferManager( ...
    %       'TransferFactory', @factory, 'HistoryFile', historyFile);
    %   taskID = manager.addTransfer(request);
```

```matlab
function taskID = addUpload(obj, url, options)
    % ADDUPLOAD Queue an upload of a local file to URL.
    %
    % LOCALPATH is optional in desktop modes (uigetfile is shown) and
    % required in webApp. Returns [] when the user cancels selection.
    arguments
        ...
    end
```

Rules:

- The H1 line is the `UPPERCASE` name plus a one-line summary that ends with a
  period. It is placed before the `arguments` block.
- Describe inputs, outputs, errors raised, and callbacks fired. Do not narrate
  the implementation.
- Private methods and local functions: an H1 line only when the name does not
  already say what the function does.
- Inline comments: one short line that states only what the code cannot show
  (a protocol quirk, an F5 behavior, a MATLAB limitation). No change-log
  comments.
- Keep the `%-----------------------------------------------------------------%`
  separators between methods and local functions, as in the existing files.
- Validate inputs with `arguments` blocks at public boundaries only.

### 3.4 Structure

- One public class or function per file. Helpers are local functions at the
  end of the file.
- Do not create shared helper files for one-time use. Some helpers are
  currently duplicated across files (`absolutePath`, `moveFileWithFallback`,
  `deleteIfExists`). Promote such a helper to a `+datatransfer` function only
  when a phase touches all of its copies anyway.
- No UI calls (`uifigure`, `uihtml`, `uigetfile`, `uiputfile`, `uiconfirm`) in
  `+datatransfer`. No F5/cookie knowledge in `+datatransfer` or `+ui`.

### 3.5 Documentation

- Every phase updates the READMEs it affects in the **same change**: package
  README, `tests/transfers/README.md`, `tests/auth/README.md`, and
  `src/Anatel/+ws/+auth/README.md` (keep each file's language, per D8).
- Fix the stale items listed in `todo.md` ("Refresh stale download
  documentation and links") during Phase 1. They are touched anyway.
- Verify relative links after every rename.
- Update `/memories/repo/ui-download-panel-contract.md` or replace it with a
  `transfer-panel-contract.md` note when the contract changes.

### 3.6 Security (OWASP-relevant, mandatory)

- Cookies are sent only to the exact F5 host over HTTPS (current
  `hasCookieForURL` rule). This applies unchanged to every method, including
  `OPTIONS`, `POST`, `PUT`, `PATCH`, `HEAD`, and `DELETE`.
- Body-bearing requests never follow redirects automatically. A `3xx` from the
  F5 host means `NeedsAuthentication`. A `3xx` from any other host raises
  `datatransfer:sendHTTPRequest:unexpectedRedirect`. Exceptions: the tus
  `Location` on `201 Created`, which identifies the tus resource and is not a
  redirect.
  A body-bearing request that may have reached the server is never replayed
  automatically, including after an auth response. Mark an ambiguous upload
  outcome explicitly and require in-panel confirmation before a user restarts.
  Reauthentication and retry are allowed for preflight requests sent before
  the body operation.
- Authenticate **before** sending the body: the preflight (`OPTIONS`, or
  `HEAD` as a fallback) runs with the session context first. This prevents
  streaming a large body only to receive `302 /my.policy`.
- Sanitize the file name used in the multipart `filename=`, in tus
  `Upload-Metadata`, and in any header. Remove CR/LF, quotes, path separators,
  and control characters to prevent header injection. Use
  `datatransfer.transferFileName`.
- Validate form field names against `^[A-Za-z0-9_.-]{1,64}$`. Extra form
  values must be scalar text. Callers cannot set `Cookie`, `Authorization`,
  `Host`, `Content-Length`, or `Transfer-Encoding` headers.
- For uploads, `LocalPath` must be an existing regular file (not a folder),
  resolved to an absolute path. In `webApp` it must be passed explicitly by the calling
  application (Q3); the panel never accepts a user-typed path there. Enforce
  `MaxUploadBytes` (§5.6).
- Response bodies are never rendered as HTML by the panel. They are capped
  (default 64 KiB) in completion info and are not persisted (D7).
- Never log or persist cookie values. History stores no headers.

---

## 4. Target architecture

```text
src/General/
├── +ui/
│   ├── TransferPanel.m                 (was DownloadPanel.m)
│   └── html/
│       ├── pingTransferAvatar.html     (was pingDownloadAvatar.html)
│       └── orbitDownloadAvatar.html    (unchanged, Q4)
├── icons/
│   ├── transfer-start.svg  transfer-pause.svg  transfer-continue.svg
│   ├── transfer-restart.svg  transfer-trash.svg      (renamed download-*.svg)
│   └── transfer-download.svg  transfer-upload.svg    (new direction badges)
└── +datatransfer/                      (was +download)
    ├── README.md
    ├── TransferManager.m               (was DownloadManager.m)
    ├── TransferHistoryStore.m          (was DownloadHistoryStore.m; SchemaVersion 1 redefined)
    ├── HTTPFileTransfer.m              (new: provider-neutral transfer adapter, no auth)
    ├── sendHTTPRequest.m               (was downloadHTTPResponse.m; all methods + body)
    ├── uploadCapabilities.m            (new: OPTIONS preflight / protocol selection)
    ├── uploadFileWorker.m              (new: multipart / raw / tus)
    ├── UploadProgressMonitor.m          (new: upload request progress monitor)
    ├── downloadFileWorker.m
    ├── downloadSourceMetadata.m
    ├── transferFileName.m              (was downloadFileName.m)
    | `src/General/+download/` | `src/General/+datatransfer/` |
    └── moveToTrash.m

src/Anatel/+ws/+auth/
├── F5Session.m          (method renames in §3.1.1)
├── FileTransfer.m       (was FileDownload.m; subclass of datatransfer.HTTPFileTransfer)
└── DownloadProgressMonitor.m  (unchanged; download-only)

tests/transfers/          (was tests/downloads; checkOrbitDownloadHtml.m unchanged)
```

### 4.1 Ownership (unchanged principle, extended)

| Boundary | Owns | Must not own |
|---|---|---|
| `datatransfer.*` | Direction-neutral lifecycle, HTTP request/response handling for all methods, upload protocol selection, chunking, staging, publication, history. | UI, F5, cookies (it only forwards an opaque `requestContext`). |
| `ui.TransferPanel` | Rows, controls, avatar, source/destination selection dialogs (desktop only), rendering snapshots. | Transfer lifecycle, protocol choice, authentication. |
| `ws.auth.FileTransfer` | Acquiring and refreshing the F5 `requestContext`; reauthenticating before body submission, but never replaying an ambiguous body-bearing operation. | Upload/download protocol logic (inherited from `HTTPFileTransfer`). |

### 4.2 Adapter hierarchy

`datatransfer.HTTPFileTransfer` implements the transfer contract
(`prepare`, `start`, `pause`, `resume`, `stop`, `delete`, `ProgressFcn`,
`CompletedFcn`, `ErrorFcn`, `IsRunning`, `IsPaused`, `IsResumable`). It
dispatches on `request.Direction` to `@datatransfer.downloadFileWorker` or
`@datatransfer.uploadFileWorker` in `backgroundPool`. Its context hooks are
protected methods:

```matlab
methods (Access = protected)
    function context = acquireContext(obj, url)        % default: public, no cookies
    function context = reauthenticate(obj, url)        % default: error authenticationRequired
end
```

`ws.auth.FileTransfer < datatransfer.HTTPFileTransfer` overrides only these
two hooks using `F5Session.getRequestContext` and `authenticateForRequest`.
This removes the current coupling, where public downloads also need an
`F5Session` object. An application without F5 uses
`@(request) datatransfer.HTTPFileTransfer(request)` as its factory.

---

## 5. Contracts

### 5.1 Normalized transfer request

Common fields (manager-normalized):

| Field | Download | Upload |
|---|---|---|
| `Direction` | `'download'` | `'upload'` |
| `URL` | Remote source | Remote endpoint (POST/PUT target or tus creation URL) |
| `LocalPath` | Absolute local target (was `FinalPath`) | Absolute local source; existing regular file |
| `TaskID` | Short UID | Short UID |
| `LogicalFileID` | Hash of `URL` | Hash of canonical `LocalPath` |
| `DisplayMode` | `normal`/`silent` | `normal`/`silent` |
| `TempFolder` | Partial/chunk staging | Upload state only (no source copy) |
| `FileName` | Name part of `LocalPath` | Remote name sent to the server (defaults to the name part of `LocalPath`) |
| `LocalBytes` | Set at completion | Captured at `addUpload` |
| `LocalModifiedAt` (ISO 8601 UTC) | Set at completion | Captured at `addUpload`. If the file changes, resume is invalid. |

`Direction` is the only way to tell source from target. Code that needs the
target folder of a download derives it with `fileparts(LocalPath)`.

The current download `LogicalFileID` (a hash of the target path) changes to a
hash of `URL`, identifying the remote resource independently of its local
destination. Logical identity is not the live-task deduplication key or the
history-row key. Live duplicates remain direction-specific: downloads use
`URL` plus case-insensitive `FileName`; uploads use canonical `LocalPath` plus
exact `URL` (§6.5). Completed/failed history rows group by `Direction`, exact
`URL`, and canonical `LocalPath`; retries and `AttemptedTimestamps` share a row
only when all three match. Different download destinations for the same URL
remain separate. Active tasks always keep separate rows by task ID and are
never hidden solely because their logical IDs match.

Download-only: `PartialPath`, `ChunkPath`, `BackupPath`,
`AllowSourceFilename`.

Upload-only:

| Field | Type / default | Notes |
|---|---|---|
| `Protocol` | `'auto'` \| `'multipart'` \| `'raw'` \| `'tus'` | `'auto'` runs the preflight. |
| `Method` | `'POST'` \| `'PUT'` | For `multipart` (POST only) and `raw`. Default: `POST`. |
| `FormFieldName` | `'file'` | Multipart only. Validated (§3.6). |
| `FormFields` | scalar struct of text | Extra multipart fields. Validated. |
| `ContentType` | from extension, else `application/octet-stream` | |
| `ChunkSize` | 8 MiB | Resumable protocols only. |
| `UploadURL` | `''` | tus resource URL. Set by the worker and persisted for resume. |
| `UploadOffset` | 0 | Last server-confirmed offset. |
| `ResolvedProtocol` | `''` | Set after the preflight. Never `'auto'`. |

### 5.2 Snapshot changes

- Add `Direction`, `IsResumable`, `ResolvedProtocol`, `LocalPath` (both
  directions; replaces `FinalPath`), and `Response` (uploads, after
  completion or failure: `StatusCode`, `Message`, `OutcomeUncertain`).
- Rename `ReceivedBytes` to `TransferredBytes`. `TotalBytes` is the source
  size for uploads.
- The lifecycle vocabulary is unchanged: `created`, `active`, `paused`,
  `awaitingConflictDecision`, `completed`, `failed`, `canceled`,
  `interrupted`. `paused` can only be reached when `IsResumable` is true.
  `TransferManager.pause` on a non-resumable task is a no-op. It returns
  without error and sends no snapshot.

### 5.3 History schema (`SchemaVersion = 1`, redefined)

The version number stays `1` (Q6); no migration code or compatibility aliases
are written. The new default history file is `transfer-history.json`.
`download-history.json` is not imported. A guarded one-time PowerShell check
for that legacy filename in the workspace root found no file. If a configured
history JSON contains the old entry shape (`SourceURL`, `TargetPath`, or
`DownloadedBytes`) instead of the new schema, treat it as corrupt and delete
it; never fill renamed fields or migrate its records. Do not restore legacy
partial-transfer state. New and renamed fields per entry:

| Field | Download | Upload |
|---|---|---|
| `Direction` | `download` | `upload` |
| `SourceURL` → `URL` | remote source | remote endpoint |
| `TargetPath` → `LocalPath` | local target | local source |
| `LogicalFileID` | hash of `URL` | hash of `LocalPath` |
| `DownloadedBytes` → `TransferredBytes` | ✓ | ✓ |
| `Protocol` | `''` | resolved protocol |
| `UploadURL`, `UploadOffset` | — | resumable only, for restore |
| `LocalBytes`, `LocalModifiedAt` | at completion | at registration |
| `Response` | — | `struct('FileName', ..., 'CompletedAt', ..., 'Success', tf, 'StatusCode', n, 'Message', '...', 'OutcomeUncertain', tf)` (D7) |
| `isAvailable` | `isfile(LocalPath)` | `isfile(LocalPath)` (enables Restart) |

`Response.Message` stores the error message on failure, or a short status
phrase in Brazilian Portuguese on success. It never contains the response body. `OutcomeUncertain` is
true only when the request may have been committed but no authoritative outcome
was received; `StatusCode` is empty if there was no response.

### 5.4 Upload completion info (callback only, not persisted)

```matlab
info = struct('TaskID', ..., 'Direction', 'upload', 'URL', ..., ...
              'LocalPath', ..., 'FileName', ..., 'TransferredBytes', ..., ...
              'ResolvedProtocol', ..., 'StatusCode', ..., ...
              'ResponseHeaders', <Location, Content-Type, ETag only>, ...
              'ResponseBody', <uint8, capped 64 KiB>, 'ResponseTruncated', tf);
```

### 5.5 Avatar protocol (`pingTransferAvatar.html`)

- Data items become `{id, rate, progress, direction}`, where `direction` is
  `'download'` or `'upload'`. Missing `direction` is a validation error, not a
  default.
- Upload indicators use a distinct color (proposal: `#1f8f4e`). The central
  arrow glyph shows ↓ when only downloads are visible, ↑ when only uploads are
  visible, and ↕ when both are visible.
- Non-resumable active uploads never send `rate = 0` (that would show the
  pause/warning yellow).
- Events are renamed to `transferAvatarReady` and `transferAvatarClick`. Since
  the protocol breaks anyway, also apply the `todo.md` item "Review duplicate
  HTML event compatibility handling": MATLAB dispatches on the documented
  `HTMLEventName`/`HTMLEventData` only, and the payload `type` fallback is
  removed.


- `TransferManager.MaxUploadBytes`: public property, `(1,1) double`,
  positive, `Inf` allowed. Default `200 * 1024^2` (209 715 200 bytes, the same
  unit nginx uses for `client_max_body_size 200m`).
- `TransferPanel.MaxUploadBytes`: a constructor option and public property.
  Its setter forwards to the manager, following the `setCollisionPolicy`
  pattern.
- The property is runtime-settable on purpose. A future application can read
  a server-defined limit with a `GET` (for example through `F5Session.read`)
  and assign it. No resolver or automatic fetch is implemented now.
- Effective limit = `min(MaxUploadBytes, TusMaxSize)` when the tus preflight
  reports `Tus-Max-Size`.
- Enforcement:
  - `addTransfer` raises `datatransfer:TransferManager:uploadTooLarge` before
    creating a task.
  - `uploadFileWorker` rechecks the file against `MaxUploadBytes` and the
    `TusMaxSize` returned by `prepare` before sending a body, in case the file
    grew or the server limit is lower, and fails with the same size-limit
    identifier.
  - The panel does not catch the `addTransfer` error. The application
    decides how to report it.

---

## 6. Upload protocol behavior

### 6.1 Preflight (`datatransfer.uploadCapabilities`)

```matlab
caps = datatransfer.uploadCapabilities(url, requestContext, request)
% caps: NeedsAuthentication, ResolvedProtocol, IsResumable, AllowedMethods,
%       TusVersion, TusExtensions, TusMaxSize, StatusCode
```

1. Send `OPTIONS url` with the same cookie rules and `MaxRedirects = 0`. For
   tus, add `Tus-Resumable: 1.0.0`. Send no `Origin` header: this is
   capability discovery, not browser CORS.
2. `401`/`403`, or any `3xx` from the F5 host, sets `NeedsAuthentication = true`
   and stops.
3. Selection when `Protocol = 'auto'`, in this order:
   1. **tus**: `Tus-Version` lists `1.0.0` and `Tus-Extension` contains
      `creation`. Reject the upload when `Tus-Max-Size` is smaller than
      `LocalBytes`.
  2. **raw**: `Allow` contains the configured method (`PUT` or `POST`).
  3. **multipart** `POST`: the default.
4. `405`, `501`, a missing `Allow`, or a network error on `OPTIONS` falls back
   to the configured non-resumable protocol (`raw` when
   `Method = 'PUT'`, otherwise `multipart`). It is never an error by itself.
   On the F5 host, a `HEAD` probe confirms authentication when `OPTIONS` is
   inconclusive.
5. An explicit `Protocol` skips selection, but the auth probe still runs.

### 6.2 Non-resumable (`multipart`, `raw`)

- Stream from disk. Use `matlab.net.http.io.MultipartFormProvider` with
  `FileProvider`, or `FileProvider` for raw. Never `fileread` the whole file.
- Progress: a provider-neutral `matlab.net.http.ProgressMonitor` subclass,
- Progress: `uploadFileWorker.m` uses the separate
  `datatransfer.UploadProgressMonitor` class, a
  `matlab.net.http.ProgressMonitor` subclass with `Direction = Request` that
  forwards progress to `progressQueue`. MATLAB requires this class definition
  in its own same-named file. `backgroundPool`/`DataQueue` execution is
  validated in Phase 10, not by offline documentation.
- `pause` is unavailable (D5). `stop`/`cancel` cancels the future. `restart`
  starts from byte 0.
- Success: `2xx`. `409`/`412`/`413`/`415` fail the task with a descriptive
  message (for example `"413 Tamanho da carga excedido: verifique client_max_body_size"`).
- Do not automatically replay a body-bearing request after it may have been
  submitted, regardless of whether a response arrived. A missing response or
  auth response does not prove that the operation was not committed. Retry is
  allowed only when transport evidence proves the request was never submitted.
  Otherwise fail with `Response.OutcomeUncertain = true`, preserve any known
  status code (or `[]` when none was received), and explain in `Message` that
  the server may have received the file. The UI requires explicit confirmation
  before a manual restart.

### 6.3 Resumable: tus 1.0.0

- Create: `POST url` with `Upload-Length` and
  `Upload-Metadata: filename <base64>, filetype <base64>`. Expect `201` with a
  `Location`. Resolve it against `url` and store it in `UploadURL`. A
  `Location` on a different host than `url` fails the task (no cookie
  leakage). Never automatically replay an ambiguous creation POST; without a
  returned `Location`, report `OutcomeUncertain = true`.
- Send: `PATCH UploadURL` with `Upload-Offset`, `Tus-Resumable`, and
  `Content-Type: application/offset+octet-stream`, one chunk per request read
  with `fread` at the offset. Expect `204` with the new `Upload-Offset`.
  Report progress after each chunk.
- After an interrupted or ambiguous `PATCH`, `HEAD UploadURL` returns the
  authoritative `Upload-Offset`. Continue only from that confirmed offset;
  never infer server progress from bytes sent by the client.
 - Cancelar: `DELETE UploadURL` (best effort) when `Tus-Extension` contains
  `termination`.
- `404`/`410` on resume: offer only **Reiniciar**/**Cancelar**.

### 6.4 Content-Range uploads (unsupported)

Content-Range partial `PUT` uploads are not supported. Do not send an empty
`PUT` probe, infer partial-upload support from `Accept-Ranges`, send chunks
with request-side `Content-Range`, or treat `308` as an upload acknowledgement.
The only supported resumable upload protocol is tus 1.0.0 (§6.3). Raw `PUT`
remains whole-file and non-resumable. Reconsidering this exclusion requires a
future user-approved specification revision with a concrete backend contract
and nonmutating capability and offset mechanisms.

### 6.5 Upload conflicts

- No pre-check for remote targets.
- Restored resumable upload (history has `UploadURL` and
  `LifecycleState = interrupted`): the manager sets
  `ConflictType = 'partial'` with `resume`/`restart`/`cancel`, mirroring
  partial downloads. If `LocalBytes` or `LocalModifiedAt` no longer match,
  `resume` is removed from the allowed actions and the row text says the
  source changed.
- Duplicate key for nonterminal uploads: canonical `LocalPath` + exact `URL`.
  Duplicate behavior is the same as for downloads (promotion and no new
  attempt timestamp).

---

## 7. Phases

Each phase lists **files**, **steps**, and a **Definition of done (DoD)**.
For Phases 1–9 the DoD is static (D9). It always includes:

- The MATLAB Code Analyzer (`checkcode`) reports no new warnings in the
  touched files.
- `which` resolves every renamed or new class and function.
- Existing harnesses are updated for the renames (executed in Phase 10).

### Initial step — README translation (documentation-only)

Before Phase 0, translate English explanatory prose in all existing README files
to Brazilian Portuguese, following D8. The current workspace inventory contains
five README files: `src/General/+download/README.md` is in English;
`tests/auth/README.md` contains English sections; the root README,
`tests/downloads/README.md`, and `src/Anatel/+ws/+auth/README.md` are already in
Portuguese. Preserve technical meaning, identifiers, commands, and code
examples; code comments and identifiers remain English per D8. This is a
translation-only task: defer component/path renames and technical updates to
their owning phases. New or rewritten README files are also in Portuguese.

DoD: no English explanatory prose remains in the inventoried READMEs. Existing
technical content is preserved; path/link updates are handled by the rename and
documentation phases.

### Phase 0 — MATLAB feasibility inspection (offline only; no production code)

Inspect installed MATLAB documentation and local API definitions only, using
MATLAB 24.1.0.2837808 (R2024a Update 7). Do not write or run spike scripts,
execute transfer code, send HTTP requests, or contact public/backend endpoints.
Record sources, release, documented API facts, and limitations in an appendix
to this plan. Inspect only the MATLAB syntax and APIs needed by the proposed
implementation, including `FileProvider`, `MultipartFormProvider`,
`ProgressMonitor`, `RequestMethod`, `RequestMessage`, and custom headers.

Documentation cannot prove streaming memory behavior, `backgroundPool` or
`DataQueue` execution, server behavior, or wire-level header handling. Defer
those executable checks to Phase 10. Content-Range uploads are excluded by
Q1; P0 does not test that protocol.

DoD: the appendix distinguishes documented facts from runtime-only
assumptions. Any API or syntax limitation that would change §5/§6 is presented
to the user for approval before Phase 1; agents do not change requirements.

### Phase 1 — Mechanical rename (no behavior change)

Files: existing symbols and files in the rename map of §3.1.1, plus
`tests/downloads` → `tests/transfers` and the affected existing READMEs. P1
renames only artifacts that already exist; entries with no current source are
created in their owning later phase.

Steps:

1. `git mv` only existing folders and files from the shared rename map in
  §3.1.1. Rename classes, constructors, `which(...)` lookups, and error
  identifiers (`download:` → `datatransfer:`, `ui:DownloadPanel:` →
  `ui:TransferPanel:`, `ws:auth:FileDownload:` → `ws:auth:FileTransfer:`).
  Download-only files keep their names but update their namespace references.
2. Apply identifier-only renames to existing methods, properties, private
  members, and events. Rename `addDownload` to `addTransfer` exactly once;
  P2 extends the renamed method with direction-aware behavior. Do not add
  classes/functions/icons in P1, alter serialized/history/request field
  shapes, remove `TargetFolder`, or implement derived-folder behavior.
  Those contract changes belong to their owning phases.
3. Rename the test files per §3.1.1. Do not edit `checkOrbitDownloadHtml.m`
  or `orbitDownloadAvatar.html` (Q4). Move the harness with the folder, and
  confirm by reading that its asset path still resolves from
  `tests/transfers`.
4. Update the compiler packaging snippets in `src/Anatel/+ws/+auth/README.md`
  (`pingTransferAvatar.html` path, `which('ui.TransferPanel')`).
5. Fix the stale-documentation items in `todo.md` and tick them.

DoD: `grep -ri "DownloadManager\|DownloadPanel\|+download\|download\.\(Download\|download\)"`
returns no hits outside this plan and the download-only names in §3.1.1.
Static checks pass. No functional diff.

### Phase 2 — Direction-neutral contracts

Files: `TransferManager.m`, `TransferHistoryStore.m`, `TransferPanel.m`, the
fakes, and `checkTransferManager.m`.

Steps:

  `historyEntry`. Apply the request, snapshot, and history field changes in
  §3.1.1 in this phase. Compute `LogicalFileID` per direction (§5.1): `URL` for
  downloads, which replaces the current target-path hash, and `LocalPath` for
  uploads. Keep logical identity, live deduplication, and history-row keys
  separate; group terminal rows and attempt timestamps by §5.1's approved
  `Direction`/`URL`/canonical `LocalPath` key.
2. Extend the P1-renamed `TransferManager.addTransfer(request)` with direction-
  aware behavior. Branch on `Direction` only where behavior differs: conflict detection, duplicate key,
   cleanup paths, and `isAvailable`.
3. Add the upload fields from §5.3 (empty for downloads), keeping
   `SchemaVersion = 1` (Q6).
4. Upload request validation (§3.6, §5.1): source is an existing regular
   file, `MaxUploadBytes` (§5.6), form field names, and file-name
   sanitization.
5. `IsResumable` in the task and snapshot. `pause`/`resume` are no-ops when it
   is false.
6. Extend `TransferManagerFakeTransfer` with `Direction` and `IsResumable`.

DoD: static checks. Cases for Phase 10 `checkTransferManager`: upload
registration, `uploadTooLarge`, duplicate key for uploads, pause no-op for
non-resumable uploads, interrupted resumable upload restored as a partial
conflict, source-changed resume rejection, response summary persistence, and
legacy-format entries rejected as corrupt and deleted without migration,
same-URL downloads at distinct LocalPaths retained as separate history rows,
and active rows with a shared LogicalFileID kept distinct.

### Phase 3 — HTTP layer

Files: `sendHTTPRequest.m` (generalizes `downloadHTTPResponse.m`) and
`uploadCapabilities.m`.

Steps:

1. Signature:
   `result = sendHTTPRequest(url, requestContext, method, options)` with name-value
   `Range`, `Headers` (allow-listed), `Body` (a `matlab.net.http.io.ContentProvider`
   or `uint8`), `FollowRedirects` (default true only for `GET`/`HEAD`/`OPTIONS`),
   and `ProgressMonitor`.
2. Keep the existing redirect, cookie, and authentication rules. Add the
   body-request redirect policy from §3.6.
3. Update `downloadFileWorker` and `downloadSourceMetadata` to call
   `sendHTTPRequest`.
4. Implement `uploadCapabilities` per §6.1.

DoD: static checks. Give `uploadCapabilities` an optional sender
function-handle argument so that Phase 10 can feed canned
`matlab.net.http.ResponseMessage` objects to it.

### Phase 4 — Upload worker

Files: `uploadFileWorker.m`, `UploadProgressMonitor.m`.

Signature (mirrors the download worker):
`result = uploadFileWorker(requestContext, request, chunkSize, maxRetries, progressQueue, jobId)`.

`result` has `Success`, `NeedsAuthentication`, `TransferredBytes`,
`TotalBytes`, `ResolvedProtocol`, `UploadURL`, `UploadOffset`,
`OutcomeUncertain`, `StatusCode`,
`ResponseHeaders`, `ResponseBody`, `ResponseTruncated`, and `Error`.

Steps:

1. Require a prepared, nonempty `ResolvedProtocol` and the `TusMaxSize`
  capability value from `prepare`. If `ResolvedProtocol` is empty or `auto`,
  return `datatransfer:uploadFileWorker:unpreparedRequest` without sending a
  body; the worker never calls `uploadCapabilities`. Recheck the effective
  upload limit (§5.6).
2. Implement §6.2–§6.3. Before each tus chunk and on resume, verify that the
  source size and modification time are unchanged. Content-Range is excluded
  by §6.4.
3. Progress messages: `struct('Type','progress','JobId',...,'TransferredBytes',...,'TotalBytes',...)`.
   Resumable protocols also send a `Type = 'offset'` message carrying
   `UploadURL`/`UploadOffset`, so the manager can persist them during the
   transfer.

DoD: static checks. Live protocol tests are in Phase 10.

### Phase 5 — Adapters

Files: `datatransfer/HTTPFileTransfer.m`, `ws/auth/FileTransfer.m`, and
`ws/auth/F5Session.m`.

Steps:

1. Move the lifecycle code from `FileDownload` into `HTTPFileTransfer` (§4.2).
  `prepare` branches by direction: download metadata or upload preflight.
  For uploads, `prepare` is the sole owner of `uploadCapabilities`; it
  authenticates/retries the preflight before body submission and supplies the
  resolved protocol and `TusMaxSize` to the worker.
2. Add `IsResumable` (known after `prepare`). `pause` on a non-resumable task
   is a no-op.
3. Handle `Type = 'offset'` messages via a new `StateFcn(state)` callback
   that the manager subscribes to.
4. `ws.auth.FileTransfer` overrides `acquireContext`/`reauthenticate` only,
   using the `F5Session` methods renamed in Phase 1. It may reauthenticate and
   retry before the body operation; after possible submission it surfaces an
   uncertain outcome instead of replaying.

DoD: static checks. `HTTPFileTransfer` has no reference to `ws.auth`.

### Phase 6 — Panel

Files: `TransferPanel.m`, icons, and `TransferPanelFakeTransfer.m`.

Steps:

1. Public API:
   - `taskID = addDownload(url, options)` (unchanged behavior).
   - `taskID = addUpload(url, options)` with `LocalPath`, `FileName`,
     `Protocol`, `Method`, `FormFieldName`, `FormFields`, `DisplayMode`,
     `LogicalFileID`. In desktop modes with empty `LocalPath`, call
     `uigetfile` (or the injected `SourceResolver`, analogous to
     `DestinationResolver`, for tests). In `webApp`, the caller must pass
     `LocalPath` explicitly (Q3). An empty value raises
     `ui:TransferPanel:missingUploadSource`.
   - `MaxUploadBytes` option and property (§5.6).
2. Rows show a direction badge (`transfer-download.svg`/`transfer-upload.svg`)
  left of the file name. The bytes text uses the label `enviados` for uploads.
3. Non-resumable upload rows: hide `ActionButton`; show `RestartButton` and
  `CancelButton` with the visible labels **Reiniciar** and **Cancelar** (D5).
  Visibility is driven by `snapshot.IsResumable`, which
   is unknown (false) until `prepare` completes. That is acceptable.
4. Concluded upload rows: file name, completion timestamp, and status text.
  An uncertain outcome shows `Response.Message` in Portuguese, marks
  `Response.OutcomeUncertain`, and requires an in-row **Confirmar novo envio**
  confirmation before a manual restart; **Cancelar** abandons the restart.
  Ordinary **Reiniciar** re-uploads from `LocalPath` when
  `isAvailable`, and is hidden otherwise. Row text chooses source/target
  wording from `Direction`.
5. Rename the title `Downloads` → `Transferências`. Keep active task rows separate;
  group concluded history only by the approved history-row key in §5.1.
6. The avatar data gets `direction` (§5.5). A non-resumable active upload with
   an unmeasured rate is sent as `100000`, never `0`.
7. Implement the `todo.md` items that touch this file only if they are
   required by the above; otherwise leave them.

DoD: static checks. `TransferPanelFakeTransfer` supports `Direction` and
`IsResumable`, so that Phase 10 can drive the upload rows.

### Phase 7 — Avatar asset

Files: `pingTransferAvatar.html` and `checkPingTransferHtml.m`.

Steps: implement §5.5. Validate `direction` in `normalizeItems`. Keep the
23-slot coordinate scheme. Emit `pingTransferAvatarError` on validation
failures.

DoD: static review of the HTML. `checkPingTransferHtml` sends the
`direction` field (it must, since `direction` is now required).

### Phase 8 — Integration app

Files: `tests/auth/F5BrowserTestApp.m` and `tests/auth/README.md`.

Steps:

1. Add an upload `uiimage` next to the execution-mode toggle. In desktop mode
   it opens `uigetfile` and uploads to the URL currently in the combo box. In
   `webApp` mode the app calls `addUpload` with an explicit `LocalPath` (a
   fixed test file under `tests/transfers/target`).
2. Add combo entries `https://httpbin.org/post` and `https://httpbin.org/put`,
   plus a placeholder for the protected F5 upload endpoint (to be supplied).
3. The factory becomes `@(request) ws.auth.FileTransfer(app.Session, request)`.

DoD: static checks. Manual runs are in Phase 10.

### Phase 9 — Documentation and cleanup

- Rewrite `src/General/+datatransfer/README.md` (Portuguese): modules,
  ownership, request/snapshot/history contracts, upload protocols, preflight
  rules, tus protocol and security notes, packaging (`pingTransferAvatar.html`),
  security notes.
- Update `tests/transfers/README.md`, `tests/auth/README.md`, and
  `src/Anatel/+ws/+auth/README.md` (Portuguese).
- Delete `tests/transfers/spikes/`. Move the Phase 0 appendix into the package
  README if still relevant.
- Update the repository memory note.

### Phase 10 — Runtime validation (LAN/Tus subset authorized)

The supplied unauthenticated LAN service enables download and Tus checks.
These checks do not replace protected F5 validation or the unavailable
one-shot upload backends.

Temporary test service:

- Tus creation endpoint: `http://containerhost.hv:8080/upload/`.
- Download health check: `http://localhost:8080/files/test.txt`.
- A completed upload is available at `http://localhost:8080/files/<FileName>`.
- No authentication is configured. Tests use an empty cookie context.
- `checkUploadHttp` uses a unique file name and leaves the uploaded test file
  on the service; it cleans only local temporary files.

Observed setup evidence (2026-10-07): `GET /files/test.txt` returned HTTP 200
with 5 bytes. `OPTIONS /upload/` returned HTTP 200 with `Tus-Version: 1.0.0`,
`Tus-Extension` including `creation`, and `Tus-Max-Size: 2147483648`; it omitted
`Allow`. `uploadCapabilities` now accepts advertised Tus creation capability
without `Allow`. These endpoint probes confirm setup only; MATLAB harness
reports remain pending.

1. LAN checks:
   - `checkDownloadHttp` fetches `test.txt` through the download worker.
   - `checkUploadPreflight` verifies canned Tus capability responses, including
     a valid Tus response without `Allow`.
   - `checkUploadHttp` discovers Tus, uploads multiple chunks through
     `backgroundPool`/`DataQueue`, and verifies downloaded bytes match.
   - These checks do not validate raw `PUT`, multipart `POST`, ambiguous
     one-shot outcomes, or an interrupted-upload recovery.
2. Protected backend and F5 checks remain deferred:
   - F5 responses without a cookie for `OPTIONS`, `POST`, `PUT`, and `PATCH`
     on the protected host (expected: `302 /my.policy`).
   - With a cookie: whether the APM forwards `OPTIONS`, buffers request
     bodies, or imposes size limits.
   - Whether the protected backend limit matches `MaxUploadBytes`.
   - Manual `F5BrowserTestApp` upload flow.
3. Run the LAN checks and the non-network harnesses from §8 that are available.
   Record skipped protected-backend checks explicitly.
4. Fix defects found in the authorized checks. Do not mark Phase 10 complete
   until the protected-backend and remaining protocol checks pass.

---

## 8. Test matrix (minimum, executed in Phase 10)

| Area | Harness | Network |
|---|---|---|
| Manager lifecycle, history fields, size limit, duplicates | `checkTransferManager` | No |
| Silent tasks (both directions) | `checkTransferSilent` | No |
| Panel UI, controls per resumability | `checkTransferPanel` (manual) | No |
| Source/destination resolution per mode | `checkTransferPanelDestination` | No |
| Avatar protocol | `checkPingTransferHtml` (manual) | No |
| Download transport and service health | `checkDownloadHttp` | LAN |
| Preflight selection | `checkUploadPreflight` | Canned responses |
| Tus upload, confirmed offsets, `DataQueue` callbacks in `backgroundPool`, and byte-for-byte retrieval | `checkUploadHttp` | LAN |
| Raw/multipart upload and uncertain one-shot outcomes | Deferred backend harness | Backend required |
| F5 end-to-end | `F5BrowserTestApp` (manual) | F5 + MFA |

Harnesses that do not require UI return a `report` struct with one logical
field per assertion and raise an error on the first failed assertion. Follow
the existing `checkDownloadManager` pattern.

## 9. Reference server profile (input to backend configuration, Phase 10)

The backend is being configured separately. This profile states what the
client expects from it. If a local copy is useful, place it in
`tests/transfers/server/nginx.conf`, bound to `127.0.0.1` only.

- `location /upload/raw/` with `dav_methods PUT`, `client_max_body_size 200m`
  (aligned with §5.6),
  `client_body_temp_path`, and `create_full_put_path on`.
- `location /upload/form` proxied to a minimal backend (or `return 201` with
  `proxy_request_buffering off` for size and stream tests only).
- `location /files/` with `proxy_pass` to `tusd`
  (`proxy_request_buffering off`, `client_max_body_size 0`,
  `proxy_set_header X-Forwarded-*`).
- An `OPTIONS` response for `/upload/raw/` that emits `Allow: OPTIONS, PUT`
- `/upload/raw/` is a whole-file `PUT` endpoint. Do not configure partial
  `PUT` or advertise `Accept-Ranges` as an upload capability. Resumable
  uploads use the separate tus endpoint under `/files/`.

## 10. Review checklist for each pull request

- [ ] Error identifiers follow §3.2.
- [ ] Every new or changed public member has an H1 docstring (§3.3). No
      narrative or change-log comments.
- [ ] No UI calls in `+datatransfer`. No F5 knowledge outside `ws.auth`.
- [ ] Names match the §3.1.1 map (shared: "transfer"; download-only: kept;
      upload-only: "upload").
- [ ] Security rules in §3.6 hold (cookie scope, redirects, sanitization,
      explicit `webApp` source, size limit, response cap).
- [ ] The affected READMEs are updated in the same PR, in their own language.
- [ ] Static checks pass (Phases 1–9). Harness cases for Phase 10 are listed
      in the PR description.

## Appendix A. Draft implementation contracts

Status: **draft for review, not implementation authorization**. This appendix
clarifies cross-agent interfaces without approving new behavior. Approved
decisions D1-D9 and Q1-Q7 take precedence. If the appendix conflicts with the
plan, stop the affected task and record the conflict in the
[implementation tracker](http-transfer-implementation-tracker.md).
Delegation templates are in
[the delegation draft](http-transfer-delegation-draft.md); inactive repository
instructions are in [the instructions draft](http-transfer-instructions-draft.md).

### A.1 Location, identity, and ownership

- `Direction` is mandatory: `'download'` or `'upload'`. `URL` is the original
  remote address. `LocalPath` is the absolute local file path, a destination
  for downloads and a source for uploads. No stored `TargetFolder`,
  `FinalPath`, or `SourcePath` aliases are retained.
- Default `LogicalFileID`: hash the exact `URL` for downloads and canonical
  `LocalPath` for uploads. Preserve the existing hash utility/encoding unless
  review requires a change. Explicit caller IDs remain supported.
- Identity comparisons include `Direction`; do not deduplicate an upload
  against a download. Nonterminal duplicate keys remain download `URL` plus
  case-insensitive `FileName`, and upload canonical `LocalPath` plus exact
  `URL`. Logical identity is not the deduplication key.
- Approved history-row key: `Direction` plus exact `URL` plus canonical
  `LocalPath`. Group only terminal entries with the same key;
  `AttemptedTimestamps` are per row key. Active rows remain separate by
  `TaskID` even when their `LogicalFileID` matches.
- `FileName` is the basename of `LocalPath` for downloads and the selected
  remote filename for uploads. Never change the upload source path when
  sanitizing or changing the remote filename.
- `LocalBytes` is a nonnegative scalar double; `LocalModifiedAt` is UTC ISO
  8601 text. Capture both for uploads before registration and for downloads
  after publication; use `[]` and `''` while a download target is unavailable.
- The manager owns request validation, IDs, lifecycle, history, and snapshots.
  Adapters own asynchronous execution and suppress stale worker generations.
  Workers own HTTP/protocol operations. The panel owns graphics only.

### A.2 Boundary contracts

| Boundary | Inputs | Output and defaults |
|---|---|---|
| `TransferFactory(request)` | Manager-normalized scalar request struct | Adapter with `prepare`, `start`, `pause`, `resume`, `stop`, callbacks, and readable `IsRunning`, `IsPaused`, `IsResumable` |
| `prepare()` | No arguments | Scalar metadata struct: `Direction`, `URL`, `LocalPath`, `FileName`, `TotalBytes`, `IsResumable`, `ResolvedProtocol`, `TusMaxSize`, `UploadURL`, `UploadOffset` |
| `uploadCapabilities(url, context, request)` | Endpoint, transient request context, upload request | Scalar capabilities struct listed in section 6.1; never persist context |
| Both file workers | Context, normalized request, chunk size, retry bound, queue, generation ID | Common result below; direction-specific fields are empty when unused |
| Manager `getSnapshot(id)` | Numeric presentation ID | Snapshot fields from section 5.2 plus existing IDs, lifecycle, conflicts, rates, timestamps, history entry; no adapter/UI handles |

The normalized upload worker request includes the current `MaxUploadBytes`
value captured when that execution starts (default `200 * 1024^2`) and the
`TusMaxSize` discovered by `prepare`. A later property change affects
subsequent executions; do not promise live mutation of an already serialized
worker request. The worker recomputes the effective limit from those values.
`ChunkSize` remains execution configuration, not an HTTP capability.

`prepare()` must not start file-body transfer. It is the sole owner of upload
capability discovery and authentication preflight; workers never repeat it. A
download may refine
`LocalPath` from source metadata only when `AllowSourceFilename` permits it;
the manager rechecks conflicts before starting. Upload preparation cannot
change `LocalPath`. A non-resumable upload reports `IsResumable = false`.

### A.3 Callbacks and queue messages

| Layer | Signature | Rule |
|---|---|---|
| Adapter | `ProgressFcn(transferredBytes, totalBytes)` | Bytes refer to file payload, not multipart envelope size; unknown total is `[]` |
| Adapter | `StateFcn(state)` | Scalar protocol state: `IsResumable`, `ResolvedProtocol`, `UploadURL`, `UploadOffset`; no credentials |
| Adapter | `CompletedFcn(info)` | Once after confirmed completion, not merely bytes sent |
| Adapter | `ErrorFcn(exception)` | Once on terminal failure; cancellation is not failure |
| Manager | `SnapshotFcn(snapshot)`, `TaskReorderedFcn(snapshot)` | Preserve silent-task presentation filtering |
| Manager | `CompletedFcn(id, info, snapshot)`, `ErrorFcn(id, exception, snapshot)` | Preserve notification for silent tasks |

Queue messages carry `Type` and `JobId`. `progress` carries `TransferredBytes`
and `TotalBytes`; `offset` carries `UploadURL` and `UploadOffset`. Any change
to protocol or resumability also sends a state message so the manager can
publish an updated snapshot and the UI can hide/show the pause control.
Adapter pause, stop, restart, and deletion invalidate the previous generation
before accepting more messages. A server-confirmed offset, not bytes read
from disk or sent by the client, is authoritative for resumable uploads.

### A.4 Worker results and persistence

Both workers return scalar structs with `Success` (false),
`NeedsAuthentication` (false), `Direction`, `URL`, `LocalPath`, `FileName`,
`TransferredBytes` (0), `TotalBytes` ([]), `ResolvedProtocol` (''),
`UploadURL` (''), `UploadOffset` (0), `StatusCode` ([]), `ResponseHeaders`
(scalar allow-listed struct), `ResponseBody` (empty uint8),
`ResponseTruncated` (false), `OutcomeUncertain` (false), and `Error` ([] or `MException`). Downloads
also retain `FinalURL` and `ResolvedFileName` for redirects/source metadata.
These HTTP-derived values do not replace the original identity `URL`.

`NeedsAuthentication = true` is a control result, not success. The adapter
refreshes context on the MATLAB foreground and retries only before body
submission or after a protocol-specific authoritative status check. An
ambiguous body-bearing result sets `OutcomeUncertain` and is never replayed
automatically. Never serialize the session handle to a worker. Exact-host
HTTPS cookie scope remains enforced at every request, including upload
resource URLs.

History keeps `SchemaVersion = 1`, the current common entry IDs, timestamps,
measured-rate fields, attempt list, and error list, plus section 5.3 fields.
Use one homogeneous entry shape for both directions; unused text fields are
`''`, numeric unknowns are `[]`, and lists are empty cell arrays. History
`TemporaryPath` maps to the download request's `PartialPath`, not `LocalPath`.
Upload source files never participate in temporary-file cleanup.

Persist only the response summary defined in section 5.3. Full headers,
bodies, cookies, and authentication contexts are excluded. Cap callback-only
response data at 64 KiB during reception, not just after buffering it all.
`isAvailable = isfile(LocalPath)` is local availability, not proof of remote
upload availability or downloaded-content integrity.

### A.5 Review gates

The tracker records safety and feasibility blockers with proposed resolutions.
Content-Range partial uploads are unsupported: do not infer capability from
`Accept-Ranges`, send an empty `PUT` probe, or treat `308` as an upload
acknowledgement. Tus is the only resumable upload protocol. Do not replay an
ambiguously committed POST. Network tests remain deferred; static checks must
report unavailable MATLAB tooling honestly.

## Appendix B. MATLAB API Inspection Results (P0)

Status: **verified offline documentation/API inspection; no project-code execution or network contact**.
MATLAB version: `24.1.0.2837808 (R2024a) Update 7`; `version('-release')` is `2024a`.

This appendix records installed MATLAB documentation and API inspection without
running project code or transfer logic, or contacting endpoints.

### B.1 Verified API Facts

**FileProvider** (`matlab.net.http.io.FileProvider`)
- A `ContentProvider` for sending files as HTTP request bodies
- Can serve as a `RequestMessage` body
- Derives `Content-Type` from filename extension
- Automatically adds `Content-Disposition` with filename
- API exposes `getData` method returning the next buffer
- Documented behavior does not prove memory-bound streaming

**MultipartFormProvider** (`matlab.net.http.io.MultipartFormProvider`)
- For `multipart/form-data` requests
- Each part has a control name
- Part data can be a `RequestMessage.Body.Data` type or another `ContentProvider`
- Help documentation does not prove specific memory or wire framing behaviors beyond these facts

**MultipartProvider** (`matlab.net.http.io.MultipartProvider`)
- `multipart/mixed` by default
- Delegates supply parts in sequence
- Documentation states it sends the message chunked without `Content-Length`
- Do not attribute unverified details to `MultipartFormProvider`

**ProgressMonitor** (`matlab.net.http.ProgressMonitor`)
- Abstract base class
- `Direction` and `Value` are abstract properties
- MATLAB initially sets `Direction` to `MessageType.Request` when `RequestMessage.send` sends the request; when response reception begins, MATLAB sets it to `MessageType.Response`
- Updates `Value` repeatedly during transfer
- `HTTPOptions` has `ProgressMonitorFcn` and `UseProgressMonitor` properties
- The documented `Direction` transition provides request-versus-response context for progress reporting
- Documentation does not prove callback threading or `backgroundPool`/`DataQueue` behavior

**RequestMethod** (`matlab.net.http.RequestMethod`)
- References the IANA registry
- Available methods confirmed: GET, HEAD, OPTIONS, POST, PUT, PATCH, DELETE (among others)

**RequestMessage** (`matlab.net.http.RequestMessage`)
- Has `Method`, `Header`, `Body` properties
- Supports `send`/`complete` methods
- No actual send operations were called during inspection

**HeaderField** (`matlab.net.http.HeaderField`)
- Documents string `Name`/`Value` properties
- Allows arbitrary field names subject to HTTP character restrictions
- Specialized subclasses are preferred for common fields
- `GenericField` does not exist at the queried namespace

**HTTPOptions** (`matlab.net.http.HTTPOptions`)
- Has `ProgressMonitorFcn` and `UseProgressMonitor` properties

### B.2 Implementation Interpretations (Not Contract Changes)

- Implementation interpretation: forward progress as upload payload only while `Direction` is `MessageType.Request`; do not report response-direction bytes as upload bytes
- No approved contract change was necessary: `HeaderField` provides the documented general header mechanism
- `GenericField` is not needed and does not exist in the inspected API

### B.3 Unverified Limitations

The following aspects remain unverified by documentation inspection and are deferred to Phase 10:
- Memory streaming behavior
- `MultipartFormProvider` wire framing/headers beyond its help
- Progress callback threading and behavior in asynchronous workers
- `backgroundPool`/`DataQueue` execution and interaction with progress callbacks
- Server behaviors
- Cookie/authentication handling
- Live transport behavior
- Wire-level header handling beyond the documented API descriptions

### B.4 Command Execution Note

Successful MATLAB help/API queries (no project scripts or transfer code):

```powershell
matlab.exe -batch "disp(version); disp(version('-release')); help matlab.net.http.io.FileProvider; help matlab.net.http.io.MultipartFormProvider; help matlab.net.http.ProgressMonitor; help matlab.net.http.RequestMethod; help matlab.net.http.RequestMessage; help matlab.net.http.HeaderField; help matlab.net.http.GenericField;"
matlab.exe -batch "help matlab.net.http.HTTPOptions; enumeration matlab.net.http.RequestMethod; help matlab.net.http.io.MultipartProvider;"
```

The first shell attempt for the second query failed during PowerShell parsing,
before MATLAB launched; the PATH-based command above succeeded. No project
scripts, tests, transfers, network communications, authentications, endpoints,
benchmarks, background executions, or wire behaviors were verified.
