function txt_file = db_write_ncdisp_txt(ncfile)
%db_write_ncdisp_txt - Guarda la salida de ncdisp en un archivo .txt.
%
%   txt_file = db_write_ncdisp_txt(ncfile)
%
%   Genera un archivo de texto en el mismo directorio del NetCDF con el
%   contenido mostrado por ncdisp.

    if ~isfile(ncfile)
        txt_file = "";
        return
    end

    [nc_dir, nc_name, ~] = fileparts(ncfile);
    txt_file = fullfile(nc_dir, [nc_name, '_ncdisp.txt']);

    nc_text = evalc('ncdisp(ncfile)');

    fid = fopen(txt_file, 'w');

    if fid == -1
        warning('db_write_ncdisp_txt:FileOpenError', ...
            'No se pudo crear el archivo ncdisp: %s', txt_file);
        txt_file = "";
        return
    end

    fprintf(fid, '%s', nc_text);
    fclose(fid);

    fprintf('\nArchivo ncdisp generado:\n%s\n', txt_file);

end