/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 09/11/2026

 Objetivo    : Carga de datos base (seed) para el esquema Publicidad.
               Usa los datos reales del torneo que cargan 50a, 50b y 50c
               (fases, sedes, selecciones y los 31 partidos) y agrega solo los
               países de mercado de los anunciantes que faltan.
               Claves propias en Sistema.Parametro:
                 PRIME_TIME_INICIO, PRIME_TIME_FIN, MAX_ESPACIOS_PARTIDO
               Caso obligatorio: la Final real (partido 104, España–Argentina,
               2026-07-19 19:00 UTC) cae en prime time en 7 mercados candidatos.

 DEPENDENCIAS Y ORDEN:
 ---------------------
 Corre después de 10a (SP de Torneo), 12 (SP de Publicidad), 22 (funciones de
 prime time) y 50a, 50b y 50c. Todas las altas pasan por los SP: no hay INSERT
 directo en ninguna tabla. Cada alta verifica antes si el registro ya existe,
 así que el script se puede ejecutar varias veces sin duplicar datos.
 AsignarPiezasPartido solo acepta partidos Programado o En juego, y 53 deja los
 31 partidos Finalizado: para asignar piezas a partidos reales (por ejemplo la
 Final) hay que ejecutar la asignación antes de 53.
================================================================================
*/

USE MundialFutbol;

GO

SET NOCOUNT ON;

GO

/* ======= SECCION 1: Sistema.Parametro — claves propias de Publicidad ======= */
/*
   Sistema.Parametro es una tabla compartida (PK = clave varchar).
   Se usan MERGEs para que el script sea idempotente: si la clave ya existe,
   no hace nada; si no existe, la inserta.
*/

MERGE Sistema.Parametro AS destino
USING (
    VALUES
        ('PRIME_TIME_INICIO',    19, 'Hora de inicio del horario prime time (hora local del mercado)'),
        ('PRIME_TIME_FIN',       23, 'Hora de fin del horario prime time (hora local del mercado, inclusive)'),
        ('MAX_ESPACIOS_PARTIDO',  4, 'Máximo de piezas publicitarias asignables por partido')
) AS origen (clave, valor, descripcion)
ON destino.clave = origen.clave
WHEN NOT MATCHED THEN
    INSERT (clave, valor, descripcion)
    VALUES (origen.clave, origen.valor, origen.descripcion);

GO

/* ======= SECCION 2: Publicidad.UbicacionPublicitaria — 4 espacios del estadio ======= */
/*
   Se usa EXEC Publicidad.UbicacionPublicitaria_Alta.
   El SP valida que el idUbicacion no exista, por lo que se envuelve cada
   llamada en un IF NOT EXISTS para evitar errores en ejecuciones repetidas.
*/

IF NOT EXISTS (SELECT 1 FROM Publicidad.UbicacionPublicitaria WHERE idUbicacion = 1)
    EXEC Publicidad.UbicacionPublicitaria_Alta
        @idUbicacion = 1,
        @nombre      = 'Cartel Principal',
        @descripcion = 'Panel LED principal ubicado detrás de los arcos';

IF NOT EXISTS (SELECT 1 FROM Publicidad.UbicacionPublicitaria WHERE idUbicacion = 2)
    EXEC Publicidad.UbicacionPublicitaria_Alta
        @idUbicacion = 2,
        @nombre      = 'Perimetral Norte',
        @descripcion = 'Cartel perimetral lado norte del campo';

IF NOT EXISTS (SELECT 1 FROM Publicidad.UbicacionPublicitaria WHERE idUbicacion = 3)
    EXEC Publicidad.UbicacionPublicitaria_Alta
        @idUbicacion = 3,
        @nombre      = 'Perimetral Sur',
        @descripcion = 'Cartel perimetral lado sur del campo';

IF NOT EXISTS (SELECT 1 FROM Publicidad.UbicacionPublicitaria WHERE idUbicacion = 4)
    EXEC Publicidad.UbicacionPublicitaria_Alta
        @idUbicacion = 4,
        @nombre      = 'Pantalla Gigante',
        @descripcion = 'Pantalla LED gigante visible para las cámaras de TV';

GO

/* ======= SECCION 3: Datos de apoyo — verificación de la carga real y países de mercado ======= */
/*
   El torneo (7 fases, 16 sedes, 16 selecciones y los 31 partidos) lo cargan 50a, 50b
   y 50c con los SP de Torneo y Equipos. Este script usa esos datos reales: no inserta
   fases, sedes, selecciones ni partidos propios.

   Lo único que falta son los países de mercado de los anunciantes que no juegan los
   partidos cargados (Brasil, Alemania, Italia, Países Bajos, Portugal y Japón). Se dan
   de alta con Torneo.Pais_Alta. A los que ya existen (Argentina, España, Francia y
   Reino Unido, que 50a carga como Inglaterra) se les completa el PBI con
   Torneo.Pais_Modificacion solo si está en NULL, para no pisar el valor que cargue
   la API del Banco Mundial.

   CASO OBLIGATORIO: la Final real (partido 104, España–Argentina) es el 2026-07-19 a las
   19:00 UTC. Con el horario de verano europeo, la hora local en cada mercado es:
     - Alemania    (UTC+2, 'W. Europe Standard Time')   → 21:00  PRIME TIME
     - España      (UTC+2, 'Romance Standard Time')     → 21:00  PRIME TIME
     - Francia     (UTC+2, 'Romance Standard Time')     → 21:00  PRIME TIME
     - Italia      (UTC+2, 'W. Europe Standard Time')   → 21:00  PRIME TIME
     - Países Bajos (UTC+2, 'W. Europe Standard Time')  → 21:00  PRIME TIME
     - Portugal    (UTC+1, 'GMT Standard Time')         → 20:00  PRIME TIME
     - Reino Unido (UTC+1, 'GMT Standard Time')         → 20:00  PRIME TIME
     - Argentina y Brasil (UTC-3)                       → 16:00  no
     - Japón       (UTC+9)                              → 04:00  no
   Son 7 mercados en prime time simultáneo, más que los 4 espacios por partido: se
   activa la priorización del SP AsignarPiezasPartido.
*/

IF (SELECT COUNT(*) FROM Torneo.Fase WHERE idFase BETWEEN 1 AND 7) < 7
   OR NOT EXISTS (SELECT 1 FROM Torneo.Partido WHERE nroPartidoOficial = 104)
    THROW 50001, N'Faltan las fases o el partido 104 del torneo. Ejecutar antes 50a, 50b y 50c.', 1;

GO

DROP TABLE IF EXISTS #mercados;
CREATE TABLE #mercados (n int IDENTITY(1,1) PRIMARY KEY, nombre nvarchar(60), codigoISO2 char(2),
                        codigoISO3 char(3), husoHorario varchar(50), moneda char(3),
                        pbiPerCapita decimal(12,2), poblacion bigint);
INSERT INTO #mercados (nombre, codigoISO2, codigoISO3, husoHorario, moneda, pbiPerCapita, poblacion) VALUES
    (N'Argentina',    N'AR', N'ARG', N'Argentina Standard Time',        N'ARS', 13700.00,  46000000),
    (N'Brasil',       N'BR', N'BRA', N'E. South America Standard Time', N'BRL',  9100.00, 215000000),
    (N'Alemania',     N'DE', N'DEU', N'W. Europe Standard Time',        N'EUR', 51200.00,  84000000),
    (N'España',       N'ES', N'ESP', N'Romance Standard Time',          N'EUR', 30100.00,  47000000),
    (N'Francia',      N'FR', N'FRA', N'Romance Standard Time',          N'EUR', 44000.00,  68000000),
    (N'Italia',       N'IT', N'ITA', N'W. Europe Standard Time',        N'EUR', 36000.00,  59000000),
    (N'Países Bajos', N'NL', N'NLD', N'W. Europe Standard Time',        N'EUR', 60000.00,  17900000),
    (N'Portugal',     N'PT', N'PRT', N'GMT Standard Time',              N'EUR', 25000.00,  10300000),
    (N'Reino Unido',  N'GB', N'GBR', N'GMT Standard Time',              N'GBP', 46200.00,  67000000),
    (N'Japón',        N'JP', N'JPN', N'Tokyo Standard Time',            N'JPY', 42200.00, 125000000);

DECLARE @nombre nvarchar(60), @iso2 char(2), @iso3 char(3), @huso varchar(50), @moneda char(3),
        @pbi decimal(12,2), @poblacion bigint, @idPais int;
DECLARE @nombreAct nvarchar(60), @iso2Act char(2), @iso3Act char(3), @husoAct varchar(50),
        @monedaAct char(3), @poblacionAct bigint;
DECLARE @n int = 1, @max int = (SELECT MAX(n) FROM #mercados);
WHILE @n <= @max
BEGIN
    SELECT @nombre = nombre, @iso2 = codigoISO2, @iso3 = codigoISO3, @huso = husoHorario,
           @moneda = moneda, @pbi = pbiPerCapita, @poblacion = poblacion
    FROM #mercados WHERE n = @n;
    BEGIN TRY
        SET @idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO3 = @iso3);
        IF @idPais IS NULL
            EXEC Torneo.Pais_Alta @nombre = @nombre, @codigoISO2 = @iso2, @codigoISO3 = @iso3,
                 @husoHorario = @huso, @moneda = @moneda, @pbiPerCapita = @pbi, @poblacion = @poblacion;
        ELSE IF EXISTS (SELECT 1 FROM Torneo.Pais WHERE id = @idPais AND pbiPerCapita IS NULL)
        BEGIN
            -- El país ya lo cargó 50a sin PBI: se completa conservando el resto de sus datos
            SELECT @nombreAct = nombre, @iso2Act = codigoISO2, @iso3Act = codigoISO3,
                   @husoAct = husoHorario, @monedaAct = moneda, @poblacionAct = poblacion
            FROM Torneo.Pais WHERE id = @idPais;
            SET @poblacionAct = ISNULL(@poblacionAct, @poblacion);
            EXEC Torneo.Pais_Modificacion @id = @idPais, @nombre = @nombreAct, @codigoISO2 = @iso2Act,
                 @codigoISO3 = @iso3Act, @husoHorario = @husoAct, @moneda = @monedaAct,
                 @pbiPerCapita = @pbi, @poblacion = @poblacionAct;
        END;
    END TRY
    BEGIN CATCH
        PRINT 'Error al cargar el país de la fila ' + CAST(@n AS varchar(10)) + ' de #mercados.';
        THROW;
    END CATCH;
    SET @n += 1;
END;

GO

/* ======= SECCION 4: Publicidad.Tarifa — 7 fases × 4 ubicaciones (28 tarifas) ======= */
/*
   Se usa EXEC Publicidad.Tarifa_Alta.
   El SP valida que el par (idFase, idUbicacion) no exista, por lo que
   se envuelve cada llamada en IF NOT EXISTS.
   Las fases se buscan por nombre en Torneo.Fase (los 7 nombres de 50a) y no por id,
   así cada tarifa queda en la fase correcta: el tercer puesto (fase 6) y la Final
   (fase 7) tienen tarifas propias.
*/

DROP TABLE IF EXISTS #tarifas;
CREATE TABLE #tarifas (n int IDENTITY(1,1) PRIMARY KEY, nombreFase varchar(60),
                       idUbicacion tinyint, montoUSD decimal(12,2));
INSERT INTO #tarifas (nombreFase, idUbicacion, montoUSD) VALUES
    ('Fase de grupos',          1,  50000.00), ('Fase de grupos',          2,  35000.00),
    ('Fase de grupos',          3,  35000.00), ('Fase de grupos',          4,  80000.00),
    ('Dieciseisavos de final',  1,  60000.00), ('Dieciseisavos de final',  2,  42000.00),
    ('Dieciseisavos de final',  3,  42000.00), ('Dieciseisavos de final',  4,  96000.00),
    ('Octavos de final',        1,  70000.00), ('Octavos de final',        2,  50000.00),
    ('Octavos de final',        3,  50000.00), ('Octavos de final',        4, 112000.00),
    ('Cuartos de final',        1,  90000.00), ('Cuartos de final',        2,  65000.00),
    ('Cuartos de final',        3,  65000.00), ('Cuartos de final',        4, 145000.00),
    ('Semifinal',               1, 120000.00), ('Semifinal',               2,  85000.00),
    ('Semifinal',               3,  85000.00), ('Semifinal',               4, 190000.00),
    ('Tercer puesto',           1, 100000.00), ('Tercer puesto',           2,  70000.00),
    ('Tercer puesto',           3,  70000.00), ('Tercer puesto',           4, 160000.00),
    ('Final',                   1, 200000.00), ('Final',                   2, 140000.00),
    ('Final',                   3, 140000.00), ('Final',                   4, 320000.00);

DECLARE @idFase int, @idUbicacion tinyint, @montoUSD decimal(12,2);
DECLARE @n int = 1, @max int = (SELECT MAX(n) FROM #tarifas);
WHILE @n <= @max
BEGIN
    SELECT @idFase = NULL;
    SELECT @idFase = f.idFase, @idUbicacion = t.idUbicacion, @montoUSD = t.montoUSD
    FROM #tarifas t
    JOIN Torneo.Fase f ON f.nombre = t.nombreFase
    WHERE t.n = @n;
    BEGIN TRY
        IF @idFase IS NULL
            THROW 50001, N'La fase de la tarifa no existe en Torneo.Fase.', 1;
        IF NOT EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = @idFase AND idUbicacion = @idUbicacion)
            EXEC Publicidad.Tarifa_Alta @idFase = @idFase, @idUbicacion = @idUbicacion, @montoUSD = @montoUSD;
    END TRY
    BEGIN CATCH
        PRINT 'Error al cargar la tarifa de la fila ' + CAST(@n AS varchar(10)) + ' de #tarifas.';
        THROW;
    END CATCH;
    SET @n += 1;
END;

GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
DECLARE @idPais_AR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'AR');
DECLARE @idPais_BR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'BR');
DECLARE @idPais_DE int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'DE');
DECLARE @idPais_JP int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'JP');
DECLARE @idPais_FR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'FR');
DECLARE @idPais_IT int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'IT');
DECLARE @idPais_ES int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'ES');
DECLARE @idPais_NL int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'NL');
DECLARE @idPais_GB int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'GB');
DECLARE @idPais_PT int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'PT');

/* ======= SECCION 5: Publicidad.Anunciante — 8 anunciantes de distintos países ======= */
/*
   Se usa EXEC Publicidad.Anunciante_Alta.
   El SP valida duplicidad de nombre, por lo que se envuelve en IF NOT EXISTS.
   Todos los anunciantes son de países ya insertados en Torneo.Pais.
*/

-- Adidas (Alemania - Indumentaria Deportiva)
IF NOT EXISTS (SELECT 1 FROM Publicidad.Anunciante WHERE nombre = N'Adidas')
    EXEC Publicidad.Anunciante_Alta
        @nombre            = N'Adidas',
        @rubro             = 'Indumentaria Deportiva',
        @idPais = @idPais_DE,
        @monedaFacturacion = 'EUR';

-- YPF (Argentina - Energía)
IF NOT EXISTS (SELECT 1 FROM Publicidad.Anunciante WHERE nombre = N'YPF')
    EXEC Publicidad.Anunciante_Alta
        @nombre            = N'YPF',
        @rubro             = 'Energia',
        @idPais = @idPais_AR,
        @monedaFacturacion = 'ARS';

-- Petrobras (Brasil - Energía)
IF NOT EXISTS (SELECT 1 FROM Publicidad.Anunciante WHERE nombre = N'Petrobras')
    EXEC Publicidad.Anunciante_Alta
        @nombre            = N'Petrobras',
        @rubro             = 'Energia',
        @idPais = @idPais_BR,
        @monedaFacturacion = 'BRL';

-- Sony (Japón - Electrónica)
IF NOT EXISTS (SELECT 1 FROM Publicidad.Anunciante WHERE nombre = N'Sony')
    EXEC Publicidad.Anunciante_Alta
        @nombre            = N'Sony',
        @rubro             = 'Electronica',
        @idPais = @idPais_JP,
        @monedaFacturacion = 'JPY';

-- L Oreal (Francia - Cosmética)
IF NOT EXISTS (SELECT 1 FROM Publicidad.Anunciante WHERE nombre = N'L Oreal')
    EXEC Publicidad.Anunciante_Alta
        @nombre            = N'L Oreal',
        @rubro             = 'Cosmetica',
        @idPais = @idPais_FR,
        @monedaFacturacion = 'EUR';

-- Ferrari (Italia - Automotriz)
IF NOT EXISTS (SELECT 1 FROM Publicidad.Anunciante WHERE nombre = N'Ferrari')
    EXEC Publicidad.Anunciante_Alta
        @nombre            = N'Ferrari',
        @rubro             = 'Automotriz',
        @idPais = @idPais_IT,
        @monedaFacturacion = 'EUR';

-- Zara (España - Moda)
IF NOT EXISTS (SELECT 1 FROM Publicidad.Anunciante WHERE nombre = N'Zara')
    EXEC Publicidad.Anunciante_Alta
        @nombre            = N'Zara',
        @rubro             = 'Moda',
        @idPais = @idPais_ES,
        @monedaFacturacion = 'EUR';

-- Heineken (Países Bajos - Bebidas)
IF NOT EXISTS (SELECT 1 FROM Publicidad.Anunciante WHERE nombre = N'Heineken')
    EXEC Publicidad.Anunciante_Alta
        @nombre            = N'Heineken',
        @rubro             = 'Bebidas',
        @idPais = @idPais_NL,
        @monedaFacturacion = 'EUR';

GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
DECLARE @idAnunc_Adidas int = (SELECT id FROM Publicidad.Anunciante WHERE nombre = N'Adidas');
DECLARE @idAnunc_YPF int = (SELECT id FROM Publicidad.Anunciante WHERE nombre = N'YPF');
DECLARE @idAnunc_Petrobras int = (SELECT id FROM Publicidad.Anunciante WHERE nombre = N'Petrobras');
DECLARE @idAnunc_Sony int = (SELECT id FROM Publicidad.Anunciante WHERE nombre = N'Sony');
DECLARE @idAnunc_L_Oreal int = (SELECT id FROM Publicidad.Anunciante WHERE nombre = N'L Oreal');
DECLARE @idAnunc_Ferrari int = (SELECT id FROM Publicidad.Anunciante WHERE nombre = N'Ferrari');
DECLARE @idAnunc_Zara int = (SELECT id FROM Publicidad.Anunciante WHERE nombre = N'Zara');
DECLARE @idAnunc_Heineken int = (SELECT id FROM Publicidad.Anunciante WHERE nombre = N'Heineken');
/* ======= SECCION 6: Publicidad.Campania — una campaña por anunciante ======= */
/*
   Se usa EXEC Publicidad.Campania_Alta.
   No hay restricción UNIQUE en Campania (distintos anunciantes pueden tener
   campañas con el mismo nombre), por lo que el IF NOT EXISTS se hace por
   combinación (idAnunciante, nombre).
*/

-- Campaña Adidas
IF NOT EXISTS (
    SELECT 1 FROM Publicidad.Campania
    WHERE idAnunciante = (SELECT id FROM Publicidad.Anunciante WHERE nombre = N'Adidas')
      AND nombre       = N'Adidas Mundial 2026'
)
    EXEC Publicidad.Campania_Alta
        @idAnunciante = @idAnunc_Adidas,
        @nombre       = N'Adidas Mundial 2026',
        @fechaInicio  = '2026-06-01',
        @fechaFin     = '2026-07-31';

-- Campaña YPF
IF NOT EXISTS (
    SELECT 1 FROM Publicidad.Campania
    WHERE idAnunciante = (SELECT id FROM Publicidad.Anunciante WHERE nombre = N'YPF')
      AND nombre       = N'YPF Energia del Juego'
)
    EXEC Publicidad.Campania_Alta
        @idAnunciante = @idAnunc_YPF,
        @nombre       = N'YPF Energia del Juego',
        @fechaInicio  = '2026-06-01',
        @fechaFin     = '2026-07-31';

-- Campaña Petrobras
IF NOT EXISTS (
    SELECT 1 FROM Publicidad.Campania
    WHERE idAnunciante = (SELECT id FROM Publicidad.Anunciante WHERE nombre = N'Petrobras')
      AND nombre       = N'Petrobras Forca Brasil'
)
    EXEC Publicidad.Campania_Alta
        @idAnunciante = @idAnunc_Petrobras,
        @nombre       = N'Petrobras Forca Brasil',
        @fechaInicio  = '2026-06-01',
        @fechaFin     = '2026-07-31';

-- Campaña Sony
IF NOT EXISTS (
    SELECT 1 FROM Publicidad.Campania
    WHERE idAnunciante = (SELECT id FROM Publicidad.Anunciante WHERE nombre = N'Sony')
      AND nombre       = N'Sony Vive el Momento'
)
    EXEC Publicidad.Campania_Alta
        @idAnunciante = @idAnunc_Sony,
        @nombre       = N'Sony Vive el Momento',
        @fechaInicio  = '2026-06-01',
        @fechaFin     = '2026-07-31';

-- Campaña L Oreal
IF NOT EXISTS (
    SELECT 1 FROM Publicidad.Campania
    WHERE idAnunciante = (SELECT id FROM Publicidad.Anunciante WHERE nombre = N'L Oreal')
      AND nombre       = N'L Oreal Brilla en el Mundial'
)
    EXEC Publicidad.Campania_Alta
        @idAnunciante = @idAnunc_L_Oreal,
        @nombre       = N'L Oreal Brilla en el Mundial',
        @fechaInicio  = '2026-06-01',
        @fechaFin     = '2026-07-31';

-- Campaña Ferrari
IF NOT EXISTS (
    SELECT 1 FROM Publicidad.Campania
    WHERE idAnunciante = (SELECT id FROM Publicidad.Anunciante WHERE nombre = N'Ferrari')
      AND nombre       = N'Ferrari Pasion por la Velocidad'
)
    EXEC Publicidad.Campania_Alta
        @idAnunciante = @idAnunc_Ferrari,
        @nombre       = N'Ferrari Pasion por la Velocidad',
        @fechaInicio  = '2026-06-01',
        @fechaFin     = '2026-07-31';

-- Campaña Zara
IF NOT EXISTS (
    SELECT 1 FROM Publicidad.Campania
    WHERE idAnunciante = (SELECT id FROM Publicidad.Anunciante WHERE nombre = N'Zara')
      AND nombre       = N'Zara Style Mundial'
)
    EXEC Publicidad.Campania_Alta
        @idAnunciante = @idAnunc_Zara,
        @nombre       = N'Zara Style Mundial',
        @fechaInicio  = '2026-06-01',
        @fechaFin     = '2026-07-31';

-- Campaña Heineken
IF NOT EXISTS (
    SELECT 1 FROM Publicidad.Campania
    WHERE idAnunciante = (SELECT id FROM Publicidad.Anunciante WHERE nombre = N'Heineken')
      AND nombre       = N'Heineken Brindis Mundial'
)
    EXEC Publicidad.Campania_Alta
        @idAnunciante = @idAnunc_Heineken,
        @nombre       = N'Heineken Brindis Mundial',
        @fechaInicio  = '2026-06-01',
        @fechaFin     = '2026-07-31';

GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
DECLARE @idCamp_Adidas int = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Adidas Mundial 2026');
DECLARE @idCamp_YPF int = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'YPF Energia del Juego');
DECLARE @idCamp_Petrobras int = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Petrobras Forca Brasil');
DECLARE @idCamp_Sony int = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Sony Play the World');
DECLARE @idCamp_L int = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'L Oreal Belleza Global');
DECLARE @idCamp_Ferrari int = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Ferrari Passione Mondiale');
DECLARE @idCamp_Zara int = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Zara Pasarela Mundial');
DECLARE @idCamp_Heineken int = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Heineken Cheers to the Cup');
DECLARE @idCampania_current int;
/* ======= SECCION 7: Publicidad.PiezaContenido — 2 piezas por campaña ======= */
/*
   Se usa EXEC Publicidad.PiezaContenido_Alta.
   No hay UNIQUE en PiezaContenido, por lo que el IF NOT EXISTS verifica la
   combinación (idCampania, descripcion, idioma).
   Idiomas: 'es' español, 'de' alemán, 'pt' portugués, 'ja' japonés,
            'fr' francés, 'it' italiano, 'nl' neerlandés, 'en' inglés.
*/

-- ── Adidas (campania: 'Adidas Mundial 2026') ───────────────────────────────
-- Pieza 1 en español
IF NOT EXISTS (
    SELECT 1 FROM Publicidad.PiezaContenido
    WHERE idCampania  = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Adidas Mundial 2026')
      AND descripcion = N'Adidas - Impossible is Nothing (es)'
      AND idioma      = 'es'
)
    EXEC Publicidad.PiezaContenido_Alta
        @idCampania  = @idCamp_Adidas,
        @descripcion = N'Adidas - Impossible is Nothing (es)',
        @idioma      = 'es';

-- Pieza 2 en alemán
IF NOT EXISTS (
    SELECT 1 FROM Publicidad.PiezaContenido
    WHERE idCampania  = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Adidas Mundial 2026')
      AND descripcion = N'Adidas - Impossible is Nothing (de)'
      AND idioma      = 'de'
)
    EXEC Publicidad.PiezaContenido_Alta
        @idCampania  = @idCamp_Adidas,
        @descripcion = N'Adidas - Impossible is Nothing (de)',
        @idioma      = 'de';

-- ── YPF (campania: 'YPF Energia del Juego') ────────────────────────────────
IF NOT EXISTS (
    SELECT 1 FROM Publicidad.PiezaContenido
    WHERE idCampania  = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'YPF Energia del Juego')
      AND descripcion = N'YPF - La energia que mueve Argentina (es)'
      AND idioma      = 'es'
)
    EXEC Publicidad.PiezaContenido_Alta
        @idCampania  = @idCamp_YPF,
        @descripcion = N'YPF - La energia que mueve Argentina (es)',
        @idioma      = 'es';

IF NOT EXISTS (
    SELECT 1 FROM Publicidad.PiezaContenido
    WHERE idCampania  = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'YPF Energia del Juego')
      AND descripcion = N'YPF - Orgullo Argentino (es)'
      AND idioma      = 'es'
)
    EXEC Publicidad.PiezaContenido_Alta
        @idCampania  = @idCamp_YPF,
        @descripcion = N'YPF - Orgullo Argentino (es)',
        @idioma      = 'es';

-- ── Petrobras (campania: 'Petrobras Forca Brasil') ─────────────────────────
IF NOT EXISTS (
    SELECT 1 FROM Publicidad.PiezaContenido
    WHERE idCampania  = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Petrobras Forca Brasil')
      AND descripcion = N'Petrobras - Energia para el futbol (es)'
      AND idioma      = 'es'
)
    EXEC Publicidad.PiezaContenido_Alta
        @idCampania  = @idCamp_Petrobras,
        @descripcion = N'Petrobras - Energia para el futbol (es)',
        @idioma      = 'es';

IF NOT EXISTS (
    SELECT 1 FROM Publicidad.PiezaContenido
    WHERE idCampania  = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Petrobras Forca Brasil')
      AND descripcion = N'Petrobras - Forca Brasil (pt)'
      AND idioma      = 'pt'
)
    EXEC Publicidad.PiezaContenido_Alta
        @idCampania  = @idCamp_Petrobras,
        @descripcion = N'Petrobras - Forca Brasil (pt)',
        @idioma      = 'pt';

-- ── Sony (campania: 'Sony Vive el Momento') ────────────────────────────────
IF NOT EXISTS (
    SELECT 1 FROM Publicidad.PiezaContenido
    WHERE idCampania  = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Sony Vive el Momento')
      AND descripcion = N'Sony - Vive cada gol (es)'
      AND idioma      = 'es'
)
BEGIN
    SELECT @idCampania_current = idCampania FROM Publicidad.Campania WHERE nombre = N'Sony Vive el Momento';
    EXEC Publicidad.PiezaContenido_Alta
        @idCampania  = @idCampania_current,
        @descripcion = N'Sony - Vive cada gol (es)',
        @idioma      = 'es';
END;

IF NOT EXISTS (
    SELECT 1 FROM Publicidad.PiezaContenido
    WHERE idCampania  = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Sony Vive el Momento')
      AND descripcion = N'Sony - Feel Every Moment (ja)'
      AND idioma      = 'ja'
)
BEGIN
    SELECT @idCampania_current = idCampania FROM Publicidad.Campania WHERE nombre = N'Sony Vive el Momento';
    EXEC Publicidad.PiezaContenido_Alta
        @idCampania  = @idCampania_current,
        @descripcion = N'Sony - Feel Every Moment (ja)',
        @idioma      = 'ja';
END;

-- ── L Oreal (campania: 'L Oreal Brilla en el Mundial') ────────────────────
IF NOT EXISTS (
    SELECT 1 FROM Publicidad.PiezaContenido
    WHERE idCampania  = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'L Oreal Brilla en el Mundial')
      AND descripcion = N'L Oreal - Porque tu lo vales (es)'
      AND idioma      = 'es'
)
BEGIN
    SELECT @idCampania_current = idCampania FROM Publicidad.Campania WHERE nombre = N'L Oreal Brilla en el Mundial';
    EXEC Publicidad.PiezaContenido_Alta
        @idCampania  = @idCampania_current,
        @descripcion = N'L Oreal - Porque tu lo vales (es)',
        @idioma      = 'es';
END;

IF NOT EXISTS (
    SELECT 1 FROM Publicidad.PiezaContenido
    WHERE idCampania  = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'L Oreal Brilla en el Mundial')
      AND descripcion = N'L Oreal - Parce que je le vaux bien (fr)'
      AND idioma      = 'fr'
)
BEGIN
    SELECT @idCampania_current = idCampania FROM Publicidad.Campania WHERE nombre = N'L Oreal Brilla en el Mundial';
    EXEC Publicidad.PiezaContenido_Alta
        @idCampania  = @idCampania_current,
        @descripcion = N'L Oreal - Parce que je le vaux bien (fr)',
        @idioma      = 'fr';
END;

-- ── Ferrari (campania: 'Ferrari Pasion por la Velocidad') ─────────────────
IF NOT EXISTS (
    SELECT 1 FROM Publicidad.PiezaContenido
    WHERE idCampania  = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Ferrari Pasion por la Velocidad')
      AND descripcion = N'Ferrari - Pasion italiana (es)'
      AND idioma      = 'es'
)
BEGIN
    SELECT @idCampania_current = idCampania FROM Publicidad.Campania WHERE nombre = N'Ferrari Pasion por la Velocidad';
    EXEC Publicidad.PiezaContenido_Alta
        @idCampania  = @idCampania_current,
        @descripcion = N'Ferrari - Pasion italiana (es)',
        @idioma      = 'es';
END;

IF NOT EXISTS (
    SELECT 1 FROM Publicidad.PiezaContenido
    WHERE idCampania  = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Ferrari Pasion por la Velocidad')
      AND descripcion = N'Ferrari - La passione italiana (it)'
      AND idioma      = 'it'
)
BEGIN
    SELECT @idCampania_current = idCampania FROM Publicidad.Campania WHERE nombre = N'Ferrari Pasion por la Velocidad';
    EXEC Publicidad.PiezaContenido_Alta
        @idCampania  = @idCampania_current,
        @descripcion = N'Ferrari - La passione italiana (it)',
        @idioma      = 'it';
END;

-- ── Zara (campania: 'Zara Style Mundial') ─────────────────────────────────
IF NOT EXISTS (
    SELECT 1 FROM Publicidad.PiezaContenido
    WHERE idCampania  = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Zara Style Mundial')
      AND descripcion = N'Zara - Moda en el estadio (es)'
      AND idioma      = 'es'
)
BEGIN
    SELECT @idCampania_current = idCampania FROM Publicidad.Campania WHERE nombre = N'Zara Style Mundial';
    EXEC Publicidad.PiezaContenido_Alta
        @idCampania  = @idCampania_current,
        @descripcion = N'Zara - Moda en el estadio (es)',
        @idioma      = 'es';
END;

IF NOT EXISTS (
    SELECT 1 FROM Publicidad.PiezaContenido
    WHERE idCampania  = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Zara Style Mundial')
      AND descripcion = N'Zara - Estilo sin limites (es)'
      AND idioma      = 'es'
)
BEGIN
    SELECT @idCampania_current = idCampania FROM Publicidad.Campania WHERE nombre = N'Zara Style Mundial';
    EXEC Publicidad.PiezaContenido_Alta
        @idCampania  = @idCampania_current,
        @descripcion = N'Zara - Estilo sin limites (es)',
        @idioma      = 'es';
END;

-- ── Heineken (campania: 'Heineken Brindis Mundial') ────────────────────────
IF NOT EXISTS (
    SELECT 1 FROM Publicidad.PiezaContenido
    WHERE idCampania  = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Heineken Brindis Mundial')
      AND descripcion = N'Heineken - Brindamos por el futbol (es)'
      AND idioma      = 'es'
)
BEGIN
    SELECT @idCampania_current = idCampania FROM Publicidad.Campania WHERE nombre = N'Heineken Brindis Mundial';
    EXEC Publicidad.PiezaContenido_Alta
        @idCampania  = @idCampania_current,
        @descripcion = N'Heineken - Brindamos por el futbol (es)',
        @idioma      = 'es';
END;

IF NOT EXISTS (
    SELECT 1 FROM Publicidad.PiezaContenido
    WHERE idCampania  = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Heineken Brindis Mundial')
      AND descripcion = N'Heineken - Open Your World (nl)'
      AND idioma      = 'nl'
)
BEGIN
    SELECT @idCampania_current = idCampania FROM Publicidad.Campania WHERE nombre = N'Heineken Brindis Mundial';
    EXEC Publicidad.PiezaContenido_Alta
        @idCampania  = @idCampania_current,
        @descripcion = N'Heineken - Open Your World (nl)',
        @idioma      = 'nl';
END;

GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
DECLARE @idPais_AR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'AR');
DECLARE @idPais_BR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'BR');
DECLARE @idPais_DE int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'DE');
DECLARE @idPais_JP int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'JP');
DECLARE @idPais_FR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'FR');
DECLARE @idPais_IT int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'IT');
DECLARE @idPais_ES int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'ES');
DECLARE @idPais_NL int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'NL');
DECLARE @idPais_GB int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'GB');
DECLARE @idPais_PT int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'PT');

/* ======= SECCION 8: Publicidad.PiezaMercado — mercados de cada pieza ======= */
/*
   Se usa EXEC Publicidad.PiezaMercado_Alta.
   El SP valida duplicados (idPieza, idPais), por lo que se envuelve en
   IF NOT EXISTS.
   Se usan variables DECLARE para capturar los IDs de las piezas (IDENTITY)
   obtenidos mediante subquery, agrupados por campaña para mayor claridad.

   CASO OBLIGATORIO — Adidas:
   Las 2 piezas de Adidas tienen mercados en los 7 países europeos en prime time
   (Alemania, España, Francia, Italia, Países Bajos, Portugal, Reino Unido).
   Para la Final real (partido 104, 2026-07-19 19:00 UTC), los 7 mercados europeos
   están en prime time pero solo hay 4 ubicaciones → se activa la priorización.
*/

-- ============================================================================
-- 8.1 Piezas de Adidas (CASO OBLIGATORIO: 7 mercados europeos en prime time)
-- ============================================================================
DECLARE @idCampaniaAdidas int = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Adidas Mundial 2026');

DECLARE @idPiezaAdidas_es int = (
    SELECT id FROM Publicidad.PiezaContenido
    WHERE idCampania = @idCampaniaAdidas
      AND descripcion = N'Adidas - Impossible is Nothing (es)'
);
DECLARE @idPiezaAdidas_de int = (
    SELECT id FROM Publicidad.PiezaContenido
    WHERE idCampania = @idCampaniaAdidas
      AND descripcion = N'Adidas - Impossible is Nothing (de)'
);

-- Mercados Pieza Adidas (es): DE, ES, FR, IT, NL, PT, GB
IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaAdidas_es AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'DE'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaAdidas_es, @idPais = @idPais_DE;
IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaAdidas_es AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'ES'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaAdidas_es, @idPais = @idPais_ES;
IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaAdidas_es AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'FR'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaAdidas_es, @idPais = @idPais_FR;
IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaAdidas_es AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'IT'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaAdidas_es, @idPais = @idPais_IT;
IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaAdidas_es AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'NL'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaAdidas_es, @idPais = @idPais_NL;
IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaAdidas_es AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'PT'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaAdidas_es, @idPais = @idPais_PT;
IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaAdidas_es AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'GB'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaAdidas_es, @idPais = @idPais_GB;

-- Mercados Pieza Adidas (de): DE, ES, FR, IT, NL, PT, GB
IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaAdidas_de AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'DE'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaAdidas_de, @idPais = @idPais_DE;
IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaAdidas_de AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'ES'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaAdidas_de, @idPais = @idPais_ES;
IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaAdidas_de AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'FR'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaAdidas_de, @idPais = @idPais_FR;
IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaAdidas_de AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'IT'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaAdidas_de, @idPais = @idPais_IT;
IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaAdidas_de AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'NL'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaAdidas_de, @idPais = @idPais_NL;
IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaAdidas_de AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'PT'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaAdidas_de, @idPais = @idPais_PT;
IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaAdidas_de AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'GB'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaAdidas_de, @idPais = @idPais_GB;

GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
DECLARE @idPais_AR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'AR');
DECLARE @idPais_BR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'BR');
DECLARE @idPais_DE int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'DE');
DECLARE @idPais_JP int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'JP');
DECLARE @idPais_FR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'FR');
DECLARE @idPais_IT int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'IT');
DECLARE @idPais_ES int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'ES');
DECLARE @idPais_NL int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'NL');
DECLARE @idPais_GB int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'GB');
DECLARE @idPais_PT int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'PT');

-- ============================================================================
-- 8.2 Piezas de YPF (mercados: Argentina)
-- ============================================================================
DECLARE @idCampaniaYPF int = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'YPF Energia del Juego');

DECLARE @idPiezaYPF_1 int = (
    SELECT id FROM Publicidad.PiezaContenido
    WHERE idCampania = @idCampaniaYPF
      AND descripcion = N'YPF - La energia que mueve Argentina (es)'
);
DECLARE @idPiezaYPF_2 int = (
    SELECT id FROM Publicidad.PiezaContenido
    WHERE idCampania = @idCampaniaYPF
      AND descripcion = N'YPF - Orgullo Argentino (es)'
);

IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaYPF_1 AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'AR'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaYPF_1, @idPais = @idPais_AR;
IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaYPF_1 AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'ES'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaYPF_1, @idPais = @idPais_ES;

IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaYPF_2 AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'AR'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaYPF_2, @idPais = @idPais_AR;

GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
DECLARE @idPais_AR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'AR');
DECLARE @idPais_BR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'BR');
DECLARE @idPais_DE int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'DE');
DECLARE @idPais_JP int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'JP');
DECLARE @idPais_FR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'FR');
DECLARE @idPais_IT int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'IT');
DECLARE @idPais_ES int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'ES');
DECLARE @idPais_NL int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'NL');
DECLARE @idPais_GB int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'GB');
DECLARE @idPais_PT int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'PT');

-- ============================================================================
-- 8.3 Piezas de Petrobras (mercados: Brasil, Portugal)
-- ============================================================================
DECLARE @idCampaniaPetrobras int = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Petrobras Forca Brasil');

DECLARE @idPiezaPetrobras_es int = (
    SELECT id FROM Publicidad.PiezaContenido
    WHERE idCampania = @idCampaniaPetrobras
      AND descripcion = N'Petrobras - Energia para el futbol (es)'
);
DECLARE @idPiezaPetrobras_pt int = (
    SELECT id FROM Publicidad.PiezaContenido
    WHERE idCampania = @idCampaniaPetrobras
      AND descripcion = N'Petrobras - Forca Brasil (pt)'
);

IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaPetrobras_es AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'BR'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaPetrobras_es, @idPais = @idPais_BR;
IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaPetrobras_es AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'AR'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaPetrobras_es, @idPais = @idPais_AR;

IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaPetrobras_pt AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'BR'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaPetrobras_pt, @idPais = @idPais_BR;
IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaPetrobras_pt AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'PT'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaPetrobras_pt, @idPais = @idPais_PT;

GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
DECLARE @idPais_AR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'AR');
DECLARE @idPais_BR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'BR');
DECLARE @idPais_DE int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'DE');
DECLARE @idPais_JP int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'JP');
DECLARE @idPais_FR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'FR');
DECLARE @idPais_IT int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'IT');
DECLARE @idPais_ES int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'ES');
DECLARE @idPais_NL int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'NL');
DECLARE @idPais_GB int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'GB');
DECLARE @idPais_PT int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'PT');

-- ============================================================================
-- 8.4 Piezas de Sony (mercados: Japón, España)
-- ============================================================================
DECLARE @idCampaniaSony int = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Sony Vive el Momento');

DECLARE @idPiezaSony_es int = (
    SELECT id FROM Publicidad.PiezaContenido
    WHERE idCampania = @idCampaniaSony
      AND descripcion = N'Sony - Vive cada gol (es)'
);
DECLARE @idPiezaSony_ja int = (
    SELECT id FROM Publicidad.PiezaContenido
    WHERE idCampania = @idCampaniaSony
      AND descripcion = N'Sony - Feel Every Moment (ja)'
);

IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaSony_es AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'ES'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaSony_es, @idPais = @idPais_ES;
IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaSony_es AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'AR'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaSony_es, @idPais = @idPais_AR;

IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaSony_ja AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'JP'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaSony_ja, @idPais = @idPais_JP;

GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
DECLARE @idPais_AR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'AR');
DECLARE @idPais_BR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'BR');
DECLARE @idPais_DE int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'DE');
DECLARE @idPais_JP int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'JP');
DECLARE @idPais_FR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'FR');
DECLARE @idPais_IT int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'IT');
DECLARE @idPais_ES int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'ES');
DECLARE @idPais_NL int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'NL');
DECLARE @idPais_GB int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'GB');
DECLARE @idPais_PT int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'PT');

-- ============================================================================
-- 8.5 Piezas de L Oreal (mercados: Francia, España)
-- ============================================================================
DECLARE @idCampaniaLOreal int = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'L Oreal Brilla en el Mundial');

DECLARE @idPiezaLOreal_es int = (
    SELECT id FROM Publicidad.PiezaContenido
    WHERE idCampania = @idCampaniaLOreal
      AND descripcion = N'L Oreal - Porque tu lo vales (es)'
);
DECLARE @idPiezaLOreal_fr int = (
    SELECT id FROM Publicidad.PiezaContenido
    WHERE idCampania = @idCampaniaLOreal
      AND descripcion = N'L Oreal - Parce que je le vaux bien (fr)'
);

IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaLOreal_es AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'ES'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaLOreal_es, @idPais = @idPais_ES;
IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaLOreal_es AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'FR'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaLOreal_es, @idPais = @idPais_FR;

IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaLOreal_fr AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'FR'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaLOreal_fr, @idPais = @idPais_FR;
IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaLOreal_fr AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'GB'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaLOreal_fr, @idPais = @idPais_GB;

GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
DECLARE @idPais_AR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'AR');
DECLARE @idPais_BR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'BR');
DECLARE @idPais_DE int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'DE');
DECLARE @idPais_JP int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'JP');
DECLARE @idPais_FR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'FR');
DECLARE @idPais_IT int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'IT');
DECLARE @idPais_ES int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'ES');
DECLARE @idPais_NL int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'NL');
DECLARE @idPais_GB int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'GB');
DECLARE @idPais_PT int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'PT');

-- ============================================================================
-- 8.6 Piezas de Ferrari (mercados: Italia, Alemania, España)
-- ============================================================================
DECLARE @idCampaniaFerrari int = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Ferrari Pasion por la Velocidad');

DECLARE @idPiezaFerrari_es int = (
    SELECT id FROM Publicidad.PiezaContenido
    WHERE idCampania = @idCampaniaFerrari
      AND descripcion = N'Ferrari - Pasion italiana (es)'
);
DECLARE @idPiezaFerrari_it int = (
    SELECT id FROM Publicidad.PiezaContenido
    WHERE idCampania = @idCampaniaFerrari
      AND descripcion = N'Ferrari - La passione italiana (it)'
);

IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaFerrari_es AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'ES'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaFerrari_es, @idPais = @idPais_ES;
IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaFerrari_es AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'DE'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaFerrari_es, @idPais = @idPais_DE;

IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaFerrari_it AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'IT'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaFerrari_it, @idPais = @idPais_IT;
IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaFerrari_it AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'DE'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaFerrari_it, @idPais = @idPais_DE;

GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
DECLARE @idPais_AR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'AR');
DECLARE @idPais_BR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'BR');
DECLARE @idPais_DE int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'DE');
DECLARE @idPais_JP int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'JP');
DECLARE @idPais_FR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'FR');
DECLARE @idPais_IT int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'IT');
DECLARE @idPais_ES int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'ES');
DECLARE @idPais_NL int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'NL');
DECLARE @idPais_GB int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'GB');
DECLARE @idPais_PT int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'PT');

-- ============================================================================
-- 8.7 Piezas de Zara (mercados: España, Argentina)
-- ============================================================================
DECLARE @idCampaniaZara int = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Zara Style Mundial');

DECLARE @idPiezaZara_1 int = (
    SELECT id FROM Publicidad.PiezaContenido
    WHERE idCampania = @idCampaniaZara
      AND descripcion = N'Zara - Moda en el estadio (es)'
);
DECLARE @idPiezaZara_2 int = (
    SELECT id FROM Publicidad.PiezaContenido
    WHERE idCampania = @idCampaniaZara
      AND descripcion = N'Zara - Estilo sin limites (es)'
);

IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaZara_1 AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'ES'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaZara_1, @idPais = @idPais_ES;
IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaZara_1 AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'AR'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaZara_1, @idPais = @idPais_AR;

IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaZara_2 AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'ES'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaZara_2, @idPais = @idPais_ES;
IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaZara_2 AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'FR'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaZara_2, @idPais = @idPais_FR;

GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
DECLARE @idPais_AR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'AR');
DECLARE @idPais_BR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'BR');
DECLARE @idPais_DE int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'DE');
DECLARE @idPais_JP int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'JP');
DECLARE @idPais_FR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'FR');
DECLARE @idPais_IT int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'IT');
DECLARE @idPais_ES int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'ES');
DECLARE @idPais_NL int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'NL');
DECLARE @idPais_GB int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'GB');
DECLARE @idPais_PT int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'PT');

-- ============================================================================
-- 8.8 Piezas de Heineken (mercados: Países Bajos, Alemania, Reino Unido)
-- ============================================================================
DECLARE @idCampaniaHeineken int = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Heineken Brindis Mundial');

DECLARE @idPiezaHeineken_es int = (
    SELECT id FROM Publicidad.PiezaContenido
    WHERE idCampania = @idCampaniaHeineken
      AND descripcion = N'Heineken - Brindamos por el futbol (es)'
);
DECLARE @idPiezaHeineken_nl int = (
    SELECT id FROM Publicidad.PiezaContenido
    WHERE idCampania = @idCampaniaHeineken
      AND descripcion = N'Heineken - Open Your World (nl)'
);

IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaHeineken_es AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'NL'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaHeineken_es, @idPais = @idPais_NL;
IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaHeineken_es AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'DE'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaHeineken_es, @idPais = @idPais_DE;
IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaHeineken_es AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'GB'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaHeineken_es, @idPais = @idPais_GB;

IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaHeineken_nl AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'NL'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaHeineken_nl, @idPais = @idPais_NL;
IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPiezaHeineken_nl AND idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'GB'))
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPiezaHeineken_nl, @idPais = @idPais_GB;

GO

/* ======= SECCION 9: Resumen de carga — verificacion de totales ======= */

SELECT 'Sistema.Parametro'               AS tabla, COUNT(*) AS registros FROM Sistema.Parametro        WHERE clave IN ('PRIME_TIME_INICIO','PRIME_TIME_FIN','MAX_ESPACIOS_PARTIDO')
UNION ALL
SELECT 'Torneo.Pais',                              COUNT(*)               FROM Torneo.Pais
UNION ALL
SELECT 'Torneo.Fase',                              COUNT(*)               FROM Torneo.Fase
UNION ALL
SELECT 'Torneo.Sede',                              COUNT(*)               FROM Torneo.Sede
UNION ALL
SELECT 'Equipos.Seleccion',                        COUNT(*)               FROM Equipos.Seleccion
UNION ALL
SELECT 'Torneo.Partido',                           COUNT(*)               FROM Torneo.Partido
UNION ALL
SELECT 'Publicidad.UbicacionPublicitaria',         COUNT(*)               FROM Publicidad.UbicacionPublicitaria
UNION ALL
SELECT 'Publicidad.Tarifa',                        COUNT(*)               FROM Publicidad.Tarifa
UNION ALL
SELECT 'Publicidad.Anunciante',                    COUNT(*)               FROM Publicidad.Anunciante
UNION ALL
SELECT 'Publicidad.Campania',                      COUNT(*)               FROM Publicidad.Campania
UNION ALL
SELECT 'Publicidad.PiezaContenido',                COUNT(*)               FROM Publicidad.PiezaContenido
UNION ALL
SELECT 'Publicidad.PiezaMercado',                  COUNT(*)               FROM Publicidad.PiezaMercado
UNION ALL
SELECT 'Publicidad.ExhibicionPublicitaria',        COUNT(*)               FROM Publicidad.ExhibicionPublicitaria
ORDER BY tabla;

/*
   ── Verificacion del caso obligatorio ────────────────────────────────────────
   El siguiente SELECT muestra, para la Final real (partido 104, España–Argentina,
   2026-07-19 19:00 UTC), la hora local de cada mercado de las piezas y si cae en
   prime time, confirmando que 7 mercados (más de 4) están en prime time.
   Si se ejecuta EXEC Publicidad.AsignarPiezasPartido con el idPartido de la Final
   (antes de 53_Cierre_Partidos.sql), el sistema selecciona solo 4 de las piezas
   aplicando los criterios de priorización del SP.
*/
DECLARE @fechaFinal datetime2(0) = (SELECT fechaHoraUTC FROM Torneo.Partido WHERE nroPartidoOficial = 104);

SELECT
    pa.nombre                                                AS pais,
    pa.husoHorario,
    Publicidad.fn_HoraLocal(@fechaFinal, pa.husoHorario)     AS horaLocal,
    CASE
        WHEN Publicidad.fn_EsPrimeTime(@fechaFinal, pa.husoHorario) = 1
        THEN 'PRIME TIME'
        ELSE 'fuera de prime time'
    END                                                      AS esPrimeTime
FROM Torneo.Pais pa
WHERE pa.husoHorario IS NOT NULL
  AND pa.id IN (SELECT idPais FROM Publicidad.PiezaMercado)
ORDER BY esPrimeTime DESC, pa.nombre;

GO
