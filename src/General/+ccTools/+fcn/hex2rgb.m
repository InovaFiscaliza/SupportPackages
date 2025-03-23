function rgbImg = hex2rgb(hexImg, OuputFormat, Decimals)
%HEX2RGB

% Author.: Eric Magalhães Delgado
% Date...: May 12, 2023
% Version: 1.00

    arguments
        hexImg      {ccTools.validators.mustBeColor(hexImg, 'hex')}
        OuputFormat {mustBeMember(OuputFormat, {'uint8', 'float'})} = 'float'
        Decimals    {mustBeInteger, mustBeNonnegative} = 3
    end

    hexImg = char(hexImg);
    rgbImg = [hex2dec(hexImg(2:3)), ...
              hex2dec(hexImg(4:5)), ...
              hex2dec(hexImg(6:7))];

    switch OuputFormat
        case 'uint8'; rgbImg = uint8(rgbImg);
        case 'float'; rgbImg = round(rgbImg/255, Decimals);
    end
end