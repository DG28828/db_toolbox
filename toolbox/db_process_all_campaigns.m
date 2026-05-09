function results = db_process_all_campaigns(db_dir, opts)
%db_process_all_campaigns Procesa automáticamente campañas detectadas en raw/.
%
%   results = db_process_all_campaigns(db_dir)
%   results = db_process_all_campaigns(db_dir, 'overwrite', true)
%
% Recorre:
%   raw/Sitio/Camp/Raw_Data
%
% y llama a:
%   db_proc_camp(db_dir, Sitio, Camp, ...)
%
% Salida:
%   results : tabla resumen de ejecución
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
    opts.raw_overwrite logical = false
    opts.clean_overwrite logical = false
    opts.preproc_overwrite logical = false
    opts.preproc_flag logical = true
    opts.only_new logical = true
    opts.mounting_height = []
    opts.wsa_toolbox_dir char = ''
    opts.stop_on_error logical = false
end

%% Verificaciones iniciales

%Verificar que exista el directorio indicado de la base de datos
if ~isfolder(db_dir)
    error('db_process_all_campaigns:InvalidDbDir', ...
        'El directorio de base de datos no existe: %s', db_dir);
end

%Verificar que exista el directorio /raw
raw_dir = fullfile(db_dir, 'raw');
if ~isfolder(raw_dir)
    error('db_process_all_campaigns:MissingRawDir', ...
        'No existe la carpeta raw: %s', raw_dir);
end

%% Detectar campañas

%Detectar campañas en /raw
raw_campaigns_table = db_list_campaigns_raw(db_dir);
if isempty(raw_campaigns_table)
    warning('db_process_all_campaigns:NoCampaigns', ...
        'No se detectaron campañas válidas en raw/.');
    results = table();
    return
end

%% Leer metadatos

% campaign_metadata = fullfile(db_dir, 'metadata', 'campaigns.csv');
% metadata_exists = isfile(campaign_metadata);
% if isfile(campaign_metadata)
%     metadata_table = db_read_metadata(db_dir);
% else
%     metadata_table = table();
% end

%% Resultados

%Inicializar tabla de resultados
results = table(strings(0, 1), ...
                strings(0, 1), ...
                strings(0, 1), ...
                strings(0, 1), ...
                strings(0, 1), ...
                strings(0, 1), ...
                'VariableNames', { ...
                'site', ...
                'campaign', ...
                'action', ...
                'status', ...
                'message', ...
                'actual_message'});

%Procesar campañas
for i = 1:height(raw_campaigns_table)

    %Extraer id, sitio y campaña de la campaña a procesar
    id = char(raw_campaigns_table.id(i));
    Site = char(raw_campaigns_table.site(i));
    Camp = char(raw_campaigns_table.campaign(i));

    %Inicializar accion, skip_reason y message
    action = "";
    skip_reason = "";
    message = "";
    
    %Verificar si existen raw.nc y clean.nc
    raw_ncfile = fullfile(db_dir, 'raw_nc', Site, Camp, [Site, '_', Camp, '_raw.nc']);
    proc_ncfile = fullfile(db_dir, 'processed', Site, Camp, [Site, '_', Camp, '.nc']);
    raw_nc_exists = isfile(raw_ncfile);
    proc_nc_exists = isfile(proc_ncfile);

    % Verificar estado según archivo de metadatos
    cleaned_metadata = false;
    processed_metadata = false;
    try
        camp_info = db_get_campaign_info(db_dir, Site, Camp);
    
        if isfield(camp_info, 'cleaning status')
            cleaned_metadata = strcmpi(strtrim(camp_info.("cleaning status")), "clean");
        end
    
        if isfield(camp_info, 'processing_status')
            processed_metadata = strcmpi(strtrim(camp_info.processing_status), "processed");
        end
    
    catch
        camp_info = struct();
        cleaned_metadata = false;
        processed_metadata = false;
    end

    % Se asigna logica a preproc_status según cualquiera de los dos, ya sea
    %   el .nc o metadata.csv indiquen que preprocessing_status = 'processed'
    preproc_status_nc = false;
    if proc_nc_exists
        try
            preproc_status_nc = logical(ncreadatt(clean_ncfile, '/', 'preprocessing_status'));
        catch
            preproc_status_nc = false;
        end
    end
    preproc_status = preproc_status_nc || processed_metadata;

    % -------------------------------------------------------------------------
    % Definir acción esperada

    if opts.only_new && proc_nc_exists && (~opts.preproc_flag || preproc_status) && ~opts.raw_overwrite && ~opts.clean_overwrite && ~opts.preproc_overwrite
        action = "omitir";
        skip_reason = "Solo campañas nuevas, la campaña cuenta con archivo .nc y no se solicitó reprocesamiento.";
        message = skip_reason;

    elseif opts.raw_overwrite && opts.clean_overwrite
        action = "obreescribir_datos_crudos_y_limpiar";
        message = "Se regenerará raw.nc desde Raw_Data, se regenerará clean.nc y se aplicará preprocesamiento si corresponde.";

    elseif opts.clean_overwrite && raw_nc_exists && ~opts.raw_overwrite
        action = "sobreescribir_datos_limpios";
        message = "Se usará raw.nc existente para regenerar archivo .nc limpio; no se volverá a leer Raw_Data.";
    
    elseif ~raw_nc_exists && ~proc_nc_exists
        action = "procesamiento_completo";
        message = "No existen raw.nc ni archivo .nc limpio; se leerá Raw_Data, se creará raw.nc, se limpiará y se preprocesará si corresponde.";
    
    elseif raw_nc_exists && ~proc_nc_exists
        action = "limpiar_raw_nc";
        message = "Ya existe raw.nc, pero no el archivo .nc limpio; se omitirá lectura Raw_Data y se generará clean.nc.";
    
    elseif proc_nc_exists && opts.preproc_flag && (~preproc_status || opts.preproc_overwrite)
        action = "preprocesar_datos_limpios_existentes";
        if opts.preproc_overwrite && preproc_status
            message = "Ya existe el archivo .nc limpio y ya estaba preprocesado, pero preproc_overwrite = true; se reprocesará.";
        else
            message = "Ya existe el archivo .nc limpio, pero no está preprocesado; se ejecutará wsa_awac_process.";
        end
    
    elseif proc_nc_exists && ~opts.preproc_flag
        action = "sobreescribir_datos_limpios";
        message = "Ya existe el archivo .nc limpio y preproc_flag=false; no se ejecutará preprocesamiento.";
    
    elseif proc_nc_exists && preproc_status
        action = "limpio_y_preprocesado";
        message = "Ya existe el archivo .nc limpio y la campaña ya está preprocesada.";
    
    elseif cleaned_metadata && ~proc_nc_exists
        action = "metadatos_inconsistentes";
        message = "Los metadatos indican estado limpio, pero no se encontró el archivo .nc limpio; se intentará reprocesar la campaña.";
    
    else
        action = "procesar";
        message = "Se procesará con los parámetros indicados.";
    end
    % -------------------------------------------------------------------------

    %Imprimir mensaje informativo
    fprintf('\n------------------------------------------------------------\n');
    fprintf('Site    : %s\n', Site);
    fprintf('Campaña : %s\n', Camp);
    fprintf('Acción  : %s\n', action);
    fprintf('Detalle : %s\n', message);
    
    if action == "omitir"
        fprintf('Motivo  : %s\n', skip_reason);
    end
    
    fprintf('raw.nc  : %s\n', string(raw_nc_exists));
    fprintf('clean.nc: %s\n', string(proc_nc_exists));
    fprintf('preproc : %s\n', string(preproc_status));
    fprintf('------------------------------------------------------------\n');
    
    %Agregar información a la tabla de resultados y salir del ciclo si action = "skip"
    if action == "omitir"
        results = [results; {string(Site), string(Camp), action, "skipped", message, ""}]; %#ok<AGROW>
        continue
    end

    %Se ejecuta si action no es skip
    try

        run_info = db_process_campaign(db_dir, ...
                     Site, ...
                     Camp, ...
                    'mounting_height', opts.mounting_height, ...
                    'wsa_toolbox_dir', opts.wsa_toolbox_dir, ...
                    'raw_overwrite', opts.raw_overwrite, ...
                    'clean_overwrite', opts.clean_overwrite, ...
                    'preproc_overwrite', opts.preproc_overwrite, ...
                    'preproc_flag', opts.preproc_flag);

        results = [results; {string(Site), string(Camp), action, "success", message, run_info.message}]; %#ok<AGROW>
        close all;

    catch ME

        msg = string(ME.message);
        results = [results; { string(Site), string(Camp), action, "error", msg, ""}]; %#ok<AGROW>

        
        fprintf('Error procesando %s / %s:\n%s\n', Site, Camp, ME.message);
        

        if opts.stop_on_error
            rethrow(ME)
        end

    end

end









end