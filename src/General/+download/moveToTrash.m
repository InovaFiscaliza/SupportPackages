function moveToTrash(filePath)
% MOVETOTRASH Remove a temporary file through the host trash when available.

if ~isfile(filePath)
    return
end

try
    desktop = java.awt.Desktop.getDesktop();
    movedToTrash = desktop.moveToTrash(java.io.File(filePath));
    if movedToTrash
        return
    end
catch
end

delete(filePath)
end