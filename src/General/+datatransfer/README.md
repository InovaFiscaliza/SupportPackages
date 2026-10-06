# datatransfer

Gerenciamento neutro de transferências HTTP para aplicações MATLAB.

Este pacote contém a orquestração neutra de transferências e o transporte HTTP de
downloads e uploads preparados, compartilhados por fontes públicas e adaptadores
específicos de provedor como `ws.auth.FileTransfer`. `HTTPFileTransfer` possui o
ciclo de vida comum e seleciona o worker por direção. O worker `uploadFileWorker`
executa uploads multipart, raw e Tus; `prepare` chama `uploadCapabilities` uma vez
para descobrir capacidades antes do envio do corpo. A integração F5 pertence a
`ws.auth.FileTransfer`; a interface do painel pertence a `ui.TransferPanel`.
O pacote não depende de `uifigure`,
`uihtml`, `ui.TransferPanel`, sessões de autenticação, cookies ou outras classes de
apresentação.

O pacote deve ser resolvido adicionando `src/General` ao caminho do MATLAB. Não
adicione a própria pasta `+datatransfer`.

## Módulos

| Módulo | Responsabilidade |
|---|---|
| [`TransferManager.m`](TransferManager.m) | Responsável pelo registro de tarefas, transições de ciclo de vida, IDs de tarefas, decisões de conflito, callbacks de transferência, snapshots, filtragem de callbacks tardios, limpeza e notificações de conclusão/erro. |
| [`HTTPFileTransfer.m`](HTTPFileTransfer.m) | Possui a preparação e o ciclo de vida assíncrono comum; seleciona `downloadFileWorker` ou `uploadFileWorker`, protege callbacks por geração e publica progresso, estado, conclusão e erro. |
| [`TransferHistoryStore.m`](TransferHistoryStore.m) | Lê, valida e escreve atomicamente o histórico de tarefas persistente versionado. |
| [`downloadFileWorker.m`](downloadFileWorker.m) | Executa transferências HTTP fragmentadas retomáveis, escreve arquivos temporários com escopo de tarefa, publica arquivos concluídos, tenta novamente falhas recuperáveis e relata progresso. |
| [`sendHTTPRequest.m`](sendHTTPRequest.m) | Envia `GET`, `HEAD`, `OPTIONS`, `POST`, `PUT`, `PATCH` e `DELETE`. As opções aceitam `Range`, cabeçalhos permitidos, corpo `uint8` ou `ContentProvider`, `FollowRedirects`, `ProgressMonitor` e um `ResponseConsumer` opcional. Redirecionamentos são tratados manualmente; corpos não são repetidos nem redirecionados. Cookies ficam limitados ao host F5 exato em HTTPS. |
| [`uploadCapabilities.m`](uploadCapabilities.m) | Descobre capacidades com `OPTIONS` e, quando necessário em host F5, `HEAD`; interpreta `Allow` e cabeçalhos Tus e seleciona o protocolo sem enviar corpo. O transporte do arquivo é executado por `uploadFileWorker`. |
| [`uploadFileWorker.m`](uploadFileWorker.m) | Executa uploads preparados nos protocolos multipart, raw ou Tus, revalida limites antes do envio e publica somente offsets Tus confirmados pelo servidor. |
| [`UploadFileProvider.m`](UploadFileProvider.m) | Lê somente o arquivo de origem e informa os bytes exatos retornados pelo provedor para o progresso raw e multipart. |
| [`UploadProgressMonitor.m`](UploadProgressMonitor.m) | Publica bytes cumulativos exatos do payload do arquivo para uploads raw e multipart, sem estimar o envelope HTTP. |
| [`UploadResponseBodyConsumer.m`](UploadResponseBodyConsumer.m) | Captura durante a recepção até 64 KiB do corpo de resposta do upload e descarta o excedente sem interromper a leitura. |
| [`transferFileName.m`](transferFileName.m) | Deriva um nome de arquivo seguro a partir de uma URL ou cria um nome de arquivo de fallback determinístico. |
| [`downloadContentDispositionFileName.m`](downloadContentDispositionFileName.m) | Extrai e sanitiza valores `filename` e `filename*` de um cabeçalho `Content-Disposition`. |
| [`moveToTrash.m`](moveToTrash.m) | Move arquivos temporários para a lixeira do host quando suportado, recorrendo à exclusão. |

## Arquitetura

O subsistema de transferências é dividido em limites de aplicação, transporte genérico e autenticação:

```text
src/General/
├── +ui/
│   ├── TransferPanel.m
│   └── html/
│       ├── orbitDownloadAvatar.html (alternativa agregada de órbita opcional)
│       └── pingTransferAvatar.html
└── +datatransfer/
    ├── HTTPFileTransfer.m
    ├── TransferManager.m
    ├── TransferHistoryStore.m
    ├── downloadContentDispositionFileName.m
    ├── transferFileName.m
    ├── downloadFileWorker.m
    ├── sendHTTPRequest.m
    ├── uploadCapabilities.m
    ├── uploadFileWorker.m
    ├── UploadFileProvider.m
    ├── UploadProgressMonitor.m
    ├── UploadResponseBodyConsumer.m
    ├── downloadSourceMetadata.m
    └── moveToTrash.m

src/Anatel/+ws/+auth/
├── F5Session.m
├── FileTransfer.m
└── DownloadProgressMonitor.m
```

### Limites de propriedade

| Limite | Propriedade | Não deve possuir |
|---|---|---|
| `datatransfer.*` | Transferência HTTP neutra em relação ao provedor, ciclo de vida assíncrono, seleção de worker, tratamento de resposta, metadados de origem, derivação de nome de arquivo, preparação e publicação. | Controles de interface do usuário, figuras, sessões de autenticação, cookies ou comportamento específico do provedor. |
| [`ui.TransferPanel`](../+ui/TransferPanel.m) | Apresentação, controles de linha, estado do avatar, callbacks da interface do usuário e renderização de snapshots do gerenciador. | Ciclo de vida de transferência, autenticação, inspeção de cookies ou chamadas diretas de adaptadores de transferência. |
| `ws.auth` | Tratamento de sessão F5, captura de cookies, reautenticação, recuperação de perfil e o adaptador `FileTransfer`. | Interface do usuário genérica e implementações de transferência neutras em relação ao provedor. |

`TransferManager` recebe um `TransferFactory` injetado; ele não chama
`uifigure`, `uihtml`, `uiputfile`, `uiconfirm`, `questdlg` ou outras APIs da interface do usuário.
A seleção de destino pertence ao painel, ao aplicativo consumidor ou a um
resolvedor de destino injetado. O gerenciador recebe o resultado normalizado e
responsável pela detecção de conflitos e transições de ciclo de vida.

`ui.TransferPanel` aceita um callback opcional `DestinationResolver` para
modos semelhantes ao desktop. O callback recebe `ExecutionMode`, `URL`,
`SuggestedFileName`, `InitialFolder` e `UIFigure`, e retorna uma estrutura
escalar com `Cancelled`, `TargetFolder` e `FileName`. Sem um callback,
o painel usa `uiputfile`. No modo `webApp` o callback e `uiputfile` são
ignorados: o painel requer um `TargetPath` existente e deriva o
nome do arquivo a partir da URL.

Para uploads, `addUpload(url, options)` aceita `LocalPath`, `FileName`,
`Protocol`, `Method`, `FormFieldName`, `FormFields`, `DisplayMode` e
`LogicalFileID`. Em modos desktop, um `LocalPath` vazio abre `uigetfile` ou
usa o `SourceResolver` injetado, que recebe `ExecutionMode`, `URL`,
`SuggestedFileName`, `InitialFolder` e `UIFigure` e retorna `Cancelled` e
`LocalPath`. No modo `webApp`, `LocalPath` deve ser explícito; caso contrário,
o painel lança `ui:TransferPanel:missingUploadSource`. `MaxUploadBytes` é uma
propriedade pública do painel, encaminhada ao gerenciador; o padrão é 200 MiB.
Linhas exibem a direção, ações em português e bytes enviados ou baixados.
Uploads sem retomada mostram **Reiniciar** e **Cancelar**, sem ação de pausa.
Um resultado incerto mostra a mensagem da resposta e exige confirmação em linha
antes de um novo envio; **Cancelar** abandona essa confirmação.

O avatar das transferências ativas é
[`pingTransferAvatar.html`](../+ui/html/pingTransferAvatar.html), ao lado da
implementação da interface do usuário do painel. Ele não faz parte deste pacote neutro em relação ao provedor.
O opcional [`orbitDownloadAvatar.html`](../+ui/html/orbitDownloadAvatar.html)
fornece a apresentação mais antiga de progresso agregado e órbita. Ele é exercitado
por `tests/transfers/checkOrbitDownloadHtml.m` e não é carregado por
`ui.TransferPanel`. Um componente `transferStatus.html` separado não está atualmente
implementado ou exigido por este pacote.

### Contrato do gerenciador

`datatransfer.TransferManager` é responsável pelo registro de tarefas, IDs de tarefas, transições de estado,
comandos `start`, `pause`, `resume` e `cancel`, callbacks da transferência,
filtragem de callbacks tardios, limpeza, decisões de conflito, snapshots e
notificações de conclusão/erro. Ele expõe snapshots e eventos, nunca
manipuladores da interface do usuário ou detalhes internos do adaptador.
`SnapshotFcn(snapshot)` publica snapshots e `TaskReorderedFcn(snapshot)` informa
mudanças de ordem. `CompletedFcn(id, info, snapshot)` e
`ErrorFcn(id, exception, snapshot)` notificam resultados terminais, inclusive
para tarefas silenciosas.

O método `addTransfer(request)` recebe `Direction` (`'download'` ou `'upload'`),
`URL` remota, `LocalPath` absoluto, `TempFolder` e `FileName` (em uploads, o nome
pode ser derivado de `LocalPath`). `LocalPath` é o destino local do download ou a
origem local do upload; a pasta de destino é obtida com `fileparts(LocalPath)`.
O gerenciador usa a fábrica injetada em `TransferFactory` e oferece
`restoreInterruptedTransfers()` para restaurar transferências elegíveis.

Snapshots expõem `Direction`, `TaskID`, `URL`, `LocalPath`, `TransferredBytes`,
`TotalBytes`, `IsResumable` e o estado do ciclo de vida. `LocalPath` é sempre
absoluto: destino de download e origem de upload. Resultados de upload podem
incluir `Response` com `StatusCode`, `Message` e `OutcomeUncertain`; detalhes
internos do adaptador e credenciais não fazem parte do snapshot.

No contrato de upload, o gerenciador exige um arquivo de origem existente e regular,
aplica `MaxUploadBytes` (padrão: 200 MiB; excesso gera
`datatransfer:TransferManager:uploadTooLarge`), valida `FormFieldName` e os nomes
dos campos adicionais e sanitiza o nome remoto `FileName`. Raw e multipart publicam o
progresso exato dos bytes do arquivo lidos; o progresso Tus permanece limitado ao
offset confirmado pelo servidor.

Em uma falha de PATCH Tus, quando existe uma resposta do PATCH, `StatusCode`,
`ResponseHeaders`, `ResponseBody` (limitado a 64 KiB) e `ResponseTruncated` continuam
descrevendo essa resposta, enquanto `UploadOffset` e `TransferredBytes` refletem
somente o offset confirmado por HEAD. Sem resposta do PATCH, a resposta conhecida de
HEAD pode fornecer esses campos; um HEAD 404/410 ainda produz erro de recurso Tus
indisponível sem substituir a evidência de uma resposta PATCH.

Snapshots, adaptadores, resultados e mensagens do worker, e o histórico usam
`TransferredBytes`. O callback `ProgressFcn` recebe
`(transferredBytes, totalBytes)`; as informações de conclusão incluem `LocalPath`.
Cada tarefa e snapshot expõe `IsResumable`. Downloads são retomáveis por padrão;
`pause` e `resume` não fazem nada quando `IsResumable` é falso.

Por padrão, `LogicalFileID` é o hash da URL exata para downloads e do caminho
canônico de `LocalPath` para uploads. Ele não é a chave de deduplicação ativa nem a
chave de linha do histórico. Duplicatas ativas de download usam URL exata e
`FileName` sem distinção entre maiúsculas e minúsculas; as de upload usam URL exata
e `LocalPath` canônico. Linhas ativas permanecem separadas por ID de tarefa; linhas
terminais do histórico e `AttemptedTimestamps` são agrupados por direção, URL exata
e `LocalPath` canônico.

`DisplayMode` aceita `normal` ou `silent` e pertence ao estado da tarefa
do gerenciador, não ao comportamento de inferência de URL ou do transporte. Tarefas silenciosas retêm o
mesmo ciclo de vida, callbacks de transferência, limpeza e callbacks de conclusão/erro,
mas seus snapshots e notificações de reordenação são omitidos da apresentação por
padrão. Uma solicitação normal que corresponda a uma tarefa silenciosa existente promove essa
tarefa à apresentação normal. A correspondência duplicada usa URL exata e
nome de arquivo insensível a maiúsculas e minúsculas, independentemente da pasta de destino e modo de exibição.
Defina `IncludeSilentTasks` no `TransferManager` para incluir snapshots de tarefas
silenciosas na apresentação do painel e do avatar sem alterar o contrato do adaptador.

O vocabulário do ciclo de vida é autoritativo:

- `pause` interrompe a transferência enquanto preserva o estado temporário retomável;
- `resume` continua a transferência pausada sem adicionar um novo timestamp de tentativa;
- `cancel` interrompe a transferência, remove arquivos temporários com escopo de tarefa e a entrada
    do histórico, e deixa qualquer arquivo de destino concluído intacto;
- `restart` descarta o estado parcial antes de começar novamente;
- conflitos de destino usam `keep`, `restart` e `cancel`;
- conflitos de arquivo parcial usam `resume`, `restart` e `cancel`.

### Protocolos de upload

`addUpload(url, options)` aceita `Protocol` como `auto`, `multipart`, `raw` ou
`tus`; `Method` aceita `POST` ou `PUT` e, por padrão, é `POST`. Multipart usa
somente `POST`; raw usa o método configurado. Os dois são envios de uma única
requisição e não podem ser pausados ou retomados. `FormFieldName` e `FormFields`
se aplicam somente a multipart.

Com `Protocol = 'auto'`, `uploadCapabilities` envia `OPTIONS` sem corpo nem
cabeçalho `Origin` e escolhe, nesta ordem: Tus 1.0.0 com a extensão `creation`;
raw quando `Allow` contém o método configurado; caso contrário, multipart `POST`
ou raw `PUT`. Para Tus, o preflight envia `Tus-Resumable: 1.0.0`. Respostas
`405`/`501`, ausência de `Allow` ou falha de rede usam o protocolo não retomável
configurado. `401`/`403` ou `3xx` do host F5 indicam necessidade de autenticação;
`HEAD` pode confirmar a sessão quando `OPTIONS` não for conclusivo. Um protocolo
explícito pula a seleção, mas não a verificação de autenticação. Preflight
descobre capacidades; não prova que o servidor aceitará o corpo.

Tus cria um recurso com `POST`, `Tus-Resumable: 1.0.0`, `Upload-Length` e
`Upload-Metadata`; espera `201 Created` com `Location`. Depois envia blocos com
`PATCH`, `Upload-Offset`, `Tus-Resumable: 1.0.0` e
`Content-Type: application/offset+octet-stream`; espera `204` com o novo offset.
O `Location` retornado é resolvido em relação à URL da solicitação; se apontar
para outro host, a tarefa falha e esse recurso não é usado.
Só o offset confirmado pelo servidor é retomável. Após interrupção ou resultado
ambíguo de `PATCH`, `HEAD` determina o offset autorizado para continuar. A
criação Tus ambígua não é repetida automaticamente. `Content-Range` não é
suportado; raw `PUT` sempre envia o arquivo inteiro.

Ao cancelar um upload Tus, o worker tenta `DELETE UploadURL` como melhor esforço
somente quando `Tus-Extension` anuncia `termination`.

O limite padrão é `MaxUploadBytes = 200 * 1024^2` bytes. O manager valida a
origem e o limite antes de criar a tarefa; o worker verifica o limite novamente
antes do corpo. Para Tus, aplica-se também `Tus-Max-Size` quando anunciado.
Uploads de uma única requisição nunca são repetidos automaticamente depois que
o corpo pode ter sido enviado. Um resultado sem confirmação fica marcado como
incerto e exige confirmação explícita no painel antes de reiniciar.

Quando o resultado expõe `ResponseHeaders`, somente `Location`, `Content-Type`
e `ETag` são permitidos. Os cabeçalhos não são persistidos no histórico.

### Histórico persistente

`TransferManager` requer um `HistoryFile` explícito e expõe o caminho resolvido
como uma propriedade somente leitura. `ui.TransferPanel` aceita `historyFile` e
usa `transfer-history.json` em `TempPath` como padrão. O gerenciador possui a
representação JSON e expõe registros normalizados por `getHistory()` e pelo campo
`HistoryEntry` nos snapshots das tarefas. `SchemaVersion` permanece `1`; cada
registro contém `EntryID`, `Direction`, `LogicalFileID`, `TaskID`, `URL`,
`LocalPath`, `TemporaryPath`, `ChunkPath`, `BackupPath`, `TempFolder`, `StartedAt`,
`CompletedAt`, `UpdatedAt`, `LifecycleState`, `TransferredBytes`, `MeasuredSpeed`,
`RateSource`, `ErrorMessages`, `AttemptedTimestamps`, `isAvailable`, `Protocol`,
`UploadURL`, `UploadOffset`, `LocalBytes`, `LocalModifiedAt` e `Response`.

O JSON contém o array `Entries`, com um registro por tentativa e timestamps UTC
ISO 8601. `Response` guarda somente o resumo `FileName`, `CompletedAt`, `Success`,
`StatusCode`, `Message` e `OutcomeUncertain`; corpo, cabeçalhos e cookies não são
persistidos. `AttemptedTimestamps` reúne tentativas com a mesma direção, URL exata
e caminho local canônico. Retomar uma tarefa pausada ou repetir uma duplicata não
adiciona um timestamp.

O gerenciador escreve o histórico em transições do ciclo de vida usando um arquivo
temporário no mesmo diretório seguido por substituição. Um histórico ausente começa
vazio. Um arquivo no formato legado com `SourceURL`, `TargetPath` ou
`DownloadedBytes` é tratado como corrompido e excluído sem migração; outros JSON
inválidos são colocados em quarentena como `.corrupt` e tratados como vazios. A
inicialização atualiza as contagens de bytes a partir de arquivos parciais correspondentes, marca tentativas ativas obsoletas como interrompidas,
verifica a disponibilidade do destino concluído e remove arquivos de preparação não referenciados com escopo de tarefa e
`.part` legados das pastas temporárias configuradas. Arquivos não relacionados são deixados intactos. A limpeza usa
a lixeira do host quando disponível e exclui permanentemente o arquivo temporário apenas quando
o host não fornece uma API de lixeira utilizável.

`restoreInterruptedTransfers()` restaura a tentativa interrompida elegível mais
recente para cada combinação de direção, URL exata e caminho local canônico. Para
downloads, exige que o arquivo temporário ainda exista; a tarefa restaurada aparece
como conflito parcial com `Continuar`, `Reiniciar` e `Cancelar`, sem iniciar o download
até uma escolha. Uploads Tus restaurados verificam a origem antes de oferecer
retomada ou reinício.

O painel traduz as ações do usuário em comandos do gerenciador e renderiza snapshots.
O estado da tarefa tem um único proprietário: o gerenciador possui o estado de transferência, enquanto o painel possui
apenas manipuladores da interface do usuário e estado de apresentação.

Quando um conflito de arquivo de destino ou parcial é detectado com a
política correspondente definida como `askInRow`, o gerenciador emite um snapshot pendente. O painel
renderiza as opções de linha apropriadas sem abrir um diálogo modal:
**Manter**, **Reiniciar** e **Cancelar** para conflitos de destino, ou
**Continuar**, **Reiniciar** e **Cancelar** para arquivos parciais. Manter um destino registra uma tentativa concluída disponível
sem iniciar uma transferência. Reiniciar substitui explicitamente o destino.
Excluir uma linha concluída remove seu histórico e arquivos temporários restantes, mas
não exclui o arquivo de destino. O gerenciador verifica novamente o destino antes da
publicação.

### Contrato do adaptador

`datatransfer.HTTPFileTransfer` possui a preparação e o ciclo de vida da
transferência, chama `downloadSourceMetadata` para downloads e chama
`uploadCapabilities` uma vez em `prepare` para uploads. Depois da preparação,
despacha para `downloadFileWorker` ou `uploadFileWorker` com os valores resolvidos.
Aplicações sem F5 podem usar `@(request) datatransfer.HTTPFileTransfer(request)`.

O adaptador implementa `prepare`, `start`, `pause`, `resume`, `stop` e `delete`;
expõe `IsRunning`, `IsPaused` e `IsResumable`; e aceita os callbacks
`ProgressFcn`, `CompletedFcn`, `ErrorFcn` e `StateFcn`. `CompletedFcn(info)` é
chamado uma vez após a conclusão confirmada. `ErrorFcn(exception)` é chamado
uma vez em falha terminal; cancelamento não é falha. Em downloads, o callback
recebe um `MException`; em uploads, recebe um struct com `identifier`, `message`,
`StatusCode` e `OutcomeUncertain` para preservar resultados ambíguos.
`prepare` retorna um struct escalar com `Direction`, `URL`, `LocalPath`,
`FileName`, `TotalBytes`, `IsResumable`, `ResolvedProtocol`, `TusMaxSize`,
`UploadURL` e `UploadOffset`; o manager aplica esse estado inicial à tarefa.
`StateFcn(state)` recebe um struct escalar com `IsResumable`, `ResolvedProtocol`,
`UploadURL` e `UploadOffset`, sem credenciais, e publica atualizações do worker,
incluindo URL e offset Tus confirmados. O manager mantém `IsResumable` na tarefa
e no snapshot. No histórico, `ResolvedProtocol` é gravado como `Protocol`.
`UploadURL` e `UploadOffset` só contêm estado útil para uploads Tus retomáveis;
`IsResumable` permanece na tarefa e no snapshot, não no histórico. O manager
associa callbacks à geração da tarefa, ignora callbacks obsoletos e os limpa ao
liberar o adaptador.

Para transferências autenticadas pelo F5, `ws.auth.FileTransfer` herda de
`datatransfer.HTTPFileTransfer` e substitui somente `acquireContext` e
`reauthenticate`, delegando a `F5Session.getRequestContext` e
`F5Session.authenticateForRequest`. O worker genérico recebe um `requestContext`
opaco; `HTTPFileTransfer` não inspeciona cookies nem conhece `F5Session`.
A autenticação ocorre no preflight de `prepare`, antes do primeiro corpo. Em
Tus, após `NeedsAuthentication`, o adaptador só recomeça quando um `HEAD` seguro
permite usar o último `Upload-Offset` confirmado; publica esse offset antes de
retomar. Se `OutcomeUncertain` permanece verdadeiro, não há retry automático.
Uploads one-shot nunca são repetidos após possível envio; resultados ambíguos
são expostos ao manager.

Nenhum pacote genérico chama a implementação concreta de outro provedor. A
solicitação normalizada e o `requestContext` opaco são os limites entre o
transporte genérico e os adaptadores de autenticação.

### Segurança

- Cookies F5 só são enviados ao host exato da sessão, por HTTPS, em qualquer
  método HTTP. URLs públicas não recebem cookies F5.
- Requisições com corpo não seguem redirecionamentos automaticamente. Um `3xx`
  do host F5 indica necessidade de autenticação; um `3xx` de outro host falha
  com `datatransfer:sendHTTPRequest:unexpectedRedirect`. O `Location` de uma
  criação Tus `201 Created` identifica o recurso, não um redirecionamento.
- A autenticação ocorre no preflight, antes do corpo. Um corpo que possa ter
  chegado ao servidor nunca é repetido automaticamente, inclusive após resposta
  de autenticação. Resultados ambíguos exigem confirmação no painel.
- `transferFileName` remove CR/LF, aspas, separadores de caminho e controles do
  nome usado em multipart, `Upload-Metadata` e cabeçalhos. Nomes de campos
  seguem `^[A-Za-z0-9_.-]{1,64}$`; valores adicionais devem ser texto escalar.
  Chamadores não podem definir `Cookie`, `Authorization`, `Host`,
  `Content-Length` ou `Transfer-Encoding`.
- `LocalPath` de upload deve resolver para arquivo regular existente. Em
  `webApp`, a aplicação deve fornecer explicitamente a origem; o painel não
  pede um caminho digitado. Os limites de tamanho são verificados antes do
  registro e novamente antes do envio.
- Corpos de resposta não são renderizados como HTML nem persistidos. Valores de
  cookies nunca são registrados ou gravados no histórico; o histórico não guarda
  cabeçalhos.

### Política de namespace e erro

Todos os chamadores do repositório usam `datatransfer.*` para auxiliares genéricos, incluindo
`datatransfer.transferFileName`, `datatransfer.downloadSourceMetadata`,
`datatransfer.sendHTTPRequest` e `@datatransfer.downloadFileWorker`.

Erros genéricos usam o namespace `datatransfer:*`. Erros do adaptador F5 usam
`ws:auth:*`, e erros do painel usam `ui:TransferPanel:*`. O painel reutilizável
é `ui.TransferPanel`; não há wrappers de compatibilidade.

### Caminho, empacotamento e validação

Adicione `src/General` ao caminho do MATLAB para que `ui.*` e `datatransfer.*` resolvam como
pacotes irmãos. Não adicione a pasta de nenhum pacote diretamente. Os arquivos de código
`+datatransfer` são dependências de código regulares. Aplicações que usam `ui.TransferPanel`
devem incluir `pingTransferAvatar.html` explicitamente como um arquivo adicional;
`profileAvatar.html` permanece em `+ws/+auth`. Inclua
`orbitDownloadAvatar.html` apenas quando uma aplicação usar essa alternativa opcional.

Aplicações compiladas que usam `ui.TransferPanel` devem incluir
`pingTransferAvatar.html` explicitamente nos arquivos adicionais. Localize o
recurso pelo pacote, sem fixar o caminho do checkout:

```matlab
uiFolder = fileparts(which('ui.TransferPanel'));
transferAvatar = fullfile(uiFolder, 'html', 'pingTransferAvatar.html');
compiler.build.standaloneApplication(appFile, ...
    'AdditionalFiles', string(transferAvatar));
```

Mantenha os demais arquivos adicionais já usados pela aplicação na mesma lista.
Inclua `orbitDownloadAvatar.html` somente se a aplicação usar essa alternativa.

### Limites da inspeção da API MATLAB

A inspeção offline da API confirma que `FileProvider` pode fornecer o corpo de
uma requisição e que `MultipartFormProvider` aceita partes fornecidas por
`ContentProvider`. Ela não comprova limites de memória, framing HTTP multipart,
execução de callbacks em `backgroundPool`/`DataQueue`, nem comportamento de
servidores. `ProgressMonitor` expõe direção e valor de progresso; o comportamento
assíncrono real ainda requer validação. Esses pontos permanecem para a Fase 10;
esta documentação não os trata como garantias.
