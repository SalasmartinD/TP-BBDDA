/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 23/11/2026

 Objetivo    : Entrega 8 (cifrado) - SP de negocio e importación que
               trabajaban con nombres de árbitros:
               - Arbitraje.DesignarCuerpoArbitral (script 21): los mensajes de
                 conflicto de nacionalidad y la advertencia de cruce muestran el
                 nombre del árbitro, que ahora se lee de Arbitraje.vw_Arbitro. Se
                 declara WITH EXECUTE AS OWNER para poder descifrarlo.
               - Arbitraje.Importar_ArbitrosXMLDatos (script 41): el árbitro
                 existente ya no se busca por nombre y apellido en la tabla sino
                 con Arbitraje.Arbitro_Buscar (70c), que compara por huella.
                 Las filas rechazadas se guardan en Sistema.ErrorImportacion (tabla
                 sin cifrar) sin el nombre, el apellido ni el género del nodo XML.
               Se redefinen con CREATE OR ALTER: los scripts 21 y 41 no se modifican.
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

/* =============================================================================
   1. Arbitraje.DesignarCuerpoArbitral
   Designa los 5 roles del cuerpo arbitral de un partido programado.

   Advertencia de cruce (no bloquea): si el partido es de una fase con
   orden >= 2, se avisa en @advertencia (y con PRINT) por cada árbitro cuyo
   país tenga una selección en competencia distinta de las dos que juegan.
   - En competencia: la selección tiene al menos un partido en una fase con
     orden >= 2 y no perdió ningún partido 'Finalizado' de esas fases.
   - Perdió: hizo menos goles que el rival; si empataron, hizo menos goles en
     la definición por penales (goles con minuto NULL, atribuidos a la
     selección del autor según Eventos.FormacionPartido). Un empate sin datos
     de penales no elimina a nadie (se prefiere advertir de más).
   ============================================================================= */

CREATE OR ALTER PROCEDURE Arbitraje.DesignarCuerpoArbitral
    @idPartido        int,
    @idPrincipal      int,
    @idAsistente1     int,
    @idAsistente2     int,
    @idCuartoArbitro  int,
    @idVar            int,
    @advertencia      nvarchar(2000) = NULL OUTPUT
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores          nvarchar(2000) = N'';
    DECLARE @estado           varchar(15),
            @ordenFase        int,
            @idSelLocal       int,
            @idSelVisitante   int,
            @idPaisLocal      int,
            @idPaisVisitante  int,
            @lista            nvarchar(2000);

    DECLARE @designacion TABLE (
        orden      tinyint      NOT NULL,
        rol        varchar(15)  NOT NULL,
        idArbitro  int          NULL
    );

    SET @advertencia = NULL;

    INSERT INTO @designacion (orden, rol, idArbitro)
    VALUES (1, 'Principal',      @idPrincipal),
           (2, 'Asistente 1',    @idAsistente1),
           (3, 'Asistente 2',    @idAsistente2),
           (4, 'Cuarto Arbitro', @idCuartoArbitro),
           (5, 'VAR',            @idVar);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Datos del partido (bloqueado hasta el final de la transacción)
        SELECT @estado          = p.estado,
               @ordenFase       = f.orden,
               @idSelLocal      = p.idSeleccionLocal,
               @idSelVisitante  = p.idSeleccionVisitante,
               @idPaisLocal     = sl.idPais,
               @idPaisVisitante = sv.idPais
        FROM Torneo.Partido p WITH (UPDLOCK, HOLDLOCK)
        JOIN Torneo.Fase f        ON f.idFase = p.fase
        JOIN Equipos.Seleccion sl ON sl.id    = p.idSeleccionLocal
        JOIN Equipos.Seleccion sv ON sv.id    = p.idSeleccionVisitante
        WHERE p.idPartido = @idPartido;

        -- D1. Existencia del partido
        IF @estado IS NULL
            SET @errores += CHAR(10) + N'- El partido especificado no existe.';

        -- D2. Solo partidos programados
        IF @estado IS NOT NULL AND @estado <> 'Programado'
            SET @errores += CHAR(10) + N'- Solo se puede designar el cuerpo arbitral de un partido programado.';

        -- D3. El partido no puede tener árbitros designados
        IF EXISTS (SELECT 1
                   FROM Arbitraje.cuerpoArbitral WITH (UPDLOCK, HOLDLOCK)
                   WHERE idPartido = @idPartido)
            SET @errores += CHAR(10) + N'- El partido ya tiene árbitros designados.';

        -- D4. Los 5 roles son obligatorios
        SET @lista = NULL;
        SELECT @lista = STRING_AGG(CAST(d.rol AS nvarchar(15)), N', ') WITHIN GROUP (ORDER BY d.orden)
        FROM @designacion d
        WHERE d.idArbitro IS NULL;

        IF @lista IS NOT NULL
            SET @errores += CHAR(10) + N'- Faltan designar los roles: ' + @lista + N'.';

        -- D5. Existencia de los árbitros informados
        SET @lista = NULL;
        SELECT @lista = STRING_AGG(CAST(x.idArbitro AS nvarchar(12)), N', ') WITHIN GROUP (ORDER BY x.idArbitro)
        FROM (SELECT DISTINCT d.idArbitro
              FROM @designacion d
              WHERE d.idArbitro IS NOT NULL
                AND NOT EXISTS (SELECT 1 FROM Arbitraje.Arbitro a WHERE a.idArbitro = d.idArbitro)) x;

        IF @lista IS NOT NULL
            SET @errores += CHAR(10) + N'- No existen los árbitros con id: ' + @lista + N'.';

        -- D6. Un árbitro, un rol
        IF EXISTS (SELECT 1
                   FROM @designacion
                   WHERE idArbitro IS NOT NULL
                   GROUP BY idArbitro
                   HAVING COUNT(*) > 1)
            SET @errores += CHAR(10) + N'- Un mismo árbitro no puede cumplir más de un rol en el partido.';

        -- D7. Conflicto de nacionalidad: una línea por árbitro en conflicto
        IF @estado IS NOT NULL
        BEGIN
            SET @lista = NULL;
            SELECT @lista = STRING_AGG(CAST(CHAR(10) + N'- El árbitro ' + a.apellido + N', ' + a.nombre
                                            + N' (' + d.rol + N') es de ' + pa.nombre
                                            + N', que disputa el partido.' AS nvarchar(max)), N'')
                            WITHIN GROUP (ORDER BY d.orden)
            FROM @designacion d
            JOIN Arbitraje.vw_Arbitro a ON a.idArbitro = d.idArbitro
            JOIN Torneo.Pais pa      ON pa.id       = a.idPais
            WHERE a.idPais IN (@idPaisLocal, @idPaisVisitante);

            IF @lista IS NOT NULL
                SET @errores += @lista;
        END;

        -- THROW único
        IF @errores <> N''
        BEGIN
            SET @errores = N'No se pudo designar el cuerpo arbitral:' + @errores;
            THROW 50002, @errores, 1;
        END;

        INSERT INTO Arbitraje.cuerpoArbitral (idArbitro, idPartido, rol)
        SELECT d.idArbitro, @idPartido, d.rol
        FROM @designacion d;

        -- Advertencia de cruce (informativa, solo desde la fase de orden 2)
        IF @ordenFase >= 2
        BEGIN
            WITH PartidoEliminatorio AS (
                SELECT p.idPartido, p.idSeleccionLocal, p.idSeleccionVisitante,
                       p.estado, p.golLocal, p.golVisitante
                FROM Torneo.Partido p
                JOIN Torneo.Fase f ON f.idFase = p.fase
                WHERE f.orden >= 2
            ),
            Lado AS (   -- una fila por selección y partido eliminatorio
                SELECT idPartido, idSeleccionLocal AS idSeleccion, idSeleccionVisitante AS idRival,
                       estado, golLocal AS golesPropios, golVisitante AS golesRival
                FROM PartidoEliminatorio
                UNION ALL
                SELECT idPartido, idSeleccionVisitante, idSeleccionLocal,
                       estado, golVisitante, golLocal
                FROM PartidoEliminatorio
            ),
            LadoPenales AS (
                SELECT l.idSeleccion, l.estado, l.golesPropios, l.golesRival,
                       (SELECT COUNT(*)
                        FROM Eventos.Gol g
                        JOIN Eventos.FormacionPartido fp ON fp.idPartido = g.idPartido
                                                        AND fp.idJugador = g.idJugador
                        WHERE g.idPartido = l.idPartido
                          AND g.minuto IS NULL
                          AND fp.idSeleccion = l.idSeleccion) AS penalesPropios,
                       (SELECT COUNT(*)
                        FROM Eventos.Gol g
                        JOIN Eventos.FormacionPartido fp ON fp.idPartido = g.idPartido
                                                        AND fp.idJugador = g.idJugador
                        WHERE g.idPartido = l.idPartido
                          AND g.minuto IS NULL
                          AND fp.idSeleccion = l.idRival) AS penalesRival
                FROM Lado l
            ),
            Eliminada AS (
                SELECT DISTINCT idSeleccion
                FROM LadoPenales
                WHERE estado = 'Finalizado'
                  AND (   golesPropios < golesRival
                       OR (golesPropios = golesRival AND penalesPropios < penalesRival))
            ),
            EnCompetencia AS (
                SELECT DISTINCT l.idSeleccion
                FROM Lado l
                WHERE NOT EXISTS (SELECT 1 FROM Eliminada e WHERE e.idSeleccion = l.idSeleccion)
            )
            SELECT @advertencia = STRING_AGG(CAST(N'Advertencia: el árbitro ' + a.apellido + N', ' + a.nombre
                                                  + N' (' + d.rol + N') es de ' + pa.nombre
                                                  + N', cuya selección sigue en competencia y podría cruzarse con las selecciones de este partido.'
                                                  AS nvarchar(max)), CHAR(10))
                                  WITHIN GROUP (ORDER BY d.orden)
            FROM @designacion d
            JOIN Arbitraje.vw_Arbitro a  ON a.idArbitro = d.idArbitro
            JOIN Torneo.Pais pa       ON pa.id       = a.idPais
            JOIN Equipos.Seleccion s  ON s.idPais    = a.idPais
            JOIN EnCompetencia ec     ON ec.idSeleccion = s.id
            WHERE s.id NOT IN (@idSelLocal, @idSelVisitante);
        END;

        COMMIT TRANSACTION;

        IF @advertencia IS NOT NULL
            PRINT @advertencia;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END
GO
GO

/* =============================================================================
   2. Procedimiento interno: procesa el XML ya leído (estructura, parseo, upsert por
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
        fechaTexto   = LTRIM(RTRIM(nodo.value('(/Arbitro/FechaInternacional)[1]',        'nvarchar(50)')));

    -- datoOriginal se guarda en Sistema.ErrorImportacion, que no está cifrada: se le
    -- quitan el nombre, el apellido y el género (los datos que cifra el 70b). Queda el
    -- resto del nodo (país, categoría, fecha, idiomas) para diagnosticar el rechazo.
    -- Los valores ya se leyeron arriba; los idiomas se leen del nodo más abajo y no se tocan.
    UPDATE #FilaImp
    SET nodo.modify('delete (/Arbitro/Nombre, /Arbitro/Apellido, /Arbitro/Genero)');

    UPDATE #FilaImp
    SET datoOriginal = CAST(nodo AS nvarchar(max)),
        fecha        = TRY_CONVERT(date, fechaTexto, 23);

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

            -- ¿Existe? Misma regla de unicidad que Arbitro_Alta. El nombre y el apellido
            -- están cifrados: la búsqueda la hace Arbitro_Buscar por huella (70c).
            IF @idPais IS NOT NULL AND ISNULL(@nombre, N'') <> N'' AND ISNULL(@apellido, N'') <> N''
                EXEC Arbitraje.Arbitro_Buscar @idPais = @idPais, @nombre = @nombre, @apellido = @apellido,
                                              @idArbitro = @idArbitro OUTPUT;

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
