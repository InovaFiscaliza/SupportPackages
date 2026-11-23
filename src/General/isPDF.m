function [tf, msg] = isPDF(filePath)

    tf = false;
    msg = '';

    if ~isfile(filePath)
        msg = 'Arquivo inexistente.';
        return
    end

    fid = fopen(filePath, 'r');

    if fid == -1
        msg = 'Não foi possível abrir o arquivo.';
        return
    end

    fileCloser = onCleanup(@() fclose(fid));

    % Leitores toleram bytes iniciais antes da assinatura, desde que ela
    % esteja nos primeiros 1024 bytes.
    header = fread(fid, 1024, '*uint8')';
    tf = contains(char(header), '%PDF-');

    if ~tf
        frewind(fid)
        content = fread(fid, 500, '*uint8')';
        if isempty(content) || any(content == 0)
            msg = 'O arquivo não é um PDF válido.';
        else
            msg = strtrim(native2unicode(content, 'UTF-8'));
            if isempty(msg)
                msg = 'O arquivo não é um PDF válido.';
            end
        end
    end

end