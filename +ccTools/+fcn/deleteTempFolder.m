function deleteTempFolder(tempFolder)
    try
        rmdir(tempFolder, 's')
    catch
    end
end