function waitfor(obj, propName, condition, PAUSE, TIMEOUT)

    tWaitFor = tic;
    while toc(tWaitFor) < TIMEOUT
        if condition(obj.(propName))
            break
        end
        pause(PAUSE)
    end

end