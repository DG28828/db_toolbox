function time_datetime = db_posix2datetime(time_posix)
% Convierte segundos POSIX a datetime MATLAB si es posible.
% Si no, devuelve NaT.

    time_datetime = NaT;

    % Caso: POSIX numérico
    try
        if isnumeric(time_posix) && isscalar(time_posix)
            time_datetime = datetime(time_posix, ...
                'ConvertFrom','posixtime', ...
                'TimeZone','UTC');
            return
        end
    catch
    end

    % Caso: si por alguna razón ya viene como datetime
    try
        if isa(time_posix,'datetime')
            if isempty(time_posix.TimeZone)
                time_posix.TimeZone = 'UTC';
            end
            time_datetime = time_posix;
            return
        end
    catch
    end
end