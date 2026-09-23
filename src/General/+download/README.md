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

## Boundaries

`download.DownloadManager` receives a normalized request and an injected
`DownloaderFactory`. The manager owns transfer state, but it does not create UI
controls or call UI APIs. Its snapshots contain task state, paths, byte counts,
rates, timestamps, and error information without exposing downloader objects or
UI handles.

The presentation layer is [`ui.DownloadPanel`](../+ui/DownloadPanel.m). It
renders manager snapshots and translates row actions into manager commands. Its
avatar asset is [`downloadAvatar.html`](../+ui/html/downloadAvatar.html).
The panel and avatar are UI concerns and are intentionally kept outside this
package.

Authentication adapters remain outside this package. For F5-authenticated
transfers, `ws.auth.FileDownload` supplies the request context and invokes
`@download.downloadFileWorker`; the generic worker does not inspect cookies or
know about `F5Session`.

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
    'tempPath', temporaryFolder, ...
    'targetPath', targetFolder);
```

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
