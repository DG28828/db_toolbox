function burst_data = db_read_burst(ncfile, nburst)

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

burst_data = struct;

burst_data.time             = db_posix2datetime(ncread(ncfile, 'time', nburst, 1));
burst_data.burst_counter    = ncread(ncfile, 'burst_counter', nburst, 1);
burst_data.pressure_dbar    = ncread(ncfile, 'pressure_dbar', [1, nburst], [Inf, 1]);
burst_data.ast_distance_m   = ncread(ncfile, 'ast_distance_m', [1, 1, nburst], [Inf, Inf, 1]);
burst_data.ast_quality      = ncread(ncfile, 'ast_quality', [1, nburst], [Inf, 1]);
burst_data.analog_input     = ncread(ncfile, 'analog_input', [1, nburst], [Inf, 1]);
burst_data.velocity_ms      = ncread(ncfile, 'velocity_ms', [1, 1, nburst], [Inf, Inf, 1]);
burst_data.amplitude        = ncread(ncfile, 'amplitude', [1, 1, nburst], [Inf, Inf, 1]);

end