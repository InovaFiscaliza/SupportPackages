function [imgExt, imgString] = img2base64(imgFileFullPath, callSource)
%IM2BASE64

% Author.: Eric Magalhães Delgado
% Date...: April 20, 2024
% Version: 1.01

    arguments
        imgFileFullPath {ccTools.validators.mustBeScalarText}
        callSource      {ccTools.validators.mustBeScalarText} = ''
    end

    imgFileFullPath = ccTools.fcn.FileParts(imgFileFullPath);

    try
        [~, ~, imgExt] = fileparts(imgFileFullPath);
        switch lower(imgExt)
            case '.png';            imgExt = 'png';
            case {'.jpg', '.jpeg'}; imgExt = 'jpeg';
            case '.gif';            imgExt = 'gif';
            case '.svg';            imgExt = 'svg+xml';
            otherwise;              error('Image file format must be "JPEG", "PNG", "GIF", or "SVG".')
        end

        fileID = fopen(imgFileFullPath, 'r');
        imgArray  = fread(fileID, 'uint8=>uint8');
        imgString = matlab.net.base64encode(imgArray);
        fclose(fileID);

    catch ME
        imgExt = 'png';
        switch callSource
            case 'ccTools.Button'
                imgString = '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';
            case 'ccTools.MessageBox'
                imgString = 'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAJiSURBVGhD7Zk/b9pAGMaxDcYR2ICgCKpKRhSFgSZDJTIlEksVqsLeIWOHfoEMyZQPkClD1yyZEnWiH6RTMiQS8pBKAQkR6grLBbvPwcVJ1ESJYjsG5X7SK7/3R/A+3PnuvSPEYDDmG4E+faFer3Oqqobb7bZFq+aDfD7/Spblr6Io/pAk6Wc0Gt1PpVLr5XKZp11mm3g8vsPz/CVcm5oVDoe1dDr9nrTPNAhSikQiF3CvgncMI7GHp6d4PqS2bZPPlKal26AtSl3P8FxAoVAwMF0O4f6d1kzhOE6PxWLfaXG2URRlES/wId4DA0Uy/7uYPlvFYlGc9pgDqtWqmEwmlxH4Wi6XUxuNBkebGIwXBea/kkgk3lYqlQVa5Sm+5EK1Wo0bjUYprEIfBoPBrmman+Gf6Lqu0S6e4XZlUGFfsMZHsGzGsQMr8NOGYbwej8dvLMvKkE6CIAywQ290Op0WKc8Sq7Ah7L+04aZBwGU2m23A9xxXOzGyTh2b1jECPMUvf4qqM2KYLr8nHa65EjMf4KX9CFFOQge/jxH4NGn0GF/yc4zGL6QPf2jRV/wSQD3/8UXAc8IEBA0TEDRMQNAwAUHDBAQNExA0TMBd2LZN8umbOTXxfblAcJW4ZzIZBYf3dwjYCQ5nAcE0zepwONzGoT5J6yxJkvZhByiSU9rke1Fvy7J8pmnaOSk/BVcCcOpaweMIApw7HwTFI3AZdusil4ggR0u4zt9NVMBOr9f7RquenUfdStxnRBTOz5vwn4yrEWg2m3K3213q9/t3/qHxEERAqVQ6brVaHVrFYDBeFqHQPwNXrRGhF/9eAAAAAElFTkSuQmCC';
            otherwise
                error(ME.message)
        end
    end
end