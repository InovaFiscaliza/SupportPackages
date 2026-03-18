classdef (Abstract) Constants
    % Constants - Identificadores estaticos do aplicativo repoSFI.
    %
    % Esta classe centraliza os metadados basicos usados pelo servidor
    % para identificacao, exibicao de banner, logs e empacotamento.

    properties (Constant)
        %-----------------------------------------------------------------%
        % Nome logico da aplicacao e usado em paths e configuracoes.
        appName    = 'repoSFI'
        % Release do MATLAB utilizada para o build do pacote.
        appRelease = 'R2024a'
        % Versao funcional do aplicativo/servidor.
        appVersion = '0.1.0'
    end
    
end
