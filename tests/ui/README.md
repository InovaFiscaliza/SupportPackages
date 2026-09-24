# tests/ui

Esta pasta contém o harness manual de UI e o dublê de teste de
`src/General/+ui/DownloadPanel` e `src/General/+download/DownloadManager`.

Ela também contém o harness visual isolado de
`src/General/+ui/html/downloadAvatar.html`. O harness do avatar e o harness do
painel são deliberadamente separados: um verifica o protocolo de apresentação
HTML, enquanto o outro verifica o painel MATLAB, a fábrica de downloaders, o
ciclo de vida das tarefas e o comportamento do sistema de arquivos.

## Arquivos

| Arquivo | Função |
|---|---|
| [`checkDownloadPanel.m`](checkDownloadPanel.m) | Abre um harness manual em `uifigure` para o painel reutilizável. |
| [`checkDownloadPanelDestination.m`](checkDownloadPanelDestination.m) | Verifica automaticamente a resolução de destino nos modos desktop e Web App. |
| [`checkDownloadManager.m`](checkDownloadManager.m) | Verifica o ciclo de vida e conflitos do manager sem UI. |
| [`checkDownloadSilent.m`](checkDownloadSilent.m) | Verifica tarefas silenciosas, callbacks e inclusão opcional na apresentação. |
| [`checkDownloadHtml.m`](checkDownloadHtml.m) | Testa apenas o recurso `uihtml` `downloadAvatar.html`. |
| [`checkDownloadHttp.m`](checkDownloadHttp.m) | Faz um teste rápido do transporte HTTP público, do fallback de nome de arquivo e do isolamento de cookies por host exato. |
| [`DownloadPanelFakeDownloader.m`](DownloadPanelFakeDownloader.m) | Simula o objeto downloader exigido por `ui.DownloadPanel`. |
| [`DownloadManagerFakeDownloader.m`](DownloadManagerFakeDownloader.m) | Simula um downloader síncrono para o contrato do manager. |

Esses arquivos têm responsabilidades diferentes. `checkDownloadPanel` é o
harness de teste interativo propriamente dito. `DownloadPanelFakeDownloader` é
sua dependência injetada: ele fornece progresso determinístico orientado por
timer e comportamento do sistema de arquivos sem tráfego de rede, autenticação
F5 ou `backgroundPool`.

`checkDownloadHtml` é intencionalmente separado do harness do painel. Ele testa
apenas o protocolo de apresentação de `downloadAvatar.html`: níveis de
progresso, estado ativo, quantidade de esferas em órbita, velocidade da órbita,
evento de pronto e evento de clique. Ele não cria arquivos de download, não
instancia `ui.DownloadPanel` nem executa operações de rede ou autenticação.

## Harness isolado do avatar

`checkDownloadHtml.m` cria uma pequena `uifigure` contendo o componente `uihtml`
`downloadAvatar.html` e controles para seu estado visual:

- Progresso de `0%` a `100%`, convertido nos níveis de avatar de `0` a `10`.
- Estado de animação ativo/inativo.
- Quantidade de esferas em órbita de `1` a `10`.
- Velocidade da órbita em radianos por segundo.
- Um indicador de clique que confirma que `downloadAvatarClick` chegou ao MATLAB.

Este harness é exclusivamente de apresentação. Ele não cria arquivos
temporários ou de destino, não inicia `ui.DownloadPanel`, não autentica nem
realiza transferências de rede.

## Integração com DownloadPanel

`checkDownloadPanel.m` exercita `ui.DownloadPanel` com
`DownloadPanelFakeDownloader`. Ele fornece quatro links de exemplo com tamanhos
e velocidades diferentes, progresso das tarefas, comportamento de
pausar/retomar/cancelar, escolhas para conflitos de destino e de arquivos parciais
e os controles de fechar/lixeira. O painel usa internamente o recurso
compartilhado `downloadAvatar.html`.

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

Depois que o recurso informa que está pronto, o painel envia o seguinte estado
para `downloadAvatar.html`:

- `level`: nível de progresso agregado de `0` a `10`.
- `inProgress`: indica se há pelo menos uma transferência ativa.
- `ballCount`: quantidade de downloads ativos representados por esferas em órbita.
- `speedRadiansPerSecond`: velocidade visual agregada da órbita.

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

Para executar o teste isolado do avatar de download:

```matlab
uiFigure = checkDownloadHtml;
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
ele cria `tests/ui/temp` e `tests/ui/target` e usa essas pastas como pastas
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
