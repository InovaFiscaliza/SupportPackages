classdef (Abstract) Constants

    properties (Constant)
        %-----------------------------------------------------------------%
        libName       = 'reportLib'
        libRelease    = 'R2024a'
        libVersion    = '0.02'
    end


    methods (Static=true)
        %-----------------------------------------------------------------%
        function libVersion = ReportLib()
            libVersion = struct('name',    reportLib.Constants.libName,    ...
                                'release', reportLib.Constants.libRelease, ...
                                'version', reportLib.Constants.libVersion);
        end


        %-----------------------------------------------------------------%
        function machineVersion = MachineVersion()
            machineVersion = struct('name',         'MACHINE',                                   ...
                                    'platform',     ccTools.fcn.OperationSystem('platform'),     ...
                                    'version',      ccTools.fcn.OperationSystem('ver'),          ...
                                    'computerName', ccTools.fcn.OperationSystem('computerName'), ...
                                    'userName',     ccTools.fcn.OperationSystem('userName'));
        end


        %-----------------------------------------------------------------%
        function matlabVersion = MatlabVersion()
            matVersion    = version;    
            matProducts   = struct2table(ver);

            matlabVersion = struct('name',        'MATLAB',                                   ...
                                   'release',     char(extractBetween(matVersion, '(', ')')), ...
                                   'version',     extractBefore(matVersion, ' '),             ...
                                   'path',        matlabroot,                                 ...
                                   'productList', char(strjoin(matProducts.Name + " v. " + matProducts.Version, ', ')));
        end


        %-----------------------------------------------------------------%
        function s = logical2String(l, sClass)
            arguments
                l      logical {mustBeVector}
                sClass {mustBeTextScalar, ismember(sClass, {'cellstr', 'string', 'categorical'})} = 'string'
            end

            d = dictionary([true, false], ["Sim", "Não"]);
            s = d(l);

            switch sClass
                case 'categorical'
                    s = categorical(s);
                case 'cellstr'
                    s = cellstr(s);
            end
        end
    end
end