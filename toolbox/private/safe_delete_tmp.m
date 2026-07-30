function safe_delete_tmp(filename)

if ~isfile(filename)
    return
end

try
    delete(filename);
catch
    % No ocultar el error original si falla la limpieza.
end

end