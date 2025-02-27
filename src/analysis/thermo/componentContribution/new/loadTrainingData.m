function training_data = loadTrainingData(param)
% Generates the structure that contains all the training data needed for
% Component Contribution.
%
% USAGE:
%
%    training_data = loadTrainingData(formation_weight)
%
% INPUT:
%    formation_weight:    the relative weight to give the formation energies (Alberty's data)
%                         compared to the reaction measurements (TECRDB)
%
% OUTPUT:
%    training_data:       structure with data for Component Contribution
%                         *.S   `m x n` stoichiometric matrix of training data
%                         *.cids: `m x 1` compound ids
%                         *.dG0_prime: `n x 1`
%                         *.T:  `n x 1`
%                         *.I:  `n x 1`
%                         *.pH:  `n x 1`
%                         *.pMg:  `n x 1`
%                         *.weights:  `n x 1`
%                         *.balance:  `n x 1`
%                         *.cids_that_dont_decompose: k x 1 ids of compounds that do not decompose

if ~exist('param','var')
    formation_weight = 1;
    use_cached_kegg_inchis=true;
    use_model_pKas_by_default=true;
else
    if ~isfield(param,'formation_weight')
        formation_weight = 1;
    end
    if ~isfield(params,'use_cached_kegg_inchis')
        use_cached_kegg_inchis = true;
        % use_cached_kegg_inchis = false;
    else
        use_cached_kegg_inchis=params.use_cached_kegg_inchis;
    end
    if ~isfield(params,'use_model_pKas_by_default')
        use_model_pKas_by_default = true;
    else
        use_model_pKas_by_default=params.use_model_pKas_by_default;
    end
end

TECRDB_TSV_FNAME = 'data/TECRDB.tsv';
FORMATION_TSV_FNAME = 'data/formation_energies_transformed.tsv';
REDOX_TSV_FNAME = 'data/redox.tsv';

WEIGHT_TECRDB = 1;
WEIGHT_FORMATION = formation_weight;
WEIGHT_REDOX = formation_weight;

R=8.31451;
%Energies are expressed in kJ mol^-1.*)
R=R/1000; % kJ/mol/K
%Faraday Constant (kJ/mol)
F=96.48; %kJ/mol

if ~exist(TECRDB_TSV_FNAME, 'file')
    error(['file not found: ', TECRDB_TSV_FNAME]);
end

if ~exist(FORMATION_TSV_FNAME, 'file')
    error(['file not found: ', FORMATION_TSV_FNAME]);
end

if ~exist(REDOX_TSV_FNAME, 'file')
    error(['file not found: ', REDOX_TSV_FNAME]);
end

% Read the raw data of TECRDB (NIST)
reactions = {};
cids = [];
cids_that_dont_decompose = [];
thermo_params = []; % columns are: dG'0, T, I, pH, pMg, weight, balance?


fid = fopen(TECRDB_TSV_FNAME, 'r');
% fields are: 
% URL
% REF_ID
% METHOD
% EVAL
% EC
% ENZYME NAME
% REACTION IN KEGG IDS
% REACTION IN COMPOUND NAMES
% K
% K'
% T
% I
% pH
% pMg

res = textscan(fid, '%s%s%s%s%s%s%s%s%f%f%f%f%f%f', 'delimiter','\t');
fclose(fid);

inds = find(~isnan(res{10}) .* ~isnan(res{11}) .* ~isnan(res{13}));

dG0_prime = -R * res{11}(inds) .* log(res{10}(inds)); % calculate dG'0
thermo_params = [dG0_prime, res{11}(inds), res{12}(inds), res{13}(inds), ...
                 res{14}(inds), WEIGHT_TECRDB * ones(size(inds)), ...
                 true(size(inds))];

% parse the reactions in each row
for i = 1:length(inds)
    sprs = reaction2sparse(res{7}{inds(i)});
    cids = unique([cids, find(sprs)]);
    reactions = [reactions, {sprs}];
end
fprintf('Successfully added %d values from TECRDB\n', length(inds));

% Read the Formation Energy data.
fid = fopen(FORMATION_TSV_FNAME, 'r');
fgetl(fid); % skip the first header line
% fields are: 
% cid
% name
% dG'0
% pH
% I
% pMg
% T
% decompose?
% compound_ref
% remark
res = textscan(fid, '%f%s%f%f%f%f%f%f%s%s', 'delimiter','\t');
fclose(fid);

inds = find(~isnan(res{3}));
thermo_params = [thermo_params; [res{3}(inds), res{7}(inds), res{5}(inds), ...
                                 res{4}(inds), res{6}(inds), ...
                                 WEIGHT_FORMATION * ones(size(inds)), ...
                                 false(size(inds))]];
for i = 1:length(inds)
    sprs = sparse([]);
    sprs(res{1}(inds(i))) = 1;
    reactions = [reactions, {sprs}];
end

cids = union(cids, res{1}');
cids_that_dont_decompose = res{1}(find(res{8} == 0));

fprintf('Successfully added %d formation energies\n', length(res{1}));


% Read the Reduction potential data.
fid = fopen(REDOX_TSV_FNAME, 'r');
fgetl(fid); % skip the first header line
% fields are: 
% name
% CID_ox
% nH_ox
% charge_ox
% CID_red
% nH_red,
% charge_red
% E'0
% pH
% I
% pMg
% T
% ref
res = textscan(fid, '%s%f%f%f%f%f%f%f%f%f%f%f%s', 'delimiter', '\t');
fclose(fid);

delta_e = (res{6} - res{3}) - (res{7} - res{4}); % delta_nH - delta_charge
dG0_prime = -F * res{8} .* delta_e;
thermo_params = [thermo_params; [dG0_prime, res{12}, res{10}, res{9}, ...
                                 res{11}, ...
                                 WEIGHT_REDOX * ones(size(dG0_prime)), ...
                                 false(size(dG0_prime))]];

for i = 1:length(res{1})
    sprs = sparse([]);
    sprs(res{2}(i)) = -1;
    sprs(res{5}(i)) = 1;
    cids = unique([cids, res{2}(i), res{5}(i)]);
    reactions = [reactions, {sprs}];
end

fprintf('Successfully added %d redox potentials\n', length(res{1}));

% convert the list of reactions in sparse notation into a full
% stoichiometric matrix, where the rows (compounds) are according to the
% CID list 'cids'.
S = zeros(length(cids), length(reactions));
for i = 1:length(reactions)
    r = reactions{i};
    S(ismember(cids, find(r)), i) = r(r ~= 0);
end

training_data.S = sparse(S);

if ~isfield(training_data,'rxns')
    for i=1:size(training_data.S,2)
        training_data.rxns{i,1}=['rxn' int2str(i)];
    end
end
if ~isfield(training_data,'lb')
    training_data.lb=ones(size(training_data.S,2),1)*-inf;
end
if ~isfield(training_data,'ub')
    training_data.lb=ones(size(training_data.S,2),1)*inf;
end

training_data.cids = cids';
training_data.dG0_prime = thermo_params(:, 1);
training_data.T = thermo_params(:, 2);
training_data.I = thermo_params(:, 3);
training_data.pH = thermo_params(:, 4);
training_data.pMg = thermo_params(:, 5);
training_data.weights = thermo_params(:, 6);
training_data.balance = thermo_params(:, 7);
training_data.cids_that_dont_decompose = cids_that_dont_decompose;



