function burst_data_var = db_read_burst_var(ncfile, nburst, var)
%db_read_burst_var Lee una variable específica para un burst indicado.

arguments
    ncfile (1,1) string
    nburst
    var {mustBeTextScalar}
end

var = string(var);

% Alias opcionales
switch lower(char(var))
    case {'ast', 's'}
        var = "ast_distance";
    case {'pressure', 'presión', 'presion', 'press', 'p'}
        var = "pressure";
    case {'velocity','vel', 'velocidad', 'v'}
        var = "velocity";
end

if ~isfile(ncfile)
    error('El archivo no existe: %s', ncfile);
end

% Verificar que la variable exista y obtener info
info_var = ncinfo(ncfile, char(var));

dim_names = string({info_var.Dimensions.Name});
dim_lens  = [info_var.Dimensions.Length];

burst_dim_idx = find(dim_names == "burst", 1);
if isempty(burst_dim_idx)
    error('La variable "%s" no depende de la dimensión "burst".', var);
end

nBurstsTotal = dim_lens(burst_dim_idx);

% Detectar modo ALL
leer_todos = isempty(nburst) || ...
             (ischar(nburst)   && strcmpi(nburst,'all')) || ...
             (isstring(nburst) && isscalar(nburst) && lower(nburst) == "all");

if leer_todos
    % Leer toda la variable
    data = ncread(ncfile, char(var));
else
    % Validar nburst numérico
    if ~(isnumeric(nburst) && isscalar(nburst) && ...
         isfinite(nburst) && nburst == floor(nburst) && nburst > 0)
        error('nburst debe ser un entero positivo o ''all''.');
    end

    if nburst > nBurstsTotal
        error('nburst=%d excede el número de bursts (%d).', ...
            nburst, nBurstsTotal);
    end

    start = ones(1, numel(dim_lens));
    count = dim_lens;

    start(burst_dim_idx) = nburst;
    count(burst_dim_idx) = 1;

    data = ncread(ncfile, char(var), start, count);
end

if var == "time"
    data = db_posix2datetime(data);
end

burst_data_var = squeeze(data);

end