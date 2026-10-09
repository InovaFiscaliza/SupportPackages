# tests/transfers

Esta pasta contém o harness manual de UI e o dublê de teste de
`src/General/+ui/TransferPanel` e `src/General/+datatransfer/TransferManager`.

Os harnesses desta pasta cobrem o transporte de download e o fluxo Tus do
serviço LAN temporário descrito na Fase 10 do plano. Eles não validam upload
raw, multipart, autenticação F5 ou resultados ambíguos de uploads one-shot.
Os contratos dos protocolos e de segurança estão no
[README do pacote `datatransfer`](../../src/General/+datatransfer/README.md).

Ela também contém harnesses visuais isolados para os avatares. O painel usa
`pingTransferAvatar.html`; `orbitDownloadAvatar.html` é uma alternativa visual
agregada, exercitada apenas pelo harness `checkOrbitDownloadHtml`. Os harnesses
de avatar e de painel são deliberadamente separados: os primeiros verificam os
protocolos de apresentação HTML, enquanto o painel verifica a UI MATLAB, a
fábrica de transferências, o ciclo de vida das tarefas e o comportamento do sistema
de arquivos.

## Arquivos

| Arquivo | Função |
|---|---|
| [`checkTransferPanel.m`](checkTransferPanel.m) | Abre um harness manual em `uifigure` para o painel reutilizável. |
| [`checkTransferPanelDestination.m`](checkTransferPanelDestination.m) | Verifica automaticamente a resolução de destino nos modos desktop e Web App. |
| [`checkTransferManager.m`](checkTransferManager.m) | Verifica o ciclo de vida e conflitos do manager sem UI. |
| [`checkTransferSilent.m`](checkTransferSilent.m) | Verifica tarefas silenciosas, callbacks e inclusão opcional na apresentação. |
| [`checkOrbitDownloadHtml.m`](checkOrbitDownloadHtml.m) | Harness visual opcional de `orbitDownloadAvatar.html`, com progresso agregado e órbita. |
| [`checkPingTransferHtml.m`](checkPingTransferHtml.m) | Testa o recurso `uihtml` `pingTransferAvatar.html` com IDs, taxas, progresso e direção por transferência. |
| [`checkTransferPanelPausedAvatarRate.m`](checkTransferPanelPausedAvatarRate.m) | Confirma que downloads pausados chegam ao avatar com taxa zero. |
| [`checkDownloadHttp.m`](checkDownloadHttp.m) | Testa o transporte HTTP sem autenticação usando `test.txt` no serviço LAN, o fallback de nome e o isolamento de cookies. |
| [`checkUploadPreflight.m`](checkUploadPreflight.m) | Testa seleção Tus com respostas HTTP simuladas, inclusive sem o cabeçalho `Allow`. |
| [`checkUploadHttp.m`](checkUploadHttp.m) | Faz upload Tus real no serviço LAN e compara os bytes recuperados com a origem. |
| [`TransferPanelFakeTransfer.m`](TransferPanelFakeTransfer.m) | Simula o objeto de transferência exigido por `ui.TransferPanel`. |
| [`TransferManagerFakeTransfer.m`](TransferManagerFakeTransfer.m) | Simula uma transferência síncrona para o contrato do manager. |

Esses arquivos têm responsabilidades diferentes. `checkTransferPanel` é o
harness de teste interativo propriamente dito. `TransferPanelFakeTransfer` é
sua dependência injetada: ele fornece progresso determinístico orientado por
timer e comportamento do sistema de arquivos sem tráfego de rede, autenticação
F5 ou `backgroundPool`.

`checkOrbitDownloadHtml` é um harness visual opcional, separado do painel.
Ele testa o protocolo agregado de `orbitDownloadAvatar.html`: níveis de
progresso, estado ativo, quantidade de esferas em órbita, velocidade da órbita,
evento de pronto e evento de clique. Não é usado pelo painel atual.

## Harnesses isolados de avatar

`checkOrbitDownloadHtml.m` cria uma pequena `uifigure` contendo o componente
`uihtml` opcional `orbitDownloadAvatar.html` e controles para seu estado visual:

- Progresso de `0%` a `100%`, convertido nos níveis de avatar de `0` a `10`.
- Estado de animação ativo/inativo.
- Quantidade de esferas em órbita de `1` a `10`.
- Velocidade da órbita em radianos por segundo.
- Um indicador de clique que confirma que `downloadAvatarClick` chegou ao MATLAB.

Este harness é exclusivamente de apresentação. Ele não cria arquivos
temporários ou de destino, não inicia `ui.TransferPanel`, não autentica nem
realiza transferências de rede.

`checkPingTransferHtml.m` exercita o avatar por meio de structs MATLAB com os
campos `id`, `rate`, `progress` e `direction`, que aceita somente `download` ou
`upload`. O harness envia struct vazio, escalar ou array conforme a quantidade
selecionada, com IDs numéricos, taxa em bytes por segundo e progresso entre `0`
e `100`. Os controles permitem variar até 23 transferências, escolher downloads,
uploads ou ambos, ajustar progresso e taxa, além de confirmar o evento de clique
e erros de validação recebidos pelo MATLAB.

`checkTransferPanelPausedAvatarRate.m` verifica taxa zero para tarefas pausadas
e parciais em espera. Também confirma que uma solicitação normal repetida pode
recuperar uma tarefa silenciosa, promover sua linha ao topo e abrir o painel
sem acrescentar um timestamp de tentativa.

## Integração com TransferPanel

`checkTransferPanel.m` exercita `ui.TransferPanel` com
`TransferPanelFakeTransfer`. Ele fornece links para quatro tamanhos e
velocidades, além de cenários de falha, destino existente, arquivo parcial e
cancelamento. O harness cobre progresso, pausa/retomada/cancelamento e escolhas
de conflito. O painel usa internamente o recurso
`pingTransferAvatar.html`, que apresenta cada tarefa visível com ID, taxa de
transferência e progresso individuais. Isso inclui tarefas ativas, pausadas e
parciais em espera. Tarefas silenciosas não aparecem no avatar; uma solicitação
normal correspondente as torna visíveis.

`checkTransferManager.m` exercita o manager sem criar `uifigure`: confirma
snapshots, conclusão, remoção de tarefas, deduplicação por URL e nome, timestamps
de tentativa, retomada e decisões de conflito de destino e arquivo parcial. A
retomada e a repetição deduplicada não acrescentam timestamp. O manager mantém a
tarefa e o adaptador de transferência; o painel possui somente handles de apresentação e
snapshots renderizados.

O teste também verifica a persistência do histórico entre reconstruções,
transições de pausa/retomada/cancelamento, identidade lógica estável,
reconciliação de arquivos concluídos, recuperação de bytes de parciais
interrompidas e seu retorno ao estado de conflito parcial, além da limpeza de
parciais legadas e por tarefa quando o JSON do histórico está corrompido, sem
remover arquivos não relacionados. Por padrão,
o painel armazena `transfer-history.json` ao lado dos arquivos temporários. O manager usado
diretamente recebe `HistoryFile`
explicitamente; `TempFolder` pode ser informado quando a limpeza inicial deve
examinar outra pasta.

`checkTransferPanelDestination.m` cria uma figura invisível e injeta um
`DestinationResolver` determinístico. O teste confirma que modos desktop usam
o destino retornado pelo callback e que `webApp` usa `TargetPath` sem chamar o
resolver ou construir o adaptador de transferência antes da decisão de conflito. Também
confirma que um nome alternativo sem extensão recebe a extensão original da URL
e é usado como o target final.

`checkTransferSilent.m` confirma que tarefas com `DisplayMode = 'silent'` não
criam linhas nem progresso visível por padrão, mas ainda emitem conclusão e
erro. Também verifica `IncludeSilentTasks = true` no manager.

O exemplo de integração com F5 é [`F5BrowserTestApp.m`](../auth/F5BrowserTestApp.m).
Ele fornece a fábrica `ws.auth.FileTransfer` baseada na sessão, enquanto
`ui.TransferPanel` continua responsável pela UI de transferência e pelo ciclo de
vida das tarefas. A mesma fábrica trata fontes HTTP/HTTPS públicas sem iniciar
o login do F5.

`TransferPanel.addUpload(url, options)` aceita o caminho local, nome remoto,
protocolo, método, campos multipart, modo de exibição e identidade lógica. Em
modos desktop, um `LocalPath` vazio usa `uigetfile` ou um `SourceResolver`
injetado; no modo `webApp`, o chamador deve informar `LocalPath`. O fake respeita
`Direction` e `IsResumable`, simula o progresso do envio sem alterar o arquivo de
origem e não realiza chamadas de rede.

Para URLs sem um nome útil, o painel reutiliza o fallback gerado para novas
tentativas durante a vida da mesma instância, permitindo oferecer um arquivo
`.part` parado para retomada. A deduplicação de tarefas não terminais compara a
URL exata e o nome de arquivo selecionado em downloads, sem distinguir a pasta
de destino ou o modo de exibição. Se a fonte ignorar o cabeçalho HTTP `Range`, não é possível
continuar byte a byte; o worker detecta a resposta `200` e baixa a fonte
novamente desde o início.

Depois que o recurso informa que está pronto, o painel envia um array de structs
para `pingTransferAvatar.html`, com um item para cada tarefa ativa, pausada ou
parcial em espera que esteja visível:

- `id`: ID numérico da tarefa no gerenciador.
- `rate`: taxa atual em bytes por segundo; taxas ainda não medidas são enviadas como `100000`.
- `progress`: progresso da tarefa em porcentagem, de `0` a `100`.
- `direction`: `download` ou `upload`.

Uma taxa pausada ou exatamente zero gera o ponto amarelo de alerta. `NaN` e taxas
diferentes de zero abaixo de `100000` usam `100000` para a animação mínima. Um
upload ativo não retomável também envia `100000` quando a taxa ainda não foi
medida. `pingTransferAvatar.html` valida `direction` e exibe setas distintas para
downloads, uploads ou ambos; o harness inclui esse campo nos dados enviados.

O recurso emite `transferAvatarReady` e `transferAvatarClick`, com os tipos de
payload `ready` e `click`. O próprio recurso do avatar não acessa arquivos,
autenticação ou serviços de rede.

## Integração de download com F5

Quando `F5BrowserTestApp` recebe uma URL cujo segmento final do caminho possui
uma extensão, ele delega a solicitação a `ui.TransferPanel`. A fábrica da
aplicação cria `ws.auth.FileTransfer` com a sessão F5 autenticada.
`FileTransfer` foi projetado para executar transferências em `backgroundPool`;
essa execução e o comportamento de callbacks em `backgroundPool`/`DataQueue`
permanecem sem validação em runtime até a Fase 10. Arquivos parciais e partes
específicas da tarefa são armazenados na pasta temporária configurada, e o
arquivo concluído é publicado na pasta de destino somente depois que a
transferência é bem-sucedida.

O painel oferece suporte a vários downloads simultâneos, pausar/retomar,
reiniciar e cancelar, conflitos de destino (**Manter**, **Reiniciar**, **Cancelar**)
e conflitos de arquivos parciais (**Continuar**, **Reiniciar**, **Cancelar**).
Arquivos concluídos e com falha permanecem no histórico renderizado pelo painel.
A aplicação mantém apenas as responsabilidades específicas do F5 relacionadas
à autenticação, registro e comunicação de erros.

O JSON mantém um registro por tentativa. As linhas de histórico terminais do
painel agrupam tentativas por direção, URL exata e `LocalPath` canônico, usando o
estado mais recente; tarefas ativas permanecem separadas por ID de tarefa.
`LogicalFileID` não é a chave dessas linhas: para downloads, é derivado da URL
exata. Ao inicializar, o gerenciador restaura tentativas interrompidas elegíveis cujo
arquivo temporário ainda existe. O download restaurado aparece como conflito
parcial, com **Continuar**, **Reiniciar** e **Cancelar**; nenhum adaptador de transferência é
iniciado até o usuário escolher uma ação.

## Execução dos harnesses

A partir da raiz do repositório, adicione as pastas de código e testes ao caminho
do MATLAB e execute:

```matlab
addpath(fullfile(pwd, 'src', 'General'))
addpath(fullfile(pwd, 'tests', 'transfers'))
uiFigure = checkTransferPanel;
```

Para executar o harness do avatar agregado opcional:

```matlab
uiFigure = checkOrbitDownloadHtml;
```

Para executar o teste isolado do avatar de transferências:

```matlab
uiFigure = checkPingTransferHtml;
```

Para verificar a taxa transmitida quando um download é pausado:

```matlab
report = checkTransferPanelPausedAvatarRate;
```

Para executar o teste rápido do transporte HTTP sem autenticação:

```matlab
report = checkDownloadHttp;
```

Para verificar a seleção de protocolo Tus sem rede:

```matlab
report = checkUploadPreflight;
```

Para executar o upload Tus real e a verificação byte a byte:

```matlab
report = checkUploadHttp;
```

Esses dois harnesses HTTP usam o serviço LAN temporário: Tus em
`http://containerhost.hv:8080/upload/` e arquivos em
`http://localhost:8080/files/`. `checkUploadHttp` cria um nome único e deixa
o arquivo remoto no servidor; remove apenas arquivos locais temporários.
O arquivo `http://localhost:8080/files/test.txt` confirma que o servidor de
download está ativo. Esses testes não substituem a validação autenticada do F5.

Para executar o teste isolado do manager:

```matlab
report = checkTransferManager;
```

Para verificar a resolução de destino por modo:

```matlab
report = checkTransferPanelDestination;
```

Para verificar tarefas silenciosas:

```matlab
report = checkTransferSilent;
```

O harness adiciona `src/General` ao caminho automaticamente. Quando executado,
ele cria `tests/transfers/temp` e `tests/transfers/target` e usa essas pastas como pastas
temporária e de destino simuladas.

## Cenários manuais

- **`sample1.bin`** baixa 10 MB a 250 kB/s.
- **`sample2.bin`** baixa 20 MB a 500 kB/s.
- **`sample3.bin`** baixa 30 MB a 750 kB/s.
- **`sample4.bin`** baixa 40 MB a 1 MB/s no modo silencioso.
- **`sample-failed.bin`** conclui com falha simulada para exercitar a notificação de erro.
- **`sample-existing.bin`** exercita manter o destino existente ou reiniciar a transferência.
- **`sample-partial.bin`** exercita continuar ou reiniciar um arquivo parcial.
- **`sample-cancel.bin`** exercita o cancelamento de uma transferência ativa.
- O **ícone de lixeira** para as tarefas ativas e remove as pastas `temp` e
  `target` com todo o seu conteúdo. As pastas são recriadas automaticamente
  quando outro link de exemplo é clicado.
- Arquivos de destino existentes usam a linha de conflito compartilhada com
  **Manter**, **Reiniciar** e **Cancelar**. Manter conclui a tentativa sem
  transferir novamente os bytes; Reiniciar substitui o arquivo apenas após
  escolha explícita.
- Com a política `askInRow`, um arquivo parcial oferece **Continuar**,
  **Reiniciar** e **Cancelar**. O painel mostra downloads pausados primeiro,
  depois ativos e por fim os registros concluídos, preservando a ordem de
  inclusão em cada grupo.
- Cancelar uma linha concluída remove o registro de histórico, mas preserva o
  arquivo de destino; cancelar um download inacabado também remove seus
  temporários.
- A linha de download exercita callbacks de progresso, callbacks de conclusão
  e limpeza de arquivos temporários.

O harness usa `executionMode = 'webApp'` para verificar que os controles da
aplicação no painel conseguem representar o fluxo sem seleção de arquivos na
área de trabalho ou diálogos modais de conflito. O teste ainda é executado em
uma `uifigure` local do MATLAB; ele não inicia o MATLAB Web App Server.

## Contrato do dublê de transferência

`TransferPanelFakeTransfer` expõe a mesma interface esperada de uma transferência
real e inclui `Direction` e `IsResumable`:

- Métodos `start`, `pause`, `resume`, `stop` e `delete`.
- Propriedades de callback `ProgressFcn`, `CompletedFcn` e `ErrorFcn`.
- Propriedades de estado `IsRunning` e `IsPaused`.

O timer avança cada download de exemplo na velocidade configurada, grava bytes
representativos em `Request.PartialPath` e `Request.ChunkPath` e publica um
arquivo em `Request.LocalPath` com o tamanho configurado. Nos envios simulados,
ele atualiza o progresso e conclui a tarefa sem alterar o arquivo de origem.
Pausar um download preserva os arquivos de preparação para permitir a
continuação; cancelar remove os temporários do download e a linha correspondente.
Uma conclusão bem-sucedida remove o arquivo parcial, o arquivo de partes e
qualquer backup de sobrescrita. O dublê não modela o transporte HTTP real nem a
autenticação F5. O ciclo de vida e o transporte neutros pertencem a
`datatransfer.HTTPFileTransfer` e aos workers de `datatransfer`; `ws.auth.FileTransfer`
fornece os contextos de autenticação F5.

## Limitações

Este é um harness manual visual/de integração, não uma suíte automatizada de
asserções. Os contadores de callback e o rótulo de status fornecem feedback
imediato, enquanto o dublê de transferência torna o comportamento do painel
repetível. A validação de transferências autenticadas do F5 pertence a
`tests/auth/F5BrowserTestApp.m` e exige o fluxo interativo real de autenticação.
