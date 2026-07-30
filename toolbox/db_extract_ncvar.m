function out = db_extract_ncvar(db_dir, file_type, var_name, varargin)
%db_extract_ncvar Extrae variables desde la base de datos netCDF procesada.
%
%   out = db_extract_ncvar(db_dir, file_type, var_name)
%   out = db_extract_ncvar(..., 'Sites', sites, 'Campaigns', camps)
%   out = db_extract_ncvar(..., 'Method', method, 'Band', band)
%   out = db_extract_ncvar(..., 'BurstRawMode', 'clean')
%
%   La función busca archivos dentro de:
%       db_dir/processed/Sitio/Campaña/
%
%   Tipos de archivo aceptados:
%       "processed", "base", "measured", "datos"  -> Sitio_Camp.nc
%       "spectral",  "espectral"                  -> Sitio_Camp_spectral.nc
%       "directional", "direccional"              -> Sitio_Camp_directional.nc
%
%   Ejemplos:
%       % Hm0 total de todos los sitios y campañas
%       D = db_extract_ncvar('C:\COPC_db', 'spectral', 'Hm0', 'Band', 'total');
%
%       % Espectro frecuencial no direccional de Cabo Blanco
%       D = db_extract_ncvar('C:\COPC_db', 'spectral', 'S', ...
%             'Sites', 'Cabo_Blanco');
%
%       % Dirección media por frecuencia usando Fourier
%       D = db_extract_ncvar('C:\COPC_db', 'directional', 'f_mean_dir', ...
%             'Method', 'Fourier', 'Sites', 'Cabo_Blanco');
%
%       % Parámetro direccional dentro de banda total
%       D = db_extract_ncvar('C:\COPC_db', 'directional', 'MeanDir', ...
%             'Method', 'MEM', 'Band', 'total');
%
%       % Variable del archivo base/procesado
%       D = db_extract_ncvar('C:\COPC_db', 'processed', 'pressure_proc', ...
%             'Site', 'Cabo_Blanco', 'Camp', '2025-04_2025-10');
%
%   Salida principal:
%       out.value       Variable concatenada en la dimensión burst, si aplica.
%       out.time        Tiempo concatenado por burst, si aplica.
%       out.site        Sitio asociado a cada burst.
%       out.campaign    Campaña asociada a cada burst.
%       out.table       Tabla para variables vectoriales por burst.
%       out.byCampaign  Struct con los datos por campaña.
%       out.records     Tabla resumen de archivos leídos/omitidos.
%
%   Nota:
%       Si la variable no depende de la dimensión "burst" (por ejemplo f,
%       theta o band_limits), no se concatena en out.value; se conserva en
%       out.byCampaign(k).value.
%
%       Las variables almacenadas en "burst_raw" pueden alinearse con las
%       ráfagas limpias usando:
%           'BurstRawMode', 'clean'
%       En ese modo se eliminan los registros donde is_bad_burst == 1 y se
%       verifica que el número resultante coincida con la variable time.
%       El valor predeterminado es 'raw', que conserva el comportamiento
%       anterior y deja la variable únicamente en out.byCampaign.

% -------------------------------------------------------------------------
% Entradas
% -------------------------------------------------------------------------
p = inputParser;
p.FunctionName = mfilename;

addRequired(p, 'db_dir',    @(x) ischar(x) || isstring(x));
addRequired(p, 'file_type', @(x) ischar(x) || isstring(x));
addRequired(p, 'var_name',  @(x) ischar(x) || isstring(x));

% Alias en inglés y español para que la función sea cómoda de usar.
addParameter(p, 'Sites',      string.empty(0,1), @local_is_text_list);
addParameter(p, 'Site',       string.empty(0,1), @local_is_text_list);
addParameter(p, 'Sitios',     string.empty(0,1), @local_is_text_list);
addParameter(p, 'Sitio',      string.empty(0,1), @local_is_text_list);

addParameter(p, 'Campaigns',  string.empty(0,1), @local_is_text_list);
addParameter(p, 'Campaign',   string.empty(0,1), @local_is_text_list);
addParameter(p, 'Camps',      string.empty(0,1), @local_is_text_list);
addParameter(p, 'Camp',       string.empty(0,1), @local_is_text_list);
addParameter(p, 'Campanas',   string.empty(0,1), @local_is_text_list);
addParameter(p, 'Campana',    string.empty(0,1), @local_is_text_list);

addParameter(p, 'Method',     'Fourier',         @(x) ischar(x) || isstring(x));
addParameter(p, 'Band',       '',                @(x) ischar(x) || isstring(x));
addParameter(p, 'Burst',        'all');
addParameter(p, 'BurstRawMode', 'raw',             @(x) ischar(x) || isstring(x));
addParameter(p, 'Concat',       true,              @(x) islogical(x) && isscalar(x));
addParameter(p, 'ReadTime',   true,              @(x) islogical(x) && isscalar(x));
addParameter(p, 'ReadCoords', true,              @(x) islogical(x) && isscalar(x));
addParameter(p, 'Strict',     false,             @(x) islogical(x) && isscalar(x));
addParameter(p, 'Verbose',    true,              @(x) islogical(x) && isscalar(x));
addParameter(p, 'TimeZone',   '',                @(x) ischar(x) || isstring(x));

parse(p, db_dir, file_type, var_name, varargin{:});
opts = p.Results;

db_dir    = char(string(opts.db_dir));
file_type = local_normalize_file_type(opts.file_type);
var_name  = string(opts.var_name);
method    = string(opts.Method);
band      = string(opts.Band);
timezone  = string(opts.TimeZone);

burst_raw_mode = lower(strtrim(string(opts.BurstRawMode)));
if ~isscalar(burst_raw_mode) || ~any(burst_raw_mode == ["raw", "clean"])
    error('BurstRawMode debe ser "raw" o "clean".');
end

sites = local_first_nonempty_text(opts.Sites, opts.Site, opts.Sitios, opts.Sitio);
camps = local_first_nonempty_text(opts.Campaigns, opts.Campaign, opts.Camps, ...
                                  opts.Camp, opts.Campanas, opts.Campana);

if ~isfolder(db_dir)
    error('El directorio de base de datos no existe: %s', db_dir);
end

processed_dir = fullfile(db_dir, 'processed');
if ~isfolder(processed_dir)
    error('No existe la carpeta processed: %s', processed_dir);
end

if isempty(sites)
    sites = local_list_subdirs(processed_dir);
end

if isempty(sites)
    warning('No se detectaron sitios dentro de: %s', processed_dir);
end

% -------------------------------------------------------------------------
% Inicializar salida
% -------------------------------------------------------------------------
out = struct();
out.db_dir      = string(db_dir);
out.file_type   = file_type;
out.requested_variable = var_name;
out.method      = method;
out.band        = band;
out.burst_raw_mode = burst_raw_mode;
out.variable    = local_resolve_var_path(file_type, var_name, method, band);
out.value       = [];
out.time        = NaT(0,1);
out.site        = strings(0,1);
out.campaign    = strings(0,1);
out.byCampaign  = struct('site', {}, 'campaign', {}, 'ncfile', {}, ...
                         'variable', {}, 'value', {}, 'time', {}, ...
                         'coords', {}, 'dimensions', {}, ...
                         'output_dimensions', {}, 'attributes', {});
out.table       = table();

rec_site     = strings(0,1);
rec_campaign = strings(0,1);
rec_file     = strings(0,1);
rec_variable = strings(0,1);
rec_status   = strings(0,1);
rec_message  = strings(0,1);
rec_size     = strings(0,1);
rec_burstdim = NaN(0,1);
rec_nburst   = NaN(0,1);

value_all = [];
can_concat = opts.Concat;
cat_dim_ref = [];

% -------------------------------------------------------------------------
% Recorrido de sitios y campañas
% -------------------------------------------------------------------------
for s = 1:numel(sites)

    site = sites(s);
    site_dir = fullfile(processed_dir, char(site));

    if ~isfolder(site_dir)
        msg = "No existe la carpeta del sitio.";
        [rec_site, rec_campaign, rec_file, rec_variable, rec_status, rec_message, rec_size, rec_burstdim, rec_nburst] = ...
            local_add_record(rec_site, rec_campaign, rec_file, rec_variable, rec_status, rec_message, rec_size, rec_burstdim, rec_nburst, ...
            site, "", "", out.variable, "missing_site", msg, "", NaN, NaN);
        if opts.Strict, error('%s Sitio: %s', msg, site); end
        if opts.Verbose, warning('%s Sitio: %s', msg, site); end
        continue
    end

    if isempty(camps)
        camps_site = local_list_subdirs(site_dir);
    else
        camps_site = camps;
    end

    for c = 1:numel(camps_site)

        camp = camps_site(c);
        camp_dir = fullfile(site_dir, char(camp));
        ncfile = local_build_ncfile(camp_dir, site, camp, file_type);
        var_path = out.variable;

        status = "ok";
        msg = "";
        data_size_txt = "";
        burst_dim_idx = NaN;
        nburst_var = NaN;

        if ~isfolder(camp_dir)
            status = "missing_campaign";
            msg = "No existe la carpeta de campaña.";
            local_handle_problem(opts, msg + " " + site + " / " + camp);
            [rec_site, rec_campaign, rec_file, rec_variable, rec_status, rec_message, rec_size, rec_burstdim, rec_nburst] = ...
                local_add_record(rec_site, rec_campaign, rec_file, rec_variable, rec_status, rec_message, rec_size, rec_burstdim, rec_nburst, ...
                site, camp, string(ncfile), var_path, status, msg, data_size_txt, burst_dim_idx, nburst_var);
            continue
        end

        if ~isfile(ncfile)
            status = "missing_file";
            msg = "No existe el archivo netCDF solicitado.";
            local_handle_problem(opts, msg + " " + string(ncfile));
            [rec_site, rec_campaign, rec_file, rec_variable, rec_status, rec_message, rec_size, rec_burstdim, rec_nburst] = ...
                local_add_record(rec_site, rec_campaign, rec_file, rec_variable, rec_status, rec_message, rec_size, rec_burstdim, rec_nburst, ...
                site, camp, string(ncfile), var_path, status, msg, data_size_txt, burst_dim_idx, nburst_var);
            continue
        end

        try
            info_var = ncinfo(ncfile, char(var_path));
        catch ME
            status = "missing_variable";
            msg = "No existe la variable indicada en el archivo.";
            local_handle_problem(opts, msg + " Variable: " + var_path + ". Archivo: " + string(ncfile));
            [rec_site, rec_campaign, rec_file, rec_variable, rec_status, rec_message, rec_size, rec_burstdim, rec_nburst] = ...
                local_add_record(rec_site, rec_campaign, rec_file, rec_variable, rec_status, rec_message, rec_size, rec_burstdim, rec_nburst, ...
                site, camp, string(ncfile), var_path, status, string(ME.message), data_size_txt, burst_dim_idx, nburst_var);
            continue
        end

        dim_names = string({info_var.Dimensions.Name});
        dim_lens  = [info_var.Dimensions.Length];

        burst_dim_idx_native = find(dim_names == "burst", 1);
        burst_raw_dim_idx    = find(dim_names == "burst_raw", 1);

        has_native_burst = ~isempty(burst_dim_idx_native);
        has_burst_raw    = ~isempty(burst_raw_dim_idx);
        align_burst_raw  = ~has_native_burst && has_burst_raw && ...
                           burst_raw_mode == "clean";

        % Dimensión efectiva usada para concatenar la salida.
        if has_native_burst
            burst_dim_idx = burst_dim_idx_native;
            has_burst = true;
        elseif align_burst_raw
            burst_dim_idx = burst_raw_dim_idx;
            has_burst = true;
        else
            burst_dim_idx = NaN;
            has_burst = false;
        end

        if has_burst
            nburst_var = dim_lens(burst_dim_idx);
        end

        try
            if align_burst_raw
                [data, nburst_selected] = local_read_clean_burst_raw_variable( ...
                    ncfile, var_path, info_var, opts.Burst, burst_raw_dim_idx);
            else
                [data, nburst_selected] = local_read_variable( ...
                    ncfile, var_path, info_var, opts.Burst, burst_dim_idx, timezone);
            end

            data_size_txt = string(mat2str(size(data)));

            if has_burst
                nburst_var = nburst_selected;
            end

            time = NaT(0,1);
            if opts.ReadTime && has_burst
                if local_is_time_var(var_path)
                    time = data(:);
                else
                    time = local_read_time(ncfile, opts.Burst, timezone);
                end

                if numel(time) ~= nburst_selected
                    error(['La variable alineada contiene %d ráfagas, pero time ' ...
                           'contiene %d para %s / %s.'], ...
                           nburst_selected, numel(time), site, camp);
                end
            end

            coords = struct();
            if opts.ReadCoords
                coords = local_read_coords(ncfile, file_type, var_path, info_var, method);
            end

            attrs = local_attributes_to_struct(info_var.Attributes);

            k = numel(out.byCampaign) + 1;
            out.byCampaign(k).site       = site;
            out.byCampaign(k).campaign   = camp;
            out.byCampaign(k).ncfile     = string(ncfile);
            out.byCampaign(k).variable   = var_path;
            out.byCampaign(k).value      = data;
            out.byCampaign(k).time       = time;
            out.byCampaign(k).coords     = coords;

            % Dimensiones originales del archivo.
            out.byCampaign(k).dimensions = table(dim_names(:), dim_lens(:), ...
                                                  'VariableNames', {'Name','Length'});

            % Dimensiones efectivas de los datos devueltos.
            output_dim_names = dim_names;
            output_dim_lens  = dim_lens;

            if has_burst
                output_dim_lens(burst_dim_idx) = nburst_selected;
                if align_burst_raw
                    output_dim_names(burst_dim_idx) = "burst";
                end
            end

            out.byCampaign(k).output_dimensions = ...
                table(output_dim_names(:), output_dim_lens(:), ...
                      'VariableNames', {'Name','Length'});

            out.byCampaign(k).attributes = attrs;

            % Concatenación automática en la dimensión burst.
            if has_burst && opts.Concat && can_concat
                if isempty(value_all)
                    value_all = data;
                    cat_dim_ref = burst_dim_idx;
                else
                    if burst_dim_idx ~= cat_dim_ref
                        can_concat = false;
                        msg = "No se concatenó: la dimensión burst no está en la misma posición en todos los archivos.";
                    else
                        try
                            value_all = cat(cat_dim_ref, value_all, data);
                        catch MEcat
                            can_concat = false;
                            msg = "No se concatenó: las dimensiones no-burst no coinciden. " + string(MEcat.message);
                        end
                    end
                end

                if ~isempty(time)
                    out.time = [out.time; time(:)]; %#ok<AGROW>
                    out.site = [out.site; repmat(site, numel(time), 1)]; %#ok<AGROW>
                    out.campaign = [out.campaign; repmat(camp, numel(time), 1)]; %#ok<AGROW>
                elseif ~isnan(nburst_var)
                    out.site = [out.site; repmat(site, nburst_var, 1)]; %#ok<AGROW>
                    out.campaign = [out.campaign; repmat(camp, nburst_var, 1)]; %#ok<AGROW>
                end
            end

        catch ME
            status = "read_error";
            msg = string(ME.message);
            local_handle_problem(opts, "Error leyendo " + site + " / " + camp + ": " + msg);
        end

        [rec_site, rec_campaign, rec_file, rec_variable, rec_status, rec_message, rec_size, rec_burstdim, rec_nburst] = ...
            local_add_record(rec_site, rec_campaign, rec_file, rec_variable, rec_status, rec_message, rec_size, rec_burstdim, rec_nburst, ...
            site, camp, string(ncfile), var_path, status, msg, data_size_txt, burst_dim_idx, nburst_var);
    end
end

% -------------------------------------------------------------------------
% Cierre de salida
% -------------------------------------------------------------------------
if opts.Concat && can_concat && ~isempty(value_all)
    out.value = value_all;
elseif opts.Concat && ~can_concat
    warning('No fue posible concatenar out.value. Revise out.byCampaign y out.records.');
end

out.records = table(rec_site, rec_campaign, rec_file, rec_variable, ...
                    rec_status, rec_message, rec_size, rec_burstdim, rec_nburst, ...
                    'VariableNames', {'site','campaign','ncfile','variable', ...
                                      'status','message','size','burst_dim','n_burst'});

% Tabla conveniente para parámetros escalares por burst.
try
    if ~isempty(out.value) && isvector(out.value) && numel(out.value) == numel(out.time)
        out.table = table(out.time(:), out.site(:), out.campaign(:), out.value(:), ...
                          'VariableNames', {'time','site','campaign','value'});
    end
catch
    out.table = table();
end

end

% =========================================================================
% Funciones auxiliares locales
% =========================================================================
function tf = local_is_text_list(x)
    tf = isempty(x) || ischar(x) || isstring(x) || iscellstr(x); %#ok<ISCLSTR>
end

function out = local_first_nonempty_text(varargin)
    out = string.empty(0,1);
    for i = 1:nargin
        x = local_to_string_list(varargin{i});
        if ~isempty(x)
            out = x;
            return
        end
    end
end

function x = local_to_string_list(x)
    if isempty(x)
        x = string.empty(0,1);
        return
    end
    if ischar(x)
        x = string({x});
    elseif iscell(x)
        x = string(x);
    else
        x = string(x);
    end
    x = strtrim(x(:));
    x = x(strlength(x) > 0);
end

function names = local_list_subdirs(parent_dir)
    d = dir(parent_dir);
    d = d([d.isdir]);
    names = string({d.name});
    names = names(~ismember(names, [".", ".."]));
    names = sort(names(:));
end

function file_type = local_normalize_file_type(file_type)
    ft = lower(strtrim(string(file_type)));
    switch ft
        case {"base", "processed", "procesado", "measured", "medido", "data", "datos", "nc"}
            file_type = "processed";
        case {"spectral", "espectral", "spec"}
            file_type = "spectral";
        case {"directional", "direccional", "dir"}
            file_type = "directional";
        otherwise
            error(['file_type no reconocido: %s. Use "processed", ', ...
                   '"spectral" o "directional".'], ft);
    end
end

function ncfile = local_build_ncfile(camp_dir, site, camp, file_type)
    base = char(site + "_" + camp);
    switch file_type
        case "processed"
            fname = [base, '.nc'];
        case "spectral"
            fname = [base, '_spectral.nc'];
        case "directional"
            fname = [base, '_directional.nc'];
    end
    ncfile = fullfile(camp_dir, fname);
end

function var_path = local_resolve_var_path(file_type, var_name, method, band)
    var_name = strtrim(string(var_name));
    method   = strtrim(string(method));
    band     = strtrim(string(band));

    if startsWith(var_name, "/")
        var_path = var_name;
        return
    end

    % Si el usuario pasa una ruta sin slash inicial, se normaliza.
    if contains(var_name, "/")
        var_path = "/" + var_name;
        return
    end

    root_vars = ["time", "Type"];

    switch file_type
        case "processed"
            var_path = var_name;

        case "spectral"
            if strlength(band) > 0 && ~any(var_name == root_vars)
                var_path = "/bands/" + band + "/" + var_name;
            else
                var_path = var_name;
            end

        case "directional"
            if any(var_name == root_vars)
                var_path = var_name;
            elseif strlength(band) > 0
                var_path = "/" + method + "/bands/" + band + "/" + var_name;
            else
                var_path = "/" + method + "/" + var_name;
            end
    end
end

function [data, nburst_selected] = local_read_variable(ncfile, var_path, info_var, burst, burst_dim_idx, timezone)
    dim_lens = [info_var.Dimensions.Length];
    has_burst = ~isempty(burst_dim_idx) && ~isnan(burst_dim_idx);

    if ~has_burst || local_is_all_burst(burst)
        data = ncread(ncfile, char(var_path));
        if has_burst
            nburst_selected = dim_lens(burst_dim_idx);
        else
            nburst_selected = NaN;
        end
    else
        burst_idx = local_validate_burst_index(burst, dim_lens(burst_dim_idx));
        pieces = cell(numel(burst_idx), 1);

        for i = 1:numel(burst_idx)
            start = ones(1, numel(dim_lens));
            count = dim_lens;
            start(burst_dim_idx) = burst_idx(i);
            count(burst_dim_idx) = 1;
            pieces{i} = ncread(ncfile, char(var_path), start, count);
        end

        data = pieces{1};
        for i = 2:numel(pieces)
            data = cat(burst_dim_idx, data, pieces{i});
        end
        nburst_selected = numel(burst_idx);
    end

    if local_is_time_var(var_path)
        data = local_posix2datetime(data, timezone);
    end
end


function [data, nburst_selected] = local_read_clean_burst_raw_variable( ...
    ncfile, var_path, info_var, burst, burst_raw_dim_idx)
% Lee una variable definida en burst_raw y la alinea con burst mediante
% is_bad_burst. Los índices indicados en Burst se interpretan después de
% aplicar la limpieza, es decir, sobre la dimensión burst resultante.

    if isempty(burst_raw_dim_idx) || isnan(burst_raw_dim_idx)
        error('La variable no contiene la dimensión burst_raw.');
    end

    dim_lens = [info_var.Dimensions.Length];
    nburst_raw = dim_lens(burst_raw_dim_idx);

    data_raw = ncread(ncfile, char(var_path));

    try
        is_bad_burst = ncread(ncfile, 'is_bad_burst');
    catch ME
        error('No se pudo leer is_bad_burst para alinear %s: %s', ...
              var_path, ME.message);
    end

    is_bad_burst = double(is_bad_burst(:));

    if numel(is_bad_burst) ~= nburst_raw
        error(['La longitud de is_bad_burst (%d) no coincide con la dimensión ' ...
               'burst_raw de %s (%d).'], ...
               numel(is_bad_burst), var_path, nburst_raw);
    end

    invalid_flag = ~isfinite(is_bad_burst) | ...
                   ~ismember(is_bad_burst, [0 1]);

    if any(invalid_flag)
        error('is_bad_burst contiene %d valores distintos de 0 o 1.', ...
              sum(invalid_flag));
    end

    clean_raw_idx = find(is_bad_burst == 0);
    data = local_select_dimension(data_raw, burst_raw_dim_idx, clean_raw_idx);

    % Verificación estructural: la cantidad limpia debe coincidir con time,
    % que está definida sobre la dimensión burst.
    try
        time_clean = ncread(ncfile, 'time');
    catch ME
        error('No se pudo leer time para verificar la alineación: %s', ...
              ME.message);
    end

    if numel(time_clean) ~= numel(clean_raw_idx)
        error(['Después de aplicar is_bad_burst quedan %d ráfagas, pero time ' ...
               'contiene %d. No se puede garantizar la correspondencia.'], ...
               numel(clean_raw_idx), numel(time_clean));
    end

    if local_is_all_burst(burst)
        nburst_selected = numel(clean_raw_idx);
    else
        burst_idx = local_validate_burst_index(burst, numel(clean_raw_idx));
        data = local_select_dimension(data, burst_raw_dim_idx, burst_idx);
        nburst_selected = numel(burst_idx);
    end
end

function data = local_select_dimension(data, dim_idx, idx)
% Selecciona índices arbitrarios a lo largo de una dimensión sin alterar
% el orden de las demás dimensiones.

    nsubs = max(ndims(data), dim_idx);
    subs = repmat({':'}, 1, nsubs);
    subs{dim_idx} = idx;
    data = data(subs{:});
end

function tf = local_is_all_burst(burst)
    tf = isempty(burst) || ...
         (ischar(burst) && strcmpi(burst, 'all')) || ...
         (isstring(burst) && isscalar(burst) && lower(strtrim(burst)) == "all");
end

function burst_idx = local_validate_burst_index(burst, nmax)
    if ~(isnumeric(burst) && isvector(burst) && all(isfinite(burst)) && ...
         all(burst == floor(burst)) && all(burst > 0))
        error('Burst debe ser "all" o un índice/vector de índices enteros positivos.');
    end
    burst_idx = burst(:).';
    if any(burst_idx > nmax)
        error('Al menos un índice Burst excede el número de bursts disponibles (%d).', nmax);
    end
end

function tf = local_is_time_var(var_path)
    parts = split(string(var_path), "/");
    parts = parts(strlength(parts) > 0);
    tf = ~isempty(parts) && lower(parts(end)) == "time";
end

function time = local_read_time(ncfile, burst, timezone)
    try
        t = ncread(ncfile, 'time');
    catch
        time = NaT(0,1);
        return
    end

    if ~local_is_all_burst(burst)
        idx = local_validate_burst_index(burst, numel(t));
        t = t(idx);
    end

    time = local_posix2datetime(t, timezone);
    time = time(:);
end

function dt = local_posix2datetime(t, timezone)
    if isa(t, 'datetime')
        dt = t;
        return
    end

    if isnumeric(t)
        dt = datetime(t, 'ConvertFrom', 'posixtime', 'TimeZone', 'UTC');
        if strlength(string(timezone)) == 0
            dt.TimeZone = '';
        else
            dt.TimeZone = char(timezone);
        end
    else
        dt = t;
    end
end

function coords = local_read_coords(ncfile, file_type, var_path, info_var, method)
    coords = struct();
    dim_names = lower(string({info_var.Dimensions.Name}));

    has_freq = any(contains(dim_names, "frequency"));
    has_dir  = any(contains(dim_names, "direction"));

    if ~(has_freq || has_dir)
        return
    end

    switch file_type
        case "spectral"
            if has_freq
                coords.f = local_read_coord_if_exists(ncfile, "f");
            end

        case "directional"
            group = local_directional_group_from_path(var_path, method);
            if has_freq
                coords.f = local_read_coord_if_exists(ncfile, group + "/f");
            end
            if has_dir
                coords.theta = local_read_coord_if_exists(ncfile, group + "/theta");
            end
    end
end

function group = local_directional_group_from_path(var_path, method)
    parts = split(string(var_path), "/");
    parts = parts(strlength(parts) > 0);
    if ~isempty(parts) && any(parts(1) == ["Fourier", "MEM"])
        group = "/" + parts(1);
    else
        group = "/" + string(method);
    end
end

function x = local_read_coord_if_exists(ncfile, coord_path)
    try
        x = ncread(ncfile, char(coord_path));
    catch
        x = [];
    end
end

function attrs = local_attributes_to_struct(ncattrs)
    attrs = struct();
    for i = 1:numel(ncattrs)
        name = matlab.lang.makeValidName(ncattrs(i).Name);
        attrs.(name) = ncattrs(i).Value;
    end
end

function local_handle_problem(opts, msg)
    if opts.Strict
        error('%s', msg);
    elseif opts.Verbose
        warning('%s', msg);
    end
end

function [rec_site, rec_campaign, rec_file, rec_variable, rec_status, rec_message, rec_size, rec_burstdim, rec_nburst] = ...
    local_add_record(rec_site, rec_campaign, rec_file, rec_variable, rec_status, rec_message, rec_size, rec_burstdim, rec_nburst, ...
                     site, campaign, ncfile, variable, status, message, size_txt, burst_dim, nburst)

    if isempty(burst_dim)
        burst_dim = NaN;
    end
    if isempty(nburst)
        nburst = NaN;
    end

    rec_site(end+1,1)     = string(site); %#ok<AGROW>
    rec_campaign(end+1,1) = string(campaign); %#ok<AGROW>
    rec_file(end+1,1)     = string(ncfile); %#ok<AGROW>
    rec_variable(end+1,1) = string(variable); %#ok<AGROW>
    rec_status(end+1,1)   = string(status); %#ok<AGROW>
    rec_message(end+1,1)  = string(message); %#ok<AGROW>
    rec_size(end+1,1)     = string(size_txt); %#ok<AGROW>
    rec_burstdim(end+1,1) = double(burst_dim); %#ok<AGROW>
    rec_nburst(end+1,1)   = double(nburst); %#ok<AGROW>
end

