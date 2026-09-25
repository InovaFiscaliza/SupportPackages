# download

Provider-neutral download services for MATLAB applications.

This package contains the transfer logic shared by public HTTP sources and
provider-specific adapters such as `ws.auth.FileDownload`. It does not depend
on `uifigure`, `uihtml`, `ui.DownloadPanel`, authentication sessions, cookies,
or other presentation classes.

The package should be resolved by adding `src/General` to the MATLAB path. Do
not add the `+download` folder itself.

## Modules

| Module | Responsibility |
|---|---|
| [`DownloadManager.m`](DownloadManager.m) | Owns task registration, lifecycle transitions, task IDs, conflict decisions, downloader callbacks, snapshots, late-callback filtering, cleanup, and completion/error notifications. |
| [`downloadFileWorker.m`](downloadFileWorker.m) | Performs resumable chunked HTTP transfers, writes task-scoped temporary files, publishes completed files, retries recoverable failures, and reports progress. |
| [`downloadHTTPResponse.m`](downloadHTTPResponse.m) | Sends HTTP `GET` and `HEAD` requests with cookie-aware redirect handling, byte ranges, authentication-response detection, and URL validation. |
| [`downloadSourceMetadata.m`](downloadSourceMetadata.m) | Reads source headers and derives metadata such as the final URL and `Content-Disposition` filename before a transfer starts. |
| [`downloadFileName.m`](downloadFileName.m) | Derives a safe filename from a URL or creates a deterministic fallback filename. |
| [`downloadContentDispositionFileName.m`](downloadContentDispositionFileName.m) | Extracts and sanitizes `filename` and `filename*` values from a `Content-Disposition` header. |

## Architecture

The download subsystem is split into three boundaries:

```text
src/General/
├── +ui/
│   ├── DownloadPanel.m
│   └── html/
│       ├── downloadAvatar.html (legacy)
│       ├── pingDownloadAvatar.html
│       └── downloadStatus.html
└── +download/
    ├── DownloadManager.m
    ├── downloadContentDispositionFileName.m
    ├── downloadFileName.m
    ├── downloadFileWorker.m
    ├── downloadHTTPResponse.m
    └── downloadSourceMetadata.m

src/Anatel/+ws/+auth/
├── F5Session.m
├── FileDownload.m
└── DownloadProgressMonitor.m
```

### Ownership boundaries

| Boundary | Owns | Must not own |
|---|---|---|
| `download.*` | Provider-neutral HTTP transfer, response handling, source metadata, filename derivation, task-scoped staging, publication, and transfer orchestration. | UI controls, figures, authentication sessions, cookies, or provider-specific behavior. |
| [`ui.DownloadPanel`](../+ui/DownloadPanel.m) | Presentation, row controls, avatar state, UI callbacks, and rendering manager snapshots. | Transfer lifecycle, authentication, cookie inspection, or direct downloader calls. |
| `ws.auth` | F5 session handling, cookie capture, reauthentication, profile retrieval, and the `FileDownload` adapter. | Generic UI and provider-neutral transfer implementations. |

`DownloadManager` receives an injected `DownloaderFactory`; it does not call
`uifigure`, `uihtml`, `uiputfile`, `uiconfirm`, `questdlg`, or other UI APIs.
Destination selection belongs to the panel, the consuming application, or an
injected destination resolver. The manager receives the normalized result and
owns conflict detection and lifecycle transitions.

`ui.DownloadPanel` accepts an optional `DestinationResolver` callback for
desktop-like modes. The callback receives `ExecutionMode`, `URL`,
`SuggestedFileName`, `InitialFolder`, and `UIFigure`, and returns a scalar
struct with `Cancelled`, `TargetFolder`, and `FileName`. Without a callback,
the panel uses `uiputfile`. In `webApp` mode the callback and `uiputfile` are
both bypassed: the panel requires an existing `TargetPath` and derives the
filename from the URL.

The active download avatar is
[`pingDownloadAvatar.html`](../+ui/html/pingDownloadAvatar.html), beside the
panel's UI implementation. It is not part of this provider-neutral package.
The old [`downloadAvatar.html`](../+ui/html/downloadAvatar.html) is retained as
a legacy asset for `tests/downloads/checkDownloadHtml.m`; it is not used by
`ui.DownloadPanel`. The optional `downloadStatus.html` asset follows the same
UI ownership rule.

### Manager contract

`download.DownloadManager` owns task registration, task IDs, state transitions,
`start`, `pause`, `resume`, and `cancel` commands, downloader callbacks,
late-callback filtering, cleanup, conflict decisions, snapshots, and
completion/error notifications. It exposes snapshots and events, never UI
handles or downloader internals.

A normalized `DownloadRequest` contains the URL, task ID, temporary folder,
target folder, filename, final path, display mode, task-scoped partial/chunk
paths, and applicable conflict policies. A `TaskSnapshot` contains the task ID,
lifecycle state, paths, received and total bytes, progress fraction, a measured
`TransferRate` in bytes per second, timestamps, and error information, along
with task and conflict state. `TransferRate` is `NaN` until enough progress
samples are available. The snapshot does not contain a separate estimated rate
or rate-source field; `ui.DownloadPanel` derives the estimated remaining time
from the remaining bytes and `TransferRate`. Neither contract exposes UI handles
or downloader internals.

`DisplayMode` accepts `normal` or `silent` and belongs to the manager task
state, not to URL inference or downloader behavior. Silent tasks retain the
same lifecycle, downloader callbacks, cleanup, and completion/error callbacks,
but their snapshots and reorder notifications are omitted from presentation by
default. Set `IncludeSilentTasks` on `DownloadManager` to include those
snapshots in the panel and avatar without changing the downloader contract.

The lifecycle vocabulary is authoritative:

- `pause` stops transfer while preserving resumable temporary state;
- `cancel` stops transfer, removes task-scoped temporary files, and removes the
    task from the panel;
- `restart` discards the partial state before starting again;
- target conflicts use `overwrite`, `uniqueName` (shown as **Save as new**),
    and `cancel`;
- partial-file conflicts use `resume`, `restart`, and `cancel`.

The panel translates user actions into manager commands and renders snapshots.
Task state has one owner: the manager owns transfer state, while the panel owns
only UI handles and presentation state.

When a target or partial file conflict is detected with the corresponding
policy set to `askInRow`, the manager emits a pending snapshot. The panel
renders the appropriate row choices without opening a modal dialog:
`Overwrite`, **Save as new**, and `Cancel` for target conflicts, or `Resume`,
`Restart`, and `Cancel` for partial files. Automatic policies such as
`overwrite` are applied before any pending snapshot is emitted. The manager
rechecks the destination before publication.

### Adapter boundary

Generic helpers use normalized request arguments and a provider-supplied
`requestContext`. For F5-authenticated transfers, `ws.auth.FileDownload`
supplies the context and invokes `@download.downloadFileWorker`. The generic
worker does not inspect cookies or know about `F5Session`.

The remaining
[`src/Anatel/+ws/+auth/downloadFileWorker.m`](../../Anatel/+ws/+auth/downloadFileWorker.m)
file is a compatibility wrapper during this migration. It delegates to
`download.downloadFileWorker`; there is only one worker implementation. Once
all external callers are confirmed to use the new namespace, the wrapper may be
removed or retained as an explicitly documented compatibility entry point.

No package calls into another provider's concrete implementation. The
normalized request and provider `requestContext` are the only transfer
boundary between generic services and authentication adapters.

### Namespace and error policy

All repository callers use `download.*` for generic helpers, including
`download.downloadFileName`, `download.downloadSourceMetadata`,
`download.downloadHTTPResponse`, and `@download.downloadFileWorker`.

Generic errors use the `download:*` namespace. F5 adapter errors use
`ws:auth:*`, and panel errors use `ui:DownloadPanel:*`. Old `ui.download*`
implementations are not maintained as permanent duplicate wrappers.

### Path, packaging, and validation

Add `src/General` to the MATLAB path so `ui.*` and `download.*` resolve as
sibling packages. Do not add either package folder directly. `+download` code
files are regular code dependencies. UI assets such as
`pingDownloadAvatar.html` and `downloadStatus.html` must be included explicitly
as additional files in compiled applications; `profileAvatar.html` remains
under `+ws/+auth`. The legacy `downloadAvatar.html` is only needed when running
its dedicated legacy harness.

The avatar asset is resolved relative to `DownloadPanel.m`. Its MATLAB-to-HTML
protocol sends one `{id, rate, progress}` struct per active visible download
and uses the `downloadAvatarReady` and `downloadAvatarClick` events. Compiled
applications must include the asset explicitly rather than copying it into
the consuming application.

Validate the generic package with `tests/downloads/checkDownloadHttp.m`, validate the
manager contract without UI using `tests/downloads/checkDownloadManager.m`, and
validate the panel/factory boundary with `tests/downloads/checkDownloadPanel.m`. Real
F5 authentication in `F5BrowserTestApp.m` is a later integration check and is
not required for provider-neutral tests.

## Request boundary

A normalized request contains, at minimum:

```matlab
request = struct(...
    'URL', url, ...
    'TaskID', taskID, ...
    'TempFolder', temporaryFolder, ...
    'TargetFolder', targetFolder, ...
    'FileName', fileName, ...
    'FinalPath', fullfile(targetFolder, fileName), ...
    'PartialPath', partialPath, ...
    'ChunkPath', [partialPath, '.chunk']);
```

`TempFolder` is used for partial and chunk files. `TargetFolder` is used only
for the completed file. The worker publishes the completed file after a
successful transfer and removes successful staging files.

## Usage

For a UI-backed application, construct the panel with a factory that adapts the
request to the selected provider:

```matlab
panel = ui.DownloadPanel(parentContainer, ...
    'DownloaderFactory', @(request) ws.auth.FileDownload(session, request), ...
    'DestinationResolver', @resolveDestination, ...
    'tempPath', temporaryFolder, ...
    'targetPath', targetFolder);
```

`DestinationResolver` is optional. It is useful for automated tests and for
applications that already own a desktop destination workflow. Collision
choices remain manager operations regardless of how the initial destination
was selected.

For a non-F5 provider, the factory can return any object implementing the
manager downloader contract: `start`, `pause`, `resume`, and `stop` methods,
plus `ProgressFcn`, `CompletedFcn`, and `ErrorFcn` callback properties.

The panel deduplicates nonterminal tasks by URL and target filename. A repeated
request returns the existing task and brings its row to the top. `Pause`
stops transfer while retaining resumable temporary files. `Cancel` stops the
transfer, deletes task temporary files, and removes the row.

Generic errors use the `download:*` identifier namespace. Authentication and
UI-specific errors remain owned by their respective adapter or presentation
package.
