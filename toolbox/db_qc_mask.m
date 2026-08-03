function [keep, result] = db_qc_mask(meta, QC, varargin)
%DB_QC_MASK Obtiene una máscara de bursts válidos mediante un registro QC.
%
% Entradas:
%   meta:
%       Tabla con site, campaign y burst_index.
%       Puede incluir time para verificar la correspondencia.
%
%   QC:
%       Estructura creada por db_build_spectral_qc_registry,
%       tabla QC.bursts o ruta al archivo MAT.
%
% Salidas:
%   keep:
%       true para bursts que deben conservarse.
%
%   result:
%       Tabla con matched, exclude y reason.

p = inputParser;

addRequired(p, 'meta', @istable);

addRequired(p, 'QC');

addParameter(p, 'Unmatched', 'keep', ...
    @(x) any(strcmpi(string(x), ["keep","exclude","error"])));

addParameter(p, 'TimeTolerance', seconds(1), ...
    @(x) isduration(x) && isscalar(x));

parse(p, meta, QC, varargin{:});
opts = p.Results;

%% Cargar registro

if ischar(QC) || isstring(QC)

    S = load(char(QC));

    if ~isfield(S, 'QC')
        error('El archivo indicado no contiene una variable llamada QC.');
    end

    QC = S.QC;
end

if isstruct(QC)

    if ~isfield(QC, 'bursts')
        error('La estructura QC no contiene el campo bursts.');
    end

    Q = QC.bursts;

elseif istable(QC)

    Q = QC;

else
    error('QC debe ser una estructura, una tabla o una ruta MAT.');
end

%% Verificar variables

requiredMeta = ["site","campaign","burst_index"];
requiredQC = ["site","campaign","burst_index","exclude"];

if ~all(ismember(requiredMeta, string(meta.Properties.VariableNames)))
    error('meta debe contener site, campaign y burst_index.');
end

if ~all(ismember(requiredQC, string(Q.Properties.VariableNames)))
    error(['La tabla QC debe contener site, campaign, burst_index ' ...
           'y exclude.']);
end

%% Crear claves

metaKey = ...
    string(meta.site) + "|" + ...
    string(meta.campaign) + "|" + ...
    string(double(meta.burst_index));

qcKey = ...
    string(Q.site) + "|" + ...
    string(Q.campaign) + "|" + ...
    string(double(Q.burst_index));

if numel(unique(qcKey)) ~= numel(qcKey)
    error('El registro QC contiene identificadores de burst duplicados.');
end

%% Buscar correspondencias

[matched, registryIndex] = ismember(metaKey, qcKey);

exclude = false(height(meta),1);
reason = repmat("not_in_registry", height(meta), 1);

idxMatched = find(matched);

exclude(idxMatched) = logical( ...
    Q.exclude(registryIndex(idxMatched)));

if ismember('reason', Q.Properties.VariableNames)
    reason(idxMatched) = string( ...
        Q.reason(registryIndex(idxMatched)));
else
    reason(idxMatched & exclude) = "excluded";
    reason(idxMatched & ~exclude) = "pass";
end

%% Verificar tiempo cuando esté disponible

hasMetaTime = ismember('time', meta.Properties.VariableNames);
hasQCTime   = ismember('time', Q.Properties.VariableNames);

if hasMetaTime && hasQCTime && any(matched)

    idx = find( ...
        matched & ...
        ~isnat(meta.time));

    qcTime = Q.time(registryIndex(idx));
    idxHasQCTime = ~isnat(qcTime);

    idx = idx(idxHasQCTime);
    qcTime = qcTime(idxHasQCTime);

    timeMismatch = ...
        abs(meta.time(idx) - qcTime) > opts.TimeTolerance;

    if any(timeMismatch)
        error(['El tiempo no coincide con el registro QC para %d bursts. ' ...
               'No se aplicó la máscara.'], ...
               sum(timeMismatch));
    end
end

%% Política para bursts no registrados

switch lower(string(opts.Unmatched))

    case "keep"
        exclude(~matched) = false;

    case "exclude"
        exclude(~matched) = true;
        reason(~matched) = "not_in_registry";

    case "error"
        if any(~matched)
            error('%d bursts no aparecen en el registro QC.', ...
                sum(~matched));
        end
end

keep = ~exclude;

result = table( ...
    matched, ...
    registryIndex, ...
    exclude, ...
    reason, ...
    'VariableNames', { ...
        'matched', ...
        'registry_index', ...
        'exclude', ...
        'reason'});

end