classdef DownloadProgressMonitor < matlab.net.http.ProgressMonitor

    % ws.auth.DownloadProgressMonitor
    % Reports the transfer progress to the caller of ws.auth.F5Session,
    % which decides how to display it.
    %
    % "Max" is the expected total, obtained from the Content-Length header. It remains empty
    % when the server uses chunked transfer - in this case only the total already
    % received can be informed.

    properties
        % Direction Message type (Request or Response) for this progress monitor
        Direction matlab.net.http.MessageType
        % Value Current progress value in bytes
        Value     uint64
        % Callback Function handle to call with progress updates
        Callback  function_handle
    end

    methods
        %-----------------------------------------------------------------%
        function obj = DownloadProgressMonitor(callback)
            % DownloadProgressMonitor Constructor for the progress monitor
            %
            % Constructs a DownloadProgressMonitor object that reports progress
            % to the specified callback function.
            %
            % Input:
            %   callback - Function handle that will be called with progress updates
            %              The function should accept two parameters:
            %              1. Current progress value (bytes received)
            %              2. Maximum expected value (total bytes expected)

            arguments
                callback (1,1) function_handle
            end

            obj.Interval = 0.25;
            obj.Callback = callback;
        end

        %-----------------------------------------------------------------%
        function done(~)
            % done Called when the HTTP operation is completed
            %
            % This method is called when the HTTP operation is completed,
            % but no action is needed for this implementation.
        end

        %-----------------------------------------------------------------%
        function set.Direction(obj, direction)
            % set.Direction Setter for the Direction property
            %
            % Sets the direction of the HTTP message (Request or Response).
            %
            % Input:
            %   obj - The DownloadProgressMonitor object
            %   direction - The message type (matlab.net.http.MessageType.Request or
            %               matlab.net.http.MessageType.Response)

            obj.Direction = direction;
        end

        %-----------------------------------------------------------------%
        function set.Value(obj, value)
            % set.Value Setter for the Value property
            %
            % Sets the current progress value and notifies the caller of the update.
            %
            % Input:
            %   obj - The DownloadProgressMonitor object
            %   value - Current progress value in bytes (uint64)

            obj.Value = value;
            notifyCaller(obj)
        end
    end


    methods (Access = private)
        %-----------------------------------------------------------------%
        function notifyCaller(obj)
            % notifyCaller Notifies the callback function with current progress
            %
            % Calls the callback function with the current progress values if
            % the direction is Response. Any errors during callback execution
            % are silently ignored.
            %
            % Input:
            %   obj - The DownloadProgressMonitor object

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
