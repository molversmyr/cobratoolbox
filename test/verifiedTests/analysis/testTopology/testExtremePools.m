% The COBRAToolbox: testExtremePools.m
%
% Purpose:
%     - testExtremePools tests the functionality of lsr and extremePools.
%
% Authors:
%     - Modified for CI integration - Thomas Pfau
%
% Test problem from
%     Extreme Pathway Lengths and Reaction Participation in Genome-Scale Metabolic Networks
%     Jason A. Papin, Nathan D. Price and Bernhard Ø. Palsson


% save the current path
currentDir = pwd;

% initialize the test
cd(fileparts(which(mfilename)));

%Generate the test model an set up the fields.
model = createExtremePathwayModel();
model = findSExRxnInd(model);

% Extreme pools:
Pools = [0     0     0     1     0     0     1;...
         1     1     0     0     0     2     0;...
         1     1     2     2     2     0     0];      

fprintf('%s\n','Testing Extreme pools')
%calculates the matrix of extreme pools
if isunix
    [CalculatedPools]=extremePools(model);    
    assert(isequal(full(CalculatedPools),Pools));
else
    %Does not work on windows os.
    assert(verifyCobraFunctionError(@(extremePools(model))));
end

cd(currentDir);
