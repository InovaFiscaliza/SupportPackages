# tests/auth

Exemplos e validação de [`ws.auth.F5Session`](../../src/Anatel/+ws/+auth/README.md), o módulo de autenticação SAML 2.0 + MFA através do proxy reverso F5 BIG-IP APM.

| Arquivo | Tipo | Finalidade |
|---|---|---|
| [checkF5Auth.m](checkF5Auth.m) | Script por seções | Validação passo a passo do fluxo |
| [`profileAvatar.html`](../../src/Anatel/+ws/+auth/profileAvatar.html) | Componente `uihtml` compartilhado | Avatar reutilizável para o estado de autenticação |
| [checkProfileHtml.m](checkProfileHtml.m) | Harness `uifigure` | Teste isolado do avatar compartilhado, sem autenticação |
| [`downloadAvatar.html`](../../src/Anatel/+ws/+auth/downloadAvatar.html) | Componente `uihtml` compartilhado | Indicador reutilizável de progresso e downloads ativos |
| [checkDownloadHtml.m](checkDownloadHtml.m) | Harness `uifigure` | Teste isolado do indicador de downloads, sem autenticação |
| [F5BrowserTestApp.m](F5BrowserTestApp.m) | App `uifigure` | Integração completa em uma aplicação |

Os testes de autenticação exigem um login real, com aprovação do push no Microsoft
Authenticator. Os harnesses isolados do avatar e do indicador de downloads não
exigem autenticação.

Não há como executá-los de forma desassistida.

O componente `profileAvatar.html` pertence ao módulo compartilhado em
[`src/Anatel/+ws/+auth`](../../src/Anatel/+ws/+auth/README.md) e pode ser reutilizado por
qualquer aplicação que use este pacote de autenticação. O harness não exige login.
Execute `checkProfileHtml` para alternar entre desconectado, conectado com inicial e
conectado com a foto PNG de teste, além de verificar o callback de clique emitido pelo
componente HTML.

Execute `checkDownloadHtml` para testar o componente
[`downloadAvatar.html`](../../src/Anatel/+ws/+auth/downloadAvatar.html) sem iniciar
downloads reais. O harness apresenta o slider de progresso e o controle `uihtml` em
duas colunas, além de controles para reproduzir a atividade da fila:

- **Progresso** — slider de `0%` a `100%`, com marcações a cada `10%`, ajustado ao
	inteiro mais próximo. O valor `0%` representa a fila ociosa; os valores são
	convertidos para os dez níveis visuais do indicador.
- **Estado do download** — botão independente para ligar ou desligar a animação das
	bolas, sem alterar o percentual.
- **Quantidade de bolas** — slider inteiro de `1` a `10`, representando a quantidade
	de downloads ativos na órbita.
- **Velocidade** — slider contínuo em radianos por segundo, para simular a velocidade
	agregada dos downloads.
- **Clique** — pressionar o indicador dispara o evento de abertura da janela de
	downloads e acende temporariamente o indicador de teste.

O harness também envia o estado `level`, `inProgress`, `ballCount` e
`speedRadiansPerSecond` ao componente e trata os eventos `downloadAvatarReady` e
`downloadAvatarClick`.

```matlab
checkDownloadHtml
```

---

## checkDownloadHtml.m

Harness visual para validar o estado do indicador sem autenticação ou transferência
de arquivos. O controle de progresso é convertido para níveis de `0` a `10`, enquanto
o número de bolas e a velocidade da órbita são atualizados independentemente. O botão
de estado permite verificar que a animação pode ser ligada ou desligada sem alterar o
progresso exibido.

O botão do indicador representa a abertura do painel de downloads. O callback
recebe os eventos emitidos pelo HTML e pisca o indicador inferior em verde, permitindo
verificar visualmente que o clique chegou ao MATLAB.

---

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

`navigate` acrescenta a URL ao histórico, garante a sessão e faz a leitura sob um
`uiprogressdlg` indeterminado. Erros viram `uialert`, sem derrubar a aplicação.

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

### Download de arquivos

Quando o último segmento do caminho da URL contém extensão — por exemplo
`.../p-a2d86905--rfeye002126_260902_T161700.bin` — o conteúdo é gravado diretamente em disco,
em vez de ser renderizado. Nesta aplicação de teste, o destino padrão do servidor é a
própria pasta `tests/auth`, e o nome sugerido é derivado da URL, com separadores e
caracteres inválidos sanitizados. A aplicação passa esse caminho explicitamente para o
download. Se `downloadFile` for chamado sem um caminho de destino, o fluxo mantém um
`uiputfile` como fallback para que o usuário escolha o arquivo e a pasta.

A implementação atual usa `ws.auth.FileDownload`, que executa as requisições por blocos em
`backgroundPool`. A interface permanece livre para outras requisições durante o download, e um
arquivo parcial pode ser retomado a partir do ponto em que foi interrompido. Downloads diferentes
podem permanecer ativos ao mesmo tempo dentro de um painel de downloads compartilhado, em seções
empilhadas que redimensionam o conteúdo conforme novas tarefas são adicionadas ou concluídas.

O painel aparece abaixo do avatar de downloads e cresce conforme o número de seções. Quando a
altura necessária excede o espaço disponível, somente a rolagem vertical é habilitada; a largura
do conteúdo recebe uma margem de segurança para evitar uma rolagem horizontal causada pela barra
vertical. Clicar fora do painel o oculta; clicar no avatar o reabre.

O progresso é exibido na barra a partir do tamanho total informado pelo servidor. O contador mostra
os bytes recebidos e o total; quando o total não é conhecido, mostra apenas os bytes recebidos.
Além disso, o app salva um arquivo de log ao lado do download (`<arquivo>.log`) com URL,
destino, identificação resumida da sessão e bytes recebidos. Em caso de falha, o log inclui a
exceção e o stack; código HTTP e `Content-Length` não são registrados atualmente.

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


### TODO

- Chunked writer: Current downloadFileWorker.m appends chunks repeatedly to the selected destination. This is unsuitable for web apps because repeated writes can trigger multiple browser downloads. Download chunks to a server-side temporary file, then perform one final copy/write to the uiputfile path.
- Change download avatar to use a list of speeds as entry points instead of number of circles and speed. Number of circles should be equal to the length of the list. Speed may be zero for some entries resulting in stationary circles.