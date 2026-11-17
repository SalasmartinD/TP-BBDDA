/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 17/11/2026

 Objetivo    : Pruebas de 60_Reportes_Torneo.sql:
               - Torneo.Reporte_Resultados: marcador, empate, definición por
                 penales, ganador, hora local, cada filtro y las validaciones.
               - Equipos.Reporte_SeleccionesPlantillas: estructura del XML,
                 datos de los convocados, selección sin convocados, bajas y
                 validaciones.

 Requisitos  : 00_InitialSchema.sql, 10a, 10b, 11b, 20a, 30a y 60. Funciona con
               o sin la carga base: los filtros usan solo los datos de prueba.

 Datos de prueba:
 - Países con códigos ISO de uso privado (XX, XY, XZ / XXA, XYA, XZA), que la
   norma ISO 3166 nunca asigna a un país real.
 - Una sede (Eastern Standard Time, UTC-5 en febrero), fases 910 (grupos) y 911
   (eliminatoria), períodos 205 y 206 y jugadores con apellido Prueba80i.
 - Partidos oficiales 98071 a 98074 (XXA es la selección local de los tres
   primeros; la selección XZA no tiene convocados):
     98071  grupos        2025-02-01 18:00 UTC  XXA-XYA  2-1  Finalizado (13:00 local)
     98072  grupos        2025-02-04 18:00 UTC  XXA-XZA  0-0  Finalizado
     98073  eliminatoria  2025-02-08 02:00 UTC  XXA-XYA  1-1 y penales 3-2 para XXA
                          (cruza la medianoche: 2025-02-07 21:00 local)
     98074  grupos        2030-03-01 18:00 UTC  XYA-XZA  Programado, sin resultado
 - Se limpian al inicio y al final: el script se puede ejecutar varias veces.

 Cada prueba imprime [OK] o [FALLO]. Resultado esperado: todas [OK].
================================================================================
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO
-- Los métodos XML (value, query, exist) exigen QUOTED_IDENTIFIER ON
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

PRINT '================================================================================';
PRINT ' PRUEBAS: 60_Reportes_Torneo.sql';
PRINT '================================================================================';
GO

/* =============================================================================
   LIMPIEZA PREVIA (DELETE directo en orden inverso de claves foráneas, por si
   una corrida anterior se cortó y dejó datos con dependencias)
   ============================================================================= */
DELETE FROM Eventos.Gol WHERE idPartido IN
    (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 98071 AND 98074);
DELETE FROM Eventos.FormacionPartido WHERE idPartido IN
    (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 98071 AND 98074);
DELETE FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 98071 AND 98074;
DELETE FROM Equipos.ListadoJugadores WHERE idSeleccion IN
    (SELECT id FROM Equipos.Seleccion WHERE abreviacion IN ('XXA', 'XYA', 'XZA'));
DELETE FROM Equipos.Jugador WHERE apellido = N'Prueba80i';
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('XXA', 'XYA', 'XZA');
DELETE FROM Torneo.Sede WHERE nombreEstadio = N'Estadio Prueba 80i';
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('XX', 'XY', 'XZ');
DELETE FROM Torneo.Fase WHERE idFase IN (910, 911);
DELETE FROM Torneo.Periodo WHERE idPeriodo IN (205, 206);
GO

/* =============================================================================
   DATOS DE PRUEBA con los SP de 10a, 10b, 11b y 20a
   ============================================================================= */
EXEC Torneo.Pais_Alta @nombre = N'País Prueba 80i X', @codigoISO2 = 'XX', @codigoISO3 = 'XXA';
EXEC Torneo.Pais_Alta @nombre = N'País Prueba 80i Y', @codigoISO2 = 'XY', @codigoISO3 = 'XYA';
EXEC Torneo.Pais_Alta @nombre = N'País Prueba 80i Z', @codigoISO2 = 'XZ', @codigoISO3 = 'XZA';
EXEC Torneo.Fase_Alta @idFase = 910, @nombre = 'Fase Prueba 80i Grupos', @esEliminatoria = 0, @orden = 1;
EXEC Torneo.Fase_Alta @idFase = 911, @nombre = 'Fase Prueba 80i Eliminatoria', @esEliminatoria = 1, @orden = 2;
EXEC Torneo.Periodo_Alta @idPeriodo = 205, @nombre = 'Periodo Prueba 80i Juego', @orden = 205;
EXEC Torneo.Periodo_Alta @idPeriodo = 206, @nombre = 'Periodo Prueba 80i Penales', @orden = 206;
GO

DECLARE @idPaisX int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XX');
DECLARE @idPaisY int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XY');
DECLARE @idPaisZ int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XZ');
DECLARE @selX int, @selY int, @selZ int, @sede int, @p int;
DECLARE @x1 int, @x2 int, @x3 int, @y1 int, @y2 int;

EXEC Equipos.Seleccion_Alta @idPais = @idPaisX, @confederacion = 'UEFA', @abreviacion = 'XXA', @grupo = 'A', @id = @selX OUTPUT;
EXEC Equipos.Seleccion_Alta @idPais = @idPaisY, @confederacion = 'UEFA', @abreviacion = 'XYA', @grupo = 'A', @id = @selY OUTPUT;
EXEC Equipos.Seleccion_Alta @idPais = @idPaisZ, @confederacion = 'UEFA', @abreviacion = 'XZA', @grupo = 'A', @id = @selZ OUTPUT;
EXEC Torneo.Sede_Alta @nombreEstadio = N'Estadio Prueba 80i', @ciudad = N'Ciudad Prueba', @idPais = @idPaisX,
     @husoHorario = 'Eastern Standard Time', @capacidad = 60000;
SET @sede = (SELECT idSede FROM Torneo.Sede WHERE nombreEstadio = N'Estadio Prueba 80i');

-- Jugadores: XXA tiene tres convocados, XYA dos y XZA ninguno
EXEC Equipos.Jugador_Alta @nombre = N'X1', @apellido = N'Prueba80i', @club = N'Club Prueba', @posicion = 'Delantero', @id = @x1 OUTPUT;
EXEC Equipos.Jugador_Alta @nombre = N'X2', @apellido = N'Prueba80i', @posicion = 'Defensor', @id = @x2 OUTPUT;
EXEC Equipos.Jugador_Alta @nombre = N'X3', @apellido = N'Prueba80i', @id = @x3 OUTPUT;
EXEC Equipos.Jugador_Alta @nombre = N'Y1', @apellido = N'Prueba80i', @id = @y1 OUTPUT;
EXEC Equipos.Jugador_Alta @nombre = N'Y2', @apellido = N'Prueba80i', @id = @y2 OUTPUT;
EXEC Equipos.ListadoJugadores_Alta @idSeleccion = @selX, @idJugador = @x1, @dorsal = 9,  @fechaAlta = '2025-01-01';
EXEC Equipos.ListadoJugadores_Alta @idSeleccion = @selX, @idJugador = @x2, @dorsal = 10, @fechaAlta = '2025-01-01';
EXEC Equipos.ListadoJugadores_Alta @idSeleccion = @selX, @idJugador = @x3, @dorsal = 11, @fechaAlta = '2025-01-01';
EXEC Equipos.ListadoJugadores_Alta @idSeleccion = @selY, @idJugador = @y1, @dorsal = 7,  @fechaAlta = '2025-01-01';
EXEC Equipos.ListadoJugadores_Alta @idSeleccion = @selY, @idJugador = @y2, @dorsal = 8,  @fechaAlta = '2025-01-01';

-- 98071: 2-1 (X1 y X2 para XXA, Y1 para XYA)
EXEC Torneo.Partido_Alta @idSede = @sede, @idSeleccionLocal = @selX, @idSeleccionVisitante = @selY, @fase = 910,
     @fechaHoraUTC = '2025-02-01 18:00', @nroPartidoOficial = 98071, @idPartido = @p OUTPUT;
EXEC Eventos.FormacionPartido_Alta @idPartido = @p, @idSeleccion = @selX, @idJugador = @x1, @titular = 1;
EXEC Eventos.FormacionPartido_Alta @idPartido = @p, @idSeleccion = @selX, @idJugador = @x2, @titular = 1;
EXEC Eventos.FormacionPartido_Alta @idPartido = @p, @idSeleccion = @selY, @idJugador = @y1, @titular = 1;
EXEC Torneo.Partido_Modificacion @idPartido = @p, @idSede = @sede, @idSeleccionLocal = @selX,
     @idSeleccionVisitante = @selY, @fase = 910, @fechaHoraUTC = '2025-02-01 18:00', @estado = 'En juego',
     @nroPartidoOficial = 98071;
EXEC Eventos.Gol_Alta @idPartido = @p, @idJugador = @x1, @minuto = 10, @tipo = 'Jugada', @idPeriodo = 205;
EXEC Eventos.Gol_Alta @idPartido = @p, @idJugador = @x2, @minuto = 30, @tipo = 'Jugada', @idPeriodo = 205;
EXEC Eventos.Gol_Alta @idPartido = @p, @idJugador = @y1, @minuto = 60, @tipo = 'Jugada', @idPeriodo = 205;
EXEC Torneo.RegistrarResultado @idPartido = @p, @golLocal = 2, @golVisitante = 1, @cantPublico = 40000;

-- 98072: 0-0 sin eventos
EXEC Torneo.Partido_Alta @idSede = @sede, @idSeleccionLocal = @selX, @idSeleccionVisitante = @selZ, @fase = 910,
     @fechaHoraUTC = '2025-02-04 18:00', @nroPartidoOficial = 98072, @idPartido = @p OUTPUT;
EXEC Torneo.RegistrarResultado @idPartido = @p, @golLocal = 0, @golVisitante = 0, @cantPublico = 30000;

-- 98073: 1-1 en el juego (X1 y Y1) y 3-2 en los penales (minuto NULL) para XXA
EXEC Torneo.Partido_Alta @idSede = @sede, @idSeleccionLocal = @selX, @idSeleccionVisitante = @selY, @fase = 911,
     @fechaHoraUTC = '2025-02-08 02:00', @nroPartidoOficial = 98073, @idPartido = @p OUTPUT;
EXEC Eventos.FormacionPartido_Alta @idPartido = @p, @idSeleccion = @selX, @idJugador = @x1, @titular = 1;
EXEC Eventos.FormacionPartido_Alta @idPartido = @p, @idSeleccion = @selX, @idJugador = @x2, @titular = 1;
EXEC Eventos.FormacionPartido_Alta @idPartido = @p, @idSeleccion = @selX, @idJugador = @x3, @titular = 1;
EXEC Eventos.FormacionPartido_Alta @idPartido = @p, @idSeleccion = @selY, @idJugador = @y1, @titular = 1;
EXEC Eventos.FormacionPartido_Alta @idPartido = @p, @idSeleccion = @selY, @idJugador = @y2, @titular = 1;
EXEC Torneo.Partido_Modificacion @idPartido = @p, @idSede = @sede, @idSeleccionLocal = @selX,
     @idSeleccionVisitante = @selY, @fase = 911, @fechaHoraUTC = '2025-02-08 02:00', @estado = 'En juego',
     @nroPartidoOficial = 98073;
EXEC Eventos.Gol_Alta @idPartido = @p, @idJugador = @x1, @minuto = 20, @tipo = 'Jugada', @idPeriodo = 205;
EXEC Eventos.Gol_Alta @idPartido = @p, @idJugador = @y1, @minuto = 70, @tipo = 'Jugada', @idPeriodo = 205;
EXEC Eventos.Gol_Alta @idPartido = @p, @idJugador = @x1, @tipo = 'Penal', @idPeriodo = 206;
EXEC Eventos.Gol_Alta @idPartido = @p, @idJugador = @x2, @tipo = 'Penal', @idPeriodo = 206;
EXEC Eventos.Gol_Alta @idPartido = @p, @idJugador = @x3, @tipo = 'Penal', @idPeriodo = 206;
EXEC Eventos.Gol_Alta @idPartido = @p, @idJugador = @y1, @tipo = 'Penal', @idPeriodo = 206;
EXEC Eventos.Gol_Alta @idPartido = @p, @idJugador = @y2, @tipo = 'Penal', @idPeriodo = 206;
EXEC Torneo.RegistrarResultado @idPartido = @p, @golLocal = 1, @golVisitante = 1, @cantPublico = 45000;

-- 98074: programado, todavía sin resultado
EXEC Torneo.Partido_Alta @idSede = @sede, @idSeleccionLocal = @selY, @idSeleccionVisitante = @selZ, @fase = 910,
     @fechaHoraUTC = '2030-03-01 18:00', @nroPartidoOficial = 98074;
GO

/* =============================================================================
   1. Torneo.Reporte_Resultados
   El resultado se guarda en #r y se cuentan solo los partidos de prueba
   (nroPartido 98071 a 98074).
   ============================================================================= */
PRINT '--- 1. Torneo.Reporte_Resultados ---';

DROP TABLE IF EXISTS #r;
CREATE TABLE #r (
    nroPartido int, fase nvarchar(100), grupo nvarchar(5), estado varchar(15), fechaLocal date, horaLocal time(0),
    sede nvarchar(100), ciudad nvarchar(100), seleccionLocal nvarchar(100), golLocal int, golVisitante int,
    seleccionVisitante nvarchar(100), marcador nvarchar(200), penalesLocal int, penalesVisitante int,
    ganador nvarchar(100), cantPublico int);

DECLARE @sede int = (SELECT idSede FROM Torneo.Sede WHERE nombreEstadio = N'Estadio Prueba 80i');
DECLARE @selY int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'XYA');
DECLARE @selZ int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'XZA');

-- PRUEBA 1.1: sin filtros (los tres partidos finalizados de la sede de prueba, en orden de hora)
-- Resultado esperado: sin filtros devuelve todos los partidos Finalizados de vw_Fixture; el de la sede de
-- prueba son 98071, 98072 y 98073 (no el 98074, que está Programado), ordenados por hora.
BEGIN TRY
    DELETE FROM #r;
    INSERT INTO #r EXEC Torneo.Reporte_Resultados;
    SELECT 'EVIDENCIA 1.1' AS momento, nroPartido, fase, estado, fechaLocal, horaLocal, marcador, ganador
    FROM #r WHERE nroPartido BETWEEN 98071 AND 98074 ORDER BY fechaLocal, horaLocal;
    IF (SELECT STRING_AGG(CAST(nroPartido AS varchar(10)), ',') WITHIN GROUP (ORDER BY fechaLocal, horaLocal)
        FROM #r WHERE nroPartido BETWEEN 98071 AND 98074) = '98071,98072,98073'
       AND (SELECT COUNT(*) FROM #r) = (SELECT COUNT(*) FROM Torneo.vw_Fixture WHERE estado = 'Finalizado')
        PRINT '[OK] PRUEBA 1.1: la consulta sin filtros devuelve los partidos finalizados.';
    ELSE PRINT '[FALLO] PRUEBA 1.1: el resultado no es el esperado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.2: partido con ganador por goles (98071, 2-1)
-- Resultado esperado: marcador "XXA 2 - 1 XYA", ganador el país X, grupo A, 2025-02-01 13:00 local
-- (18:00 UTC con la sede en UTC-5), sin penales y con 40000 espectadores.
BEGIN TRY
    DELETE FROM #r;
    INSERT INTO #r EXEC Torneo.Reporte_Resultados @idSede = @sede;
    SELECT 'EVIDENCIA 1.2' AS momento, * FROM #r WHERE nroPartido = 98071;
    IF EXISTS (SELECT 1 FROM #r WHERE nroPartido = 98071 AND marcador = N'XXA 2 - 1 XYA'
               AND ganador = N'País Prueba 80i X' AND grupo = 'A' AND estado = 'Finalizado'
               AND fechaLocal = '2025-02-01' AND horaLocal = '13:00:00'
               AND golLocal = 2 AND golVisitante = 1 AND penalesLocal IS NULL AND penalesVisitante IS NULL
               AND cantPublico = 40000 AND seleccionLocal = N'País Prueba 80i X'
               AND seleccionVisitante = N'País Prueba 80i Y')
        PRINT '[OK] PRUEBA 1.2: marcador, ganador y hora local correctos.';
    ELSE PRINT '[FALLO] PRUEBA 1.2: la fila no es la esperada.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.3: empate en fase de grupos (98072, 0-0)
-- Resultado esperado: marcador "XXA 0 - 0 XZA" y ganador "Empate".
BEGIN TRY
    DELETE FROM #r;
    INSERT INTO #r EXEC Torneo.Reporte_Resultados @idSede = @sede;
    SELECT 'EVIDENCIA 1.3' AS momento, nroPartido, marcador, ganador FROM #r WHERE nroPartido = 98072;
    IF EXISTS (SELECT 1 FROM #r WHERE nroPartido = 98072 AND marcador = N'XXA 0 - 0 XZA'
               AND ganador = N'Empate' AND penalesLocal IS NULL)
        PRINT '[OK] PRUEBA 1.3: empate informado.';
    ELSE PRINT '[FALLO] PRUEBA 1.3: la fila no es la esperada.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.4: eliminatoria definida por penales (98073, 1-1 y penales 3-2)
-- Resultado esperado: marcador "XXA 1 - 1 XYA (3-2 pen.)", penales 3 y 2 (no suman al marcador), ganador
-- el país X, grupo NULL (es eliminatoria) y fecha local 2025-02-07 aunque en UTC ya sea el 08.
BEGIN TRY
    SELECT 'EVIDENCIA 1.4' AS momento, nroPartido, fase, grupo, fechaLocal, horaLocal, marcador,
           penalesLocal, penalesVisitante, ganador
    FROM #r WHERE nroPartido = 98073;
    IF EXISTS (SELECT 1 FROM #r WHERE nroPartido = 98073 AND marcador = N'XXA 1 - 1 XYA (3-2 pen.)'
               AND golLocal = 1 AND golVisitante = 1 AND penalesLocal = 3 AND penalesVisitante = 2
               AND ganador = N'País Prueba 80i X' AND grupo IS NULL
               AND fechaLocal = '2025-02-07' AND horaLocal = '21:00:00')
        PRINT '[OK] PRUEBA 1.4: penales, ganador y fecha local correctos.';
    ELSE PRINT '[FALLO] PRUEBA 1.4: la fila no es la esperada.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.5: incluir los partidos sin resultado (@soloFinalizados = 0)
-- Resultado esperado: aparece también el 98074 (Programado) con marcador y ganador NULL.
BEGIN TRY
    DELETE FROM #r;
    INSERT INTO #r EXEC Torneo.Reporte_Resultados @idSede = @sede, @soloFinalizados = 0;
    SELECT 'EVIDENCIA 1.5' AS momento, nroPartido, estado, golLocal, marcador, ganador FROM #r ORDER BY nroPartido;
    IF (SELECT COUNT(*) FROM #r) = 4
       AND EXISTS (SELECT 1 FROM #r WHERE nroPartido = 98074 AND estado = 'Programado'
                   AND golLocal IS NULL AND marcador IS NULL AND ganador IS NULL)
        PRINT '[OK] PRUEBA 1.5: el partido sin resultado se informa sin marcador ni ganador.';
    ELSE PRINT '[FALLO] PRUEBA 1.5: el resultado no es el esperado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.5: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.6: @soloFinalizados en NULL
-- Resultado esperado: se toma como 1, igual que el valor por defecto: 3 partidos.
BEGIN TRY
    DELETE FROM #r;
    INSERT INTO #r EXEC Torneo.Reporte_Resultados @idSede = @sede, @soloFinalizados = NULL;
    SELECT 'EVIDENCIA 1.6' AS momento, COUNT(*) AS partidos FROM #r;
    IF (SELECT COUNT(*) FROM #r) = 3 AND NOT EXISTS (SELECT 1 FROM #r WHERE nroPartido = 98074)
        PRINT '[OK] PRUEBA 1.6: NULL equivale a solo finalizados.';
    ELSE PRINT '[FALLO] PRUEBA 1.6: el resultado no es el esperado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.6: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.7: filtro por selección (XYA juega de visitante en 98071 y 98073 y de local en 98074)
-- Resultado esperado: 98071 y 98073 (el 98074 no tiene resultado).
BEGIN TRY
    DELETE FROM #r;
    INSERT INTO #r EXEC Torneo.Reporte_Resultados @idSeleccion = @selY;
    SELECT 'EVIDENCIA 1.7' AS momento, nroPartido, marcador FROM #r ORDER BY nroPartido;
    IF (SELECT STRING_AGG(CAST(nroPartido AS varchar(10)), ',') WITHIN GROUP (ORDER BY nroPartido) FROM #r) = '98071,98073'
        PRINT '[OK] PRUEBA 1.7: filtro por selección.';
    ELSE PRINT '[FALLO] PRUEBA 1.7: el resultado no es el esperado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.7: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.8: filtro por fase (910, grupos) y sede
-- Resultado esperado: 98071 y 98072 (el 98073 es de la fase 911).
BEGIN TRY
    DELETE FROM #r;
    INSERT INTO #r EXEC Torneo.Reporte_Resultados @idSede = @sede, @idFase = 910;
    SELECT 'EVIDENCIA 1.8' AS momento, nroPartido, fase FROM #r ORDER BY nroPartido;
    IF (SELECT STRING_AGG(CAST(nroPartido AS varchar(10)), ',') WITHIN GROUP (ORDER BY nroPartido) FROM #r) = '98071,98072'
        PRINT '[OK] PRUEBA 1.8: filtro por fase.';
    ELSE PRINT '[FALLO] PRUEBA 1.8: el resultado no es el esperado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.8: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.9: filtro por fecha local
-- Resultado esperado: el rango 2025-02-07 a 2025-02-07 devuelve solo 98073 (en UTC es del 08).
BEGIN TRY
    DELETE FROM #r;
    INSERT INTO #r EXEC Torneo.Reporte_Resultados @idSede = @sede, @fechaDesde = '2025-02-07', @fechaHasta = '2025-02-07';
    SELECT 'EVIDENCIA 1.9' AS momento, nroPartido, fechaLocal, horaLocal FROM #r;
    IF (SELECT STRING_AGG(CAST(nroPartido AS varchar(10)), ',') FROM #r) = '98073'
        PRINT '[OK] PRUEBA 1.9: el filtro de fecha usa la fecha local de la sede.';
    ELSE PRINT '[FALLO] PRUEBA 1.9: el resultado no es el esperado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.9: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.10: filtro por sede sin otros filtros
-- Resultado esperado: los tres partidos finalizados de la sede de prueba.
BEGIN TRY
    DELETE FROM #r;
    INSERT INTO #r EXEC Torneo.Reporte_Resultados @idSede = @sede;
    SELECT 'EVIDENCIA 1.10' AS momento, nroPartido, sede FROM #r ORDER BY nroPartido;
    IF (SELECT STRING_AGG(CAST(nroPartido AS varchar(10)), ',') WITHIN GROUP (ORDER BY nroPartido) FROM #r) = '98071,98072,98073'
        PRINT '[OK] PRUEBA 1.10: filtro por sede.';
    ELSE PRINT '[FALLO] PRUEBA 1.10: el resultado no es el esperado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.10: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.11: filtros que no encuentran partidos
-- Resultado esperado: cero filas y sin error (XZA no jugó ninguna eliminatoria).
BEGIN TRY
    DELETE FROM #r;
    INSERT INTO #r EXEC Torneo.Reporte_Resultados @idFase = 911, @idSeleccion = @selZ;
    SELECT 'EVIDENCIA 1.11' AS momento, COUNT(*) AS partidos FROM #r;
    IF (SELECT COUNT(*) FROM #r) = 0
        PRINT '[OK] PRUEBA 1.11: sin coincidencias devuelve cero filas.';
    ELSE PRINT '[FALLO] PRUEBA 1.11: se esperaban cero filas.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.11: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.12: acumulación (los cuatro errores a la vez)
-- Resultado esperado: error 50001 con las cuatro líneas en el mismo mensaje.
BEGIN TRY
    EXEC Torneo.Reporte_Resultados @idSede = -1, @idFase = -1, @idSeleccion = -1,
         @fechaDesde = '2025-02-02', @fechaHasta = '2025-02-01';
    PRINT '[FALLO] PRUEBA 1.12: no se detectaron los errores.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() = N'No se pudo generar el reporte de resultados:'
           + CHAR(10) + N'- La sede no existe.'
           + CHAR(10) + N'- La fase no existe.'
           + CHAR(10) + N'- La selección no existe.'
           + CHAR(10) + N'- La fecha desde no puede ser posterior a la fecha hasta.'
        PRINT '[OK] PRUEBA 1.12: los 4 errores se informaron juntos.';
    ELSE PRINT '[FALLO] PRUEBA 1.12: ' + ERROR_MESSAGE();
END CATCH;

DROP TABLE IF EXISTS #r;
GO

/* =============================================================================
   2. Equipos.Reporte_SeleccionesPlantillas (XML)
   El XML se guarda en #x y se consulta con XQuery.
   ============================================================================= */
PRINT '--- 2. Equipos.Reporte_SeleccionesPlantillas ---';

DROP TABLE IF EXISTS #x;
CREATE TABLE #x (plantillas xml);

DECLARE @x xml;
DECLARE @selX int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'XXA');
DECLARE @selZ int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'XZA');
DECLARE @idListadoX3 int = (SELECT lj.id FROM Equipos.ListadoJugadores lj
                            JOIN Equipos.Jugador j ON j.id = lj.idJugador
                            WHERE j.nombre = N'X3' AND j.apellido = N'Prueba80i');

-- PRUEBA 2.1: una selección con sus tres convocados
-- Resultado esperado: una <seleccion> XXA (país X, grupo A, UEFA) con cantidadConvocados = 3 y tres
-- <jugador> ordenados por dorsal (9, 10, 11).
BEGIN TRY
    DELETE FROM #x;
    INSERT INTO #x EXEC Equipos.Reporte_SeleccionesPlantillas @idSeleccion = @selX;
    SET @x = (SELECT TOP 1 plantillas FROM #x);
    SELECT 'EVIDENCIA 2.1' AS momento, @x AS plantillas;
    IF @x.value('count(/selecciones/seleccion)', 'int') = 1
       AND @x.value('(/selecciones/seleccion/@abreviacion)[1]', 'varchar(10)') = 'XXA'
       AND @x.value('(/selecciones/seleccion/@pais)[1]', 'nvarchar(100)') = N'País Prueba 80i X'
       AND @x.value('(/selecciones/seleccion/@grupo)[1]', 'varchar(5)') = 'A'
       AND @x.value('(/selecciones/seleccion/@confederacion)[1]', 'varchar(10)') = 'UEFA'
       AND @x.value('(/selecciones/seleccion/@cantidadConvocados)[1]', 'int') = 3
       AND @x.value('count(/selecciones/seleccion/convocados/jugador)', 'int') = 3
       AND @x.query('data(/selecciones/seleccion/convocados/jugador/@dorsal)').value('.', 'varchar(50)') = '9 10 11'
        PRINT '[OK] PRUEBA 2.1: selección con su vector de convocados ordenado por dorsal.';
    ELSE PRINT '[FALLO] PRUEBA 2.1: el XML no tiene la estructura esperada.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.2: datos de cada convocado (nombre, posición, club y dorsal)
-- Resultado esperado: el dorsal 9 es "X1 Prueba80i", Delantero, de "Club Prueba"; el dorsal 11 (X3) no
-- tiene posición ni club cargados, así que su <jugador> no trae esos elementos.
BEGIN TRY
    SELECT 'EVIDENCIA 2.2' AS momento, @x.query('/selecciones/seleccion/convocados/jugador') AS convocados;
    IF @x.value('(/selecciones/seleccion/convocados/jugador[@dorsal="9"]/nombre)[1]', 'nvarchar(100)') = N'X1 Prueba80i'
       AND @x.value('(/selecciones/seleccion/convocados/jugador[@dorsal="9"]/posicion)[1]', 'varchar(20)') = 'Delantero'
       AND @x.value('(/selecciones/seleccion/convocados/jugador[@dorsal="9"]/club)[1]', 'nvarchar(100)') = N'Club Prueba'
       AND @x.value('(/selecciones/seleccion/convocados/jugador[@dorsal="10"]/posicion)[1]', 'varchar(20)') = 'Defensor'
       AND @x.exist('/selecciones/seleccion/convocados/jugador[@dorsal="11"]/posicion') = 0
       AND @x.exist('/selecciones/seleccion/convocados/jugador[@dorsal="11"]/club') = 0
        PRINT '[OK] PRUEBA 2.2: nombre, posición, club y dorsal de cada convocado.';
    ELSE PRINT '[FALLO] PRUEBA 2.2: los datos de los convocados no son los esperados.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.3: selección sin convocados (XZA)
-- Resultado esperado: <seleccion> con cantidadConvocados = 0 y sin el nodo <convocados>.
BEGIN TRY
    DELETE FROM #x;
    INSERT INTO #x EXEC Equipos.Reporte_SeleccionesPlantillas @idSeleccion = @selZ;
    SET @x = (SELECT TOP 1 plantillas FROM #x);
    SELECT 'EVIDENCIA 2.3' AS momento, @x AS plantillas;
    IF @x.value('count(/selecciones/seleccion)', 'int') = 1
       AND @x.value('(/selecciones/seleccion/@cantidadConvocados)[1]', 'int') = 0
       AND @x.exist('/selecciones/seleccion/convocados') = 0
        PRINT '[OK] PRUEBA 2.3: selección sin convocados.';
    ELSE PRINT '[FALLO] PRUEBA 2.3: el XML no es el esperado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.4: baja de un convocado (por defecto solo activos; con @soloActivos = 0 también las bajas)
-- Resultado esperado: después de dar de baja a X3 por lesión, el reporte por defecto muestra los dorsales
-- 9 y 10 (cantidadConvocados = 2); con @soloActivos = 0 muestra 9, 10 y 11 (cantidadConvocados = 3) y el
-- dorsal 11 trae fechaBaja = 2025-02-10 y motivoBaja = "Lesion".
BEGIN TRY
    EXEC Equipos.ListadoJugadores_Baja @id = @idListadoX3, @fechaBaja = '2025-02-10', @motivoBaja = 'Lesion';

    DELETE FROM #x;
    INSERT INTO #x EXEC Equipos.Reporte_SeleccionesPlantillas @idSeleccion = @selX;
    SET @x = (SELECT TOP 1 plantillas FROM #x);
    SELECT 'ANTES 2.4 (solo activos)' AS momento, @x AS plantillas;
    DECLARE @soloActivosOk bit = CASE
        WHEN @x.value('(/selecciones/seleccion/@cantidadConvocados)[1]', 'int') = 2
         AND @x.query('data(/selecciones/seleccion/convocados/jugador/@dorsal)').value('.', 'varchar(50)') = '9 10'
        THEN 1 ELSE 0 END;

    DELETE FROM #x;
    INSERT INTO #x EXEC Equipos.Reporte_SeleccionesPlantillas @idSeleccion = @selX, @soloActivos = 0;
    SET @x = (SELECT TOP 1 plantillas FROM #x);
    SELECT 'DESPUES 2.4 (con bajas)' AS momento, @x AS plantillas;
    IF @soloActivosOk = 1
       AND @x.value('(/selecciones/seleccion/@cantidadConvocados)[1]', 'int') = 3
       AND @x.query('data(/selecciones/seleccion/convocados/jugador/@dorsal)').value('.', 'varchar(50)') = '9 10 11'
       AND @x.value('(/selecciones/seleccion/convocados/jugador[@dorsal="11"]/@fechaBaja)[1]', 'varchar(10)') = '2025-02-10'
       AND @x.value('(/selecciones/seleccion/convocados/jugador[@dorsal="11"]/@motivoBaja)[1]', 'varchar(100)') = 'Lesion'
       AND @x.exist('/selecciones/seleccion/convocados/jugador[@dorsal="9"]/@fechaBaja') = 0
        PRINT '[OK] PRUEBA 2.4: las bajas solo se informan con @soloActivos = 0.';
    ELSE PRINT '[FALLO] PRUEBA 2.4: el XML no es el esperado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.5: sin filtros (todas las selecciones)
-- Resultado esperado: un <seleccion> por cada selección de la base, entre ellas las tres de prueba
-- ordenadas por nombre de país (XXA, XYA, XZA).
BEGIN TRY
    DELETE FROM #x;
    INSERT INTO #x EXEC Equipos.Reporte_SeleccionesPlantillas;
    SET @x = (SELECT TOP 1 plantillas FROM #x);
    SELECT 'EVIDENCIA 2.5' AS momento, @x.value('count(/selecciones/seleccion)', 'int') AS selecciones,
           (SELECT COUNT(*) FROM Equipos.Seleccion) AS seleccionesEnTabla;
    IF @x.value('count(/selecciones/seleccion)', 'int') = (SELECT COUNT(*) FROM Equipos.Seleccion)
       AND @x.query('data(/selecciones/seleccion[@abreviacion="XXA" or @abreviacion="XYA" or @abreviacion="XZA"]/@abreviacion)')
           .value('.', 'varchar(50)') = 'XXA XYA XZA'
        PRINT '[OK] PRUEBA 2.5: todas las selecciones, ordenadas por país.';
    ELSE PRINT '[FALLO] PRUEBA 2.5: el XML no es el esperado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.5: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.6: selección inexistente
-- Resultado esperado: error 50001 "La selección no existe."
BEGIN TRY
    EXEC Equipos.Reporte_SeleccionesPlantillas @idSeleccion = -1;
    PRINT '[FALLO] PRUEBA 2.6: se aceptó una selección inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%selección no existe%'
        PRINT '[OK] PRUEBA 2.6: selección inexistente rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 2.6: ' + ERROR_MESSAGE();
END CATCH;

DROP TABLE IF EXISTS #x;
GO

/* =============================================================================
   LIMPIEZA FINAL
   ============================================================================= */
DELETE FROM Eventos.Gol WHERE idPartido IN
    (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 98071 AND 98074);
DELETE FROM Eventos.FormacionPartido WHERE idPartido IN
    (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 98071 AND 98074);
DELETE FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 98071 AND 98074;
DELETE FROM Equipos.ListadoJugadores WHERE idSeleccion IN
    (SELECT id FROM Equipos.Seleccion WHERE abreviacion IN ('XXA', 'XYA', 'XZA'));
DELETE FROM Equipos.Jugador WHERE apellido = N'Prueba80i';
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('XXA', 'XYA', 'XZA');
DELETE FROM Torneo.Sede WHERE nombreEstadio = N'Estadio Prueba 80i';
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('XX', 'XY', 'XZ');
DELETE FROM Torneo.Fase WHERE idFase IN (910, 911);
DELETE FROM Torneo.Periodo WHERE idPeriodo IN (205, 206);

PRINT '================================================================================';
PRINT ' FIN DE LAS PRUEBAS: 60_Reportes_Torneo.sql (18 pruebas)';
PRINT '================================================================================';
GO
