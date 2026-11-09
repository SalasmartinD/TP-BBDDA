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
               Incluye datos de apoyo mínimos en Torneo y Equipos para poder
               probar los SPs de Publicidad de forma independiente, antes de
               que la Persona 1 suba su carga completa.
               Claves propias en Sistema.Parametro:
                 PRIME_TIME_INICIO, PRIME_TIME_FIN, MAX_ESPACIOS_PARTIDO
               Caso obligatorio: un partido cuyo horario cae en prime time
               en más de 4 mercados candidatos.

 NOTA SOBRE INSERTS DIRECTOS EN TABLAS DE OTROS ESQUEMAS:
 ---------------------------------------------------------
 Los SPs de Alta/Baja/Modificación para las tablas de Torneo (Pais, Fase,
 Sede, Partido) y Equipos (Seleccion) corresponden a la Persona 1 del grupo
 y aún no están disponibles en el repositorio. Por ese motivo, las secciones
 2 y 3 de este script usan INSERT directo con guarda IF NOT EXISTS, que es el
 mecanismo equivalente y seguro para ejecuciones repetidas. En cuanto la
 Persona 1 suba sus SPs, se deberán reemplazar esos bloques por EXEC.
 Las tablas del esquema Publicidad se cargan exclusivamente a través de los
 SPs del script 12_ABM_Publicidad.sql.
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

/* ======= SECCION 3: Datos de apoyo en Torneo y Equipos (INSERT directo) ======= */
/*
   Ver nota al inicio del script: se usan INSERTs directos con IF NOT EXISTS
   porque los SPs de la Persona 1 todavía no están disponibles.
*/

/* --- 3.1 Torneo.Pais — 10 países con husoHorario válido (sys.time_zone_info) --- */
/*
   Países elegidos estratégicamente para el caso obligatorio de prime time:
   El partido Argentina vs Brasil está programado para el 2026-06-15 a las 18:00 UTC.
   En esa fecha (verano europeo), los países con UTC+1 / UTC+2 ven el partido en
   horario prime time (19:00–23:00 local):
     - Alemania   (UTC+2 en verano, 'W. Europe Standard Time')   → 20:00 ✓
     - España     (UTC+2 en verano, 'Romance Standard Time')     → 20:00 ✓
     - Francia    (UTC+2 en verano, 'Romance Standard Time')     → 20:00 ✓
     - Italia     (UTC+2 en verano, 'W. Europe Standard Time')   → 20:00 ✓
     - Países Bajos (UTC+2 en verano, 'W. Europe Standard Time') → 20:00 ✓
     - Portugal   (UTC+1 en verano, 'GMT Standard Time')         → 19:00 ✓
     - Reino Unido (UTC+1 en verano, 'GMT Standard Time')        → 19:00 ✓
   Son 7 mercados europeos en prime time simultáneo, superando el límite de 4
   espacios → se activa la priorización del SP AsignarPiezasPartido.
*/

-- Argentina (UTC-3)
IF NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE codigoISO2 = 'AR')
    INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3, husoHorario, moneda, pbiPerCapita, poblacion)
    VALUES (N'Argentina', 'AR', 'ARG', 'Argentina Standard Time', 'ARS', 13700.00, 46000000);

-- Brasil (UTC-3)
IF NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE codigoISO2 = 'BR')
    INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3, husoHorario, moneda, pbiPerCapita, poblacion)
    VALUES (N'Brasil', 'BR', 'BRA', 'E. South America Standard Time', 'BRL', 9100.00, 215000000);

-- Alemania (UTC+1, UTC+2 en verano)
IF NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE codigoISO2 = 'DE')
    INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3, husoHorario, moneda, pbiPerCapita, poblacion)
    VALUES (N'Alemania', 'DE', 'DEU', 'W. Europe Standard Time', 'EUR', 51200.00, 84000000);

-- España (UTC+1, UTC+2 en verano)
IF NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE codigoISO2 = 'ES')
    INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3, husoHorario, moneda, pbiPerCapita, poblacion)
    VALUES (N'España', 'ES', 'ESP', 'Romance Standard Time', 'EUR', 30100.00, 47000000);

-- Francia (UTC+1, UTC+2 en verano)
IF NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE codigoISO2 = 'FR')
    INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3, husoHorario, moneda, pbiPerCapita, poblacion)
    VALUES (N'Francia', 'FR', 'FRA', 'Romance Standard Time', 'EUR', 44000.00, 68000000);

-- Italia (UTC+1, UTC+2 en verano)
IF NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE codigoISO2 = 'IT')
    INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3, husoHorario, moneda, pbiPerCapita, poblacion)
    VALUES (N'Italia', 'IT', 'ITA', 'W. Europe Standard Time', 'EUR', 36000.00, 59000000);

-- Países Bajos (UTC+1, UTC+2 en verano)
IF NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE codigoISO2 = 'NL')
    INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3, husoHorario, moneda, pbiPerCapita, poblacion)
    VALUES (N'Países Bajos', 'NL', 'NLD', 'W. Europe Standard Time', 'EUR', 60000.00, 17900000);

-- Portugal (UTC+0, UTC+1 en verano)
IF NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE codigoISO2 = 'PT')
    INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3, husoHorario, moneda, pbiPerCapita, poblacion)
    VALUES (N'Portugal', 'PT', 'PRT', 'GMT Standard Time', 'EUR', 25000.00, 10300000);

-- Reino Unido (UTC+0, UTC+1 en verano)
IF NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE codigoISO2 = 'GB')
    INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3, husoHorario, moneda, pbiPerCapita, poblacion)
    VALUES (N'Reino Unido', 'GB', 'GBR', 'GMT Standard Time', 'GBP', 46200.00, 67000000);

-- Japón (UTC+9)
IF NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE codigoISO2 = 'JP')
    INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3, husoHorario, moneda, pbiPerCapita, poblacion)
    VALUES (N'Japón', 'JP', 'JPN', 'Tokyo Standard Time', 'JPY', 42200.00, 125000000);

GO

/* --- 3.2 Torneo.Fase — 6 fases del torneo --- */

IF NOT EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = 1)
    INSERT INTO Torneo.Fase (idFase, nombre, esEliminatoria, orden)
    VALUES (1, 'Fase de Grupos', 0, 1);

IF NOT EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = 2)
    INSERT INTO Torneo.Fase (idFase, nombre, esEliminatoria, orden)
    VALUES (2, 'Dieciseisavos de Final', 1, 2);

IF NOT EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = 3)
    INSERT INTO Torneo.Fase (idFase, nombre, esEliminatoria, orden)
    VALUES (3, 'Octavos de Final', 1, 3);

IF NOT EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = 4)
    INSERT INTO Torneo.Fase (idFase, nombre, esEliminatoria, orden)
    VALUES (4, 'Cuartos de Final', 1, 4);

IF NOT EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = 5)
    INSERT INTO Torneo.Fase (idFase, nombre, esEliminatoria, orden)
    VALUES (5, 'Semifinal', 1, 5);

IF NOT EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = 6)
    INSERT INTO Torneo.Fase (idFase, nombre, esEliminatoria, orden)
    VALUES (6, 'Final', 1, 6);

GO

/* --- 3.3 Torneo.Sede — 2 sedes de apoyo --- */

-- Estadio Monumental, Buenos Aires, Argentina (lat: -34.545, lon: -58.449)
IF NOT EXISTS (SELECT 1 FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Monumental' AND ciudad = 'Buenos Aires')
    INSERT INTO Torneo.Sede (nombreEstadio, ciudad, idPais, capacidad, husoHorario, latitud, longitud)
    VALUES (
        'Estadio Monumental',
        'Buenos Aires',
        (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'AR'),
        80000,
        'Argentina Standard Time',
        -34.545400,
        -58.449800
    );

-- Arena Corinthians, São Paulo, Brasil (lat: -23.545, lon: -46.473)
IF NOT EXISTS (SELECT 1 FROM Torneo.Sede WHERE nombreEstadio = 'Arena Corinthians' AND ciudad = 'São Paulo')
    INSERT INTO Torneo.Sede (nombreEstadio, ciudad, idPais, capacidad, husoHorario, latitud, longitud)
    VALUES (
        'Arena Corinthians',
        'São Paulo',
        (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'BR'),
        68000,
        'E. South America Standard Time',
        -23.545300,
        -46.473100
    );

GO

/* --- 3.4 Equipos.Seleccion — 4 selecciones de apoyo --- */

-- Argentina
IF NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'AR'))
    INSERT INTO Equipos.Seleccion (idPais, confederacion, nombreAsociacion, abreviacion, grupo)
    VALUES (
        (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'AR'),
        'CONMEBOL',
        'Asociación del Fútbol Argentino',
        'ARG',
        'A'
    );

-- Brasil
IF NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'BR'))
    INSERT INTO Equipos.Seleccion (idPais, confederacion, nombreAsociacion, abreviacion, grupo)
    VALUES (
        (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'BR'),
        'CONMEBOL',
        'Confederação Brasileira de Futebol',
        'BRA',
        'A'
    );

-- Alemania
IF NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'DE'))
    INSERT INTO Equipos.Seleccion (idPais, confederacion, nombreAsociacion, abreviacion, grupo)
    VALUES (
        (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'DE'),
        'UEFA',
        'Deutscher Fußball-Bund',
        'GER',
        'B'
    );

-- Japón
IF NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'JP'))
    INSERT INTO Equipos.Seleccion (idPais, confederacion, nombreAsociacion, abreviacion, grupo)
    VALUES (
        (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'JP'),
        'AFC',
        'Japan Football Association',
        'JPN',
        'B'
    );

GO

/* --- 3.5 Torneo.Partido — 3 partidos de apoyo --- */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

/*
   PARTIDO 1 (CASO OBLIGATORIO):
   Argentina vs Brasil — 2026-06-15 18:00 UTC — Estadio Monumental — Fase de Grupos.
   
   Horarios locales el 15/06/2026 (horario de verano europeo activo):
     - Argentina  (UTC-3,  'Argentina Standard Time')     → 15:00  NO prime time
     - Brasil     (UTC-3,  'E. South America Std Time')   → 15:00  NO prime time
     - Alemania   (UTC+2,  'W. Europe Standard Time')     → 20:00  ✓ PRIME TIME
     - España     (UTC+2,  'Romance Standard Time')       → 20:00  ✓ PRIME TIME
     - Francia    (UTC+2,  'Romance Standard Time')       → 20:00  ✓ PRIME TIME
     - Italia     (UTC+2,  'W. Europe Standard Time')     → 20:00  ✓ PRIME TIME
     - Países Bajos (UTC+2,'W. Europe Standard Time')     → 20:00  ✓ PRIME TIME
     - Portugal   (UTC+1,  'GMT Standard Time')           → 19:00  ✓ PRIME TIME
     - Reino Unido (UTC+1, 'GMT Standard Time')           → 19:00  ✓ PRIME TIME
     - Japón      (UTC+9,  'Tokyo Standard Time')         → 03:00  NO prime time
   
   7 mercados europeos en prime time → supera el límite de MAX_ESPACIOS_PARTIDO=4
   → el SP Publicidad.AsignarPiezasPartido debe aplicar criterios de priorización.
*/

IF NOT EXISTS (
    SELECT 1 FROM Torneo.Partido
    WHERE idSeleccionLocal      = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'ARG')
      AND idSeleccionVisitante  = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'BRA')
      AND fechaHoraUTC          = '2026-06-15 18:00:00'
)
    INSERT INTO Torneo.Partido (nroPartidoOficial, idSede, idSeleccionLocal, idSeleccionVisitante, fase, fechaHoraUTC, estado)
    VALUES (
        1,
        (SELECT idSede FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Monumental' AND ciudad = 'Buenos Aires'),
        (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'ARG'),
        (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'BRA'),
        1,                          -- Fase de Grupos
        '2026-06-15 18:00:00',
        'Programado'
    );

-- PARTIDO 2: Alemania vs Japón — 2026-06-16 15:00 UTC — Arena Corinthians (sede alternativa) — Fase de Grupos
IF NOT EXISTS (
    SELECT 1 FROM Torneo.Partido
    WHERE idSeleccionLocal      = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'GER')
      AND idSeleccionVisitante  = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'JPN')
      AND fechaHoraUTC          = '2026-06-16 15:00:00'
)
    INSERT INTO Torneo.Partido (nroPartidoOficial, idSede, idSeleccionLocal, idSeleccionVisitante, fase, fechaHoraUTC, estado)
    VALUES (
        2,
        (SELECT idSede FROM Torneo.Sede WHERE nombreEstadio = 'Arena Corinthians' AND ciudad = 'São Paulo'),
        (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'GER'),
        (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'JPN'),
        1,                          -- Fase de Grupos
        '2026-06-16 15:00:00',
        'Programado'
    );

-- PARTIDO 3: Argentina vs Alemania — Cuartos de Final — 2026-07-05 20:00 UTC — Estadio Monumental
IF NOT EXISTS (
    SELECT 1 FROM Torneo.Partido
    WHERE idSeleccionLocal      = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'ARG')
      AND idSeleccionVisitante  = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'GER')
      AND fechaHoraUTC          = '2026-07-05 20:00:00'
)
    INSERT INTO Torneo.Partido (nroPartidoOficial, idSede, idSeleccionLocal, idSeleccionVisitante, fase, fechaHoraUTC, estado)
    VALUES (
        3,
        (SELECT idSede FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Monumental' AND ciudad = 'Buenos Aires'),
        (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'ARG'),
        (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'GER'),
        4,                          -- Cuartos de Final
        '2026-07-05 20:00:00',
        'Programado'
    );

GO

/* ======= SECCION 4: Publicidad.Tarifa — 6 fases × 4 ubicaciones (24 tarifas) ======= */
/*
   Se usa EXEC Publicidad.Tarifa_Alta.
   El SP valida que el par (idFase, idUbicacion) no exista, por lo que
   se envuelve cada llamada en IF NOT EXISTS.
*/

-- ── Fase 1: Fase de Grupos ──────────────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = 1 AND idUbicacion = 1)
    EXEC Publicidad.Tarifa_Alta @idFase = 1, @idUbicacion = 1, @montoUSD =  50000.00;
IF NOT EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = 1 AND idUbicacion = 2)
    EXEC Publicidad.Tarifa_Alta @idFase = 1, @idUbicacion = 2, @montoUSD =  35000.00;
IF NOT EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = 1 AND idUbicacion = 3)
    EXEC Publicidad.Tarifa_Alta @idFase = 1, @idUbicacion = 3, @montoUSD =  35000.00;
IF NOT EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = 1 AND idUbicacion = 4)
    EXEC Publicidad.Tarifa_Alta @idFase = 1, @idUbicacion = 4, @montoUSD =  80000.00;

-- ── Fase 2: Dieciseisavos de Final ─────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = 2 AND idUbicacion = 1)
    EXEC Publicidad.Tarifa_Alta @idFase = 2, @idUbicacion = 1, @montoUSD =  60000.00;
IF NOT EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = 2 AND idUbicacion = 2)
    EXEC Publicidad.Tarifa_Alta @idFase = 2, @idUbicacion = 2, @montoUSD =  42000.00;
IF NOT EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = 2 AND idUbicacion = 3)
    EXEC Publicidad.Tarifa_Alta @idFase = 2, @idUbicacion = 3, @montoUSD =  42000.00;
IF NOT EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = 2 AND idUbicacion = 4)
    EXEC Publicidad.Tarifa_Alta @idFase = 2, @idUbicacion = 4, @montoUSD =  96000.00;

-- ── Fase 3: Octavos de Final ────────────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = 3 AND idUbicacion = 1)
    EXEC Publicidad.Tarifa_Alta @idFase = 3, @idUbicacion = 1, @montoUSD =  70000.00;
IF NOT EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = 3 AND idUbicacion = 2)
    EXEC Publicidad.Tarifa_Alta @idFase = 3, @idUbicacion = 2, @montoUSD =  50000.00;
IF NOT EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = 3 AND idUbicacion = 3)
    EXEC Publicidad.Tarifa_Alta @idFase = 3, @idUbicacion = 3, @montoUSD =  50000.00;
IF NOT EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = 3 AND idUbicacion = 4)
    EXEC Publicidad.Tarifa_Alta @idFase = 3, @idUbicacion = 4, @montoUSD = 112000.00;

-- ── Fase 4: Cuartos de Final ────────────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = 4 AND idUbicacion = 1)
    EXEC Publicidad.Tarifa_Alta @idFase = 4, @idUbicacion = 1, @montoUSD =  90000.00;
IF NOT EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = 4 AND idUbicacion = 2)
    EXEC Publicidad.Tarifa_Alta @idFase = 4, @idUbicacion = 2, @montoUSD =  65000.00;
IF NOT EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = 4 AND idUbicacion = 3)
    EXEC Publicidad.Tarifa_Alta @idFase = 4, @idUbicacion = 3, @montoUSD =  65000.00;
IF NOT EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = 4 AND idUbicacion = 4)
    EXEC Publicidad.Tarifa_Alta @idFase = 4, @idUbicacion = 4, @montoUSD = 145000.00;

-- ── Fase 5: Semifinal ───────────────────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = 5 AND idUbicacion = 1)
    EXEC Publicidad.Tarifa_Alta @idFase = 5, @idUbicacion = 1, @montoUSD = 120000.00;
IF NOT EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = 5 AND idUbicacion = 2)
    EXEC Publicidad.Tarifa_Alta @idFase = 5, @idUbicacion = 2, @montoUSD =  85000.00;
IF NOT EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = 5 AND idUbicacion = 3)
    EXEC Publicidad.Tarifa_Alta @idFase = 5, @idUbicacion = 3, @montoUSD =  85000.00;
IF NOT EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = 5 AND idUbicacion = 4)
    EXEC Publicidad.Tarifa_Alta @idFase = 5, @idUbicacion = 4, @montoUSD = 190000.00;

-- ── Fase 6: Final ───────────────────────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = 6 AND idUbicacion = 1)
    EXEC Publicidad.Tarifa_Alta @idFase = 6, @idUbicacion = 1, @montoUSD = 200000.00;
IF NOT EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = 6 AND idUbicacion = 2)
    EXEC Publicidad.Tarifa_Alta @idFase = 6, @idUbicacion = 2, @montoUSD = 140000.00;
IF NOT EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = 6 AND idUbicacion = 3)
    EXEC Publicidad.Tarifa_Alta @idFase = 6, @idUbicacion = 3, @montoUSD = 140000.00;
IF NOT EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = 6 AND idUbicacion = 4)
    EXEC Publicidad.Tarifa_Alta @idFase = 6, @idUbicacion = 4, @montoUSD = 320000.00;

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
    SELECT @idCampania_current = idCampania FROM Publicidad.Campania WHERE nombre = N'Sony Vive el Momento';
    EXEC Publicidad.PiezaContenido_Alta
        @idCampania  = @idCampania_current,
        @descripcion = N'Sony - Vive cada gol (es)',
        @idioma      = 'es';

IF NOT EXISTS (
    SELECT 1 FROM Publicidad.PiezaContenido
    WHERE idCampania  = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Sony Vive el Momento')
      AND descripcion = N'Sony - Feel Every Moment (ja)'
      AND idioma      = 'ja'
)
    SELECT @idCampania_current = idCampania FROM Publicidad.Campania WHERE nombre = N'Sony Vive el Momento';
    EXEC Publicidad.PiezaContenido_Alta
        @idCampania  = @idCampania_current,
        @descripcion = N'Sony - Feel Every Moment (ja)',
        @idioma      = 'ja';

-- ── L Oreal (campania: 'L Oreal Brilla en el Mundial') ────────────────────
IF NOT EXISTS (
    SELECT 1 FROM Publicidad.PiezaContenido
    WHERE idCampania  = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'L Oreal Brilla en el Mundial')
      AND descripcion = N'L Oreal - Porque tu lo vales (es)'
      AND idioma      = 'es'
)
    SELECT @idCampania_current = idCampania FROM Publicidad.Campania WHERE nombre = N'L Oreal Brilla en el Mundial';
    EXEC Publicidad.PiezaContenido_Alta
        @idCampania  = @idCampania_current,
        @descripcion = N'L Oreal - Porque tu lo vales (es)',
        @idioma      = 'es';

IF NOT EXISTS (
    SELECT 1 FROM Publicidad.PiezaContenido
    WHERE idCampania  = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'L Oreal Brilla en el Mundial')
      AND descripcion = N'L Oreal - Parce que je le vaux bien (fr)'
      AND idioma      = 'fr'
)
    SELECT @idCampania_current = idCampania FROM Publicidad.Campania WHERE nombre = N'L Oreal Brilla en el Mundial';
    EXEC Publicidad.PiezaContenido_Alta
        @idCampania  = @idCampania_current,
        @descripcion = N'L Oreal - Parce que je le vaux bien (fr)',
        @idioma      = 'fr';

-- ── Ferrari (campania: 'Ferrari Pasion por la Velocidad') ─────────────────
IF NOT EXISTS (
    SELECT 1 FROM Publicidad.PiezaContenido
    WHERE idCampania  = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Ferrari Pasion por la Velocidad')
      AND descripcion = N'Ferrari - Pasion italiana (es)'
      AND idioma      = 'es'
)
    SELECT @idCampania_current = idCampania FROM Publicidad.Campania WHERE nombre = N'Ferrari Pasion por la Velocidad';
    EXEC Publicidad.PiezaContenido_Alta
        @idCampania  = @idCampania_current,
        @descripcion = N'Ferrari - Pasion italiana (es)',
        @idioma      = 'es';

IF NOT EXISTS (
    SELECT 1 FROM Publicidad.PiezaContenido
    WHERE idCampania  = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Ferrari Pasion por la Velocidad')
      AND descripcion = N'Ferrari - La passione italiana (it)'
      AND idioma      = 'it'
)
    SELECT @idCampania_current = idCampania FROM Publicidad.Campania WHERE nombre = N'Ferrari Pasion por la Velocidad';
    EXEC Publicidad.PiezaContenido_Alta
        @idCampania  = @idCampania_current,
        @descripcion = N'Ferrari - La passione italiana (it)',
        @idioma      = 'it';

-- ── Zara (campania: 'Zara Style Mundial') ─────────────────────────────────
IF NOT EXISTS (
    SELECT 1 FROM Publicidad.PiezaContenido
    WHERE idCampania  = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Zara Style Mundial')
      AND descripcion = N'Zara - Moda en el estadio (es)'
      AND idioma      = 'es'
)
    SELECT @idCampania_current = idCampania FROM Publicidad.Campania WHERE nombre = N'Zara Style Mundial';
    EXEC Publicidad.PiezaContenido_Alta
        @idCampania  = @idCampania_current,
        @descripcion = N'Zara - Moda en el estadio (es)',
        @idioma      = 'es';

IF NOT EXISTS (
    SELECT 1 FROM Publicidad.PiezaContenido
    WHERE idCampania  = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Zara Style Mundial')
      AND descripcion = N'Zara - Estilo sin limites (es)'
      AND idioma      = 'es'
)
    SELECT @idCampania_current = idCampania FROM Publicidad.Campania WHERE nombre = N'Zara Style Mundial';
    EXEC Publicidad.PiezaContenido_Alta
        @idCampania  = @idCampania_current,
        @descripcion = N'Zara - Estilo sin limites (es)',
        @idioma      = 'es';

-- ── Heineken (campania: 'Heineken Brindis Mundial') ────────────────────────
IF NOT EXISTS (
    SELECT 1 FROM Publicidad.PiezaContenido
    WHERE idCampania  = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Heineken Brindis Mundial')
      AND descripcion = N'Heineken - Brindamos por el futbol (es)'
      AND idioma      = 'es'
)
    SELECT @idCampania_current = idCampania FROM Publicidad.Campania WHERE nombre = N'Heineken Brindis Mundial';
    EXEC Publicidad.PiezaContenido_Alta
        @idCampania  = @idCampania_current,
        @descripcion = N'Heineken - Brindamos por el futbol (es)',
        @idioma      = 'es';

IF NOT EXISTS (
    SELECT 1 FROM Publicidad.PiezaContenido
    WHERE idCampania  = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Heineken Brindis Mundial')
      AND descripcion = N'Heineken - Open Your World (nl)'
      AND idioma      = 'nl'
)
    SELECT @idCampania_current = idCampania FROM Publicidad.Campania WHERE nombre = N'Heineken Brindis Mundial';
    EXEC Publicidad.PiezaContenido_Alta
        @idCampania  = @idCampania_current,
        @descripcion = N'Heineken - Open Your World (nl)',
        @idioma      = 'nl';

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
   Para el partido ARG vs BRA del 15/06 a las 18:00 UTC, los 7 mercados europeos
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
   El siguiente SELECT muestra los países en prime time para el partido
   Argentina vs Brasil (2026-06-15 18:00 UTC), confirmando que ≥ 5 mercados
   de las piezas de Adidas caen en prime time.
   Si se ejecuta EXEC Publicidad.AsignarPiezasPartido con el idPartido
   correspondiente, el sistema debe seleccionar solo 4 de los 7 mercados
   en prime time, aplicando los criterios de priorización del SP.
*/
SELECT
    pa.nombre                             AS pais,
    pa.husoHorario,
    CAST(
        CAST(CAST('2026-06-15 18:00:00' AS datetime2(0)) AS datetimeoffset)
        AT TIME ZONE 'UTC'
        AT TIME ZONE pa.husoHorario
    AS datetimeoffset)                    AS horaLocal,
    DATEPART(HOUR,
        CAST(
            CAST(CAST('2026-06-15 18:00:00' AS datetime2(0)) AS datetimeoffset)
            AT TIME ZONE 'UTC'
            AT TIME ZONE pa.husoHorario
        AS datetimeoffset)
    )                                     AS horaLocalInt,
    CASE
        WHEN DATEPART(HOUR,
            CAST(
                CAST(CAST('2026-06-15 18:00:00' AS datetime2(0)) AS datetimeoffset)
                AT TIME ZONE 'UTC'
                AT TIME ZONE pa.husoHorario
            AS datetimeoffset)
        ) BETWEEN 19 AND 23
        THEN 'PRIME TIME ✓'
        ELSE 'fuera de prime time'
    END                                   AS esPrimeTime
FROM Torneo.Pais pa
WHERE pa.husoHorario IS NOT NULL
ORDER BY esPrimeTime DESC, pa.nombre;

GO
