function db_update_campaign_field(db_dir, Sitio, Camp, field_name, field_value)
%db_update_campaign_field - Actualiza un campo específico en campaigns.csv
%
%   db_update_campaign_field(db_dir, Sitio, Camp, field_name, field_value)
%
%   Actualiza únicamente el campo indicado para la campaña especificada
%   (id = Sitio_Camp) en el archivo metadata/campaigns.csv.
%
%   Entradas:
%       db_dir      - Directorio base de la base de datos
%       Sitio       - Nombre del sitio
%       Camp        - Nombre de la campaña
%       field_name  - Nombre de la columna a actualizar (string o char)
%       field_value - Nuevo valor (se convertirá a string)
%
% -------------------------------------------------------------------------
% Universidad de Costa Rica
% Escuela de Ingeniería Civil
% Autor: Danny Garro Arias
% -------------------------------------------------------------------------

%% Manejo de entradas

field_name  = string(field_name);
field_value = string(field_value);
Sitio       = string(Sitio);
Camp        = string(Camp);

metadata_file = fullfile(db_dir, 'metadata', 'campaigns.csv');

%% Verificar existencia del archivo

if ~isfile(metadata_file)
    warning('db_update_campaign_field:NoMetadataFile', ...
        'No existe el archivo campaigns.csv en: %s', metadata_file);
    return
end

%% Leer tabla

opts = detectImportOptions(metadata_file, 'Delimiter', ';');
opts = setvartype(opts, opts.VariableNames, 'string');
T = readtable(metadata_file, opts);

%% Verificar que exista la columna

if ~ismember(field_name, string(T.Properties.VariableNames))
    error('db_update_campaign_field:InvalidField', ...
        'La columna "%s" no existe en campaigns.csv.', field_name);
end

%% Buscar campaña

campaign_id = Sitio + "_" + Camp;

idx = db_find_table_rows(T, "id", campaign_id);

if isempty(idx)
    warning('db_update_campaign_field:CampaignNotFound', ...
        'No se encontró la campaña con id "%s".', campaign_id);
    return
end

%% Actualizar valor

T.(field_name)(idx(1)) = field_value;

% Eliminar duplicados si existen
if numel(idx) > 1
    T(idx(2:end), :) = [];
end

%% Escribir archivo actualizado

writetable(T, metadata_file, 'Delimiter', ';');

fprintf('Campo "%s" actualizado a "%s" para campaña %s.\n', ...
    field_name, field_value, campaign_id);

end