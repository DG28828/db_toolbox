function time_datetime = db_posix2datetime(time_posix)
% Convierte segundos POSIX a datetime MATLAB si es posible.
% Si no, devuelve NaT.

    time_datetime = NaT(size(time_posix), 'TimeZone', 'UTC');

    % Caso: POSIX numérico
    try
        if isnumeric(time_posix)
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
            time_datetime = time_posix;
            if isempty(time_posix.TimeZone)
                time_posix.TimeZone = 'UTC';
            end
            return
        end
    catch
    end
end