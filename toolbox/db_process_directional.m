function info = db_process_directional(db_dir, Sitio, Camp, opts)

%% Manejo de entradas
arguments
    db_dir char
    Sitio char;
    Camp char;
    opts.InputType char = 'optimum';  % 'optimum', 'ast', 'pressure'  
    opts.DirSpecDoF double = 64;
    opts.IGDirSpecDoF double = 8;
    opts.Ntheta double = 180;
    opts.Kp_min double = 0.05;
    opts.pressure_units char = 'dba';
    opts.DirConvention char = 'nautic_from';
    opts.wsa_toolbox_dir char = ''
    opts.IG_flag = false;
    opts.IG_export_fmax (1,1) double {mustBePositive} = 0.1;
end

%% Verificaciones iniciales

if ~isfolder(db_dir)
    error('El directorio de base de datos no existe: %s', db_dir);
end

%% Path a funciones

% Toolbox WSA
if ~isempty(strtrim(opts.wsa_toolbox_dir))
    if ~isfolder(opts.wsa_toolbox_dir)
        error('El directorio indicado para wsa_toolbox_dir no existe: %s', ...
            opts.wsa_toolbox_dir);
    end
    addpath(genpath(opts.wsa_toolbox_dir))
end

%% Verificación de dependencias requeridas

% Funciones mínimas requeridas del toolbox WSA
req_wsa = {
    'wsa_dirspectrum'
    'wsa_directional_parameters'
    'wsa_cartto2nautfrom'
    'wsa_nc_create_var'
    'wsa_datetime2posix'
    };

% Verificar existencia de funciones
db_check_required_functions(req_wsa, 'WSA', 'opts.wsa_toolbox_dir');


%% Crear log file

log_dir = fullfile(db_dir, 'logs', 'processing_runs', Sitio, Camp);         %Directorio de los logs para procesamiento: logs/processing_runs/Sitio/Camp
if ~exist(log_dir, 'dir')                                                   %Crea el directorio si no existe
    mkdir(log_dir);
end
log_file = fullfile(log_dir, ['log_', Sitio, '_', Camp, '_proc_at_', ...    %Nombre del archivo log a guardar log_Sitio_Camp_proc_at_fecha.txt
            char(string(datetime('now'), 'yyyy-MM-dd_HHmmss')), '.txt']);
info.log_file = string(log_file);
diary(log_file);                                                            %Comenzar a registrar archivo log.

%Encabezado del archivo log
fprintf('\n========================================================================================================================\n');
fprintf('Inicio de procesamiento direccional: %s\n', char(string(datetime('now'), 'yyyy-MM-dd_HHmmss')));
fprintf('Sitio   : %s\n', Sitio);
fprintf('Campaña : %s\n', Camp);
fprintf('========================================================================================================================\n');

try


%% Ruta de archivo netCDF y verificaciones

processed_dir = fullfile(db_dir, 'processed', Sitio, Camp);
proc_ncfile = fullfile(processed_dir, [Sitio, '_', Camp, '.nc']);

%Verificar existencia del archivo
if ~isfile(proc_ncfile)
    error('El archivo %s no existe', proc_ncfile);
end

%Verificar que el archivo indique que se encuentra preprocesado
is_preprocessed = logical(ncreadatt(proc_ncfile, '/', 'preprocessing_status'));
if ~is_preprocessed
    error('El archivo %s no se encuentra preprocesado', proc_ncfile);
end

%% Leer datos de la campaña del archivo netCDF

%Extraer datos de la campaña
burst_data = db_read_burst_principal(proc_ncfile, 'all', 'IG', true);

%% Definir tipo de datos de entrada a utilizar según InputType

nBursts = size(burst_data.processed.ast, 3);

switch lower(opts.InputType)
    case 'optimum'
        
        %Inicializar tipos AST por defecto
        Type = repmat("ast", nBursts, 1);

        %Cambiar InputTypes en los que AST da problemas según criterios:

        %   1) Porcentaje de bad detects mayor al 10 % (ast_bad_detects_percentage > 10 %)
        bad_detects_idx = burst_data.processed.ast_bad_detects_percentage > 10;
        Type(bad_detects_idx(1, :)) = "pressure";

        %   2) Tilt mayor a 10° (bad_tilt_flag)
        bad_tilt_flag_raw = ncread(proc_ncfile, 'bad_tilt_flag');  %Esta bandera esta respecto a burst_raw
        burst_counter = burst_data.general.burst_counter;
        bad_tilt_idx = logical(bad_tilt_flag_raw(burst_counter));
        Type(bad_tilt_idx) = "pressure";

    case 'ast'
        Type = repmat("ast", nBursts, 1);

    case 'pressure'
        Type = repmat("pressure", nBursts, 1);

    otherwise
        error('InputType no reconocido: %s', opts.InputType);
end

%% Ciclo principal

%Variables preliminares
ast_mean = burst_data.general.ast_mean;
mounting_height = burst_data.general.mounting_height;
z_p = -(ast_mean);
h   = ast_mean + mounting_height;
z_v = burst_data.general.cell_position - ast_mean;
fs = burst_data.general.fs;


for b = 1:nBursts

    % Extraer datos del burst
    P    = burst_data.processed.pressure(:, b);
    AST1 = burst_data.processed.ast(:, 1, b);
    U    = burst_data.processed.velocity_enu(:, 1, b);
    V    = burst_data.processed.velocity_enu(:, 2, b);

    if opts.IG_flag
        P_ig = burst_data.processed.pressure_ig(:, b);
        AST1_ig = burst_data.processed.ast_ig(:, 1, b); 
        U_ig    = burst_data.processed.velocity_enu_ig(:, 1, b);
        V_ig    = burst_data.processed.velocity_enu_ig(:, 2, b);
    end

    burst_results(b).Type = Type(b);

    switch Type(b)
        case "ast"
            fprintf('\nCalculando espectro direccional basado en AST para burst %d\n', b);
            [out_dirspectrum, info_dirspectrum] = wsa_dirspectrum( ...
                detrend(AST1), ...
                U, ...
                V, ...
                fs, ...
                'suv', ...
                'DoF', opts.DirSpecDoF, ...
                'Ntheta', opts.Ntheta, ...
                'z_v', z_v(b), ...
                'h', h(b));

            % if opts.IG_flag
            %     fprintf('\nCalculando espectro direccional IG basado en AST para burst %d\n', b);
            %     [out_IG_dirspectrum, info_IG_dirspectrum] = wsa_dirspectrum( ...
            %         detrend(AST1_ig), ...
            %         U_ig, ...
            %         V_ig, ...
            %         fs, ...
            %         'suv', ...
            %         'DoF', opts.IGDirSpecDoF, ...
            %         'Ntheta', opts.Ntheta, ...
            %         'z_v', z_v(b), ...
            %         'h', h(b), ...
            %         'FrequencyRange', [0 opts.IG_export_fmax]); 
            % end

        case "pressure"
            fprintf('\nCalculando espectro direccional basado en Presión para burst %d\n', b);
            [out_dirspectrum, info_dirspectrum] = wsa_dirspectrum( ...
                P, ...
                U, ...
                V, ...
                fs, ...
                'puv', ...
                'DoF', opts.DirSpecDoF, ...
                'Ntheta', opts.Ntheta, ...
                'un', opts.pressure_units, ...
                'z_p', z_p(b), ...
                'z_v', z_v(b), ...
                'h', h(b), ...
                'Kp_min', opts.Kp_min);

            % if opts.IG_flag
            % fprintf('\nCalculando espectro direccional IG basado en Presión para burst %d\n', b);
            %     [out_IG_dirspectrum, info_IG_dirspectrum] = wsa_dirspectrum( ...
            %         P_ig, ...
            %         U_ig, ...
            %         V_ig, ...
            %         fs, ...
            %         'puv', ...
            %         'DoF', opts.IGDirSpecDoF, ...
            %         'Ntheta', opts.Ntheta, ...
            %         'un', opts.pressure_units, ...
            %         'z_p', z_p(b), ...
            %         'z_v', z_v(b), ...
            %         'h', h(b), ...
            %         'Kp_min', opts.Kp_min, ...
            %         'FrequencyRange', [0 opts.IG_export_fmax]); 
            % end

        otherwise
            error('Tipo de entrada no reconocido para burst %d: %s', b, Type(b));
    end

    if opts.IG_flag
    fprintf('\nCalculando espectro direccional IG basado en Presión para burst %d\n', b);
        [out_IG_dirspectrum, info_IG_dirspectrum] = wsa_dirspectrum( ...
            P_ig, ...
            U_ig, ...
            V_ig, ...
            fs, ...
            'puv', ...
            'DoF', opts.IGDirSpecDoF, ...
            'Ntheta', opts.Ntheta, ...
            'un', opts.pressure_units, ...
            'z_p', z_p(b), ...
            'z_v', z_v(b), ...
            'h', h(b), ...
            'Kp_min', opts.Kp_min, ...
            'FrequencyRange', [0 opts.IG_export_fmax]); 
    end

    % Parámetros direccionales
    fourier_dir_parameters = wsa_directional_parameters(out_dirspectrum.Fourier);
    if opts.IG_flag
        IG_fourier_dir_parameters = wsa_directional_parameters(out_IG_dirspectrum.Fourier, ...
                                                                'IncludeDefaultBands', false);
    end

    mem_dir_parameters = wsa_directional_parameters( ...
                            out_dirspectrum.MEM.f, ...
                            out_dirspectrum.MEM.S, ...
                            out_dirspectrum.MEM.coeffs_mem.a1, ...
                            out_dirspectrum.MEM.coeffs_mem.b1, ...
                            'a2', out_dirspectrum.MEM.coeffs_mem.a2, ...
                            'b2', out_dirspectrum.MEM.coeffs_mem.b2);
    if opts.IG_flag
        IG_mem_dir_parameters = wsa_directional_parameters( ...
                                out_IG_dirspectrum.MEM.f, ...
                                out_IG_dirspectrum.MEM.S, ...
                                out_IG_dirspectrum.MEM.coeffs_mem.a1, ...
                                out_IG_dirspectrum.MEM.coeffs_mem.b1, ...
                                'a2', out_IG_dirspectrum.MEM.coeffs_mem.a2, ...
                                'b2', out_IG_dirspectrum.MEM.coeffs_mem.b2, ...
                                'IncludeDefaultBands', false);
    end


    %== Convertir E a single inmediatamente, para optimizar memoria ==%
    out_dirspectrum.Fourier.E = single(out_dirspectrum.Fourier.E);
    out_dirspectrum.MEM.E = single(out_dirspectrum.MEM.E);
    if opts.IG_flag
        out_IG_dirspectrum.Fourier.E = single(out_IG_dirspectrum.Fourier.E);
        out_IG_dirspectrum.MEM.E = single(out_IG_dirspectrum.MEM.E);
    end
    %=======================================================================================================%



    % Coeficientes de Fourier provenientes de funciones direccionales
    input_coeffs = out_dirspectrum.Fourier.coeffs;
    mem_reconstructed_coeffs = out_dirspectrum.MEM.coeffs_mem;
    mem_residual_coeffs = out_dirspectrum.MEM.coeffs_residual;
    if opts.IG_flag
        IG_input_coeffs = out_IG_dirspectrum.Fourier.coeffs;
        IG_mem_reconstructed_coeffs = out_IG_dirspectrum.MEM.coeffs_mem;
        IG_mem_residual_coeffs = out_IG_dirspectrum.MEM.coeffs_residual;
    end

    % Transformar los coeficientes a la convención indicada.
    switch lower(opts.DirConvention)
        case {'nautic_from', 'nautica_desde'}
            input_coeffs = convert_coeffs_cart_to_naut_from(input_coeffs);
            mem_reconstructed_coeffs = convert_coeffs_cart_to_naut_from(mem_reconstructed_coeffs);
            mem_residual_coeffs = convert_coeffs_cart_to_naut_from(mem_residual_coeffs);
            if opts.IG_flag
                IG_input_coeffs = convert_coeffs_cart_to_naut_from(IG_input_coeffs);
                IG_mem_reconstructed_coeffs = convert_coeffs_cart_to_naut_from(IG_mem_reconstructed_coeffs);
                IG_mem_residual_coeffs = convert_coeffs_cart_to_naut_from(IG_mem_residual_coeffs); 
            end
    
        case {'cartesian_to', 'cartesiana_desde'}
            % No se requiere transformación.
    end

    % Conversión de direcciones
    switch lower(opts.DirConvention)
        case {'nautic_from', 'nautica_desde'}
            out_dirspectrum = wsa_cartto2nautfrom(out_dirspectrum);
            fourier_dir_parameters = wsa_cartto2nautfrom(fourier_dir_parameters);
            mem_dir_parameters = wsa_cartto2nautfrom(mem_dir_parameters);
            if opts.IG_flag
                out_IG_dirspectrum = wsa_cartto2nautfrom(out_IG_dirspectrum);
                IG_fourier_dir_parameters = wsa_cartto2nautfrom(IG_fourier_dir_parameters);
                IG_mem_dir_parameters = wsa_cartto2nautfrom(IG_mem_dir_parameters);
            end

        case {'cartesian_to', 'cartesiana_desde'}

        otherwise
            error('Se debe especificar alguna de las siguientes convenciones de dirección: ''cartesiana_hacia'' | ''nautica_desde'' ')
    end

    %== !!Mantener estas líneas SOLO si no se va a utilizar D, con el fin de optimizar uso de memoria!! == %.
    out_dirspectrum.Fourier = rmfield(out_dirspectrum.Fourier, 'D');
    out_dirspectrum.MEM = rmfield(out_dirspectrum.MEM, 'D');
    if opts.IG_flag
        out_IG_dirspectrum.Fourier = rmfield(out_IG_dirspectrum.Fourier, 'D');
        out_IG_dirspectrum.MEM = rmfield(out_IG_dirspectrum.MEM, 'D');
    end
    %=======================================================================================================%

    % Guardado 
    burst_results(b).out_dirspectrum = out_dirspectrum;
    burst_results(b).info_dirspectrum = info_dirspectrum;

    burst_results(b).params.Fourier = fourier_dir_parameters;
    burst_results(b).params.MEM = mem_dir_parameters;

    burst_results(b).coefficients.input = input_coeffs;
    burst_results(b).coefficients.MEM_reconstructed = mem_reconstructed_coeffs;
    burst_results(b).coefficients.MEM_residual = mem_residual_coeffs;


    if opts.IG_flag
        burst_results(b).out_IG_dirspectrum = out_IG_dirspectrum;
        burst_results(b).info_IG_dirspectrum = info_IG_dirspectrum;
        burst_results(b).IG_params.Fourier = IG_fourier_dir_parameters;
        burst_results(b).IG_params.MEM = IG_mem_dir_parameters;
        burst_results(b).IG_coefficients.input = IG_input_coeffs;
        burst_results(b).IG_coefficients.MEM_reconstructed = IG_mem_reconstructed_coeffs;
        burst_results(b).IG_coefficients.MEM_residual = IG_mem_residual_coeffs;
    end
end

%% Reorganización de datos para NetCDF

fprintf('\nReorganizando datos para formato NetCDF...\n');

nc_data = struct();

nc_data.time = burst_data.general.time(1:nBursts);
nc_data.Type = Type;

Methods = {'Fourier', 'MEM'};

% Coordenadas comunes
nc_data.f = burst_results(1).out_dirspectrum.Fourier.f(:);
nc_data.theta = burst_results(1).out_dirspectrum.Fourier.theta(:);

% Tamaños de variables (dimensiones)
nBurst = nBursts;
nFreq = numel(nc_data.f);
nTheta = numel(nc_data.theta);

% Verificar correspondencia Fourier-MEM
if ~isequaln(burst_results(1).out_dirspectrum.Fourier.f(:), burst_results(1).out_dirspectrum.MEM.f(:))
    error('Las frecuencias Fourier y MEM no coinciden.');
end
if ~isequaln(burst_results(1).out_dirspectrum.Fourier.theta(:), burst_results(1).out_dirspectrum.MEM.theta(:))
    error('Las direcciones Fourier y MEM no coinciden.');
end

% Inicializar resultados de los métodos
for k = 1:numel(Methods)
    method = Methods{k};
    nc_data.directional.(method).E = NaN(nFreq, nTheta, nBurst, 'single');
    nc_data.directional.(method).S = NaN(nFreq, nBurst);
    nc_data.directional.(method).f_mean_dir = NaN(nFreq, nBurst);
    nc_data.directional.(method).f_dir_spr = NaN(nFreq, nBurst);

end

% Inicializar coeficientes
coefficient_sets = {'input', 'MEM_reconstructed', 'MEM_residual'};
coefficient_names = {'a1','b1','a2','b2'};
for s = 1:numel(coefficient_sets)
    set_name = coefficient_sets{s};

    for c = 1:numel(coefficient_names)
        coeff = coefficient_names{c};
        nc_data.coefficients.(set_name).(coeff) = NaN(nFreq, nBurst);
    end
end

% Inicializar control de calidad Fourier
nc_data.qc.Fourier.D_raw_nonnegative_flag = zeros(nFreq, nBurst, 'uint8');
nc_data.qc.Fourier.D_raw_min_value = NaN(nFreq, nBurst);
nc_data.qc.Fourier.D_clipping_required_flag = zeros(nFreq, nBurst, 'uint8');
nc_data.qc.Fourier.D_negative_fraction = NaN(nFreq, nBurst);
nc_data.qc.Fourier.all_D_raw_nonnegative_flag = zeros(nBurst, 1, 'uint8');

% Inicializar control de calidad MEM
nc_data.qc.MEM.D_nonnegative_flag = zeros(nFreq, nBurst, 'uint8');
nc_data.qc.MEM.D_min_value = NaN(nFreq, nBurst);
nc_data.qc.MEM.D_finite_flag = zeros(nFreq, nBurst, 'uint8');
nc_data.qc.MEM.D_area_before_normalization = NaN(nFreq, nBurst);
nc_data.qc.MEM.max_imaginary_part = NaN(nFreq, nBurst);
nc_data.qc.MEM.check1_flag = zeros(nFreq, nBurst, 'uint8');
nc_data.qc.MEM.check2_flag = zeros(nFreq, nBurst, 'uint8');
nc_data.qc.MEM.double_peak_flag = zeros(nFreq, nBurst, 'uint8');
nc_data.qc.MEM.double_peak_error = NaN(nFreq, nBurst);
nc_data.qc.MEM.all_D_nonnegative_flag = zeros(nBurst, 1, 'uint8');
nc_data.qc.MEM.all_check1_flag = zeros(nBurst, 1, 'uint8');
nc_data.qc.MEM.all_check2_flag = zeros(nBurst, 1, 'uint8');
nc_data.qc.MEM.all_constraints_flag = zeros(nBurst, 1, 'uint8');

%% Inicializar resultados IG para exportación

if opts.IG_flag

    % Frecuencia y dirección completas del primer burst IG
    f_ig_full = burst_results(1).out_IG_dirspectrum.Fourier.f(:);
    theta_ig  = burst_results(1).out_IG_dirspectrum.Fourier.theta(:);

    % Frecuencia y dirección MEM del primer burst
    f_ig_mem = burst_results(1).out_IG_dirspectrum.MEM.f(:);
    theta_ig_mem = burst_results(1).out_IG_dirspectrum.MEM.theta(:);

    % Tolerancia para comparar vectores de frecuencia
    frequency_tolerance_IG = 10 * eps(max(1, max(abs(f_ig_full))));

    % Verificar correspondencia entre Fourier y MEM
    if numel(f_ig_mem) ~= numel(f_ig_full) || any(abs(f_ig_mem - f_ig_full) > frequency_tolerance_IG)
        error('Las frecuencias IG de Fourier y MEM no coinciden en el primer burst.')
    end

    if ~isequaln(theta_ig_mem, theta_ig)
        error('Las direcciones IG de Fourier y MEM no coinciden en el primer burst.');
    end

    % Se empleará una única coordenada direccional en el NetCDF
    if ~isequaln(theta_ig, nc_data.theta)
        error('El vector direccional IG no coincide con el vector direccional del procesamiento convencional.');
    end

    % Máscara de frecuencias que serán exportadas
    ig_keep = isfinite(f_ig_full) & f_ig_full >= 0 & f_ig_full <= opts.IG_export_fmax;

    if ~any(ig_keep)
        error('El espectro direccional IG no contiene frecuencias dentro del intervalo [0, %.6g] Hz.', opts.IG_export_fmax);
    end

    % Vector de frecuencias IG recortado
    nc_data.IG.f = f_ig_full(ig_keep);

    % Cantidad de frecuencias que se exportarán
    nFreq_IG = nnz(ig_keep);

    % Inicializar resultados IG por método
    for k = 1:numel(Methods)
        method = Methods{k};
        nc_data.IG.directional.(method).E = NaN(nFreq_IG, nTheta, nBurst, 'single');
        nc_data.IG.directional.(method).S = NaN(nFreq_IG, nBurst);
        nc_data.IG.directional.(method).f_mean_dir = NaN(nFreq_IG, nBurst);
        nc_data.IG.directional.(method).f_dir_spr = NaN(nFreq_IG, nBurst);
    end

    % Inicializar coeficientes IG
    for s = 1:numel(coefficient_sets)
        set_name = coefficient_sets{s};
        for c = 1:numel(coefficient_names)
            coeff = coefficient_names{c};
            nc_data.IG.coefficients.(set_name).(coeff) = NaN(nFreq_IG, nBurst);
        end
    end

    % Inicializar control de calidad IG Fourier
    nc_data.IG.qc.Fourier.D_raw_nonnegative_flag = zeros(nFreq_IG, nBurst, 'uint8');
    nc_data.IG.qc.Fourier.D_raw_min_value = NaN(nFreq_IG, nBurst);
    nc_data.IG.qc.Fourier.D_clipping_required_flag = zeros(nFreq_IG, nBurst, 'uint8');
    nc_data.IG.qc.Fourier.D_negative_fraction = NaN(nFreq_IG, nBurst);
    nc_data.IG.qc.Fourier.all_D_raw_nonnegative_flag = zeros(nBurst, 1, 'uint8');

    % Inicializar control de calidad IG MEM
    nc_data.IG.qc.MEM.D_nonnegative_flag = zeros(nFreq_IG, nBurst, 'uint8');
    nc_data.IG.qc.MEM.D_min_value = NaN(nFreq_IG, nBurst);
    nc_data.IG.qc.MEM.D_finite_flag = zeros(nFreq_IG, nBurst, 'uint8');
    nc_data.IG.qc.MEM.D_area_before_normalization = NaN(nFreq_IG, nBurst);
    nc_data.IG.qc.MEM.max_imaginary_part = NaN(nFreq_IG, nBurst);
    nc_data.IG.qc.MEM.check1_flag = zeros(nFreq_IG, nBurst, 'uint8');
    nc_data.IG.qc.MEM.check2_flag = zeros(nFreq_IG, nBurst, 'uint8');
    nc_data.IG.qc.MEM.double_peak_flag = zeros(nFreq_IG, nBurst, 'uint8');
    nc_data.IG.qc.MEM.double_peak_error = NaN(nFreq_IG, nBurst);
    nc_data.IG.qc.MEM.all_D_nonnegative_flag = zeros(nBurst, 1, 'uint8');
    nc_data.IG.qc.MEM.all_check1_flag = zeros(nBurst, 1, 'uint8');
    nc_data.IG.qc.MEM.all_check2_flag = zeros(nBurst, 1, 'uint8');
    nc_data.IG.qc.MEM.all_constraints_flag = zeros(nBurst, 1, 'uint8');
end

% Reorganizar burst por burst
for b = 1:nBurst
    % Verificar que la discretización sea común
    if ~isequaln(burst_results(b).out_dirspectrum.Fourier.f(:), nc_data.f)
        error('El vector de frecuencia cambia en el burst %d.', b);
    end

    if ~isequaln(burst_results(b).out_dirspectrum.Fourier.theta(:), nc_data.theta)
        error('El vector direccional cambia en el burst %d.', b);
    end

    % Métodos
    for k = 1:numel(Methods)
        method = Methods{k};
        out_method = burst_results(b).out_dirspectrum.(method);

        nc_data.directional.(method).E(:, :, b) = single(out_method.E);
        nc_data.directional.(method).S(:, b) = out_method.S;
        nc_data.directional.(method).f_mean_dir(:, b) = burst_results(b).params.(method).f_mean_dir;
        nc_data.directional.(method).f_dir_spr(:, b) = burst_results(b).params.(method).f_dir_spr;

    end

    % Coeficientes
    for s = 1:numel(coefficient_sets)
        set_name = coefficient_sets{s};

        coeffs = burst_results(b).coefficients.(set_name);

        for c = 1:numel(coefficient_names)
            coeff = coefficient_names{c};

            nc_data.coefficients.(set_name).(coeff)(:, b) = coeffs.(coeff);

        end
    end

    % QC Fourier
    qcFourier = burst_results(b).info_dirspectrum.Fourier;
    nc_data.qc.Fourier.D_raw_nonnegative_flag(:, b) = uint8(qcFourier.D_raw_nonnegative_flag);
    nc_data.qc.Fourier.D_raw_min_value(:, b) = qcFourier.D_raw_min_value;
    nc_data.qc.Fourier.D_clipping_required_flag(:, b) = uint8(qcFourier.D_clipping_required_flag);
    nc_data.qc.Fourier.D_negative_fraction(:, b) = qcFourier.D_negative_fraction;
    nc_data.qc.Fourier.all_D_raw_nonnegative_flag(b) = uint8(qcFourier.all_D_raw_nonnegative);

    % QC MEM
    qcMEM = burst_results(b).info_dirspectrum.MEM;
    nc_data.qc.MEM.D_nonnegative_flag(:, b) = uint8(qcMEM.D_nonnegative_flag);
    nc_data.qc.MEM.D_min_value(:, b) = qcMEM.D_min_value;
    nc_data.qc.MEM.D_finite_flag(:, b) = uint8(qcMEM.D_finite_flag);
    nc_data.qc.MEM.D_area_before_normalization(:, b) = qcMEM.D_area_before_normalization;
    nc_data.qc.MEM.max_imaginary_part(:, b) = qcMEM.max_imaginary_part;
    nc_data.qc.MEM.check1_flag(:, b) = uint8(qcMEM.constraints.check1);
    nc_data.qc.MEM.check2_flag(:, b) = uint8(qcMEM.constraints.check2);
    nc_data.qc.MEM.double_peak_flag(:, b) = uint8(qcMEM.double_peak_flag);
    nc_data.qc.MEM.double_peak_error(:, b) = qcMEM.double_peak_error;
    nc_data.qc.MEM.all_D_nonnegative_flag(b) = uint8(qcMEM.all_D_nonnegative);
    nc_data.qc.MEM.all_check1_flag(b) = uint8(all(qcMEM.constraints.check1));
    nc_data.qc.MEM.all_check2_flag(b) = uint8(all(qcMEM.constraints.check2));
    nc_data.qc.MEM.all_constraints_flag(b) = uint8(all(qcMEM.constraints.check1 & qcMEM.constraints.check2));

end

%% Reorganizar resultados IG burst por burst

if opts.IG_flag

    for b = 1:nBurst

        %% Verificar discretización común de frecuencias IG

        f_ig_burst = ...
            burst_results(b).out_IG_dirspectrum.Fourier.f(:);

        if numel(f_ig_burst) ~= numel(f_ig_full) || ...
                any(abs(f_ig_burst - f_ig_full) > ...
                    frequency_tolerance_IG)

            error(['El vector de frecuencias IG cambia en el ', ...
                   'burst %d.'], b);
        end

        theta_ig_burst = ...
            burst_results(b).out_IG_dirspectrum.Fourier.theta(:);

        if ~isequaln(theta_ig_burst, nc_data.theta)
            error(['El vector direccional IG cambia en el ', ...
                   'burst %d.'], b);
        end

        %% Resultados IG por método

        for k = 1:numel(Methods)
            method = Methods{k};
            out_method = burst_results(b).out_IG_dirspectrum.(method);

            % Verificar frecuencia del método
            f_method = out_method.f(:);
            if numel(f_method) ~= numel(f_ig_full) || any(abs(f_method - f_ig_full) > frequency_tolerance_IG)
                error('El vector de frecuencias IG del método %s cambia en el burst %d.', method, b);
            end

            % Verificar dirección del método
            if ~isequaln(out_method.theta(:), nc_data.theta)
                error('El vector direccional IG del método %s cambia en el burst %d.', method, b);
            end

            % Espectro direccional recortado
            nc_data.IG.directional.(method).E(:, :, b) = single(out_method.E(ig_keep, :));

            % Espectro frecuencial recortado
            S_method = out_method.S(:);
            nc_data.IG.directional.(method).S(:, b) = S_method(ig_keep);

            % Parámetros en función de la frecuencia
            f_mean_dir = burst_results(b).IG_params.(method).f_mean_dir(:);
            f_dir_spr = burst_results(b).IG_params.(method).f_dir_spr(:);
            nc_data.IG.directional.(method).f_mean_dir(:, b) = f_mean_dir(ig_keep);
            nc_data.IG.directional.(method).f_dir_spr(:, b) = f_dir_spr(ig_keep);
        end

        % Coeficientes IG
        for s = 1:numel(coefficient_sets)
            set_name = coefficient_sets{s};
            coeffs = burst_results(b).IG_coefficients.(set_name);
            for c = 1:numel(coefficient_names)
                coeff = coefficient_names{c};
                coeff_values = coeffs.(coeff);
                coeff_values = coeff_values(:);
                nc_data.IG.coefficients.(set_name).(coeff)(:, b) = coeff_values(ig_keep);
            end
        end

        % Control de calidad IG Fourier
        qcFourier = burst_results(b).info_IG_dirspectrum.Fourier;
        D_raw_nonnegative_flag = qcFourier.D_raw_nonnegative_flag(:);
        D_raw_min_value = qcFourier.D_raw_min_value(:);
        D_clipping_required_flag = qcFourier.D_clipping_required_flag(:);
        D_negative_fraction = qcFourier.D_negative_fraction(:);
        nc_data.IG.qc.Fourier.D_raw_nonnegative_flag(:, b) = uint8(D_raw_nonnegative_flag(ig_keep));
        nc_data.IG.qc.Fourier.D_raw_min_value(:, b) = D_raw_min_value(ig_keep);
        nc_data.IG.qc.Fourier.D_clipping_required_flag(:, b) = uint8(D_clipping_required_flag(ig_keep));
        nc_data.IG.qc.Fourier.D_negative_fraction(:, b) = D_negative_fraction(ig_keep);

        % Indicador agregado sobre las frecuencias exportadas
        nc_data.IG.qc.Fourier.all_D_raw_nonnegative_flag(b) = uint8(all(logical(D_raw_nonnegative_flag(ig_keep))));

        % Control de calidad IG MEM
        qcMEM = burst_results(b).info_IG_dirspectrum.MEM;
        D_nonnegative_flag = qcMEM.D_nonnegative_flag(:);
        D_min_value = qcMEM.D_min_value(:);
        D_finite_flag = qcMEM.D_finite_flag(:);
        D_area_before_normalization = qcMEM.D_area_before_normalization(:);
        max_imaginary_part = qcMEM.max_imaginary_part(:);
        check1_flag = qcMEM.constraints.check1(:);
        check2_flag = qcMEM.constraints.check2(:);
        double_peak_flag = qcMEM.double_peak_flag(:);
        double_peak_error = qcMEM.double_peak_error(:);
        nc_data.IG.qc.MEM.D_nonnegative_flag(:, b) = uint8(D_nonnegative_flag(ig_keep));
        nc_data.IG.qc.MEM.D_min_value(:, b) = D_min_value(ig_keep);
        nc_data.IG.qc.MEM.D_finite_flag(:, b) = uint8(D_finite_flag(ig_keep));
        nc_data.IG.qc.MEM.D_area_before_normalization(:, b) = D_area_before_normalization(ig_keep);
        nc_data.IG.qc.MEM.max_imaginary_part(:, b) = max_imaginary_part(ig_keep);
        nc_data.IG.qc.MEM.check1_flag(:, b) = uint8(check1_flag(ig_keep));
        nc_data.IG.qc.MEM.check2_flag(:, b) = uint8(check2_flag(ig_keep));
        nc_data.IG.qc.MEM.double_peak_flag(:, b) = uint8(double_peak_flag(ig_keep));
        nc_data.IG.qc.MEM.double_peak_error(:, b) = double_peak_error(ig_keep);

        % Indicadores agregados sobre las frecuencias exportadas
        nc_data.IG.qc.MEM.all_D_nonnegative_flag(b) = uint8(all(logical(D_nonnegative_flag(ig_keep))));
        nc_data.IG.qc.MEM.all_check1_flag(b) = uint8(all(logical(check1_flag(ig_keep))));
        nc_data.IG.qc.MEM.all_check2_flag(b) = uint8(all(logical(check2_flag(ig_keep))));
        nc_data.IG.qc.MEM.all_constraints_flag(b) = uint8(all(logical(check1_flag(ig_keep)) & logical(check2_flag(ig_keep))));
    end

    fprintf('\nEspectros direccionales IG recortados para exportación: 0 <= f <= %.6f Hz.\n', opts.IG_export_fmax);
    fprintf('Frecuencias IG originales : %d\n', numel(f_ig_full));
    fprintf('Frecuencias IG exportadas : %d\n', nFreq_IG);
end

% Parámetros direccionales por banda
bands = fieldnames(burst_results(1).params.Fourier.bands);
bands = setdiff(bands, {'ig'}, 'stable'); % Retirar la banda ig, ya que se procesa por separado y se agrega luego.
dir_params = {
    'DirTp'
    'SprTp'
    'MeanDir'
    'MeanSpread'
    'fp'
    'Tp'
    'm0'
    };
for k = 1:numel(Methods)
    method = Methods{k};
    for j = 1:numel(bands)
        band = bands{j};
        for p = 1:numel(dir_params)
            param = dir_params{p};
            if ~isfield(burst_results(1).params.(method).bands.(band), param)
                continue
            end
            nc_data.directional.(method).bands.(band).(param) = arrayfun(@(x) x.params.(method).bands.(band).(param), burst_results).';
        end
        nc_data.directional.(method).bands.(band).band_limits = burst_results(1).params.(method).bands.(band).band_limits;
    end
end

% Parámetros direccionales IG
if opts.IG_flag
    for k = 1:numel(Methods)
        method = Methods{k};
        for p = 1:numel(dir_params)
            param = dir_params{p};
            if ~isfield( ...
                    burst_results(1).IG_params.(method).bands.total, param)
                continue
            end
            nc_data.directional.(method).bands.ig.(param) = arrayfun(@(x) x.IG_params.(method).bands.total.(param), burst_results).';
        end
        nc_data.directional.(method).bands.ig.band_limits =  burst_results(1).IG_params.(method) .bands.total.band_limits;
    end
end

% Metadatos efectivos del procesamiento
effectiveDoF =  arrayfun(@(x) x.info_dirspectrum.info_spectrum.DoF, burst_results).';
effectiveK =    arrayfun(@(x) x.info_dirspectrum.info_spectrum.K, burst_results).';
effectiveN =    arrayfun(@(x) x.info_dirspectrum.info_spectrum.N, burst_results).';
effectiveN0 =   arrayfun(@(x) x.info_dirspectrum.info_spectrum.N0, burst_results).';
effectiveNfft = arrayfun(@(x) x.info_dirspectrum.info_spectrum.Nfft, burst_results).';
resolution_Hz = arrayfun(@(x) x.info_dirspectrum.info_spectrum.resolution_Hz, burst_results).';
resolution_s =  arrayfun(@(x) x.info_dirspectrum.info_spectrum.resolution_s, burst_results).';
effective_fs =  arrayfun(@(x) x.info_dirspectrum.info_spectrum.fs, burst_results).';

if opts.IG_flag

    effectiveDoF_IG = arrayfun(@(x) x.info_IG_dirspectrum.info_spectrum.DoF, burst_results).';
    effectiveK_IG = arrayfun(@(x) x.info_IG_dirspectrum.info_spectrum.K, burst_results).';
    effectiveN_IG = arrayfun(@(x) x.info_IG_dirspectrum.info_spectrum.N, burst_results).';
    effectiveN0_IG = arrayfun(@(x) x.info_IG_dirspectrum.info_spectrum.N0, burst_results).';
    effectiveNfft_IG = arrayfun(@(x) x.info_IG_dirspectrum.info_spectrum.Nfft, burst_results).';
    resolution_Hz_IG = arrayfun(@(x) x.info_IG_dirspectrum.info_spectrum.resolution_Hz, burst_results).';
    resolution_s_IG = arrayfun(@(x) x.info_IG_dirspectrum.info_spectrum.resolution_s, burst_results).';
    effective_fs_IG = arrayfun(@(x) x.info_IG_dirspectrum.info_spectrum.fs, burst_results).';
end


%% Crear archivo NetCDF temporal

fprintf('\nCreando archivo NetCDF...\n');

directional_ncfile = fullfile(processed_dir, [Sitio, '_', Camp, '_directional.nc']);

%Archivo temporal
directional_tmpfile = [directional_ncfile, '.tmp'];
if isfile(directional_tmpfile)

    delete(directional_tmpfile);
    pause(0.1);

    if isfile(directional_tmpfile)
        error(['No fue posible eliminar el archivo temporal residual:\n%s\n', ...
               'Puede estar abierto o bloqueado.'], ...
              directional_tmpfile);
    end
end

% Eliminar temp automáticamente si ocurre un error
tmpCleanup = onCleanup(@() safe_delete_tmp(directional_tmpfile));

%% Crear variables base del archivo NetCDF

fprintf('\nEscribiendo variables principales...\n');

wsa_nc_create_var(directional_tmpfile, ...
    'time', ...
    {'burst', nBurst}, ...
    'double', ...
    'units', 'seconds since 1970-01-01 00:00:00 UTC-06:00', ...
    'long_name', 'tiempo inicial');

wsa_nc_create_var(directional_tmpfile, ...
    'Type', ...
    {'burst', nBurst}, ...
    'string', ...
    'long_name', 'input signal type', ...
    'description', 'señal utilizada: ast o pressure');

wsa_nc_create_var(directional_tmpfile, ...
    'f', ...
    {'frequency', nFreq}, ...
    'double', ...
    'units', 'Hz', ...
    'long_name', 'frecuencia');

wsa_nc_create_var(directional_tmpfile, ...
    'theta', ...
    {'direction', nTheta}, ...
    'double', ...
    'units', 'degree', ...
    'long_name', 'dirección', ...
    'direction_convention', opts.DirConvention);

if opts.IG_flag
    wsa_nc_create_var(directional_tmpfile, ...
        'f_ig', ...
        {'frequency_ig', nFreq_IG}, ...
        'double', ...
        'units', 'Hz', ...
        'long_name', 'frecuencia IG');
end

safe_ncwrite(directional_tmpfile, 'time', wsa_datetime2posix(nc_data.time));
safe_ncwrite(directional_tmpfile, 'Type', nc_data.Type);
safe_ncwrite(directional_tmpfile, 'f', nc_data.f);
safe_ncwrite(directional_tmpfile, 'theta', nc_data.theta);
if opts.IG_flag
    safe_ncwrite(directional_tmpfile, 'f_ig', nc_data.IG.f);
end

%% Espectros direccionales y parámetros por método

Methods = {'Fourier', 'MEM'};

dir_params = {'DirTp', 'SprTp', 'MeanDir', 'MeanSpread', 'fp', 'Tp', 'm0'};
dir_units = {'degree', 'degree', 'degree', 'degree', 'Hz', 's', 'm2'};
dir_long_names = {
    'dirección media en el período pico'
    'dispersión angular en el período pico'
    'dirección media ponderada por energía'
    'dispersión angular ponderada por energía'
    'frecuencia pico'
    'período pico'
    'momento de orden cero'};

for k = 1:numel(Methods)

    method = Methods{k};

    fprintf('\nEscribiendo parámetros para el método %s...\n', method);

    % Espectros
    wsa_nc_create_var(directional_tmpfile, ...
        [method '/E'], ...
        {'frequency', nFreq, 'direction', nTheta, 'burst', nBurst}, ...
        'single', ...
        'units', 'm2/Hz/degree', ...
        'long_name', 'espectro direccional', ...
        'DeflateLevel', 3, ...
        'Shuffle', true, ...
        'ChunkSize', [nFreq, nTheta, 1]);

    safe_ncwrite(directional_tmpfile, [method '/E'], nc_data.directional.(method).E);

    if opts.IG_flag
        wsa_nc_create_var(directional_tmpfile, ...
            [method '/E_ig'], ...
            {'frequency_ig', nFreq_IG, 'direction', nTheta, 'burst', nBurst}, ...
            'single', ...
            'units', 'm2/Hz/degree', ...
            'long_name', 'espectro direccional IG', ...
            'DeflateLevel', 3, ...
            'Shuffle', true, ...
            'ChunkSize', [nFreq_IG, nTheta, 1]);
   
        safe_ncwrite(directional_tmpfile, [method '/E_ig'], nc_data.IG.directional.(method).E);
    end

    wsa_nc_create_var(directional_tmpfile, ...
        [method '/S'], ...
        {'frequency', nFreq, 'burst', nBurst}, ...
        'double', ...
        'units', 'm2/Hz', ...
        'long_name', 'espectro frecuencial asociado al espectro direccional');

    safe_ncwrite(directional_tmpfile, [method '/S'], nc_data.directional.(method).S);

    if opts.IG_flag
        wsa_nc_create_var(directional_tmpfile, ...
            [method '/S_ig'], ...
            {'frequency_ig', nFreq_IG, 'burst', nBurst}, ...
            'double', ...
            'units', 'm2/Hz', ...
            'long_name', 'espectro frecuencial asociado al espectro direccional IG');
    
        safe_ncwrite(directional_tmpfile, [method '/S_ig'], nc_data.IG.directional.(method).S);
    end


    % Dirección y dispersión por frecuencia

    wsa_nc_create_var(directional_tmpfile, ...
        [method '/f_mean_dir'], ...
        {'frequency', nFreq, 'burst', nBurst}, 'double', ...
        'units', 'degree', ...
        'long_name', 'dirección media en función de la frecuencia');

    safe_ncwrite(directional_tmpfile, [method '/f_mean_dir'], nc_data.directional.(method).f_mean_dir);

    if opts.IG_flag
        wsa_nc_create_var(directional_tmpfile, ...
            [method '/f_mean_dir_ig'], ...
            {'frequency_ig', nFreq_IG, 'burst', nBurst}, ...
            'double', ...
            'units', 'degree', ...
            'long_name', 'dirección media IG en función de la frecuencia');
    
        safe_ncwrite(directional_tmpfile, [method '/f_mean_dir_ig'], nc_data.IG.directional.(method).f_mean_dir);
    end

    wsa_nc_create_var(directional_tmpfile, ...
        [method '/f_dir_spr'], ...
        {'frequency', nFreq, 'burst', nBurst}, ...
        'double', ...
        'units', 'degree', ...
        'long_name', 'dispersión direccional en función de la frecuencia');

    safe_ncwrite(directional_tmpfile, [method '/f_dir_spr'], nc_data.directional.(method).f_dir_spr);

    if opts.IG_flag
        wsa_nc_create_var(directional_tmpfile, ...
            [method '/f_dir_spr_ig'], ...
            {'frequency_ig', nFreq_IG, 'burst', nBurst}, ...
            'double', ...
            'units', 'degree', ...
            'long_name', 'dispersión direccional IG en función de la frecuencia');
    
        safe_ncwrite(directional_tmpfile, [method '/f_dir_spr_ig'], nc_data.IG.directional.(method).f_dir_spr);
    end

    % Parámetros por banda
    method_bands = fieldnames(nc_data.directional.(method).bands);

    for j = 1:numel(method_bands)

        band = method_bands{j};

        for p = 1:numel(dir_params)

            param = dir_params{p};

            if ~isfield( ...
                    nc_data.directional.(method).bands.(band), param)
                continue
            end

            varname = [method '/bands/' band '/' param];

            wsa_nc_create_var(directional_tmpfile, ...
                varname, ...
                {'burst', nBurst}, ...
                'double', ...
                'units', dir_units{p}, ...
                'long_name', dir_long_names{p});

            safe_ncwrite(directional_tmpfile, varname, nc_data.directional.(method).bands.(band).(param));
        end
        
        % band limits
        limits_var = [method '/bands/' band '/band_limits'];

        wsa_nc_create_var(directional_tmpfile, ...
            limits_var, ...
            {'limit', 2}, ...
            'double', ...
            'units', 'Hz', ...
            'long_name', 'Limites superior e inferior de bandas de frecuencia');

        safe_ncwrite(directional_tmpfile, limits_var, nc_data.directional.(method).bands.(band).band_limits(:));
    end
end

%% Coeficientes direccionales

fprintf('\nEscribiendo coeficientes direccionales...\n');

coefficient_sets = {'input', 'MEM_reconstructed', 'MEM_residual'};

coefficient_names = {'a1','b1','a2','b2'};

coefficient_long_names = { 
    'Coeficiente de Fourier en coseno de primer orden' 
    'Coeficiente de Fourier en seno de primer orden' 
    'Coeficiente de Fourier en coseno de segundo orden' 
    'Coeficiente de Fourier en seno de segundo orden' 
    };

set_descriptions = {
    'coeficientes estimados directamente a partir de las señales medidas'
    'coeficientes reconstruidos a partir de la distribución direccional MEM'
    'diferencia entre los coeficientes reconstruidos por MEM y los coeficientes de entrada'
    };


for s = 1:numel(coefficient_sets)

    set_name = coefficient_sets{s};

    for c = 1:numel(coefficient_names)

        coeff = coefficient_names{c};

        varname = ['coefficients/' set_name '/' coeff];

        wsa_nc_create_var(directional_tmpfile, ...
            varname, ...
            {'frequency', nFreq, 'burst', nBurst}, ...
            'double', ...
            'units', '1', ...
            'long_name', coefficient_long_names{c}, ...
            'coefficient_set', set_descriptions{s}, ...
            'direction_convention', opts.DirConvention);

        safe_ncwrite(directional_tmpfile, varname, nc_data.coefficients.(set_name).(coeff));

        if opts.IG_flag
            varname_IG = ['coefficients_IG/' set_name '/' coeff];
        
            wsa_nc_create_var(directional_tmpfile, ...
                        varname_IG, ...
                        {'frequency_ig', nFreq_IG, 'burst', nBurst}, ...
                        'double', ...
                        'units', '1', ...
                        'long_name', [coefficient_long_names{c} ' para la señal IG'], ...
                        'coefficient_set', set_descriptions{s}, ...
                        'direction_convention', opts.DirConvention);
        
            safe_ncwrite(directional_tmpfile, varname_IG, nc_data.IG.coefficients.(set_name).(coeff));
        end
    end
end

%% Control de calidad Fourier

fprintf('\nEscribiendo parámetros de control de calidad para método Fourier...\n');

write_qc_variable(directional_tmpfile, ...
    'qc/Fourier/D_raw_nonnegative_flag', ...
    nc_data.qc.Fourier.D_raw_nonnegative_flag, ...
    {'frequency', nFreq, 'burst', nBurst}, ...
    'uint8', ...
    '1', ...
    'indicador de no negatividad de la distribución direccional TFS antes del recorte');

write_qc_variable(directional_tmpfile, ...
    'qc/Fourier/D_raw_min_value', ...
    nc_data.qc.Fourier.D_raw_min_value, ...
    {'frequency', nFreq, 'burst', nBurst}, ...
    'double', ...
    'rad-1', ...
    'valor mínimo de la distribución direccional TFS antes del recorte');

write_qc_variable(directional_tmpfile, ...
    'qc/Fourier/D_clipping_required_flag', ...
    nc_data.qc.Fourier.D_clipping_required_flag, ...
    {'frequency', nFreq, 'burst', nBurst}, ...
    'uint8', ...
    '1', ...
    'indicador de valores negativos que requirieron recorte');

write_qc_variable(directional_tmpfile, ...
    'qc/Fourier/D_negative_fraction', ...
    nc_data.qc.Fourier.D_negative_fraction, ...
    {'frequency', nFreq, 'burst', nBurst}, ...
    'double', ...
    '1', ...
    'fracción de bins direccionales por debajo de la tolerancia negativa');

write_qc_variable(directional_tmpfile, ...
    'qc/Fourier/all_D_raw_nonnegative_flag', ...
    nc_data.qc.Fourier.all_D_raw_nonnegative_flag, ...
    {'burst', nBurst}, ...
    'uint8', ...
    '1', ...
    'indicador de no negatividad de la distribución TFS en todas las frecuencias exportadas');

%% Control de calidad IG Fourier

if opts.IG_flag

    write_qc_variable(directional_tmpfile, ...
        'qc_IG/Fourier/D_raw_nonnegative_flag', ...
        nc_data.IG.qc.Fourier.D_raw_nonnegative_flag, ...
        {'frequency_ig', nFreq_IG, 'burst', nBurst}, ...
        'uint8', ...
        '1', ...
        'indicador de no negatividad de la distribución direccional TFS IG antes del recorte');

    write_qc_variable(directional_tmpfile, ...
        'qc_IG/Fourier/D_raw_min_value', ...
        nc_data.IG.qc.Fourier.D_raw_min_value, ...
        {'frequency_ig', nFreq_IG, 'burst', nBurst}, ...
        'double', ...
        'rad-1', ...
        'valor mínimo de la distribución direccional TFS IG antes del recorte');

    write_qc_variable(directional_tmpfile, ...
        'qc_IG/Fourier/D_clipping_required_flag', ...
        nc_data.IG.qc.Fourier.D_clipping_required_flag, ...
        {'frequency_ig', nFreq_IG, 'burst', nBurst}, ...
        'uint8', ...
        '1', ...
        'indicador de valores negativos IG que requirieron recorte');

    write_qc_variable(directional_tmpfile, ...
        'qc_IG/Fourier/D_negative_fraction', ...
        nc_data.IG.qc.Fourier.D_negative_fraction, ...
        {'frequency_ig', nFreq_IG, 'burst', nBurst}, ...
        'double', ...
        '1', ...
        'fracción de bins direccionales IG por debajo de la tolerancia negativa');

    write_qc_variable(directional_tmpfile, ...
        'qc_IG/Fourier/all_D_raw_nonnegative_flag', ...
        nc_data.IG.qc.Fourier.all_D_raw_nonnegative_flag, ...
        {'burst', nBurst}, ...
        'uint8', ...
        '1', ...
        'indicador de no negatividad de la distribución TFS en todas las frecuencias IG exportadas');
end

%% Control de calidad MEM

fprintf('\nEscribiendo parámetros de control de calidad para método MEM...\n');

write_qc_variable(directional_tmpfile, ...
    'qc/MEM/D_nonnegative_flag', ...
    nc_data.qc.MEM.D_nonnegative_flag, ...
    {'frequency', nFreq, 'burst', nBurst}, ...
    'uint8', ...
    '1', ...
    'indicador de no negatividad de la distribución direccional MEM');

write_qc_variable(directional_tmpfile, ...
    'qc/MEM/D_min_value', ...
    nc_data.qc.MEM.D_min_value, ...
    {'frequency', nFreq, 'burst', nBurst}, ...
    'double', ...
    'rad-1', ...
    'valor mínimo de la distribución direccional MEM cruda (raw)');

write_qc_variable(directional_tmpfile, ...
    'qc/MEM/D_finite_flag', ...
    nc_data.qc.MEM.D_finite_flag, ...
    {'frequency', nFreq, 'burst', nBurst}, ...
    'uint8', ...
    '1', ...
    'indicador que señala valores finitos en la distribución direccional MEM');

write_qc_variable(directional_tmpfile, ...
    'qc/MEM/D_area_before_normalization', ...
    nc_data.qc.MEM.D_area_before_normalization, ...
    {'frequency', nFreq, 'burst', nBurst}, ...
    'double', ...
    '1', ...
    'área de la distribución direccional MEM antes de la normalización');

write_qc_variable(directional_tmpfile, ...
    'qc/MEM/max_imaginary_part', ...
    nc_data.qc.MEM.max_imaginary_part, ...
    {'frequency', nFreq, 'burst', nBurst}, ...
    'double', ...
    'rad-1', ...
    'máxima componente imaginaria de la distribución MEM');

write_qc_variable(directional_tmpfile, ...
    'qc/MEM/check1_flag', ...
    nc_data.qc.MEM.check1_flag, ...
    {'frequency', nFreq, 'burst', nBurst}, ...
    'uint8', ...
    '1', ...
    'indicador para la desigualdad abs(C1) <= 1');

write_qc_variable(directional_tmpfile, ...
    'qc/MEM/check2_flag', ...
    nc_data.qc.MEM.check2_flag, ...
    {'frequency', nFreq, 'burst', nBurst}, ...
    'uint8', ...
    '1', ...
    'indicador para la desigualdad abs(C2-C1^2) <= 1-abs(C1)^2');

write_qc_variable(directional_tmpfile, ...
    'qc/MEM/double_peak_flag', ...
    nc_data.qc.MEM.double_peak_flag, ...
    {'frequency', nFreq, 'burst', nBurst}, ...
    'uint8', ...
    '1', ...
    'indicador de posible doble pico direccional');

write_qc_variable(directional_tmpfile, ...
    'qc/MEM/double_peak_error', ...
    nc_data.qc.MEM.double_peak_error, ...
    {'frequency', nFreq, 'burst', nBurst}, ...
    'double', ...
    '1', ...
    'error relativo utilizado para la detección de posibles dobles picos');

write_qc_variable(directional_tmpfile, ...
    'qc/MEM/all_D_nonnegative_flag', ...
    nc_data.qc.MEM.all_D_nonnegative_flag, ...
    {'burst', nBurst}, ...
    'uint8', ...
    '1', ...
    'indicador que señala una distribución MEM no negativa en todas las frecuencias');

write_qc_variable(directional_tmpfile, ...
    'qc/MEM/all_check1_flag', ...
    nc_data.qc.MEM.all_check1_flag, ...
    {'burst', nBurst}, ...
    'uint8', ...
    '1', ...
    'indicador que señala que se cumple el check1 en todas las frecuencias');

write_qc_variable(directional_tmpfile, ...
    'qc/MEM/all_check2_flag', ...
    nc_data.qc.MEM.all_check2_flag, ...
    {'burst', nBurst}, ...
    'uint8', ...
    '1', ...
    'indicador que señala que se cumple el check2 en todas las frecuencias');

write_qc_variable(directional_tmpfile, ...
    'qc/MEM/all_constraints_flag', ...
    nc_data.qc.MEM.all_constraints_flag, ...
    {'burst', nBurst}, ...
    'uint8', ...
    '1', ...
    'indicador que señala que se cumplen todas las desigualdades de los coeficientes MEM');

%% Control de calidad IG MEM

if opts.IG_flag

    write_qc_variable(directional_tmpfile, ...
        'qc_IG/MEM/D_nonnegative_flag', ...
        nc_data.IG.qc.MEM.D_nonnegative_flag, ...
        {'frequency_ig', nFreq_IG, 'burst', nBurst}, ...
        'uint8', ...
        '1', ...
        'indicador de no negatividad de la distribución direccional MEM IG');

    write_qc_variable(directional_tmpfile, ...
        'qc_IG/MEM/D_min_value', ...
        nc_data.IG.qc.MEM.D_min_value, ...
        {'frequency_ig', nFreq_IG, 'burst', nBurst}, ...
        'double', ...
        'rad-1', ...
        'valor mínimo de la distribución direccional MEM IG cruda');

    write_qc_variable(directional_tmpfile, ...
        'qc_IG/MEM/D_finite_flag', ...
        nc_data.IG.qc.MEM.D_finite_flag, ...
        {'frequency_ig', nFreq_IG, 'burst', nBurst}, ...
        'uint8', ...
        '1', ...
        'indicador de valores finitos en la distribución direccional MEM IG');

    write_qc_variable(directional_tmpfile, ...
        'qc_IG/MEM/D_area_before_normalization', ...
        nc_data.IG.qc.MEM.D_area_before_normalization, ...
        {'frequency_ig', nFreq_IG, 'burst', nBurst}, ...
        'double', ...
        '1', ...
        'área de la distribución direccional MEM IG antes de la normalización');

    write_qc_variable(directional_tmpfile, ...
        'qc_IG/MEM/max_imaginary_part', ...
        nc_data.IG.qc.MEM.max_imaginary_part, ...
        {'frequency_ig', nFreq_IG, 'burst', nBurst}, ...
        'double', ...
        'rad-1', ...
        'máxima componente imaginaria de la distribución MEM IG');

    write_qc_variable(directional_tmpfile, ...
        'qc_IG/MEM/check1_flag', ...
        nc_data.IG.qc.MEM.check1_flag, ...
        {'frequency_ig', nFreq_IG, 'burst', nBurst}, ...
        'uint8', ...
        '1', ...
        'indicador IG para la desigualdad abs(C1) <= 1');

    write_qc_variable(directional_tmpfile, ...
        'qc_IG/MEM/check2_flag', ...
        nc_data.IG.qc.MEM.check2_flag, ...
        {'frequency_ig', nFreq_IG, 'burst', nBurst}, ...
        'uint8', ...
        '1', ...
        'indicador IG para la desigualdad abs(C2-C1^2) <= 1-abs(C1)^2');

    write_qc_variable(directional_tmpfile, ...
        'qc_IG/MEM/double_peak_flag', ...
        nc_data.IG.qc.MEM.double_peak_flag, ...
        {'frequency_ig', nFreq_IG, 'burst', nBurst}, ...
        'uint8', ...
        '1', ...
        'indicador IG de posible doble pico direccional');

    write_qc_variable(directional_tmpfile, ...
        'qc_IG/MEM/double_peak_error', ...
        nc_data.IG.qc.MEM.double_peak_error, ...
        {'frequency_ig', nFreq_IG, 'burst', nBurst}, ...
        'double', ...
        '1', ...
        'error relativo IG utilizado para detectar posibles dobles picos');

    write_qc_variable(directional_tmpfile, ...
        'qc_IG/MEM/all_D_nonnegative_flag', ...
        nc_data.IG.qc.MEM.all_D_nonnegative_flag, ...
        {'burst', nBurst}, ...
        'uint8', ...
        '1', ...
        'indicador de no negatividad MEM para todas las frecuencias IG exportadas');

    write_qc_variable(directional_tmpfile, ...
        'qc_IG/MEM/all_check1_flag', ...
        nc_data.IG.qc.MEM.all_check1_flag, ...
        {'burst', nBurst}, ...
        'uint8', ...
        '1', ...
        'indicador de cumplimiento del check1 en todas las frecuencias IG exportadas');

    write_qc_variable(directional_tmpfile, ...
        'qc_IG/MEM/all_check2_flag', ...
        nc_data.IG.qc.MEM.all_check2_flag, ...
        {'burst', nBurst}, ...
        'uint8', ...
        '1', ...
        'indicador de cumplimiento del check2 en todas las frecuencias IG exportadas');

    write_qc_variable(directional_tmpfile, ...
        'qc_IG/MEM/all_constraints_flag', ...
        nc_data.IG.qc.MEM.all_constraints_flag, ...
        {'burst', nBurst}, ...
        'uint8', ...
        '1', ...
        'indicador de cumplimiento de todas las restricciones MEM en las frecuencias IG exportadas');
end

%% Atributos globales

fprintf('\nEscribiendo atributos globales...\n');

safe_ncwriteatt(directional_tmpfile, '/', 'description', 'Resultados de procesamiento direccional');
safe_ncwriteatt(directional_tmpfile, '/', 'source_file', proc_ncfile);
safe_ncwriteatt(directional_tmpfile, '/', 'processing_time_UTC-6', char(datetime('now', 'TimeZone', 'America/Costa_Rica', 'Format', 'yyyy-MM-dd''T''HH:mm:ssZZ')));
safe_ncwriteatt(directional_tmpfile, '/', 'Sitio', Sitio);
safe_ncwriteatt(directional_tmpfile, '/', 'Camp', Camp);
safe_ncwriteatt(directional_tmpfile, '/', 'InputType', opts.InputType);
safe_ncwriteatt(directional_tmpfile, '/', 'DirConvention', opts.DirConvention);
safe_ncwriteatt(directional_tmpfile, '/', 'coefficient_direction_convention', opts.DirConvention);
safe_ncwriteatt(directional_tmpfile, '/', 'DirSpecDoF_requested', opts.DirSpecDoF);
safe_ncwriteatt(directional_tmpfile, '/', 'Ntheta', opts.Ntheta);
safe_ncwriteatt(directional_tmpfile, '/', 'Kp_min', opts.Kp_min);
safe_ncwriteatt(directional_tmpfile, '/', 'pressure_units', opts.pressure_units);
safe_ncwriteatt(directional_tmpfile, '/', 'IG_processing', uint8(opts.IG_flag));

if opts.IG_flag
    safe_ncwriteatt(directional_tmpfile, '/', 'IGDirSpecDoF_requested', opts.IGDirSpecDoF);
    safe_ncwriteatt(directional_tmpfile, '/', 'IG_export_frequency_min_Hz', 0);
    safe_ncwriteatt(directional_tmpfile, '/', 'IG_export_frequency_max_Hz', opts.IG_export_fmax);
end

%% Crear variables adicionales que brindan información del método de Welch-Bartlett

% Decidir si escribir como atributo global o variable, dependiendo de si es constante o no.
write_att_or_var(directional_tmpfile, effectiveDoF, 'SpecDoF_effective', 'processing/DoF_effective', {'burst', nBurst}, 'double', 'grados de libertad espectrales efectivos')
write_att_or_var(directional_tmpfile, effectiveK, 'K_effective', 'processing/K_effective', {'burst', nBurst}, 'double', 'número de segmentos efectivos')
write_att_or_var(directional_tmpfile, effectiveN, 'N_effective', 'processing/N_effective', {'burst', nBurst}, 'double', 'longitud efectiva de segmentos')
write_att_or_var(directional_tmpfile, effectiveN0, 'N0_effective', 'processing/N0_effective', {'burst', nBurst}, 'double', 'traslape efectivo de segmentos')
write_att_or_var(directional_tmpfile, effectiveNfft, 'Nfft_effective', 'processing/Nfft_effective', {'burst', nBurst}, 'double', 'bins Nfft efectivos')
write_att_or_var(directional_tmpfile, resolution_Hz, 'resolution_Hz', 'processing/resolution_Hz', {'burst', nBurst}, 'double', 'resolución espectral en Hz')
write_att_or_var(directional_tmpfile, resolution_s, 'resolution_s', 'processing/resolution_s', {'burst', nBurst}, 'double', 'resolución espectral en segundos')
write_att_or_var(directional_tmpfile, effective_fs, 'fs', 'processing/fs', {'burst', nBurst}, 'double', 'frecuencia de muestreo');

if opts.IG_flag
    write_att_or_var(directional_tmpfile, effectiveDoF_IG, 'IGDirSpecDoF_effective', 'processing_IG/DoF_effective', {'burst', nBurst}, 'double', 'grados de libertad direccionales IG efectivos');
    write_att_or_var( directional_tmpfile,  effectiveK_IG,  'IGK_effective', 'processing_IG/K_effective', {'burst', nBurst}, 'double', 'número de segmentos IG efectivos');
    write_att_or_var(directional_tmpfile,  effectiveN_IG, 'IGN_effective', 'processing_IG/N_effective', {'burst', nBurst}, 'double', 'longitud efectiva de los segmentos IG');
    write_att_or_var(directional_tmpfile,  effectiveN0_IG, 'IGN0_effective', 'processing_IG/N0_effective', {'burst', nBurst}, 'double', 'traslape efectivo de los segmentos IG');
    write_att_or_var(directional_tmpfile, effectiveNfft_IG, 'IGNfft_effective', 'processing_IG/Nfft_effective', {'burst', nBurst}, 'double', 'cantidad efectiva de bins Nfft IG');
    write_att_or_var(  directional_tmpfile,  resolution_Hz_IG,  'IG_resolution_Hz', 'processing_IG/resolution_Hz', {'burst', nBurst}, 'double', 'resolución espectral IG en Hz');
    write_att_or_var(directional_tmpfile, resolution_s_IG, 'IG_resolution_s', 'processing_IG/resolution_s', {'burst', nBurst}, 'double', 'resolución espectral IG en segundos');
    write_att_or_var(directional_tmpfile, effective_fs_IG, 'IG_fs', 'processing_IG/fs', {'burst', nBurst}, 'double', 'frecuencia de muestreo del procesamiento IG');
end

%% Sustituir archivo definitivo

[status, msg, ~] = movefile(directional_tmpfile, directional_ncfile, 'f');

if ~status
    error(['El archivo temporal direccional se creó correctamente, ', ...
           'pero no fue posible sustituir el archivo definitivo:\n%s\n\n%s'], ...
          directional_ncfile, msg);
end
clear tmpCleanup

info.directional_ncfile = string(directional_ncfile);

%% Generar archivo de texto con contenido del NetCDF en la carpeta

fprintf('\nGenerando archivo de texto del contenido del NetCDF generado...\n');

if isfile(directional_ncfile)
    info.ncdisp_file = db_write_ncdisp_txt(directional_ncfile);
    fprintf('\n\nFormato de archivo netCDF resultante:\n')
    ncdisp(directional_ncfile);
else
    info.ncdisp_file = "";
    fprintf('\nNo se generó archivo ncdisp porque no existe el archivo .nc:\n%s\n', directional_tmpfile);
end

%% Mensaje final 

fprintf('\n\n========================================================================================================================\n');
fprintf('Procesamiento direccional finalizado correctamente: %s\n', char(string(datetime('now'), 'yyyy-MM-dd_HHmmss')));
fprintf('========================================================================================================================\n');

catch ME
    %Bloque que se corre en caso de errores y también genera un archivo de error
    
    % Mensaje a colocar en el archivo log.
    fprintf('\n\n========================================================================================================================\n');
    fprintf('ERROR durante el procesamiento direccional: %s\n', char(string(datetime('now'), 'yyyy-MM-dd_HHmmss')));
    fprintf('Mensaje: %s\n', ME.message);
    fprintf('Identificador: %s\n', ME.identifier);

    fprintf('\nReporte completo del error:\n');
    fprintf('%s\n', getReport( ...
        ME, ...
        'extended', ...
        'hyperlinks', 'off'));

    for k = 1:numel(ME.stack)
        fprintf('En %s (línea %d)\n', ME.stack(k).name, ME.stack(k).line);
    end
    fprintf('========================================================================================================================\n');

    diary off                                                               % En caso de error, se termina de escribir el log aquí.
    
    % Archivo de error.
    err_dir = fullfile(db_dir, 'logs', 'errors', Sitio, Camp);              % Directorio para archivos de errores: logs/errors/Sitio/Camp
    if ~exist(err_dir, 'dir')                                               % Crear directorio en caso de no existir
        mkdir(err_dir);
    end
    err_file = fullfile(err_dir, ...                                        % Nombre del archivo de error: error_Sitio_Camp_fecha.txt
        ['error_', Sitio, '_', Camp, '_', char(string(datetime('now'), 'yyyy-MM-dd_HHmmss')), '.txt']);
    fid = fopen(err_file, 'w');                                             % Comenzar escritura de archivo de error
    if fid ~= -1
        fprintf(fid, 'Fecha: %s\n', char(string(datetime('now'), 'yyyy-MM-dd_HHmmss')));
        fprintf(fid, 'Mensaje: %s\n', ME.message);
        fprintf(fid, 'Identificador: %s\n', ME.identifier);
        for k = 1:numel(ME.stack)
            fprintf(fid, 'En %s (línea %d)\n', ME.stack(k).name, ME.stack(k).line);
        end
        fclose(fid);                                                        % Finalizar escritura de arhivo de error
    else
        warning('No se pudo crear el archivo de error: %s', err_file);      % Error en caso de que falle fopen() al crear el archivo.
    end

    rethrow(ME)                                                             % Retoma el error al finalizar catch.
end

diary off                                                                   %Se termina de escribir el log si el try no presentó error.

end

function coeffs = convert_coeffs_cart_to_naut_from(coeffs)

a1 = coeffs.a1;
b1 = coeffs.b1;
a2 = coeffs.a2;
b2 = coeffs.b2;

% theta_nautical_from = 270° - theta_cartesian_to
coeffs.a1 = -b1;
coeffs.b1 = -a1;
coeffs.a2 = -a2;
coeffs.b2 =  b2;

end



