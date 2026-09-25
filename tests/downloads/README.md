# tests/ui

Esta pasta contém o harness manual de UI e o dublê de teste de
`src/General/+ui/DownloadPanel` e `src/General/+download/DownloadManager`.

Ela também contém harnesses visuais isolados para os avatares. O antigo
`downloadAvatar.html` permanece legado, exercitado apenas pelo seu harness; o
painel e novas integrações usam `pingDownloadAvatar.html`. Os harnesses de
avatar e de painel são deliberadamente separados: os primeiros verificam os
protocolos de apresentação HTML, enquanto o painel verifica a UI MATLAB, a
fábrica de downloaders, o ciclo de vida das tarefas e o comportamento do sistema
de arquivos.

## Arquivos

| Arquivo | Função |
|---|---|
| [`checkDownloadPanel.m`](checkDownloadPanel.m) | Abre um harness manual em `uifigure` para o painel reutilizável. |
| [`checkDownloadPanelDestination.m`](checkDownloadPanelDestination.m) | Verifica automaticamente a resolução de destino nos modos desktop e Web App. |
| [`checkDownloadManager.m`](checkDownloadManager.m) | Verifica o ciclo de vida e conflitos do manager sem UI. |
| [`checkDownloadSilent.m`](checkDownloadSilent.m) | Verifica tarefas silenciosas, callbacks e inclusão opcional na apresentação. |
| [`checkDownloadHtml.m`](checkDownloadHtml.m) | Harness legado de `downloadAvatar.html`. |
| [`checkPingDownloadHtml.m`](checkPingDownloadHtml.m) | Testa o recurso `uihtml` `pingDownloadAvatar.html` com IDs, taxas e progresso por download. |
| [`checkDownloadPanelPausedAvatarRate.m`](checkDownloadPanelPausedAvatarRate.m) | Confirma que downloads pausados chegam ao avatar com taxa zero. |
| [`checkDownloadHttp.m`](checkDownloadHttp.m) | Faz um teste rápido do transporte HTTP público, do fallback de nome de arquivo e do isolamento de cookies por host exato. |
| [`DownloadPanelFakeDownloader.m`](DownloadPanelFakeDownloader.m) | Simula o objeto downloader exigido por `ui.DownloadPanel`. |
| [`DownloadManagerFakeDownloader.m`](DownloadManagerFakeDownloader.m) | Simula um downloader síncrono para o contrato do manager. |

Esses arquivos têm responsabilidades diferentes. `checkDownloadPanel` é o
harness de teste interativo propriamente dito. `DownloadPanelFakeDownloader` é
sua dependência injetada: ele fornece progresso determinístico orientado por
timer e comportamento do sistema de arquivos sem tráfego de rede, autenticação
F5 ou `backgroundPool`.

`checkDownloadHtml` é um harness legado, intencionalmente separado do painel.
Ele testa apenas o protocolo antigo de apresentação de `downloadAvatar.html`:
níveis de progresso, estado ativo, quantidade de esferas em órbita, velocidade
da órbita, evento de pronto e evento de clique. Não é usado pelo painel atual e
permanece apenas para testar o asset legado.

## Harnesses isolados de avatar

`checkDownloadHtml.m` cria uma pequena `uifigure` contendo o componente `uihtml`
legado `downloadAvatar.html` e controles para seu estado visual:

- Progresso de `0%` a `100%`, convertido nos níveis de avatar de `0` a `10`.
- Estado de animação ativo/inativo.
- Quantidade de esferas em órbita de `1` a `10`.
- Velocidade da órbita em radianos por segundo.
- Um indicador de clique que confirma que `downloadAvatarClick` chegou ao MATLAB.

Este harness é exclusivamente de apresentação. Ele não cria arquivos
temporários ou de destino, não inicia `ui.DownloadPanel`, não autentica nem
realiza transferências de rede.

`checkPingDownloadHtml.m` exercita o novo avatar por meio de structs MATLAB com
os campos `id`, `rate` e `progress`. O harness envia struct vazio, escalar ou
array conforme a quantidade selecionada, com IDs numéricos, taxa em bytes por
segundo e progresso entre `0` e `100`. Os controles permitem variar até 23
downloads, o progresso e a taxa, além de confirmar o evento de clique e erros
de validação recebidos pelo MATLAB.

`checkDownloadPanelPausedAvatarRate.m` cria um download simulado, pausa a tarefa
no manager e verifica que `ui.DownloadPanel` mantém seu ID no avatar e envia
`rate = 0`, apesar de o snapshot pausado conter `TransferRate = NaN`.

## Integração com DownloadPanel

`checkDownloadPanel.m` exercita `ui.DownloadPanel` com
`DownloadPanelFakeDownloader`. Ele fornece quatro links de exemplo com tamanhos
e velocidades diferentes, progresso das tarefas, comportamento de
pausar/retomar/cancelar, escolhas para conflitos de destino e de arquivos parciais
e os controles de fechar/lixeira. O painel usa internamente o recurso
`pingDownloadAvatar.html`, que apresenta cada download ativo visível com ID,
taxa de transferência e progresso individuais. Downloads silenciosos continuam
fora do avatar, como no comportamento anterior.

`checkDownloadManager.m` exercita o manager sem criar `uifigure`: confirma
snapshots, conclusão, remoção de tarefas e todas as decisões de conflito de
destino e arquivo parcial. O manager mantém a tarefa e o downloader; o painel
possui somente handles de apresentação e snapshots renderizados.

`checkDownloadPanelDestination.m` cria uma figura invisível e injeta um
`DestinationResolver` determinístico. O teste confirma que modos desktop usam
o destino retornado pelo callback e que `webApp` usa `TargetPath` sem chamar o
resolver ou construir o downloader antes da decisão de conflito. Também
confirma que um nome alternativo sem extensão recebe a extensão original da URL
e é usado como o target final.

`checkDownloadSilent.m` confirma que tarefas com `DisplayMode = 'silent'` não
criam linhas nem progresso visível por padrão, mas ainda emitem conclusão e
erro. Também verifica `IncludeSilentTasks = true` no manager.

O exemplo de integração com F5 é [`F5BrowserTestApp.m`](../auth/F5BrowserTestApp.m).
Ele fornece a fábrica `ws.auth.FileDownload` baseada na sessão, enquanto
`ui.DownloadPanel` continua responsável pela UI de download e pelo ciclo de
vida das tarefas. A mesma fábrica trata fontes HTTP/HTTPS públicas sem iniciar
o login do F5.

Para URLs sem um nome útil, o painel reutiliza o fallback gerado para novas
tentativas durante a vida da mesma instância, permitindo oferecer um arquivo
`.part` parado para retomada. Se a fonte ignorar o cabeçalho HTTP `Range`, não
é possível continuar byte a byte; o worker detecta a resposta `200` e baixa a
fonte novamente desde o início.

Depois que o recurso informa que está pronto, o painel envia um array de structs
para `pingDownloadAvatar.html`, com um item para cada download ativo visível:

- `id`: ID numérico da tarefa no gerenciador.
- `rate`: taxa atual em bytes por segundo; taxas ainda não medidas são enviadas como `100000`.
- `progress`: progresso da tarefa em porcentagem, de `0` a `100`.

Uma taxa pausada ou exatamente zero gera o ponto amarelo de alerta. `NaN` e taxas
diferentes de zero abaixo de `100000` usam `100000` para a animação mínima.

O recurso emite `downloadAvatarReady` e `downloadAvatarClick`, com os tipos de
payload `ready` e `click`. O próprio recurso do avatar não acessa arquivos,
autenticação ou serviços de rede.

## Integração de download com F5

Quando `F5BrowserTestApp` recebe uma URL cujo segmento final do caminho possui
uma extensão, ele delega a solicitação a `ui.DownloadPanel`. A fábrica da
aplicação cria `ws.auth.FileDownload` com a sessão F5 autenticada.
`FileDownload` transfere dados em `backgroundPool`; arquivos parciais e partes
específicas da tarefa são armazenados na pasta temporária configurada, e o
arquivo concluído é publicado na pasta de destino somente depois que a
transferência é bem-sucedida.

O painel oferece suporte a vários downloads simultâneos, pausar/retomar e cancelar,
conflitos de destino (**Overwrite**, **Save as new**, **Cancel**) e conflitos de
arquivos parciais (**Resume**, **Restart**, **Cancel**). A aplicação mantém
apenas as responsabilidades específicas do F5 relacionadas à autenticação,
registro e comunicação de erros.

## Execução do harness

A partir da raiz do repositório, adicione a pasta de testes ao caminho do MATLAB
e execute:

```matlab
addpath(fullfile(pwd, 'tests', 'ui'))
uiFigure = checkDownloadPanel;
```

Para executar o harness legado do avatar antigo:

```matlab
uiFigure = checkDownloadHtml;
```

Para executar o teste isolado do novo avatar por download:

```matlab
uiFigure = checkPingDownloadHtml;
```

Para verificar a taxa transmitida quando um download é pausado:

```matlab
report = checkDownloadPanelPausedAvatarRate;
```

Para executar o teste rápido do transporte público:

```matlab
report = checkDownloadHttp;
```

Para executar o teste isolado do manager:

```matlab
report = checkDownloadManager;
```

Para verificar a resolução de destino por modo:

```matlab
report = checkDownloadPanelDestination;
```

Para verificar tarefas silenciosas:

```matlab
report = checkDownloadSilent;
```

O harness adiciona `src/General` ao caminho automaticamente. Quando executado,
ele cria `tests/downloads/temp` e `tests/downloads/target` e usa essas pastas como pastas
temporária e de destino simuladas.

## Cenários manuais

- **`sample1.bin`** baixa 10 MB a 250 kB/s.
- **`sample2.bin`** baixa 20 MB a 500 kB/s.
- **`sample3.bin`** baixa 30 MB a 750 kB/s.
- **`sample4.bin`** baixa 40 MB a 1 MB/s.
- O **ícone de lixeira** para as tarefas ativas e remove as pastas `temp` e
  `target` com todo o seu conteúdo. As pastas são recriadas automaticamente
  quando outro link de exemplo é clicado.
- Arquivos de destino existentes usam a linha de conflito compartilhada com
  **Overwrite**, **Save as new** e **Cancel**.
- Com a política `askInRow`, ao detectar um conflito de destino ou de arquivo
  parcial, o painel é aberto automaticamente para exibir as escolhas
  **Overwrite**/**Save as new** ou **Resume**/**Restart**. Políticas automáticas
  como `overwrite` não exibem os controles de confirmação.
- A linha de download exercita callbacks de progresso, callbacks de conclusão
  e limpeza de arquivos temporários.

O harness usa `executionMode = 'webApp'` para verificar que os controles da
aplicação no painel conseguem representar o fluxo sem seleção de arquivos na
área de trabalho ou diálogos modais de conflito. O teste ainda é executado em
uma `uifigure` local do MATLAB; ele não inicia o MATLAB Web App Server.

## Contrato do downloader simulado

`DownloadPanelFakeDownloader` expõe a mesma interface esperada de um downloader
real:

- Métodos `start`, `pause`, `resume`, `stop` e `delete`.
- Propriedades de callback `ProgressFcn`, `CompletedFcn` e `ErrorFcn`.
- Propriedades de estado `IsRunning` e `IsPaused`.

O timer avança cada exemplo na velocidade configurada, grava bytes
representativos em `Request.PartialPath` e `Request.ChunkPath` e publica um
arquivo em `Request.FinalPath` com o tamanho configurado. Pausar preserva os
arquivos de preparação para permitir a continuação; cancelar remove os arquivos
temporários e a linha correspondente. Uma
conclusão bem-sucedida remove o arquivo parcial, o arquivo de partes e qualquer
backup de sobrescrita. Intencionalmente, ele não modela o comportamento HTTP
real, autenticação, novas tentativas ou publicação entre volumes; essas
responsabilidades são cobertas por `ws.auth.FileDownload` e seu worker.

## Limitações

Este é um harness manual visual/de integração, não uma suíte automatizada de
asserções. Os contadores de callback e o rótulo de status fornecem feedback
imediato, enquanto o downloader simulado torna o comportamento do painel
repetível. A validação de transferências autenticadas do F5 pertence a
`tests/auth/F5BrowserTestApp.m` e exige o fluxo interativo real de autenticação.
