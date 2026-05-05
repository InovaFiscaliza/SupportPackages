function nodePosition = blePositionEstimate(locatorPosition,localizationMethod,varargin)
%blePositionEstimate Estimate Bluetooth LE node position
%
%   NODEPOSITION = blePositionEstimate(LOCATORPOSITION,LOCALIZATIONMETHOD,
%   DIRECTION) estimates the unknown Bluetooth(R) low energy (LE) node
%   position, NODEPOSITION, for the known Bluetooth LE locator positions,
%   LOCATORPOSITION, and the localization method, LOCALIZATIONMETHOD. When
%   you specify the localization method as 'angulation', the function
%   calculates NODEPOSITION by using the angle of arrival (AoA) or angle of
%   departure (AoD), direction, between each locator and node.
%
%   NODEPOSITION is a column vector of size 2-by-1 or 3-by-1, specifying
%   the 2-D or 3-D position (in meters) of the Bluetooth LE node,
%   respectively.
%
%   LOCATORPOSITION is a matrix of size 2-by-N or 3-by-N, specifying the
%   position of N number of locators in a network. Each column of
%   LOCATORPOSITION denotes the 2-D or 3-D position (in meters) of each
%   locator.
%
%   LOCALIZATIONMETHOD is a character vector or a string scalar specifying
%   the localization method. This value must be one of these: 'angulation',
%   'lateration', or 'distance-angle'.
%
%   DIRECTION is a vector of size 1-by-N or a matrix of size 2-by-N, where
%   N represents the number of Bluetooth LE locators in a network. The
%   first row represents the azimuth angles and the second row represents
%   the elevation angles between each Bluetooth LE locator and Bluetooth LE
%   node. The range of azimuth and elevation angles is [-180, 180] degrees
%   and [-90, 90] degrees, respectively.
%
%   NODEPOSITION = blePositionEstimate(LOCATORPOSITION,LOCALIZATIONMETHOD,
%   DISTANCE) estimates the unknown Bluetooth LE node position by using the
%   localization method as 'lateration'. The DISTANCE input specifies the
%   distance between each locator and node.
%
%   DISTANCE is a row vector of size 1-by-N, where N represents the number
%   of Bluetooth LE locators in a network. This value specifies the
%   distances (in meters) between each locator and node.
%
%   NODEPOSITION = blePositionEstimate(LOCATORPOSITION,LOCALIZATIONMETHOD,
%   DISTANCE,DIRECTION) estimates the unknown Bluetooth LE node position by
%   using the localization method as 'direction-angle'.
%
%   % Examples:
%
%   % Example 1:
%   % Estimate the position of a Bluetooth LE transmitter (node) in a 2-D
%   % network consisting of two Bluetooth LE receivers (locators). The two
%   % receivers are located at (-18,-10) and (-40,70). The direction of
%   % signals between each receiver and the transmitter are 29.0546 degrees
%   % and -60.2551 degrees in azimuth, respectively. The actual position of
%   % the Bluetooth LE transmitter is at the origin (0,0).
%
%   % As the direction of signals are known, the localization method must
%   % be 'angulation'
%   localizationMethod = 'angulation';
%   rxPosition = [-18 -40;-10 70]; % Receiver positions
%   azimAngles = [29.0546 -60.2551]; % Azimuth angles of the signals
%   txPosition = blePositionEstimate(rxPosition,localizationMethod,...
%                       azimAngles); % Estimate the transmitter position
%
%   % Example 2:
%   % Estimate the position of a Bluetooth LE receiver (node) in a 3-D
%   % network consisting of four Bluetooth LE transmitters (locators). The
%   % four transmitters are located at (-5,8.6603,-17.3205),
%   % (-15,-15,21.2132), (-30,-17.3205,20), (-12.5,-21.6506,43.3013). The
%   % distances between each transmitter and the receiver are 13.2964,
%   % 33.4221, 40, and 55.0728 meters. The actual location of the Bluetooth
%   % LE receiver is [-7.5,4.33,-5].
%
%   % As the distances are known, the localization method must be
%   % 'lateration'.
%   localizationMethod = 'lateration';
%   txPosition = [-5 -15 -30 -12.5;8.6603 -15 -17.3205 -21.6506;...
%   -17.3205 21.2132 20 43.3013]; % Transmitter positions
%   distance = [13.2964 33.4221 40 55.0728]; % Distance between each
%                                            % transmitter and receiver
%   rxPosition = blePositionEstimate(txPosition,localizationMethod,...
%                       distance); % Estimate the receiver position
%
%   See also bleAngleEstimate, bleWaveformGenerator, bleIdealReceiver,
%   bleAngleEstimateConfig.

%   Copyright 2021 The MathWorks, Inc.

%#codegen

% Check the number of input arguments
narginchk(3,4)

% Validate the input arguments
[localizationMethod,numDimensions,numLocators] = ....
            validateInputArgs(locatorPosition,localizationMethod,varargin{:});

if strcmp(localizationMethod,'angulation')
    direction = varargin{1};
    x = locatorPosition(1,:); % X-coordinates for all the locators
    y = locatorPosition(2,:); % Y-coordinates for all the locators
    azimAngles = direction(1,:); % Azimuth angles
    z = locatorPosition(end,:); % Z-coordinates for all the locators
    eleAngles = direction(end,:); % Elevation angles
    constZY = tand(eleAngles)./sind(azimAngles);
    if numDimensions == 2 || (numDimensions == 3 && ...
        all(round(constZY) == round(constZY(1))) || any(abs(azimAngles)<10))
        % Compute x, y coordinates of the node using azimuth angles and x, y
        % coordinates of locators
        A = [tand(azimAngles).' repmat(-1,numLocators,1)];
        B = x.*tand(azimAngles)-y;
        idx1 = find(A(:,1) ==  Inf);
        idx2 = find(A(:,1) == -Inf);
        if ~isempty(idx1)
            A(idx1,:) = repmat([1 0],numel(idx1),1);
            B(idx1) = x(idx1);
        end
        if ~isempty(idx2)
            A(idx2,:) = repmat([-1 0],numel(idx2),1);
            B(idx2) = -x(idx2);
        end
        posXY = (A.'*A)\(A.'*B(:));
        if numDimensions == 3
            % Compute z coordinates of the node using elevation angles
            d = sqrt((posXY(1)-x).^2+(posXY(2)-y).^2);
            posZ = mean(z+d.*tand(eleAngles));
            nodePosition = [posXY;posZ];
        else
            nodePosition = posXY;
        end
    else % If azimuth angles are almost equal
        A1 = [ones(numLocators,1) -constZY.'];
        B1 = z-y.*constZY;
        idx3 = find(constZY ==  Inf);
        idx4 = find(constZY == -Inf);
        if ~isempty(idx3)
            A1(idx3,:) = repmat([-1 0],numel(idx3),1);
            B1(idx3) = -y(idx3);
            x(idx3) = [];
            azimAngles(idx3) = [];
            y(idx3) = [];
        end
        if ~isempty(idx4)
            A1(idx4,:) = repmat([1 0],numel(idx4),1);
            B1(idx4) = y(idx4);
            x(idx4) = [];
            azimAngles(idx4) = [];
            y(idx4) = [];
        end
        posZY = (A1.'*A1)\(A1.'*B1(:));
        posX = (posZY(2)-y)./tand(azimAngles)+x;
        [xMax,xMaxInd] = max(abs(posX));
        xMaxDiff = xMax-abs(posX) > 20;
        if any(xMaxDiff)
            posX(xMaxInd) = [];
        end
        posXAvg = mean(posX);
        nodePosition = [posXAvg;posZY(2);posZY(1)];
    end
elseif strcmp(localizationMethod,'lateration')
    distance = varargin{1};
    % Compute the node position using distances
    A = 2*(locatorPosition(:,1:end-1)-repmat(locatorPosition(:,end),1,numLocators-1)).';
    B = sum(locatorPosition(:,1:end-1).^2-...
        repmat(locatorPosition(:,end),1,numLocators-1).^2)+...
        distance(end)^2-distance(1:end-1).^2;
    nodePosition = (A.'*A)\(A.'*B(:));
else
    distance = varargin{1};
    direction = varargin{2};
    % Angles defined in local coordinate system
    if numDimensions == 2
        inc = [cosd(direction(1,:));sind(direction(1,:))];
    else
        inc = [cosd(direction(2,:)).*cosd(direction(1,:));...
               cosd(direction(2,:)).*sind(direction(1,:));...
               sind(direction(2,:))];
    end
    nodePosition = mean(locatorPosition+distance.*inc,2);
end
end

function [localizationMethod,numDimensions,numLocators] = ....
                                    validateInputArgs(locatorPosition,localizationMethod,varargin)

% Validate the locator positions
validateattributes(locatorPosition,{'double'},{'nonnan','finite','real'},...
                        mfilename,'locatorPosition');
[numDimensions, numLocators] = size(locatorPosition); % Dimensions and number of locators
coder.internal.errorIf(numDimensions < 2 || numDimensions > 3,...
        'bluetooth:blePositionEstimate:PositionRowSize',numDimensions);

% Validate the localization method
localizationMethod = validatestring(localizationMethod,{'angulation',...
    'lateration','distance-angle'},mfilename,'localizationMethod');

if strcmp(localizationMethod,'angulation')
    narginchk(3,3)

    % Validate the locator position size
    coder.internal.errorIf(numLocators < numDimensions-1,...
        'bluetooth:blePositionEstimate:AngulationPositionSize');

    % Validate the azimuth and elevation angles
    direction = varargin{1};
    validateattributes(direction,{'double'},{'nonnan','finite','real'},...
                        mfilename,'direction');
    coder.internal.errorIf(numLocators ~= size(direction,2),...
        'bluetooth:blePositionEstimate:NumLocators','''direction''','');
    coder.internal.errorIf(size(direction,1) ~= size(locatorPosition,1)-1,...
        'bluetooth:blePositionEstimate:PositionDirectionRowSize');
    azimAngles = direction(1,:); % Azimuth angles
    coder.internal.errorIf(all(azimAngles == 0 | azimAngles == 180 | azimAngles == -180)...
        && numDimensions == 2,'bluetooth:blePositionEstimate:InvalidAzimuthCombination');
    coder.internal.errorIf(all(azimAngles == azimAngles(1)) && numDimensions == 2,...
        'bluetooth:blePositionEstimate:AngleRowValues');
    coder.internal.errorIf(all(abs(azimAngles) == 90),...
        'bluetooth:blePositionEstimate:AzimAngleNinetyDeg');
    coder.internal.errorIf(any(abs(azimAngles) > 180),...
        'bluetooth:blePositionEstimate:AngleValues','First','azimuth',180);
    if numDimensions == 3
        eleAngles = direction(2,:); % Elevation angles
        coder.internal.errorIf(any(abs(eleAngles) > 90),...
        'bluetooth:blePositionEstimate:AngleValues','Second','elevation',90);
        coder.internal.errorIf(all(azimAngles == azimAngles(1)) && all(eleAngles == eleAngles(1)),...
        'bluetooth:blePositionEstimate:AngleRowValues');
    end
elseif strcmp(localizationMethod,'lateration')
    narginchk(3,3)

    % Validate the locator position size
    coder.internal.errorIf(numLocators <= numDimensions,...
        'bluetooth:blePositionEstimate:LaterationPositionSize');

    % Validate the distance
    distance = varargin{1};
    validateattributes(distance,{'double'},{'nonnan','finite','real','nonnegative','row'},...
                        mfilename,'distance');
    coder.internal.errorIf(numLocators ~= size(distance,2),...
        'bluetooth:blePositionEstimate:NumLocators','''distance''','');
else
    narginchk(4,4)
    distance = varargin{1};
    direction = varargin{2};

    % Validate the distance(s) and direction(s)
    validateattributes(distance,{'double'},{'nonnan','finite','real','nonnegative','row'},...
                        mfilename,'distance');
    validateattributes(direction,{'double'},{'nonnan','finite','real'},...
                        mfilename,'direction');
    coder.internal.errorIf(size(direction,1) ~= size(locatorPosition,1)-1,...
        'bluetooth:blePositionEstimate:PositionDirectionRowSize');
    coder.internal.errorIf(numLocators ~= size(distance,2) || numLocators ~= size(direction,2),...
        'bluetooth:blePositionEstimate:NumLocators','''distance''',', ''direction'', ')
    coder.internal.errorIf(any(abs(direction(1,:)) > 180),...
        'bluetooth:blePositionEstimate:AngleValues','First','azimuth',180);
    if numDimensions == 3
        coder.internal.errorIf(any(abs(direction(2,:)) > 90),...
        'bluetooth:blePositionEstimate:AngleValues','Second','elevation',90);
    end
end
end