/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 09/11/2026

 Objetivo    : Pruebas de los SP de 20b_Negocio_Equipos.sql
               (Equipos.RegistrarConvocatoria y Equipos.ReemplazarConvocado):
               casos exitosos con evidencia antes/después, casos que deben
               fallar en cada validación y comprobación del ROLLBACK cuando
               falla una de las altas o bajas de la operación.

 Requisitos  : 00_InitialSchema.sql, 10a, 10b, 20b y las claves MIN_CONVOCADOS,
               MAX_CONVOCADOS y HORAS_LIMITE_REEMPLAZO de 50d. Las pruebas leen
               los valores de Sistema.Parametro, no los suponen.

 Datos de prueba:
 - Países con códigos ISO de uso privado (QX, QY, QZ / QXA, QYA, QZA), que la
   norma ISO 3166 nunca asigna a un país real.
 - Fase 906, partido oficial 98031 y jugadores con apellido Prueba80e (un
   grupo de 2 x MAX_CONVOCADOS + 5 jugadores; el primero es arquero).
 - Se limpian al inicio y al final: el script se puede ejecutar varias veces.

 Cada prueba imprime [OK] o [FALLO]. Resultado esperado: todas [OK].
================================================================================
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

PRINT '================================================================================';
PRINT ' PRUEBAS: 20b_Negocio_Equipos.sql';
PRINT '================================================================================';
GO

/* =============================================================================
   LIMPIEZA PREVIA (DELETE directo en orden inverso de claves foráneas, por si
   una corrida anterior se cortó y dejó datos con dependencias)
   ============================================================================= */
DELETE FROM Equipos.ListadoJugadores WHERE idReemplazaA IS NOT NULL
    AND idJugador IN (SELECT id FROM Equipos.Jugador WHERE apellido = N'Prueba80e');
DELETE FROM Equipos.ListadoJugadores WHERE idJugador IN (SELECT id FROM Equipos.Jugador WHERE apellido = N'Prueba80e');
DELETE FROM Equipos.Jugador WHERE apellido = N'Prueba80e';
DELETE FROM Torneo.Partido WHERE nroPartidoOficial = 98031;
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('QXA', 'QYA', 'QZA');
DELETE FROM Torneo.Sede WHERE nombreEstadio = N'Estadio Prueba 80e';
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('QX', 'QY', 'QZ');
DELETE FROM Torneo.Fase WHERE idFase = 906;
GO

/* =============================================================================
   FIXTURE con los SP de 10a y 10b
   - QXA juega su primer partido (98031) el 2030-06-10 a las 18:00 UTC contra QZA.
   - QYA no tiene partidos.
   - #grupo guarda los jugadores de prueba numerados del 1 en adelante.
   ============================================================================= */
IF NOT EXISTS (SELECT 1 FROM Sistema.Parametro WHERE clave = 'MIN_CONVOCADOS')
   OR NOT EXISTS (SELECT 1 FROM Sistema.Parametro WHERE clave = 'MAX_CONVOCADOS')
   OR NOT EXISTS (SELECT 1 FROM Sistema.Parametro WHERE clave = 'HORAS_LIMITE_REEMPLAZO')
    PRINT '[FALLO] REQUISITO: faltan las claves de 50d_Carga_Parametros.sql en Sistema.Parametro.';

EXEC Torneo.Pais_Alta @nombre = N'País Prueba 80e X', @codigoISO2 = 'QX', @codigoISO3 = 'QXA';
EXEC Torneo.Pais_Alta @nombre = N'País Prueba 80e Y', @codigoISO2 = 'QY', @codigoISO3 = 'QYA';
EXEC Torneo.Pais_Alta @nombre = N'País Prueba 80e Z', @codigoISO2 = 'QZ', @codigoISO3 = 'QZA';
EXEC Torneo.Fase_Alta @idFase = 906, @nombre = 'Fase Prueba 80e', @esEliminatoria = 0, @orden = 1;
GO

DECLARE @selX int, @selZ int, @sede int;
DECLARE @idPaisX int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'QX');
DECLARE @idPaisY int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'QY');
DECLARE @idPaisZ int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'QZ');
EXEC Equipos.Seleccion_Alta @idPais = @idPaisX, @confederacion = 'UEFA', @abreviacion = 'QXA', @id = @selX OUTPUT;
EXEC Equipos.Seleccion_Alta @idPais = @idPaisY, @confederacion = 'UEFA', @abreviacion = 'QYA';
EXEC Equipos.Seleccion_Alta @idPais = @idPaisZ, @confederacion = 'UEFA', @abreviacion = 'QZA', @id = @selZ OUTPUT;
EXEC Torneo.Sede_Alta @nombreEstadio = N'Estadio Prueba 80e', @ciudad = N'Ciudad Prueba', @idPais = @idPaisX,
     @husoHorario = 'UTC', @capacidad = 30000;
SET @sede = (SELECT idSede FROM Torneo.Sede WHERE nombreEstadio = N'Estadio Prueba 80e');
EXEC Torneo.Partido_Alta @idSede = @sede, @idSeleccionLocal = @selX, @idSeleccionVisitante = @selZ, @fase = 906,
     @fechaHoraUTC = '2030-06-10 18:00', @nroPartidoOficial = 98031;

DROP TABLE IF EXISTS #grupo;
CREATE TABLE #grupo (n int PRIMARY KEY, id int);
DECLARE @total int = 2 * (SELECT valor FROM Sistema.Parametro WHERE clave = 'MAX_CONVOCADOS') + 5;
DECLARE @n int = 1, @id int, @nombre nvarchar(60), @posicion varchar(15);
WHILE @n <= @total
BEGIN
    SET @nombre = N'J' + RIGHT('0' + CAST(@n AS nvarchar(3)), 2);
    SET @posicion = CASE WHEN @n = 1 THEN 'Arquero' ELSE 'Defensor' END;
    EXEC Equipos.Jugador_Alta @nombre = @nombre, @apellido = N'Prueba80e', @posicion = @posicion, @id = @id OUTPUT;
    INSERT INTO #grupo (n, id) VALUES (@n, @id);
    SET @n += 1;
END;
GO

/* =============================================================================
   1. Equipos.RegistrarConvocatoria
   Jugadores de #grupo: 1 a MAX van a QXA; desde MAX + 1 quedan libres.
   ============================================================================= */
PRINT '--- 1. Equipos.RegistrarConvocatoria ---';

DECLARE @min int = (SELECT valor FROM Sistema.Parametro WHERE clave = 'MIN_CONVOCADOS');
DECLARE @max int = (SELECT valor FROM Sistema.Parametro WHERE clave = 'MAX_CONVOCADOS');
DECLARE @selX int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'QXA');
DECLARE @selY int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'QYA');
DECLARE @lista nvarchar(max), @j1 int, @j2 int;

-- PRUEBA 1.1: convocatoria exitosa con el mínimo exacto (jugadores 1 a MIN, dorsal = número)
-- Resultado esperado: QXA queda con MIN convocados activos, todos con fecha de alta 2030-05-20.
BEGIN TRY
    SET @lista = (SELECT '[' + STRING_AGG(CONCAT('{"idJugador":', id, ',"dorsal":', n, '}'), ',') + ']'
                  FROM #grupo WHERE n BETWEEN 1 AND @min);
    SELECT 'ANTES 1.1' AS momento, COUNT(*) AS activos FROM Equipos.ListadoJugadores
    WHERE idSeleccion = @selX AND fechaBaja IS NULL;
    EXEC Equipos.RegistrarConvocatoria @idSeleccion = @selX, @fechaAlta = '2030-05-20', @convocados = @lista;
    SELECT 'DESPUES 1.1' AS momento, COUNT(*) AS activos FROM Equipos.ListadoJugadores
    WHERE idSeleccion = @selX AND fechaBaja IS NULL AND fechaAlta = '2030-05-20';
    IF (SELECT COUNT(*) FROM Equipos.ListadoJugadores
        WHERE idSeleccion = @selX AND fechaBaja IS NULL AND fechaAlta = '2030-05-20') = @min
        PRINT '[OK] PRUEBA 1.1: convocatoria registrada con el mínimo de jugadores.';
    ELSE PRINT '[FALLO] PRUEBA 1.1: la cantidad de convocados no es la esperada.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.2: datos de entrada (selección inexistente, sin fecha y texto que no es JSON)
-- Resultado esperado: error 50001 con las tres líneas en el mismo mensaje.
BEGIN TRY
    EXEC Equipos.RegistrarConvocatoria @idSeleccion = -1, @fechaAlta = NULL, @convocados = N'no es json';
    PRINT '[FALLO] PRUEBA 1.2: no se detectaron los errores.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'%selección no existe%'
       AND ERROR_MESSAGE() LIKE N'%fecha de alta es obligatoria%'
       AND ERROR_MESSAGE() LIKE N'%debe ser un arreglo JSON%'
        PRINT '[OK] PRUEBA 1.2: los 3 errores se informaron juntos.';
    ELSE PRINT '[FALLO] PRUEBA 1.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.3: lista con un jugador repetido, un dorsal repetido y un convocado sin dorsal
-- Resultado esperado: error 50001 con las tres líneas en el mismo mensaje.
BEGIN TRY
    SET @j1 = (SELECT id FROM #grupo WHERE n = @max + 1);
    SET @j2 = (SELECT id FROM #grupo WHERE n = @max + 2);
    SET @lista = CONCAT('[{"idJugador":', @j1, ',"dorsal":1},{"idJugador":', @j1, ',"dorsal":1},{"idJugador":', @j2, '}]');
    EXEC Equipos.RegistrarConvocatoria @idSeleccion = @selY, @fechaAlta = '2030-05-20', @convocados = @lista;
    PRINT '[FALLO] PRUEBA 1.3: no se detectaron los errores.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'%jugador figura más de una vez%'
       AND ERROR_MESSAGE() LIKE N'%dorsal figura más de una vez%'
       AND ERROR_MESSAGE() LIKE N'%debe tener idJugador y dorsal numéricos%'
        PRINT '[OK] PRUEBA 1.3: los 3 errores de la lista se informaron juntos.';
    ELSE PRINT '[FALLO] PRUEBA 1.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.4: lista vacía
-- Resultado esperado: error 50001 "La lista de convocados está vacía."
BEGIN TRY
    EXEC Equipos.RegistrarConvocatoria @idSeleccion = @selY, @fechaAlta = '2030-05-20', @convocados = N'[]';
    PRINT '[FALLO] PRUEBA 1.4: se aceptó una lista vacía.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%lista de convocados está vacía%'
        PRINT '[OK] PRUEBA 1.4: lista vacía rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 1.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.5: convocatoria por debajo del mínimo (MIN - 1 jugadores libres para QYA)
-- Resultado esperado: error 50002 "...el mínimo es MIN."; QYA sigue sin convocados.
BEGIN TRY
    SET @lista = (SELECT '[' + STRING_AGG(CONCAT('{"idJugador":', id, ',"dorsal":', n - @max, '}'), ',') + ']'
                  FROM #grupo WHERE n BETWEEN @max + 1 AND @max + @min - 1);
    EXEC Equipos.RegistrarConvocatoria @idSeleccion = @selY, @fechaAlta = '2030-05-20', @convocados = @lista;
    PRINT '[FALLO] PRUEBA 1.5: se aceptó una convocatoria con menos del mínimo.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%el mínimo es ' + CAST(@min AS nvarchar(10)) + N'%'
       AND NOT EXISTS (SELECT 1 FROM Equipos.ListadoJugadores WHERE idSeleccion = @selY)
        PRINT '[OK] PRUEBA 1.5: convocatoria por debajo del mínimo rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 1.5: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.6: convocatoria que supera el máximo (QXA tiene MIN y se suman MAX - MIN + 1)
-- Resultado esperado: error 50002 "...el máximo es MAX."; QXA sigue con MIN convocados.
BEGIN TRY
    SET @lista = (SELECT '[' + STRING_AGG(CONCAT('{"idJugador":', id, ',"dorsal":', n, '}'), ',') + ']'
                  FROM #grupo WHERE n BETWEEN @max + 1 AND 2 * @max - @min + 1);
    EXEC Equipos.RegistrarConvocatoria @idSeleccion = @selX, @fechaAlta = '2030-05-20', @convocados = @lista;
    PRINT '[FALLO] PRUEBA 1.6: se aceptó una convocatoria con más del máximo.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%el máximo es ' + CAST(@max AS nvarchar(10)) + N'%'
       AND (SELECT COUNT(*) FROM Equipos.ListadoJugadores WHERE idSeleccion = @selX AND fechaBaja IS NULL) = @min
        PRINT '[OK] PRUEBA 1.6: convocatoria por encima del máximo rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 1.6: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.7: falla el alta del último convocado de la lista (ROLLBACK)
-- La lista de QYA tiene MIN - 1 jugadores libres y, al final, el jugador 1,
-- que ya está convocado en QXA.
-- Resultado esperado: error 50001 "Convocado MIN de la lista ... ya está
-- convocado activo"; QYA sigue sin convocados (se deshicieron las altas previas).
BEGIN TRY
    SET @lista = (SELECT '[' + STRING_AGG(CONCAT('{"idJugador":', id, ',"dorsal":', n - @max, '}'), ',')
                  WITHIN GROUP (ORDER BY n) + ','
                  FROM #grupo WHERE n BETWEEN @max + 1 AND @max + @min - 1)
               + CONCAT('{"idJugador":', (SELECT id FROM #grupo WHERE n = 1), ',"dorsal":', @min, '}]');
    EXEC Equipos.RegistrarConvocatoria @idSeleccion = @selY, @fechaAlta = '2030-05-20', @convocados = @lista;
    PRINT '[FALLO] PRUEBA 1.7: se aceptó un jugador convocado en otra selección.';
END TRY
BEGIN CATCH
    SELECT 'DESPUES 1.7' AS momento, COUNT(*) AS convocadosQYA FROM Equipos.ListadoJugadores WHERE idSeleccion = @selY;
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'Convocado ' + CAST(@min AS nvarchar(10)) + N' de la lista%'
       AND ERROR_MESSAGE() LIKE N'%ya está convocado activo%'
       AND NOT EXISTS (SELECT 1 FROM Equipos.ListadoJugadores WHERE idSeleccion = @selY)
        PRINT '[OK] PRUEBA 1.7: alta fallida informada y altas anteriores deshechas.';
    ELSE PRINT '[FALLO] PRUEBA 1.7: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.8: completar una convocatoria existente hasta el máximo (jugadores MIN + 1 a MAX)
-- Resultado esperado: QXA queda con MAX convocados activos.
BEGIN TRY
    SET @lista = (SELECT '[' + STRING_AGG(CONCAT('{"idJugador":', id, ',"dorsal":', n, '}'), ',') + ']'
                  FROM #grupo WHERE n BETWEEN @min + 1 AND @max);
    SELECT 'ANTES 1.8' AS momento, COUNT(*) AS activos FROM Equipos.ListadoJugadores
    WHERE idSeleccion = @selX AND fechaBaja IS NULL;
    EXEC Equipos.RegistrarConvocatoria @idSeleccion = @selX, @fechaAlta = '2030-05-20', @convocados = @lista;
    SELECT 'DESPUES 1.8' AS momento, COUNT(*) AS activos FROM Equipos.ListadoJugadores
    WHERE idSeleccion = @selX AND fechaBaja IS NULL;
    IF (SELECT COUNT(*) FROM Equipos.ListadoJugadores WHERE idSeleccion = @selX AND fechaBaja IS NULL) = @max
        PRINT '[OK] PRUEBA 1.8: convocatoria completada hasta el máximo.';
    ELSE PRINT '[FALLO] PRUEBA 1.8: la cantidad de convocados no es la esperada.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.8: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   2. Equipos.ReemplazarConvocado
   QXA tiene MAX convocados y su primer partido es el 2030-06-10 18:00 UTC.
   Reemplazantes libres: jugadores 2 x MAX + 1 en adelante.
   ============================================================================= */
PRINT '--- 2. Equipos.ReemplazarConvocado ---';

DECLARE @max int = (SELECT valor FROM Sistema.Parametro WHERE clave = 'MAX_CONVOCADOS');
DECLARE @selX int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'QXA');
DECLARE @conv int, @nuevo int, @jug int;

-- PRUEBA 2.1: reemplazo exitoso de un jugador de campo con tiempo (2030-06-01)
-- Resultado esperado: el convocado del jugador 2 queda con baja 2030-06-01 y
-- motivo; el reemplazante entra con el mismo dorsal (2) e idReemplazaA; QXA
-- sigue con MAX convocados activos.
BEGIN TRY
    SET @conv = (SELECT lj.id FROM Equipos.ListadoJugadores lj JOIN #grupo g ON g.id = lj.idJugador
                 WHERE g.n = 2 AND lj.fechaBaja IS NULL);
    SET @jug = (SELECT id FROM #grupo WHERE n = 2 * @max + 1);
    SELECT 'ANTES 2.1' AS momento, * FROM Equipos.ListadoJugadores WHERE id = @conv;
    EXEC Equipos.ReemplazarConvocado @idConvocado = @conv, @idJugadorReemplazo = @jug, @fechaCambio = '2030-06-01',
         @motivoBaja = 'Lesión en el entrenamiento', @idNuevo = @nuevo OUTPUT;
    SELECT 'DESPUES 2.1' AS momento, * FROM Equipos.ListadoJugadores WHERE id IN (@conv, @nuevo);
    IF EXISTS (SELECT 1 FROM Equipos.ListadoJugadores WHERE id = @conv AND fechaBaja = '2030-06-01'
               AND motivoBaja = 'Lesión en el entrenamiento')
       AND EXISTS (SELECT 1 FROM Equipos.ListadoJugadores WHERE id = @nuevo AND idJugador = @jug AND dorsal = 2
                   AND idReemplazaA = @conv AND fechaAlta = '2030-06-01' AND fechaBaja IS NULL)
       AND (SELECT COUNT(*) FROM Equipos.ListadoJugadores WHERE idSeleccion = @selX AND fechaBaja IS NULL) = @max
        PRINT '[OK] PRUEBA 2.1: baja y alta del reemplazo registradas juntas.';
    ELSE PRINT '[FALLO] PRUEBA 2.1: el reemplazo no quedó como se esperaba.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.2: convocado ya dado de baja (el reemplazado de la prueba 2.1)
-- Resultado esperado: error 50001 "El convocado a reemplazar ya fue dado de baja."
BEGIN TRY
    SET @jug = (SELECT id FROM #grupo WHERE n = 2 * @max + 2);
    EXEC Equipos.ReemplazarConvocado @idConvocado = @conv, @idJugadorReemplazo = @jug, @fechaCambio = '2030-06-01',
         @motivoBaja = 'Lesión';
    PRINT '[FALLO] PRUEBA 2.2: se reemplazó a un convocado ya dado de baja.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%ya fue dado de baja%'
        PRINT '[OK] PRUEBA 2.2: convocado dado de baja rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.3: datos de entrada (convocado y reemplazante inexistentes, sin fecha)
-- Resultado esperado: error 50001 con las tres líneas en el mismo mensaje.
BEGIN TRY
    EXEC Equipos.ReemplazarConvocado @idConvocado = -1, @idJugadorReemplazo = -1, @fechaCambio = NULL,
         @motivoBaja = 'Lesión';
    PRINT '[FALLO] PRUEBA 2.3: no se detectaron los errores.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'%convocado a reemplazar no existe%'
       AND ERROR_MESSAGE() LIKE N'%jugador reemplazante no existe%'
       AND ERROR_MESSAGE() LIKE N'%fecha del cambio es obligatoria%'
        PRINT '[OK] PRUEBA 2.3: los 3 errores se informaron juntos.';
    ELSE PRINT '[FALLO] PRUEBA 2.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.4: el reemplazante es el mismo jugador que se da de baja (jugador 3)
-- Resultado esperado: error 50001 "El reemplazante no puede ser el mismo jugador..."
BEGIN TRY
    SET @jug = (SELECT id FROM #grupo WHERE n = 3);
    SET @conv = (SELECT id FROM Equipos.ListadoJugadores WHERE idJugador = @jug AND fechaBaja IS NULL);
    EXEC Equipos.ReemplazarConvocado @idConvocado = @conv, @idJugadorReemplazo = @jug, @fechaCambio = '2030-06-01',
         @motivoBaja = 'Lesión';
    PRINT '[FALLO] PRUEBA 2.4: se reemplazó a un jugador por sí mismo.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%no puede ser el mismo jugador%'
        PRINT '[OK] PRUEBA 2.4: reemplazo por el mismo jugador rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.5: jugador de campo reemplazado fuera de término (jugador 3, el
-- 2030-06-10, a menos de HORAS_LIMITE_REEMPLAZO horas del primer partido)
-- Resultado esperado: error 50002 "Fuera de término..."; el jugador 3 sigue convocado.
BEGIN TRY
    SET @jug = (SELECT id FROM #grupo WHERE n = 2 * @max + 2);
    EXEC Equipos.ReemplazarConvocado @idConvocado = @conv, @idJugadorReemplazo = @jug, @fechaCambio = '2030-06-10',
         @motivoBaja = 'Lesión';
    PRINT '[FALLO] PRUEBA 2.5: se aceptó un reemplazo fuera de término.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%Fuera de término%'
       AND EXISTS (SELECT 1 FROM Equipos.ListadoJugadores WHERE id = @conv AND fechaBaja IS NULL)
       AND NOT EXISTS (SELECT 1 FROM Equipos.ListadoJugadores WHERE idJugador = @jug)
        PRINT '[OK] PRUEBA 2.5: reemplazo fuera de término rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.5: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.6: al arquero se lo puede reemplazar fuera de término (jugador 1, el 2030-06-10)
-- Resultado esperado: el reemplazo se registra con el dorsal 1.
BEGIN TRY
    SET @conv = (SELECT lj.id FROM Equipos.ListadoJugadores lj JOIN #grupo g ON g.id = lj.idJugador
                 WHERE g.n = 1 AND lj.fechaBaja IS NULL);
    SELECT 'ANTES 2.6' AS momento, * FROM Equipos.ListadoJugadores WHERE id = @conv;
    EXEC Equipos.ReemplazarConvocado @idConvocado = @conv, @idJugadorReemplazo = @jug, @fechaCambio = '2030-06-10',
         @motivoBaja = 'Lesión del arquero', @idNuevo = @nuevo OUTPUT;
    SELECT 'DESPUES 2.6' AS momento, * FROM Equipos.ListadoJugadores WHERE id IN (@conv, @nuevo);
    IF EXISTS (SELECT 1 FROM Equipos.ListadoJugadores WHERE id = @nuevo AND idJugador = @jug
               AND dorsal = 1 AND idReemplazaA = @conv)
        PRINT '[OK] PRUEBA 2.6: arquero reemplazado fuera de término.';
    ELSE PRINT '[FALLO] PRUEBA 2.6: el reemplazo no quedó como se esperaba.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.6: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.7: falla el alta del reemplazante después de la baja (ROLLBACK)
-- El jugador 4 se reemplaza por el jugador 5, que ya está convocado en QXA.
-- Resultado esperado: error 50001 "ya está convocado activo"; la baja del
-- jugador 4 se deshace y sigue convocado.
BEGIN TRY
    SET @conv = (SELECT lj.id FROM Equipos.ListadoJugadores lj JOIN #grupo g ON g.id = lj.idJugador
                 WHERE g.n = 4 AND lj.fechaBaja IS NULL);
    SET @jug = (SELECT id FROM #grupo WHERE n = 5);
    EXEC Equipos.ReemplazarConvocado @idConvocado = @conv, @idJugadorReemplazo = @jug, @fechaCambio = '2030-06-01',
         @motivoBaja = 'Lesión';
    PRINT '[FALLO] PRUEBA 2.7: se aceptó un reemplazante ya convocado.';
END TRY
BEGIN CATCH
    SELECT 'DESPUES 2.7' AS momento, * FROM Equipos.ListadoJugadores WHERE id = @conv;
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%ya está convocado activo%'
       AND EXISTS (SELECT 1 FROM Equipos.ListadoJugadores WHERE id = @conv AND fechaBaja IS NULL AND motivoBaja IS NULL)
        PRINT '[OK] PRUEBA 2.7: alta fallida y baja deshecha.';
    ELSE PRINT '[FALLO] PRUEBA 2.7: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.8: reemplazo con un dorsal nuevo (jugador 4 por un libre, dorsal 99)
-- Resultado esperado: el reemplazante entra con el dorsal 99.
BEGIN TRY
    SET @jug = (SELECT id FROM #grupo WHERE n = 2 * @max + 3);
    EXEC Equipos.ReemplazarConvocado @idConvocado = @conv, @idJugadorReemplazo = @jug, @fechaCambio = '2030-06-01',
         @motivoBaja = 'Lesión', @dorsal = 99, @idNuevo = @nuevo OUTPUT;
    SELECT 'DESPUES 2.8' AS momento, * FROM Equipos.ListadoJugadores WHERE id IN (@conv, @nuevo);
    IF EXISTS (SELECT 1 FROM Equipos.ListadoJugadores WHERE id = @nuevo AND idJugador = @jug AND dorsal = 99)
        PRINT '[OK] PRUEBA 2.8: reemplazo registrado con un dorsal nuevo.';
    ELSE PRINT '[FALLO] PRUEBA 2.8: el reemplazo no quedó como se esperaba.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.8: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.9: la transacción no queda abierta después de los errores
-- Resultado esperado: @@TRANCOUNT = 0.
IF @@TRANCOUNT = 0
    PRINT '[OK] PRUEBA 2.9: no quedaron transacciones abiertas.';
ELSE PRINT '[FALLO] PRUEBA 2.9: quedaron ' + CAST(@@TRANCOUNT AS varchar(10)) + ' transacciones abiertas.';
GO

/* =============================================================================
   LIMPIEZA FINAL
   ============================================================================= */
DELETE FROM Equipos.ListadoJugadores WHERE idReemplazaA IS NOT NULL
    AND idJugador IN (SELECT id FROM Equipos.Jugador WHERE apellido = N'Prueba80e');
DELETE FROM Equipos.ListadoJugadores WHERE idJugador IN (SELECT id FROM Equipos.Jugador WHERE apellido = N'Prueba80e');
DELETE FROM Equipos.Jugador WHERE apellido = N'Prueba80e';
DELETE FROM Torneo.Partido WHERE nroPartidoOficial = 98031;
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('QXA', 'QYA', 'QZA');
DELETE FROM Torneo.Sede WHERE nombreEstadio = N'Estadio Prueba 80e';
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('QX', 'QY', 'QZ');
DELETE FROM Torneo.Fase WHERE idFase = 906;
DROP TABLE IF EXISTS #grupo;

PRINT '================================================================================';
PRINT ' FIN DE LAS PRUEBAS: 20b_Negocio_Equipos.sql (17 pruebas)';
PRINT '================================================================================';
GO
