function waitfor(obj, propName, condition, PAUSE, TIMEOUT, ORIENTATION)

    arguments
        obj
        propName
        condition
        PAUSE
        TIMEOUT
        ORIENTATION char {mustBeMember(ORIENTATION, {'propValue', 'propName'})} = 'propValue'
    end

    tWaitFor = tic;
    while toc(tWaitFor) < TIMEOUT
        switch ORIENTATION
            case 'propValue'
                if condition(obj.(propName))
                    break
                end
            case 'propName'
                if condition(propName)
                    break
                end
        end

        pause(PAUSE)
    end

end