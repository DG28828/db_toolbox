function info = db_process_directional(db_dir, Sitio, Camp, opts)

%% Manejo de entradas
arguments
    db_dir char
    Sitio char;
    Camp char;
    opts.InputType char = 'optimum';  % 'optimum', 'ast', 'pressure'  
    opts.DirSpecDoF double = 64;
    opts.Kp_min double = 0.05;
    opts.pression_units char = 'dba';
    opts.DirConvention char = 'nautic_from';
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
fprintf('Inicio de procesamiento direccional: %s\n', char(string(datetime('now'), 'yyyy-MM-dd_HHmmss')));
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
z_v = burst_data.general.cell_position - ast_mean;
fs = burst_data.general.fs;


for b = 1:nBursts

    % Extraer datos del burst
    P    = burst_data.processed.pressure(:, b);
    AST1 = burst_data.processed.ast(:, 1, b);
    U    = burst_data.processed.velocity_enu(:, 1, b);
    V    = burst_data.processed.velocity_enu(:, 2, b);

    burst_results(b).Type = Type(b);

    switch Type(b)
        case "ast"
            fprintf('\nCalculando espectro direccional basado en AST para burst %d\n', b);
            [out_dirspectrum, info_dirspectrum] = wsa_dirspectrum( ...
                detrend(AST1), ...
                U, ...
                V, ...
                fs, ...
                'suv', ...
                'DoF', opts.DirSpecDoF, ...
                'z_v', z_v(b), ...
                'h', h(b));

        case "pressure"
            fprintf('\nCalculando espectro direccional basado en Presión para burst %d\n', b);
            [out_dirspectrum, info_dirspectrum] = wsa_dirspectrum( ...
                P, ...
                U, ...
                V, ...
                fs, ...
                'puv', ...
                'DoF', opts.DirSpecDoF, ...
                'un', opts.pression_units, ...
                'z_p', z_p(b), ...
                'z_v', z_v(b), ...
                'h', h(b), ...
                'Kp_min', opts.Kp_min);

        otherwise
            error('Tipo de entrada no reconocido para burst %d: %s', b, Type(b));
    end

    % Parámetros direccionales
    fourier_dir_parameters = wsa_directional_parameters(out_dirspectrum.Fourier);

    mem_dir_parameters = wsa_directional_parameters( ...
        out_dirspectrum.MEM.f, ...
        out_dirspectrum.MEM.S, ...
        out_dirspectrum.MEM.coeffs_mem.a1, ...
        out_dirspectrum.MEM.coeffs_mem.b1, ...
        'a2', out_dirspectrum.MEM.coeffs_mem.a2, ...
        'b2', out_dirspectrum.MEM.coeffs_mem.b2);

    % Conversión de direcciones

    switch lower(opts.DirConvention)
        case {'nautic_from', 'nautica_desde'}
            out_dirspectrum = wsa_cartto2nautfrom(out_dirspectrum);
            fourier_dir_parameters = wsa_cartto2nautfrom(fourier_dir_parameters);
            mem_dir_parameters = wsa_cartto2nautfrom(mem_dir_parameters);

        case {'cartesian_to', 'cartesiana_desde'}

        otherwise
            error('Se debe especificar alguna de las siguientes convenciones de dirección: ''cartesiana_hacia'' | ''nautica_desde'' ')
    end

    % Guardado 
    burst_results(b).out_dirspectrum = out_dirspectrum;
    burst_results(b).info_dirspectrum = info_dirspectrum;

    burst_results(b).params.Fourier = fourier_dir_parameters;
    burst_results(b).params.MEM = mem_dir_parameters;

end

%% Reorganización de datos para NetCDF

nc_data = struct();

nc_data.time = burst_data.general.time(1:nBursts);
nc_data.Type = Type;

Methods = {'Fourier', 'MEM'};
bands   = {'total', 'ig', 'swell1', 'swell2', 'swell', 'wind'};

for k = 1:numel(Methods)

    method = Methods{k};

    % Frecuencia y dirección
    nc_data.directional.(method).f = burst_results(1).out_dirspectrum.(method).f;

    nc_data.directional.(method).theta = burst_results(1).out_dirspectrum.(method).theta;

    nFreq = numel(nc_data.directional.(method).f);
    nTheta = numel(nc_data.directional.(method).theta);

    % Inicializar espectros direccionales
    nc_data.directional.(method).E = NaN(nFreq, nTheta, nBursts, 'single');
    nc_data.directional.(method).S = NaN(nFreq, nBursts);

    %Inicializar espectros de parámetros
    nc_data.directional.(method).f_mean_dir = NaN(nFreq, nBursts);
    nc_data.directional.(method).f_dir_spr = NaN(nFreq, nBursts);

    % Inicializar coeficientes
    nc_data.directional.(method).a1 = NaN(nFreq, nBursts);
    nc_data.directional.(method).b1 = NaN(nFreq, nBursts);
    nc_data.directional.(method).a2 = NaN(nFreq, nBursts);
    nc_data.directional.(method).b2 = NaN(nFreq, nBursts);

    for b = 1:nBursts

        out_method = burst_results(b).out_dirspectrum.(method);

        nc_data.directional.(method).E(:, :, b) = out_method.E;
        nc_data.directional.(method).S(:, b)    = out_method.S;

        nc_data.directional.(method).f_mean_dir(:, b)   = burst_results(b).params.(method).f_mean_dir;
        nc_data.directional.(method).f_dir_spr(:, b)    = burst_results(b).params.(method).f_dir_spr;

        if strcmp(method, 'Fourier')
            coeffs = out_method.coeffs;
        else
            coeffs = out_method.coeffs_mem;
        end

        nc_data.directional.(method).a1(:, b) = coeffs.a1;
        nc_data.directional.(method).b1(:, b) = coeffs.b1;
        nc_data.directional.(method).a2(:, b) = coeffs.a2;
        nc_data.directional.(method).b2(:, b) = coeffs.b2;

    end

    % Parámetros direccionales por banda
    for j = 1:numel(bands)

        band = bands{j};

        nc_data.directional.(method).bands.(band).DirTp = arrayfun(@(x) x.params.(method).bands.(band).DirTp, burst_results).';

        nc_data.directional.(method).bands.(band).SprTp = arrayfun(@(x) x.params.(method).bands.(band).SprTp, burst_results).';

        nc_data.directional.(method).bands.(band).MeanDir = arrayfun(@(x) x.params.(method).bands.(band).MeanDir, burst_results).';

        nc_data.directional.(method).bands.(band).MeanSpread = arrayfun(@(x) x.params.(method).bands.(band).MeanSpread, burst_results).';

        nc_data.directional.(method).bands.(band).band_limits = burst_results(1).params.(method).bands.(band).band_limits;

    end
end

%% Crear archivo NetCDF

directional_ncfile = fullfile(processed_dir, [Sitio, '_', Camp, '_directional.nc']);

if isfile(directional_ncfile)
    delete(directional_ncfile);
end

nBurst = numel(nc_data.time);

%% Crear variables base del archivo NetCDF

wsa_nc_create_var(directional_ncfile, ...
    'time', ...
    {'burst', nBurst}, ...
    'double', ...
    'units', 'seconds since 1970-01-01 00:00:00 UTC', ...
    'long_name', 'burst time' ...
    );
ncwrite(directional_ncfile, 'time', wsa_datetime2posix(nc_data.time));


wsa_nc_create_var(directional_ncfile, ...
    'Type', ...
    {'burst', nBurst}, ...
    'string', ...
    'description', 'Tipo de señal usada por burst: ast o pressure' ...
    );
ncwrite(directional_ncfile, 'Type', nc_data.Type);

%% Métodos

Methods = fieldnames(nc_data.directional);

dir_params = {'DirTp', 'SprTp', 'MeanDir', 'MeanSpread', 'fp', 'Tp', 'm0'};

for k = 1:numel(Methods)

    method = Methods{k};

    f     = nc_data.directional.(method).f;
    theta = nc_data.directional.(method).theta;

    nFreq  = numel(f);
    nTheta = numel(theta);

    freq_dim = [method '_frequency'];
    dir_dim  = [method '_direction'];

    % Coordenadas
    wsa_nc_create_var(directional_ncfile, ...
        [method '/f'], ...
        {freq_dim, nFreq}, ...
        'double', ...
        'units', 'Hz' ...
        );
    ncwrite(directional_ncfile, [method '/f'], f);

    wsa_nc_create_var(directional_ncfile, ...
        [method '/theta'], ...
        {dir_dim, nTheta}, ...
        'double', ...
        'units', 'degrees' ...
        );
    ncwrite(directional_ncfile, [method '/theta'], theta);

    % Espectros
    wsa_nc_create_var(directional_ncfile, ...
        [method '/E'], ...
        {freq_dim, nFreq, dir_dim, nTheta, 'burst', nBurst}, ...
        'single', ...
        'units', 'm2/Hz/deg', ...
        'long_name', 'directional energy spectrum', ...
        'DeflateLevel', 3, ...
        'Shuffle', true);
    ncwrite(directional_ncfile, [method '/E'], nc_data.directional.(method).E);

    wsa_nc_create_var(directional_ncfile, ...
        [method '/S'], ...
        {freq_dim, nFreq, 'burst', nBurst}, ...
        'double', ...
        'units', 'm2/Hz', ...
        'long_name', 'frequency spectrum associated with directional calculation' ...
        );
    ncwrite(directional_ncfile, [method '/S'], nc_data.directional.(method).S);

    % Coeficientes
    coeff_names = {'a1','b1','a2','b2'};

    for c = 1:numel(coeff_names)

        coeff = coeff_names{c};

        wsa_nc_create_var(directional_ncfile, ...
            [method '/' coeff], ...
            {freq_dim, nFreq, 'burst', nBurst}, ...
            'double', ...
            'long_name', ['directional Fourier coefficient ' coeff] ...
            );
        ncwrite(directional_ncfile, [method '/' coeff], nc_data.directional.(method).(coeff));

    end

    %Espectros de parámetros de dirección media y spread (f_mean_dir y f_dir_spr)
    wsa_nc_create_var(directional_ncfile, ...
        [method '/f_mean_dir'], ...
        {freq_dim, nFreq, 'burst', nBurst}, ...
        'double', ...
        'units', 'm2/Hz', ...
        'long_name', 'mean direction spectrum' ...
        );
    ncwrite(directional_ncfile, [method '/f_mean_dir'], nc_data.directional.(method).f_mean_dir);

    wsa_nc_create_var(directional_ncfile, ...
        [method '/f_dir_spr'], ...
        {freq_dim, nFreq, 'burst', nBurst}, ...
        'double', ...
        'units', 'm2/Hz', ...
        'long_name', 'directional spread spectrum' ...
        );
    ncwrite(directional_ncfile, [method '/f_dir_spr'], nc_data.directional.(method).f_dir_spr);

    %% Parámetros direccionales por banda

    bands = fieldnames(nc_data.directional.(method).bands);

    for j = 1:numel(bands)

        band = bands{j};

        for p = 1:numel(dir_params)

            param = dir_params{p};

            if ~isfield(nc_data.directional.(method).bands.(band), param)
                continue
            end

            varname = [method '/bands/' band '/' param];

            wsa_nc_create_var(directional_ncfile, ...
                varname, ...
                {'burst', nBurst}, ...
                'double' ...
                );
            ncwrite(directional_ncfile, varname, nc_data.directional.(method).bands.(band).(param));

        end

        %% Límites de banda

        limits_var = [method '/bands/' band '/band_limits'];

        wsa_nc_create_var(directional_ncfile, ...
            limits_var, ...
            {'limit', 2}, ...
            'double', ...
            'units', 'Hz' ...
            );
        ncwrite(directional_ncfile, limits_var, nc_data.directional.(method).bands.(band).band_limits(:));

    end
end

%% Atributos globales
ncwriteatt(directional_ncfile, '/', 'description', 'Resultados direccionales de oleaje');
ncwriteatt(directional_ncfile, '/', 'source_file', proc_ncfile);
ncwriteatt(directional_ncfile, '/', 'Sitio', Sitio);
ncwriteatt(directional_ncfile, '/', 'Camp', Camp);
ncwriteatt(directional_ncfile, '/', 'InputType', opts.InputType);
ncwriteatt(directional_ncfile, '/', 'DirConvention', opts.DirConvention);
ncwriteatt(directional_ncfile, '/', 'DirSpecDoF', opts.DirSpecDoF);

info.directional_ncfile = string(directional_ncfile);

%% Generar archivo de texto con contenido del NetCDF en la carpeta

if isfile(directional_ncfile)
    info.ncdisp_file = db_write_ncdisp_txt(directional_ncfile);
    fprintf('\n\nFormato de archivo netCDF resultante:\n')
    ncdisp(directional_ncfile);
else
    info.ncdisp_file = "";
    fprintf('\nNo se generó archivo ncdisp porque no existe el archivo .nc:\n%s\n', directional_ncfile);
end

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

