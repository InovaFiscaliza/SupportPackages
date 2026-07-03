%% 
clear all
close all
clc

% Adiciona diretório anterior com as libs
addpath("../")
addpath("../config")

tcpServer = tcpServerLib();


% Caminho do arquivo de teste

%testFile = "C:\Celplan Exemplos Quebrados\_E3_A1_Mean Frq=92.000 Span=32.000 RBW=1.000_[2022-12-12-14-34-13]_[2022-12-12-14-34-13]_1_DONE.zip";
%testFile = "C:\Celplan Exemplos Quebrados\CWSM2110021_E1_Arquivo_Bom.zip";
%testFile = "C:\Celplan Exemplos Quebrados\CWSM21100031_E11_A1_Spec Frq=1940.000 Span=460.000 RBW=100.00000_[2026-06-27-13-51-27]_[2026-06-30-01-51-46]_10_DONE.zip";

% Arquivo quebrado
testFile = "C:\Celplan Exemplos Quebrados\CWSM21100006_E3_A1_Mean Frq=92.000 Span=32.000 RBW=1.000_[2022-12-07-10-30-52]_[2022-12-08-11-15-04]_1_DONE.zip";
%testFile = "C:\Celplan Exemplos Quebrados\CWSM21100006_E3_A1_Mean Frq=92.000 Span=32.000 RBW=1.000 [2022-12-07,10-30-52-570-0673].dBm";
%testFile = "C:\Celplan Exemplos Quebrados\CWSM21100006_E3_A1_Mean Frq=92.000 Span=32.000 RBW=1.000 [2022-12-07,10-41-16-466-0300].dBm";
%testFile = "C:\Celplan Exemplos Quebrados\Arquivo corrompido.dBm";
%testFile = "C:\Celplan Exemplos Quebrados\CWSM21100006_E18_A1_Spec Frq=1150.000 Span=100.000 RBW=100.00000_[2024-08-31-07-50-04]_[2024-09-12-07-50-33]_1_DONE.zip";
%testFile = "C:\Celplan Exemplos Quebrados\CWSM21100019_E6_A1_Spec Frq=122.500 Span=29.000 RBW=25.00000_[2025-09-22-05-46-27]_[2025-09-30-04-46-30]_3_DONE.zip";

% Processamento
specData = handlers.FileReadHandler.readFile(testFile,'SingleFile');

% Export Mat
fullMatPath = handlers.FileReadHandler.exportMatFile(specData,testFile);

% Json Output
json = handlers.FileReadHandler.buildMetadataResponse(specData,fullMatPath);
json = jsonencode(json);


