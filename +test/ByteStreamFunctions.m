%% ByteStream
% Test of the functions "matlab.getByteStreamFromArray" and "matlab.getArrayFromByteStream", 
% which mimic the undocumented built-in MATLAB functions "getByteStreamFromArray" 
% and "getArrayFromByteStream", but are limited to cases where the input is 
% a numeric or logical array.
% 
% The variable "cellArray" can be expanded to test other numeric or logical arrays. 
% Error checking is done by comparing the results of the custom functions with the 
% outputs of the built-in MATLAB functions.

cellArray = {uint8(1),                             ... scalar
             uint8(1:5),                           ... array 2D (matrix)
             randi(255, 1000, 'uint8'),            ...
             true,                                 ... logical
             [true, false; true, true],            ...
             int16(reshape(1:21, 3, 7)),           ...
             int32(reshape(1:21, 1, 3, 7)),        ... array 3D
             single(1:5),                          ...
             randn(10, 10),                        ...
             uint64([5+2i, 10+7i; 8+23i, 18+22i]), ... imaginary
             [5+2i, 10+7i; 8+23i, 18+22i; 11, 22]};

for ii = 1:numel(cellArray)
    byteStream   = matlab.getByteStreamFromArray(cellArray{ii}, true);
    numericArray = matlab.getArrayFromByteStream(byteStream,    true);

    if ~isequal(cellArray{ii}, numericArray)
        error('BUG... :(')
    end
end
fprintf('SUCESS! :)')