function idx = db_find_table_rows(T, column_name, value)
%db_find_table_rows Busca filas de una tabla donde una columna tenga cierto valor.
%
%   idx = db_find_table_rows(T, column_name, value)
%
%   Entradas:
%       T           - tabla MATLAB
%       column_name - nombre de la columna a consultar
%       value       - valor a buscar
%
%   Salida:
%       idx         - índices de filas que coinciden
%
%   Notas:
%       - La comparación se hace convirtiendo a string para mayor robustez.
%       - Permite buscar en columnas como id, site, status, campaign, etc.

    arguments
        T table
        column_name {mustBeTextScalar}
        value
    end

    column_name = string(column_name);
    value = string(value);

    varNames = string(T.Properties.VariableNames);

    if ~ismember(column_name, varNames)
        error('db_find_table_rows:InvalidColumn', ...
            'La columna "%s" no existe en la tabla.', column_name);
    end

    col = T.(column_name);

    % Convertir a string para hacer comparación homogénea
    if ~isa(col, 'string')
        col = string(col);
    end

    idx = find(col == value);
end