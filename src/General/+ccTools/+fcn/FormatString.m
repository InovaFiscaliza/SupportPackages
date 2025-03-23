function formattedString = FormatString(unformattedString)

    arguments
        unformattedString string
    end

    formattedString = char(strjoin("""" + unformattedString + """", ', '));

end