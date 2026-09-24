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
- **Imagem de debug** (<img src="debug-alt.svg" alt="ícone de debug" width="16" height="16"> / <img src="debug-alt-active.svg" alt="ícone de debug" width="16" height="16">), ao lado do combo: controla a abertura das DevTools do navegador de autenticação e a gravação do estado bruto do navegador em arquivo de log. O ícone muda de cor quando o modo de debug está ativo.
- **Modo de execução** (![ícone desktop](vm.svg) / ![ícone Web App Server](globe.svg)), ao lado do debug: indica o comportamento desktop ou Web App Server. O clique alterna o modo usado pelos próximos downloads e permite testar a compatibilidade com os dois modos de execução dos aplicativos.
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
`http://httpbin.org/bytes/1024` exercitam downloads públicos sem login. Os itens
do host `fiscalizacao.anatel.gov.br` exercitam o mesmo fluxo com autenticação F5
sob demanda. `ensureSession` reutiliza a sessão enquanto o host permanece o
mesmo e cria uma nova sessão quando a URL aponta para outro host.

No modo desktop, o painel abre `uiputfile` antes de criar a tarefa. No modo Web
App Server, usa diretamente a pasta de destino configurada na aplicação e não
abre diálogos desktop. Depois dessa resolução, ambos os modos enviam a mesma
solicitação normalizada ao `DownloadManager`; conflitos são apresentados na
linha do painel, que é aberto automaticamente quando a intervenção do usuário
é necessária, e resolvidos pelo manager.

No modo desktop deste app, um conflito com o target escolhido no `uiputfile` é
resolvido automaticamente com **Overwrite**, pois a escolha do destino já foi
confirmada pelo usuário. Se o usuário informar outro nome, esse nome passa a
ser o target final e o conflito com o nome original deixa de existir. Quando o
nome informado não contém extensão, o painel acrescenta a extensão do arquivo
indicado pela URL, quando disponível.

O avatar de perfil usa o componente compartilhado
[`profileAvatar.html`](../../src/Anatel/+ws/+auth/profileAvatar.html). O harness
de perfil verifica os estados desconectado, inicial e foto PNG; o app de teste
verifica também o clique que abre o menu de perfil e a opção de desconectar.

`render` exibe respostas HTML no `uihtml` e respostas JSON formatadas em `<pre>`.
Endpoints sem extensão no último segmento, como `debug/headers` e
`server/runtime-health`, também são aceitos pelo teste.

O conteúdo HTML recebido é sanitizado antes da exibição: scripts, atributos
`on*` e URIs `javascript:` são removidos. Isso torna o harness adequado para
validar respostas sem executar código remoto, mas páginas que dependem de
JavaScript aparecem apenas como markup estático. Um `<base href>` é injetado
para permitir que CSS e imagens relativos sejam resolvidos; essas
subrequisições usam o cookie jar do `uihtml`, não os cookies mantidos pelo
MATLAB.

A janela de autenticação é criada oculta e exibida apenas quando a navegação
sai do host protegido ou demora além do limite de espera. Com uma sessão CEF
válida, o login pode terminar sem uma janela visível.

### TODO — remaining implementation order

Os itens abaixo tratam da evolução dos testes e das funcionalidades de download;
os detalhes arquiteturais do item 1 estão documentados em
[`src/General/+download/README.md`](../../src/General/+download/README.md).

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
- Should cancel always delete partial files, or should a deployment be able
	to retain them for later recovery? The manager must expose one explicit
	policy rather than infer behavior from the button label.
- Is backward compatibility with released consumers of `ui.download*`
	required? If so, retain deprecated forwarding wrappers with a documented
	removal point; otherwise perform the namespace migration without wrappers.