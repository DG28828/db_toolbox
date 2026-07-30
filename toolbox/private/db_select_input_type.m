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

if instrument_type == "AQUADOPP"
    ast_available(:) = false;
end

%% Calidad del AST

ast_bad = false(nBursts,1);

if isfield(burst_data.processed, 'ast_bad_detects_percentage')

    bad_pct = burst_data.processed.ast_bad_detects_percentage;

    if size(bad_pct,1) >= 1 && size(bad_pct,2) == nBursts

        % Si el porcentaje no existe, no se considera el AST
        % suficientemente verificado para el modo optimum.
        ast_bad = ~isfinite(bad_pct(1,:)).' | bad_pct(1,:).' > 10;
    end
else
    ast_bad(:) = true;
end

%% Tilt mapeado desde burst_raw hasta burst limpio

bad_tilt = read_clean_burst_flag(proc_ncfile, 'bad_tilt_flag', nBursts);

%% Selección

requested_type = lower(string(InputType));

switch requested_type

    case "optimum"

        % La fuente segura por defecto es presión.
        Type = repmat("pressure", nBursts, 1);

        if instrument_type == "AWAC"

            use_ast = ast_available & ~ast_bad & ~bad_tilt;

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
selection_info.bad_tilt = bad_tilt;

end