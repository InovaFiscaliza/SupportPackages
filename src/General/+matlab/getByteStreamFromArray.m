function byteStream = getByteStreamFromArray(numericArray, errorCheckFlag)

    % Mimics the undocumented built-in function "getByteStreamFromArray" for 
    % numeric input (real, imaginary, vector, matrix, double, uint8 etc)
    %
    % Reference:
    % - https://www.mathworks.com/help/pdf_doc/matlab/matfile_format.pdf
    % - https://www.mathworks.com/help/matlab/ref/computer.html
    %   (little-endian byte ordering for 64-bit Windows, Linux, and macOS
    %   platforms)

    arguments
        numericArray   {mustBeNumericOrLogical}
        errorCheckFlag logical = false
    end

    % Referência
    if errorCheckFlag
        byteStreamMATLAB = getByteStreamFromArray(numericArray);            % MATLAB undocumented built-in function
    end

    % Input array
    if ~isreal(numericArray)
        dataSubTypeID = 8;                                                  % numeric+complex
    elseif islogical(numericArray)
        numericArray = uint8(numericArray);
        dataSubTypeID = 2;                                                  % logical+real (não existe logical+complex >> convertido para double)
    else
        dataSubTypeID = 0;                                                  % numeric+real
    end

    realNumericArray = real(numericArray);
    realNumericUint8Array = typecast(realNumericArray(:), 'uint8')';
    realNumericUint8ArrayLength = numel(realNumericUint8Array);

    if isreal(numericArray)
        imagNumericUint8Array = [];
    else
        imagNumericArray = imag(numericArray); 
        imagNumericUint8Array = typecast(imagNumericArray(:), 'uint8')';
    end
    
    [xSize, ySize, zSize] = size(numericArray);
    if zSize == 1
        dimensionArrayID = 8;
    else
        dimensionArrayID = 12;
    end

    % ByteStream length    
    byteStreamHeaderLength = 56;
    if realNumericUint8ArrayLength <= 4
        byteStreamBlockHeaderType   = 'Compact';        
        byteStreamBlockHeaderLength = 4;
    else
        byteStreamBlockHeaderType   = 'Normal';
        byteStreamBlockHeaderLength = 8;
        if zSize ~= 1
            byteStreamHeaderLength = byteStreamHeaderLength+8;
        end        
    end

    byteStreamBlockLength = byteStreamBlockHeaderLength + realNumericUint8ArrayLength;
    if mod(byteStreamBlockLength, 8)
        byteStreamBlockLength = byteStreamBlockLength + (8 - mod(byteStreamBlockLength, 8));
    end

    byteStreamLength  = byteStreamHeaderLength + (1 + (dataSubTypeID == 8)) * byteStreamBlockLength;

    % Datatype-IDs Mapping
    dataTypeMapping   = DataTypeMapping(class(numericArray));
    
    % ByteStream constructor
    byteStream        = zeros(1, byteStreamLength, 'uint8');
    
    byteStream(1:2)   = [0, 1];                                             % "Version": 0x0100
    byteStream(3:4)   = [73, 77];                                           % "EndianIndicator": char([73, 77]) = 'IM' (LittleEndian) | char([77, 73]) = 'MI' (BigEndian)
    byteStream(9)     = 14;
    byteStream(13:16) = typecast(uint32(byteStreamLength - 16), 'uint8');
    byteStream(17:20) = typecast(uint32(6), 'uint8');
    byteStream(21:24) = typecast(uint32(8), 'uint8');
    byteStream(25)    = dataTypeMapping.ArrayType;
    byteStream(26)    = dataSubTypeID;
    byteStream(33:36) = typecast(uint32(5), 'uint8');
    byteStream(37:40) = typecast(uint32(dimensionArrayID), 'uint8');
    byteStream(41:44) = typecast(uint32(xSize), 'uint8');
    byteStream(45:48) = typecast(uint32(ySize), 'uint8');
    byteStream(49:52) = typecast(uint32(zSize), 'uint8');

    byteOffset = 57;
    % 3D arrays adds 8 more bytes to the header: uint32([1,0])
    if zSize ~= 1
        byteStream(byteOffset:byteOffset+3) = typecast(uint32(1), 'uint8');
        byteOffset = byteOffset+8;
    end

    [byteStream, byteOffset] = AddArrayData(byteStream, byteOffset, byteStreamBlockHeaderType, dataTypeMapping, realNumericUint8Array, byteStreamBlockLength, true);
    byteStream               = AddArrayData(byteStream, byteOffset, byteStreamBlockHeaderType, dataTypeMapping, imagNumericUint8Array, byteStreamBlockLength, dataSubTypeID == 8);

    if errorCheckFlag
        if ~isequal(byteStream, byteStreamMATLAB)
            byteStreamMATLABString = "[" + strjoin(string(byteStreamMATLAB), ', ') + "]";
            byteStreamString       = "[" + strjoin(string(byteStream),       ', ') + "]";

            error('Unexpected Byte Stream\nBuilt-in: %s\nCustom:   %s', byteStreamMATLABString, byteStreamString)
        end
    end
end


%-------------------------------------------------------------------------%
function dataTypeMapping = DataTypeMapping(inputDataType)
    dataTypeIDs = struct('double', [ 6,  9], ...
                         'single', [ 7,  7], ...
                         'int8',   [ 8,  1], ...
                         'uint8',  [ 9,  2], ...
                         'int16',  [10,  3], ...
                         'uint16', [11,  4], ...
                         'int32',  [12,  5], ...
                         'uint32', [13,  6], ...
                         'int64',  [14, 12], ...
                         'uint64', [15, 13]);

    if isfield(dataTypeIDs, inputDataType)
        dataTypeMapping = struct('ArrayType', dataTypeIDs.(inputDataType)(1), 'DataType', dataTypeIDs.(inputDataType)(2));
    else
        error('Unexpected data type "%s"', inputDataType)
    end    
end


%-------------------------------------------------------------------------%
function [byteStream, byteOffset] = AddArrayData(byteStream, byteOffset, byteStreamBlockHeaderType, dataTypeMapping, numericArray, byteStreamBlockLength, writeFlag)
    if ~writeFlag
        return
    end

    numelInputArray = numel(numericArray);

    switch byteStreamBlockHeaderType
        case 'Compact'
            byteStream(byteOffset:byteOffset+1)   = typecast(uint16(dataTypeMapping.DataType), 'uint8'); % "DataType"
            byteStream(byteOffset+2:byteOffset+3) = typecast(uint16(numelInputArray),          'uint8'); % "NumberOfBytes"
            byteStreamBlockHeaderLength = 4;
            
        case 'Normal'
            byteStream(byteOffset:byteOffset+3)   = typecast(uint32(dataTypeMapping.DataType), 'uint8');
            byteStream(byteOffset+4:byteOffset+7) = typecast(uint32(numelInputArray),          'uint8');
            byteStreamBlockHeaderLength = 8;
    end

    byteOffset = byteOffset+byteStreamBlockHeaderLength;    
    byteStream(byteOffset:byteOffset+numelInputArray-1) = numericArray;
    byteOffset = byteOffset+(byteStreamBlockLength-byteStreamBlockHeaderLength);
end