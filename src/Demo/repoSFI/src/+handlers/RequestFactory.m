classdef RequestFactory
    % RequestFactory - Ponto unico de roteamento do protocolo.
    %
    % Esta classe existe para separar duas responsabilidades que, embora
    % proximas, nao sao a mesma coisa:
    %   - tcpServerLib cuida de transporte TCP, validacao e resposta
    %   - RequestFactory decide qual handler atende cada Request
    %
    % A vantagem dessa camada pequena e manter o catalogo de operacoes
    % publicadas em um lugar so. Quando um novo tipo de Request e exposto
    % para o cliente, a entrada dele deve aparecer aqui.
    %
    % Em outras palavras, o RequestFactory justifica sua existencia porque:
    %   - evita if/switch de negocio espalhados dentro do tcpServerLib
    %   - deixa explicito o conjunto de Requests suportados externamente
    %   - concentra o ponto de extensao para novos handlers
    %   - facilita teste e manutencao do protocolo

    methods (Static)
        %------------------------------------------------------------------
        % Processa requisicao baseada no tipo
        %------------------------------------------------------------------
        % Este metodo recebe um requestType ja validado pelo transporte e
        % delega o trabalho para o handler correspondente. O switch abaixo
        % e pequeno de proposito: ele mostra exatamente quais operacoes o
        % servidor publica para fora.
        function answer = process(requestType, requestData, generalSettings)
            arguments
                requestType (1,:) string
                requestData (1,1) struct
                generalSettings (1,1) struct
            end

            % Normalizamos para lower(...) para que o protocolo nao dependa
            % de variacoes de caixa vindas do cliente.
            switch lower(requestType)
                case 'diagnostic'
                    % Handler sem dependencia de requestData; serve para
                    % diagnostico simples e health checks do cliente.
                    answer = handlers.DiagnosticHandler.handle();

                case 'fileread'
                    % Handler mais pesado, que recebe os parametros do
                    % request e tambem o contexto geral do servidor.
                    answer = handlers.FileReadHandler.handle(requestData, generalSettings);

                otherwise
                    % Fail fast para requests desconhecidos: e melhor
                    % responder erro explicito do que deixar o protocolo
                    % falhar de forma silenciosa ou ambigua.
                    error('handlers:RequestFactory:UnknownRequestType', ...
                        sprintf('Unknown request type: "%s"', requestType))
            end
        end
    end
end
