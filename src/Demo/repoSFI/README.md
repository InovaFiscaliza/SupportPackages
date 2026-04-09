# repoSFI - Servidor TCP de Processamento Distribuído

Processamento distribuído de dados RF/Espectro via socket TCP

Servidor MATLAB que recebe requisições JSON via TCP, processa dados de espectro e retorna respostas estruturadas. Compilável como executável `.exe` para produção.

---

## Início Rápido

### Iniciar Servidor

```matlab
cd src/
main()
```

Você verá:

```
========================================================================
  SERVIDOR TCP - repoSFI
  Processamento Distribuido de RF/Espectro
  Versão: <appVersion> | Release: <appRelease>
  Iniciado: 17/03/2026 14:30:45
========================================================================

[...]
STATUS: Servidor aguardando requisições...
```

### Enviar Requisição de Cliente

```matlab
% Exemplo via socket direto:
client = tcpclient('localhost', 8910);
msg = struct('Key', '123456', 'ClientName', 'Matlab', ...
    'Request', struct('type', 'Diagnostic'));
writeline(client, jsonencode(msg))
```

---

## Arquitetura

### Visão Geral

```
Cliente TCP (Zabbix, Jupyter, MATLAB)
           | (JSON via socket)
    tcpServerLib (Orquestrador)
           |
    MessageValidator (Valida estrutura, autenticação, autorização)
           |
    RequestFactory (Factory Pattern)
      /         \
  DiagnosticHandler    FileReadHandler
           |              |
      (Processa)    (Processa)
           \         /
    ServerLogger (Registra)
           |
    Cliente (JSON encapsulado)
```

### Estrutura de Diretórios

```
src/
├── main.m                          Entry point com interface visual
├── tcpServerLib.m                  Orquestrador principal (refatorado)
├── config/
│   └── GeneralSettings.json        Configurações centralizadas
├── +class/
│   └── Constants.m                 Versão, release, constantes
├── +util/
│   └── portRelease.m               Libera portas em uso (Windows)
├── +server/                        [NOVO] Módulo servidor
│   ├── MessageValidator.m          Valida mensagens JSON
│   └── ServerLogger.m              Gerencia logging
├── +handlers/                      [NOVO] Handlers de requisição
│   ├── RequestFactory.m            Factory pattern
│   ├── DiagnosticHandler.m         Processa 'Diagnostic'
│   └── FileReadHandler.m           Processa 'FileRead'
├── test/
│   └── test_tcpServerLib.m         Script manual de teste
├── wsSpectrumReader/               Artefatos de compilação
└── wsSpectrumReader.prj            Projeto de build do executável
```

Observacao: a arvore acima preserva a organizacao conceitual do projeto.
A estrutura real logo abaixo reflete os caminhos e arquivos atuais do repositorio.

Estrutura real atual:

```text
src/
|-- main.m
|-- tcpServerLib.m
|-- wsSpectrumReader.prj
|-- config/
|   `-- GeneralSettings.json
|-- +class/
|   `-- Constants.m
|-- +util/
|   `-- portRelease.m
|-- +server/
|   |-- MessageValidator.m
|   |-- RuntimeLog.m
|   `-- ServerLogger.m
|-- +handlers/
|   |-- RequestFactory.m
|   |-- DiagnosticHandler.m
|   |-- FileReadHandler.m
|   `-- +internal/
|       `-- ProtectedCellPlanDBM.m
|-- test/
|   `-- test_tcpServerLib.m
`-- wsSpectrumReader/
    |-- for_testing/
    `-- for_redistribution/
```

---

## Protocolo de Comunicação

### Formato da Requisição

Cliente envia JSON com três campos obrigatórios:

```json
{
  "Key": "123456",                    // Autenticação
  "ClientName": "Matlab",              // Identificação do cliente
  "Request": {
    "type": "Diagnostic"               // Tipo de requisição
    // ... campos específicos do tipo
  }
}
```

Servidor responde:

```json
{
  "<JSON>" + {
    "Request": {
      "type": "Diagnostic"
    },
    "Answer": {
      "App": { "name": "repoSFI", ... },
      "EnvVariables": [...],
      "SystemInfo": [...]
    }
  } + "</JSON>"
}
```

### Tipos de Requisição

#### 1. Diagnostic - Diagnóstico do Sistema

Retorna informações de ambiente, SO, hardware.

**Request:**

```json
{
  "Key": "123456",
  "ClientName": "Zabbix",
  "Request": {
    "type": "Diagnostic"
  }
}
```

**Answer:**

```json
{
  "App": {
    "name": "repoSFI",
    "version": "<appVersion>",
    "release": "<appRelease>"
  },
  "EnvVariables": [
    {"env": "COMPUTERNAME", "value": "WIMATLABPDIN01"},
    ...
  ],
  "SystemInfo": [
    {"parameter": "HostName", "value": "..."},
    ...
  ],
  "LogicalDisk": [
    {"DeviceID": "C:", "FileSystem": "NTFS", ...}
  ]
}
```

#### 2. FileRead - Leitura de Espectro

Lê arquivo de espectro, opcionalmente exporta para .mat.

Comportamento operacional atual do `FileRead`:

- Arquivos `.zip` sao lidos de forma tolerante, membro a membro.
- Um membro invalido nao derruba a requisicao inteira se ainda houver outros arquivos legiveis no ZIP.
- Arquivos `.dbm` passam por um wrapper protegido para evitar que o `CellPlan_dBmReader.exe` deixe o servico preso em popup modal ou sem resposta.
- O parser interno continua equivalente ao fluxo legado; a mudanca principal esta na supervisao do processo externo e no tratamento gracioso de falhas.
- Cada instancia do `repoSFI` processa uma requisicao por vez. Se um `FileRead` estiver lendo um ZIP grande, a conexao atual permanece aberta ate o fim do processamento.
- ZIPs com muitos arquivos pequenos, especialmente `.dbm` da Celplan, podem aumentar bastante o tempo total por requisicao porque a leitura e feita membro a membro.
- Timeout do cliente Python durante um ZIP grande nao significa, por si so, que a porta caiu. Em geral isso indica que o cliente desistiu antes da resposta final.

**Request:**

```json
{
  "Key": "123456",
  "ClientName": "Jupyter",
  "Request": {
    "type": "FileRead",
    "filepath": "/mnt/reposfi/espectro.zip",
    "export": true                    // [opcional] exporta .mat
  }
}
```

**Answer:**

```json
{
  "General": {
    "FilePath": "/mnt/reposfi",
    "FileName": "espectro.zip",
    "Extension": ".zip"
  },
  "Spectra": [
    {
      "Frequency": [...],
      "Power": [...],
      "FrequencyCenter": 2400e6,
      ...
    }
  ]
}
```

---

## Configuração

### `config/GeneralSettings.json`

```json
{
  "version": 0.12,
  
  "tcpServer": {
    "IP": "",                         // "" = 0.0.0.0 (todas as interfaces)
    "Port": 8910,                     // Porta de escuta
    "Key": "123456",                  // Chave de autenticação
    "ClientList": [                   // Whitelist de clientes
      "Zabbix",
      "Jupyter",
      "Matlab"
    ],
    "Repo":"Z:",                      // Caminho MATLAB para repositório
    "Repo_map":"/mnt/reposfi"         // Mapeamento RF.Fusion
  },
  
  "operationMode": {
    "Debug": false,
    "Dock": true,
    "Simulation": false
  }
}
```

### Variáveis Importantes

| Variável | Significado | Exemplo |
|----------|-------------|----------|
| `IP` | Interface de escuta | `""` (todas) ou `"127.0.0.1"` |
| `Port` | Porta TCP | `8910` |
| `Key` | Chave de segurança | `"123456"` |
| `ClientList` | Clientes autorizados | `["Zabbix", "Jupyter"]` |
| `Repo` | Caminho MATLAB | `"Z:"` |
| `Repo_map` | Mapeamento RF.Fusion | `"/mnt/reposfi"` |

### Variaveis de ambiente opcionais

| Variavel | Significado | Padrao |
|----------|-------------|--------|
| `REPOSFI_CELLPLAN_TIMEOUT_SECONDS` | Timeout, em segundos, para o `CellPlan_dBmReader.exe` | `30` |
| `REPOSFI_VERBOSE_READ_LOGS` | Habilita logs detalhados do pipeline de leitura (`1`, `true`, `on`, `yes`) | desabilitado |

### Intervalos internos de runtime

Os intervalos abaixo sao internos do servico e hoje nao sao configurados por variavel de ambiente:

| Item | Valor atual | Finalidade |
|------|-------------|------------|
| Heartbeat de runtime | `60 s` | Registrar que o processo principal continua vivo |
| Watchdog de listener/timer | `15 s` | Detectar estado "processo vivo, porta morta" e tentar recuperacao |
| Timer de reconexao TCP | `300 s` | Reaplicar tentativa de conexao/reconexao do listener |

---

## Segurança

### Autenticação

✓ Chave obrigatória configurada em `GeneralSettings.json`

```matlab
% Validado automaticamente em MessageValidator
if ~strcmp(decodedMsg.Key, obj.General.tcpServer.Key)
    error(...'Incorrect key'...)
end
```

### Autorização

✓ Whitelist de clientes (se configurado)

```matlab
% Se ClientList não vazio, cliente deve estar na lista
if ~isempty(clientList) && ~ismember(clientName, clientList)
    error(...'Unauthorized client'...)
end
```

### Boas Práticas

- Altere `Key` em produção
- Configure `ClientList` com clientes esperados
- Use TLS/SSL em produção (considerar futura melhoria)

---

## Logging

### Log persistente de runtime

Diagnosticos do processo principal, callbacks, timers e protecoes de leitura sao gravados em:

```text
C:\ProgramData\ANATEL\repoSFI\logs\repoSFI-runtime.log
```

Por padrao, o caminho feliz do `FileRead` usa menos logs para reduzir overhead.
Quando for necessario diagnosticar uma leitura em detalhe, habilite:

```powershell
$env:REPOSFI_VERBOSE_READ_LOGS='1'
```

Com isso, o servico volta a registrar as etapas intermediarias da validacao de arquivo,
leitura protegida de ZIP/DBM e agregacao dos membros do ZIP.

### Heartbeat e watchdog

O runtime log tambem registra sinais de saude do processo:

- `Heartbeat | {...}`: snapshot periodico de saude do listener, timer e request atual.
- `tcpServerLib.Watchdog`: mudancas de saude, tentativas de recuperacao do listener e avisos de requisicao longa.
- `CurrentRequest` e `CurrentRequestAgeSeconds`: ajudam a distinguir "processando devagar" de "listener caiu".

Na pratica:

- Se o processo continuar vivo, mas a porta parar de aceitar conexoes, o watchdog tenta recriar o listener/timer.
- Se uma request ficar muito tempo ativa, o watchdog registra avisos periodicos sem abortar a operacao.
- Se o processo travar de verdade, o ultimo heartbeat ajuda a delimitar quando ele deixou de responder.

### Acessar histórico de requisições

```matlab
% A partir do servidor em execução
logTable = server.getLog()              % Tabela completa
count = server.getLogCount()            % Número de transações
lastEntries = server.Logger.getLastEntries(10)  % Últimas 10
```

### Colunas do Log

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `Timestamp` | string | Data/hora da requisição |
| `ClientAddress` | string | IP do cliente |
| `ClientPort` | double | Porta do cliente |
| `Message` | string | Mensagem raw recebida |
| `ClientName` | string | Nome do cliente |
| `Request` | string | Request JSON |
| `NumBytesWritten` | double | Bytes enviados |
| `Status` | string | `'success'` ou mensagem de erro |

### Exemplo de Log

```
Timestamp           ClientAddress  ClientPort  Client    Status
17/03/2026 14:30:45 192.168.1.100  49152       Jupyter   success
17/03/2026 14:35:22 192.168.1.100  49153       Zabbix    Incorrect key
17/03/2026 14:40:10 192.168.1.100  49154       Matlab    success
```

---

## Compilação para .exe

### Usar `wsSpectrumReader.prj`

```matlab
% No MATLAB
cd src
mcc -m wsSpectrumReader.prj
```

Historico de build antigo:

```
src/wsSpectrumReader/application/
  - layout antigo, mantido aqui apenas como referencia historica
```

### Executar

```bash
cd src/wsSpectrumReader/for_testing
repoSFI.exe
```

Observacao: no projeto atual (`wsSpectrumReader.prj`), os artefatos principais sao gerados em:

```text
src/wsSpectrumReader/for_testing/repoSFI.exe
src/wsSpectrumReader/for_redistribution/
```

Para teste local do build, use:

```bash
cd src/wsSpectrumReader/for_testing
repoSFI.exe
```

---

## Resolução de Problemas

### "Porta 8910 já em uso"

```matlab
% Utilitario manual; nao e chamado automaticamente no startup atual:
util.portRelease(8910)
```

### "Arquivo GeneralSettings.json não encontrado"

✓ Copia automaticamente de `config/GeneralSettings.json` para `ProgramData` na primeira execução

### "Cliente não autorizado"

✓ Verificar:

1. `Key` está correto
2. `ClientName` está em `ClientList` em `GeneralSettings.json`

### Servidor não se conecta

✓ Verificar:

1. Porta não bloqueada por firewall
2. IP configurado corretamente
3. Outro servidor não está rodando na mesma porta

### Processo aparece no Windows, mas a porta recusa conexoes

Isso normalmente indica degradacao do listener TCP, nao necessariamente queda completa do processo.

Verificar no arquivo:

```text
C:\ProgramData\ANATEL\repoSFI\logs\repoSFI-runtime.log
```

Procurar por:

- `Heartbeat |`
- `tcpServerLib.Watchdog`
- `tcpServerLib.ConnectAttempt`
- `tcpServerLib.TimerError`
- `tcpServerLib.sendMessageToClient`

Se houver heartbeat recente com `ServerValid=false`, `ServerConnected=false`, `TimerValid=false` ou `TimerRunning="off"`, o processo esta vivo mas a infraestrutura TCP degradou.

### Cliente Python da timeout em ZIP grande

Quando o `FileRead` recebe um ZIP com muitos arquivos pequenos, o processamento pode levar bem mais tempo do que uma leitura simples.

Nesses casos:

1. O `repoSFI` continua processando a request atual de forma sincrona.
2. A conexao pode permanecer aberta ate a resposta final.
3. O cliente pode expirar antes da resposta se o timeout dele for curto.

Para diagnosticar, compare:

- o timeout configurado no cliente Python
- o `CurrentRequestAgeSeconds` no heartbeat
- os logs de `handlers.FileReadHandler.handle` e `handlers.FileReadHandler.readZipFileTolerant`

---

## Referências

### Módulos Principais

- [+server/MessageValidator.m](./src/+server/MessageValidator.m) - Validação de requisições
- [+server/ServerLogger.m](./src/+server/ServerLogger.m) - Gerenciamento de log
- [+server/RuntimeLog.m](./src/+server/RuntimeLog.m) - Log persistente de runtime
- [+handlers/RequestFactory.m](./src/+handlers/RequestFactory.m) - Factory pattern
- [+handlers/DiagnosticHandler.m](./src/+handlers/DiagnosticHandler.m) - Handler Diagnostic
- [+handlers/FileReadHandler.m](./src/+handlers/FileReadHandler.m) - Handler FileRead
- [+handlers/+internal/ProtectedCellPlanDBM.m](./src/+handlers/+internal/ProtectedCellPlanDBM.m) - Wrapper protegido para `.dbm` da Celplan
- [tcpServerLib.m](./src/tcpServerLib.m) - Listener TCP, watchdog e auto-recuperacao
- [main.m](./src/main.m) - Entry-point, lock global, heartbeat e loop principal

---

## Licença

MIT License - veja [LICENSE](../../../LICENSE)

---

## Estado da Documentacao

Release base do ambiente: `R2024a`  
Ultima atualizacao deste README: `07/04/2026`  
Observacao: a versao funcional do app e a versao do pacote compilado podem divergir entre `src/+class/Constants.m` e `src/wsSpectrumReader.prj`; por isso os exemplos usam placeholders como `<appVersion>`.



