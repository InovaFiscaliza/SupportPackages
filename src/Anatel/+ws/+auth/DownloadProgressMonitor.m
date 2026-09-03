classdef DownloadProgressMonitor < matlab.net.http.ProgressMonitor

    % ws.auth.DownloadProgressMonitor
    % Reporta o andamento da transferência ao chamador de ws.auth.F5Session,
    % que decide como exibi-lo.
    %
    % "Max" é o total esperado, obtido do cabeçalho Content-Length. Fica vazio
    % quando o servidor usa transferência chunked - nesse caso só há como
    % informar o total já recebido.

    properties
        Direction matlab.net.http.MessageType
        Value     uint64
        Callback  function_handle
    end

    methods
        %-----------------------------------------------------------------%
        function obj = DownloadProgressMonitor(callback)
            arguments
                callback (1,1) function_handle
            end

            obj.Interval = 0.25;
            obj.Callback = callback;
        end

        %-----------------------------------------------------------------%
        function done(~)
        end

        %-----------------------------------------------------------------%
        function set.Direction(obj, direction)
            obj.Direction = direction;
        end

        %-----------------------------------------------------------------%
        function set.Value(obj, value)
            obj.Value = value;
            notifyCaller(obj)
        end
    end


    methods (Access = private)
        %-----------------------------------------------------------------%
        function notifyCaller(obj)
            if isempty(obj.Direction) || obj.Direction ~= matlab.net.http.MessageType.Response
                return
            end

            try
                obj.Callback(double(obj.Value), double(obj.Max))
            catch
            end
        end
    end

end
