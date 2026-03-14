function burst_data_var = db_read_burst_var(ncfile, nburst, var)
%db_read_burst_var Lee una variable específica para un burst indicado.

arguments
    ncfile (1,1) string
    nburst (1,1) double {mustBeInteger, mustBePositive}
    var {mustBeTextScalar}
end

var = string(var);

% Alias opcionales
switch lower(char(var))
    case 'ast'
        var = "ast_distance_m";
    case 'pressure'
        var = "pressure_dbar";
    case {'velocity','vel'}
        var = "velocity_ms";
end

if ~isfile(ncfile)
    error('El archivo no existe: %s', ncfile);
end

info_var = ncinfo(ncfile, char(var));

dim_names = string({info_var.Dimensions.Name});
dim_lens  = [info_var.Dimensions.Length];

burst_dim_idx = find(dim_names == "burst", 1);
if isempty(burst_dim_idx)
    error('La variable "%s" no depende de la dimensión "burst".', var);
end

if nburst > dim_lens(burst_dim_idx)
    error('nburst=%d excede el número de bursts (%d).', ...
        nburst, dim_lens(burst_dim_idx));
end

start = ones(1, numel(dim_lens));
count = dim_lens;

start(burst_dim_idx) = nburst;
count(burst_dim_idx) = 1;

data = ncread(ncfile, char(var), start, count);

if var == "time"
    data = db_posix2datetime(data);
end

burst_data_var = squeeze(data);


end