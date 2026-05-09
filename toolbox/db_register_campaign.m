function db_register_campaign(db_dir, Sitio, Camp, start_date, end_date, raw_bursts, clean_bursts, mounting_height, instrument_serial, head_serial, clean_status, proc_status, raw_nc, proc_nc)

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

    if isempty(raw_bursts)
        raw_bursts = "";
    else
        raw_bursts = string(raw_bursts);
    end

    if isempty(clean_bursts)
        clean_bursts = "";
    else
        clean_bursts = string(clean_bursts);
    end
    
    if isempty(mounting_height)
        mounting_height = "";
    else
        mounting_height = string(mounting_height);
    end

    instrument_serial = string(instrument_serial);
    head_serial = string(head_serial);
    clean_status = string(clean_status);
    proc_status = string(proc_status);

    raw_nc = string(raw_nc);
    if strlength(proc_nc) == 0
        proc_nc = "";
    end
    
    proc_nc = string(proc_nc);
    if strlength(proc_nc) == 0
        proc_nc = "";
    end

    % ID de campaña
    campaign_id = Sitio + "_" + Camp;

    new_row = table( ...
        campaign_id, ...
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
        proc_nc, ...
        string(datetime("now"), 'yyyy-MM-dd HH:mm:ss'), ...
        'VariableNames', { ...
        'id', ...
        'site', ...
        'campaign', ...
        'start_date', ...
        'end_date', ...
        'raw_bursts', ...
        'clean_bursts', ...
        'mounting_height', ...
        'instrument_serial', ...
        'head_serial', ...
        'cleaning_status', ...
        'processing_status', ...
        'raw_nc_file', ...
        'proc_nc_file', ...
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