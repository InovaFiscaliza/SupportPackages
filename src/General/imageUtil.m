classdef (Abstract) imageUtil
    
    methods (Static = true)
        %-----------------------------------------------------------------%
        function RGB = getRGB(hPlot, idx)
            arguments
                hPlot 
                idx = []
            end
            
            if isempty(idx)
                idx = 1:numel(hPlot.CData);
            end

            hAxes = hPlot.Parent;
            cMap  = hAxes.Colormap;
            cLim  = hAxes.CLim;

            iMap  = round((hPlot.CData(idx) - cLim(1))/range(cLim) * (height(cMap)-1) + 1);
            RGB   = cMap(iMap,:);
        end

        %-----------------------------------------------------------------%
        function [imgExt, imgString] = img2base64(imgFullPath)
            % Especificação para gerar imagens "Warning.html":
            % - Consolas, negrito, 10

            fileID = -1;
            while fileID == -1
                fileID = fopen(imgFullPath, 'r');
                pause(1)                
            end
            
            [~, ~, imgExt] = fileparts(imgFullPath);
            switch lower(imgExt)
                case '.png';            imgExt = 'png';
                case {'.jpg', '.jpeg'}; imgExt = 'jpeg';
                case '.gif';            imgExt = 'gif';
                case '.svg';            imgExt = 'svg+xml';
                otherwise;              error('imageUtil:img2base64', 'Image file format must be "JPEG", "PNG", "GIF", or "SVG".')
            end
            
            imgArray  = fread(fileID, 'uint8=>uint8');
            imgString = matlab.net.base64encode(imgArray);
            fclose(fileID);        
        end

        %-----------------------------------------------------------------%
        function imgFile = base642img(imgString, imgExt, viewFlag)        
            arguments
                imgString char
                imgExt    char    = '.png'
                viewFlag  logical = false
            end
        
            if ~ismember(lower(imgExt), {'.jpg', '.jpeg', '.png', '.gif', '.svg'})
                error('Image file format must be "JPEG", "PNG", "GIF", or "SVG".')
            end
        
            imgFile  = [tempname imgExt];
            imgArray = matlab.net.base64decode(imgString);
        
            fileID   = fopen(imgFile, 'w');
            fwrite(fileID, imgArray, 'uint8');
            fclose(fileID);
        
            if viewFlag
                img = imread(imgFile);
                figure, imshow(img);
            end
        end
    end
end

