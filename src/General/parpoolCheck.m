function parpoolCheck()
    p = gcp("nocreate");
    if isempty(p)
        parpool("Threads");
    end
end