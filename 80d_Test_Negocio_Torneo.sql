/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 09/11/2026

 Objetivo    : Pruebas de los SP de 20a_Negocio_Torneo.sql
               (Torneo.RegistrarResultado): casos exitosos con evidencia
               antes/después, casos que deben fallar en cada validación y
               comprobación del ROLLBACK cuando la operación falla.

 Requisitos  : 00_InitialSchema.sql, 10a, 10b, 11b (formaciones y goles) y 20a.

 Datos de prueba:
 - Países con códigos ISO de uso privado (QV, QW / QVA, QWA), que la norma
   ISO 3166 nunca asigna a un país real.
 - Fases 904 (grupos) y 905 (eliminatoria), períodos 203 y 204, partidos
   oficiales 98021 a 98027 y jugadores con apellido Prueba80d.
 - Se limpian al inicio y al final: el script se puede ejecutar varias veces.

 Cada prueba imprime [OK] o [FALLO]. Resultado esperado: todas [OK].
================================================================================
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

PRINT '================================================================================';
PRINT ' PRUEBAS: 20a_Negocio_Torneo.sql';
PRINT '================================================================================';
GO

/* =============================================================================
   LIMPIEZA PREVIA (DELETE directo en orden inverso de claves foráneas, por si
   una corrida anterior se cortó y dejó datos con dependencias)
   ============================================================================= */
DELETE FROM Eventos.Gol WHERE idPartido IN
    (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 98021 AND 98027);
DELETE FROM Eventos.FormacionPartido WHERE idPartido IN
    (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 98021 AND 98027);
DELETE FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 98021 AND 98027;
DELETE FROM Equipos.Jugador WHERE apellido = N'Prueba80d';
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('QVA', 'QWA');
DELETE FROM Torneo.Sede WHERE nombreEstadio = N'Estadio Prueba 80d';
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('QV', 'QW');
DELETE FROM Torneo.Fase WHERE idFase IN (904, 905);
DELETE FROM Torneo.Periodo WHERE idPeriodo IN (203, 204);
GO

/* =============================================================================
   FIXTURE con los SP de 10a, 10b y 11b
   Partidos entre QVA (local) y QWA (visitante), en la misma sede y separados
   por 48 horas para respetar la regla de 24 horas del ABM:
     98021  grupos        2025-01-01  Programado, sin eventos
     98022  eliminatoria  2030-01-01  Programado, todavía no empezó
     98023  grupos        2025-01-03  Suspendido
     98024  grupos        2025-01-05  En juego, goles: QVA en jugada y en contra de QWA (2-0)
     98025  eliminatoria  2025-01-07  Programado, sin eventos
     98026  eliminatoria  2025-01-09  En juego, 1-1 y penales 2-1 para QVA
     98027  grupos        2025-01-11  Programado, sin eventos
   ============================================================================= */
EXEC Torneo.Pais_Alta @nombre = N'País Prueba 80d V', @codigoISO2 = 'QV', @codigoISO3 = 'QVA';
EXEC Torneo.Pais_Alta @nombre = N'País Prueba 80d W', @codigoISO2 = 'QW', @codigoISO3 = 'QWA';
EXEC Torneo.Fase_Alta @idFase = 904, @nombre = 'Fase Prueba 80d Grupos', @esEliminatoria = 0, @orden = 1;
EXEC Torneo.Fase_Alta @idFase = 905, @nombre = 'Fase Prueba 80d Eliminatoria', @esEliminatoria = 1, @orden = 2;
EXEC Torneo.Periodo_Alta @idPeriodo = 203, @nombre = 'Periodo Prueba 80d Juego', @orden = 203;
EXEC Torneo.Periodo_Alta @idPeriodo = 204, @nombre = 'Periodo Prueba 80d Penales', @orden = 204;
GO

DECLARE @idPaisV int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'QV');
DECLARE @idPaisW int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'QW');
DECLARE @selV int, @selW int, @sede int, @l1 int, @l2 int, @v1 int, @p int;

EXEC Equipos.Seleccion_Alta @idPais = @idPaisV, @confederacion = 'UEFA', @abreviacion = 'QVA', @id = @selV OUTPUT;
EXEC Equipos.Seleccion_Alta @idPais = @idPaisW, @confederacion = 'UEFA', @abreviacion = 'QWA', @id = @selW OUTPUT;
EXEC Torneo.Sede_Alta @nombreEstadio = N'Estadio Prueba 80d', @ciudad = N'Ciudad Prueba', @idPais = @idPaisV,
     @husoHorario = 'UTC', @capacidad = 30000;
SET @sede = (SELECT idSede FROM Torneo.Sede WHERE nombreEstadio = N'Estadio Prueba 80d');
EXEC Equipos.Jugador_Alta @nombre = N'L1', @apellido = N'Prueba80d', @id = @l1 OUTPUT;
EXEC Equipos.Jugador_Alta @nombre = N'L2', @apellido = N'Prueba80d', @id = @l2 OUTPUT;
EXEC Equipos.Jugador_Alta @nombre = N'V1', @apellido = N'Prueba80d', @id = @v1 OUTPUT;

EXEC Torneo.Partido_Alta @idSede = @sede, @idSeleccionLocal = @selV, @idSeleccionVisitante = @selW, @fase = 904,
     @fechaHoraUTC = '2025-01-01 18:00', @nroPartidoOficial = 98021, @esquemaLocal = '4-4-2';
EXEC Torneo.Partido_Alta @idSede = @sede, @idSeleccionLocal = @selV, @idSeleccionVisitante = @selW, @fase = 905,
     @fechaHoraUTC = '2030-01-01 18:00', @nroPartidoOficial = 98022;
EXEC Torneo.Partido_Alta @idSede = @sede, @idSeleccionLocal = @selV, @idSeleccionVisitante = @selW, @fase = 904,
     @fechaHoraUTC = '2025-01-03 18:00', @estado = 'Suspendido', @nroPartidoOficial = 98023;
EXEC Torneo.Partido_Alta @idSede = @sede, @idSeleccionLocal = @selV, @idSeleccionVisitante = @selW, @fase = 905,
     @fechaHoraUTC = '2025-01-07 18:00', @nroPartidoOficial = 98025;
EXEC Torneo.Partido_Alta @idSede = @sede, @idSeleccionLocal = @selV, @idSeleccionVisitante = @selW, @fase = 904,
     @fechaHoraUTC = '2025-01-11 18:00', @nroPartidoOficial = 98027;

-- 98024: formaciones con el partido programado, después En juego y los goles
EXEC Torneo.Partido_Alta @idSede = @sede, @idSeleccionLocal = @selV, @idSeleccionVisitante = @selW, @fase = 904,
     @fechaHoraUTC = '2025-01-05 18:00', @nroPartidoOficial = 98024, @idPartido = @p OUTPUT;
EXEC Eventos.FormacionPartido_Alta @idPartido = @p, @idSeleccion = @selV, @idJugador = @l1, @titular = 1;
EXEC Eventos.FormacionPartido_Alta @idPartido = @p, @idSeleccion = @selW, @idJugador = @v1, @titular = 1;
EXEC Torneo.Partido_Modificacion @idPartido = @p, @idSede = @sede, @idSeleccionLocal = @selV,
     @idSeleccionVisitante = @selW, @fase = 904, @fechaHoraUTC = '2025-01-05 18:00', @estado = 'En juego',
     @nroPartidoOficial = 98024;
EXEC Eventos.Gol_Alta @idPartido = @p, @idJugador = @l1, @minuto = 10, @tipo = 'Jugada', @idPeriodo = 203;
EXEC Eventos.Gol_Alta @idPartido = @p, @idJugador = @v1, @minuto = 50, @tipo = 'En contra', @idPeriodo = 203;

-- 98026: 1-1 en el juego y 2-1 en los penales (minuto NULL) para QVA
EXEC Torneo.Partido_Alta @idSede = @sede, @idSeleccionLocal = @selV, @idSeleccionVisitante = @selW, @fase = 905,
     @fechaHoraUTC = '2025-01-09 18:00', @nroPartidoOficial = 98026, @idPartido = @p OUTPUT;
EXEC Eventos.FormacionPartido_Alta @idPartido = @p, @idSeleccion = @selV, @idJugador = @l1, @titular = 1;
EXEC Eventos.FormacionPartido_Alta @idPartido = @p, @idSeleccion = @selV, @idJugador = @l2, @titular = 1;
EXEC Eventos.FormacionPartido_Alta @idPartido = @p, @idSeleccion = @selW, @idJugador = @v1, @titular = 1;
EXEC Torneo.Partido_Modificacion @idPartido = @p, @idSede = @sede, @idSeleccionLocal = @selV,
     @idSeleccionVisitante = @selW, @fase = 905, @fechaHoraUTC = '2025-01-09 18:00', @estado = 'En juego',
     @nroPartidoOficial = 98026;
EXEC Eventos.Gol_Alta @idPartido = @p, @idJugador = @l1, @minuto = 30, @tipo = 'Jugada', @idPeriodo = 203;
EXEC Eventos.Gol_Alta @idPartido = @p, @idJugador = @v1, @minuto = 80, @tipo = 'Cabeza', @idPeriodo = 203;
EXEC Eventos.Gol_Alta @idPartido = @p, @idJugador = @l1, @tipo = 'Penal', @idPeriodo = 204;
EXEC Eventos.Gol_Alta @idPartido = @p, @idJugador = @l2, @tipo = 'Penal', @idPeriodo = 204;
EXEC Eventos.Gol_Alta @idPartido = @p, @idJugador = @v1, @tipo = 'Penal', @idPeriodo = 204;
GO

/* =============================================================================
   1. Torneo.RegistrarResultado
   ============================================================================= */
PRINT '--- 1. Torneo.RegistrarResultado ---';

DECLARE @p int;

-- PRUEBA 1.1: registro exitoso en un partido sin eventos
-- Resultado esperado: 98021 queda Finalizado 2-1 con 25000 espectadores; el
-- esquema local cargado antes (4-4-2) se conserva y el visitante queda 4-3-3.
BEGIN TRY
    SET @p = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 98021);
    SELECT 'ANTES 1.1' AS momento, * FROM Torneo.Partido WHERE idPartido = @p;
    EXEC Torneo.RegistrarResultado @idPartido = @p, @golLocal = 2, @golVisitante = 1, @cantPublico = 25000,
         @esquemaVisitante = '4-3-3';
    SELECT 'DESPUES 1.1' AS momento, * FROM Torneo.Partido WHERE idPartido = @p;
    IF EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @p AND estado = 'Finalizado' AND golLocal = 2
               AND golVisitante = 1 AND cantPublico = 25000 AND esquemaLocal = '4-4-2' AND esquemaVisitante = '4-3-3')
        PRINT '[OK] PRUEBA 1.1: resultado registrado y partido finalizado.';
    ELSE PRINT '[FALLO] PRUEBA 1.1: el partido no quedó como se esperaba.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.2: partido que ya tiene resultado (el de la prueba 1.1)
-- Resultado esperado: error 50002 "El partido ya tiene un resultado registrado".
BEGIN TRY
    EXEC Torneo.RegistrarResultado @idPartido = @p, @golLocal = 3, @golVisitante = 1;
    PRINT '[FALLO] PRUEBA 1.2: se registró dos veces el resultado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%ya tiene un resultado registrado%'
       AND EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @p AND golLocal = 2)
        PRINT '[OK] PRUEBA 1.2: segundo registro rechazado y resultado original intacto.';
    ELSE PRINT '[FALLO] PRUEBA 1.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.3: datos de entrada (partido inexistente y resultado incompleto)
-- Resultado esperado: error 50001 con las dos líneas en el mismo mensaje.
BEGIN TRY
    EXEC Torneo.RegistrarResultado @idPartido = -1, @golLocal = 1, @golVisitante = NULL;
    PRINT '[FALLO] PRUEBA 1.3: no se detectaron los errores.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'%partido no existe%'
       AND ERROR_MESSAGE() LIKE N'%resultado debe cargarse completo%'
        PRINT '[OK] PRUEBA 1.3: los 2 errores se informaron juntos.';
    ELSE PRINT '[FALLO] PRUEBA 1.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.4: partido que todavía no empezó (98022, en 2030)
-- Resultado esperado: error 50002 "El partido todavía no empezó."; sigue Programado.
BEGIN TRY
    SET @p = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 98022);
    EXEC Torneo.RegistrarResultado @idPartido = @p, @golLocal = 1, @golVisitante = 0;
    PRINT '[FALLO] PRUEBA 1.4: se registró el resultado de un partido futuro.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%todavía no empezó%'
       AND EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @p AND estado = 'Programado')
        PRINT '[OK] PRUEBA 1.4: partido futuro rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 1.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.5: acumulación de reglas de negocio (98022: futuro y eliminatoria empatada sin penales)
-- Resultado esperado: error 50002 con las dos líneas en el mismo mensaje.
BEGIN TRY
    EXEC Torneo.RegistrarResultado @idPartido = @p, @golLocal = 0, @golVisitante = 0;
    PRINT '[FALLO] PRUEBA 1.5: no se detectaron los errores.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002
       AND ERROR_MESSAGE() LIKE N'%todavía no empezó%'
       AND ERROR_MESSAGE() LIKE N'%requiere la definición por penales%'
        PRINT '[OK] PRUEBA 1.5: las 2 reglas se informaron juntas.';
    ELSE PRINT '[FALLO] PRUEBA 1.5: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.6: partido suspendido (98023)
-- Resultado esperado: error 50002 "El partido está suspendido."
BEGIN TRY
    SET @p = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 98023);
    EXEC Torneo.RegistrarResultado @idPartido = @p, @golLocal = 1, @golVisitante = 1;
    PRINT '[FALLO] PRUEBA 1.6: se registró el resultado de un partido suspendido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%partido está suspendido%'
        PRINT '[OK] PRUEBA 1.6: partido suspendido rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 1.6: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.7: resultado que no coincide con los goles registrados (98024 tiene 2-0)
-- Resultado esperado: error 50002 "no coincide con los goles registrados como
-- eventos (2-0)"; el partido sigue En juego y sin resultado (ROLLBACK).
BEGIN TRY
    SET @p = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 98024);
    EXEC Torneo.RegistrarResultado @idPartido = @p, @golLocal = 1, @golVisitante = 1;
    PRINT '[FALLO] PRUEBA 1.7: se aceptó un resultado distinto a los goles registrados.';
END TRY
BEGIN CATCH
    SELECT 'DESPUES 1.7' AS momento, * FROM Torneo.Partido WHERE idPartido = @p;
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%no coincide con los goles registrados como eventos (2-0)%'
       AND EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @p AND estado = 'En juego' AND golLocal IS NULL)
        PRINT '[OK] PRUEBA 1.7: resultado inconsistente rechazado y partido sin cambios.';
    ELSE PRINT '[FALLO] PRUEBA 1.7: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.8: resultado que coincide con los goles, incluido un gol en contra
-- Resultado esperado: 98024 queda Finalizado 2-0 (el gol en contra de QWA suma para QVA).
BEGIN TRY
    SELECT 'ANTES 1.8' AS momento, * FROM Torneo.Partido WHERE idPartido = @p;
    EXEC Torneo.RegistrarResultado @idPartido = @p, @golLocal = 2, @golVisitante = 0;
    SELECT 'DESPUES 1.8' AS momento, * FROM Torneo.Partido WHERE idPartido = @p;
    IF EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @p AND estado = 'Finalizado'
               AND golLocal = 2 AND golVisitante = 0)
        PRINT '[OK] PRUEBA 1.8: resultado consistente con los eventos registrado.';
    ELSE PRINT '[FALLO] PRUEBA 1.8: el partido no quedó como se esperaba.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.8: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.9: eliminatoria empatada sin definición por penales (98025)
-- Resultado esperado: error 50002 "requiere la definición por penales registrada con un ganador."
BEGIN TRY
    SET @p = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 98025);
    EXEC Torneo.RegistrarResultado @idPartido = @p, @golLocal = 1, @golVisitante = 1;
    PRINT '[FALLO] PRUEBA 1.9: se aceptó un empate en eliminación directa sin penales.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%requiere la definición por penales%'
        PRINT '[OK] PRUEBA 1.9: empate de eliminatoria sin penales rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 1.9: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.10: eliminatoria empatada con penales y ganador (98026: 1-1, penales 2-1)
-- Resultado esperado: 98026 queda Finalizado 1-1; los penales no suman al resultado.
BEGIN TRY
    SET @p = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 98026);
    SELECT 'ANTES 1.10' AS momento, * FROM Torneo.Partido WHERE idPartido = @p;
    EXEC Torneo.RegistrarResultado @idPartido = @p, @golLocal = 1, @golVisitante = 1;
    SELECT 'DESPUES 1.10' AS momento, * FROM Torneo.Partido WHERE idPartido = @p;
    IF EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @p AND estado = 'Finalizado'
               AND golLocal = 1 AND golVisitante = 1)
        PRINT '[OK] PRUEBA 1.10: eliminatoria definida por penales registrada.';
    ELSE PRINT '[FALLO] PRUEBA 1.10: el partido no quedó como se esperaba.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.10: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.11: validación del ABM dentro de la transacción (público mayor a la
-- capacidad de 30000 y esquema inválido en 98027)
-- Resultado esperado: error 50001 de Torneo.Partido_Modificacion con las dos
-- líneas; el partido sigue Programado y sin resultado (ROLLBACK).
BEGIN TRY
    SET @p = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 98027);
    EXEC Torneo.RegistrarResultado @idPartido = @p, @golLocal = 1, @golVisitante = 0, @cantPublico = 99999,
         @esquemaLocal = '5-5-5';
    PRINT '[FALLO] PRUEBA 1.11: se aceptó un público mayor a la capacidad.';
END TRY
BEGIN CATCH
    SELECT 'DESPUES 1.11' AS momento, * FROM Torneo.Partido WHERE idPartido = @p;
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'%supera la capacidad de la sede%'
       AND ERROR_MESSAGE() LIKE N'%esquema local debe tener%'
       AND EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @p AND estado = 'Programado' AND golLocal IS NULL)
        PRINT '[OK] PRUEBA 1.11: error del ABM propagado y partido sin cambios.';
    ELSE PRINT '[FALLO] PRUEBA 1.11: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.12: la transacción no queda abierta después de un error
-- Resultado esperado: @@TRANCOUNT = 0.
IF @@TRANCOUNT = 0
    PRINT '[OK] PRUEBA 1.12: no quedaron transacciones abiertas.';
ELSE PRINT '[FALLO] PRUEBA 1.12: quedaron ' + CAST(@@TRANCOUNT AS varchar(10)) + ' transacciones abiertas.';
GO

/* =============================================================================
   LIMPIEZA FINAL
   ============================================================================= */
DELETE FROM Eventos.Gol WHERE idPartido IN
    (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 98021 AND 98027);
DELETE FROM Eventos.FormacionPartido WHERE idPartido IN
    (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 98021 AND 98027);
DELETE FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 98021 AND 98027;
DELETE FROM Equipos.Jugador WHERE apellido = N'Prueba80d';
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('QVA', 'QWA');
DELETE FROM Torneo.Sede WHERE nombreEstadio = N'Estadio Prueba 80d';
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('QV', 'QW');
DELETE FROM Torneo.Fase WHERE idFase IN (904, 905);
DELETE FROM Torneo.Periodo WHERE idPeriodo IN (203, 204);

PRINT '================================================================================';
PRINT ' FIN DE LAS PRUEBAS: 20a_Negocio_Torneo.sql (12 pruebas)';
PRINT '================================================================================';
GO
