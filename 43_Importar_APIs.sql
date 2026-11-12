/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 10/11/2026

 Objetivo    : Consumir dos APIs públicas desde T-SQL y cargar los datos con
               los SP del ABM:
               - Banco Mundial: PBI per cápita (indicador NY.GDP.PCAP.CD) en
                 Torneo.Pais.pbiPerCapita.
                 Torneo.Importar_PBIBancoMundial
               - Frankfurter: cotización de cada moneda por 1 USD en
                 Publicidad.TipoCambio.
                 Publicidad.Importar_TipoCambioFrankfurter
               Ambas pasan por Sistema.ConsultarAPI, que hace el pedido HTTP.

 Fuentes     :
 - Banco Mundial, API de indicadores v2.
     URL      : https://api.worldbank.org/v2/country/<ISO3;ISO3>/indicator/NY.GDP.PCAP.CD
                ?format=json&mrnev=1 (mrnev=1: el último valor informado).
     Clave    : no requiere (la documentación oficial dice que las claves ya
                no son necesarias).
     Límites  : la documentación no publica un límite numérico de pedidos;
                se hacen pocos pedidos (10 países por llamada).
     Dato     : PBI per cápita en USD corrientes del último año disponible
                (hoy 2025). La tabla no guarda el año de referencia.
 - Frankfurter, API v2 (tipos de cambio de referencia de bancos centrales).
     URL      : https://api.frankfurter.dev/v2/rates?base=USD&quotes=<MONEDAS>
                [&from=AAAA-MM-DD&to=AAAA-MM-DD]
     Clave    : no requiere.
     Límites  : sin cuotas diarias ni mensuales; tiene un límite de tasa para
                evitar abusos (según su documentación).
     Dato     : unidades de la moneda por 1 USD, que es lo que guarda
                Publicidad.TipoCambio.cotizacionUSD. Son cotizaciones de
                referencia, no cotizaciones en vivo.
     Aviso    : la v1 (api.frankfurter.dev/v1) está marcada como antigua y
                cubre solo unas 30 monedas; la v2 cubre 219.

 Cómo trabaja:
 - Cada importación tiene dos SP: Importar_* hace el pedido HTTP y Procesar_*
   interpreta el JSON y carga los datos. Así Procesar_* se prueba con
   respuestas fijas, sin depender de internet.
 - Upsert sin duplicados: un dato igual al que ya está no se toca; uno distinto
   se modifica con el SP del ABM (Torneo.Pais_Modificacion,
   Publicidad.TipoCambio_Alta y Publicidad.TipoCambio_Modificacion). Repetir la
   importación no duplica nada.
 - Importación parcial: cada dato inválido va a Sistema.ErrorImportacion (con
   la URL como origen, el dato original y su motivo) y se sigue con los demás.
 - Los pedidos HTTP se reintentan hasta 2 veces, esperando 2 y 4 segundos, si
   fallan por algo transitorio (la red no responde, se agota el tiempo de
   espera o la API contesta HTTP 429 o 5xx).
 - Una API inaccesible, una respuesta que no es JSON o un error HTTP cortan la
   importación con THROW 50003. Un parámetro inválido, con THROW 50001.

 Requisito   : tener habilitado "Ole Automation Procedures" en el servidor:
                  EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
                  EXEC sp_configure 'Ole Automation Procedures', 1; RECONFIGURE;
               (requiere ser sysadmin). Se eligió esta vía porque
               sp_invoke_external_rest_endpoint solo existe en Azure SQL y SQL
               Server 2025: en este servidor el objeto está pero no funciona.
 Límite      : sp_OAGetProperty no devuelve más de unos 4000 caracteres (medido
               en este servidor: una respuesta de 3530 se lee y una de más de
               4000 falla), por eso los pedidos se hacen en tramos chicos: 10
               países por llamada al Banco Mundial y 40 cotizaciones por
               llamada a Frankfurter. Una respuesta más grande se informa con
               un error claro, no se corta en silencio.
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

/* =============================================================================
   1. Sistema.ConsultarAPI
   Hace un GET a una URL https y devuelve el cuerpo de la respuesta.
   - @exigir200 = 1: cualquier estado HTTP distinto de 200 corta con 50003.
     Con 0, devuelve el cuerpo y el estado para que decida quien llama (se usa
     para leer el 422 de Frankfurter cuando una moneda no existe).
   - @reintentos: cuántas veces más se intenta si falla por algo transitorio
     (la red no responde, se agota el tiempo de espera o la API contesta
     HTTP 429, 500, 502, 503 o 504), esperando 2, 4, 6... segundos entre
     intentos. Un error definitivo (HTTP 404, 422, respuesta mal formada)
     no se reintenta.
   - Solo https y solo GET: no se acepta otro protocolo ni otro método.
   ============================================================================= */
CREATE OR ALTER PROCEDURE Sistema.ConsultarAPI
    @url         nvarchar(2000),
    @respuesta   nvarchar(max)  OUTPUT,
    @estadoHttp  int            = NULL OUTPUT,
    @timeoutSeg  int            = 30,
    @exigir200   bit            = 1,
    @reintentos  int            = 2
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    DECLARE @http int, @hr int, @ms int, @paso nvarchar(60), @texto varchar(8000), @origen nvarchar(255),
            @descripcion nvarchar(255), @detalle nvarchar(1000), @numero int, @intento int = 0, @espera char(8);
    SET @url = LTRIM(RTRIM(@url));
    SET @respuesta = NULL;
    SET @estadoHttp = NULL;

    IF @url IS NULL OR @url = N''
        SET @errores += CHAR(10) + N'- La URL es obligatoria.';
    ELSE IF @url NOT LIKE N'https://%'
        SET @errores += CHAR(10) + N'- La URL debe empezar con https://.';

    IF @timeoutSeg IS NULL OR @timeoutSeg NOT BETWEEN 1 AND 300
        SET @errores += CHAR(10) + N'- El tiempo de espera debe estar entre 1 y 300 segundos.';

    IF @reintentos IS NULL OR @reintentos NOT BETWEEN 0 AND 5
        SET @errores += CHAR(10) + N'- Los reintentos deben estar entre 0 y 5.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo consultar la API:' + @errores;
        THROW 50001, @errores, 1;
    END;

    SET @ms = @timeoutSeg * 1000;

    WHILE 1 = 1
    BEGIN
        SET @intento += 1;
        SET @http = NULL;
        SET @hr = 0;
        SET @paso = N'';
        SET @estadoHttp = NULL;
        SET @texto = NULL;

        BEGIN TRY
            SET @paso = N'crear el objeto HTTP';
            EXEC @hr = sys.sp_OACreate N'MSXML2.ServerXMLHTTP.6.0', @http OUTPUT;
            IF @hr <> 0 THROW 51000, N'Falló sp_OACreate.', 1;

            SET @paso = N'configurar los tiempos de espera';
            EXEC @hr = sys.sp_OAMethod @http, 'setTimeouts', NULL, @ms, @ms, @ms, @ms;
            IF @hr <> 0 THROW 51000, N'Falló sp_OAMethod.', 1;

            SET @paso = N'abrir la conexión';
            EXEC @hr = sys.sp_OAMethod @http, 'open', NULL, 'GET', @url, 0;
            IF @hr <> 0 THROW 51000, N'Falló sp_OAMethod.', 1;

            SET @paso = N'enviar los encabezados';
            EXEC @hr = sys.sp_OAMethod @http, 'setRequestHeader', NULL, 'Accept', 'application/json';
            IF @hr <> 0 THROW 51000, N'Falló sp_OAMethod.', 1;
            EXEC @hr = sys.sp_OAMethod @http, 'setRequestHeader', NULL, 'User-Agent', 'TP-BBDDA-UNLaM (trabajo academico)';
            IF @hr <> 0 THROW 51000, N'Falló sp_OAMethod.', 1;

            SET @paso = N'enviar el pedido';
            EXEC @hr = sys.sp_OAMethod @http, 'send';
            IF @hr <> 0 THROW 51000, N'Falló sp_OAMethod.', 1;

            SET @paso = N'leer el estado HTTP';
            EXEC @hr = sys.sp_OAGetProperty @http, 'status', @estadoHttp OUTPUT;
            IF @hr <> 0 THROW 51000, N'Falló sp_OAGetProperty.', 1;

            -- sp_OAGetProperty devuelve como máximo unos 4000 caracteres, aunque el parámetro admita 8000
            SET @paso = N'leer la respuesta';
            EXEC @hr = sys.sp_OAGetProperty @http, 'responseText', @texto OUTPUT;
            IF @hr <> 0 AND @estadoHttp = 200
                THROW 51002, N'La respuesta supera los 4000 caracteres que permite leer sp_OAGetProperty: hay que pedir menos datos por llamada.', 1;

            IF @estadoHttp <> 200 AND @exigir200 = 1
            BEGIN
                SET @detalle = CONCAT(N'La API respondió HTTP ', @estadoHttp, N': ', LEFT(ISNULL(@texto, N''), 300));
                THROW 51001, @detalle, 1;
            END;

            SET @respuesta = CAST(@texto AS nvarchar(max));
            EXEC sys.sp_OADestroy @http;
            BREAK;
        END TRY
        BEGIN CATCH
            SET @numero = ERROR_NUMBER();
            SET @detalle = ERROR_MESSAGE();
            IF @numero = 51000
            BEGIN
                EXEC sys.sp_OAGetErrorInfo @http, @origen OUTPUT, @descripcion OUTPUT;
                SET @detalle = CONCAT(ISNULL(@descripcion, N'sin detalle'), N' (HRESULT ', CONVERT(varchar(20), @hr, 1), N')');
            END
            ELSE IF @numero = 15281
                SET @detalle = CONCAT(@detalle, N' Habilitarlo con: EXEC sp_configure ''Ole Automation Procedures'', 1; RECONFIGURE; (requiere ser sysadmin).');

            IF @http IS NOT NULL
                EXEC sys.sp_OADestroy @http;

            -- Solo se reintenta lo transitorio: la red que falla al enviar o una API sobrecargada
            IF @intento <= @reintentos
               AND (@paso = N'enviar el pedido' OR (@numero = 51001 AND @estadoHttp IN (429, 500, 502, 503, 504)))
                SET @espera = CONVERT(char(8), DATEADD(SECOND, 2 * @intento, CAST('00:00:00' AS time)), 108);
            ELSE
            BEGIN
                SET @errores = CONCAT(N'No se pudo consultar la API (', @paso, N'): ', @detalle,
                                      CASE WHEN @intento > 1 THEN CONCAT(N' [tras ', @intento, N' intentos]') ELSE N'' END);
                THROW 50003, @errores, 1;
            END;
        END CATCH;

        WAITFOR DELAY @espera;     -- solo se llega acá si hay que reintentar
    END;
END
GO

/* =============================================================================
   2. Torneo.Procesar_PBIBancoMundial
   Recibe un arreglo JSON con observaciones del Banco Mundial (los objetos que
   la API devuelve en la segunda posición de su respuesta) y actualiza el PBI
   per cápita de los países de Torneo.Pais.
   - @paises: códigos ISO alfa-3 separados por coma que se procesan. NULL son
     todos los países de la base. Un país pedido que la fuente no trae queda
     registrado como error.
   - Un país con la misma cifra no se toca; con otra, se modifica con
     Torneo.Pais_Modificacion.
   ============================================================================= */
CREATE OR ALTER PROCEDURE Torneo.Procesar_PBIBancoMundial
    @observacionesJson  nvarchar(max),
    @origen             nvarchar(260),
    @paises             varchar(max)  = NULL,
    @actualizados       int           = NULL OUTPUT,
    @sinCambios         int           = NULL OUTPUT,
    @conError           int           = NULL OUTPUT,
    @devolverResumen    bit           = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    DECLARE @leidas int, @id int, @nombre nvarchar(60), @iso2 varchar(10), @iso3 varchar(10),
            @huso varchar(50), @moneda varchar(10), @poblacion bigint, @nuevo decimal(12,2);
    SET @observacionesJson = LTRIM(RTRIM(@observacionesJson));
    SET @origen = LTRIM(RTRIM(@origen));

    IF @observacionesJson IS NULL OR @observacionesJson = N''
        SET @errores += CHAR(10) + N'- Las observaciones son obligatorias.';
    IF @origen IS NULL OR @origen = N''
        SET @errores += CHAR(10) + N'- El origen de los datos es obligatorio.';
    IF @paises IS NOT NULL
       AND EXISTS (SELECT 1 FROM STRING_SPLIT(@paises, ',')
                   WHERE TRIM(value) <> '' AND TRIM(value) COLLATE Latin1_General_BIN NOT LIKE '[A-Z][A-Z][A-Z]')
        SET @errores += CHAR(10) + N'- Los países deben ser códigos ISO alfa-3 de 3 letras separados por coma.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo procesar el PBI del Banco Mundial:' + @errores;
        THROW 50001, @errores, 1;
    END;

    IF ISJSON(@observacionesJson) = 0
    BEGIN
        SET @errores = N'No se pudo procesar el PBI del Banco Mundial: el contenido no es un JSON válido.';
        THROW 50003, @errores, 1;
    END;
    IF LEFT(@observacionesJson, 1) <> N'['
    BEGIN
        SET @errores = N'No se pudo procesar el PBI del Banco Mundial: se esperaba un arreglo de observaciones.';
        THROW 50003, @errores, 1;
    END;

    /* 1. Observaciones de la fuente, una fila por objeto del arreglo */
    CREATE TABLE #fuente (fila int PRIMARY KEY, iso3 varchar(10), anio varchar(10), valorTexto nvarchar(60),
                          original nvarchar(max));
    INSERT INTO #fuente (fila, iso3, anio, valorTexto, original)
    SELECT CAST(j.[key] AS int) + 1, UPPER(LTRIM(RTRIM(x.iso3))), x.anio, x.valor, j.value
    FROM OPENJSON(@observacionesJson) j
    CROSS APPLY OPENJSON(j.value) WITH (iso3  nvarchar(10) '$.countryiso3code',
                                        anio  nvarchar(10) '$.date',
                                        valor nvarchar(60) '$.value') x;
    SELECT @leidas = COUNT(*) FROM #fuente;

    /* 2. Un renglón por país a procesar, con su observación más reciente (si la hay) */
    CREATE TABLE #pais (id int PRIMARY KEY, nombre nvarchar(60), iso2 varchar(10), iso3 varchar(10),
                        huso varchar(50), moneda varchar(10), pbiActual decimal(12,2), poblacion bigint,
                        fila int NULL, original nvarchar(max) NULL, valorTexto nvarchar(60) NULL,
                        nuevo decimal(12,2) NULL,
                        accion char(1) NULL,     -- U: modificar, S: sin cambios, K: modificado, E: error
                        mensaje nvarchar(400) NULL);
    INSERT INTO #pais (id, nombre, iso2, iso3, huso, moneda, pbiActual, poblacion, fila, original, valorTexto)
    SELECT p.id, p.nombre, p.codigoISO2, p.codigoISO3, p.husoHorario, p.moneda, p.pbiPerCapita, p.poblacion,
           s.fila, s.original, s.valorTexto
    FROM Torneo.Pais p
    OUTER APPLY (SELECT TOP (1) f.fila, f.original, f.valorTexto
                 FROM #fuente f
                 WHERE f.iso3 = p.codigoISO3
                 ORDER BY f.anio DESC, f.fila) s
    WHERE @paises IS NULL
       OR p.codigoISO3 IN (SELECT UPPER(TRIM(value)) FROM STRING_SPLIT(@paises, ','));

    UPDATE #pais SET nuevo = TRY_CAST(TRY_CAST(valorTexto AS float) AS decimal(12,2)) WHERE valorTexto IS NOT NULL;

    UPDATE #pais SET accion = 'E', mensaje = N'- El país no figura en la fuente.' WHERE fila IS NULL;
    UPDATE #pais SET accion = 'E', mensaje = N'- La fuente no informa el PBI per cápita (valor nulo).'
    WHERE accion IS NULL AND valorTexto IS NULL;
    UPDATE #pais SET accion = 'E', mensaje = CONCAT(N'- El PBI per cápita no es un número válido: ', valorTexto, N'.')
    WHERE accion IS NULL AND nuevo IS NULL;
    UPDATE #pais SET accion = 'E', mensaje = N'- El PBI per cápita debe ser mayor a cero.'
    WHERE accion IS NULL AND nuevo <= 0;
    UPDATE #pais SET accion = CASE WHEN pbiActual = nuevo THEN 'S' ELSE 'U' END WHERE accion IS NULL;

    /* 3. Modificación país por país: un error no frena a los demás */
    SELECT @id = MIN(id) FROM #pais WHERE accion = 'U';
    WHILE @id IS NOT NULL
    BEGIN
        SELECT @nombre = nombre, @iso2 = iso2, @iso3 = iso3, @huso = huso, @moneda = moneda,
               @poblacion = poblacion, @nuevo = nuevo
        FROM #pais WHERE id = @id;

        BEGIN TRY
            EXEC Torneo.Pais_Modificacion @id = @id, @nombre = @nombre, @codigoISO2 = @iso2, @codigoISO3 = @iso3,
                 @husoHorario = @huso, @moneda = @moneda, @pbiPerCapita = @nuevo, @poblacion = @poblacion;
            UPDATE #pais SET accion = 'K' WHERE id = @id;
        END TRY
        BEGIN CATCH
            UPDATE #pais SET accion = 'E', mensaje = ERROR_MESSAGE() WHERE id = @id;
        END CATCH;

        SELECT @id = MIN(id) FROM #pais WHERE accion = 'U' AND id > @id;
    END;

    INSERT INTO Sistema.ErrorImportacion (archivo, tablaDestino, nroFila, datoOriginal, mensajeError)
    SELECT LEFT(@origen, 260), 'Torneo.Pais', fila, ISNULL(original, CONCAT(N'país ', iso3)), mensaje
    FROM #pais WHERE accion = 'E';

    SELECT @actualizados = ISNULL(SUM(CASE WHEN accion = 'K' THEN 1 ELSE 0 END), 0),
           @sinCambios   = ISNULL(SUM(CASE WHEN accion = 'S' THEN 1 ELSE 0 END), 0),
           @conError     = ISNULL(SUM(CASE WHEN accion = 'E' THEN 1 ELSE 0 END), 0)
    FROM #pais;

    IF @devolverResumen = 1
        SELECT @leidas AS filasLeidas, @actualizados AS actualizados, @sinCambios AS sinCambios,
               @conError AS conError;
END
GO

/* =============================================================================
   3. Torneo.Importar_PBIBancoMundial
   Pide a la API el PBI per cápita de todos los países de Torneo.Pais, de a
   @paisesPorPedido por llamada, y lo carga con Procesar_PBIBancoMundial.
   - Si la API rechaza un pedido (un código que no conoce), reintenta país por
     país: el país rechazado queda registrado como error y los demás se cargan.
   ============================================================================= */
CREATE OR ALTER PROCEDURE Torneo.Importar_PBIBancoMundial
    @urlBase           nvarchar(200) = N'https://api.worldbank.org/v2',
    @indicador         varchar(30)   = 'NY.GDP.PCAP.CD',
    @paisesPorPedido   int           = 10
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    DECLARE @url nvarchar(2000), @json nvarchar(max), @lista varchar(400), @cantidad int, @tramo int,
            @mensaje nvarchar(400), @filas nvarchar(max), @codigos varchar(max), @origen nvarchar(260),
            @act int, @sin int, @err int, @rechazados int, @leidas int;
    SET @urlBase = LTRIM(RTRIM(@urlBase));
    SET @indicador = LTRIM(RTRIM(@indicador));
    IF RIGHT(@urlBase, 1) = N'/'
        SET @urlBase = LEFT(@urlBase, LEN(@urlBase) - 1);

    IF @urlBase IS NULL OR @urlBase NOT LIKE N'https://%'
        SET @errores += CHAR(10) + N'- La URL base debe empezar con https://.';
    IF @indicador IS NULL OR @indicador = '' OR @indicador COLLATE Latin1_General_BIN LIKE '%[^A-Z0-9._]%'
        SET @errores += CHAR(10) + N'- El indicador solo puede tener letras mayúsculas, números, punto y guion bajo.';
    IF @paisesPorPedido IS NULL OR @paisesPorPedido NOT BETWEEN 1 AND 15
        SET @errores += CHAR(10) + N'- Los países por pedido deben estar entre 1 y 15.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo importar el PBI del Banco Mundial:' + @errores;
        THROW 50001, @errores, 1;
    END;

    SET @origen = LEFT(CONCAT(@urlBase, N'/country/<ISO3>/indicator/', @indicador), 260);

    /* 1. Cola de pedidos: los países de la base, en tramos */
    CREATE TABLE #cola (id int IDENTITY(1,1) PRIMARY KEY, lista varchar(400), cantidad int, hecho bit NOT NULL DEFAULT 0);
    ;WITH numerados AS (
        SELECT codigoISO3, (ROW_NUMBER() OVER (ORDER BY codigoISO3) - 1) / @paisesPorPedido AS tramo
        FROM Torneo.Pais
    )
    INSERT INTO #cola (lista, cantidad)
    SELECT STRING_AGG(codigoISO3, ';') WITHIN GROUP (ORDER BY codigoISO3), COUNT(*)
    FROM numerados GROUP BY tramo;

    CREATE TABLE #obs (id int IDENTITY(1,1) PRIMARY KEY, fila nvarchar(max));
    CREATE TABLE #rechazados (iso3 varchar(10), mensaje nvarchar(400));

    /* 2. Un pedido por tramo; si la API lo rechaza, se reintenta de a un país */
    SELECT @tramo = MIN(id) FROM #cola WHERE hecho = 0;
    WHILE @tramo IS NOT NULL
    BEGIN
        SELECT @lista = lista, @cantidad = cantidad FROM #cola WHERE id = @tramo;
        UPDATE #cola SET hecho = 1 WHERE id = @tramo;

        SET @url = CONCAT(@urlBase, N'/country/', @lista, N'/indicator/', @indicador, N'?format=json&per_page=50&mrnev=1');
        EXEC Sistema.ConsultarAPI @url = @url, @respuesta = @json OUTPUT;

        IF ISJSON(@json) = 0
        BEGIN
            SET @errores = CONCAT(N'No se pudo importar el PBI del Banco Mundial: la respuesta de ', @url, N' no es un JSON válido.');
            THROW 50003, @errores, 1;
        END;

        SET @mensaje = JSON_VALUE(@json, '$[0].message[0].value');
        IF @mensaje IS NOT NULL
        BEGIN
            IF @cantidad > 1
                INSERT INTO #cola (lista, cantidad) SELECT TRIM(value), 1 FROM STRING_SPLIT(@lista, ';');
            ELSE
                INSERT INTO #rechazados (iso3, mensaje) VALUES (@lista, @mensaje);
        END
        ELSE
            INSERT INTO #obs (fila) SELECT j.value FROM OPENJSON(@json, '$[1]') j;

        SELECT @tramo = MIN(id) FROM #cola WHERE hecho = 0;
    END;

    /* 3. Carga: los países rechazados por la API se informan y no se procesan */
    INSERT INTO Sistema.ErrorImportacion (archivo, tablaDestino, nroFila, datoOriginal, mensajeError)
    SELECT @origen, 'Torneo.Pais', NULL, CONCAT(N'país ', iso3),
           CONCAT(N'- La API rechazó el código de país ', iso3, N': ', mensaje)
    FROM #rechazados;
    SELECT @rechazados = COUNT(*) FROM #rechazados;
    SELECT @leidas = COUNT(*) FROM #obs;

    SELECT @filas = N'[' + ISNULL(STRING_AGG(fila, N','), N'') + N']' FROM #obs;
    SELECT @codigos = ISNULL(STRING_AGG(p.codigoISO3, ','), '')
    FROM Torneo.Pais p
    WHERE NOT EXISTS (SELECT 1 FROM #rechazados r WHERE r.iso3 = p.codigoISO3);

    EXEC Torneo.Procesar_PBIBancoMundial @observacionesJson = @filas, @origen = @origen, @paises = @codigos,
         @actualizados = @act OUTPUT, @sinCambios = @sin OUTPUT, @conError = @err OUTPUT, @devolverResumen = 0;

    SELECT @leidas AS filasLeidas, @act AS actualizados, @sin AS sinCambios, @err + @rechazados AS conError;
END
GO

/* =============================================================================
   4. Publicidad.Procesar_TipoCambioFrankfurter
   Recibe un arreglo JSON de cotizaciones de Frankfurter v2
   ([{"date":"2026-06-15","base":"USD","quote":"EUR","rate":0.86}, ...]) y las
   carga en Publicidad.TipoCambio con upsert por moneda y fecha.
   - Una cotización igual a la guardada no se toca; con otro valor se modifica
     con TipoCambio_Modificacion; si no existe se da de alta con TipoCambio_Alta.
   - Una fila con la base distinta de USD, sin fecha o moneda válidas, o con una
     cotización que no es un número positivo, se registra como error.
   ============================================================================= */
CREATE OR ALTER PROCEDURE Publicidad.Procesar_TipoCambioFrankfurter
    @cotizacionesJson  nvarchar(max),
    @origen            nvarchar(260),
    @insertados        int  = NULL OUTPUT,
    @actualizados      int  = NULL OUTPUT,
    @sinCambios        int  = NULL OUTPUT,
    @conError          int  = NULL OUTPUT,
    @devolverResumen   bit  = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    DECLARE @leidas int, @fila int, @moneda char(3), @fecha date, @cotizacion decimal(18,6);
    SET @cotizacionesJson = LTRIM(RTRIM(@cotizacionesJson));
    SET @origen = LTRIM(RTRIM(@origen));

    IF @cotizacionesJson IS NULL OR @cotizacionesJson = N''
        SET @errores += CHAR(10) + N'- Las cotizaciones son obligatorias.';
    IF @origen IS NULL OR @origen = N''
        SET @errores += CHAR(10) + N'- El origen de los datos es obligatorio.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo procesar el tipo de cambio:' + @errores;
        THROW 50001, @errores, 1;
    END;

    IF ISJSON(@cotizacionesJson) = 0
    BEGIN
        SET @errores = N'No se pudo procesar el tipo de cambio: el contenido no es un JSON válido.';
        THROW 50003, @errores, 1;
    END;
    IF LEFT(@cotizacionesJson, 1) = N'{'
    BEGIN
        SET @errores = CONCAT(N'No se pudo procesar el tipo de cambio: la API devolvió un error: ',
                              ISNULL(JSON_VALUE(@cotizacionesJson, '$.message'), N'sin detalle'));
        THROW 50003, @errores, 1;
    END;
    IF LEFT(@cotizacionesJson, 1) <> N'['
    BEGIN
        SET @errores = N'No se pudo procesar el tipo de cambio: se esperaba un arreglo de cotizaciones.';
        THROW 50003, @errores, 1;
    END;

    /* 1. Filas de la fuente, con cada campo validado por separado */
    CREATE TABLE #cot (fila int PRIMARY KEY, fechaTexto varchar(30), base varchar(10), moneda varchar(10),
                       rateTexto nvarchar(60), original nvarchar(max),
                       fecha date NULL, cotizacion decimal(18,6) NULL,
                       accion char(1) NULL,    -- I: alta, U: modificar, S: sin cambios, K: cargada, E: error
                       mensaje nvarchar(400) NULL);
    INSERT INTO #cot (fila, fechaTexto, base, moneda, rateTexto, original)
    SELECT CAST(j.[key] AS int) + 1, LTRIM(RTRIM(x.fecha)), UPPER(LTRIM(RTRIM(x.base))),
           UPPER(LTRIM(RTRIM(x.moneda))), x.rate, j.value
    FROM OPENJSON(@cotizacionesJson) j
    CROSS APPLY OPENJSON(j.value) WITH (fecha  varchar(30)   '$.date',
                                        base   varchar(10)   '$.base',
                                        moneda varchar(10)   '$.quote',
                                        rate   nvarchar(60)  '$.rate') x;
    SELECT @leidas = COUNT(*) FROM #cot;

    UPDATE #cot SET fecha = TRY_CAST(fechaTexto AS date),
                    cotizacion = TRY_CAST(TRY_CAST(rateTexto AS float) AS decimal(18,6));

    UPDATE #cot SET accion = 'E', mensaje = N'- La base de la cotización debe ser USD.'
    WHERE accion IS NULL AND ISNULL(base, '') <> 'USD';
    UPDATE #cot SET accion = 'E', mensaje = N'- La moneda debe ser un código ISO 4217 de 3 letras.'
    WHERE accion IS NULL AND (moneda IS NULL OR moneda COLLATE Latin1_General_BIN NOT LIKE '[A-Z][A-Z][A-Z]');
    UPDATE #cot SET accion = 'E', mensaje = CONCAT(N'- La fecha no es válida: ', ISNULL(fechaTexto, N'(vacía)'), N'.')
    WHERE accion IS NULL AND fecha IS NULL;
    UPDATE #cot SET accion = 'E', mensaje = CONCAT(N'- La cotización debe ser un número mayor a cero: ', ISNULL(rateTexto, N'(vacía)'), N'.')
    WHERE accion IS NULL AND (cotizacion IS NULL OR cotizacion <= 0);

    -- La misma moneda y fecha más de una vez en la respuesta: pasa cuando Frankfurter, que no publica los
    -- fines de semana, devuelve en dos ventanas seguidas la cotización del último día hábil. Si el valor es
    -- el mismo se cuenta como "sin cambios"; si difiere, es un error. Siempre se compara con la primera.
    UPDATE c SET accion = CASE WHEN o.cotizacion = c.cotizacion THEN 'S' ELSE 'E' END,
                 mensaje = CASE WHEN o.cotizacion = c.cotizacion THEN NULL
                                ELSE N'- La moneda y la fecha están repetidas en la respuesta con otro valor.' END
    FROM #cot c
    CROSS APPLY (SELECT TOP (1) x.cotizacion FROM #cot x
                 WHERE x.fila < c.fila AND x.accion IS NULL AND x.moneda = c.moneda AND x.fecha = c.fecha
                 ORDER BY x.fila) o
    WHERE c.accion IS NULL;

    UPDATE c SET accion = CASE WHEN t.moneda IS NULL THEN 'I'
                               WHEN t.cotizacionUSD = c.cotizacion THEN 'S'
                               ELSE 'U' END
    FROM #cot c
    LEFT JOIN Publicidad.TipoCambio t ON t.moneda = c.moneda AND t.fecha = c.fecha
    WHERE c.accion IS NULL;

    /* 2. Alta o modificación fila por fila: un error no frena a las demás */
    SELECT @fila = MIN(fila) FROM #cot WHERE accion IN ('I', 'U');
    WHILE @fila IS NOT NULL
    BEGIN
        SELECT @moneda = moneda, @fecha = fecha, @cotizacion = cotizacion FROM #cot WHERE fila = @fila;
        BEGIN TRY
            IF EXISTS (SELECT 1 FROM #cot WHERE fila = @fila AND accion = 'I')
                EXEC Publicidad.TipoCambio_Alta @moneda = @moneda, @fecha = @fecha, @cotizacionUSD = @cotizacion;
            ELSE
                EXEC Publicidad.TipoCambio_Modificacion @moneda = @moneda, @fecha = @fecha, @cotizacionUSD = @cotizacion;
            UPDATE #cot SET accion = CASE WHEN accion = 'I' THEN 'A' ELSE 'M' END WHERE fila = @fila;
        END TRY
        BEGIN CATCH
            UPDATE #cot SET accion = 'E', mensaje = ERROR_MESSAGE() WHERE fila = @fila;
        END CATCH;
        SELECT @fila = MIN(fila) FROM #cot WHERE accion IN ('I', 'U') AND fila > @fila;
    END;

    INSERT INTO Sistema.ErrorImportacion (archivo, tablaDestino, nroFila, datoOriginal, mensajeError)
    SELECT LEFT(@origen, 260), 'Publicidad.TipoCambio', fila, original, mensaje
    FROM #cot WHERE accion = 'E';

    SELECT @insertados   = ISNULL(SUM(CASE WHEN accion = 'A' THEN 1 ELSE 0 END), 0),
           @actualizados = ISNULL(SUM(CASE WHEN accion = 'M' THEN 1 ELSE 0 END), 0),
           @sinCambios   = ISNULL(SUM(CASE WHEN accion = 'S' THEN 1 ELSE 0 END), 0),
           @conError     = ISNULL(SUM(CASE WHEN accion = 'E' THEN 1 ELSE 0 END), 0)
    FROM #cot;

    IF @devolverResumen = 1
        SELECT @leidas AS filasLeidas, @insertados AS insertados, @actualizados AS actualizados,
               @sinCambios AS sinCambios, @conError AS conError;
END
GO

/* =============================================================================
   5. Publicidad.Importar_TipoCambioFrankfurter
   Pide a Frankfurter la cotización de cada moneda por 1 USD y la carga con
   Procesar_TipoCambioFrankfurter.
   - @fechaDesde y @fechaHasta: sin ninguna de las dos, la última cotización
     publicada; solo @fechaDesde, hasta hoy; con las dos, ese rango (máximo
     400 días). Las fechas no pueden ser futuras.
   - @monedas: códigos separados por coma. NULL son las monedas de los países
     (Torneo.Pais.moneda) y de los anunciantes (monedaFacturacion), menos USD.
   - Frankfurter rechaza todo el pedido si una moneda no existe (HTTP 422). En
     ese caso la moneda se registra como error y el pedido sigue con las demás.
   ============================================================================= */
CREATE OR ALTER PROCEDURE Publicidad.Importar_TipoCambioFrankfurter
    @fechaDesde  date          = NULL,
    @fechaHasta  date          = NULL,
    @monedas     varchar(200)  = NULL,
    @urlBase     nvarchar(200) = N'https://api.frankfurter.dev/v2'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    DECLARE @hoy date = CAST(GETDATE() AS date);
    DECLARE @url nvarchar(2000), @json nvarchar(max), @estado int, @quotes varchar(400), @mensaje nvarchar(400),
            @malaMoneda char(3), @origen nvarchar(260), @filas nvarchar(max),
            @tramo int, @maxTramo int, @cantMonedas int, @porVentana int, @dias int, @desde date, @hasta date,
            @ventana nvarchar(100), @seguir bit, @ins int, @act int, @sin int, @err int, @sinSoporte int,
            @leidas int;
    SET @urlBase = LTRIM(RTRIM(@urlBase));
    SET @monedas = NULLIF(LTRIM(RTRIM(@monedas)), '');
    IF RIGHT(@urlBase, 1) = N'/'
        SET @urlBase = LEFT(@urlBase, LEN(@urlBase) - 1);

    IF @urlBase IS NULL OR @urlBase NOT LIKE N'https://%'
        SET @errores += CHAR(10) + N'- La URL base debe empezar con https://.';
    IF @fechaHasta IS NOT NULL AND @fechaDesde IS NULL
        SET @errores += CHAR(10) + N'- Si se indica la fecha hasta, también hay que indicar la fecha desde.';
    IF @fechaDesde > @hoy OR @fechaHasta > @hoy
        SET @errores += CHAR(10) + N'- Las fechas no pueden ser futuras.';
    IF @fechaDesde > @fechaHasta
        SET @errores += CHAR(10) + N'- La fecha desde no puede ser posterior a la fecha hasta.';
    IF DATEDIFF(DAY, @fechaDesde, ISNULL(@fechaHasta, @hoy)) > 400
        SET @errores += CHAR(10) + N'- El rango no puede superar los 400 días.';
    IF @monedas IS NOT NULL
       AND EXISTS (SELECT 1 FROM STRING_SPLIT(@monedas, ',')
                   WHERE TRIM(value) COLLATE Latin1_General_BIN NOT LIKE '[A-Za-z][A-Za-z][A-Za-z]')
        SET @errores += CHAR(10) + N'- Las monedas deben ser códigos ISO 4217 de 3 letras separados por coma.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo importar el tipo de cambio:' + @errores;
        THROW 50001, @errores, 1;
    END;

    IF @fechaDesde IS NOT NULL AND @fechaHasta IS NULL
        SET @fechaHasta = @hoy;
    SET @origen = LEFT(CONCAT(@urlBase, N'/rates?base=USD'), 260);

    /* 1. Monedas a pedir, en tramos de hasta 40 por llamada */
    CREATE TABLE #monedas (moneda char(3) PRIMARY KEY, tramo int NULL, soportada bit NOT NULL DEFAULT 1,
                           mensaje nvarchar(400) NULL);
    IF @monedas IS NULL
        INSERT INTO #monedas (moneda)
        SELECT m FROM (SELECT UPPER(moneda) AS m FROM Torneo.Pais WHERE moneda IS NOT NULL
                       UNION
                       SELECT UPPER(monedaFacturacion) FROM Publicidad.Anunciante) x
        WHERE m <> 'USD' AND m COLLATE Latin1_General_BIN LIKE '[A-Z][A-Z][A-Z]';
    ELSE
        INSERT INTO #monedas (moneda)
        SELECT DISTINCT UPPER(TRIM(value)) FROM STRING_SPLIT(@monedas, ',') WHERE UPPER(TRIM(value)) <> 'USD';

    UPDATE m SET tramo = (n.rn - 1) / 40 FROM #monedas m
    JOIN (SELECT moneda, ROW_NUMBER() OVER (ORDER BY moneda) AS rn FROM #monedas) n ON n.moneda = m.moneda;
    SELECT @maxTramo = MAX(tramo), @cantMonedas = COUNT(*) FROM #monedas;

    CREATE TABLE #obs (id int IDENTITY(1,1) PRIMARY KEY, fila nvarchar(max));

    /* 2. Cada llamada trae a lo sumo 40 cotizaciones (unos 63 caracteres cada una): cabe en el tope de 4000 */
    SET @porVentana = CASE WHEN @cantMonedas > 40 THEN 40 ELSE ISNULL(NULLIF(@cantMonedas, 0), 1) END;
    SET @dias = CASE WHEN 40 / @porVentana < 1 THEN 1 ELSE 40 / @porVentana END;
    SET @desde = @fechaDesde;
    SET @seguir = CASE WHEN @maxTramo IS NULL THEN 0 ELSE 1 END;     -- sin monedas no hay nada que pedir

    WHILE @seguir = 1
    BEGIN
        IF @fechaDesde IS NULL
        BEGIN
            SET @ventana = N'';
            SET @hasta = NULL;
        END
        ELSE
        BEGIN
            SET @hasta = DATEADD(DAY, @dias - 1, @desde);
            IF @hasta > @fechaHasta SET @hasta = @fechaHasta;
            SET @ventana = CONCAT(N'&from=', CONVERT(char(10), @desde, 23), N'&to=', CONVERT(char(10), @hasta, 23));
        END;

        SET @tramo = 0;
        WHILE @tramo <= @maxTramo
        BEGIN
            WHILE 1 = 1
            BEGIN
                SELECT @quotes = STRING_AGG(moneda, ',') FROM #monedas WHERE tramo = @tramo AND soportada = 1;
                IF @quotes IS NULL BREAK;

                SET @url = CONCAT(@urlBase, N'/rates?base=USD&quotes=', @quotes, @ventana);
                EXEC Sistema.ConsultarAPI @url = @url, @respuesta = @json OUTPUT, @estadoHttp = @estado OUTPUT,
                     @exigir200 = 0;

                IF @estado = 200
                BEGIN
                    IF ISJSON(@json) = 0 OR LEFT(LTRIM(@json), 1) <> N'['
                    BEGIN
                        SET @errores = CONCAT(N'No se pudo importar el tipo de cambio: la respuesta de ', @url,
                                              N' no es un arreglo JSON.');
                        THROW 50003, @errores, 1;
                    END;
                    INSERT INTO #obs (fila) SELECT j.value FROM OPENJSON(@json) j;
                    BREAK;
                END
                ELSE IF @estado = 422 AND JSON_VALUE(@json, '$.message') LIKE N'invalid currency: %'
                BEGIN
                    -- Frankfurter rechaza todo el pedido por una moneda: se la aparta y se repite con las demás
                    SET @mensaje = JSON_VALUE(@json, '$.message');
                    SET @malaMoneda = UPPER(LTRIM(RTRIM(SUBSTRING(@mensaje, CHARINDEX(N':', @mensaje) + 1, 10))));
                    UPDATE #monedas SET soportada = 0, mensaje = @mensaje WHERE moneda = @malaMoneda;
                    IF @@ROWCOUNT = 0
                    BEGIN
                        SET @errores = CONCAT(N'No se pudo importar el tipo de cambio: Frankfurter rechazó el pedido: ', @mensaje);
                        THROW 50003, @errores, 1;
                    END;
                END
                ELSE
                BEGIN
                    SET @errores = CONCAT(N'No se pudo importar el tipo de cambio: la API respondió HTTP ', @estado,
                                          N': ', LEFT(ISNULL(@json, N''), 300));
                    THROW 50003, @errores, 1;
                END;
            END;
            SET @tramo += 1;
        END;

        IF @fechaDesde IS NULL
            SET @seguir = 0;                      -- sin fechas es un único pedido: la última cotización
        ELSE
        BEGIN
            SET @desde = DATEADD(DAY, @dias, @desde);
            IF @desde > @fechaHasta SET @seguir = 0;
        END;
    END;

    /* 3. Las monedas que Frankfurter no tiene se informan; el resto se carga */
    INSERT INTO Sistema.ErrorImportacion (archivo, tablaDestino, nroFila, datoOriginal, mensajeError)
    SELECT @origen, 'Publicidad.TipoCambio', NULL, CONCAT(N'moneda ', moneda),
           CONCAT(N'- La moneda ', moneda, N' no está disponible en Frankfurter (', mensaje, N').')
    FROM #monedas WHERE soportada = 0;
    SELECT @sinSoporte = COUNT(*) FROM #monedas WHERE soportada = 0;
    SELECT @leidas = COUNT(*) FROM #obs;

    SELECT @filas = N'[' + ISNULL(STRING_AGG(fila, N','), N'') + N']' FROM #obs;
    EXEC Publicidad.Procesar_TipoCambioFrankfurter @cotizacionesJson = @filas, @origen = @origen,
         @insertados = @ins OUTPUT, @actualizados = @act OUTPUT, @sinCambios = @sin OUTPUT, @conError = @err OUTPUT,
         @devolverResumen = 0;

    SELECT @leidas AS filasLeidas, @ins AS insertados, @act AS actualizados, @sin AS sinCambios,
           @err + @sinSoporte AS conError;
END
GO
