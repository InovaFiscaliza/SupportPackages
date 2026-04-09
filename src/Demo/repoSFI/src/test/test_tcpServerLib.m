clear all
close all
clc

% Adiciona diretório anterior com as libs
addpath("../")
addpath("../config")

% Cria objeto do servidor
tcpServerLib = tcpServerLib();

% Caminho do arquivo de teste
%testFile = "C:\appColeta\Combo7.appColeta.-.DT.Level.zip";
%testFile = "C:\Celplan\CWSM22010038_E11_A1_Spec Frq=1940.000 Span=460.000 RBW=100.00000_[2025-08-24-14-13-17]_[2025-08-27-02-14-18]_9_DONE.zip";
%testFile = "C:\Celplan\CWSM21100012_E16_A1_Spec Frq=1588.500 Span=117.000 RBW=100.00000_[2026-02-14-13-28-27]_[2026-02-14-11-45-42]_1_DONE.zip";
%testFile = "C:\ERMx\appColeta_251231_T164605_ID1_1.bin";
%testFile = "C:\Celplan\CWSM21100004_E16_A1_Spec Frq=1588.500 Span=117.000 RBW=100.00000_[2025-02-28-17-54-41]_[2025-03-18-10-27-34]_1_DONE.zip";
%testFile = "C:\Celplan\CWSM21100004_E17_A1_Spec Frq=2795.000 Span=210.000 RBW=100.00000_[2025-03-07-05-56-08]_[2025-03-18-10-27-36]_2_DONE.zip";
%testFile = "C:\Celplan\2025_02\CWSM21100001_E1_A1_Spec Frq=71.000 Span=34.000 RBW=100.00000 [2025-01-31,20-18-51-635-2008].dBm";
%testFile = "C:\RFeye\p-4d2c95e5--rfeye002106_251210_T144800.bin";
%testFile = "C:\appColeta\p-febda2cc--appColeta_250628_T122251_ID4_1.bin";
%testFile = "C:\Celplan\CWSM21100004_E17_A1_Spec Frq=2795.000 Span=210.000 RBW=100.00000 [2025-03-10,05-55-41-305-6927].dBm";
testFile = "C:\Celplan\CWSM21100022_E21_A1_Spec Frq=1413.500 Span=27.000 RBW=100.00000_[2024-11-01-08-13-06]_[2024-11-14-08-34-23]_1_DONE.zip";
testFile = fullfile(testFile);

% Processamento
specData = handlers.FileReadHandler.readFile(testFile,'SingleFile');

% Export Mat
fullMatPath = handlers.FileReadHandler.exportMatFile(specData,testFile);

% Json Output
json = handlers.FileReadHandler.buildMetadataResponse(specData,fullMatPath,tcpServerLib.General);
json = jsonencode(json);


