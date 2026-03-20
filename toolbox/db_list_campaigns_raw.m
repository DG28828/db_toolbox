function T = db_list_campaigns_raw(db_dir)
%db_list_campaigns_raw Lista campañas detectadas en raw/Sitio/Camp/Raw_Data

raw_dir = fullfile(db_dir, 'raw');                                          %Directorio raw: db_dir/raw

%Extraer nombres de carpetas de sitios en raw/
site_dirs = dir(raw_dir);                                                   %Extrae las carpetas existentes en db_dir/raw/
site_dirs = site_dirs([site_dirs.isdir]);                                   %Mantiene solo los directorios
site_dirs = site_dirs(~ismember({site_dirs.name}, {'.', '..'}));            %Mantiene solo los directorios que no son . y ..

%Inicializar vectores de strings
site = strings(0, 1);                                                       
campaign = strings(0, 1);
id = strings(0, 1);
raw_data_dir = strings(0, 1);

%Ciclo de sitios
for s = 1:numel(site_dirs)

    Site = string(site_dirs(s).name);
    site_dir = fullfile(raw_dir, Site);                                     %Directorio del Sitio: db_dir/raw/Sitio

    %Extraer nombres de carpetas de sitios en raw/Sitio/
    camp_dirs = dir(site_dir);                                              %Extrae las carpetas existentes en db_dir/raw/Sitio/
    camp_dirs = camp_dirs([camp_dirs.isdir]);                               %Mantiene solo los directorios
    camp_dirs = camp_dirs(~ismember({camp_dirs.name}, {'.', '..'}));        %Mantiene solo los directorios que no son . y ..
    
    %Ciclo de campañas en sitio
    for c = 1:numel(camp_dirs)

        Camp = string(camp_dirs(c).name);
        raw_data_path = fullfile(site_dir, Camp, 'Raw_Data');               %Directorio Raw_Data: db_dir/raw/Sitio/Camp/Raw_Data

        if isfolder(raw_data_path)                                          %Ejecutar si existe el directorio Raw_Data
            site(end+1,1) = Site; %#ok<AGROW>
            campaign(end+1,1) = Camp; %#ok<AGROW>
            id(end+1,1) = Site + "_" + Camp; %#ok<AGROW>
            raw_data_dir(end+1,1) = string(raw_data_path); %#ok<AGROW>
        end
    end
end

%Guardar resultados Sitio - Campaña en formato de tabla
T = table(site, campaign, id, raw_data_dir);

%Ordena la tabla
if ~isempty(T)
    T = sortrows(T, {'site','campaign'});
end


end