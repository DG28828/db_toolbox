function info = db_process_spectral(db_dir, Sitio, Camp, opts)

%% Manejo de entradas
arguments
    db_dir char
    Sitio char;
    Camp char;
    opts.InputType char = 'optimum';  % 'optimum', 'ast', 'pressure'  
    opts.SpecDoF double = 64;
    opts.Kp_min double = 0.05;
    opts.pression_units char = 'dba';
    opts.wsa_toolbox_dir char = ''
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
    error('El archivo %s no se encuentra preprocesado');
end

%% Leer datos de la campaña del archivo netCDF

%Extraer datos de la campaña
burst_data = db_read_burst_principal(proc_ncfile, 'all');

%% Definir tipo de datos de entrada a utilizar según InputType

nBursts = size(burst_data.processed.ast, 3);

switch lower(opts.InputType)
    case 'optimum'
        
        %Inicializar tipos AST por defecto
        Type = repmat("ast", nBursts, 1);

        %Cambiar InputTypes en los que AST da problemas según criterios:

        %   1) Porcentaje de bad detects mayor al 10 % (ast_bad_detects_percentage > 10 %)
        bad_detects_idx = burst_data.processed.ast_bad_detects_percentage > 10;
        Type(bad_detects_idx(1, :)) = "pressure";

        %   2) Tilt mayor a 10° (bad_tilt_flag)
        bad_tilt_flag_raw = ncread(proc_ncfile, 'bad_tilt_flag');  %Esta bandera esta respecto a burst_raw
        burst_counter = burst_data.general.burst_counter;
        bad_tilt_idx = logical(bad_tilt_flag_raw(burst_counter));
        Type(bad_tilt_idx) = "pressure";

    case 'ast'
        Type = repmat("ast", nBursts, 1);
    case 'pressure'
        Type = repmat("pressure", nBursts, 1);
end

%% Ciclo principal

%Variables preliminares
ast_mean = burst_data.general.ast_mean;
mounting_height = burst_data.general.mounting_height;
z_p = -(ast_mean);
h   = ast_mean + mounting_height;
fs = burst_data.general.fs;



for b = 1:nBursts

    % Extraer datos del burst
    P = burst_data.processed.pressure(:, b);
    AST1 = burst_data.processed.ast(:, 1, b);

    switch Type(b)
        
        case "ast"
            %%% ------------------------ Basado en AST ------------------------ %%%%
            % Espectro frecuencial AST
            fprintf('\nCalculando espectro frecuencial basado en AST para burst %d\n', b);
            [out_spectrum, info_spectrum] = wsa_spectrum( ...
                                                        detrend(AST1), ...
                                                        fs, ...
                                                        'DoF', opts.SpecDoF, ...
                                                        'printFlag', 0);
        
        case "pressure"
            %%% ---------------------  Basado en Presión  --------------------- %%%%
            % Espectro frecuencial Presión
            fprintf('\nCalculando espectro frecuencial basado en Presión para burst %d\n', b);
            [out_spectrum, info_spectrum] = wsa_spectrum( ...
                                                        P, ...
                                                        fs, ...
                                                        'InputType', "pressure", ...
                                                        'un', opts.pression_units, ...
                                                        'z_p', z_p(b), ...
                                                        'h', h(b), ...
                                                        'DoF', opts.SpecDoF, ...
                                                        'Kp_min', opts.Kp_min, ...
                                                        'printFlag', 0);
        
        otherwise
            error('Tipo de entrada no reconocido para burst %d: %s', b, Type(b));
    end
        
    % Parámetros espectrales
    spec_parameters = wsa_spectral_parameters(out_spectrum);

    % Guardado directo de resultados
    burst_results(b).out_spectrum = out_spectrum;
    burst_results(b).info_spectrum = info_spectrum;
    burst_results(b).params.spectral = spec_parameters;
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

for b = 1:nBursts
    nc_data.S(:, b) = burst_results(b).out_spectrum.S;
end

bands   = {'total', 'ig', 'swell1', 'swell2', 'swell', 'wind'};

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


%% Crear archivo NetCDF

spectral_ncfile = fullfile(processed_dir, [Sitio, '_', Camp, '_spectral.nc']);

if isfile(spectral_ncfile)
    delete(spectral_ncfile);
end

nBurst = numel(nc_data.time);
nFreq = numel(nc_data.f);

%% Crear variables base del archivo NetCDF

wsa_nc_create_var(spectral_ncfile, ...
    'time', ...
    {'burst', nBurst}, ...
    'double', ...
    'units', 'seconds since 1970-01-01 00:00:00 UTC', ...
    'long_name', 'burst time' ...
    );

ncwrite(spectral_ncfile, 'time', wsa_datetime2posix(nc_data.time));

wsa_nc_create_var(spectral_ncfile, 'f', ...
    {'frequency', nFreq}, 'double', ...
    'units', 'Hz');

ncwrite(spectral_ncfile, 'f', nc_data.f);

wsa_nc_create_var(spectral_ncfile, 'Type', ...
    {'burst', nBurst}, 'string', ...
    'description', 'ast o pressure');

ncwrite(spectral_ncfile, 'Type', nc_data.Type);

wsa_nc_create_var(spectral_ncfile, 'S', ...
    {'frequency', nFreq, 'burst', nBurst}, 'double', ...
    'units', 'm2/Hz');

ncwrite(spectral_ncfile, 'S', nc_data.S);

%% Parámetros espectrales

bands = fieldnames(nc_data.spectral);

params = {'m0','m1','m2','m4','eta_rms','Hrms','Hm0','Tm01','Tm02','Tp','fp','v','Qp'};

for j = 1:numel(bands)

    band = bands{j};

    for k = 1:numel(params)

        param = params{k};
        varname = ['bands/' band '/' param];

        wsa_nc_create_var(spectral_ncfile, varname, ...
            {'burst', nBurst}, 'double');

        ncwrite(spectral_ncfile, varname, nc_data.spectral.(band).(param));

    end

    % band limits
    wsa_nc_create_var(spectral_ncfile, ['bands/' band '/band_limits'], ...
        {'limit', 2}, 'double', ...
        'units', 'Hz');

    ncwrite(spectral_ncfile, ['bands/' band '/band_limits'], ...
        nc_data.spectral.(band).band_limits(:));

end

%% Atributos globales
ncwriteatt(spectral_ncfile, '/', 'description', 'Espectro no direccional');
ncwriteatt(spectral_ncfile, '/', 'Sitio', Sitio);
ncwriteatt(spectral_ncfile, '/', 'Camp', Camp);
ncwriteatt(spectral_ncfile, '/', 'InputType', opts.InputType);

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

