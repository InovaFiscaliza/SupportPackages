function [d, e, c] = remove_sequencias(perfil)
% Remove os valores em sequência com a mesma elevação e mesmo clutter
% d: array de distancias
% e: array de elevações
% c: array de clutter
% perfil: matriz (3, n) contendo distancias, elevações e clutter
    idx = 1;
    d = zeros(size(perfil,2));
    c = d;
    e = d;
    c(idx) = perfil(3, 1);
    e(idx) = perfil(2, 1);
    d(idx) = perfil(1, 1);
    
    %----------------------------------------------------------------------
    % varre a matriz perfil desconsiderando valores repetidos em sequência
    
    if size(perfil, 2) > 1
    
        for n = 2:size(perfil, 2)
            if or((abs(perfil(2,n) - perfil(2, idx)) >= 1),...
                    (abs(perfil(3,n) - perfil(3, idx)) >= 1))
                idx = idx + 1;
                c(idx) = perfil(3, n);
                e(idx) = perfil(2, n);
                d(idx) = perfil(1, n);
            end
        end
        %------------------------------------------------------------------
        
    end

    e = e(1:idx);
    d = d(1:idx);
    c = c(1:idx);

end

