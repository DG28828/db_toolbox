function safe_ncwrite(ncfile, varname, data)

maxAttempts = 8;

for attempt = 1:maxAttempts

    try
        ncwrite(ncfile, varname, data);
        return

    catch ME

        fprintf(['[NETCDF] Falló escritura de datos "%s". ', ...
                 'Intento %d de %d.\n'], ...
                 varname, attempt, maxAttempts);

        if attempt == maxAttempts
            newME = MException( ...
                'WSA:NetCDFDataWriteFailed', ...
                ['No fue posible escribir "%s" después de %d ', ...
                 'intentos en:\n%s\n\nCausa original:\n%s'], ...
                varname, ...
                maxAttempts, ...
                ncfile, ...
                getReport(ME, 'extended', 'hyperlinks', 'off'));

            newME = addCause(newME, ME);
            throwAsCaller(newME)
        end

        pause(0.20 * attempt);
    end
end

end