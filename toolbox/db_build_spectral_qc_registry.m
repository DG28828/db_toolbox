function QC = db_build_spectral_qc_registry(db_dir, varargin)
%DB_BUILD_SPECTRAL_QC_REGISTRY
% Crea un registro externo de bursts excluidos según el error relativo
% entre la varianza temporal y el momento espectral de orden cero.
%
% El registro se aplica sobre la dimensión "burst" limpia de los archivos
% espectrales y direccionales. No modifica ningún archivo netCDF.
%
% Ejemplo:
%
%   QC = db_build_spectral_qc_registry( ...
%       'C:\COPC_db', ...
%       'Sites', ["Cabo_Velas","Cabo_Blanco"], ...
%       'ThresholdPct', 10, ...
%       'ErrorScale', 1);

%% Entradas

p = inputParser;
p.FunctionName = mfilename;

addRequired(p, 'db_dir', @(x) ischar(x) || isstring(x));

addParameter(p, 'Sites', string.empty(0,1), @(x) isempty(x) || ischar(x) || isstring(x) || iscellstr(x));

addParameter(p, 'ThresholdPct', 10, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);

addParameter(p, 'ErrorScale', 1, @(x) isnumeric(x) && isscalar(x) && isfinite(x));

addParameter(p, 'OutputFile', "", @(x) ischar(x) || isstring(x));

addParameter(p, 'WriteCSV', true, @(x) islogical(x) && isscalar(x));

addParameter(p, 'Verbose', true, @(x) islogical(x) && isscalar(x));

parse(p, db_dir, varargin{:});
opts = p.Results;

db_dir = char(string(db_dir));
sites = string(opts.Sites);
sites = sites(:);

if ~isfolder(db_dir)
    error('No existe el directorio de la base de datos: %s', db_dir);
end

%% Argumentos comunes para db_extract_ncvar

extractArgs = { ...
    'Verbose', opts.Verbose, ...
    'Concat', true};

if ~isempty(sites)
    extractArgs = [extractArgs, {'Sites', cellstr(sites)}];
end

%% Extraer variables QC

D_error = db_extract_ncvar( ...
    db_dir, ...
    'spectral', ...
    '/qc/error', ...
    extractArgs{:});

D_m0 = db_extract_ncvar( ...
    db_dir, ...
    'spectral', ...
    '/qc/m0', ...
    extractArgs{:});

D_var = db_extract_ncvar( ...
    db_dir, ...
    'spectral', ...
    '/qc/var', ...
    extractArgs{:});

%% Convertir cada salida en una tabla con claves estables

T_error = local_scalar_output_to_table( ...
    D_error, ...
    "error_stored");

T_m0 = local_scalar_output_to_table( ...
    D_m0, ...
    "m0");

T_var = local_scalar_output_to_table( ...
    D_var, ...
    "variance");

if isempty(T_error)
    error('No se encontraron valores válidos de /qc/error.');
end

keys = {'site','campaign','burst_index'};

%% Mantener los tiempos auxiliares para verificar alineación

T_m0 = renamevars(T_m0, 'time', 'time_m0');
T_var = renamevars(T_var, 'time', 'time_variance');

%% Unir sin depender de la posición concatenada

T = outerjoin( ...
    T_error, ...
    T_m0, ...
    'Keys', keys, ...
    'MergeKeys', true, ...
    'Type', 'left');

T = outerjoin( ...
    T, ...
    T_var, ...
    'Keys', keys, ...
    'MergeKeys', true, ...
    'Type', 'left');

%% Verificar que los tiempos coincidan

timeTolerance = milliseconds(1);

idxCheck = ...
    ~isnat(T.time) & ...
    ~isnat(T.time_m0);

idxMismatch = false(height(T),1);

idxMismatch(idxCheck) = ...
    abs(T.time(idxCheck) - T.time_m0(idxCheck)) > timeTolerance;

if any(idxMismatch)
    error(['Se encontraron %d bursts para los cuales el tiempo de /qc/m0 ' ...
           'no coincide con el tiempo de /qc/error.'], ...
           sum(idxMismatch));
end

idxCheck = ...
    ~isnat(T.time) & ...
    ~isnat(T.time_variance);

idxMismatch = false(height(T),1);

idxMismatch(idxCheck) = ...
    abs(T.time(idxCheck) - T.time_variance(idxCheck)) > timeTolerance;

if any(idxMismatch)
    error(['Se encontraron %d bursts para los cuales el tiempo de /qc/var ' ...
           'no coincide con el tiempo de /qc/error.'], ...
           sum(idxMismatch));
end

T = removevars(T, {'time_m0','time_variance'});

%% Convertir el error a porcentaje

T.error_pct = double(T.error_stored) .* opts.ErrorScale;
T = removevars(T, 'error_stored');

%% Identificar registros válidos

T.qc_available = ...
    ~isnat(T.time) & ...
    strlength(T.site) > 0 & ...
    strlength(T.campaign) > 0 & ...
    isfinite(T.error_pct);

%% Aplicar criterio de exclusión

T.flag_var_m0 = ...
    T.qc_available & ...
    abs(T.error_pct) > opts.ThresholdPct;

% Indicador general.
% En el futuro puede combinarse con otros controles:
%
% T.exclude = T.flag_var_m0 | T.flag_tilt | T.flag_manual;

T.exclude = T.flag_var_m0;

%% Razón de exclusión

T.reason = repmat("pass", height(T), 1);

T.reason(~T.qc_available) = ...
    "qc_missing_or_invalid";

T.reason(T.flag_var_m0) = ...
    "spectral_variance_m0_error";

%% Identificador estable

T.burst_id = ...
    T.site + "|" + ...
    T.campaign + "|" + ...
    compose("%06d", double(T.burst_index));

T = movevars(T, 'burst_id', 'Before', 'site');

%% Ordenar según la estructura de la base de datos

T = sortrows(T, ...
    {'site','campaign','burst_index'});

%% Crear estructura final

QC = struct();

QC.schema_version = "1.0";

QC.created_utc = datetime( ...
    'now', ...
    'TimeZone', 'UTC');

QC.db_dir = string(db_dir);

QC.metric = "/qc/error";

QC.threshold_pct = opts.ThresholdPct;

QC.error_scale = opts.ErrorScale;

QC.index_definition = ...
    "Índice local sobre la dimensión burst limpia de cada campaña.";

QC.bursts = T;

%% Archivo de salida

outputFile = string(opts.OutputFile);

if strlength(outputFile) == 0
    outputFile = fullfile( ...
        db_dir, ...
        'qc', ...
        'burst_qc_registry.mat');
end

outputFile = char(outputFile);
outputDir = fileparts(outputFile);

if ~isfolder(outputDir)
    mkdir(outputDir);
end

save(outputFile, 'QC', '-v7.3');

%% CSV auxiliar para inspección

if opts.WriteCSV
    [outputDir, fileName] = fileparts(outputFile);

    csvFile = fullfile( ...
        outputDir, ...
        [fileName, '.csv']);

    writetable(QC.bursts, csvFile);
end

%% Resumen

nTotal   = height(T);
nFail    = sum(T.exclude);
nInvalid = sum(~T.qc_available);

fprintf('\nRegistro QC creado:\n');
fprintf('  Bursts evaluados:       %d\n', nTotal);
fprintf('  Bursts excluidos:       %d\n', nFail);
fprintf('  Registros QC inválidos: %d\n', nInvalid);
fprintf('  Archivo: %s\n\n', outputFile);

end


function T = local_scalar_output_to_table(D, variableName)
% Convierte out.byCampaign de db_extract_ncvar en una tabla escalar,
% asignando un índice local para cada burst.

variableName = string(variableName);
variableName = matlab.lang.makeValidName(variableName);

parts = cell(numel(D.byCampaign), 1);
nParts = 0;

for k = 1:numel(D.byCampaign)

    B = D.byCampaign(k);
    value = B.value;

    if isempty(value)
        continue
    end

    if ~isvector(value)
        error(['La variable %s no es escalar por burst en %s / %s. ' ...
               'Tamaño recibido: %s.'], ...
               variableName, ...
               B.site, ...
               B.campaign, ...
               mat2str(size(value)));
    end

    value = double(value(:));
    time = B.time(:);

    n = numel(value);

    if numel(time) ~= n
        error(['La cantidad de tiempos no coincide con la variable %s ' ...
               'en %s / %s.'], ...
               variableName, ...
               B.site, ...
               B.campaign);
    end

    % Utilizar el índice devuelto por db_extract_ncvar si posteriormente
    % se incorpora esa propiedad.
    if isfield(B, 'burst_index') && numel(B.burst_index) == n
        burstIndex = uint32(B.burst_index(:));
    else
        burstIndex = uint32((1:n).');
    end

    site = repmat(string(B.site), n, 1);
    campaign = repmat(string(B.campaign), n, 1);

    Tk = table( ...
        site, ...
        campaign, ...
        burstIndex, ...
        time, ...
        value, ...
        'VariableNames', { ...
            'site', ...
            'campaign', ...
            'burst_index', ...
            'time', ...
            char(variableName)});

    nParts = nParts + 1;
    parts{nParts} = Tk;
end

parts = parts(1:nParts);

if isempty(parts)
    T = table( ...
        strings(0,1), ...
        strings(0,1), ...
        zeros(0,1,'uint32'), ...
        NaT(0,1), ...
        zeros(0,1), ...
        'VariableNames', { ...
            'site', ...
            'campaign', ...
            'burst_index', ...
            'time', ...
            char(variableName)});
else
    T = vertcat(parts{:});
end

end