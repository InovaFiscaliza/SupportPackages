%% 
%clear all
close all
clc

% Adiciona diretório anterior com as libs
addpath("../")
addpath("../config")

tcpServer = tcpServerLib();


% Arquivo Matlab antigo
testFile = "C:\Celplan\Verificar Posição\p-4f54433e--appColeta_260701_T203552_ID4_1.bin";
% Processamento
specData = handlers.FileReadHandler.readFile(testFile,'SingleFile');

% Export Mat
fullMatPath = handlers.FileReadHandler.exportMatFile(specData,testFile);

% Json Output
json = handlers.FileReadHandler.buildMetadataResponse(specData,fullMatPath);
json = jsonencode(json);


