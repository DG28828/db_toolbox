function db_check_required_functions(func_list, toolbox_name, opt_name)

    missing = func_list(~cellfun(@(f) exist(f,'file') == 2, func_list));

    if ~isempty(missing)
        msg = sprintf(['No se encontraron funciones requeridas del toolbox %s en el path de MATLAB.\n' ...
                       'Funciones faltantes: %s\n' ...
                       'Agregue el path manualmente con addpath(genpath(...)) o proporcione %s.'], ...
                       toolbox_name, strjoin(missing, ', '), opt_name);

        error('db_proc_camp:MissingDependencies', '%s', msg);
    end
end