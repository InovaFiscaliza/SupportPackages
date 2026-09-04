# tests/auth

Exemplos e validação de [`ws.auth.F5Session`](../../src/Anatel/+ws/+auth/README.md), o módulo de autenticação SAML 2.0 + MFA através do proxy reverso F5 BIG-IP APM.

| Arquivo | Tipo | Finalidade |
|---|---|---|
| [checkF5Auth.m](checkF5Auth.m) | Script por seções | Validação passo a passo do fluxo |
| [F5BrowserTestApp.m](F5BrowserTestApp.m) | App `uifigure` | Integração completa em uma aplicação |

Ambos exigem um login real, com aprovação do push no Microsoft Authenticator.

Não há como executá-los de forma desassistida.

---

## checkF5Auth.m

Script organizado em seções (`%%`), pensado para execução com **Ctrl+Enter**, uma de cada vez. O cabeçalho define `targetURL` e acrescenta `src/Anatel` ao path.

O path provido refere-se a exemplo simples que 

### Test1 — Login interativo

Cria a `F5Session` e chama `login`. A janela do navegador só aparece quando o fluxo é redirecionado ao Azure AD; conclua o login e aprove o push. Ao final, `debugInfo` imprime `IsAuthenticated`, a quantidade e os **nomes** dos cookies capturados — nunca os valores.

Esperado: `IsAuthenticated = 1` e `LastMRH_Session`, `F5_ST` (e normalmente `MRHSession`) entre os nomes.

### Test2 — Round-trip fora do navegador embarcado

Este é o teste que valida a premissa central do módulo: que o cookie obtido no navegador embarcado é **portável para o cliente HTTP do MATLAB**, ou seja, que o F5 não vincula a sessão a um *fingerprint* de navegador (User-Agent, IP, sessão TLS).

Faz um `read` no mesmo endpoint e verifica que a resposta é JSON. Se voltasse a página de login em vez do payload, a abordagem inteira seria inviável e exigiria replicar cabeçalhos do navegador.

Esperado: struct com os campos `X_User_*` que o APM injeta.

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
- **Rótulo de status**, à direita: `Conectado` / `Desconectado`.
- **Área de conteúdo** (`uihtml`), ocupando o restante da figura.

### Comportamento

`navigate` acrescenta a URL ao histórico, garante a sessão e faz a leitura sob um
`uiprogressdlg` indeterminado. Erros viram `uialert`, sem derrubar a aplicação.

`ensureSession` só cria uma sessão nova quando não há login válido **ou** quando a URL
aponta para outro host — o cookie do APM é válido apenas para o host que o emitiu. Enquanto
o host for o mesmo, nenhuma nova autenticação ocorre.

`render` decide como exibir a resposta: HTML é renderizado como HTML; respostas JSON (que
`matlab.net.http` já converte em struct) são exibidas como JSON formatado dentro de `<pre>`.

### Download de arquivos

Quando o último segmento do caminho da URL contém extensão — por exemplo
`.../p-a2d86905--rfeye002126_260902_T161700.bin` — o conteúdo é gravado diretamente em disco,
em vez de ser renderizado. Abre-se um `uiputfile` já posicionado na pasta `Downloads` do
usuário e com o nome sugerido pela própria URL (sanitizado contra separadores e caracteres
inválidos).

A implementação atual usa `ws.auth.F5Session.downloadToFile`, que mantém a sessão autenticada,
abre a resposta HTTP com o cookie do F5 e grava o payload em blocos em um arquivo local. Isso
permite baixar arquivos grandes sem materializar o conteúdo inteiro em memória no MATLAB.

O progresso é exibido na barra a partir do `Content-Length` da resposta. Quando o total não é
conhecido, a barra fica indeterminada e informa apenas quantos MB foram recebidos até o momento.
Além disso, o app salva um arquivo de log ao lado do download (`<arquivo>.log`) com URL,
identificação da sessão, código HTTP, `Content-Length`, bytes recebidos e stack de erro quando
houver falha.

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
