function d = LevenshteinDistance(s1, s2)
    len1 = numel(s1);
    len2 = numel(s2);

    D = zeros(len1+1, len2+1);
    D(:,1) = (0:len1)';
    D(1,:) = 0:len2;

    for ii = 1:len1
        for jj = 1:len2
            cost = s1(ii) ~= s2(jj);
            D(ii+1,jj+1) = min([D(ii,jj+1) + 1, ...
                                D(ii+1,jj) + 1, ...
                                D(ii,jj)   + cost]);
        end
    end
    d = D(len1+1, len2+1);
end