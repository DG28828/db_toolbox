function db_register_campaign(db_dir, Sitio, Camp, start_date, end_date, mounting_height, instrument_serial, status, raw_nc, clean_nc)

    metadata_file = fullfile(db_dir, 'metadata', 'campaigns.csv');

    % Normalizar entradas
    Sitio = string(Sitio);
    Camp  = string(Camp);

    if isa(start_date, 'datetime')
        start_date = string(start_date, 'yyyy-MM-dd');
    else
        start_date = string(start_date);
    end

    if isa(end_date, 'datetime')
        end_date = string(end_date, 'yyyy-MM-dd');
    else
        end_date = string(end_date);
    end

    mounting_height = string(mounting_height);

    instrument_serial = string(instrument_serial);
    status = string(status);

    raw_nc = string(raw_nc);
    if strlength(clean_nc) == 0
        clean_nc = "";
    end
    
    clean_nc = string(clean_nc);
    if strlength(clean_nc) == 0
        clean_nc = "";
    end

    % ID de campaña
    campaign_id = Sitio + "_" + Camp;

    new_row = table( ...
        campaign_id, ...
        Sitio, ...
        Camp, ...
        start_date, ...
        end_date, ...
        mounting_height, ...
        instrument_serial, ...
        status, ...
        raw_nc, ...
        clean_nc, ...
        string(datetime("now"), 'yyyy-MM-dd HH:mm:ss'), ...
        'VariableNames', { ...
        'id', ...
        'site', ...
        'campaign', ...
        'start_date', ...
        'end_date', ...
        'mounting_height', ...
        'instrument_serial', ...
        'status', ...
        'raw_nc_file', ...
        'clean_nc_file', ...
        'date_registered'} );

    if ~isfile(metadata_file)
        outdir = fileparts(metadata_file);
        if ~isempty(outdir) && ~exist(outdir, 'dir')
            mkdir(outdir);
        end
        writetable(new_row, metadata_file, 'Delimiter', ';');
        return
    end

    opts = detectImportOptions(metadata_file, 'Delimiter', ';');
    opts = setvartype(opts, opts.VariableNames, 'string');
    T = readtable(metadata_file, opts);


    if ~ismember("id", string(T.Properties.VariableNames))
        error('El archivo campaigns.csv existe pero no contiene la columna "id".');
    end

    idx = db_find_table_rows(T, "id", campaign_id);

    if isempty(idx)
        T = [T; new_row];
    else
        T(idx(1), :) = new_row;
        if numel(idx) > 1
            T(idx(2:end), :) = [];
        end
    end

    writetable(T, metadata_file, 'Delimiter', ';');
end