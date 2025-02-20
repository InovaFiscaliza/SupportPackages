%% model.SpecDataBase
% Test of the functions "model.SpecDataBase" and its subfolder "+fileReader".

mFilePath = getThisFolderPath();
fileDir   = dir(fullfile(mFilePath, 'resources', 'SpecDataBase'));

fileList  = arrayfun(@(x) fullfile(x.folder, x.name), fileDir, "UniformOutput", false);
fileList(~isfile(fileList)) = [];

disp(strjoin(fileList, '\n'))

%% Test1: Read files from the "resources" folder
printfOnConsoleFlag = false;

for ii = 1:numel(fileList)
    specData = model.SpecDataBase.empty;

    try
        switch mod(ii, 3)
            case 0 
                specData = read(specData, fileList{ii}, 'MetaData');
                if printfOnConsoleFlag; disp(specData(1).MetaData); end
            case 1
                specData = read(specData, fileList{ii}, 'MetaData');
                specData = read(specData, fileList{ii}, 'SpecData');
                if printfOnConsoleFlag; specData(1).GPS; end
            case 2
                specData = read(specData, fileList{ii}, 'SingleFile');
                if printfOnConsoleFlag; disp(specData(1).RelatedFiles); end
        end

    catch ME
        disp(ME.message)
    end

    delete(specData)
end
disp('SUCESS! :)')

%% Test2: Analysis & Plot
% READ FILE
specData = model.SpecDataBase.empty;
specData = read(specData, fileList{end}, 'SingleFile');

% ANALYSIS
% (a) Find maximum in average curve (to show as a marker)
[~, idxPeakMax] = max(specData(1).Data{3}(:,2));

% PLOT
% (a) Identify the center of the larger screen monitor
figWidth    = 920;
figHeight   = 580;

mainMonitor = get(0, 'MonitorPositions');
[~, idx]    = max(mainMonitor(:,3));
mainMonitor = mainMonitor(idx,:);

xPosition   = mainMonitor(1)+round((mainMonitor(3)-figWidth)/2);
yPosition   = mainMonitor(2)+round((mainMonitor(4)+18-figHeight)/2);

% (b) Create uifigure and uiaxes
f  = uifigure('Position', [xPosition, yPosition, figWidth, figHeight]);
ax = uiaxes(f, 'Units', 'normalized', 'Position', [0.01,0.01,.98,.98], ...
               'YGrid', 'on', 'XGrid', 'on', 'GridColor', [.8,.8,.8],  ...
               'Color', [.15,.15,.15], 'FontSize', 10);

% (c) Configure uiaxes
xData = linspace(specData(1).MetaData.FreqStart / 1e+6, ... % Hertz >> MHz
                 specData(1).MetaData.FreqStop  / 1e+6, ...
                 specData(1).MetaData.DataPoints);

[yDataMin, yDataMax] = bounds(specData(1).Data{3}, "all");

set(ax, XLim = [xData(1), xData(end)], YLim = [yDataMin, yDataMax])
xlabel(ax, 'Frequência (MHz)')
ylabel(ax, ['Nível (' specData(1).MetaData.LevelUnit ')'])
legend(ax, 'Location','southwest', 'Box', 'off', 'TextColor', [.94,.94,.94])
hold(ax, "on")

% (d) Plot data
plot(ax, xData, specData(1).Data{3}(:,1), 'Color', '#4A90E2', 'DisplayName', 'MinHold')
plot(ax, xData, specData(1).Data{3}(:,2), 'Color', '#ffff12', 'DisplayName', 'Average', 'MarkerIndices', idxPeakMax, 'Marker', 'o', 'MarkerSize', 6, 'MarkerFaceColor', 'red', 'MarkerEdgeColor', 'red')
plot(ax, xData, specData(1).Data{3}(:,3), 'Color', '#FF5CAD', 'DisplayName', 'MaxHold')

%% Test3: Read and write (CRFS File)
% READ CRFS FILE
fileName = fullfile(mfilePath, 'resources', 'SpecDataBase', 'rfeye002292_210211_T111912.bin');

specData = model.SpecDataBase.empty;
specData = read(specData, fileName, 'SingleFile');

% WRITE FILE
fileTempName = [tempname '.bin'];
model.fileWriter.CRFSBin(fileTempName, specData)

% READ CREATED CRFS FILE
tempSpecData = model.SpecDataBase.empty;
tempSpecData = read(tempSpecData, fileTempName, 'SingleFile');
delete(fileTempName)

% CONTENT COMPARISON
if isequal(rmfield(struct(specData), {'GPS', 'RelatedFiles'}), rmfield(struct(tempSpecData), {'GPS', 'RelatedFiles'}))
    disp('SUCESS! :)')    
else
    disp('ERROR! :(')
end

%% Test4: Read and write (MAT File)
% READ CRFS FILE
fileName = fullfile(mFilePath, 'resources', 'SpecDataBase', 'rfeye002292_210211_T111912.bin');

specData = model.SpecDataBase.empty;
specData = read(specData, fileName, 'SingleFile');

% WRITE FILE (MAT)
fileTempName = [tempname '.mat'];
model.fileWriter.MAT(fileTempName, 'SpectralData', specData, [], {'UserData', 'callingApp', 'sortType'})

% READ CREATED MAT FILE
tempSpecData = model.SpecDataBase.empty;
tempSpecData = read(tempSpecData, fileTempName, 'SingleFile');
delete(fileTempName)

% CONTENT COMPARISON
if isequal(specData, tempSpecData)
    disp('SUCESS! :)')    
else
    disp('ERROR! :(')
end