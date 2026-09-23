# tests/auth

Exemplos e validação de [`ws.auth.F5Session`](../../src/Anatel/+ws/+auth/README.md), o módulo de autenticação SAML 2.0 + MFA através do proxy reverso F5 BIG-IP APM.

| Arquivo | Tipo | Finalidade |
|---|---|---|
| [checkF5Auth.m](checkF5Auth.m) | Script por seções | Validação passo a passo do fluxo |
| [`profileAvatar.html`](../../src/Anatel/+ws/+auth/profileAvatar.html) | Componente `uihtml` compartilhado | Avatar reutilizável para o estado de autenticação |
| [checkProfileHtml.m](checkProfileHtml.m) | Harness `uifigure` | Teste isolado do avatar compartilhado, sem autenticação |
| [F5BrowserTestApp.m](F5BrowserTestApp.m) | App `uifigure` | Integração completa em uma aplicação |

Os testes de autenticação exigem um login real, com aprovação do push no Microsoft
Authenticator.

Não há como executá-los de forma desassistida.

O componente `profileAvatar.html` pertence ao módulo compartilhado em
[`src/Anatel/+ws/+auth`](../../src/Anatel/+ws/+auth/README.md) e pode ser reutilizado por
qualquer aplicação que use este pacote de autenticação. O harness não exige login.
Execute `checkProfileHtml` para alternar entre desconectado, conectado com inicial e
conectado com a foto PNG de teste, além de verificar o callback de clique emitido pelo
componente HTML.

## checkF5Auth.m

Script organizado em seções (`%%`), pensado para execução com **Ctrl+Enter**, uma de cada vez. O cabeçalho define `loginURL`, `targetURL` e `debugFile`, além de acrescentar `src/Anatel` ao path.

O path provido refere-se a exemplo simples que 

### Test1 — Login interativo

Cria a `F5Session` e chama `login`. A janela do navegador só aparece quando o fluxo é redirecionado ao Azure AD; conclua o login e aprove o push. Ao final, `debugInfo` imprime `IsAuthenticated`, a quantidade e os **nomes** dos cookies capturados — nunca os valores.

A URL de login deve terminar no host protegido com HTTP `200`; o corpo da landing page pode ser vazio. Esse retorno mantém o documento no domínio dos cookies do F5 para que a sessão possa ser capturada.

Esperado: `IsAuthenticated = 1` e `LastMRH_Session`, `F5_ST` (e normalmente `MRHSession`) entre os nomes.

### Test2 — Round-trip fora do navegador embarcado

Este é o teste que valida a premissa central do módulo: que o cookie obtido no navegador embarcado é **portável para o cliente HTTP do MATLAB**, ou seja, que o F5 não vincula a sessão a um *fingerprint* de navegador (User-Agent, IP, sessão TLS).

Faz um `read` em `targetURL` e verifica que a resposta é JSON. Se voltasse a página de login em vez do payload, a abordagem inteira seria inviável e exigiria replicar cabeçalhos do navegador.

Esperado: struct de perfil obtido do cabeçalho `X-User-Profile`, normalmente com campos como `NA_USER_EMAIL`, `NA_USER_NAME` e `NA_ROLE`.

### Test3 — Requisição sem cookie (controle negativo)

Serve a dois propósitos: confirmar que o endpoint é de fato protegido (sem isso, o sucesso
do Test2 poderia ser um falso positivo em uma rota aberta) e verificar que
`isSessionExpired` **reconhece** a resposta de sessão inválida.

Envia um GET sem cookie, com `MaxRedirects = 0`, e imprime status, `Location` e o veredito
do detector. Como o APM responde `302` para `/my.policy`, o diagnóstico vem do código de
status, sem depender da inspeção do HTML.

Esperado: `HTTP 302`, `Location: /my.policy`, `Detectado como sessão inválida: 1`.

### Cleanup

`delete(session)` descarta os cookies da memória.

> **Nota sobre expiração real:** os testes acima rodam com a sessão viva. Para observar o
> comportamento de expiração de verdade, deixe a aplicação ociosa além do tempo limite do
> APM e repita o Test2 — `read` deve disparar uma nova autenticação interativa.

---

## F5BrowserTestApp.m

Mini-navegador em `uifigure` que demonstra o uso do módulo dentro de uma aplicação: autentica uma vez e reaproveita a sessão para navegar por várias URLs do mesmo host, sempre pelo cliente HTTP do MATLAB.

```matlab
F5BrowserTestApp
```

### Interface

- **Combo box de URL** (editável), pré-populado com endpoints de teste. Navega tanto ao   pressionar Enter sobre uma URL digitada quanto ao selecionar um item. URLs novas são acrescentadas ao histórico mas não serão recuperadas entre sessões.
- **Imagem de debug**, ao lado do combo: controla a abertura das DevTools do navegador de autenticação e a gravação do estado bruto do navegador.
- **Avatar de downloads**, entre o debug e o avatar de perfil: mostra o progresso agregado da fila, uma bola por download ativo e a velocidade agregada. O clique abre ou traz para frente o painel de downloads.
- **Avatar de perfil**, à direita: desconectado, conectado com inicial ou conectado com foto circular. O clique conecta ou abre o menu de perfil, que contém a opção de desconectar.
- **Área de conteúdo** (`uihtml`), ocupando o restante da figura.

### Comportamento

`navigate` acrescenta a URL ao histórico. Downloads são encaminhados primeiro
ao painel e usam a mesma chamada para fontes públicas e protegidas; a sessão F5
só autentica quando o servidor protegido exigir isso. As demais URLs garantem a
sessão e fazem a leitura sob um `uiprogressdlg` indeterminado. Erros viram
`uialert`, sem derrubar a aplicação.

Os itens `https://httpbin.org/bytes/1024` e
`http://httpbin.org/bytes/1024` demonstram downloads públicos sem login. Os
itens do host `fiscalizacao.anatel.gov.br` demonstram o mesmo painel com
autenticação F5 sob demanda.

`ensureSession` só cria uma sessão nova quando não há login válido **ou** quando a URL
aponta para outro host — o cookie do APM é válido apenas para o host que o emitiu. Enquanto
o host for o mesmo, nenhuma nova autenticação ocorre.

O avatar é o componente `uihtml` compartilhado em
[`src/Anatel/+ws/+auth/profileAvatar.html`](../../src/Anatel/+ws/+auth/profileAvatar.html).
Os SVGs são embutidos no HTML; o MATLAB envia apenas o estado de conexão, a inicial e a
foto PNG em Base64. A foto de teste é carregada por uma função específica a partir de
`Profile-Picture.png`, sem criar arquivos temporários. O componente recorta a foto em um
círculo no próprio SVG e devolve eventos de clique ao MATLAB. Aplicações consumidoras
devem configurar `uihtml.HTMLSource` para o arquivo do módulo, em vez de manter uma cópia
local.

`render` decide como exibir a resposta: HTML é renderizado como HTML; respostas JSON (que
`matlab.net.http` já converte em struct) são exibidas como JSON formatado dentro de `<pre>`.

Endpoints sem extensão no último segmento (`debug/headers`, `server/runtime-health`) seguem
sendo renderizados normalmente.

### Duas decisões deliberadas

**Sanitização do conteúdo.** O markup recebido é despido de `<script>`, atributos `on*` e
URIs `javascript:` antes da exibição. O `uihtml` compartilha o contexto CEF do MATLAB, e
executar script arbitrário de página ali é um risco desnecessário para um harness de teste.
Efeito colateral: páginas dependentes de JavaScript — provavelmente incluindo a aplicação
real — aparecem apenas como markup estático. **Este app serve para verificar o reúso da
sessão, não para navegar na aplicação.**

**`<base href>` injetado.** Permite que CSS e imagens relativos resolvam, mas essas
subrequisições partem do cookie jar do `uihtml`, e não do cookie mantido pelo MATLAB —
algumas podem falhar. Não afeta o payload principal.

### Sobre a janela de autenticação

A janela é criada oculta e só é exibida quando o fluxo sai do host protegido. Se o CEF do
MATLAB ainda tiver uma sessão válida, o login se completa sem que nenhuma janela apareça.
Resta um *glitch* conhecido: por uma fração de segundo (até ~0,25 s, o intervalo do polling)
a página final pode ficar visível antes de a janela ser ocultada.


### TODO — recommended implementation order

The original migration item is no longer a simple “move everything” task. The
current ownership should be split into three boundaries: download UI under
`src/General/+ui`, generic download services under `src/General/+download`,
and F5 authentication/adaptation under `src/Anatel/+ws/+auth`. Finish the
cleanup and documentation of that boundary before adding more features.

**First extraction slice implemented:** `download.*` now owns the generic HTTP,
filename, metadata, and worker services; `download.DownloadManager` owns the
provider-neutral task lifecycle; `ui.DownloadPanel` renders manager snapshots
and forwards UI commands; `ws.auth.FileDownload` remains the F5 adapter. The
isolated manager harness is `tests/ui/checkDownloadManager.m`. The remaining
items below are intentionally not started until the panel and F5 harnesses are
functionally tested.

1. **Separate the download UI, generic download services, and F5 adapter.**

	This is a namespace migration as well as a file reorganization. The target
	structure is:

	```text
	src/General/
	├── +ui/
	│   ├── DownloadPanel.m
	│   └── html/
	│       ├── downloadAvatar.html
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

	- Keep `DownloadPanel` in `+ui` as the presentation layer. It owns the
	  visual panel, row controls, avatar state, and UI callbacks, but it must not
	  own the transfer lifecycle or call downloader methods directly. Keep the
	  download avatar HTML beside that component.
	- Add `download.DownloadManager` to `+download`. It owns the logical task
	  lifecycle: task registration, state transitions, task identifiers,
	  `start`, `pause`, `resume`, and `cancel` commands, downloader
	  callbacks, late-callback filtering, cleanup, and notifications/snapshots
	  consumed by the panel. It must not depend on `uifigure`, `uihtml`, or
	  other presentation classes.
	- The panel must translate user actions into manager commands and render the
	  manager's task snapshots. A task state must have one authoritative owner:
	  the manager owns transfer state, while the panel owns only UI handles and
	  presentation state. Conflict decisions and history updates must follow
	  this same boundary.
	- Define the manager contract before extracting the current implementation.
	  A normalized `DownloadRequest` must contain the URL, temporary folder,
	  target folder, file name, final path, display mode, and applicable conflict
	  policies. A `TaskSnapshot` must expose the task ID, lifecycle state, paths,
	  received and total bytes, measured and estimated rates, timestamps, and
	  error information without exposing UI handles or downloader internals.
	- Use one authoritative lifecycle vocabulary. `pause` stops transfer while
	  preserving a resumable task, `cancel` stops transfer, removes temporary
	  files, and removes the task from the panel, and `restart` discards the
	  partial state before starting again.
	  Target conflicts use `overwrite`, `uniqueName`, and `cancel` (the
	  user-facing label for `uniqueName` is "Save as new"); partial-file
	  conflicts use `resume`, `restart`, and `cancel`.
	- Keep destination selection separate from transfer orchestration. A panel
	  or injected destination resolver may use `executionMode` and `uiputfile`
	  to produce a normalized request, but `DownloadManager` must not call UI
	  APIs or know about desktop/Web App Server modes. The manager owns conflict
	  detection and emits a pending decision for the panel to render.
	- Move the generic filename, HTTP, metadata, and worker functions to the
	  sibling MATLAB package `+download`. These functions must remain independent
	  of `uifigure`, `DownloadPanel`, `F5Session`, cookies, and other provider
	  details. Their existing `requestContext` and normalized request arguments
	  are the boundary that permits both public HTTP and authenticated adapters.
	- Keep `F5Session`, `FileDownload`, and F5-specific progress/authentication
	  behavior in `+ws/+auth`. `FileDownload` adapts an F5 session to the generic
	  `download` service; it is not part of the UI package.
	- Treat the current `src/Anatel/+ws/+auth/downloadFileWorker.m` as a
	  compatibility wrapper during the migration only. It must delegate to
	  `download.downloadFileWorker` if any external caller still needs it; after
	  all references are migrated, remove the wrapper or document it as a
	  deliberately supported compatibility entry point. There must be only one
	  worker implementation.

	### Required namespace changes

	Moving a file from `+ui` to the sibling package `+download` changes its
	qualified MATLAB name. Update every call from `ui.*` to `download.*`, including
	:

	- `DownloadPanel.m`: `download.downloadFileName`;
	- `FileDownload.m`: `download.downloadSourceMetadata` and
	  `@download.downloadFileWorker` passed to `parfeval`;
	- `downloadFileWorker.m` and `downloadSourceMetadata.m`: all calls to the
	  HTTP, filename, and content-disposition helpers;
	- `tests/ui/checkDownloadHttp.m` and any future tests;
	- README examples, error documentation, build scripts, and generated
	  dependency lists.

	Update error identifiers at the same time. Generic errors should use the
	`download:*` namespace, for example `download:downloadFileWorker:httpError`,
	while F5 adapter errors continue to use `ws:auth:*` and panel/UI errors use
	`ui:DownloadPanel:*`. Do not leave identifiers referring to the old package
	unless a compatibility policy explicitly requires them.

	### Migration and compatibility policy

	Before editing callers, decide whether `ui.download*` was part of the
	public package API or only an internal implementation detail. The repository
	currently contains direct test calls, but no evidence in this README of an
	external consumer. The recommended default is an intentional namespace
	migration: update all repository callers to `download.*` and do not maintain
	permanent duplicate wrappers. If backward compatibility with released
	consumers is required, retain thin deprecated wrappers in `+ui` that forward
	to `download.*`; never copy or fork the implementation, and define when the
	wrappers may be removed.

	The contract to record later in `contract.md` should state that:

	- `download.*` owns provider-neutral HTTP transfer, response handling,
	  source metadata, filename derivation, and task-scoped file publication;
	- `download.DownloadManager` owns provider-neutral transfer orchestration,
	  task state, conflict decisions, history coordination, normalized request
	  handling, and downloader lifecycle commands. It exposes snapshots/events,
	  not UI handles;
	- `ui.DownloadPanel` owns presentation and UI lifecycle only. It translates
	  user actions into manager commands, renders manager snapshots, and does
	  not perform authentication, inspect cookies, or call downloader methods
	  directly;
	- `ws.auth.FileDownload` owns F5 session interaction and supplies the
	  provider-specific `requestContext` to `download.*`; the manager receives
	  it only through the injected downloader factory;
	- no package may call into the concrete implementation of another provider;
	- the normalized request and `requestContext` are the only transfer boundary
	  between the generic service and an authentication adapter.

	### Path, compilation, and validation requirements

	- Keep `src/General` on the MATLAB path so both `ui.*` and `download.*`
	  resolve as sibling packages. Do not add the package folders themselves to
	  the path.
	- Update `parfeval` function handles and any dynamic `which`/`mfilename`
	  lookup to use the new package names. Verify that the worker can be found
	  from the background pool, not only from the interactive MATLAB client.
	- Update Application Compiler instructions and additional-file lists for the
	  new package layout. The `download` source files are code dependencies;
	  `downloadAvatar.html` and `downloadStatus.html` remain additional UI
	  assets. Keep
	  `profileAvatar.html` under `+ws/+auth` because it belongs to the F5 profile
	  component, not the download package.
	- Update `src/Anatel/+ws/+auth/README.md`, `tests/ui/README.md`, and this
	  README before deleting the old files. Remove the obsolete duplicate
	  download avatar only after a repository-wide reference search is empty.
	- Use `tests/ui/checkDownloadHttp.m` to validate the generic package without
	  authentication, then use `checkDownloadPanel.m` to validate the UI/factory
	  boundary. Real F5 authentication in `F5BrowserTestApp.m` is a later
	  integration check, not a prerequisite for this migration.
	- The migration is complete only when no generic download implementation
	  remains under the `+ui` location, `DownloadPanel` delegates transfer
	  lifecycle operations to `download.DownloadManager`, the manager contract
	  and lifecycle semantics are covered by isolated tests, all repository
	  references resolve to the new package names, and the compiled-application
	  asset instructions are consistent with the new ownership model.

2. **Resolve execution mode and destination before creating a task.**
	 - Add a `uiimage` control to `F5BrowserTestApp` for switching between
		 desktop behavior and Web App Server behavior in the test app.
	 - Keep `executionMode` and initial destination selection in the application,
		 `DownloadPanel`, or an injected `DestinationResolver`. `webApp` must not
		 open desktop file-selection dialogs; desktop-like modes may use `uiputfile`.
	 - Pass the manager a normalized request after destination resolution. The
		 request must contain the final target folder and file name; the manager
		 must not call `uiputfile`, `uiconfirm`, `questdlg`, or any other UI API.
	 - Configure collision behavior on `DownloadManager`, not through a
		 test-specific branch in the panel. The manager detects the collision and
		 emits a pending decision; the panel renders the controls and calls the
		 manager's decision method. Target conflicts use `overwrite`, `uniqueName`,
		 and `cancel` (shown as **Save as new**). Partial conflicts use `resume`,
		 `restart`, and `cancel`.
	 - Add manager tests for each mode-independent conflict transition and
		 panel tests for desktop/Web App Server destination resolution before
		 changing the visual layout.

3. **Add an explicit silent mode.**
	 - Add `DisplayMode = 'normal' | 'silent'` to the normalized request or task
		 options. The manager owns this value; the panel does not infer it from a
		 URL or caller-specific branch.
	 - A silent task must not create a visible row or contribute to the avatar by
		 default, but it must retain the normal manager lifecycle, callbacks,
		 cleanup, and history behavior. The inclusion policy must be configurable
		 without changing the downloader contract.
	 - Add manager and panel harness cases proving that silent tasks still emit
		 completion and error notifications and do not affect visible progress.

4. **Change the download avatar contract from aggregate count/speed to a
	 per-download speed list.**
	 - `TaskSnapshot` must expose both `MeasuredRate` and `EstimatedRate`, in
		 bytes per second, plus a `RateSource` value. The panel maps the snapshots
		 of represented tasks to the avatar's speed list.
	 - Send one speed value per represented download; the number of orbiting
		 circles must equal the list length. Preserve a stable ordering, preferably
		 task creation order, and exclude silent tasks by default.
	 - A paused, pending-conflict, or otherwise represented task with
		 no current rate sends zero and produces a stationary red circle. Positive
		 measured or explicitly permitted estimated rates retain active animation.
	 - Update `DownloadPanel`, `downloadAvatar.html`, and `checkDownloadHtml`
		 together. Document the units, ordering, empty-list behavior, and the
		 distinction between estimated and measured rates.

5. **Make the empty panel a first-class state.**
	 - Clicking the avatar must open or bring the panel to the front even when
		 there are no downloads.
	 - In that state, show only the configured title bar, the `Download` label,
		 and the close control aligned with the panel's top-right corner.
	 - Add a harness case for opening, closing, and reopening the empty panel.

6. **Replace the progress bar with a reusable animated `uihtml` status
	 component.**
	 - Implement the component as `src/General/+ui/html/downloadStatus.html`
		 and include it in compiled applications together with the avatar asset.
	 - Define explicit states for active download (constant blue), warning
		 (blinking yellow), and error (blinking red), with precedence
		 `error > warning > active > idle`.
	 - Map manager snapshots to these visual states in the panel. The manager
		 must retain enough failed or warning state for the component to display it
		 before the row is removed or archived.
	 - Keep the component independent of authentication and make its MATLAB to
		 HTML data contract testable from `tests/ui`.
	 - Verify desktop MATLAB and Web App Server rendering before integrating it
		 into every row.

7. **Define and implement persistent download history.**
	 - History belongs to `DownloadManager` or to an injected provider-neutral
		 history store, never to `DownloadPanel` or a downloader adapter. The
		 manager must receive the history-file location or store explicitly and
		 load it at startup.
	 - Use one JSON entry per download attempt. Link retries and restarts for the
		 same logical file with a stable `LogicalFileID`; keep the active entry
		 associated with the manager task by `TaskID`.
	 - Define one stable schema containing at least: entry and logical-file IDs,
		 source URL, full target path, temporary path, start timestamp,
		 completion timestamp, lifecycle state, downloaded byte count, measured
		 speed, rate source, error messages, and `isAvailable`. Use ISO 8601 UTC
		 timestamps.
	 - Persist changes when a download starts, pauses, resumes, completes,
		 fails, or is canceled. A history write must reflect the authoritative
		 manager transition, not a UI callback.
	 - At startup, reconcile history with target and temporary files. Update
		 availability, refresh byte counts from matching temporary files, and move
		 unreferenced task-scoped temporary files to the OS trash through a
		 platform-neutral filesystem helper.
	 - Make reconciliation and JSON writes tolerant of a missing or corrupt
		 history file. Use an atomic replacement or equivalent strategy so a
		 concurrent interruption cannot leave a partially written history file.
	 - Keep history fields in manager snapshots so the panel can render completed
		 entries without owning the JSON representation.

8. **Redesign the download rows around the finalized state model.**
	 - Render manager snapshots, not private downloader objects. Active or
	  paused downloads use a 3-row by 4-column layout: filename; progress plus
	  pause/resume and cancel controls; then byte count, speed, estimated
		 remaining time, or status text.
	 - Target conflicts show `Overwrite`, `Save as new`, and `Cancel`. Partial
		 downloads show `Resume`, `Restart`, and `Cancel`, and retain the known
		 byte count. The panel sends these choices to `DownloadManager`.
	 - Completed history entries use a 2-row by 3-column layout with filename,
		 restart/delete-history actions, timestamp, and file size. Missing target
		 files use red struck-through text. Deleting history removes the history
		 entry but does not delete the target file unless a separate file-delete
		 command is selected.
	 - Remove separator lines, use a slightly darker background per download,
		 and add a clear gap between rows. Keep the close control at the panel's
		 top-right corner.
	 - Add manager tests for every lifecycle transition and visual harness
		  coverage for every row state, including canceled downloads and unavailable
		 completed files.

9. **Use historical speeds in the examples.**
	 - Before a new transfer has enough samples, the manager may obtain an
		 estimated rate from history using the closest available key: exact URL,
		 host and filename, then a global default.
	 - Expose the estimate separately from measured transfer rate. Once real
		 progress samples exist, measured rate takes precedence and the estimate
		 must not be presented as measured data.
	 - Demonstrate the behavior in `tests/ui` with deterministic history before
		 relying on live F5 transfers. The avatar consumes the same stable speed
		 list contract regardless of whether a value is measured or estimated.

### Decisions to confirm before implementation

- Should `DestinationResolver` be a callback supplied to `DownloadPanel` or a
	separate reusable class? In either case, it must return a normalized request
	without making `DownloadManager` depend on UI APIs.
- Should a silent task be excluded from the avatar as specified above, or
	should callers be allowed to opt it into aggregate visual state?
- Should cancel always delete partial files, or should a deployment be able
	to retain them for later recovery? The manager must expose one explicit
	policy rather than infer behavior from the button label.
- Is backward compatibility with released consumers of `ui.download*`
	required? If so, retain deprecated forwarding wrappers with a documented
	removal point; otherwise perform the namespace migration without wrappers.