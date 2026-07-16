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
% instead of creating a new serializer/deserializer. And also to include a 
% fallback to .NET GZIP compression/decompression for environments without JAVA.
%--------------------------------------------------------------------------

classdef CompressLib
	methods(Static = true)
        %-----------------------------------------------------------------%
        function out = decompress(in, byteStreamFlag)
            arguments
                in {mustBeA(in, 'uint8'), mustBeVector(in)}
                byteStreamFlag = true
            end

			% Primary: Java GZIP. Fallback (catch): .NET GZIP.
            try
                out = matlabCommunity.CompressLib.gzipJAVA("decompress", in);
            catch
                out = matlabCommunity.CompressLib.gzipNET("decompress", in);
            end

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
                bytes = getByteStreamFromArray(in);
            elseif ~isa(in, 'uint8')
                bytes = typecast(in, 'uint8');
            else
                bytes = in;
            end
            bytes = bytes(:);

            % Primary: Java GZIP. Fallback (catch): .NET GZIP.
            try
                out = matlabCommunity.CompressLib.gzipJAVA("compress", bytes);
            catch
                out = matlabCommunity.CompressLib.gzipNET("compress", bytes);
            end
        end


        %-----------------------------------------------------------------%
        function out = gzipJAVA(operation, in)
            arguments
                operation (1,1) string {mustBeMember(operation, ["compress", "decompress"])}
                in (:,1) uint8
            end

            switch operation
                case "compress"
                    f = java.io.ByteArrayOutputStream();
                    g = java.util.zip.GZIPOutputStream(f);

                    g.write(in);
                    g.close;

                    out = typecast(f.toByteArray, 'uint8');
                    f.close;

                case "decompress"
                    import com.mathworks.mlwidgets.io.InterruptibleStreamCopier

                    a = java.io.ByteArrayInputStream(in);
                    b = java.util.zip.GZIPInputStream(a);

                    isc = InterruptibleStreamCopier.getInterruptibleStreamCopier;
                    c = java.io.ByteArrayOutputStream;

                    isc.copyStream(b, c);
                    out = typecast(c.toByteArray, 'uint8');
            end

            out = out(:);
        end


        %-----------------------------------------------------------------%
        function out = gzipNET(operation, in)
            arguments
                operation (1,1) string {mustBeMember(operation, ["compress", "decompress"])}
                in (:,1) uint8
            end

            switch operation
                case "compress"
                    ms = System.IO.MemoryStream();
                    gz = System.IO.Compression.GZipStream(ms, System.IO.Compression.CompressionLevel.Optimal);

                    gz.Write(in, 0, numel(in));
                    gz.Close();

                    out = uint8(ms.ToArray());

                case "decompress"
                    src = System.IO.MemoryStream(in);
                    gz  = System.IO.Compression.GZipStream(src, System.IO.Compression.CompressionMode.Decompress);
                    dst = System.IO.MemoryStream();

                    gz.CopyTo(dst);
                    gz.Close();

                    out = uint8(dst.ToArray());
                    dst.Close();
            end

            out = out(:);
        end
    end
end