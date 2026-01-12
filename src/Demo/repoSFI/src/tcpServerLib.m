classdef tcpServerLib < handle

    properties (Access = public)
        %-----------------------------------------------------------------%
        Server
        
        RootFolder
        General
        
        % Armazenado em "Timer" um handle para um objeto timer, o qual tem
        % como objetivo avaliar o status do servidor, realizando tentativa 
        % de reconexão, caso aplicável.
        Timer
        
        Time
        LOG = table( ...
            'Size', [0, 8], ...
            'VariableTypes', {'string', 'string', 'double', 'string', 'string', 'string', 'double', 'string'}, ...
            'VariableNames', {'Timestamp', 'ClientAddress', 'ClientPort', 'Message', 'ClientName', 'Request', 'NumBytesWritten', 'Status'} ...
        );
    end


    properties (Constant)
        %-----------------------------------------------------------------%
        TimerPeriod = 300 % in seconds
    end


    methods (Access = public)
        %-----------------------------------------------------------------%
        function obj = tcpServerLib()
            appEngine.util.disableWarnings()

            obj.RootFolder = tcpServerLib.Path();
            GeneralSettingsRead(obj)
            
            TimerCreation(obj)
            obj.Time = datetime('now', 'Format', 'dd/MM/yyyy HH:mm:ss');
        end

        %-----------------------------------------------------------------%
        function delete(obj)
            stop(obj.Timer)
            delete(obj.Timer)
            
            if isa(obj.Server, 'tcpserver.internal.TCPServer') && isvalid(obj.Server)
                hTransport = struct(struct(struct(obj.Server).Client).ClientImpl).Transport;
                if hTransport.Connected
                    hTransport.disconnect()
                end

                delete(obj.Server)
            end
        end
    end


    methods (Access = protected)
        %-----------------------------------------------------------------%
        function GeneralSettingsRead(obj)
            appName = class.Constants.appName;
            rootFolder = obj.RootFolder;

            [generalSettings, msgWarning] = appEngine.util.generalSettingsLoad(appName, rootFolder);
            if ~isempty(msgWarning)
                warning(msgWarning)
            end

            obj.General = generalSettings;
        end

        %-----------------------------------------------------------------%
        function TimerCreation(obj)
            obj.Timer = timer( ...
                "ExecutionMode", "fixedSpacing", ...
                "BusyMode", "queue", ...
                "StartDelay", 0, ...
                "Period", obj.TimerPeriod, ...
                "TimerFcn", @obj.ConnectAttempt ...
            );

            start(obj.Timer)
        end

        %-----------------------------------------------------------------%
        function ConnectAttempt(obj, src, evt)
            ip = obj.General.tcpServer.IP;
            port = obj.General.tcpServer.Port;

            try
                if isa(obj.Server, 'tcpserver.internal.TCPServer') && isvalid(obj.Server)
                    % Obter o handle para o objeto de baixo nível da interface
                    % tcpserver - o "GenericTransport", o qual possui propriedade 
                    % indicando o status do socket ("Connected"), além de métodos 
                    % que possibilitam reconexão ("connect" e "disconnect").

                    hTransport = struct(struct(struct(obj.Server).Client).ClientImpl).Transport;
                    if ~hTransport.Connected
                        hTransport.connect()
                    end

                else
                    if ~isempty(obj.Server)
                        delete(obj.Server)
                        obj.Server = [];
                    end

                    util.portRelease(port)
    
                    if ~isempty(ip)
                        obj.Server = tcpserver(ip, port);
                    else
                        obj.Server = tcpserver(port);
                    end
                    
                    configureTerminator(obj.Server, "CR/LF")
                    configureCallback(obj.Server, "terminator", @(~,~)obj.receivedMessage)
                end

            catch
            end
        end

        %-----------------------------------------------------------------%
        function receivedMessage(obj)
            % O servidor se comunica com apenas um único cliente, negando tentativas 
            % de conexão de outros clientes enquanto estiver ativa a comunicação com 
            % o cliente (socket criado).
    
            % O cliente deve enviar uma mensagem textual encapsulada respeitando a 
            % sintaxe JSON e possuir as seguintes chaves: "Key", "ClientName" e "Request".
    
            % O trigger no servidor não é o número de bytes recebidos, mas a chegada 
            % do terminador "CR/LF", que o cliente deve embutir na sua requisição.
        
            % Caso o cliente seja criado no MATLAB, a comunicação pode se dar da 
            % seguinte forma:
            % - writeline(tcpClient, jsonencode(msg))
            % - write(tcpClient, sprintf('%s\r\n', jsonencode(msg)))

            while obj.Server.NumBytesAvailable
                rawMsg = readline(obj.Server);
                
                if ~isempty(rawMsg)
                    for ii = 1:numel(rawMsg)
                        try
                            decodedMsg = jsondecode(rawMsg{ii});
    
                            % Verifica se a mensagem apresenta apenas as chaves
                            % "Key", "ClientName" e "Request".
                            if ~all(ismember(fields(decodedMsg), {'Key', 'ClientName', 'Request'}))
                                error('tcpServerLib:WrongListOfFields', 'Wrong list of fields')
                            end
                            
                            % Verifica tipos de dados...
                            mustBeTextScalar(decodedMsg.Key)
                            mustBeTextScalar(decodedMsg.ClientName)

                            if ~isstruct(decodedMsg.Request) || ~isfield(decodedMsg.Request, 'type')
                                error('tcpServerLib:InvalidRequestFormat', 'The request must be a struct containing a field named "type".')
                            end
    
                            % Verifica se o cliente passou o valor correto de "Key".
                            % (configurado no arquivo "GeneralSettings.json")
                            if ~strcmp(decodedMsg.Key, obj.General.tcpServer.Key)
                                error('tcpServerLib:IncorrectKey', 'Incorrect key')
                            end
    
                            % Verifica se o nome do cliente está na lista de possíveis 
                            % nomes que o servidor se comunica.
                            % (configurado no arquivo "GeneralSettings.json")
                            if ~isempty(obj.General.tcpServer.ClientList) && ~ismember(decodedMsg.ClientName, obj.General.tcpServer.ClientList)
                                error('tcpServerLib:UnauthorizedClient', 'Unauthorized client')
                            end
            
                            % Requisições...
                            switch decodedMsg.Request.type
                                case 'Diagnostic'
                                    msg = tcpServerLib.Diagnostic();
                                case 'FileRead'
                                    msg = tcpServerLib.FileRead(decodedMsg.Request.filepath);
                                otherwise
                                    error('tcpServerLib:UnexpectedRequest', 'Unexpected request type')
                            end
    
                            sendMessageToClient(obj, struct('Request', decodedMsg.Request, 'Answer', msg))
                            logTableFill(obj, rawMsg, decodedMsg, 'success')
                            
                        catch ME
                            sendMessageToClient(obj, struct('Request', rawMsg{ii}, 'Answer', ME.identifier))
                            logTableFill(obj, rawMsg, rawMsg{ii}, ME.message)
                        end
                    end
    
                else
                    sendMessageToClient(obj, struct('Request', rawMsg, 'Answer', 'Invalid request'))
                    logTableFill(obj, rawMsg, '', 'tcpServerLib:EmptyRequest')
                end
            end
        end

        %-----------------------------------------------------------------%
        function sendMessageToClient(obj, structMsg)
            writeline(obj.Server, ['<JSON>' jsonencode(structMsg) '</JSON>'])
        end

        %-----------------------------------------------------------------%
        function logTableFill(obj, rawMsg, decodedMsg, statusMsg)
            if isfield(decodedMsg, 'ClientName')
                ClientName = decodedMsg.ClientName;
            else
                ClientName = '-';
            end

            if isfield(decodedMsg, 'Request')
                Request = jsonencode(decodedMsg.Request);
            else
                Request = '-';
            end

            obj.LOG(end+1,:) = {datestr(now),               ...
                                obj.Server.ClientAddress,   ...
                                obj.Server.ClientPort,      ...
                                rawMsg,                     ...
                                ClientName,                 ...
                                Request,                    ...
                                obj.Server.NumBytesWritten, ...
                                statusMsg};
        end
    end


    methods (Static = true)
        %-----------------------------------------------------------------%
        function path = Path()
            path = fileparts(mfilename('fullpath'));
        end

        %-----------------------------------------------------------------%
        function answer = Diagnostic()
            answer = struct( ...
                'App', struct( ...
                    'name', class.Constants.appName, ...
                    'release', class.Constants.appRelease,  ...
                    'version', class.Constants.appVersion ...
                ), ...
                'EnvVariables', [], ...
                'SystemInfo',   [], ...
                'LogicalDisk',  [] ...
            );

            % A seguir os campos que irão formar essa mensagem de diagnóstico
            % do appColeta.
            envFields = ["COMPUTERNAME", ...
                         "MATLAB_ARCH", ...
                         "MODEL", ...
                         "PROCESSOR_ARCHITECTURE", ...
                         "PROCESSOR_IDENTIFIER", ...
                         "PROCESSOR_LEVEL", ...
                         "SERIAL", ...
                         "TYPE2"];
            sysNames   = ["Host Name"                 ...                   % English values
                          "OS Name"                   ...
                          "OS Version"                ...
                          "Product ID"                ...
                          "Original Install Date"     ...
                          "System Boot Time"          ...
                          "System Manufacturer"       ...
                          "System Model"              ...
                          "System Type"               ...
                          "BIOS Version"              ...
                          "Total Physical Memory"     ...
                          "Available Physical Memory" ...
                          "Virtual Memory: Max Size"  ...
                          "Virtual Memory: Available" ...
                          "Virtual Memory: In Use"    ...
                          "Nome do host"                      ...           % Portuguese values
                          "Nome do sistema operacional"       ...
                          "Versão do sistema operacional"     ...
                          "Identificação do produto"          ...
                          "Data da instalação original"       ...
                          "Tempo de Inicialização do Sistema" ...
                          "Fabricante do sistema"             ...
                          "Modelo do sistema"                 ...
                          "Tipo de sistema"                   ...
                          "Versão do BIOS"                    ...
                          "Memória física total"              ...
                          "Memória física disponível"         ...
                          "Memória Virtual: Tamanho Máximo"   ...
                          "Memória Virtual: Disponível"       ...
                          "Memória Virtual: Em Uso"];
            sysValues  = repmat(replace(sysNames(1:15), {' ', ':'}, {'', ''}), [1 2]);
            sysDict    = dictionary(sysNames, sysValues);            
            discFields = "DeviceID,FileSystem,FreeSpace,Size";            
            
            % Environment variable
            envVariables = getenv();
            envKeys      = keys(envVariables, 'uniform');
            envValues    = values(envVariables, 'uniform');
            
            [~, idx1]  = ismember(envFields, envKeys);
            idx1(~idx1) = [];
            answer.EnvVariables = table(envKeys(idx1), envValues(idx1), 'VariableNames', {'env', 'value'});
            
            % System info (Prompt1)
            [status, cmdout] = system('systeminfo');
            if ~status
                try
                    cmdout = strtrim(splitlines(cmdout));
                    cmdout(cellfun(@(x) isempty(x), cmdout)) = [];
            
                    cmdout_Cell = cellfun(@(x) regexp(x, '(?<parameter>[A-Z]\D+)[:]\s+(?<value>.+)', 'names'), cmdout, 'UniformOutput', false);
                    systemInfo  = struct('parameter', {}, 'value', {});
                    
                    for ii = 1:numel(cmdout_Cell)
                        if ~isempty(cmdout_Cell{ii})
                            keyName = cmdout_Cell{ii}.parameter;
                            if isKey(sysDict, keyName)
                                systemInfo(end+1) = struct('parameter', sysDict(keyName), 'value', cmdout_Cell{ii}.value);
                            end
                        end
                    end
                    answer.SystemInfo = systemInfo;
                catch
                end
            end            
            
            % Disc info (Prompt2)
            [status, cmdout] = system("wmic LOGICALDISK get " + discFields);
            if ~status
                try
                    cmdout = strtrim(splitlines(cmdout));
                    cmdout(cellfun(@(x) isempty(x), cmdout)) = [];
            
                    answer.LogicalDisk = cellfun(@(x) regexp(x, '(?<DeviceID>[A-Z]:)\s+(?<FileSystem>\w+)\s+(?<FreeSpace>\d+)\s+(?<Size>\d+)', 'names'), cmdout(2:end));
                catch
                end
            end
        end

        %-----------------------------------------------------------------%
        function answer = FileRead(filepath)
            if ~isfile(filepath)
                error('tcpServerLib:FileNotFound', 'File does not exist')
            end

            specData = model.SpecDataBase.empty;
            specData = read(specData, filepath, 'MetaData');
            specData = copy(specData, {'FileMap'});

            for ii = 1:numel(specData)
                for jj = 1:height(specData(ii).RelatedFiles)
                    specData(ii).RelatedFiles.GPS{jj} = [];
                end
            end

            answer = specData;
        end
    end
end