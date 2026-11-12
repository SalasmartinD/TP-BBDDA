/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 09/11/2026

 Objetivo    : Importar el fixture y los resultados del Mundial desde un CSV:
               Torneo.Importar_FixtureCSV(@rutaArchivo).

 Fuente      : https://fixturedownload.com/download/fifa-world-cup-2026-UTC.csv
               (descarga directa, sin clave y sin límite de uso publicado).
               Se guarda tal cual en datasets/fifa-world-cup-2026-UTC.csv.
               Columnas: Match Number, Round Number, Date, Location, Home Team,
               Away Team, Group, Result. La fecha viene en UTC (dd/MM/yyyy HH:mm).

 Cómo trabaja:
 - Upsert sin duplicados: la clave natural es Match Number, que es
   Partido.nroPartidoOficial. Si el partido no existe se da de alta; si existe
   y algún dato cambió se modifica; si no cambió, no se toca. Repetir la
   importación del mismo archivo no duplica nada: ni los partidos ni los
   errores, porque los de la corrida anterior de ese archivo se reemplazan.
 - El nombre del archivo es el parámetro. BULK INSERT no acepta variables
   para el nombre, por eso es el único SQL dinámico y está justificado.
 - El archivo se lee a una tabla temporal con todas las columnas como texto y
   se valida fila por fila. Cada fila inválida va a Sistema.ErrorImportacion
   (con su número de fila, el dato original y todos sus errores juntos) y las
   demás se importan igual. Un archivo ilegible o con otro encabezado corta
   toda la importación con THROW 50003.
 - Todas las altas y modificaciones pasan por Torneo.Partido_Alta y
   Torneo.Partido_Modificacion (10a). Si el ABM rechaza una fila, el error
   también queda en ErrorImportacion y se sigue con la siguiente.
 - Un partido sin resultado en el archivo queda Programado; si el archivo no
   trae el resultado de un partido que ya lo tenía, se conserva el que había
   (no se pierde información histórica). La asistencia, los esquemas y el
   número de partido no vienen en el archivo y no se tocan.
 - Los nombres en inglés de las selecciones y de los estadios se traducen a
   los datos del sistema con las tablas de equivalencias del SP (código FIFA
   de la selección y ciudad de la sede). Una selección que no está cargada
   es un error de esa fila, no de toda la importación.

 Errores     : 50001 parámetro inválido, 50003 error de importación.
 Requisito   : la cuenta que ejecuta necesita ADMINISTER BULK OPERATIONS y
               acceso de lectura a la carpeta del archivo.
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE Torneo.Importar_FixtureCSV
    @rutaArchivo  nvarchar(260)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    DECLARE @sql nvarchar(max), @fila int, @maxFila int, @idPartido int;
    DECLARE @insertados int = 0, @actualizados int = 0, @sinCambios int = 0, @conError int = 0, @total int;
    DECLARE @nro int, @fechaUTC datetime2(0), @idSede int, @idLocal int, @idVisitante int, @idFase int,
            @estado varchar(15), @golLocal tinyint, @golVisitante tinyint, @hayResultado bit;
    DECLARE @act TABLE (idSede int, idLocal int, idVisitante int, idFase int, fechaUTC datetime2(0),
                        estado varchar(15), golLocal tinyint, golVisitante tinyint, publico int,
                        esquemaLocal varchar(10), esquemaVisitante varchar(10));
    DECLARE @publico int, @esquemaLocal varchar(10), @esquemaVisitante varchar(10);
    SET @rutaArchivo = LTRIM(RTRIM(@rutaArchivo));

    IF @rutaArchivo IS NULL OR @rutaArchivo = N''
        SET @errores += CHAR(10) + N'- El nombre del archivo es obligatorio.';
    ELSE IF @rutaArchivo NOT LIKE N'%.csv'
        SET @errores += CHAR(10) + N'- El archivo debe ser un .csv.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo importar el fixture:' + @errores;
        THROW 50001, @errores, 1;
    END;

    /* -------------------------------------------------------------------------
       1. Equivalencias entre los nombres del archivo y los datos del sistema
       ------------------------------------------------------------------------- */
    DECLARE @mapSeleccion TABLE (nombre nvarchar(100) PRIMARY KEY, abreviacion char(3));
    INSERT INTO @mapSeleccion (nombre, abreviacion) VALUES
        (N'Algeria', 'ALG'), (N'Argentina', 'ARG'), (N'Australia', 'AUS'), (N'Austria', 'AUT'),
        (N'Belgium', 'BEL'), (N'Bosnia and Herzegovina', 'BIH'), (N'Brazil', 'BRA'), (N'Cabo Verde', 'CPV'),
        (N'Canada', 'CAN'), (N'Colombia', 'COL'), (N'Congo DR', 'COD'), (N'Croatia', 'CRO'),
        (N'Curaçao', 'CUW'), (N'Czechia', 'CZE'), (N'Côte d''Ivoire', 'CIV'), (N'Ecuador', 'ECU'),
        (N'Egypt', 'EGY'), (N'England', 'ENG'), (N'France', 'FRA'), (N'Germany', 'GER'),
        (N'Ghana', 'GHA'), (N'Haiti', 'HAI'), (N'IR Iran', 'IRN'), (N'Iraq', 'IRQ'),
        (N'Japan', 'JPN'), (N'Jordan', 'JOR'), (N'Korea Republic', 'KOR'), (N'Mexico', 'MEX'),
        (N'Morocco', 'MAR'), (N'Netherlands', 'NED'), (N'New Zealand', 'NZL'), (N'Norway', 'NOR'),
        (N'Panama', 'PAN'), (N'Paraguay', 'PAR'), (N'Portugal', 'POR'), (N'Qatar', 'QAT'),
        (N'Saudi Arabia', 'KSA'), (N'Scotland', 'SCO'), (N'Senegal', 'SEN'), (N'South Africa', 'RSA'),
        (N'Spain', 'ESP'), (N'Sweden', 'SWE'), (N'Switzerland', 'SUI'), (N'Tunisia', 'TUN'),
        (N'Türkiye', 'TUR'), (N'USA', 'USA'), (N'Uruguay', 'URU'), (N'Uzbekistan', 'UZB');

    DECLARE @mapSede TABLE (ubicacion nvarchar(100) PRIMARY KEY, ciudad nvarchar(60));
    INSERT INTO @mapSede (ubicacion, ciudad) VALUES
        (N'Atlanta Stadium', N'Atlanta'), (N'BC Place Vancouver', N'Vancouver'),
        (N'Boston Stadium', N'Foxborough'), (N'Dallas Stadium', N'Arlington'),
        (N'Guadalajara Stadium', N'Zapopan'), (N'Houston Stadium', N'Houston'),
        (N'Kansas City Stadium', N'Kansas City'), (N'Los Angeles Stadium', N'Inglewood'),
        (N'Mexico City Stadium', N'Ciudad de México'), (N'Miami Stadium', N'Miami Gardens'),
        (N'Monterrey Stadium', N'Guadalupe'), (N'New York/New Jersey Stadium', N'East Rutherford'),
        (N'Philadelphia Stadium', N'Philadelphia'), (N'San Francisco Bay Area Stadium', N'Santa Clara'),
        (N'Seattle Stadium', N'Seattle'), (N'Toronto Stadium', N'Toronto');

    /* -------------------------------------------------------------------------
       2. Lectura del archivo a una tabla temporal, todo como texto
       ------------------------------------------------------------------------- */
    CREATE TABLE #csv (matchNumber nvarchar(50), ronda nvarchar(50), fecha nvarchar(50), ubicacion nvarchar(100),
                       equipoLocal nvarchar(100), equipoVisitante nvarchar(100), grupo nvarchar(50),
                       resultado nvarchar(50));

    -- SQL dinámico justificado: BULK INSERT no acepta el nombre del archivo como variable
    SET @sql = N'BULK INSERT #csv FROM ''' + REPLACE(@rutaArchivo, N'''', N'''''')
             + N''' WITH (FORMAT = ''CSV'', FIRSTROW = 1, CODEPAGE = ''65001'', ROWTERMINATOR = ''0x0a'');';
    BEGIN TRY
        EXEC sys.sp_executesql @sql;
    END TRY
    BEGIN CATCH
        SET @errores = N'No se pudo leer el archivo ' + @rutaArchivo + N': ' + ERROR_MESSAGE();
        THROW 50003, @errores, 1;
    END CATCH;

    -- El orden físico de una tabla recién cargada es el orden del archivo: fila 1 es el encabezado.
    -- Un campo vacío llega como NULL: se pasa a texto vacío para que las validaciones no lo pierdan.
    SELECT ROW_NUMBER() OVER (ORDER BY %%physloc%%) AS fila,
           ISNULL(TRIM(REPLACE(REPLACE(matchNumber, NCHAR(65279), N''), CHAR(13), N'')), N'') AS matchNumber,
           ISNULL(TRIM(REPLACE(ronda, CHAR(13), N'')), N'') AS ronda,
           ISNULL(TRIM(REPLACE(fecha, CHAR(13), N'')), N'') AS fecha,
           ISNULL(TRIM(REPLACE(ubicacion, CHAR(13), N'')), N'') AS ubicacion,
           ISNULL(TRIM(REPLACE(equipoLocal, CHAR(13), N'')), N'') AS equipoLocal,
           ISNULL(TRIM(REPLACE(equipoVisitante, CHAR(13), N'')), N'') AS equipoVisitante,
           ISNULL(TRIM(REPLACE(grupo, CHAR(13), N'')), N'') AS grupo,
           ISNULL(TRIM(REPLACE(resultado, CHAR(13), N'')), N'') AS resultado,
           CAST(NULL AS int) AS nro, CAST(NULL AS datetime2(0)) AS fechaUTC, CAST(NULL AS int) AS idSede,
           CAST(NULL AS int) AS idLocal, CAST(NULL AS int) AS idVisitante, CAST(NULL AS int) AS idFase,
           CAST(NULL AS tinyint) AS golLocal, CAST(NULL AS tinyint) AS golVisitante,
           CAST(N'' AS nvarchar(2000)) AS error
    INTO #fix
    FROM #csv;

    IF NOT EXISTS (SELECT 1 FROM #fix WHERE fila = 1 AND matchNumber = N'Match Number' AND ronda = N'Round Number'
                   AND fecha = N'Date' AND ubicacion = N'Location' AND equipoLocal = N'Home Team'
                   AND equipoVisitante = N'Away Team' AND grupo = N'Group' AND resultado = N'Result')
    BEGIN
        SET @errores = N'El archivo ' + @rutaArchivo + N' no tiene el encabezado esperado: '
                     + N'Match Number,Round Number,Date,Location,Home Team,Away Team,Group,Result.';
        THROW 50003, @errores, 1;
    END;

    -- Las líneas vacías (por ejemplo la del final del archivo) no son datos
    DELETE FROM #fix
    WHERE fila > 1 AND CONCAT(matchNumber, ronda, fecha, ubicacion, equipoLocal, equipoVisitante, grupo, resultado) = N'';

    /* -------------------------------------------------------------------------
       3. Validación fila por fila: cada condición que falla suma una línea
       ------------------------------------------------------------------------- */
    UPDATE #fix
    SET nro = TRY_CAST(matchNumber AS int),
        fechaUTC = TRY_CONVERT(datetime2(0), NULLIF(fecha, N''), 103),
        golLocal = CASE WHEN resultado LIKE N'%[0-9] - [0-9]%'
                        THEN TRY_CAST(LEFT(resultado, CHARINDEX(N' - ', resultado) - 1) AS tinyint) END,
        golVisitante = CASE WHEN resultado LIKE N'%[0-9] - [0-9]%'
                            THEN TRY_CAST(SUBSTRING(resultado, CHARINDEX(N' - ', resultado) + 3, 10) AS tinyint) END
    WHERE fila > 1;

    UPDATE #fix SET error += CHAR(10) + N'- El número de partido no es un entero mayor a cero.'
    WHERE fila > 1 AND (nro IS NULL OR nro <= 0);

    UPDATE f SET error += CHAR(10) + N'- El número de partido ' + CAST(f.nro AS nvarchar(10))
                        + N' ya figura en la fila ' + CAST(p.primera AS nvarchar(10)) + N' del archivo.'
    FROM #fix f
    JOIN (SELECT nro, MIN(fila) AS primera FROM #fix WHERE fila > 1 AND nro > 0 GROUP BY nro) p ON p.nro = f.nro
    WHERE f.fila > p.primera;

    UPDATE #fix SET error += CHAR(10) + N'- La fecha no tiene el formato dd/MM/aaaa HH:mm.'
    WHERE fila > 1 AND fechaUTC IS NULL;

    UPDATE #fix SET error += CHAR(10) + N'- El resultado no tiene el formato "goles - goles".'
    WHERE fila > 1 AND resultado <> N'' AND (golLocal IS NULL OR golVisitante IS NULL);

    -- Sede: nombre conocido y cargada en el sistema
    UPDATE f SET idSede = s.idSede
    FROM #fix f JOIN @mapSede m ON m.ubicacion = f.ubicacion JOIN Torneo.Sede s ON s.ciudad = m.ciudad
    WHERE f.fila > 1;

    UPDATE #fix SET error += CHAR(10) + N'- La sede "' + ubicacion + N'" no es una sede conocida o no está cargada.'
    WHERE fila > 1 AND idSede IS NULL;

    -- Selecciones: nombre conocido y cargada en el sistema
    UPDATE f SET idLocal = s.id
    FROM #fix f JOIN @mapSeleccion m ON m.nombre = f.equipoLocal JOIN Equipos.Seleccion s ON s.abreviacion = m.abreviacion
    WHERE f.fila > 1;

    UPDATE f SET idVisitante = s.id
    FROM #fix f JOIN @mapSeleccion m ON m.nombre = f.equipoVisitante JOIN Equipos.Seleccion s ON s.abreviacion = m.abreviacion
    WHERE f.fila > 1;

    UPDATE f SET error += CHAR(10) + N'- La selección local "' + f.equipoLocal
                        + CASE WHEN m.nombre IS NULL THEN N'" no es una selección conocida.'
                               ELSE N'" no está cargada en el sistema.' END
    FROM #fix f LEFT JOIN @mapSeleccion m ON m.nombre = f.equipoLocal
    WHERE f.fila > 1 AND f.idLocal IS NULL;

    UPDATE f SET error += CHAR(10) + N'- La selección visitante "' + f.equipoVisitante
                        + CASE WHEN m.nombre IS NULL THEN N'" no es una selección conocida.'
                               ELSE N'" no está cargada en el sistema.' END
    FROM #fix f LEFT JOIN @mapSeleccion m ON m.nombre = f.equipoVisitante
    WHERE f.fila > 1 AND f.idVisitante IS NULL;

    UPDATE #fix SET error += CHAR(10) + N'- La selección local y la visitante deben ser distintas.'
    WHERE fila > 1 AND idLocal = idVisitante;

    -- Fase: la ronda del archivo se traduce al orden de Torneo.Fase (la final y el tercer puesto
    -- vienen los dos como "Finals"; el partido 103 es el del tercer puesto)
    UPDATE f SET idFase = fa.idFase
    FROM #fix f
    JOIN Torneo.Fase fa ON fa.orden = CASE WHEN f.ronda IN (N'1', N'2', N'3') THEN 1
                                           WHEN f.ronda = N'Round of 32' THEN 2
                                           WHEN f.ronda = N'Round of 16' THEN 3
                                           WHEN f.ronda = N'Quarter Finals' THEN 4
                                           WHEN f.ronda = N'Semi Finals' THEN 5
                                           WHEN f.ronda = N'Finals' AND f.nro = 103 THEN 6
                                           WHEN f.ronda = N'Finals' THEN 7 END
    WHERE f.fila > 1;

    UPDATE #fix SET error += CHAR(10) + N'- La ronda "' + ronda + N'" no es válida o su fase no está cargada.'
    WHERE fila > 1 AND idFase IS NULL;

    /* -------------------------------------------------------------------------
       4. Filas inválidas a Sistema.ErrorImportacion
       ------------------------------------------------------------------------- */
    -- Los errores de una corrida anterior del mismo archivo se reemplazan, para que reimportar no los duplique
    DELETE FROM Sistema.ErrorImportacion WHERE archivo = @rutaArchivo AND tablaDestino = 'Torneo.Partido';

    INSERT INTO Sistema.ErrorImportacion (archivo, tablaDestino, nroFila, datoOriginal, mensajeError)
    SELECT @rutaArchivo, 'Torneo.Partido', fila,
           CONCAT_WS(N',', matchNumber, ronda, fecha, ubicacion, equipoLocal, equipoVisitante, grupo, resultado),
           N'No se pudo importar el partido:' + error
    FROM #fix
    WHERE fila > 1 AND error <> N'';
    SET @conError = @@ROWCOUNT;
    SET @total = (SELECT COUNT(*) FROM #fix WHERE fila > 1);

    /* -------------------------------------------------------------------------
       5. Upsert de las filas válidas a través del ABM
       ------------------------------------------------------------------------- */
    SET @fila = 1;
    WHILE 1 = 1
    BEGIN
        SELECT @fila = MIN(fila) FROM #fix WHERE fila > @fila AND error = N'';
        IF @fila IS NULL BREAK;

        SELECT @nro = nro, @fechaUTC = fechaUTC, @idSede = idSede, @idLocal = idLocal, @idVisitante = idVisitante,
               @idFase = idFase, @golLocal = golLocal, @golVisitante = golVisitante,
               @hayResultado = CASE WHEN resultado = N'' THEN 0 ELSE 1 END
        FROM #fix WHERE fila = @fila;

        BEGIN TRY
            SET @idPartido = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = @nro);

            IF @idPartido IS NULL
            BEGIN
                SET @estado = CASE WHEN @hayResultado = 1 THEN 'Finalizado' ELSE 'Programado' END;
                EXEC Torneo.Partido_Alta @idSede = @idSede, @idSeleccionLocal = @idLocal,
                     @idSeleccionVisitante = @idVisitante, @fase = @idFase, @fechaHoraUTC = @fechaUTC,
                     @estado = @estado, @nroPartidoOficial = @nro, @golLocal = @golLocal,
                     @golVisitante = @golVisitante;
                SET @insertados += 1;
            END
            ELSE
            BEGIN
                DELETE FROM @act;
                INSERT INTO @act
                SELECT idSede, idSeleccionLocal, idSeleccionVisitante, fase, fechaHoraUTC, estado, golLocal,
                       golVisitante, cantPublico, esquemaLocal, esquemaVisitante
                FROM Torneo.Partido WHERE idPartido = @idPartido;

                -- Sin resultado en el archivo se conserva el que ya tenía el partido
                IF @hayResultado = 1
                    SET @estado = 'Finalizado';
                ELSE
                    SELECT @estado = estado, @golLocal = golLocal, @golVisitante = golVisitante FROM @act;

                IF EXISTS (SELECT 1 FROM @act WHERE idSede = @idSede AND idLocal = @idLocal
                           AND idVisitante = @idVisitante AND idFase = @idFase AND fechaUTC = @fechaUTC
                           AND estado = @estado AND ISNULL(golLocal, 255) = ISNULL(@golLocal, 255)
                           AND ISNULL(golVisitante, 255) = ISNULL(@golVisitante, 255))
                    SET @sinCambios += 1;
                ELSE
                BEGIN
                    SELECT @publico = publico, @esquemaLocal = esquemaLocal, @esquemaVisitante = esquemaVisitante
                    FROM @act;
                    EXEC Torneo.Partido_Modificacion @idPartido = @idPartido, @idSede = @idSede,
                         @idSeleccionLocal = @idLocal, @idSeleccionVisitante = @idVisitante, @fase = @idFase,
                         @fechaHoraUTC = @fechaUTC, @estado = @estado, @nroPartidoOficial = @nro,
                         @cantPublico = @publico, @golLocal = @golLocal, @golVisitante = @golVisitante,
                         @esquemaLocal = @esquemaLocal, @esquemaVisitante = @esquemaVisitante;
                    SET @actualizados += 1;
                END;
            END;
        END TRY
        BEGIN CATCH
            INSERT INTO Sistema.ErrorImportacion (archivo, tablaDestino, nroFila, datoOriginal, mensajeError)
            SELECT @rutaArchivo, 'Torneo.Partido', fila,
                   CONCAT_WS(N',', matchNumber, ronda, fecha, ubicacion, equipoLocal, equipoVisitante, grupo, resultado),
                   ERROR_MESSAGE()
            FROM #fix WHERE fila = @fila;
            SET @conError += 1;
        END CATCH;
    END;

    SELECT @total AS filasLeidas, @insertados AS insertados, @actualizados AS actualizados,
           @sinCambios AS sinCambios, @conError AS conError;
END
GO
