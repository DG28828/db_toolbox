function campaign_info = db_get_campaign_info(db_dir, Sitio, Camp)
%db_get_campaign_info - Obtiene la fila de metadata para una campaña.
%
%   campaign_info = db_get_campaign_info(db_dir, Sitio, Camp)
%
%   Busca la campaña con id = Sitio_Camp dentro de metadata/campaigns.csv
%   y devuelve su información como struct.

%% Manejo de entradas

Sitio = string(Sitio);
Camp  = string(Camp);

metadata_file = fullfile(db_dir, 'metadata', 'campaigns.csv');
campaign_id = Sitio + "_" + Camp;

%% Verificar existencia del archivo

if ~isfile(metadata_file)
    error('db_get_campaign_info:NoMetadataFile', ...
        'No existe el archivo de metadatos: %s', metadata_file);
end

%% Leer tabla

opts = detectImportOptions(metadata_file, 'Delimiter', ';');
opts = setvartype(opts, opts.VariableNames, 'string');
T = readtable(metadata_file, opts);

%% Verificar columna id

if ~ismember("id", string(T.Properties.VariableNames))
    error('db_get_campaign_info:MissingIdColumn', ...
        'El archivo campaigns.csv no contiene la columna "id".');
end

%% Buscar campaña

idx = db_find_table_rows(T, "id", campaign_id);

if isempty(idx)
    error('db_get_campaign_info:CampaignNotFound', ...
        'No se encontró la campaña con id "%s".', campaign_id);
end

if numel(idx) > 1
    warning('db_get_campaign_info:DuplicatedCampaign', ...
        'Se encontraron varias filas con id "%s". Se usará la primera.', campaign_id);
end

%% Convertir fila a struct

row = T(idx(1), :);
campaign_info = table2struct(row);

end