function [Type, Type_IG, selection_info] = db_select_input_type(proc_ncfile, burst_data, InputType, IG_flag)

instrument_type = upper(string(ncreadatt(proc_ncfile, '/', 'instrument_type')));

pressure = burst_data.processed.pressure;
ast = burst_data.processed.ast;

nBursts = size(pressure, 2);

%% Disponibilidad por burst

pressure_available = any(isfinite(pressure), 1).';

% Se utiliza el primer canal AST porque actualmente ese es el que
% se introduce en wsa_spectrum y wsa_dirspectrum.
ast1 = squeeze(ast(:,1,:));

if nBursts == 1
    ast1 = ast1(:);
end

ast_available = any(isfinite(ast1), 1).';

if instrument_type == "AQUADOPP" || instrument_type == "RBR"
    ast_available(:) = false;
end

%% Calidad del AST

ast_bad = false(nBursts,1);

if isfield(burst_data.processed, 'ast_bad_detects_percentage')

    bad_detects_idx = burst_data.processed.ast_bad_detects_percentage;

    if size(bad_detects_idx,1) >= 1 && size(bad_detects_idx,2) == nBursts

        % Si el porcentaje no existe, no se considera el AST
        % suficientemente verificado para el modo optimum.
        ast_bad = ~isfinite(bad_detects_idx(1,:)).' | bad_detects_idx(1,:).' > 10;
    end
else
    ast_bad(:) = true;
end

%% Tilt mapeado desde burst_raw hasta burst limpio
if instrument_type == "AWAC"
    bad_ast_tilt_10_idx = read_clean_burst_flag(proc_ncfile, 'warning_tilt_flag_10', nBursts);
end
%% Selección

requested_type = lower(string(InputType));

switch requested_type

    case "optimum"

        % Por defecto usar presión.
        Type = repmat("pressure", nBursts, 1);

        if instrument_type == "AWAC"

            use_ast = ast_available & ~ast_bad & ~bad_ast_tilt_10_idx;

            Type(use_ast) = "ast";
        end

    case "ast"

        if instrument_type ~= "AWAC"
            error('InputType="ast" no es válido para un archivo de %s. El instrumento no dispone de AST.', instrument_type);
        end

        if any(~ast_available)
            bad_idx = find(~ast_available);
            error('Se solicitó InputType="ast", pero el AST no está disponible en los bursts: %s', mat2str(bad_idx(:).'));
        end

        Type = repmat("ast", nBursts, 1);

    case "pressure"
        Type = repmat("pressure", nBursts, 1);

    otherwise
        error('InputType no reconocido: %s', InputType);
end

%% Validación de presión

pressure_required = Type == "pressure";

if any(pressure_required & ~pressure_available)

    bad_idx = find(pressure_required & ~pressure_available);

    error('No existen datos válidos de presión para los bursts: %s', mat2str(bad_idx(:).'));
end

%% Tipo para IG

% Por ahora se conserva la misma selección.
% Queda separado para implementar después una selección IG específica.
if IG_flag
    Type_IG = Type;
else
    Type_IG = strings(0,1);
end

selection_info.instrument_type = instrument_type;
selection_info.ast_available = ast_available;
selection_info.pressure_available = pressure_available;
selection_info.ast_bad = ast_bad;
if instrument_type == "AWAC"
    selection_info.ast_bad_tilt = bad_ast_tilt_10_idx;
end

end

function flag_clean = read_clean_burst_flag(ncfile, varname, nBursts)
% Brinda los indices respecto a la dimensión clean de una variable definida
% en dimensión raw.

flag_raw = logical(ncread(ncfile, varname));
flag_raw = flag_raw(:);

is_bad_burst = logical(ncread(ncfile, 'is_bad_burst'));

is_bad_burst = is_bad_burst(:);

if numel(flag_raw) ~= numel(is_bad_burst)
    error('%s contiene %d valores, pero is_bad_burst contiene %d.', varname, numel(flag_raw), numel(is_bad_burst));
end

good_raw_idx = find(~is_bad_burst);

if numel(good_raw_idx) ~= nBursts
    error('La máscara is_bad_burst indica %d bursts válidos, pero el archivo procesado contiene %d bursts.', numel(good_raw_idx), nBursts);
end

flag_clean = flag_raw(good_raw_idx);

end