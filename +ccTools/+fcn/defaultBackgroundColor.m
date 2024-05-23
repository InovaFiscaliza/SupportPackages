function color = defaultBackgroundColor()

    releaseVersion = version('-release');
    releaseYear    = str2double(releaseVersion(1:4));

    if releaseYear < 2022
        color = "rgba(0, 0, 0, 0.65)";
    else
        color = "rgba(255, 255, 255, 0.65)";
    end
end