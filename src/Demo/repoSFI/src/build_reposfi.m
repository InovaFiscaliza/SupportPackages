projectRoot = "C:\InovaFiscaliza\SupportPackages\src\Demo\repoSFI\src";
buildRoot = fullfile(projectRoot, "wsSpectrumReader");
testingDir = fullfile(buildRoot, "for_testing");
installerDir = fullfile(buildRoot, "for_redistribution");
portableDir = fullfile(buildRoot, "for_redistribution_files_only");
configDir = fullfile(projectRoot, "config");

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
buildOpts.ExecutableVersion = "0.3.5";
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
packageOpts.Version = "0.3.5";
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
