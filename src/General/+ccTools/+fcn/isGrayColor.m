function isGray = isGrayColor(rgbImg, THR)
%ISGRAYCOLOR
% General info:
% - RGB (Reg, Green, Blue)

% Author.: Eric Magalhães Delgado
% Date...: May 13, 2023
% Version: 1.00

    arguments
        rgbImg {ccTools.validators.mustBeColor(rgbImg, 'rgb')}
        THR {ccTools.validators.mustBeNumberInRange(THR, 0, 255)} = 20
    end

    switch class(rgbImg)
        case 'uint8'
            rgbImg = double(rgbImg);
        case {'single', 'double'}
            rgbImg = double(rgbImg)*255;
    end

    isGray = (max(rgbImg)-min(rgbImg) <= THR);
end