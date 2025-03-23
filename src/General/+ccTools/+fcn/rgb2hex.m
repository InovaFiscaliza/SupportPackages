function hexImg = rgb2hex(rgbImg)
%RGB2HEX

% Author.: Eric Magalhães Delgado
% Date...: May 12, 2023
% Version: 1.00

    arguments
        rgbImg {ccTools.validators.mustBeColor(rgbImg, 'rgb')}
    end

    Fcn = @(x) isnumeric(x) & (numel(x) == 3) & (isa(x, 'uint8') | (isfloat(x) & all(x >= 0 & x <= 1)));
    if ~Fcn(rgbImg)
        error('Input must be numeric, such as: uint8([255,0,0]) | double([1,0,0]).');
    end

    if isfloat(rgbImg)
        rgbImg = round(255*rgbImg);
    end

    hexR = dec2hex(rgbImg(1));
    hexG = dec2hex(rgbImg(2));
    hexB = dec2hex(rgbImg(3));
    
    if numel(hexR) == 1; hexR = ['0' hexR]; end
    if numel(hexG) == 1; hexG = ['0' hexG]; end
    if numel(hexB) == 1; hexB = ['0' hexB]; end

    hexImg = sprintf('#%s%s%s', hexR, hexG, hexB);
end