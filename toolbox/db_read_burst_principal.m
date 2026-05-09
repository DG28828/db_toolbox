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

    %Generales del burst
    burst_data_principal.general.time             = db_posix2datetime(ncread(ncfile, 'time'));
    burst_data_principal.general.burst_counter    = ncread(ncfile, 'burst_counter');
    burst_data_principal.general.ast_mean         = ncread(ncfile, 'ast_mean');
    burst_data_principal.general.cell_position    = ncread(ncfile, 'cell_position');
    burst_data_principal.general.mounting_height  = ncreadatt(ncfile, '/', 'mounting_height_m');
    burst_data.general.fs               = ncreadatt(ncfile, '/', 'wave_sampling_rate_Hz');
    
    %Tiempo
    burst_data_principal.time.burst_time          = db_posix2datetime(ncread(ncfile, 'burst_time'));

    %Datos procesados (despiking en AST y filtrado)
    burst_data_principal.processed.pressure       = ncread(ncfile, 'pressure_proc');
    burst_data_principal.processed.ast            = ncread(ncfile, 'ast_proc');
    burst_data_principal.processed.ast_comb       = ncread(ncfile, 'ast_proc_comb');
    burst_data_principal.processed.velocity_enu   = ncread(ncfile, 'velocity_proc');
    burst_data_principal.processed.ast_quality    = ncread(ncfile, 'ast_quality');
    burst_data_principal.processed.ast_bad_detects = ncread(ncfile, 'ast_bad_detects');
    burst_data_principal.processed.ast_bad_detects_percentage = ncread(ncfile, 'ast_bad_detects_percentage');

else
    % ===== UN SOLO BURST =====

    %Generales del burst
    burst_data_principal.general.time             = db_posix2datetime(ncread(ncfile, 'time', nburst, 1));
    burst_data_principal.general.burst_counter    = ncread(ncfile, 'burst_counter', nburst, 1);
    burst_data_principal.general.ast_mean         = ncread(ncfile, 'ast_mean', nburst, 1);
    burst_data_principal.general.cell_position    = ncread(ncfile, 'cell_position', nburst, 1);
    burst_data_principal.general.mounting_height  = ncread(ncfile, 'mounting_height_m');
    burst_data.general.fs               = ncreadatt(ncfile, '/', 'wave_sampling_rate_Hz');
    
    %Tiempo
    burst_data_principal.time.burst_time          = db_posix2datetime(ncread(ncfile, 'burst_time', [1, nburst], [Inf, 1]));

    %Datos procesados (despiking en AST y filtrado)
    burst_data_principal.processed.pressure       = ncread(ncfile, 'pressure_proc', [1, nburst], [Inf, 1]);
    burst_data_principal.processed.ast            = ncread(ncfile, 'ast_proc', [1, 1, nburst], [Inf, Inf, 1]);
    burst_data_principal.processed.ast_comb       = ncread(ncfile, 'ast_proc_comb', [1, 1, nburst], [Inf, Inf, 1]);
    burst_data_principal.processed.velocity_enu   = ncread(ncfile, 'velocity_proc', [1, 1, nburst], [Inf, Inf, 1]);
    burst_data_principal.processed.ast_quality    = ncread(ncfile, 'ast_quality', [1, nburst], [Inf, 1]);
    burst_data_principal.processed.ast_bad_detects = ncread(ncfile, 'ast_bad_detects', [1, nburst], [Inf, 1]);
    burst_data_principal.processed.ast_bad_detects_percentage = ncread(ncfile, 'ast_bad_detects_percentage', [1, nburst], [Inf, 1]);
end

end