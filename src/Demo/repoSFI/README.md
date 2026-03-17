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
  Versão: 0.2.0 | Release: R2024a
  Iniciado: 17/03/2026 14:30:45
========================================================================

[...]
STATUS: Servidor aguardando requisições...
```

### Enviar Requisição de Cliente

```matlab
% Usar test/socketClient.m
socketClient.sendRequest(struct('type', 'Diagnostic'))

% Ou via socket direto:
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
│   ├── socketClient.m              Cliente de teste
│   ├── test_celplan.m
│   └── test_rfeye.m
└── wsSpectrumReader/               Projeto compilação .exe
    └── wsSpectrumReader.prj
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
    "version": "0.2.0",
    "release": "R2024a"
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
cd src/wsSpectrumReader/
mcc -m wsSpectrumReader.prj
```

Gera executável em:

```
src/wsSpectrumReader/application/
  ├── wsSpectrumReader.exe
  ├── MCRInstaller.exe           (Runtime MATLAB)
  └── ...
```

### Executar

```bash
cd application
wsSpectrumReader.exe
```

---

## Resolução de Problemas

### "Porta 8910 já em uso"

```matlab
% portRelease() é chamado automaticamente
% Se ainda houver problema, liberar manualmente:
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

---

## Referências

### Módulos Principais

- [+server/MessageValidator.m](./src/+server/MessageValidator.m) - Validação de requisições
- [+server/ServerLogger.m](./src/+server/ServerLogger.m) - Gerenciamento de log
- [+handlers/RequestFactory.m](./src/+handlers/RequestFactory.m) - Factory pattern
- [+handlers/DiagnosticHandler.m](./src/+handlers/DiagnosticHandler.m) - Handler Diagnostic
- [+handlers/FileReadHandler.m](./src/+handlers/FileReadHandler.m) - Handler FileRead

---

## Licença

MIT License - veja [LICENSE](../../../LICENSE)

---

## Desenvolvido com dedicação

Versão: 0.2.0  
Release: R2024a  
Última atualização: 17/03/2026



