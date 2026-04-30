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

%% Manejo de entradas
arguments
    db_dir char
    opts.overwrite logical = false
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

campaign_metadata = fullfile(db_dir, 'metadata', 'campaigns.csv');
metadata_exists = isfile(campaign_metadata);
if isfile(campaign_metadata)
    metadata_table = db_read_metadata(db_dir);
else
    metadata_table = table();
end

%% Resultados

%Inicializar tabla de resultados
results = table(strings(0, 1), ...
                strings(0, 1), ...
                strings(0, 1), ...
                strings(0, 1), ...
                strings(0, 1), ...
                'VariableNames', { ...
                'site', ...
                'campaign', ...
                'action', ...
                'status', ...
                'message'});

%Procesar campañas
for i = 1:height(raw_campaigns_table)

    %Extraer id, sitio y campaña de la campaña a procesar
    id = char(raw_campaigns_table.id(i));
    Site = char(raw_campaigns_table.site(i));
    Camp = char(raw_campaigns_table.campaign(i));

    action = "process";
    skip_reason = "";

    clean_ncfile = fullfile(db_dir, 'processed', Site, Camp, [Site, '_', Camp, '_clean.nc']);   %Nombre del archivo limpio para verificar existencia

    cleaned_nc = isfile(clean_ncfile);                                         % Verifica si el archivo limpio ya existe

    % Verificar si en el archivo de metadatos (metadata/campaigns.csv) se indica que la campaña esta limpia
    cleaned_metadata = false;
    if metadata_exists && ~isempty(metadata_table)
        idx = db_find_table_rows(metadata_table, 'id', id);
        if ~isempty(idx) && ismember("status", string(metadata_table.Properties.VariableNames))
            cleaned_metadata = strcmpi(strtrim(metadata_table.status(idx)), "clean");
        end
    end

    % Seccion para verificar si se procesa (action = 'process') o se salta la campaña (action = 'skip')
    if opts.only_new && ~opts.overwrite
        if cleaned_nc || cleaned_metadata
            action = "skip";
            if cleaned_nc
                skip_reason = "Ya existe el archivo netCDF de la campaña limpia clean.nc";
            else
                skip_reason = "En archivo de metadatos (metadata/campaign.csv) se indica que la campaña esta limpia";
            end
        end
    end

    %Imprimir mensaje informativo
    fprintf('\n------------------------------------------------------------\n');
    fprintf('Site   : %s\n', Site);
    fprintf('Campaña : %s\n', Camp);
    fprintf('Acción  : %s\n', action);
    if action == "skip"
        fprintf('Motivo  : %s\n', skip_reason);
    end
    fprintf('------------------------------------------------------------\n');
    
    %Agregar información a la tabla de resultados y salir del ciclo si action = "skip"
    if action == "skip"
        results = [results; {string(Site), string(Camp), action, "skipped", skip_reason}]; %#ok<AGROW>
        continue
    end

    %Se ejecuta si action no es skip
    try

        db_process_campaign(db_dir, ...
                     Site, ...
                     Camp, ...
                    'mounting_height', opts.mounting_height, ...
                    'wsa_toolbox_dir', opts.wsa_toolbox_dir);

        results = [results; {string(Site), string(Camp), action, "success", ""}]; %#ok<AGROW>
        close all;

    catch ME

        msg = string(ME.message);
        results = [results; {string(Site), string(Camp), action, "error", msg}]; %#ok<AGROW>

        
        fprintf('Error procesando %s / %s:\n%s\n', Site, Camp, ME.message);
        

        if opts.stop_on_error
            rethrow(ME)
        end

    end

end









end