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
- **Imagem de debug** (<img src="debug-start.svg" alt="ícone de debug" width="16" height="16"> / <img src="debug-stop.svg" alt="ícone de debug" width="16" height="16">), ao lado do combo: controla a abertura das DevTools do navegador de autenticação e a gravação do estado bruto do navegador em arquivo de log. O ícone muda de cor quando o modo de debug está ativo.
- **Modo de execução** (![ícone desktop](vm.svg) / ![ícone Web App Server](globe.svg)), ao lado do debug: indica o comportamento desktop ou Web App Server. O clique alterna o modo usado pelos próximos downloads e permite testar a compatibilidade com os dois modos de execução dos aplicativos.
- **Avatar de downloads**, entre o modo silencioso e o avatar de perfil: mostra indicadores individuais de progresso e atividade dos downloads visíveis. O clique abre ou traz para frente o painel de downloads.
- **Avatar de perfil**, à direita: desconectado, conectado com inicial ou conectado com foto circular. O clique conecta ou abre o menu de perfil, que contém a opção de desconectar.
- **Área de conteúdo** (`uihtml`), ocupando o restante da figura.

### Comportamento

`navigate` acrescenta a URL ao histórico. Downloads são encaminhados primeiro
ao painel e usam a mesma chamada para fontes públicas e protegidas; a sessão F5
só autentica quando o servidor protegido exigir isso. O contrato atual de
`ws.auth.FileTransfer` aceita somente `Direction = 'download'`; o transporte de
upload ainda não está implementado. As demais URLs garantem a
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
solicitação normalizada ao `datatransfer.TransferManager`; conflitos são apresentados na
linha do painel, que é aberto automaticamente quando a intervenção do usuário
é necessária, e resolvidos pelo manager.

No modo desktop deste app, um conflito com o target escolhido no `uiputfile` é
apresentado na linha do painel, com as opções de manter o arquivo existente,
reiniciar o download ou cancelar. O `uiputfile` ainda permite escolher outro
nome no modo desktop; no Web App Server, o nome deriva da URL e não pode ser
renomeado. O reinício explícito substitui o arquivo existente.

Solicitações não terminais com a mesma URL e o mesmo nome de arquivo selecionado
são deduplicadas, independentemente da pasta de destino ou do modo normal/silencioso.
Repetir uma solicitação normal para uma tarefa silenciosa torna a tarefa visível,
promove sua linha e abre o painel. A repetição não cria uma nova tentativa; pausar
e retomar também não acrescenta um timestamp de tentativa.

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

### TODO — ordem restante de implementação

Os itens abaixo tratam da evolução dos testes e das funcionalidades de download;
os detalhes arquiteturais do item 1 estão documentados em
[`src/General/+datatransfer/README.md`](../../src/General/+datatransfer/README.md).

O histórico persistente foi implementado no manager; o schema e a recuperação
estão documentados no README do módulo de downloads.

O redesenho do painel, incluindo os estados de conflito, o histórico concluído e
as ações por ícone, foi implementado em `ui.TransferPanel` e está descrito no
README de `tests/transfers`.

1. **Tornar o painel vazio um estado de primeira classe.**
	 - Clicar no avatar deve abrir o painel ou trazê-lo para frente, mesmo quando
		 não houver downloads.
	 - Nesse estado, mostrar apenas a barra de título configurada, o rótulo
		 `Download` e o controle de fechar alinhado ao canto superior direito do painel.
	 - Adicionar um caso de teste para abrir, fechar e reabrir o painel vazio.

2. **Substituir a barra de progresso por um componente de status `uihtml`
	 reutilizável e animado.**
	 - Proposta futura: implementar o componente em
		 `src/General/+ui/html/downloadStatus.html` e incluí-lo em aplicações
		 compiladas junto com o recurso do avatar. Esse arquivo ainda não existe nem
		 é um recurso de empacotamento atual.
	 - Definir estados explícitos para download ativo (azul constante), aviso
		 (amarelo piscante) e erro (vermelho piscante), com a precedência
		 `error > warning > active > idle`.
	 - Mapear os snapshots do manager para esses estados visuais no painel. O manager
		 deve reter estado de falha ou aviso suficiente para o componente exibi-lo
		 antes que a linha seja removida ou arquivada.
	 - Manter o componente independente da autenticação e permitir que seu contrato
		 de dados do MATLAB para o HTML seja testado em `tests/transfers`.
	 - Verificar a renderização no MATLAB desktop e no Web App Server antes de
		 integrá-lo a todas as linhas.

3. **Usar velocidades históricas nos exemplos.**
	 - Antes que uma nova transferência tenha amostras suficientes, o manager pode
		 obter uma taxa estimada do histórico usando a chave disponível mais próxima:
		 URL exata, host e nome do arquivo, depois um valor global padrão.
	 - Expor a estimativa separadamente da taxa de transferência medida. Quando
		 houver amostras reais de progresso, a taxa medida terá precedência e a
		 estimativa não deverá ser apresentada como dado medido.
	 - Demonstrar o comportamento em `tests/transfers` com um histórico determinístico
		 antes de depender de transferências F5 reais. O avatar consome o mesmo
		 contrato estável de lista de velocidades, independentemente de o valor ser
		 medido ou estimado.
