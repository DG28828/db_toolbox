function info = db_process_campaign(db_dir, Sitio, Camp, opts)
%
% Acciones:
% "procesamiento_completo"                  Lee raw, crea raw.nc, limpia, crea clean.nc y preprocesa
% "limpiar_raw_nc"                          Usa raw.nc existente, crea .nc limpio y preprocesa
% "preprocesar_datos_limpios_existentes"    Usa .nc limpio existente y ejecuta preprocesamiento
% "sobreescribir_datos_crudos_y_limpiar"    Fuerza raw.nc y .nc limpio por overwrite
% "sobreescribir_datos_limpios"             Fuerza .nc limpio usando raw.nc existente
% "limpio_y_preprocesado"                   Ya existe .nc limpio y ya está preprocesado
% "sobreescribir_datos_limpios"             Genera o conserva .nc limpio, pero no preprocesa
% "omitir"                                  Se omite por only_new=true


%% Manejo de entradas
arguments
    db_dir char
    Sitio char;
    Camp char;
    opts.mounting_height {mustBeNumeric} = []
    opts.wsa_toolbox_dir char = ''
    opts.raw_overwrite logical = false
    opts.clean_overwrite logical = false
    opts.preproc_overwrite logical = false
    opts.preproc_flag logical = true
end

mounting_height = opts.mounting_height;  %m

%% Inicializar struct info de salida
info = struct();
info.site = string(Sitio);
info.campaign = string(Camp);
info.raw_action = "not_evaluated";
info.clean_action = "not_evaluated";
info.preproc_action = "not_evaluated";
info.message = "";
info.log_file = "";
info.ncdisp_file = "";

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
    'wsa_awac_preprocess'
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
info.log_file = string(log_file);
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

%% Rutas de archivos NetCDF

raw_nc_dir = fullfile(db_dir, 'raw_nc', Sitio, Camp);
raw_ncfile = fullfile(raw_nc_dir, [Sitio, '_', Camp, '_raw.nc']);

processed_dir = fullfile(db_dir, 'processed', Sitio, Camp);
proc_ncfile = fullfile(processed_dir, [Sitio, '_', Camp, '.nc']);


%% Leer Raw Data y crear raw.nc

%Verificar existencia de archivo raw.nc
raw_exists = isfile(raw_ncfile);

if raw_exists && ~opts.raw_overwrite

    fprintf('\nYa existe raw.nc y raw_overwrite=false. Se omite lectura de Raw_Data.\n');
    fprintf('Archivo existente: %s\n', raw_ncfile);
    data = [];

    info.raw_action = "skipped_existing_raw_nc";

else
    files_dir = fullfile(db_dir, 'raw', Sitio, Camp, 'Raw_Data');               %Directorio de archivos crudos: raw/Sitio/Camp/Raw_Data
                                        
    save_plot_dir = fullfile(db_dir, 'figures', Sitio, Camp, 'Quality');        %Directorio para guardado de figuras: figures/Sitio/Camp/Quality
                        
    
    %Leer datos crudos
    data = wsa_awac_read(files_dir, ...                                         %Struct con datos leidos y quality check
                        'do_plot', true, ...
                        'save_plot_dir', save_plot_dir);
    
    %Exportar a netCDF en carpeta raw_nc
    if ~exist(raw_nc_dir, 'dir')
        mkdir(raw_nc_dir);                                                      %Crea directorio para la campaña, en caso de no existir
    end
    wsa_awac_nc_write(data, ...                                                 %Escribe el struct data en formato netCDF
                      raw_ncfile, ...
                      'site_name', Sitio, ...
                      'campaign_name', Camp, ...
                      'mounting_height', mounting_height);

    info.raw_action = "created_raw_nc";
    
    %Imprimir el formato del archivo netCDF resultante
    fprintf('\n\nFormato de archivo netCDF resultante:\n')                      
    ncdisp(raw_ncfile);
    
    %Registrar campaña en archivo de metadatos
    fprintf('\nRegistrando campaña en archivo de metadatos de campaña: metadata\\campaign.csv\n')
    start_date = data.quality.summary.time_start;
    end_date = data.quality.summary.time_end;
    raw_bursts = data.quality.summary.total_bursts;
    clean_bursts = [];
    instrument_serial = data.hdr.hardware_configuration.Serial_number;
    head_serial = data.hdr.head_configuration.Serial_number;
    clean_status = 'raw';
    proc_status = 'not_processed';
    raw_nc = raw_ncfile;
    proc_nc = '';
    db_register_campaign(db_dir, ...                                            %Función que registra los metadatos relevantes de la campaña
                         Sitio, ...
                         Camp, ...
                         start_date, ...
                         end_date, ...
                         raw_bursts, ...
                         clean_bursts, ...
                         mounting_height, ...
                         instrument_serial, ...
                         head_serial, ...
                         clean_status, ...
                         proc_status, ...
                         raw_nc, ...
                         proc_nc)
end

%% Limpiar datos y crear .nc en \processed

%Verificar existencia de archivo .nc en \processed 
proc_exists = isfile(proc_ncfile);

%Verifica estado de limpieza de archivo .nc
try
    cleaning_status = logical(ncreadatt(proc_ncfile, '/', 'cleaning_status'));
catch
    warning('No se pudo leer el atributo cleaning_status. Estableciendo cleaning_status = false')
    cleaning_status = false;
end 

if proc_exists && cleaning_status && ~opts.clean_overwrite

    fprintf('\nEl archivo .nc se encuentra limpio y clean_overwrite = false. Se omite limpieza.\n');
    fprintf('Archivo existente: %s\n', proc_ncfile);

    data_clean = [];

    info.clean_action = "skipped_existing_clean_nc";

else
    if isempty(data)
        fprintf('\nEl archivo raw.nc existe, pero se requiere limpiar nuevamente.\n');
        fprintf('Recuperando datos crudos desde raw.nc:\n%s\n', raw_ncfile);
    
        data_clean = wsa_awac_clean(raw_ncfile);

        info.clean_action = "created_clean_nc_from_existing_raw_nc";
    else
        data_clean = wsa_awac_clean(data);

        info.clean_action = "created_clean_nc_from_raw_data";
    end
    
    %Exportar a netCDF en carpeta processed
    processed_dir = fullfile(db_dir, 'processed', Sitio);                       %Directorio para datos limpios: processed/Sitio
    if ~exist(fullfile(processed_dir, Camp), 'dir')                             %Crea directorio para la campaña, en caso de no existir
        mkdir(fullfile(processed_dir, Camp));
    end
    proc_ncfile = fullfile(processed_dir, ...                                  %Nombre del archivo netCDF: Sitio_Camp.nc
                            Camp , [Sitio, '_', Camp, '.nc']);
    wsa_awac_nc_write(data_clean, ...                                           %Escribe el struct data en formato netCDF
                      proc_ncfile, ...
                      'site_name', Sitio, ...
                      'campaign_name', Camp, ...
                      'mounting_height', mounting_height);
    
    fprintf('\n\nFormato de archivo netCDF resultante:\n')
    ncdisp(proc_ncfile);
    
    fprintf('\nRegistrando campaña en archivo de metadatos de campaña: metadata\\campaign.csv\n')
    start_date = data_clean.cleaning.time_start;
    end_date = data_clean.cleaning.time_end;
    raw_bursts = data_clean.quality.summary.total_bursts;
    clean_bursts = data_clean.cleaning.Number_of_wave_measurements;
    instrument_serial = data_clean.hdr.hardware_configuration.Serial_number;
    head_serial = data_clean.hdr.head_configuration.Serial_number;
    clean_status = 'clean';
    proc_status = 'not_processed';
    raw_nc = raw_ncfile;
    proc_nc = proc_ncfile;
    db_register_campaign(db_dir, ...                                            %Función que registra los metadatos relevantes de la campaña
                         Sitio, ...
                         Camp, ...
                         start_date, ...
                         end_date, ...
                         raw_bursts, ...
                         clean_bursts, ...
                         mounting_height, ...
                         instrument_serial, ...
                         head_serial, ...
                         clean_status, ...
                         proc_status, ...
                         raw_nc, ...
                         proc_nc)
end

%% Preprocesamiento de los datos en el archivo netCDF

%Se ejecuta solo si preproc_flag = true (por defecto)
if opts.preproc_flag

    if isfile(proc_ncfile)
        ncfile_to_process = proc_ncfile;
        fprintf('\nPreprocesando archivo .nc con wsa_awac_preprocess:\n%s\n', ncfile_to_process);

    else
        error('db_proc_camp:MissingNetCDF', ...
            ['No existe .nc para ejecutar wsa_awac_preprocess.\n'
             'ncfile : %s'], ...
             proc_ncfile);
    end
    
    %Solo se preprocesa si no ha sido preprocesado o si se indica preproc_overwrite = true
    try
        preproc_status = logical(ncreadatt(ncfile_to_process, '/', 'preprocessing_status'));
    catch
        preproc_status = false;
    end

    if ~preproc_status || opts.preproc_overwrite
        proc_info = wsa_awac_preprocess(ncfile_to_process);

        %Indicar en el archivo .nc que se preprocesó la campaña
        ncwriteatt(ncfile_to_process, '/', 'preprocessing_status', double(true));

        %Indicar en el archivo de metadatos que se procesó la camapaña
        db_update_campaign_field(db_dir, Sitio, Camp, ...
                                'processing_status', 'processed');

        info.preproc_action = "preprocessed_clean_nc";
        fprintf('\n\nFormato de archivo netCDF resultante:\n')
        ncdisp(ncfile_to_process);
    else
        proc_info = [];
        info.preproc_action = "skipped_existing_preprocessing";
        fprintf('\nEl archivo ya estaba preprocesado y preproc_overwrite=false. Se omite wsa_awac_preprocess.\n');
    end

else

    proc_info = [];
    info.preproc_action = "disabled_by_preproc_flag";
    fprintf('\npreproc_flag=false. Se omite wsa_awac_preprocess.\n');

end

%% Generar archivo de texto con contenido del NetCDF en la carpeta

if isfile(proc_ncfile)
    info.ncdisp_file = db_write_ncdisp_txt(proc_ncfile);
else
    info.ncdisp_file = "";
    fprintf('\nNo se generó archivo ncdisp porque no existe el archivo .nc:\n%s\n', proc_ncfile);
end


%% Mensaje final si todo se realizó correctamente
info.message = sprintf( ...
    'raw: %s | clean: %s | preproc: %s', ...
    info.raw_action, ...
    info.clean_action, ...
    info.preproc_action);

fprintf('\nResumen de acciones realizadas:\n');
fprintf('%s\n', info.message);

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

function txt_file = db_write_ncdisp_txt(ncfile)
%db_write_ncdisp_txt - Guarda la salida de ncdisp en un archivo .txt.
%
%   txt_file = db_write_ncdisp_txt(ncfile)
%
%   Genera un archivo de texto en el mismo directorio del NetCDF con el
%   contenido mostrado por ncdisp.

    if ~isfile(ncfile)
        txt_file = "";
        return
    end

    [nc_dir, nc_name, ~] = fileparts(ncfile);
    txt_file = fullfile(nc_dir, [nc_name, '_ncdisp.txt']);

    nc_text = evalc('ncdisp(ncfile)');

    fid = fopen(txt_file, 'w');

    if fid == -1
        warning('db_write_ncdisp_txt:FileOpenError', ...
            'No se pudo crear el archivo ncdisp: %s', txt_file);
        txt_file = "";
        return
    end

    fprintf(fid, '%s', nc_text);
    fclose(fid);

    fprintf('\nArchivo ncdisp generado:\n%s\n', txt_file);

end