function info = db_process_spectral(db_dir, Sitio, Camp, opts)

%% Manejo de entradas
arguments
    db_dir char
    Sitio char;
    Camp char;
    opts.InputType char = 'optimum';  % 'optimum', 'ast', 'pressure'  
    opts.SpecDoF double = 64;
    opts.IGSpecDoF double = 8;
    opts.Kp_min double = 0.05;
    opts.pressure_units char = 'dba';
    opts.wsa_toolbox_dir char = ''
    opts.IG_flag = false;
    opts.IG_export_fmax (1,1) double {mustBePositive} = 0.1;
end

%% Verificaciones iniciales

if ~isfolder(db_dir)
    error('El directorio de base de datos no existe: %s', db_dir);
end

%% Path a funciones

% Toolbox WSA
if ~isempty(strtrim(opts.wsa_toolbox_dir))
    if ~isfolder(opts.wsa_toolbox_dir)
        error('El directorio indicado para wsa_toolbox_dir no existe: %s', ...
            opts.wsa_toolbox_dir);
    end
    addpath(genpath(opts.wsa_toolbox_dir))
end

%% Verificación de dependencias requeridas

% Funciones mínimas requeridas del toolbox WSA
req_wsa = {
    'wsa_spectrum'
    'wsa_spectral_parameters'
    'wsa_nc_create_var'
    'wsa_datetime2posix'
    'wsa_nc_create_var'
    };

% Verificar existencia de funciones
db_check_required_functions(req_wsa, 'WSA', 'opts.wsa_toolbox_dir');


%% Crear log file

log_dir = fullfile(db_dir, 'logs', 'processing_runs', Sitio, Camp);         %Directorio de los logs para procesamiento: logs/processing_runs/Sitio/Camp
if ~exist(log_dir, 'dir')                                                   %Crea el directorio si no existe
    mkdir(log_dir);
end
log_file = fullfile(log_dir, ['log_', Sitio, '_', Camp, '_proc_at_', ...    %Nombre del archivo log a guardar log_Sitio_Camp_proc_at_fecha.txt
            char(string(datetime('now'), 'yyyy-MM-dd_HHmmss')), '.txt']);
info.log_file = string(log_file);
diary(log_file);                                                            %Comenzar a registrar archivo log.

%Encabezado del archivo log
fprintf('\n========================================================================================================================\n');
fprintf('Inicio de procesamiento espectral: %s\n', char(string(datetime('now'), 'yyyy-MM-dd_HHmmss')));
fprintf('Sitio   : %s\n', Sitio);
fprintf('Campaña : %s\n', Camp);
fprintf('========================================================================================================================\n');

try


%% Ruta de archivo netCDF y verificaciones

processed_dir = fullfile(db_dir, 'processed', Sitio, Camp);
proc_ncfile = fullfile(processed_dir, [Sitio, '_', Camp, '.nc']);

%Verificar existencia del archivo
if ~isfile(proc_ncfile)
    error('El archivo %s no existe', proc_ncfile);
end

%Verificar que el archivo indique que se encuentra preprocesado
is_preprocessed = logical(ncreadatt(proc_ncfile, '/', 'preprocessing_status'));
if ~is_preprocessed
    error('El archivo %s no se encuentra preprocesado', proc_ncfile);
end

IG_preprocessed = logical(ncreadatt(proc_ncfile, '/', 'preprocessing_IG_filter_flag'));
if ~IG_preprocessed
    error('Se solicitó procesamiento IG, pero el archivo base no fue preprocesado en la banda IG.');
end

%% Leer datos de la campaña del archivo netCDF

%Extraer datos de la campaña
burst_data = db_read_burst_principal(proc_ncfile, 'all', 'IG', opts.IG_flag);

%% Definir tipo de datos de entrada a utilizar según InputType

nBursts = size(burst_data.processed.pressure, 2);

[Type, Type_IG, selection_info] = db_select_input_type(proc_ncfile, burst_data, opts.InputType, opts.IG_flag);

%% Ciclo principal

%Variables preliminares
z_p = burst_data.general.z_p;
h   = burst_data.general.h;
fs = burst_data.general.fs;

% Validación
pressure_idx = Type == "pressure";
if any(pressure_idx & (~isfinite(z_p) | ~isfinite(h)))
    bad_idx = find(pressure_idx & (~isfinite(z_p) | ~isfinite(h)));
    error('Geometría inválida para procesamiento por presión en los bursts: %s', mat2str(bad_idx(:).'));
end


for b = 1:nBursts

    % Extraer datos del burst
    P = burst_data.processed.pressure(:, b);
    AST1 = burst_data.processed.ast(:, 1, b);

    if opts.IG_flag
        P_ig = burst_data.processed.pressure_ig(:, b);
        AST1_ig = burst_data.processed.ast_ig(:, 1, b); 
    end

    switch Type(b)
        
        case "ast"
            %%% ------------------------ Basado en AST ------------------------ %%%%
            % Espectro frecuencial AST
            fprintf('\nCalculando espectro frecuencial basado en AST para burst %d\n', b);
            [out_spectrum, info_spectrum] = wsa_spectrum( ...
                                                        AST1, ...
                                                        fs, ...
                                                        'DoF', opts.SpecDoF, ...
                                                        'printFlag', 0);

            if opts.IG_flag
                fprintf('\nCalculando espectro frecuencial IG basado en AST para burst %d\n', b);
                [out_IG_spectrum, info_IG_spectrum] = wsa_spectrum( ...
                                                            AST1_ig, ...
                                                            fs, ...
                                                            'DoF', opts.IGSpecDoF, ...
                                                            'printFlag', 0);
            end
        
        case "pressure"
            %%% ---------------------  Basado en Presión  --------------------- %%%%
            % Espectro frecuencial Presión
            fprintf('\nCalculando espectro frecuencial basado en Presión para burst %d\n', b);
            [out_spectrum, info_spectrum] = wsa_spectrum( ...
                                                        P, ...
                                                        fs, ...
                                                        'InputType', "pressure", ...
                                                        'un', opts.pressure_units, ...
                                                        'z_p', z_p(b), ...
                                                        'h', h(b), ...
                                                        'DoF', opts.SpecDoF, ...
                                                        'Kp_min', opts.Kp_min, ...
                                                        'printFlag', 0);
            if opts.IG_flag
                fprintf('\nCalculando espectro frecuencial IG basado en Presión para burst %d\n', b);
                [out_IG_spectrum, info_IG_spectrum] = wsa_spectrum( ...
                                                            P_ig, ...
                                                            fs, ...
                                                            'InputType', "pressure", ...
                                                            'un', opts.pressure_units, ...
                                                            'z_p', z_p(b), ...
                                                            'h', h(b), ...
                                                            'DoF', opts.IGSpecDoF, ...
                                                            'Kp_min', opts.Kp_min, ...
                                                            'printFlag', 0);
            end
        
        otherwise
            error('Tipo de entrada no reconocido para burst %d: %s', b, Type(b));
    end
        
    % Parámetros espectrales
    spec_parameters = wsa_spectral_parameters(out_spectrum);
    if opts.IG_flag
        IG_spec_parameters = wsa_spectral_parameters(out_IG_spectrum, 'IncludeDefaultBands', false); %Exportar solo total, correspondiente a IG para señal ya filtrada
    end

    % Guardado directo de resultados
    burst_results(b).out_spectrum = out_spectrum;
    burst_results(b).info_spectrum = info_spectrum;
    burst_results(b).params.spectral = spec_parameters;

    if opts.IG_flag
        burst_results(b).out_IG_spectrum = out_IG_spectrum;
        burst_results(b).info_IG_spectrum = info_IG_spectrum;
        burst_results(b).IG_params.spectral = IG_spec_parameters;
    end
end

%% Reorganizacion de datos para formato netCDF

nc_data = struct();

% Tiempo
nc_data.time = burst_data.general.time(1:nBursts);
nc_data.Type = Type;

% Frecuencia común
nc_data.f = burst_results(1).out_spectrum.f;

% Espectro S(f, burst)
nFreq = numel(nc_data.f);
nc_data.S = NaN(nFreq, nBursts);

% Información de corrección por presión (en caso de existir)
nc_data.Spp = NaN(nFreq, nBursts);
nc_data.Kp  = NaN(nFreq, nBursts);
nc_data.k   = NaN(nFreq, nBursts);

for b = 1:nBursts
    nc_data.S(:, b) = burst_results(b).out_spectrum.S;

    % En caso de existir corrección por presión
    if isfield(burst_results(b).out_spectrum, 'Spp')
        nc_data.Spp(:, b) = burst_results(b).out_spectrum.Spp;
        nc_data.Kp(:, b)  = burst_results(b).out_spectrum.Kp;
        nc_data.k(:, b)   = burst_results(b).out_spectrum.k;
    end
end

if opts.IG_flag

    % Vector completo de frecuencias calculado por wsa_spectrum
    f_ig_full = burst_results(1).out_IG_spectrum.f(:);

    % Conservar únicamente el intervalo [0, IG_export_fmax]
    ig_keep = isfinite(f_ig_full) & f_ig_full >= 0 & f_ig_full <= opts.IG_export_fmax;

    if ~any(ig_keep)
        error('El espectro IG no contiene frecuencias dentro del intervalo [0, %.6g] Hz.', opts.IG_export_fmax);
    end

    % Vector de frecuencias que se exportará
    nc_data.IG.f = f_ig_full(ig_keep);

    % Cantidad de frecuencias IG exportadas
    nFreq_IG = nnz(ig_keep);

    % Preasignación
    nc_data.IG.S   = NaN(nFreq_IG, nBursts);
    nc_data.IG.Spp = NaN(nFreq_IG, nBursts);
    nc_data.IG.Kp  = NaN(nFreq_IG, nBursts);
    nc_data.IG.k   = NaN(nFreq_IG, nBursts);

    % Tolerancia para verificar que todos los bursts tengan exactamente la misma discretización frecuencial
    frequency_tolerance = 10*eps(max(1, max(abs(f_ig_full))));

    for b = 1:nBursts

        out_ig = burst_results(b).out_IG_spectrum;
        f_ig_burst = out_ig.f(:);

        % Verificar que la malla frecuencial sea común
        if numel(f_ig_burst) ~= numel(f_ig_full) || any(abs(f_ig_burst - f_ig_full) > frequency_tolerance)

            error('El vector de frecuencias IG del burst %d no coincide con el vector de frecuencias del primer burst.', b);
        end

        % Espectro IG
        S_ig = out_ig.S(:);
        nc_data.IG.S(:, b) = S_ig(ig_keep);

        % Variables asociadas a la corrección por presión
        if isfield(out_ig, 'Spp')

            Spp_ig = out_ig.Spp(:);
            Kp_ig  = out_ig.Kp(:);
            k_ig   = out_ig.k(:);

            nc_data.IG.Spp(:, b) = Spp_ig(ig_keep);
            nc_data.IG.Kp(:, b)  = Kp_ig(ig_keep);
            nc_data.IG.k(:, b)   = k_ig(ig_keep);
        end
    end

    fprintf('\nEspectros IG recortados para exportación: 0 <= f <= %.6f Hz.\n', opts.IG_export_fmax);

    fprintf('Frecuencias originales : %d\n', numel(f_ig_full));
    fprintf('Frecuencias exportadas : %d\n', nFreq_IG);
end


%Agregar banda IG si fue solicitada
if opts.IG_flag
    % ----------          Parametros espectrales          -----------
    nc_data.spectral.ig.m0           = arrayfun(@(x) x.IG_params.spectral.bands.total.m0, burst_results).';
    nc_data.spectral.ig.m1           = arrayfun(@(x) x.IG_params.spectral.bands.total.m1, burst_results).';
    nc_data.spectral.ig.m2           = arrayfun(@(x) x.IG_params.spectral.bands.total.m2, burst_results).';
    nc_data.spectral.ig.m4           = arrayfun(@(x) x.IG_params.spectral.bands.total.m4, burst_results).';
    nc_data.spectral.ig.eta_rms      = arrayfun(@(x) x.IG_params.spectral.bands.total.eta_rms, burst_results).';
    nc_data.spectral.ig.Hrms         = arrayfun(@(x) x.IG_params.spectral.bands.total.Hrms, burst_results).';
    nc_data.spectral.ig.Hm0          = arrayfun(@(x) x.IG_params.spectral.bands.total.Hm0, burst_results).';
    nc_data.spectral.ig.Tm01         = arrayfun(@(x) x.IG_params.spectral.bands.total.Tm01,  burst_results).';
    nc_data.spectral.ig.Tm02         = arrayfun(@(x) x.IG_params.spectral.bands.total.Tm02,  burst_results).';
    nc_data.spectral.ig.Tp           = arrayfun(@(x) x.IG_params.spectral.bands.total.Tp,  burst_results).';
    nc_data.spectral.ig.fp           = arrayfun(@(x) x.IG_params.spectral.bands.total.fp,  burst_results).';
    nc_data.spectral.ig.v            = arrayfun(@(x) x.IG_params.spectral.bands.total.v,  burst_results).';
    nc_data.spectral.ig.Qp           = arrayfun(@(x) x.IG_params.spectral.bands.total.Qp,  burst_results).';
    nc_data.spectral.ig.band_limits = burst_results(1).IG_params.spectral.bands.total.band_limits;
end

%Agregar bandas por defecto
bands   = {'swell1', 'swell2', 'swell', 'wind', 'total'};

for j = 1:length(bands)
    % ----------          Parametros espectrales          -----------
    nc_data.spectral.(bands{j}).m0           = arrayfun(@(x) x.params.spectral.bands.(bands{j}).m0, burst_results).';
    nc_data.spectral.(bands{j}).m1           = arrayfun(@(x) x.params.spectral.bands.(bands{j}).m1, burst_results).';
    nc_data.spectral.(bands{j}).m2           = arrayfun(@(x) x.params.spectral.bands.(bands{j}).m2, burst_results).';
    nc_data.spectral.(bands{j}).m4           = arrayfun(@(x) x.params.spectral.bands.(bands{j}).m4, burst_results).';
    nc_data.spectral.(bands{j}).eta_rms      = arrayfun(@(x) x.params.spectral.bands.(bands{j}).eta_rms, burst_results).';
    nc_data.spectral.(bands{j}).Hrms         = arrayfun(@(x) x.params.spectral.bands.(bands{j}).Hrms, burst_results).';
    nc_data.spectral.(bands{j}).Hm0          = arrayfun(@(x) x.params.spectral.bands.(bands{j}).Hm0, burst_results).';
    nc_data.spectral.(bands{j}).Tm01         = arrayfun(@(x) x.params.spectral.bands.(bands{j}).Tm01,  burst_results).';
    nc_data.spectral.(bands{j}).Tm02         = arrayfun(@(x) x.params.spectral.bands.(bands{j}).Tm02,  burst_results).';
    nc_data.spectral.(bands{j}).Tp           = arrayfun(@(x) x.params.spectral.bands.(bands{j}).Tp,  burst_results).';
    nc_data.spectral.(bands{j}).fp           = arrayfun(@(x) x.params.spectral.bands.(bands{j}).fp,  burst_results).';
    nc_data.spectral.(bands{j}).v            = arrayfun(@(x) x.params.spectral.bands.(bands{j}).v,  burst_results).';
    nc_data.spectral.(bands{j}).Qp           = arrayfun(@(x) x.params.spectral.bands.(bands{j}).Qp,  burst_results).';
    nc_data.spectral.(bands{j}).band_limits = burst_results(1).params.spectral.bands.(bands{j}).band_limits;
end

%Extraer variables adicionales
effectiveDoF    = arrayfun(@(x) x.info_spectrum.DoF, burst_results);
effectiveK      = arrayfun(@(x) x.info_spectrum.K, burst_results);
effectiveN      = arrayfun(@(x) x.info_spectrum.N, burst_results);
effectiveN0     = arrayfun(@(x) x.info_spectrum.N0, burst_results);
effectiveNfft   = arrayfun(@(x) x.info_spectrum.Nfft, burst_results);
resolution_Hz   = arrayfun(@(x) x.info_spectrum.resolution_Hz, burst_results);
resolution_s    = arrayfun(@(x) x.info_spectrum.resolution_s, burst_results);
fs              = arrayfun(@(x) x.info_spectrum.fs, burst_results);
m0              = arrayfun(@(x) x.info_spectrum.m0, burst_results);
var             = arrayfun(@(x) x.info_spectrum.varianza, burst_results);
err             = arrayfun(@(x) x.info_spectrum.error_relativo, burst_results);

if opts.IG_flag
    effectiveDoF_IG    = arrayfun(@(x) x.info_IG_spectrum.DoF, burst_results);
    effectiveK_IG      = arrayfun(@(x) x.info_IG_spectrum.K, burst_results);
    effectiveN_IG      = arrayfun(@(x) x.info_IG_spectrum.N, burst_results);
    effectiveN0_IG     = arrayfun(@(x) x.info_IG_spectrum.N0, burst_results);
    effectiveNfft_IG   = arrayfun(@(x) x.info_IG_spectrum.Nfft, burst_results);
    resolution_Hz_IG   = arrayfun(@(x) x.info_IG_spectrum.resolution_Hz, burst_results);
    resolution_s_IG    = arrayfun(@(x) x.info_IG_spectrum.resolution_s, burst_results);
    fs_IG              = arrayfun(@(x) x.info_IG_spectrum.fs, burst_results);
    m0_IG              = arrayfun(@(x) x.info_IG_spectrum.m0, burst_results);
    var_IG             = arrayfun(@(x) x.info_IG_spectrum.varianza, burst_results);
    err_IG             = arrayfun(@(x) x.info_IG_spectrum.error_relativo, burst_results);
end


%% Crear archivo NetCDF temporal

spectral_ncfile = fullfile(processed_dir, [Sitio, '_', Camp, '_spectral.nc']);

%Archivo temporal
spectral_tmpfile = [spectral_ncfile, '.tmp'];
if isfile(spectral_tmpfile)

    delete(spectral_tmpfile);
    pause(0.1);

    if isfile(spectral_tmpfile)
        error(['No fue posible eliminar el archivo temporal residual:\n%s\n', ...
             'Puede estar abierto o bloqueado.'], ...
            spectral_tmpfile);
    end
end
% Eliminar temp automáticamente si ocurre un error
tmpCleanup = onCleanup(@() safe_delete_tmp(spectral_tmpfile));

%% Crear variables base del archivo NetCDF

nBurst = numel(nc_data.time);
nFreq = numel(nc_data.f);
if opts.IG_flag
    nFreq_IG = numel(nc_data.IG.f);
end

wsa_nc_create_var(spectral_tmpfile, ...
    'time', ...
    {'burst', nBurst}, ...
    'double', ...
    'units', 'seconds since 1970-01-01 00:00:00 UTC', ...
    'long_name', 'tiempo inicial');

wsa_nc_create_var(spectral_tmpfile, ...
    'Type', ...
    {'burst', nBurst}, ...
    'string', ...
    'long_name', 'input signal type', ...
    'description', 'señal utilizada: ast o pressure');

wsa_nc_create_var(spectral_tmpfile, ...
    'f', ...
    {'frequency', nFreq}, ...
    'double', ...
    'units', 'Hz', ...
    'long_name', 'frecuencia');

wsa_nc_create_var(spectral_tmpfile, ...
    'S', ...
    {'frequency', nFreq, 'burst', nBurst}, ...
    'double', ...
    'units', 'm2/Hz', ...
    'long_name', 'espectro frecuencial');

if opts.IG_flag
    wsa_nc_create_var(spectral_tmpfile, ...
        'f_ig', ...
        {'frequency_ig', nFreq_IG}, ...
        'double', ...
        'units', 'Hz', ...
        'long_name', 'frecuencia IG');

    wsa_nc_create_var(spectral_tmpfile, ...
        'S_ig', ...
        {'frequency_ig', nFreq_IG, 'burst', nBurst}, ...
        'double', ...
        'units', 'm2/Hz', ...
        'long_name', 'espectro frecuencial IG');
end

safe_ncwrite(spectral_tmpfile, 'time', wsa_datetime2posix(nc_data.time));
safe_ncwrite(spectral_tmpfile, 'Type', nc_data.Type);
safe_ncwrite(spectral_tmpfile, 'f', nc_data.f);
safe_ncwrite(spectral_tmpfile, 'S', nc_data.S);
if opts.IG_flag
    safe_ncwrite(spectral_tmpfile, 'f_ig', nc_data.IG.f);
    safe_ncwrite(spectral_tmpfile, 'S_ig', nc_data.IG.S);
end

%% Parámetros espectrales

bands = fieldnames(nc_data.spectral);

params = {'m0','m1','m2','m4','eta_rms','Hrms','Hm0','Tm01','Tm02','Tp','fp','v','Qp'};
units = {'m2','m2 Hz','m2 Hz2','m2 Hz4','m','m','m','s','s','s','Hz','1','1'};
long_names = {'momento de orden cero', ...
              'momento de primer orden', ...
              'momento de segundo orden', ...
              'momento de cuarto orden', ...
              'valor cuadrático medio de la elevación de superficie libre', ...
              'Altura de ola cuadrática media', ...
              'Altura significativa espectral', ...
              'Período medio espectral asociado al centro energético', ...
              'Período medio espectral asociado al período de cruce por cero', ...
              'Período pico', ...
              'Frecuencia pico', ...
              'Parámetro de anchura espectral', ...
              'Parámetro de agudeza del pico'};

for j = 1:numel(bands)

    band = bands{j};

    for k = 1:numel(params)

        param = params{k};
        unit = units{k};
        long_name = long_names{k};
        varname = ['bands/' band '/' param];

        wsa_nc_create_var(spectral_tmpfile, varname, ...
            {'burst', nBurst}, 'double', ...
            'units', unit, ...
            'long_name', long_name ...
            );

        safe_ncwrite(spectral_tmpfile, varname, nc_data.spectral.(band).(param));

    end

    % band limits
    wsa_nc_create_var(spectral_tmpfile, ...
        ['bands/' band '/band_limits'], ...
        {'limit', 2}, ...
        'double', ...
        'units', 'Hz', ...
        'long_name', 'Limites superior e inferior de bandas de frecuencia');

    safe_ncwrite(spectral_tmpfile, ['bands/' band '/band_limits'], nc_data.spectral.(band).band_limits(:));
end

%% Variables de control de calidad

write_qc_variable(spectral_tmpfile, ...
    'qc/m0', ...
    m0, ...
    {'burst', nBurst}, ...
    'double', ...
    'm2', ...
    'momento de orden cero');

write_qc_variable(spectral_tmpfile, ...
    'qc/var', ...
    var, ...
    {'burst', nBurst}, ...
    'double', ...
    'm2', ...
    'varianza temporal de la señal');

write_qc_variable(spectral_tmpfile, ...
    'qc/error', ...
    err, ...
    {'burst', nBurst}, ...
    'double', ...
    'percent', ...
    'error relativo entre la varianza temporal de la señal y el momento de orden cero');

if opts.IG_flag
    write_qc_variable(spectral_tmpfile, ...
        'qc_IG/m0', ...
        m0_IG, ...
        {'burst', nBurst}, ...
        'double', ...
        'm2', ...
        'momento de orden cero');
    
    write_qc_variable(spectral_tmpfile, ...
        'qc_IG/var', ...
        var_IG, ...
        {'burst', nBurst}, ...
        'double', ...
        'm2', ...
        'varianza temporal de la señal');
    
    write_qc_variable(spectral_tmpfile, ...
        'qc_IG/error', ...
        err_IG, ...
        {'burst', nBurst}, ...
        'double', ...
        'percent', ...
        'error relativo entre la varianza temporal de la señal y el momento de orden cero');
end


%% Atributos globales
safe_ncwriteatt(spectral_tmpfile, '/', 'description', 'Resultados de procesamiento espectral no direccional');
safe_ncwriteatt(spectral_tmpfile, '/', 'source_file', proc_ncfile);
safe_ncwriteatt(spectral_tmpfile, '/', 'processing_time_UTC-6', char(datetime('now', 'TimeZone', 'America/Costa_Rica', 'Format', 'yyyy-MM-dd''T''HH:mm:ssZZ')));
safe_ncwriteatt(spectral_tmpfile, '/', 'Sitio', Sitio);
safe_ncwriteatt(spectral_tmpfile, '/', 'Camp', Camp);
safe_ncwriteatt(spectral_tmpfile, '/', 'instrument_type', char(selection_info.instrument_type));
safe_ncwriteatt(spectral_tmpfile, '/', 'InputType', opts.InputType);
safe_ncwriteatt(spectral_tmpfile, '/', 'SpecDoF_requested', opts.SpecDoF);
if opts.IG_flag
    safe_ncwriteatt(spectral_tmpfile, '/', 'IGSpecDoF_requested', opts.IGSpecDoF);
    safe_ncwriteatt(spectral_tmpfile, '/', 'IG_export_frequency_min_Hz', 0);
    safe_ncwriteatt(spectral_tmpfile, '/', 'IG_export_frequency_max_Hz', opts.IG_export_fmax);
end
safe_ncwriteatt(spectral_tmpfile, '/', 'Kp_min', opts.Kp_min);
safe_ncwriteatt(spectral_tmpfile, '/', 'pressure_units', opts.pressure_units);

%% Crear variables adicionales que brindan información del método de Welch-Bartlett

% Decidir si escribir como atributo global o variable, dependiendo de si es constante o no.
write_att_or_var(spectral_tmpfile, effectiveDoF, 'SpecDoF_effective', 'processing/DoF_effective', {'burst', nBurst}, 'double', 'grados de libertad espectrales efectivos')
write_att_or_var(spectral_tmpfile, effectiveK, 'K_effective', 'processing/K_effective', {'burst', nBurst}, 'double', 'número de segmentos efectivos')
write_att_or_var(spectral_tmpfile, effectiveN, 'N_effective', 'processing/N_effective', {'burst', nBurst}, 'double', 'longitud efectiva de segmentos')
write_att_or_var(spectral_tmpfile, effectiveN0, 'N0_effective', 'processing/N0_effective', {'burst', nBurst}, 'double', 'traslape efectivo de segmentos')
write_att_or_var(spectral_tmpfile, effectiveNfft, 'Nfft_effective', 'processing/Nfft_effective', {'burst', nBurst}, 'double', 'bins Nfft efectivos')
write_att_or_var(spectral_tmpfile, resolution_Hz, 'resolution_Hz', 'processing/resolution_Hz', {'burst', nBurst}, 'double', 'resolución espectral en Hz')
write_att_or_var(spectral_tmpfile, resolution_s, 'resolution_s', 'processing/resolution_s', {'burst', nBurst}, 'double', 'resolución espectral en segundos')
write_att_or_var(spectral_tmpfile, fs, 'fs', 'processing/fs', {'burst', nBurst}, 'double', 'frecuencia de muestreo')

if opts.IG_flag
    write_att_or_var(spectral_tmpfile, effectiveDoF_IG, 'SpecDoF_effective_IG', 'processing/DoF_effective', {'burst', nBurst}, 'double', 'grados de libertad espectrales efectivos')
    write_att_or_var(spectral_tmpfile, effectiveK_IG, 'K_effective_IG', 'processing/K_effective', {'burst', nBurst}, 'double', 'número de segmentos efectivos')
    write_att_or_var(spectral_tmpfile, effectiveN_IG, 'N_effective_IG', 'processing/N_effective', {'burst', nBurst}, 'double', 'longitud efectiva de segmentos')
    write_att_or_var(spectral_tmpfile, effectiveN0_IG, 'N0_effective_IG', 'processing/N0_effective', {'burst', nBurst}, 'double', 'traslape efectivo de segmentos')
    write_att_or_var(spectral_tmpfile, effectiveNfft_IG, 'Nfft_effective_IG', 'processing/Nfft_effective', {'burst', nBurst}, 'double', 'bins Nfft efectivos')
    write_att_or_var(spectral_tmpfile, resolution_Hz_IG, 'resolution_IG_Hz', 'processing/resolution_Hz', {'burst', nBurst}, 'double', 'resolución espectral en Hz')
    write_att_or_var(spectral_tmpfile, resolution_s_IG, 'resolution_IG_s', 'processing/resolution_s', {'burst', nBurst}, 'double', 'resolución espectral en segundos')
end
%% Sustituir archivo definitivo
[status, msg, ~] = movefile(spectral_tmpfile, spectral_ncfile, 'f');

if ~status
    error(['El archivo temporal se creó correctamente, pero no fue ', ...
         'posible sustituir el archivo espectral definitivo:\n%s\n\n%s'], ...
        spectral_ncfile, msg);
end
clear tmpCleanup


%% Generar archivo de texto con contenido del NetCDF en la carpeta

if isfile(spectral_ncfile)
    info.ncdisp_file = db_write_ncdisp_txt(spectral_ncfile);
    fprintf('\n\nFormato de archivo netCDF resultante:\n')
    ncdisp(spectral_ncfile);
else
    info.ncdisp_file = "";
    fprintf('\nNo se generó archivo ncdisp porque no existe el archivo .nc:\n%s\n', spectral_ncfile);
end

info.spectral_ncfile = string(spectral_ncfile);

%% Mensaje final 

fprintf('\n\n========================================================================================================================\n');
fprintf('Procesamiento espectral finalizado correctamente: %s\n', char(string(datetime('now'), 'yyyy-MM-dd_HHmmss')));
fprintf('========================================================================================================================\n');


catch ME
    %Bloque que se corre en caso de errores y también genera un archivo de error
    
    % Mensaje a colocar en el archivo log.
    fprintf('\n\n========================================================================================================================\n');
    fprintf('ERROR durante el procesamiento espectral: %s\n', char(string(datetime('now'), 'yyyy-MM-dd_HHmmss')));
    fprintf('Mensaje: %s\n', ME.message);
    fprintf('Identificador: %s\n', ME.identifier);

    fprintf('\nReporte completo del error:\n');
    fprintf('%s\n', getReport(ME, ...
        'extended', ...
        'hyperlinks', 'off'));

    for k = 1:numel(ME.stack)
        fprintf('En %s (línea %d)\n', ME.stack(k).name, ME.stack(k).line);
    end
    fprintf('========================================================================================================================\n');

    diary off                                                               % En caso de error, se termina de escribir el log aquí.
    
    % Archivo de error.
    err_dir = fullfile(db_dir, 'logs', 'errors', Sitio, Camp);              % Directorio para archivos de errores: logs/errors/Sitio/Camp
    if ~exist(err_dir, 'dir')                                               % Crear directorio en caso de no existir
        mkdir(err_dir);
    end
    err_file = fullfile(err_dir, ...                                        % Nombre del archivo de error: error_Sitio_Camp_fecha.txt
        ['error_', Sitio, '_', Camp, '_', char(string(datetime('now'), 'yyyy-MM-dd_HHmmss')), '.txt']);
    fid = fopen(err_file, 'w');                                             % Comenzar escritura de archivo de error
    if fid ~= -1
        fprintf(fid, 'Fecha: %s\n', char(string(datetime('now'), 'yyyy-MM-dd_HHmmss')));
        fprintf(fid, 'Mensaje: %s\n', ME.message);
        fprintf(fid, 'Identificador: %s\n', ME.identifier);
        fprintf(fid, '\nReporte completo:\n');
        fprintf(fid, '%s\n', getReport(ME, ...
            'extended', ...
            'hyperlinks', 'off'));
        for k = 1:numel(ME.stack)
            fprintf(fid, 'En %s (línea %d)\n', ME.stack(k).name, ME.stack(k).line);
        end
        fclose(fid);                                                        % Finalizar escritura de arhivo de error
    else
        warning('No se pudo crear el archivo de error: %s', err_file);      % Error en caso de que falle fopen() al crear el archivo.
    end

    rethrow(ME)                                                             % Retoma el error al finalizar catch.
end

diary off                                                                   %Se termina de escribir el log si el try no presentó error.

end







