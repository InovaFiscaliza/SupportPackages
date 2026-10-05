# datatransfer

Gerenciamento neutro de transferências HTTP para aplicações MATLAB.

Este pacote contém a orquestração neutra de transferências e o transporte HTTP de
downloads, compartilhados por fontes públicas e adaptadores específicos de provedor
como `ws.auth.FileTransfer`. O gerenciador também valida solicitações de upload, mas
o envio do corpo do arquivo ainda pertence à fase P4; a descoberta de capacidades
de upload por `OPTIONS` pertence à fase P3. O pacote não depende de `uifigure`,
`uihtml`, `ui.TransferPanel`, sessões de autenticação, cookies ou outras classes de
apresentação.

O pacote deve ser resolvido adicionando `src/General` ao caminho do MATLAB. Não
adicione a própria pasta `+datatransfer`.

## Módulos

| Módulo | Responsabilidade |
|---|---|
| [`TransferManager.m`](TransferManager.m) | Responsável pelo registro de tarefas, transições de ciclo de vida, IDs de tarefas, decisões de conflito, callbacks do downloader, snapshots, filtragem de callbacks tardios, limpeza e notificações de conclusão/erro. |
| [`TransferHistoryStore.m`](TransferHistoryStore.m) | Lê, valida e escreve atomicamente o histórico de tarefas persistente versionado. |
| [`downloadFileWorker.m`](downloadFileWorker.m) | Executa transferências HTTP fragmentadas retomáveis, escreve arquivos temporários com escopo de tarefa, publica arquivos concluídos, tenta novamente falhas recuperáveis e relata progresso. |
| [`sendHTTPRequest.m`](sendHTTPRequest.m) | Envia `GET`, `HEAD`, `OPTIONS`, `POST`, `PUT`, `PATCH` e `DELETE`. As opções aceitam `Range`, cabeçalhos permitidos, corpo `uint8` ou `ContentProvider`, `FollowRedirects` e `ProgressMonitor`. Redirecionamentos são tratados manualmente; corpos não são repetidos nem redirecionados. Cookies ficam limitados ao host F5 exato em HTTPS. |
| [`uploadCapabilities.m`](uploadCapabilities.m) | Descobre capacidades com `OPTIONS` e, quando necessário em host F5, `HEAD`; interpreta `Allow` e cabeçalhos Tus e seleciona o protocolo sem enviar corpo. Aceita um sender opcional para respostas simuladas. Esta descoberta pertence à P3; o envio do arquivo permanece na P4. |
| [`transferFileName.m`](transferFileName.m) | Deriva um nome de arquivo seguro a partir de uma URL ou cria um nome de arquivo de fallback determinístico. |
| [`downloadContentDispositionFileName.m`](downloadContentDispositionFileName.m) | Extrai e sanitiza valores `filename` e `filename*` de um cabeçalho `Content-Disposition`. |
| [`moveToTrash.m`](moveToTrash.m) | Move arquivos temporários para a lixeira do host quando suportado, recorrendo à exclusão. |

## Arquitetura

O subsistema de download é dividido em três limites:

```text
src/General/
├── +ui/
│   ├── TransferPanel.m
│   └── html/
│       ├── orbitDownloadAvatar.html (alternativa agregada de órbita opcional)
│       └── pingTransferAvatar.html
└── +datatransfer/
    ├── TransferManager.m
    ├── TransferHistoryStore.m
    ├── downloadContentDispositionFileName.m
    ├── transferFileName.m
    ├── downloadFileWorker.m
    ├── sendHTTPRequest.m
    ├── uploadCapabilities.m
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
| `datatransfer.*` | Transferência HTTP neutra em relação ao provedor, tratamento de resposta, metadados de origem, derivação de nome de arquivo, preparação com escopo de tarefa, publicação e orquestração de transferência. | Controles de interface do usuário, figuras, sessões de autenticação, cookies ou comportamento específico do provedor. |
| [`ui.TransferPanel`](../+ui/TransferPanel.m) | Apresentação, controles de linha, estado do avatar, callbacks da interface do usuário e renderização de snapshots do gerenciador. | Ciclo de vida de transferência, autenticação, inspeção de cookies ou chamadas diretas do downloader. |
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

O avatar de download ativo é
[`pingTransferAvatar.html`](../+ui/html/pingTransferAvatar.html), ao lado da
implementação da interface do usuário do painel. Ele não faz parte deste pacote neutro em relação ao provedor.
O opcional [`orbitDownloadAvatar.html`](../+ui/html/orbitDownloadAvatar.html)
fornece a apresentação mais antiga de progresso agregado e órbita. Ele é exercitado
por `tests/transfers/checkOrbitDownloadHtml.m` e não é carregado por
`ui.TransferPanel`. Um componente `downloadStatus.html` separado não está atualmente
implementado ou exigido por este pacote.

### Contrato do gerenciador

`datatransfer.TransferManager` é responsável pelo registro de tarefas, IDs de tarefas, transições de estado,
comandos `start`, `pause`, `resume` e `cancel`, callbacks da transferência,
filtragem de callbacks tardios, limpeza, decisões de conflito, snapshots e
notificações de conclusão/erro. Ele expõe snapshots e eventos, nunca
manipuladores da interface do usuário ou detalhes internos do adaptador.

O método `addTransfer(request)` recebe `Direction` (`'download'` ou `'upload'`),
`URL` remota, `LocalPath` absoluto, `TempFolder` e `FileName` (em uploads, o nome
pode ser derivado de `LocalPath`). `LocalPath` é o destino local do download ou a
origem local do upload; a pasta de destino é obtida com `fileparts(LocalPath)`.
O gerenciador usa a fábrica injetada em `TransferFactory` e oferece
`restoreInterruptedTransfers()` para restaurar transferências elegíveis.

No contrato de upload, o gerenciador exige um arquivo de origem existente e regular,
aplica `MaxUploadBytes` (padrão: 200 MiB; excesso gera
`datatransfer:TransferManager:uploadTooLarge`), valida `FormFieldName` e os nomes
dos campos adicionais e sanitiza o nome remoto `FileName`. Isso não implementa
transporte de upload: ainda não há processador, adaptador ou interface de upload.

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
do gerenciador, não ao comportamento de inferência de URL ou do downloader. Tarefas silenciosas retêm o
mesmo ciclo de vida, callbacks do downloader, limpeza e callbacks de conclusão/erro,
mas seus snapshots e notificações de reordenação são omitidos da apresentação por
padrão. Uma solicitação normal que corresponda a uma tarefa silenciosa existente promove essa
tarefa à apresentação normal. A correspondência duplicada usa URL exata e
nome de arquivo insensível a maiúsculas e minúsculas, independentemente da pasta de destino e modo de exibição.
Defina `IncludeSilentTasks` no `TransferManager` para incluir snapshots de tarefas
silenciosas na pasta de destino e avatar sem alterar o contrato do downloader.

O vocabulário do ciclo de vida é autoritativo:

- `pause` interrompe a transferência enquanto preserva o estado temporário retomável;
- `resume` continua a transferência pausada sem adicionar um novo timestamp de tentativa;
- `cancel` interrompe a transferência, remove arquivos temporários com escopo de tarefa e a entrada
    do histórico, e deixa qualquer arquivo de destino concluído intacto;
- `restart` descarta o estado parcial antes de começar novamente;
- conflitos de destino usam `keep`, `restart` e `cancel`;
- conflitos de arquivo parcial usam `resume`, `restart` e `cancel`.

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
como conflito parcial com `Continue`, `Restart` e `Cancel`, sem iniciar o download
até uma escolha. A interface atual continua limitada a downloads.

O painel traduz as ações do usuário em comandos do gerenciador e renderiza snapshots.
O estado da tarefa tem um único proprietário: o gerenciador possui o estado de transferência, enquanto o painel possui
apenas manipuladores da interface do usuário e estado de apresentação.

Quando um conflito de arquivo de destino ou parcial é detectado com a
política correspondente definida como `askInRow`, o gerenciador emite um snapshot pendente. O painel
renderiza as opções de linha apropriadas sem abrir um diálogo modal:
`Keep`, `Restart` e `Cancel` para conflitos de destino, ou `Continue`, `Restart`
e `Cancel` para arquivos parciais. Manter um destino registra uma tentativa concluída disponível
sem iniciar uma transferência. Reiniciar substitui explicitamente o destino.
Excluir uma linha concluída remove seu histórico e arquivos temporários restantes, mas
não exclui o arquivo de destino. O gerenciador verifica novamente o destino antes da
publicação.

### Limite do adaptador

Os auxiliares genéricos usam argumentos de solicitação normalizados e um `requestContext` fornecido pelo provedor.
Para transferências autenticadas pelo F5, `ws.auth.FileTransfer`
fornece o contexto e invoca `@datatransfer.downloadFileWorker`. O worker genérico
não inspeciona cookies ou conhece `F5Session`; há uma implementação de worker
neste pacote neutro em relação ao provedor.

Nenhum pacote chama a implementação concreta de outro provedor. A
solicitação normalizada e o `requestContext` do provedor são os únicos limites de transferência
entre serviços genéricos e adaptadores de autenticação.

### Política de namespace e erro

Todos os chamadores do repositório usam `datatransfer.*` para auxiliares genéricos, incluindo
`datatransfer.transferFileName`, `datatransfer.downloadSourceMetadata`,
`datatransfer.sendHTTPRequest` e `@datatransfer.downloadFileWorker`.

Erros genéricos usam o namespace `datatransfer:*`. Erros do adaptador F5 usam
`ws:auth:*`, e erros do painel usam `ui:TransferPanel:*`. Implementações `ui.download*` antigas
não são mantidas como wrappers duplicados permanentes.

### Caminho, empacotamento e validação

Adicione `src/General` ao caminho do MATLAB para que `ui.*` e `datatransfer.*` resolvam como
pacotes irmãos. Não adicione a pasta de nenhum pacote diretamente. Os arquivos de código
`+datatransfer` são dependências de código regulares. Aplicações que usam `ui.TransferPanel`
devem incluir `pingTransferAvatar.html` explicitamente como um arquivo adicional;
`profileAvatar.html` permanece em `+ws/+auth`. Inclua
`orbitDownloadAvatar.html` apenas quando uma aplicação usar essa alternativa opcional.
