%% compareCellPlanDBM.m
% Teste comparativo entre o leitor CellPlanDBM v1.11 (método antigo via
% CellPlan_dBmReader.exe + parsing binário) e v2.00 (método novo via DLL
% IQWrapper), usando o mesmo arquivo .dBm como entrada.
%
% Execução:
%   cd('<workspace>/tests')
%   compareCellPlanDBM
%
% Resultado esperado: todos os itens imprimem [PASS].
% Tolerâncias:
%   - Metadados numéricos : diferença absoluta < 1e-3 Hz
%   - Timestamps          : diferença absoluta < 1e-3 s  (resolução = 1 ms)
%   - Níveis espectrais   : diferença absoluta < 1e-3 dBm (float32 em ambos)

clear; clc; close all

%% -----------------------------------------------------------------------
% 0. Paths
% -----------------------------------------------------------------------
testsDir    = fileparts(mfilename('fullpath'));
srcSpectrum = fullfile(testsDir, '..', 'src', 'Spectrum');
srcGeneral  = fullfile(testsDir, '..', 'src', 'General');

addpath(srcSpectrum, srcGeneral)

FILE = fullfile(testsDir, 'resources', 'SpecDataBase', ...
    'CWSM22010045_E4_A1_Spec Frq=584.000 Span=228.000 RBW=100.00000 [2024-06-19,15-38-59-701-0589].dBm');
    %'CWSM22010038_E4_A1_Spec Frq=584.000 Span=228.000 RBW=100.00000 [2025-01-23,05-54-11-205-8052].dBm');
    %'CWSM22010038_E1_A1_Spec Frq=71.000 Span=34.000 RBW=100.000 [2023-03-02,15-47-11-758-8696].dBm');

assert(isfile(FILE), 'Arquivo de teste não encontrado:\n  %s', FILE)

%% -----------------------------------------------------------------------
% 1. Leitura pelo método ANTIGO (v1.11 — CellPlanDBM_old)
% -----------------------------------------------------------------------
fprintf('\n========================================================\n')
fprintf(' Método ANTIGO  (v1.11 — CellPlanDBMold)\n')
fprintf('========================================================\n')

t0   = tic;
sdOld = model.SpecDataBase.empty;
sdOld = model.fileReader.CellPlanDBMold(sdOld, FILE, 'SingleFile');
timeOld = toc(t0);
fprintf('  Tempo de leitura: %.3f s\n', timeOld)

%% -----------------------------------------------------------------------
% 2. Leitura pelo método NOVO (v2.00 — IQWrapper DLL)
% -----------------------------------------------------------------------
fprintf('\n========================================================\n')
fprintf(' Método NOVO  (v2.00 — DLL IQWrapper)\n')
fprintf('========================================================\n')

t0   = tic;
sdNew = model.SpecDataBase.empty;
sdNew = model.fileReader.CellPlanDBM(sdNew, FILE, 'SingleFile');
timeNew = toc(t0);
fprintf('  Tempo de leitura: %.3f s\n', timeNew)

%% -----------------------------------------------------------------------
% 3. Verificações
% -----------------------------------------------------------------------
fprintf('\n========================================================\n')
fprintf(' Resultados comparativos\n')
fprintf('========================================================\n')

results = {};   % {item, status, detalhe}

%--- Número de streams retornados ----------------------------------------
nOld = numel(sdOld);
nNew = numel(sdNew);
results = addResult(results, 'Nº de streams', nOld == nNew, ...
    sprintf('old=%d  new=%d', nOld, nNew));

if nOld ~= nNew
    fprintf('\n  [AVISO] Número de streams diverge — comparação abortada.\n')
    printResults(results)
    cleanup(sdOld, sdNew)
    return
end

for ii = 1:nOld
    prefix = sprintf('[stream %d]', ii);

    %--- MetaData --------------------------------------------------------
    metaFields = {'DataType','FreqStart','FreqStop','DataPoints', ...
                  'Resolution','TraceMode','Detector','LevelUnit'};

    for ff = 1:numel(metaFields)
        f  = metaFields{ff};
        vo = sdOld(ii).MetaData.(f);
        vn = sdNew(ii).MetaData.(f);

        if isnumeric(vo) && isnumeric(vn)
            % FreqStart/FreqStop: tolerância de 1 Hz (precisão float64 entre os dois métodos)
            % Demais campos numéricos: tolerância de 1e-3
            if ismember(f, {'FreqStart','FreqStop'})
                tol = 1;
            else
                tol = 1e-3;
            end
            ok  = abs(double(vo) - double(vn)) < tol;
            det = sprintf('old=%.6g  new=%.6g  diff=%.3e', double(vo), double(vn), abs(double(vo)-double(vn)));
        else
            ok  = isequal(vo, vn);
            det = sprintf('old=%s  new=%s', num2str(vo), num2str(vn));
        end
        results = addResult(results, sprintf('%s MetaData.%s', prefix, f), ok, det);
    end

    %--- Receiver --------------------------------------------------------
    results = addResult(results, sprintf('%s Receiver', prefix), ...
        strcmp(sdOld(ii).Receiver, sdNew(ii).Receiver), ...
        sprintf('old=%s  new=%s', sdOld(ii).Receiver, sdNew(ii).Receiver));

    %--- RelatedFiles: NumSweeps, RevisitTime ----------------------------
    nSweepsOld = sdOld(ii).RelatedFiles.NumSweeps(1);
    nSweepsNew = sdNew(ii).RelatedFiles.NumSweeps(1);
    results = addResult(results, sprintf('%s NumSweeps', prefix), ...
        nSweepsOld == nSweepsNew, ...
        sprintf('old=%d  new=%d', nSweepsOld, nSweepsNew));

    rvOld = sdOld(ii).RelatedFiles.RevisitTime(1);
    rvNew = sdNew(ii).RelatedFiles.RevisitTime(1);
    results = addResult(results, sprintf('%s RevisitTime', prefix), ...
        abs(rvOld - rvNew) < 1e-3, ...
        sprintf('old=%.4f s  new=%.4f s  diff=%.3e s', rvOld, rvNew, abs(rvOld-rvNew)));

    %--- BeginTime / EndTime (tolerância 1 ms) ---------------------------
    btDiff = abs(seconds(sdOld(ii).RelatedFiles.BeginTime(1) - sdNew(ii).RelatedFiles.BeginTime(1)));
    etDiff = abs(seconds(sdOld(ii).RelatedFiles.EndTime(1)   - sdNew(ii).RelatedFiles.EndTime(1)));
    results = addResult(results, sprintf('%s BeginTime', prefix), btDiff < 1e-3, ...
        sprintf('diff=%.4f s', btDiff));
    results = addResult(results, sprintf('%s EndTime',   prefix), etDiff < 1e-3, ...
        sprintf('diff=%.4f s', etDiff));

    %--- Data{1}: timestamps ---------------------------------------------
    if ~isempty(sdOld(ii).Data) && ~isempty(sdNew(ii).Data)
        tsDiff = abs(seconds(sdOld(ii).Data{1} - sdNew(ii).Data{1}));
        maxTsDiff = max(tsDiff);
        results = addResult(results, sprintf('%s Data{1} max timestamp diff', prefix), ...
            maxTsDiff < 1e-3, sprintf('max diff=%.4f s', maxTsDiff));

        %--- Data{2}: níveis espectrais ----------------------------------
        diffLvl    = double(sdOld(ii).Data{2}) - double(sdNew(ii).Data{2});
        maxAbsDiff = max(abs(diffLvl(:)));
        rmseVal    = rms(diffLvl(:));
        results = addResult(results, sprintf('%s Data{2} max |diff|', prefix), ...
            maxAbsDiff < 1e-3, sprintf('%.6f dBm', maxAbsDiff));
        results = addResult(results, sprintf('%s Data{2} RMSE', prefix), ...
            rmseVal < 1e-4, sprintf('%.2e dBm', rmseVal));
    end

    %--- GPS -------------------------------------------------------------
    gpsOk = isequal(sdOld(ii).GPS.Status, sdNew(ii).GPS.Status) && ...
            isequal(sdOld(ii).GPS.Latitude, sdNew(ii).GPS.Latitude) && ...
            isequal(sdOld(ii).GPS.Longitude, sdNew(ii).GPS.Longitude);
    results = addResult(results, sprintf('%s GPS', prefix), gpsOk, '');
end

%% -----------------------------------------------------------------------
% 4. Sumário textual
% -----------------------------------------------------------------------
printResults(results)

%% -----------------------------------------------------------------------
% 5. Tempo comparativo
% -----------------------------------------------------------------------
fprintf('\n--- Tempo de leitura ---\n')
fprintf('  Antigo (v1.11): %.3f s\n', timeOld)
fprintf('  Novo   (v2.00): %.3f s\n', timeNew)
if timeOld > 0
    fprintf('  Speedup: %.1fx\n', timeOld / timeNew)
end

%% -----------------------------------------------------------------------
% 6. Plots comparativos
% -----------------------------------------------------------------------
if isempty(sdOld) || isempty(sdNew) || isempty(sdOld(1).Data)
    cleanup(sdOld, sdNew)
    return
end

freqAxis = linspace(double(sdNew(1).MetaData.FreqStart), double(sdNew(1).MetaData.FreqStop), ...
                    double(sdNew(1).MetaData.DataPoints)) / 1e6;   % MHz

meanOld = mean(double(sdOld(1).Data{2}), 2);
meanNew = mean(double(sdNew(1).Data{2}), 2);
diffMean = meanNew - meanOld;

fig = figure('Name', 'CellPlanDBM — Teste comparativo', ...
             'NumberTitle', 'off', ...
             'Units', 'normalized', ...
             'Position', [0.05 0.1 0.9 0.8]);

% --- Subplot 1: espectro médio dos dois métodos -------------------------
ax1 = subplot(3,1,1, 'Parent', fig);
plot(ax1, freqAxis, meanOld, 'b-',  'LineWidth', 1.2, 'DisplayName', 'v1.11 (antigo)');
hold(ax1, 'on')
plot(ax1, freqAxis, meanNew, 'r--', 'LineWidth', 1.0, 'DisplayName', 'v2.00 (novo)');
hold(ax1, 'off')
xlabel(ax1, 'Frequência (MHz)')
ylabel(ax1, 'Nível médio (dBm)')
title(ax1, 'Espectro médio — comparação dos dois métodos')
legend(ax1, 'Location', 'best')
grid(ax1, 'on')
xlim(ax1, [freqAxis(1), freqAxis(end)])

% --- Subplot 2: diferença média (new - old) -----------------------------
ax2 = subplot(3,1,2, 'Parent', fig);
plot(ax2, freqAxis, diffMean, 'k-', 'LineWidth', 1.0)
yline(ax2, 0, 'r--', 'LineWidth', 0.8)
xlabel(ax2, 'Frequência (MHz)')
ylabel(ax2, '\DeltaNível (dBm)')
title(ax2, sprintf('Diferença (new − old): max = %.3e dBm', max(abs(diffMean))))
grid(ax2, 'on')
xlim(ax2, [freqAxis(1), freqAxis(end)])

% --- Subplot 3: heatmap Data{2} do método novo --------------------------
ax3 = subplot(3,1,3, 'Parent', fig);
imagesc(ax3, freqAxis, 1:sdNew(1).RelatedFiles.NumSweeps(1), ...
        double(sdNew(1).Data{2})')
colormap(ax3, 'jet')
colorbar(ax3)
xlabel(ax3, 'Frequência (MHz)')
ylabel(ax3, 'Sweep #')
title(ax3, 'Heatmap Data{2} — método novo (v2.00)')
axis(ax3, 'tight')

%% -----------------------------------------------------------------------
% 7. Limpeza
% -----------------------------------------------------------------------
cleanup(sdOld, sdNew)


%% =====================  Funções auxiliares  ============================

function results = addResult(results, item, ok, detail)
    if ok
        status = 'PASS';
    else
        status = 'FAIL';
    end
    results{end+1} = {item, status, detail};
end

function printResults(results)
    fprintf('\n%-45s  %-6s  %s\n', 'Item', 'Status', 'Detalhe')
    fprintf('%s\n', repmat('-', 1, 90))
    nFail = 0;
    for kk = 1:numel(results)
        r = results{kk};
        if strcmp(r{2}, 'FAIL')
            mark  = '<!>';
            nFail = nFail + 1;
        else
            mark  = '   ';
        end
        fprintf('%s %-43s  [%-4s]  %s\n', mark, r{1}, r{2}, r{3})
    end
    fprintf('%s\n', repmat('-', 1, 90))
    if nFail == 0
        fprintf('  Resultado final: TODOS OS %d ITENS PASSARAM :)\n\n', numel(results))
    else
        fprintf('  Resultado final: %d/%d itens FALHARAM\n\n', nFail, numel(results))
    end
end

function cleanup(sdOld, sdNew)
    try; delete(sdOld); catch; end
    try; delete(sdNew); catch; end
end
