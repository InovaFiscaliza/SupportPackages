function imgFile = base642img(imgString, imgExt, viewFlag)
%BASE642IMG

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