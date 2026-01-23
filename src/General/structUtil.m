classdef (Abstract) structUtil

    methods (Static = true)
        %-----------------------------------------------------------------%
        function outStruct = sortByFieldNames(inStruct)
            arguments
                inStruct struct
            end

            fieldNames = fieldnames(inStruct);
            [~, idx]   = sort(lower(fieldNames));
            fieldNames = fieldNames(idx);
            outStruct  = struct();
            for ii = 1:numel(fieldNames)
                outStruct.(fieldNames{ii}) = inStruct.(fieldNames{ii});
            end
        end

        %-----------------------------------------------------------------%
        function outStruct = renameFieldNames(inStruct, fieldNameMapping)
            arguments
                inStruct struct
                fieldNameMapping dictionary
            end

            fieldNames = fieldnames(inStruct);
            outStruct  = struct();
            for ii = 1:numel(fieldNames)
                fieldName = fieldNames{ii};
                if isKey(fieldNameMapping, fieldName)
                    fieldName = fieldNameMapping(fieldName);
                end

                outStruct.(fieldName) = inStruct.(fieldNames{ii});
            end
        end

        %-----------------------------------------------------------------%
        function outStruct = addingFields(inStruct, refStruct)
            arguments
                inStruct  struct
                refStruct struct
            end

            outStruct     = inStruct;

            inFieldNames  = fieldnames(inStruct);
            refFieldNames = fieldnames(refStruct);

            for ii = 1:numel(refFieldNames)
                if ~ismember(refFieldNames{ii}, inFieldNames)
                    outStruct.(refFieldNames{ii}) = refStruct.(refFieldNames{ii});
                end
            end
        end

        %-----------------------------------------------------------------%
        function outStruct = delEmptyFields(inStruct, fieldsToRemove)
            arguments
                inStruct  struct
                fieldsToRemove cell = {}
            end

            outStruct  = rmfield(inStruct, fieldsToRemove);
            fieldNames = fieldnames(outStruct);

            for ii = 1:numel(fieldNames)
                if isempty(outStruct.(fieldNames{ii}))
                    outStruct = rmfield(outStruct, fieldNames{ii});
                end
            end
        end

        %-----------------------------------------------------------------%
        function status = hasMatchingFields(inStruct1, inStruct2, fieldsToCompare)
            arguments
                inStruct1       struct {mustBeNonempty, mustBeScalarOrEmpty}
                inStruct2       struct {mustBeNonempty, mustBeScalarOrEmpty}
                fieldsToCompare cell   {mustBeNonempty, mustBeText}
            end

            if any(~ismember(fieldsToCompare, fields(inStruct1))) || any(~ismember(fieldsToCompare, fields(inStruct2)))
                error('BothStructsMustContainAllFieldsForComparison')
            end

            status = true;
            for ii = 1:numel(fieldsToCompare)
                fieldToCompare = fieldsToCompare{ii};

                if ~isequal(inStruct1.(fieldToCompare), inStruct2.(fieldToCompare))
                    status = false;
                    return
                end
            end
        end

        %-----------------------------------------------------------------%
        function outCell = struct2cellWithFields(inStruct)
            % inStruct = struct('field1', value1, 'field2', value2)
            % outCell  = {'field1', value2, 'field2', value2}
            arguments
                inStruct struct
            end

            outCell = [fieldnames(inStruct)'; struct2cell(inStruct)'];
            outCell = outCell(:)';
        end

        %-----------------------------------------------------------------%
        function outStruct = createStructFromCell(inCellArray)
            for ii = 1:numel(inCellArray)
                outStruct.(inCellArray{ii}) = [];
            end
        end
    end

end