function report = checkDownloadHttp
% CHECKDOWNLOADHTTP Smoke-test public HTTP transport and filename rules.

mFilePath = fileparts(mfilename('fullpath'));
projectFolder = fileparts(fileparts(mFilePath));
addpath(fullfile(projectFolder, 'src', 'Anatel'))
addpath(fullfile(projectFolder, 'src', 'General'))

report = struct('FallbackName', '', ...
                'ContentDispositionName', '', ...
                'StatusCode', [], ...
                'BytesReceived', [], ...
                'FinalPath', '', ...
                'UsedAuthentication', false);

[report.FallbackName, isUseful] = download.downloadFileName('https://example.com/', 'a1b2c3d4');
assert(~isUseful)
assert(contains(report.FallbackName, '_example-com_a1b2c3d4.download'))

report.ContentDispositionName = download.downloadContentDispositionFileName(...
    'attachment; filename*=UTF-8''''report%20final.bin');
assert(strcmp(report.ContentDispositionName, 'report final.bin'))

session = ws.auth.F5Session('https://fiscalizacao.anatel.gov.br/rffusion/api/users/login');
cleanupSession = onCleanup(@() delete(session)); %#ok<NASGU>
context = session.getDownloadContext('https://httpbin.org/bytes/1024');
assert(~context.AuthenticationEligible)
assert(isempty(context.CookieHeader))

responseResult = download.downloadHTTPResponse('https://httpbin.org/bytes/1024', context, 'HEAD');
report.StatusCode = double(responseResult.Response.StatusCode);
assert(report.StatusCode == 200)

runtimeFolder = tempname;
mkdir(runtimeFolder)
cleanupFolder = onCleanup(@() removeFolder(runtimeFolder)); %#ok<NASGU>
mkdir(fullfile(runtimeFolder, 'temp'))
mkdir(fullfile(runtimeFolder, 'target'))
request = struct('URL', 'https://httpbin.org/bytes/1024', ...
                 'TaskID', 'probe1234', ...
                 'TempFolder', fullfile(runtimeFolder, 'temp'), ...
                 'TargetFolder', fullfile(runtimeFolder, 'target'), ...
                 'FileName', 'public.bin', ...
                 'PartialPath', fullfile(runtimeFolder, 'temp', 'probe1234_public.bin.part'), ...
                 'ChunkPath', fullfile(runtimeFolder, 'temp', 'probe1234_public.bin.part.chunk'), ...
                 'BackupPath', '', ...
                 'CollisionAction', 'none', ...
                 'PartialAction', 'none');
queue = parallel.pool.DataQueue;
result = download.downloadFileWorker(context, request, 1024^2, 0, queue, 1);
report.BytesReceived = result.BytesReceived;
report.FinalPath = fullfile(request.TargetFolder, request.FileName);
report.UsedAuthentication = result.NeedsAuthentication;
assert(result.Success)
assert(report.BytesReceived == 1024)
assert(isfile(report.FinalPath))
assert(~report.UsedAuthentication)
end


function removeFolder(folderPath)
if isfolder(folderPath)
    rmdir(folderPath, 's')
end
end
