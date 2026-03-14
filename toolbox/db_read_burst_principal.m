function burst_data_principal = db_read_burst_principal(ncfile, nburst)

if ~isfile(ncfile)
    error('El archivo no existe: %s', ncfile);
end

info_var = ncinfo(ncfile);
dim_names = string({info_var.Dimensions.Name});
dim_lens  = [info_var.Dimensions.Length];

burst_dim_idx = find(dim_names == "burst", 1);
if nburst > dim_lens(burst_dim_idx)
    error('nburst=%d excede el número de bursts (%d).', ...
        nburst, dim_lens(burst_dim_idx));
end

burst_data_principal = struct;

burst_data_principal.t              = db_posix2datetime(ncread(ncfile, 'time', nburst, 1));
burst_data_principal.burst_counter  = ncread(ncfile, 'burst_counter', nburst, 1);
burst_data_principal.P              = ncread(ncfile, 'pressure_dbar', [1, nburst], [Inf, 1]);
burst_data_principal.AST            = ncread(ncfile, 'ast_distance_m', [1, 1, nburst], [Inf, Inf, 1]);
burst_data_principal.V              = ncread(ncfile, 'velocity_ms', [1, 1, nburst], [Inf, Inf, 1]);

end