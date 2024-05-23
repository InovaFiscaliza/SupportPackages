function [webWin, compTag] = componentInfo(comp)

    warning('off', 'MATLAB:structOnObject')
    warning('off', 'MATLAB:ui:javaframe:PropertyToBeRemoved')

    switch class(comp)
        case 'matlab.ui.container.internal.AppContainer'
            webWin  = struct(comp).Window;
            compTag = '';

        otherwise
            fHandle = ancestor(comp, 'figure');
            webWin  = [];
        
            tic; t = toc;
            while t < 10
                try
                    webWin = struct(struct(struct(fHandle).Controller).PlatformHost).CEF;
                    break
                catch
                    pause(.1); t = toc;
                end
            end
        
            releaseVersion = version('-release');
            releaseYear    = str2double(releaseVersion(1:4));
        
            if releaseYear <= 2022
                compTag = struct(comp).Controller.ProxyView.PeerNode.Id;
            else
                compTag = struct(comp).Controller.ViewModel.Id;
            end
    end
end