/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel - 45066788
               Salas, Martín Daniel - 45205702
               Zito Padró, Ezequiel Nehuén - 46097917
 Fecha       : 15/11/2026

 Objetivo    : Importación del listado de árbitros FIFA desde un archivo XML
               (datasets/arbitros_fifa_reducido.xml) hacia Arbitraje.Arbitro y
               Arbitraje.ArbitroIdioma, mediante los SP de ABM ya existentes
               (Arbitro_Alta, Arbitro_Modificacion, ArbitroIdioma_Alta).

 Reglas del proceso:
 - La ruta del archivo llega por parámetro y se valida (THROW 50003).
 - El archivo se lee y se parsea set-based (nodes/value) a tablas temporales.
 - Upsert por fila: si existe (mismo país, nombre y apellido) se modifica; si no,
   se da de alta. Los idiomas sólo se agregan (nunca se borran).
 - El país se resuelve por ISO3 (o por nombre si el ISO3 viene vacío) y NO se
   crea: si no existe en Torneo.Pais la fila se informa como error.
 - Cada fila corre en su propia transacción; una fila inválida se registra en
   Sistema.ErrorImportacion y la importación continúa con la siguiente.
 - El recorrido fila por fila se hace con WHILE sobre tablas temporales.
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

/* =============================================================================
   Procedimiento interno: procesa el XML ya leído (estructura, parseo, upsert por
   fila y registro de errores). Lo invoca Arbitraje.Importar_ArbitrosXML y permite
   importar un XML recibido como variable, sin necesidad de un archivo.
   ============================================================================= */
CREATE OR ALTER PROCEDURE Arbitraje.Importar_ArbitrosXMLDatos
    @xml              xml,
    @origen           nvarchar(260),
    @cantFilas        int = NULL OUTPUT,
    @cantInsertados   int = NULL OUTPUT,
    @cantActualizados int = NULL OUTPUT,
    @cantErrores      int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'', @msg nvarchar(4000);

    SET @cantFilas        = 0;
    SET @cantInsertados   = 0;
    SET @cantActualizados = 0;
    SET @cantErrores      = 0;

    -- 1. Precondiciones: cada fila usa su propia transacción (ROLLBACK por fila)
    IF @@TRANCOUNT > 0
        SET @errores += CHAR(10) + N'- El proceso de importación no puede ejecutarse dentro de una transacción abierta (cada fila usa su propia transacción).';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo importar el archivo de árbitros:' + @errores;
        THROW 50003, @errores, 1;
    END;

    -- 2. Estructura del XML
    IF @xml IS NULL OR @xml.exist('/Arbitros/Arbitro') = 0
    BEGIN
        SET @msg = N'Estructura inesperada: el archivo no contiene nodos /Arbitros/Arbitro.';
        THROW 50003, @msg, 1;
    END;

    -- 3. Parseo set-based a tablas temporales
    CREATE TABLE #FilaImp (
        n             int            NOT NULL PRIMARY KEY,
        nodo          xml            NOT NULL,
        nombre        nvarchar(200)  NULL,
        apellido      nvarchar(200)  NULL,
        paisTexto     nvarchar(200)  NULL,
        iso3          nvarchar(20)   NULL,
        categoria     nvarchar(100)  NULL,
        genero        nvarchar(100)  NULL,
        fechaTexto    nvarchar(50)   NULL,
        fecha         date           NULL,
        idPais        int            NULL,
        datoOriginal  nvarchar(max)  NULL,
        errorPropio   nvarchar(2000) NOT NULL DEFAULT (N'')
    );

    CREATE TABLE #IdiomaImp (
        k       int IDENTITY(1,1) NOT NULL PRIMARY KEY,
        n       int               NOT NULL,
        idioma  nvarchar(50)      NULL
    );

    -- nroFila = posición del nodo dentro del documento. nodes() no garantiza el
    -- orden en que devuelve los nodos, y SQL Server no soporta el eje
    -- preceding-sibling en XQuery; por eso se genera la serie 1..N y se toma el
    -- nodo de esa posición, lo que hace el número de fila determinístico.
    DECLARE @totalNodos int = @xml.value('count(/Arbitros/Arbitro)', 'int');

    WITH numeros AS (
        SELECT TOP (@totalNodos) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS pos
        FROM sys.all_objects AS a
        CROSS JOIN sys.all_objects AS b
    )
    INSERT INTO #FilaImp (n, nodo)
    SELECT pos, @xml.query('(/Arbitros/Arbitro)[sql:column("pos")][1]')
    FROM numeros;

    UPDATE #FilaImp
    SET nombre       = LTRIM(RTRIM(nodo.value('(/Arbitro/Nombre)[1]',                    'nvarchar(200)'))),
        apellido     = LTRIM(RTRIM(nodo.value('(/Arbitro/Apellido)[1]',                  'nvarchar(200)'))),
        paisTexto    = LTRIM(RTRIM(nodo.value('(/Arbitro/Pais)[1]',                      'nvarchar(200)'))),
        iso3         = LTRIM(RTRIM(nodo.value('(/Arbitro/Pais/@codigoISO3)[1]',          'nvarchar(20)'))),
        categoria    = LTRIM(RTRIM(nodo.value('(/Arbitro/Categoria)[1]',                 'nvarchar(100)'))),
        genero       = LTRIM(RTRIM(nodo.value('(/Arbitro/Genero)[1]',                    'nvarchar(100)'))),
        fechaTexto   = LTRIM(RTRIM(nodo.value('(/Arbitro/FechaInternacional)[1]',        'nvarchar(50)'))),
        datoOriginal = CAST(nodo AS nvarchar(max));

    UPDATE #FilaImp
    SET fecha = TRY_CONVERT(date, fechaTexto, 23);

    -- País: por ISO3; si el ISO3 viene vacío, por nombre. No se crean países.
    UPDATE f
    SET f.idPais = p.id
    FROM #FilaImp AS f
    JOIN Torneo.Pais AS p
      ON (ISNULL(f.iso3, N'') <> N'' AND p.codigoISO3 = f.iso3)
      OR (ISNULL(f.iso3, N'') =  N'' AND p.nombre     = f.paisTexto);

    -- Validaciones propias del archivo (las demás las hacen los SP de ABM)
    UPDATE #FilaImp
    SET errorPropio += CHAR(10) + N'- La fecha internacional ''' + fechaTexto + N''' no es una fecha válida (formato yyyy-mm-dd).'
    WHERE ISNULL(fechaTexto, N'') <> N'' AND fecha IS NULL;

    UPDATE #FilaImp
    SET errorPropio += CHAR(10) + N'- El nombre supera los 60 caracteres.'
    WHERE LEN(nombre) > 60;

    UPDATE #FilaImp
    SET errorPropio += CHAR(10) + N'- El apellido supera los 60 caracteres.'
    WHERE LEN(apellido) > 60;

    UPDATE #FilaImp
    SET errorPropio += CHAR(10) + N'- El género supera los 20 caracteres.'
    WHERE LEN(genero) > 20;

    UPDATE #FilaImp
    SET errorPropio += CHAR(10) + N'- La categoría supera los 15 caracteres.'
    WHERE LEN(categoria) > 15;

    INSERT INTO #IdiomaImp (n, idioma)
    SELECT f.n, LOWER(LTRIM(RTRIM(i.v.value('.', 'nvarchar(50)'))))
    FROM #FilaImp AS f
    CROSS APPLY f.nodo.nodes('/Arbitro/Idiomas/Idioma') AS i(v)
    ORDER BY f.n;

    SELECT @cantFilas = COUNT(*) FROM #FilaImp;

    -- 4. Upsert fila por fila (WHILE sobre tabla temporal), cada una en su transacción
    DECLARE @n int = 0,
            @nombre nvarchar(200), @apellido nvarchar(200), @categoria nvarchar(100),
            @genero nvarchar(100), @fecha date, @idPais int, @datoOriginal nvarchar(max),
            @errorPropio nvarchar(2000),
            @idArbitro int, @esAlta bit,
            @kIdioma int, @idioma nvarchar(50);

    WHILE EXISTS (SELECT 1 FROM #FilaImp WHERE n > @n)
    BEGIN
        SELECT TOP (1)
               @n            = n,
               @nombre       = nombre,
               @apellido     = apellido,
               @categoria    = categoria,
               @genero       = genero,
               @fecha        = fecha,
               @idPais       = idPais,
               @datoOriginal = datoOriginal,
               @errorPropio  = errorPropio
        FROM #FilaImp
        WHERE n > @n
        ORDER BY n;

        SET @idArbitro = NULL;
        SET @esAlta    = 0;

        BEGIN TRY
            BEGIN TRANSACTION;

            -- ¿Existe? Misma regla de unicidad que Arbitro_Alta
            IF @idPais IS NOT NULL AND ISNULL(@nombre, N'') <> N'' AND ISNULL(@apellido, N'') <> N''
                SELECT TOP (1) @idArbitro = idArbitro
                FROM Arbitraje.Arbitro
                WHERE idPais = @idPais
                  AND UPPER(LTRIM(RTRIM(nombre)))   = UPPER(@nombre)
                  AND UPPER(LTRIM(RTRIM(apellido))) = UPPER(@apellido)
                ORDER BY idArbitro;

            IF @idArbitro IS NOT NULL
            BEGIN
                EXEC Arbitraje.Arbitro_Modificacion
                     @idArbitro = @idArbitro, @idPais = @idPais,
                     @nombre = @nombre, @apellido = @apellido,
                     @categoria = @categoria, @genero = @genero,
                     @fechaInternacional = @fecha;
            END
            ELSE
            BEGIN
                SET @esAlta = 1;
                EXEC Arbitraje.Arbitro_Alta
                     @idPais = @idPais, @nombre = @nombre, @apellido = @apellido,
                     @categoria = @categoria, @genero = @genero,
                     @fechaInternacional = @fecha, @idArbitro = @idArbitro OUTPUT;
            END;

            -- Idiomas: sólo se agregan los que faltan (no se borra ninguno)
            SET @kIdioma = 0;
            WHILE EXISTS (SELECT 1 FROM #IdiomaImp WHERE n = @n AND k > @kIdioma)
            BEGIN
                SELECT TOP (1) @kIdioma = k, @idioma = idioma
                FROM #IdiomaImp
                WHERE n = @n AND k > @kIdioma
                ORDER BY k;

                IF NOT EXISTS (SELECT 1 FROM Arbitraje.ArbitroIdioma
                               WHERE idArbitro = @idArbitro AND idioma = @idioma)
                    EXEC Arbitraje.ArbitroIdioma_Alta @idArbitro = @idArbitro, @idioma = @idioma;
            END;

            -- Problemas propios del archivo: la fila se descarta (rollback)
            IF @errorPropio <> N''
            BEGIN
                SET @msg = N'Datos inválidos en el archivo:' + @errorPropio;
                THROW 50003, @msg, 1;
            END;

            COMMIT TRANSACTION;

            IF @esAlta = 1
                SET @cantInsertados += 1;
            ELSE
                SET @cantActualizados += 1;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;

            -- Si falló un SP de ABM se suman los problemas propios de la fila
            SET @msg = CASE
                           WHEN ERROR_NUMBER() = 50003 THEN ERROR_MESSAGE()
                           WHEN @errorPropio <> N''
                               THEN N'Datos inválidos en el archivo:' + @errorPropio + CHAR(10) + ERROR_MESSAGE()
                           ELSE ERROR_MESSAGE()
                       END;

            -- El error se registra después del rollback y no corta la importación.
            -- ISNULL: la columna archivo es NOT NULL; si alguien llama a este SP
            -- sin origen, el registro del error no debe cortar la importación.
            INSERT INTO Sistema.ErrorImportacion (archivo, tablaDestino, nroFila, datoOriginal, mensajeError)
            VALUES (ISNULL(@origen, N'(sin origen)'), 'Arbitraje.Arbitro', @n, @datoOriginal, LEFT(@msg, 4000));

            SET @cantErrores += 1;
        END CATCH;
    END;

    -- 5. Evidencia del resultado
    SELECT @cantFilas        AS cantFilas,
           @cantInsertados   AS cantInsertados,
           @cantActualizados AS cantActualizados,
           @cantErrores      AS cantErrores;
END
GO

/* =============================================================================
   Procedimiento público: valida la ruta, lee el archivo y delega el
   procesamiento en Arbitraje.Importar_ArbitrosXMLDatos.
   ============================================================================= */
CREATE OR ALTER PROCEDURE Arbitraje.Importar_ArbitrosXML
    @rutaArchivo     nvarchar(260),
    @cantFilas       int = NULL OUTPUT,
    @cantInsertados  int = NULL OUTPUT,
    @cantActualizados int = NULL OUTPUT,
    @cantErrores     int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    SET @cantFilas        = 0;
    SET @cantInsertados   = 0;
    SET @cantActualizados = 0;
    SET @cantErrores      = 0;

    -- 1. Precondiciones: transacción externa y ruta (acumulativas, un único THROW)
    IF @@TRANCOUNT > 0
        SET @errores += CHAR(10) + N'- El proceso de importación no puede ejecutarse dentro de una transacción abierta (cada fila usa su propia transacción).';
    IF @rutaArchivo IS NULL OR LTRIM(RTRIM(@rutaArchivo)) = N''
        SET @errores += CHAR(10) + N'- La ruta del archivo es obligatoria.';
    ELSE IF @rutaArchivo LIKE N'%[<>|"*?]%'
        SET @errores += CHAR(10) + N'- La ruta del archivo contiene caracteres inválidos (< > | " * ?).';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo importar el archivo de árbitros:' + @errores;
        THROW 50003, @errores, 1;
    END;

    SET @rutaArchivo = LTRIM(RTRIM(@rutaArchivo));

    -- 2. Lectura del archivo XML
    DECLARE @xml xml, @sql nvarchar(max), @msg nvarchar(4000);

    BEGIN TRY
        /* SQL dinámico estrictamente justificado: OPENROWSET(BULK ...) exige la
           ruta como literal y no admite variables (Msg 102). Se duplican las
           comillas simples de la ruta para evitar inyección. SINGLE_BLOB porque
           el XML está en utf-8 con acentos y el cast desde varbinary respeta la
           codificación declarada. */
        SET @sql = N'SELECT @x = CAST(BulkColumn AS xml) FROM OPENROWSET(BULK N'''
                 + REPLACE(@rutaArchivo, N'''', N'''''')
                 + N''', SINGLE_BLOB) AS t;';
        EXEC sys.sp_executesql @sql, N'@x xml OUTPUT', @x = @xml OUTPUT;
    END TRY
    BEGIN CATCH
        SET @msg = N'No se pudo leer el archivo XML de árbitros (inexistente, ilegible o con formato XML inválido): '
                 + ERROR_MESSAGE();
        THROW 50003, @msg, 1;
    END CATCH;

    -- 3. Procesamiento del contenido (SP interno)
    EXEC Arbitraje.Importar_ArbitrosXMLDatos
         @xml = @xml, @origen = @rutaArchivo,
         @cantFilas = @cantFilas OUTPUT, @cantInsertados = @cantInsertados OUTPUT,
         @cantActualizados = @cantActualizados OUTPUT, @cantErrores = @cantErrores OUTPUT;
END
GO