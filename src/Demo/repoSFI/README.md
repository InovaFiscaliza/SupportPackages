# repoSFI

Servidor TCP em MATLAB para leitura distribuida de arquivos de espectro.

O `repoSFI` recebe mensagens JSON via socket TCP, processa arquivos remotos a partir de `/mnt/reposfi/...` e devolve respostas JSON estruturadas. O projeto tambem pode ser compilado como executavel para Windows.

## Visao geral do repositorio `src`

O diretorio [src](./src) concentra o servidor, a configuracao e o build.

```text
src/
|-- main.m
|-- tcpServerLib.m
|-- build_reposfi.m
|-- wsSpectrumReader.prj
|-- config/
|   `-- GeneralSettings.json
|-- +class/
|   `-- Constants.m
|-- +handlers/
|   |-- DiagnosticHandler.m
|   `-- FileReadHandler.m
|-- +server/
|   |-- MessageValidator.m
|   |-- RuntimeLog.m
|   |-- SSHHandler.m
|   `-- ServerLogger.m
|-- +util/
|   `-- portRelease.m
`-- test/
    `-- test_tcpServerLib.m
```

Descricao rapida:

- [main.m](./src/main.m): bootstrap minimo. Garante instancia unica, cria o servidor e mantem o processo vivo.
- [tcpServerLib.m](./src/tcpServerLib.m): nucleo do listener TCP. Carrega configuracao, recebe mensagens, valida requests e chama os handlers.
- [build_reposfi.m](./src/build_reposfi.m): script de build para MATLAB `2026a`.
- [config/GeneralSettings.json](./src/config/GeneralSettings.json): configuracao do listener TCP e do acesso SSH/SFTP.
- [+handlers](./src/+handlers): implementacao das requests `Diagnostic` e `FileRead`.
- [+server](./src/+server): infraestrutura de validacao, logging e SFTP.

## Como o `repoSFI` roda

O fluxo principal e este:

`main -> tcpServerLib -> MessageValidator -> DiagnosticHandler ou FileReadHandler`

No caso de `FileRead`, o caminho atual e:

`/mnt/reposfi/... -> download SFTP para tempdir/repoSFI -> leitura local -> exportacao local opcional -> upload remoto opcional`

Regras importantes:

- o `filepath` da request deve vir em `/mnt/reposfi/...`
- o `repoSFI` nao usa mais `\\reposfi\...` como caminho canonico
- a leitura remota usa SFTP nativo do MATLAB
- a pasta temporaria dedicada e `tempdir/repoSFI`
- a limpeza remove apenas a pasta temporaria da requisicao atual

## Como rodar no MATLAB

### Forma recomendada

```matlab
cd('C:\InovaFiscaliza\SupportPackages\src\Demo\repoSFI\src')
main()
```

Essa e a forma normal de subir o servidor. O `main`:

- imprime um banner curto
- impede segunda instancia na mesma maquina
- cria o `tcpServerLib`
- deixa o processo vivo ate interrupcao

### Subir o `tcpServerLib` diretamente

Para desenvolvimento e debug local, tambem da para instanciar o servidor direto:

```matlab
cd('C:\InovaFiscaliza\SupportPackages\src\Demo\repoSFI\src')
server = tcpServerLib();
```

Isso cria o listener e o timer de reconexao, mas aqui o ciclo de vida fica na sua mao. Para encerrar:

```matlab
delete(server)
clear server
```

Para uso normal, prefira `main()`.

## Exemplo de request

### Diagnostic

```matlab
client = tcpclient("localhost", 8910);
msg = struct( ...
    "Key", "123456", ...
    "ClientName", "Matlab", ...
    "Request", struct("type", "Diagnostic"));
writeline(client, jsonencode(msg))
```

### FileRead

```json
{
  "Key": "123456",
  "ClientName": "Jupyter",
  "Request": {
    "type": "FileRead",
    "filepath": "/mnt/reposfi/espectro.zip",
    "export": true
  }
}
```

Observacoes operacionais:

- o processamento e sincrono: uma requisicao por vez por instancia
- ZIPs grandes ou com muitos arquivos pequenos podem levar bastante tempo
- timeout do cliente nao implica, por si so, que o servidor caiu
- o health check mais confiavel e uma request `Diagnostic` com validacao da resposta JSON completa

## Configuracao

Arquivo: [src/config/GeneralSettings.json](./src/config/GeneralSettings.json)

Exemplo minimo:

```json
{
  "version": 0.21,
  "tcpServer": {
    "Status": 0,
    "IP": "",
    "Port": 8910,
    "Key": "123456",
    "SSH": {
      "Host": "172.16.18.11",
      "Port": 2828,
      "User": "root",
      "Password": "changeme",
      "TimeoutSeconds": 120
    },
    "ClientList": [
      "Zabbix",
      "Jupyter",
      "Matlab"
    ]
  }
}
```

Campos principais:

- `tcpServer.IP`: interface de escuta; `""` significa todas
- `tcpServer.Port`: porta TCP
- `tcpServer.Key`: chave de autenticacao
- `tcpServer.ClientList`: clientes autorizados
- `tcpServer.SSH.*`: acesso remoto via SFTP

## Build com `build_reposfi.m`

O script [build_reposfi.m](./src/build_reposfi.m) e hoje a forma mais direta de build no MATLAB `2026a`.

Ele faz tres coisas:

1. gera o executavel de teste em `wsSpectrumReader/for_testing`
2. gera o instalador em `wsSpectrumReader/for_redistribution`
3. recria uma pasta portavel em `wsSpectrumReader/for_redistribution_files_only`

### Como executar

```matlab
cd('C:\InovaFiscaliza\SupportPackages\src\Demo\repoSFI\src')
build_reposfi
```

### Saidas esperadas

```text
src/wsSpectrumReader/for_testing/repoSFI.exe
src/wsSpectrumReader/for_redistribution/
src/wsSpectrumReader/for_redistribution_files_only/
```

A pasta `for_redistribution_files_only` e reconstruida pelo proprio script a partir de `for_testing`, com copia adicional da pasta `config`.

### O que o script inclui

- `main.m` como entry-point
- `+class`, `+handlers`, `+server`, `+util`
- dependencias compartilhadas em `src/General`
- dependencias compartilhadas em `src/Spectrum`
- `config` como arquivo adicional do pacote

## Logging

O runtime log persistente fica em:

```text
C:\ProgramData\ANATEL\repoSFI\logs\repoSFI-runtime.log
```

Para diagnostico mais detalhado da leitura:

```powershell
$env:REPOSFI_VERBOSE_READ_LOGS='1'
```

## Troubleshooting

### Porta em uso

```matlab
util.portRelease(8910)
```

### Segunda instancia

O `main` usa um mutex global e nao deixa duas instancias ativas na mesma maquina.

### Cliente nao autorizado

Verificar:

1. `Key` correto
2. `ClientName` presente em `ClientList`

## Referencias

- [src/main.m](./src/main.m)
- [src/tcpServerLib.m](./src/tcpServerLib.m)
- [src/build_reposfi.m](./src/build_reposfi.m)
- [src/+handlers/FileReadHandler.m](./src/+handlers/FileReadHandler.m)
- [src/+handlers/DiagnosticHandler.m](./src/+handlers/DiagnosticHandler.m)
- [src/+server/SSHHandler.m](./src/+server/SSHHandler.m)
- [src/+server/RuntimeLog.m](./src/+server/RuntimeLog.m)
