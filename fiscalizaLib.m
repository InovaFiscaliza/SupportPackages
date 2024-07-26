classdef fiscalizaLib < handle

    properties (Access = protected)
        %-----------------------------------------------------------------%
        Fiscaliza
        Issue
    end


    properties
        %-----------------------------------------------------------------%
        issueID
        issueInfo
    end


    methods
        %-----------------------------------------------------------------%
        function obj = fiscalizaLib(userName, userPass, testFlag)
            arguments
                userName (1,:) char
                userPass (1,:) char
                testFlag (1,1) logical
            end

            pyMod = py.importlib.import_module('fiscaliza.main');
            py.importlib.reload(pyMod);

            obj.Fiscaliza = pyMod.Fiscaliza(pyargs('username', userName, 'password', userPass, 'teste', testFlag));
        end


        %-----------------------------------------------------------------%
        function getIssue(obj, issueNumber)
            if isnumeric(issueNumber)
                issueNumber = num2str(issueNumber);
            end

            obj.Issue = obj.Fiscaliza.get_issue(issueNumber);

            issueType = char(obj.Issue.type);
            if ~strcmp(issueType, 'atividade_de_inspecao')
                error('O relato da lib fiscaliza é restrito às <i>issues</i> do tipo "Atividade de inspeção". A <i>issue</i> nº %s, contudo, é um objeto Redmine do tipo "%s"', issueNumber, issueType)
            end
            
            obj.issueID   = issueNumber;
            obj.issueInfo = DataTypeMapping(obj, 'py2mat', py.getattr(obj.Issue, 'attrs'));
        end


        %-----------------------------------------------------------------%
        function refreshIssue(obj)
            if isempty(obj.issueID)
                error('The "getIssue" method must be called before the "refreshIssue" method.')
            end

            obj.Issue.refresh();
            obj.issueInfo = DataTypeMapping(obj, 'py2mat', py.getattr(obj.Issue, 'attrs'));
        end


        %-----------------------------------------------------------------%
        function updateFields(obj, matData)
            pyData = DataTypeMapping(obj, 'mat2py', matData);

            obj.Issue.update_fields(pyData);
            obj.issueInfo = DataTypeMapping(obj, 'py2mat', py.getattr(obj.Issue, 'attrs'));
        end


        %-----------------------------------------------------------------%
        function updateIssue(obj, matData)
            pyData = DataTypeMapping(obj, 'mat2py', matData);

            obj.Issue.update(pyData)
            obj.issueInfo = DataTypeMapping(obj, 'py2mat', py.getattr(obj.Issue, 'attrs'));
        end
    end


    methods (Access = protected)
        %-----------------------------------------------------------------%
        function path = Path(obj)
            path = fileparts(mfilename('fullpath'));
        end


        %-----------------------------------------------------------------%
        function outValue = DataTypeMapping(obj, convertionType, inValue)
            inClass = class(inValue);

            switch convertionType
                % Foram mapeados apenas os tipos de dados retornados pela lib 
                % fiscaliza. Há, contudo, tipos de dados ainda não mapeados aqui.
                % Por exemplo: "py.numpy.ndarray, "py.pandas.DataFrame" etc.
                case 'py2mat'
                    switch inClass
                        case 'py.int'
                            outValue = int64(inValue);

                        case 'py.float'
                            outValue = double(inValue);

                        case 'py.bool'
                            outValue = logical(inValue);

                        case 'py.str'
                            % O FISCALIZA tem alguns campos customizados que parecem 
                            % um JSON (encapsulados com os caracteres "=>" e "'" ao 
                            % invés de ":" e """). A ideia aqui é tentar retornar uma 
                            % estrutura, caso se perceba que se trata de um deles.
                            outValue = isJSONFormat(obj, char(inValue));
                            if strcmp(outValue, 'None')
                                outValue = '';
                            end

                        case 'py.list'
                            outValue = cell(inValue);
                            for ii = 1:numel(outValue)
                                outValue{ii} = DataTypeMapping(obj, convertionType, outValue{ii});
                            end

                        case 'py.dict'
                            outValue = struct(inValue);
                            fieldNames = fieldnames(outValue);
                            for ii = 1:numel(fieldNames)
                                outValue.(fieldNames{ii}) = DataTypeMapping(obj, convertionType, outValue.(fieldNames{ii}));
                            end

                        case 'py.NoneType'
                            outValue = '';

                        otherwise
                            outValue = inValue;
                    end

                % No caso das conversões Matlab >> Python, foram mapeadas apenas 
                % conversões simples requeridas pela lib para atualização de uma
                % issue.
                case 'mat2py'
                    if ~isscalar(inValue) && (isstring(inValue) || isnumeric(inValue) || islogical(inValue) || isstruct(inValue))
                        inValue = num2cell(inValue);
                        inClass = class(inValue);
                    end

                    switch inClass
                        case {'char', 'str'}
                            outValue = py.str(inValue);

                        case 'cell'
                            for ii = 1:numel(inValue)
                                inValue{ii} = DataTypeMapping(obj, convertionType, inValue{ii});
                            end
                            outValue = py.list(inValue);

                        case 'struct'
                            fieldNames = fieldnames(inValue);
                            for ii = 1:numel(fieldNames)
                                inValue.(fieldNames{ii}) = DataTypeMapping(obj, convertionType, inValue.(fieldNames{ii}));
                            end
                            outValue = py.dict(inValue);

                        case 'logical'
                            outValue = py.bool(inValue);

                        otherwise
                            if isnumeric(inValue)
                                if isInteger(obj, inValue)
                                    outValue = py.int(inValue);
                                else
                                    outValue = py.float(inValue);
                                end
                            else
                                outValue = inValue;
                            end
                    end
            end
        end
    end

        
    methods (Access = private)
        %-----------------------------------------------------------------%
        function fieldValue = isJSONFormat(obj, fieldValue)
            try
                tempValue = jsondecode(replace(fieldValue, {'=>', ''''}, {':', '"'}));

                if isstruct(tempValue)
                    fieldValue = tempValue;
                end

            catch
            end
        end


        %-----------------------------------------------------------------%
        function status = isInteger(obj, matValue)
            status = false;
            if all(abs(matValue-round(matValue)) < 1e-5)
                status = true;
            end
        end
    end
end