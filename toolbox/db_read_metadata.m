function T = db_read_metadata(db_dir)
%db_read_metadata Lee archivo metadata CSV usando delimitador ';'

campaign_metadata = fullfile(db_dir, 'metadata', 'campaigns.csv');

if ~isfile(campaign_metadata)
    error('db_read_metadata:FileNotFound', ...
        'No existe el archivo: %s', campaign_metadata);
end

opts = detectImportOptions(campaign_metadata, 'Delimiter', ';');
opts = setvartype(opts, opts.VariableNames, 'string');
T = readtable(campaign_metadata, opts);

end