function results = db_process_all_spec_dir(db_dir, opts)
%db_process_all_spec_dir Procesa espectros y espectros direccionales de todas las campañas.
%
%   results = db_process_all_spec_dir(db_dir)
%

%% Manejo de entradas
arguments
    db_dir char

    opts.InputType char = 'optimum'
    opts.SpecDoF double = 16
    opts.DirSpecDoF double = 64
    opts.Kp_min double = 0.05
    opts.pressure_units char = 'dba'
    opts.DirConvention char = 'nautic_from'

    opts.spectral_flag logical = true
    opts.directional_flag logical = true

    opts.spectral_overwrite logical = false
    opts.directional_overwrite logical = false

    opts.only_new logical = true
    opts.wsa_toolbox_dir char = ''
    opts.stop_on_error logical = false
end

%% Verificaciones iniciales

if ~isfolder(db_dir)
    error('El directorio de base de datos no existe: %s', db_dir);
end

%% Detectar campañas preprocesadas en /processed

processed_dir = fullfile(db_dir, 'processed');

if ~isfolder(processed_dir)
    error('No existe la carpeta processed: %s', processed_dir);
end

raw_sites = dir(processed_dir);
raw_sites = raw_sites([raw_sites.isdir]);
raw_sites = raw_sites(~ismember({raw_sites.name}, {'.','..'}));

campaign_rows = strings(0, 2);

for i = 1:numel(raw_sites)

    Site = raw_sites(i).name;
    site_dir = fullfile(processed_dir, Site);

    camp_dirs = dir(site_dir);
    camp_dirs = camp_dirs([camp_dirs.isdir]);
    camp_dirs = camp_dirs(~ismember({camp_dirs.name}, {'.','..'}));

    for j = 1:numel(camp_dirs)

        Camp = camp_dirs(j).name;

        proc_ncfile = fullfile(processed_dir, Site, Camp, ...
            [Site, '_', Camp, '.nc']);

        if ~isfile(proc_ncfile)
            continue
        end

        try
            preprocessing_status = logical(ncreadatt(proc_ncfile, '/', 'preprocessing_status'));
        catch
            preprocessing_status = false;
        end

        if preprocessing_status
            campaign_rows(end+1, :) = [string(Site), string(Camp)]; %#ok<AGROW>
        end

    end
end

if isempty(campaign_rows)
    warning('No se detectaron campañas con preprocessing_status = 1 en processed/.');
    results = table();
    return
end

campaigns_table = table( ...
    campaign_rows(:,1), ...
    campaign_rows(:,2), ...
    'VariableNames', {'site','campaign'});

%% Inicializar tabla de resultados

results = table(strings(0,1), ...
                strings(0,1), ...
                strings(0,1), ...
                strings(0,1), ...
                strings(0,1), ...
                strings(0,1), ...
                strings(0,1), ...
                strings(0,1), ...
                'VariableNames', { ...
                'site', ...
                'campaign', ...
                'action', ...
                'spectral_status', ...
                'directional_status', ...
                'message', ...
                'spectral_file', ...
                'directional_file'});

%% Procesar campañas

for i = 1:height(campaigns_table)

    Site = char(campaigns_table.site(i));
    Camp = char(campaigns_table.campaign(i));

    proc_ncfile = fullfile(db_dir, 'processed', Site, Camp, ...
        [Site, '_', Camp, '.nc']);

    spectral_ncfile = fullfile(db_dir, 'processed', Site, Camp, ...
        [Site, '_', Camp, '_spectral.nc']);

    directional_ncfile = fullfile(db_dir, 'processed', Site, Camp, ...
        [Site, '_', Camp, '_directional.nc']);

    proc_exists = isfile(proc_ncfile);
    spectral_exists = isfile(spectral_ncfile);
    directional_exists = isfile(directional_ncfile);

    spectral_status = "";
    directional_status = "";
    action = "";
    message = "";

    %% Verificar archivo preprocesado base

    if ~proc_exists
        action = "omitir";
        message = "No existe archivo .nc preprocesado base.";
        spectral_status = "skipped";
        directional_status = "skipped";

        results = [results; { ...
            string(Site), ...
            string(Camp), ...
            action, ...
            spectral_status, ...
            directional_status, ...
            message, ...
            "", ...
            ""}]; %#ok<AGROW>

        continue
    end

    try
        is_preprocessed = logical(ncreadatt(proc_ncfile, '/', 'preprocessing_status'));
    catch
        is_preprocessed = false;
    end

    if ~is_preprocessed
        action = "omitir";
        message = "El archivo .nc base existe, pero no está preprocesado.";
        spectral_status = "skipped";
        directional_status = "skipped";

        results = [results; { ...
            string(Site), ...
            string(Camp), ...
            action, ...
            spectral_status, ...
            directional_status, ...
            message, ...
            "", ...
            ""}]; %#ok<AGROW>

        continue
    end

    %% Decidir acción

    do_spectral = opts.spectral_flag && ...
        (~spectral_exists || opts.spectral_overwrite || ~opts.only_new);

    do_directional = opts.directional_flag && ...
        (~directional_exists || opts.directional_overwrite || ~opts.only_new);

    if ~opts.spectral_flag && ~opts.directional_flag
        action = "omitir";
        message = "spectral_flag=false y directional_flag=false.";

    elseif ~do_spectral && ~do_directional
        action = "omitir";
        message = "Ya existen los productos solicitados y no se pidió overwrite.";

    elseif do_spectral && do_directional
        action = "procesar_espectral_y_direccional";
        message = "Se procesará el producto espectral y el producto direccional.";

    elseif do_spectral
        action = "procesar_espectral";
        message = "Se procesará únicamente el producto espectral.";

    elseif do_directional
        action = "procesar_direccional";
        message = "Se procesará únicamente el producto direccional.";
    end

    %% Mostrar estado

    fprintf('\n------------------------------------------------------------\n');
    fprintf('Site              : %s\n', Site);
    fprintf('Campaña           : %s\n', Camp);
    fprintf('Acción            : %s\n', action);
    fprintf('Detalle           : %s\n', message);
    fprintf('base .nc          : %s\n', string(proc_exists));
    fprintf('preprocessed      : %s\n', string(is_preprocessed));
    fprintf('spectral exists   : %s\n', string(spectral_exists));
    fprintf('directional exists: %s\n', string(directional_exists));
    fprintf('------------------------------------------------------------\n');

    if action == "omitir"
        spectral_status = "skipped";
        directional_status = "skipped";

        if spectral_exists
            spectral_file_out = string(spectral_ncfile);
        else
            spectral_file_out = "";
        end
    
        if directional_exists
            directional_file_out = string(directional_ncfile);
        else
            directional_file_out = "";
        end

        results = [results; { ...
            string(Site), ...
            string(Camp), ...
            action, ...
            spectral_status, ...
            directional_status, ...
            message, ...
            spectral_file_out, ...
            directional_file_out}]; %#ok<AGROW>

        continue
    end

    %% Ejecutar procesamiento

    try

        spectral_file_out = "";
        directional_file_out = "";

        if do_spectral

            spectral_info = db_process_spectral(db_dir, ...
                Site, ...
                Camp, ...
                'InputType', opts.InputType, ...
                'SpecDoF', opts.SpecDoF, ...
                'Kp_min', opts.Kp_min, ...
                'pressure_units', opts.pressure_units, ...
                'wsa_toolbox_dir', opts.wsa_toolbox_dir, ...
                'IG_flag', true, ...
                'IG_export_fmax', 0.1);

            spectral_status = "success";

            if isfield(spectral_info, 'spectral_ncfile')
                spectral_file_out = spectral_info.spectral_ncfile;
            else
                spectral_file_out = string(spectral_ncfile);
            end

        else
            spectral_status = "skipped";
            spectral_file_out = string(spectral_ncfile);
        end

        if do_directional

            directional_info = db_process_directional(db_dir, ...
                Site, ...
                Camp, ...
                'InputType', opts.InputType, ...
                'DirSpecDoF', opts.DirSpecDoF, ...
                'Kp_min', opts.Kp_min, ...
                'pressure_units', opts.pressure_units, ...
                'DirConvention', opts.DirConvention, ...
                'wsa_toolbox_dir', opts.wsa_toolbox_dir, ...
                'IG_flag', true);

            directional_status = "success";

            if isfield(directional_info, 'directional_ncfile')
                directional_file_out = directional_info.directional_ncfile;
            else
                directional_file_out = string(directional_ncfile);
            end

        else
            directional_status = "skipped";
            directional_file_out = string(directional_ncfile);
        end

        results = [results; { ...
            string(Site), ...
            string(Camp), ...
            action, ...
            spectral_status, ...
            directional_status, ...
            message, ...
            spectral_file_out, ...
            directional_file_out}]; %#ok<AGROW>

        close all;

    catch ME

        msg = string(ME.message);

        if spectral_status == ""
            spectral_status = "error";
        end

        if directional_status == ""
            directional_status = "error";
        end

        results = [results; { ...
            string(Site), ...
            string(Camp), ...
            action, ...
            spectral_status, ...
            directional_status, ...
            msg, ...
            string(spectral_ncfile), ...
            string(directional_ncfile)}]; %#ok<AGROW>

        fprintf('Error procesando %s / %s:\n%s\n', Site, Camp, ME.message);

        if opts.stop_on_error
            rethrow(ME)
        end
    end
end

end