classdef (Abstract) Constants

    properties (Constant)
        %-----------------------------------------------------------------%
        libName = 'reportLib'
        libVersion = '0.03'
    end


    methods (Static=true)
        %-----------------------------------------------------------------%
        function libVersion = getVersion()
            libVersion = struct('name',    reportLib.Constants.libName, ...
                                'version', reportLib.Constants.libVersion);
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