% CompressLib.m
%--------------------------------------------------------------------------
% This Matlab class contains only static methods. These methods will 
% compress matlab variables in java GZIP functions. Matrices, strings, 
% structures, and cell arrays are supported. 
%
% Original Author: Jesse Hopkins
% Date: 2009/10/29
% Version: 1.5
%
% Co-Author: Patrik Forssén
% Date: 2022/10/16
% Source:
% https://www.mathworks.com/matlabcentral/fileexchange/25656-compression-routines
% (Discussion tab)
%
% Edited by Eric Delgado to include the option of compressing not only the
% ByteStream of the array but the array itself, and to use MATLAB's undocument
% built-in functions "getArrayFromByteStream" and "getByteStreamFromArray" 
% instead of creating a new serializer/deserializer.
%--------------------------------------------------------------------------

classdef CompressLib
	methods(Static = true)
        %-----------------------------------------------------------------%
        function out = decompress(in, byteStreamFlag)
            arguments
                in
                byteStreamFlag = true
            end

			import com.mathworks.mlwidgets.io.InterruptibleStreamCopier

			if ~strcmpi(class(in), 'uint8') || ndims(in) > 2 || min(size(in) ~= 1)
				error('Input must be a 1-D array of uint8');
			end

			a = java.io.ByteArrayInputStream(in);
			b = java.util.zip.GZIPInputStream(a);
            
            isc = InterruptibleStreamCopier.getInterruptibleStreamCopier;
			c = java.io.ByteArrayOutputStream;
			
            isc.copyStream(b,c);
			out = typecast(c.toByteArray, 'uint8');

			% Decompressed byte array >> Matlab data type
            if byteStreamFlag
                out = getArrayFromByteStream(out);
            end
		end


        %-----------------------------------------------------------------%
		function out = compress(in, byteStreamFlag)
            arguments
                in 
                byteStreamFlag = true
            end

			% Input variable >> array of bytes
            if byteStreamFlag
                in = getByteStreamFromArray(in);
            elseif ~isa(in, 'uint8')
                in = typecast(in, 'uint8');
            end

			f = java.io.ByteArrayOutputStream();
			g = java.util.zip.GZIPOutputStream(f);

			g.write(in);
			g.close;

			out = typecast(f.toByteArray, 'uint8');
			f.close;
        end
    end
end