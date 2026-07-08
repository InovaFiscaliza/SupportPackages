function [methodinfo, structs, enuminfo, thunkLibName] = CelZip64Proto()
    ival = {cell(1, 0)};
    structs = [];
    enuminfo = [];
    fcnNum = 1;
    fcns = struct('name', ival, 'calltype', ival, 'LHS', ival, 'RHS', ival, 'alias', ival, 'thunkname', ival);
    thunkLibName = '';

    fcns.name{fcnNum}     = 'CelZipDllVersion';
    fcns.calltype{fcnNum} = 'cdecl';
    fcns.LHS{fcnNum}      = 'int32';
    fcns.RHS{fcnNum}      = [];
    fcns.alias{fcnNum}    = 'CelZipDllVersion';
    fcns.thunkname{fcnNum} = '';
    fcnNum = fcnNum + 1;

    fcns.name{fcnNum}     = 'IsCompressedFile';
    fcns.calltype{fcnNum} = 'cdecl';
    fcns.LHS{fcnNum}      = 'uint8';
    fcns.RHS{fcnNum}      = {'cstring'};
    fcns.alias{fcnNum}    = 'IsCompressedFile';
    fcns.thunkname{fcnNum} = '';
    fcnNum = fcnNum + 1;

    fcns.name{fcnNum}     = 'FullDecompression';
    fcns.calltype{fcnNum} = 'cdecl';
    fcns.LHS{fcnNum}      = 'int32';
    fcns.RHS{fcnNum}      = {'voidPtrPtr', 'cstring', 'cstring'};
    fcns.alias{fcnNum}    = 'FullDecompression';
    fcns.thunkname{fcnNum} = '';
    fcnNum = fcnNum + 1;

    fcns.name{fcnNum}     = 'FreeComprMem';
    fcns.calltype{fcnNum} = 'cdecl';
    fcns.LHS{fcnNum}      = [];
    fcns.RHS{fcnNum}      = {'voidPtr'};
    fcns.alias{fcnNum}    = 'FreeComprMem';
    fcns.thunkname{fcnNum} = '';

    methodinfo = fcns;
end
