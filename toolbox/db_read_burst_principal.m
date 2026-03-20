function burst_data_principal = db_read_burst_principal(ncfile, nburst)

if ~isfile(ncfile)
    error('El archivo no existe: %s', ncfile);
end

info_var = ncinfo(ncfile);
dim_names = string({info_var.Dimensions.Name});
dim_lens  = [info_var.Dimensions.Length];

burst_dim_idx = find(dim_names == "burst", 1);
nBurstsTotal = dim_lens(burst_dim_idx);

% --- Detectar modo ALL ---
leer_todos = (nargin < 2) || isempty(nburst) || ...
             (ischar(nburst) && strcmpi(nburst,'all')) || ...
             (isstring(nburst) && lower(nburst) == "all");

% --- Validación si NO es ALL ---
if ~leer_todos
    if nburst > nBurstsTotal
        error('nburst=%d excede el número de bursts (%d).', ...
            nburst, nBurstsTotal);
    end
end

burst_data_principal = struct;

if leer_todos
    % ===== LEER TODO =====
    burst_data_principal.t              = db_posix2datetime(ncread(ncfile, 'time'));
    burst_data_principal.burst_counter  = ncread(ncfile, 'burst_counter');
    burst_data_principal.P              = ncread(ncfile, 'pressure');
    burst_data_principal.AST            = ncread(ncfile, 'ast_distance');
    burst_data_principal.V              = ncread(ncfile, 'velocity');

else
    % ===== UN SOLO BURST =====
    burst_data_principal.t              = db_posix2datetime(ncread(ncfile, 'time', nburst, 1));
    burst_data_principal.burst_counter  = ncread(ncfile, 'burst_counter', nburst, 1);
    burst_data_principal.P              = ncread(ncfile, 'pressure', [1, nburst], [Inf, 1]);
    burst_data_principal.AST            = ncread(ncfile, 'ast_distance', [1, 1, nburst], [Inf, Inf, 1]);
    burst_data_principal.V              = ncread(ncfile, 'velocity', [1, 1, nburst], [Inf, Inf, 1]);
end

end