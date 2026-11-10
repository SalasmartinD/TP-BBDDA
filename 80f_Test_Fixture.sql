/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 09/11/2026

 Objetivo    : Pruebas de 30a_Fixture.sql (Torneo.vw_Fixture y
               Torneo.ConsultarFixture): conversión de la hora local con
               AT TIME ZONE (incluido el horario de verano y el cambio de día),
               cada filtro por separado y combinados, y las validaciones.

 Requisitos  : 00_InitialSchema.sql, 10a, 10b y 30a. Funciona con o sin la
               carga base: los filtros usan solo los datos de prueba.

 Datos de prueba:
 - Países con códigos ISO de uso privado (XA, XB, XC, XD / XAA, XBA, XCA, XDA),
   que la norma ISO 3166 nunca asigna a un país real.
 - Dos sedes: Este (Eastern Standard Time) y Oeste (Pacific Standard Time).
 - Fases 907 (grupos) y 908 (eliminatoria), partidos oficiales 98041 a 98043:
     98041  fase 907  sede Este   XAA-XBA  2030-01-15 18:00 UTC  (invierno)
     98042  fase 907  sede Oeste  XCA-XDA  2030-01-16 02:00 UTC  (cruza la medianoche)
     98043  fase 908  sede Este   XAA-XCA  2030-07-15 18:00 UTC  (verano)
 - Se limpian al inicio y al final: el script se puede ejecutar varias veces.

 Cada prueba imprime [OK] o [FALLO]. Resultado esperado: todas [OK].
================================================================================
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

PRINT '================================================================================';
PRINT ' PRUEBAS: 30a_Fixture.sql';
PRINT '================================================================================';
GO

/* =============================================================================
   LIMPIEZA PREVIA (DELETE directo en orden inverso de claves foráneas, por si
   una corrida anterior se cortó y dejó datos con dependencias)
   ============================================================================= */
DELETE FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 98041 AND 98043;
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('XAA', 'XBA', 'XCA', 'XDA');
DELETE FROM Torneo.Sede WHERE nombreEstadio IN (N'Estadio Prueba 80f Este', N'Estadio Prueba 80f Oeste');
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('XA', 'XB', 'XC', 'XD');
DELETE FROM Torneo.Fase WHERE idFase IN (907, 908);
GO

/* =============================================================================
   FIXTURE con los SP de 10a y 10b
   ============================================================================= */
EXEC Torneo.Pais_Alta @nombre = N'País Prueba 80f A', @codigoISO2 = 'XA', @codigoISO3 = 'XAA';
EXEC Torneo.Pais_Alta @nombre = N'País Prueba 80f B', @codigoISO2 = 'XB', @codigoISO3 = 'XBA';
EXEC Torneo.Pais_Alta @nombre = N'País Prueba 80f C', @codigoISO2 = 'XC', @codigoISO3 = 'XCA';
EXEC Torneo.Pais_Alta @nombre = N'País Prueba 80f D', @codigoISO2 = 'XD', @codigoISO3 = 'XDA';
EXEC Torneo.Fase_Alta @idFase = 907, @nombre = 'Fase Prueba 80f Grupos', @esEliminatoria = 0, @orden = 1;
EXEC Torneo.Fase_Alta @idFase = 908, @nombre = 'Fase Prueba 80f Eliminatoria', @esEliminatoria = 1, @orden = 2;
GO

DECLARE @idPaisA int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XA');
DECLARE @idPaisB int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XB');
DECLARE @idPaisC int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XC');
DECLARE @idPaisD int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XD');
DECLARE @selA int, @selB int, @selC int, @selD int, @este int, @oeste int;
EXEC Equipos.Seleccion_Alta @idPais = @idPaisA, @confederacion = 'UEFA', @abreviacion = 'XAA', @id = @selA OUTPUT;
EXEC Equipos.Seleccion_Alta @idPais = @idPaisB, @confederacion = 'UEFA', @abreviacion = 'XBA', @id = @selB OUTPUT;
EXEC Equipos.Seleccion_Alta @idPais = @idPaisC, @confederacion = 'UEFA', @abreviacion = 'XCA', @id = @selC OUTPUT;
EXEC Equipos.Seleccion_Alta @idPais = @idPaisD, @confederacion = 'UEFA', @abreviacion = 'XDA', @id = @selD OUTPUT;
EXEC Torneo.Sede_Alta @nombreEstadio = N'Estadio Prueba 80f Este', @ciudad = N'Ciudad Prueba', @idPais = @idPaisA,
     @husoHorario = 'Eastern Standard Time', @capacidad = 30000, @idSede = @este OUTPUT;
EXEC Torneo.Sede_Alta @nombreEstadio = N'Estadio Prueba 80f Oeste', @ciudad = N'Ciudad Prueba', @idPais = @idPaisA,
     @husoHorario = 'Pacific Standard Time', @capacidad = 30000, @idSede = @oeste OUTPUT;

EXEC Torneo.Partido_Alta @idSede = @este, @idSeleccionLocal = @selA, @idSeleccionVisitante = @selB, @fase = 907,
     @fechaHoraUTC = '2030-01-15 18:00', @nroPartidoOficial = 98041;
EXEC Torneo.Partido_Alta @idSede = @oeste, @idSeleccionLocal = @selC, @idSeleccionVisitante = @selD, @fase = 907,
     @fechaHoraUTC = '2030-01-16 02:00', @nroPartidoOficial = 98042;
EXEC Torneo.Partido_Alta @idSede = @este, @idSeleccionLocal = @selA, @idSeleccionVisitante = @selC, @fase = 908,
     @fechaHoraUTC = '2030-07-15 18:00', @nroPartidoOficial = 98043;
GO

/* =============================================================================
   1. Torneo.vw_Fixture: hora local con AT TIME ZONE
   ============================================================================= */
PRINT '--- 1. Torneo.vw_Fixture ---';

-- PRUEBA 1.1: partido de invierno en la sede Este (UTC-5)
-- Resultado esperado: 18:00 UTC es 13:00 local, offset -05:00, fecha local 2030-01-15.
BEGIN TRY
    SELECT 'EVIDENCIA 1.1' AS momento, nroPartidoOficial, fechaHoraUTC, fechaHoraLocal, husoHorarioSede
    FROM Torneo.vw_Fixture WHERE nroPartidoOficial = 98041;
    IF EXISTS (SELECT 1 FROM Torneo.vw_Fixture WHERE nroPartidoOficial = 98041
               AND fechaHoraLocal = CAST('2030-01-15 13:00:00 -05:00' AS datetimeoffset(0))
               AND DATEPART(TZOFFSET, fechaHoraLocal) = -300
               AND fechaLocal = '2030-01-15' AND horaLocal = '13:00:00')
        PRINT '[OK] PRUEBA 1.1: hora local de invierno correcta.';
    ELSE PRINT '[FALLO] PRUEBA 1.1: la hora local no es la esperada.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.2: misma sede en verano: el huso aplica el horario de verano (UTC-4)
-- Resultado esperado: 18:00 UTC es 14:00 local, offset -04:00.
BEGIN TRY
    SELECT 'EVIDENCIA 1.2' AS momento, nroPartidoOficial, fechaHoraUTC, fechaHoraLocal, husoHorarioSede
    FROM Torneo.vw_Fixture WHERE nroPartidoOficial = 98043;
    IF EXISTS (SELECT 1 FROM Torneo.vw_Fixture WHERE nroPartidoOficial = 98043
               AND fechaHoraLocal = CAST('2030-07-15 14:00:00 -04:00' AS datetimeoffset(0))
               AND DATEPART(TZOFFSET, fechaHoraLocal) = -240 AND horaLocal = '14:00:00')
        PRINT '[OK] PRUEBA 1.2: horario de verano aplicado.';
    ELSE PRINT '[FALLO] PRUEBA 1.2: la hora local no es la esperada.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.3: partido que cambia de día respecto de UTC (sede Oeste, UTC-8)
-- Resultado esperado: 2030-01-16 02:00 UTC es 2030-01-15 18:00 local: la fecha local es
-- el 15 aunque la fecha UTC sea el 16.
BEGIN TRY
    SELECT 'EVIDENCIA 1.3' AS momento, nroPartidoOficial, fechaHoraUTC, fechaHoraLocal, fechaLocal
    FROM Torneo.vw_Fixture WHERE nroPartidoOficial = 98042;
    IF EXISTS (SELECT 1 FROM Torneo.vw_Fixture WHERE nroPartidoOficial = 98042
               AND fechaLocal = '2030-01-15' AND horaLocal = '18:00:00'
               AND CAST(fechaHoraUTC AS date) = '2030-01-16')
        PRINT '[OK] PRUEBA 1.3: la fecha local difiere de la fecha UTC.';
    ELSE PRINT '[FALLO] PRUEBA 1.3: la fecha local no es la esperada.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.4: la vista trae fase, sede y selecciones con sus nombres
-- Resultado esperado: 98041 es "Fase Prueba 80f Grupos" en "Estadio Prueba 80f Este",
-- XAA (local) contra XBA (visitante), sin resultado cargado (Programado).
BEGIN TRY
    IF EXISTS (SELECT 1 FROM Torneo.vw_Fixture WHERE nroPartidoOficial = 98041
               AND fase = 'Fase Prueba 80f Grupos' AND sede = N'Estadio Prueba 80f Este'
               AND abreviacionLocal = 'XAA' AND abreviacionVisitante = 'XBA'
               AND seleccionLocal = N'País Prueba 80f A' AND seleccionVisitante = N'País Prueba 80f B'
               AND estado = 'Programado' AND golLocal IS NULL AND golVisitante IS NULL)
        PRINT '[OK] PRUEBA 1.4: la vista muestra fase, sede, selecciones y estado.';
    ELSE PRINT '[FALLO] PRUEBA 1.4: la vista no muestra los datos esperados.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.4: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   2. Torneo.ConsultarFixture: filtros
   El resultado se guarda en #f y se cuentan solo los partidos de prueba
   (98041 a 98043), así la carga base no altera los resultados.
   ============================================================================= */
PRINT '--- 2. Torneo.ConsultarFixture: filtros ---';

DROP TABLE IF EXISTS #f;
SELECT TOP 0 * INTO #f FROM Torneo.vw_Fixture;
ALTER TABLE #f ADD fechaHoraConsulta datetimeoffset(0) NULL;

DECLARE @este int = (SELECT idSede FROM Torneo.Sede WHERE nombreEstadio = N'Estadio Prueba 80f Este');
DECLARE @oeste int = (SELECT idSede FROM Torneo.Sede WHERE nombreEstadio = N'Estadio Prueba 80f Oeste');
DECLARE @selA int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'XAA');
DECLARE @selB int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'XBA');

-- PRUEBA 2.1: sin filtros
-- Resultado esperado: incluye los 3 partidos de prueba, ordenados por hora UTC (98041, 98042, 98043).
BEGIN TRY
    DELETE FROM #f;
    INSERT INTO #f EXEC Torneo.ConsultarFixture;
    SELECT 'EVIDENCIA 2.1' AS momento, nroPartidoOficial, fechaHoraUTC, fechaHoraLocal
    FROM #f WHERE nroPartidoOficial BETWEEN 98041 AND 98043 ORDER BY fechaHoraUTC;
    IF (SELECT COUNT(*) FROM #f WHERE nroPartidoOficial BETWEEN 98041 AND 98043) = 3
       AND (SELECT STRING_AGG(CAST(nroPartidoOficial AS varchar(10)), ',') WITHIN GROUP (ORDER BY fechaHoraUTC)
            FROM #f WHERE nroPartidoOficial BETWEEN 98041 AND 98043) = '98041,98042,98043'
       AND (SELECT COUNT(*) FROM #f) = (SELECT COUNT(*) FROM Torneo.Partido)
       AND NOT EXISTS (SELECT 1 FROM #f WHERE fechaHoraConsulta IS NOT NULL)
        PRINT '[OK] PRUEBA 2.1: la consulta sin filtros devuelve todos los partidos ordenados por hora.';
    ELSE PRINT '[FALLO] PRUEBA 2.1: el resultado no es el esperado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.2: filtro por sede (Este)
-- Resultado esperado: solo 98041 y 98043.
BEGIN TRY
    DELETE FROM #f;
    INSERT INTO #f EXEC Torneo.ConsultarFixture @idSede = @este;
    SELECT 'EVIDENCIA 2.2' AS momento, nroPartidoOficial, sede FROM #f;
    IF (SELECT STRING_AGG(CAST(nroPartidoOficial AS varchar(10)), ',') WITHIN GROUP (ORDER BY nroPartidoOficial)
        FROM #f) = '98041,98043'
        PRINT '[OK] PRUEBA 2.2: filtro por sede.';
    ELSE PRINT '[FALLO] PRUEBA 2.2: el resultado no es el esperado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.3: filtro por fase (907)
-- Resultado esperado: solo 98041 y 98042.
BEGIN TRY
    DELETE FROM #f;
    INSERT INTO #f EXEC Torneo.ConsultarFixture @idFase = 907;
    IF (SELECT STRING_AGG(CAST(nroPartidoOficial AS varchar(10)), ',') WITHIN GROUP (ORDER BY nroPartidoOficial)
        FROM #f) = '98041,98042'
        PRINT '[OK] PRUEBA 2.3: filtro por fase.';
    ELSE PRINT '[FALLO] PRUEBA 2.3: el resultado no es el esperado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.4: filtro por selección, como local y como visitante
-- Resultado esperado: XAA juega de local en 98041 y 98043; XBA es visitante solo en 98041.
BEGIN TRY
    DELETE FROM #f;
    INSERT INTO #f EXEC Torneo.ConsultarFixture @idSeleccion = @selA;
    DECLARE @comoLocal varchar(100) = (SELECT STRING_AGG(CAST(nroPartidoOficial AS varchar(10)), ',')
                                       WITHIN GROUP (ORDER BY nroPartidoOficial) FROM #f);
    DELETE FROM #f;
    INSERT INTO #f EXEC Torneo.ConsultarFixture @idSeleccion = @selB;
    SELECT 'EVIDENCIA 2.4' AS momento, nroPartidoOficial, abreviacionLocal, abreviacionVisitante FROM #f;
    IF @comoLocal = '98041,98043' AND (SELECT STRING_AGG(CAST(nroPartidoOficial AS varchar(10)), ',') FROM #f) = '98041'
        PRINT '[OK] PRUEBA 2.4: filtro por selección (local y visitante).';
    ELSE PRINT '[FALLO] PRUEBA 2.4: el resultado no es el esperado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.5: filtro por fecha local (sede Oeste, 98042 es del 2030-01-15 local y del 16 en UTC)
-- Resultado esperado: con el día 2030-01-15 devuelve 98042; con el 2030-01-16 no devuelve nada.
BEGIN TRY
    DELETE FROM #f;
    INSERT INTO #f EXEC Torneo.ConsultarFixture @idSede = @oeste, @fechaDesde = '2030-01-15', @fechaHasta = '2030-01-15';
    DECLARE @dia15 int = (SELECT COUNT(*) FROM #f WHERE nroPartidoOficial = 98042);
    DELETE FROM #f;
    INSERT INTO #f EXEC Torneo.ConsultarFixture @idSede = @oeste, @fechaDesde = '2030-01-16', @fechaHasta = '2030-01-16';
    IF @dia15 = 1 AND (SELECT COUNT(*) FROM #f) = 0
        PRINT '[OK] PRUEBA 2.5: el filtro de fecha usa la fecha local de la sede.';
    ELSE PRINT '[FALLO] PRUEBA 2.5: el filtro de fecha no usó la fecha local.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.5: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.6: rango con un solo extremo (sede Este, solo fechaDesde = 2030-02-01)
-- Resultado esperado: solo 98043; con solo fechaHasta = 2030-02-01 devuelve solo 98041.
BEGIN TRY
    DELETE FROM #f;
    INSERT INTO #f EXEC Torneo.ConsultarFixture @idSede = @este, @fechaDesde = '2030-02-01';
    DECLARE @desde varchar(100) = (SELECT STRING_AGG(CAST(nroPartidoOficial AS varchar(10)), ',') FROM #f);
    DELETE FROM #f;
    INSERT INTO #f EXEC Torneo.ConsultarFixture @idSede = @este, @fechaHasta = '2030-02-01';
    IF @desde = '98043' AND (SELECT STRING_AGG(CAST(nroPartidoOficial AS varchar(10)), ',') FROM #f) = '98041'
        PRINT '[OK] PRUEBA 2.6: rango con un solo extremo.';
    ELSE PRINT '[FALLO] PRUEBA 2.6: el resultado no es el esperado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.6: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.7: filtros combinados (selección XAA y fase 908)
-- Resultado esperado: solo 98043.
BEGIN TRY
    DELETE FROM #f;
    INSERT INTO #f EXEC Torneo.ConsultarFixture @idSeleccion = @selA, @idFase = 908;
    IF (SELECT STRING_AGG(CAST(nroPartidoOficial AS varchar(10)), ',') FROM #f) = '98043'
        PRINT '[OK] PRUEBA 2.7: filtros combinados.';
    ELSE PRINT '[FALLO] PRUEBA 2.7: el resultado no es el esperado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.7: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.8: filtros sin coincidencias (selección XBA en la fase 908)
-- Resultado esperado: cero filas y sin error.
BEGIN TRY
    DELETE FROM #f;
    INSERT INTO #f EXEC Torneo.ConsultarFixture @idSeleccion = @selB, @idFase = 908;
    IF (SELECT COUNT(*) FROM #f) = 0
        PRINT '[OK] PRUEBA 2.8: sin coincidencias devuelve cero filas.';
    ELSE PRINT '[FALLO] PRUEBA 2.8: devolvió filas.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.8: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.9: hora en otro huso (Tokyo Standard Time, UTC+9) para 98041 y 98043
-- Resultado esperado: 98041 es 2030-01-16 03:00 +09:00; 98043 es 2030-07-16 03:00 +09:00
-- (Tokio no tiene horario de verano) y la hora local de la sede no cambia.
BEGIN TRY
    DELETE FROM #f;
    INSERT INTO #f EXEC Torneo.ConsultarFixture @idSede = @este, @husoHorarioConsulta = 'Tokyo Standard Time';
    SELECT 'EVIDENCIA 2.9' AS momento, nroPartidoOficial, fechaHoraLocal, fechaHoraConsulta FROM #f;
    IF EXISTS (SELECT 1 FROM #f WHERE nroPartidoOficial = 98041
               AND fechaHoraConsulta = CAST('2030-01-16 03:00:00 +09:00' AS datetimeoffset(0))
               AND horaLocal = '13:00:00')
       AND EXISTS (SELECT 1 FROM #f WHERE nroPartidoOficial = 98043
               AND fechaHoraConsulta = CAST('2030-07-16 03:00:00 +09:00' AS datetimeoffset(0)))
        PRINT '[OK] PRUEBA 2.9: hora de consulta en otro huso.';
    ELSE PRINT '[FALLO] PRUEBA 2.9: la hora de consulta no es la esperada.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.9: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   3. Torneo.ConsultarFixture: validaciones
   ============================================================================= */
PRINT '--- 3. Torneo.ConsultarFixture: validaciones ---';

-- PRUEBA 3.1: sede inexistente
-- Resultado esperado: error 50001 "La sede no existe."
BEGIN TRY
    EXEC Torneo.ConsultarFixture @idSede = -1;
    PRINT '[FALLO] PRUEBA 3.1: se aceptó una sede inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%sede no existe%'
        PRINT '[OK] PRUEBA 3.1: sede inexistente rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 3.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.2: fase inexistente
-- Resultado esperado: error 50001 "La fase no existe."
BEGIN TRY
    EXEC Torneo.ConsultarFixture @idFase = -1;
    PRINT '[FALLO] PRUEBA 3.2: se aceptó una fase inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%fase no existe%'
        PRINT '[OK] PRUEBA 3.2: fase inexistente rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 3.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.3: selección inexistente
-- Resultado esperado: error 50001 "La selección no existe."
BEGIN TRY
    EXEC Torneo.ConsultarFixture @idSeleccion = -1;
    PRINT '[FALLO] PRUEBA 3.3: se aceptó una selección inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%selección no existe%'
        PRINT '[OK] PRUEBA 3.3: selección inexistente rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 3.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.4: fecha desde posterior a la fecha hasta
-- Resultado esperado: error 50001 "La fecha desde no puede ser posterior a la fecha hasta."
BEGIN TRY
    EXEC Torneo.ConsultarFixture @fechaDesde = '2030-02-01', @fechaHasta = '2030-01-01';
    PRINT '[FALLO] PRUEBA 3.4: se aceptó un rango invertido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%fecha desde no puede ser posterior%'
        PRINT '[OK] PRUEBA 3.4: rango de fechas invertido rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 3.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.5: huso horario de consulta inválido
-- Resultado esperado: error 50001 "El huso horario de consulta no es un nombre válido..."
BEGIN TRY
    EXEC Torneo.ConsultarFixture @husoHorarioConsulta = 'Huso Que No Existe';
    PRINT '[FALLO] PRUEBA 3.5: se aceptó un huso inválido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%huso horario de consulta no es un nombre válido%'
        PRINT '[OK] PRUEBA 3.5: huso horario inválido rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 3.5: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.6: acumulación (los cinco errores a la vez)
-- Resultado esperado: error 50001 con las cinco líneas en el mismo mensaje.
BEGIN TRY
    EXEC Torneo.ConsultarFixture @idSede = -1, @idFase = -1, @idSeleccion = -1,
         @fechaDesde = '2030-02-01', @fechaHasta = '2030-01-01', @husoHorarioConsulta = 'Huso Que No Existe';
    PRINT '[FALLO] PRUEBA 3.6: no se detectaron los errores.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'%sede no existe%'
       AND ERROR_MESSAGE() LIKE N'%fase no existe%'
       AND ERROR_MESSAGE() LIKE N'%selección no existe%'
       AND ERROR_MESSAGE() LIKE N'%fecha desde no puede ser posterior%'
       AND ERROR_MESSAGE() LIKE N'%huso horario de consulta no es un nombre válido%'
        PRINT '[OK] PRUEBA 3.6: los 5 errores se informaron juntos.';
    ELSE PRINT '[FALLO] PRUEBA 3.6: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   LIMPIEZA FINAL
   ============================================================================= */
DROP TABLE IF EXISTS #f;
DELETE FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 98041 AND 98043;
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('XAA', 'XBA', 'XCA', 'XDA');
DELETE FROM Torneo.Sede WHERE nombreEstadio IN (N'Estadio Prueba 80f Este', N'Estadio Prueba 80f Oeste');
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('XA', 'XB', 'XC', 'XD');
DELETE FROM Torneo.Fase WHERE idFase IN (907, 908);

PRINT '================================================================================';
PRINT ' FIN DE LAS PRUEBAS: 30a_Fixture.sql (19 pruebas)';
PRINT '================================================================================';
GO
