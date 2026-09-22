# tests/ui

This folder contains the manual UI harness and test double for
`src/General/+ui/DownloadPanel`.

It also contains the isolated visual harness for
`src/General/+ui/html/downloadAvatar.html`. The avatar harness and the panel
harness are deliberately separate: one verifies the HTML presentation
protocol, while the other verifies the MATLAB panel, downloader factory, task
lifecycle, and file-system behavior.

## Files

| File | Role |
|---|---|
| [`checkDownloadPanel.m`](checkDownloadPanel.m) | Opens a manual `uifigure` harness for the reusable panel. |
| [`checkDownloadHtml.m`](checkDownloadHtml.m) | Tests only the `downloadAvatar.html` `uihtml` asset. |
| [`DownloadPanelFakeDownloader.m`](DownloadPanelFakeDownloader.m) | Simulates the downloader object required by `ui.DownloadPanel`. |

These files have different responsibilities. `checkDownloadPanel` is the
actual interactive test harness. `DownloadPanelFakeDownloader` is its injected
dependency: it provides deterministic timer-driven progress and file-system
behavior without network traffic, F5 authentication, or `backgroundPool`.

`checkDownloadHtml` is intentionally separate from the panel harness. It tests
only the presentation protocol of `downloadAvatar.html`: progress levels,
active state, orbit ball count, orbit speed, the ready event, and the click
event. It does not create download files, instantiate `ui.DownloadPanel`, or
perform network or authentication work.

## Isolated avatar harness

`checkDownloadHtml.m` creates a small `uifigure` containing the
`downloadAvatar.html` `uihtml` component and controls for its visual state:

- Progress from `0%` to `100%`, converted to avatar levels `0` to `10`.
- Active/inactive animation state.
- Orbit ball count from `1` to `10`.
- Orbit speed in radians per second.
- A click indicator that confirms `downloadAvatarClick` reached MATLAB.

This harness is presentation-only. It does not create temporary or target
files, start `ui.DownloadPanel`, authenticate, or perform network transfers.

## DownloadPanel integration

`checkDownloadPanel.m` exercises `ui.DownloadPanel` with
`DownloadPanelFakeDownloader`. It provides four sample links with different
sizes and speeds, task progress, pause/resume/stop behavior, target and partial
conflict choices, and the close/trash controls. The panel uses the shared
`downloadAvatar.html` asset internally.

The F5 integration example is [`F5BrowserTestApp.m`](../auth/F5BrowserTestApp.m).
It supplies the authenticated `ws.auth.FileDownload` factory while
`ui.DownloadPanel` remains responsible for the download UI and task lifecycle.

The panel sends the following state to `downloadAvatar.html` after the asset
reports ready:

- `level`: aggregate progress level from `0` to `10`.
- `inProgress`: whether at least one transfer is active.
- `ballCount`: number of active downloads represented by orbiting balls.
- `speedRadiansPerSecond`: aggregate visual orbit speed.

The asset emits `downloadAvatarReady` and `downloadAvatarClick`, with payload
types `ready` and `click`. The avatar asset itself does not access files,
authentication, or network services.

## F5 download integration

When `F5BrowserTestApp` receives a URL whose final path segment has an
extension, it delegates the request to `ui.DownloadPanel`. The application
factory creates `ws.auth.FileDownload` with the authenticated F5 session.
`FileDownload` transfers data in `backgroundPool`; task-scoped partial files
and chunks are stored in the configured temporary folder, and the completed
file is published in the target folder only after the transfer succeeds.

The panel supports multiple concurrent downloads, pause/resume, stopping,
target conflicts (**Overwrite**, **Save as new**, **Cancel**), and partial-file
conflicts (**Resume**, **Restart**, **Cancel**). The application keeps only
F5-specific authentication, logging, and error reporting concerns.

## Running the harness

From the repository root, add the test folder to the MATLAB path and run:

```matlab
addpath(fullfile(pwd, 'tests', 'ui'))
uiFigure = checkDownloadPanel;
```

To run the isolated download-avatar test:

```matlab
uiFigure = checkDownloadHtml;
```

The harness adds `src/General` to the path automatically. When executed, it
creates `tests/ui/temp` and `tests/ui/target` and uses them as the simulated
temporary and target folders.

## Manual scenarios

- **`sample1.bin`** downloads 10 MB at 250 kB/s.
- **`sample2.bin`** downloads 20 MB at 500 kB/s.
- **`sample3.bin`** downloads 30 MB at 750 kB/s.
- **`sample4.bin`** downloads 40 MB at 1 MB/s.
- The **trash icon** stops active tasks and removes both `temp` and `target`
  folders with all their contents. The folders are recreated automatically
  when another sample link is clicked.
- Existing target files use the shared conflict row with **Overwrite**, **Save
  as new**, and **Cancel**.
- The download row exercises progress callbacks, completion callbacks, and
  temporary-file cleanup.

The harness uses `executionMode = 'webApp'` to verify that the panel's
application-level controls can represent the flow without desktop file
selection or modal conflict dialogs. The test still runs in a local MATLAB
`uifigure`; it does not start MATLAB Web App Server.

## Fake downloader contract

`DownloadPanelFakeDownloader` exposes the same surface expected from a real
downloader:

- `start`, `pause`, `resume`, `stop`, and `delete` methods.
- `ProgressFcn`, `CompletedFcn`, and `ErrorFcn` callback properties.
- `IsRunning` and `IsPaused` state properties.

Its timer advances each sample at its configured speed, writes representative
bytes to both `Request.PartialPath` and `Request.ChunkPath`, and publishes a
file at `Request.FinalPath` with the configured size. Stopping or pausing
preserves both staging files for continuation. Successful completion removes
the partial file, chunk file, and any overwrite backup. It intentionally does
not model real HTTP behavior,
authentication, retries, or cross-volume publication; those responsibilities
are covered by `ws.auth.FileDownload` and its worker.

## Limitations

This is a manual visual/integration harness, not an automated assertion suite.
The callback counters and status label provide immediate feedback, while the
fake downloader makes the panel behavior repeatable. Authenticated F5 transfer
validation belongs to `tests/auth/F5BrowserTestApp.m` and requires the real
interactive authentication flow.
