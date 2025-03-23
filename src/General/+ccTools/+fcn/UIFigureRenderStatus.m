function status = UIFigureRenderStatus(fHandle)

    status = false;
    fControl = struct(fHandle).Controller;

    if ~isempty(fControl) && isprop(fControl, 'IsFigureViewReady') && fControl.IsFigureViewReady
        status = true;
    end
    
end