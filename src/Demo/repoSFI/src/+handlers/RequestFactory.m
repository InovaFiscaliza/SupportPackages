classdef RequestFactory
    % RequestFactory - Factory pattern para distribuir requisições
    %
    % Mapeia tipos de requisição para seus respectivos handlers
    
    methods (Static)
        %------------------------------------------------------------------
        % Processa requisição baseada no tipo
        %------------------------------------------------------------------
        function answer = process(requestType, requestData, generalSettings)
            arguments
                requestType (1,:) string
                requestData (1,1) struct
                generalSettings (1,1) struct
            end
            
            switch lower(requestType)
                case 'diagnostic'
                    answer = handlers.DiagnosticHandler.handle();
                    
                case 'fileread'
                    answer = handlers.FileReadHandler.handle(requestData, generalSettings);
                    
                otherwise
                    error('handlers:RequestFactory:UnknownRequestType', ...
                        sprintf('Unknown request type: "%s"', requestType))
            end
        end
    end
end
