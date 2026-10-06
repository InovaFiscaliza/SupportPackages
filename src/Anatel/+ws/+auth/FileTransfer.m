classdef FileTransfer < datatransfer.HTTPFileTransfer
    % FILETRANSFER F5 request-context adapter for generic HTTP transfers.

    methods
        function obj = FileTransfer(session, request, chunkSize, maxRetries)
            % FILETRANSFER Create an F5-backed transfer using an existing session.
            arguments
                session (1,1) ws.auth.F5Session
                request (1,1) struct
                chunkSize (1,1) double {mustBeInteger, mustBePositive} = 1024*1024
                maxRetries (1,1) double {mustBeInteger, mustBeNonnegative} = 3
            end
            obj@datatransfer.HTTPFileTransfer(session, request, chunkSize, maxRetries)
        end
    end

    methods (Access = protected)
        function context = acquireContext(obj, url)
            % ACQUIRECONTEXT Obtain the F5 session context for a transfer URL.
            context = obj.RequestContextProvider.getRequestContext(url);
        end

        function context = reauthenticate(obj, url)
            % REAUTHENTICATE Refresh the F5 session before a body operation.
            context = obj.RequestContextProvider.authenticateForRequest(url);
        end
    end
end
