function db_process_campaign(db_dir, Sitio, Camp, opts)


%% Manejo de entradas
arguments
    db_dir char
    Sitio char;
    Camp char;
    opts.mounting_height {mustBeNumeric} = []
    opts.wsa_toolbox_dir char = ''
end

mounting_height = opts.mounting_height;  %m

%% Verificaciones iniciales

if ~isfolder(db_dir)
    error('db_proc_camp:InvalidDbDir', ...
        'El directorio de base de datos no existe: %s', db_dir);
end

%% Path a funciones

% Toolbox WSA
if ~isempty(strtrim(opts.wsa_toolbox_dir))
    if ~isfolder(opts.wsa_toolbox_dir)
        error('db_proc_camp:InvalidWSAToolboxDir', ...
            'El directorio indicado para wsa_toolbox_dir no existe: %s', ...
            opts.wsa_toolbox_dir);
    end
    addpath(opts.wsa_toolbox_dir);
end

%% Verificación de dependencias requeridas

% Funciones mínimas requeridas del toolbox WSA
req_wsa = {
    'wsa_awac_read'
    'wsa_awac_clean'
    'wsa_awac_nc_write'
    };

% Verificar existencia de funciones
check_required_functions(req_wsa, 'WSA', 'opts.wsa_toolbox_dir');


%% Crear log file

log_dir = fullfile(db_dir, 'logs', 'processing_runs', Sitio, Camp);         %Directorio de los logs para procesamiento: logs/processing_runs/Sitio/Camp
if ~exist(log_dir, 'dir')                                                   %Crea el directorio si no existe
    mkdir(log_dir);
end
log_file = fullfile(log_dir, ['log_', Sitio, '_', Camp, '_proc_at_', ...    %Nombre del archivo log a guardar log_Sitio_Camp_proc_at_fecha.txt
            char(string(datetime('now'), 'yyyy-MM-dd_HHmmss')), '.txt']);
diary(log_file);                                                            %Comenzar a registrar archivo log.

%Encabezado del archivo log
fprintf('\n========================================================================================================================\n');
fprintf('Inicio de procesamiento: %s\n', char(string(datetime('now'), 'yyyy-MM-dd_HHmmss')));
fprintf('Sitio   : %s\n', Sitio);
fprintf('Campaña : %s\n', Camp);
fprintf('========================================================================================================================\n');

try 
%% Verificacion de altura de montaje del equipo

% Verificar si se especificó mounting_height para la campaña en el archivo
% de metadatos campaign.csv y usar este dato si no se especifica.
if isempty(mounting_height)                                                 % Se corre si mounting_height = [] (no se especificó)
    fprintf('\nNo se especificó altura del equipo (mounting_height), verificando si existe en el archivo de metadatos (metadata/campaign.csv).\n')
    metadata_file = fullfile(db_dir, 'metadata', 'campaigns.csv');
    if isfile(metadata_file)                                                % Verificar si existe mounting_height para el id en archivo campaign.csv
        id_search = [Sitio, '_', Camp];                                     % Id a buscar en metadatos: Sitio_Camp
        T_opts = detectImportOptions(metadata_file, 'Delimiter', ';');
        T_opts = setvartype(T_opts, T_opts.VariableNames, 'string');
        T = readtable(metadata_file, T_opts);                               % Leer tabla de metadatos
        idx = db_find_table_rows(T, "id", id_search);                       % Buscar id dentro de la tabla
        if ~isempty(idx)                                                    % Se ejecuta si existe el id
            fprintf('Existe el id de la campaña en el archivo de metadatos: id = %s.\n', id_search)
            mounting_height = double(T.mounting_height(idx));               % Asignar valor correspondiente al campo existente.
            if isnan(mounting_height)
                mounting_height = [];
            end
        else                                                                % Se ejecuta si no existe el id
            mounting_height = [];                                           % Asignar como string vacio para guardarlo en tabla
        end
    end
    fprintf('Utilizando la altura del equipo indicada en el archivo de metadatos: mounting_height = %.2f m.\n', mounting_height)
end


%% Leer Raw Data

files_dir = fullfile(db_dir, ...                                            %Directorio de archivos crudos: raw/Sitio/Camp/Raw_Data
                    'raw', Sitio, Camp, 'Raw_Data');                
save_plot_dir = fullfile(db_dir, ...                                        %Directorio para guardado de figuras: figures/Sitio/Camp/Quality
                    'figures', Sitio, Camp, 'Quality');

%Leer datos crudos
data = wsa_awac_read(files_dir, ...                                         %Struct con datos leidos y quality check
                    'do_plot', true, ...
                    'save_plot_dir', save_plot_dir);

%Exportar a netCDF en carpeta raw_nc
raw_nc_dir = fullfile(db_dir, 'raw_nc', Sitio);                 %Directorio para datos crudos: raw_nc/Sitio
if ~exist(fullfile(raw_nc_dir, Camp), 'dir')                          %Crea directorio para la campaña, en caso de no existir
    mkdir(fullfile(raw_nc_dir, Camp));
end
raw_ncfile = fullfile(raw_nc_dir, ...                                 %Nombre del archivo netCDF: Sitio_Camp_raw.nc
                      Camp , [Sitio, '_', Camp, '_', 'raw.nc']);
wsa_awac_nc_write(data, ...                                                 %Escribe el struct data en formato netCDF
                  raw_ncfile, ...
                  'site_name', Sitio, ...
                  'campaign_name', Camp, ...
                  'mounting_height', mounting_height);

%Imprimir el formato del archivo netCDF resultante
fprintf('\n\nFormato de archivo netCDF resultante:\n')                      
ncdisp(raw_ncfile);

%Registrar campaña en archivo de metadatos
fprintf('\nRegistrando campaña en archivo de metadatos de campaña: metadata\\campaign.csv\n')
start_date = data.quality.summary.time_start;
end_date = data.quality.summary.time_end;
instrument_serial = data.hdr.hardware_configuration.Serial_number;
status = 'raw';
raw_nc = raw_ncfile;
clean_nc = '';
db_register_campaign(db_dir, ...                                            %Función que registra los metadatos relevantes de la campaña
                     Sitio, ...
                     Camp, ...
                     start_date, ...
                     end_date, ...
                     mounting_height, ...
                     instrument_serial, ...
                     status, ...
                     raw_nc, ...
                     clean_nc)

%% Limpiar datos

%Limpieza de datos
data_clean = wsa_awac_clean(data);                                          %Función que limpia los datos extraidos con wsa_awac_read()

%Exportar a netCDF en carpeta processed
processed_dir = fullfile(db_dir, 'processed', Sitio);                       %Directorio para datos limpios: processed/Sitio
if ~exist(fullfile(processed_dir, Camp), 'dir')                             %Crea directorio para la campaña, en caso de no existir
    mkdir(fullfile(processed_dir, Camp));
end
clean_ncfile = fullfile(processed_dir, ...                                  %Nombre del archivo netCDF: Sitio_Camp_clean.nc
                        Camp , [Sitio, '_', Camp, '_', 'clean.nc']);
wsa_awac_nc_write(data_clean, ...                                           %Escribe el struct data en formato netCDF
                  clean_ncfile, ...
                  'site_name', Sitio, ...
                  'campaign_name', Camp, ...
                  'mounting_height', mounting_height);

fprintf('\n\nFormato de archivo netCDF resultante:\n')
ncdisp(clean_ncfile);

fprintf('\nRegistrando campaña en archivo de metadatos de campaña: metadata\\campaign.csv\n')
start_date = data_clean.cleaning.time_start;
end_date = data_clean.cleaning.time_end;
instrument_serial = data.hdr.hardware_configuration.Serial_number;
status = 'clean';
raw_nc = raw_ncfile;
clean_nc = clean_ncfile;
db_register_campaign(db_dir, ...                                            %Función que registra los metadatos relevantes de la campaña
                     Sitio, ...
                     Camp, ...
                     start_date, ...
                     end_date, ...
                     mounting_height, ...
                     instrument_serial, ...
                     status, ...
                     raw_nc, ...
                     clean_nc)

% Mensaje final si todo se realizó correctamente
fprintf('\n\n========================================================================================================================\n');
fprintf('Procesamiento finalizado correctamente: %s\n', char(string(datetime('now'), 'yyyy-MM-dd_HHmmss')));
fprintf('========================================================================================================================\n');

catch ME
    %Bloque que se corre en caso de errores y también genera un archivo de error
    
    % Mensaje a colocar en el archivo log.
    fprintf('\n\n========================================================================================================================\n');
    fprintf('ERROR durante el procesamiento: %s\n', char(string(datetime('now'), 'yyyy-MM-dd_HHmmss')));
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


%% Funciones auxiliares

function check_required_functions(func_list, toolbox_name, opt_name)
    missing = func_list(~cellfun(@(f) exist(f,'file') == 2, func_list));
    if ~isempty(missing)
        msg = sprintf(['No se encontraron funciones requeridas del toolbox %s en el path de MATLAB.\n' ...
                       'Funciones faltantes: %s\n' ...
                       'Agregue el path manualmente con addpath(...) o proporcione %s.'], ...
                       toolbox_name, strjoin(missing, ', '), opt_name);
        error('db_proc_camp:MissingDependencies', '%s', msg);
    end
end