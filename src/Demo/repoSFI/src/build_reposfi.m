projectRoot = "C:\InovaFiscaliza\SupportPackages\src\Demo\repoSFI\src";
buildRoot = fullfile(projectRoot, "wsSpectrumReader");
testingDir = fullfile(buildRoot, "for_testing");
installerDir = fullfile(buildRoot, "for_redistribution");
portableDir = fullfile(buildRoot, "for_redistribution_files_only");
configDir = fullfile(projectRoot, "config");
cellPlanDir = "C:\InovaFiscaliza\SupportPackages\src\Spectrum\+model\+fileReader\CellPlanDBM";

ensureCellPlanThunk(cellPlanDir);

buildOpts = compiler.build.StandaloneApplicationOptions(fullfile(projectRoot, "main.m"));
buildOpts.AdditionalFiles = [ ...
    fullfile(projectRoot, "+class"), ...
    fullfile(projectRoot, "+handlers"), ...
    fullfile(projectRoot, "+server"), ...
    fullfile(projectRoot, "+util"), ...
    "C:\InovaFiscaliza\SupportPackages\src\General", ...
    "C:\InovaFiscaliza\SupportPackages\src\Spectrum"];
buildOpts.AutoDetectDataFiles = true;
buildOpts.OutputDir = testingDir;
buildOpts.Verbose = true;
buildOpts.EmbedArchive = true;
buildOpts.ExecutableName = "repoSFI";
buildOpts.ExecutableVersion = "0.3.6";
buildOpts.TreatInputsAsNumeric = false;
buildResult = compiler.build.standaloneWindowsApplication(buildOpts);


% Create package options object, set package properties and package.
packageOpts = compiler.package.InstallerOptions(buildResult);
packageOpts.AdditionalFiles = configDir;
packageOpts.ApplicationName = "repoSFI";
packageOpts.AuthorName = "Augusto Peterle";
packageOpts.AuthorCompany = "ANATEL";
packageOpts.DefaultInstallationDir = "%ProgramFiles%\ANATEL\repoSFI\";
packageOpts.Description = "repoSFI - Servidor TCP que recebe requisições JSON, processa dados de espectro e retorna respostas estruturadas";
packageOpts.InstallerName = "MyAppInstaller_web";
packageOpts.OutputDir = installerDir;
packageOpts.Summary = "Servidor TCP para processamento distribuído de dados de RF\Espectro";
packageOpts.Verbose = true;
packageOpts.Version = "0.3.6";
compiler.package.installer(buildResult, "Options", packageOpts);

recreatePortableOutput(testingDir, portableDir, configDir);

function recreatePortableOutput(testingDir, portableDir, configDir)
if isfolder(portableDir)
    rmdir(portableDir, "s");
end

mkdir(portableDir);

buildFiles = dir(testingDir);
for ii = 1:numel(buildFiles)
    fileInfo = buildFiles(ii);
    if fileInfo.isdir
        continue;
    end

    copyfile(fullfile(fileInfo.folder, fileInfo.name), portableDir);
end

if isfolder(configDir)
    copyfile(configDir, fullfile(portableDir, "config"));
end
end

function ensureCellPlanThunk(cellPlanDir)
dllPath = fullfile(cellPlanDir, "IQWrapper.dll");
headerPath = fullfile(cellPlanDir, "IQWrapper.h");
protoPath = fullfile(cellPlanDir, "IQWrapperProto.m");
thunkBase = "IQWrapper_thunk_" + computer("arch");
tempProtoName = "IQWrapperProto_buildtmp";
tempProtoPath = fullfile(cellPlanDir, tempProtoName + ".m");
thunkSourcePath = fullfile(cellPlanDir, thunkBase + ".c");
thunkBinaryPath = fullfile(cellPlanDir, thunkBase + ".dll");

if ~isfile(dllPath) || ~isfile(headerPath)
    error("build_reposfi:MissingCellPlanWrapper", ...
        "IQWrapper.dll or IQWrapper.h not found in %s.", cellPlanDir);
end

needsRefresh = ~isfile(protoPath) || ~isfile(thunkBinaryPath);
if ~needsRefresh
    protoInfo = dir(protoPath);
    thunkInfo = dir(thunkBinaryPath);
    dllInfo = dir(dllPath);
    hdrInfo = dir(headerPath);
    needsRefresh = min([protoInfo.datenum, thunkInfo.datenum]) < max([dllInfo.datenum, hdrInfo.datenum]) || ...
        thunkInfo.datenum < protoInfo.datenum;
end

if ~needsRefresh
    return
end

wasLoaded = libisloaded("IQWrapper");
if wasLoaded
    unloadlibrary("IQWrapper");
end

initFolder = pwd;
cleanupFolder = onCleanup(@() cd(initFolder));
cd(cellPlanDir);

cleanupFiles = onCleanup(@() deleteIfExists(thunkSourcePath));
cleanupProto = onCleanup(@() deleteIfExists(tempProtoPath));
loadlibrary("IQWrapper.dll", "IQWrapper.h", ...
    "mfilename", tempProtoName, ...
    "thunkfilename", thunkBase);
unloadlibrary("IQWrapper");

if ~isfile(thunkBinaryPath)
    error("build_reposfi:MissingThunk", ...
        ["MATLAB did not generate the IQWrapper thunk library. " ...
         "Expected file: %s"], thunkBinaryPath);
end

clear cleanupFolder
clear cleanupFiles
clear cleanupProto
deleteIfExists(thunkSourcePath);
deleteIfExists(tempProtoPath);
end

function deleteIfExists(filePath)
if isfile(filePath)
    delete(filePath);
end
end
