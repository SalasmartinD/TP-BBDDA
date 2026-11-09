/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel - 45066788
               Salas, Martin Daniel - 45205702
               Zito Padró, Ezequiel Nehuén - 46097917
 Fecha       : 08/11/2026

 Objetivo    : Suite de pruebas unitarias para 11b_ABM_EventosPartido.sql.
               Cubre el Alta, la Modificación y la Baja de las 5 tablas del
               esquema Eventos:
               - Eventos.FormacionPartido
               - Eventos.Gol
               - Eventos.Tarjeta
               - Eventos.Sustitucion
               - Eventos.Suspension

 Estándares aplicados:
 - Relación 1:1 con 11b_ABM_EventosPartido.sql.
 - Alta: un caso exitoso con evidencia (SELECT) y una prueba negativa por cada
   mensaje de validación, verificando el código 50001 y el texto del error.
 - Modificación y Baja: registro inexistente, un caso exitoso con SELECT
   antes/después y solo las reglas propias de cada operación.
 - Una prueba de acumulación de errores (2 o 3 fallos) por tabla.
 - Valores límite del minuto probados una sola vez (Eventos.Gol).
 - Idempotencia: limpieza preventiva al inicio y final en orden inverso de FK;
   los períodos que crea el fixture se registran y se borran al terminar.
================================================================================
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

PRINT '================================================================================';
PRINT ' INICIANDO BATERÍA DE PRUEBAS: 11b_ABM_EventosPartido.sql';
PRINT '================================================================================';
GO

/* =============================================================================
   PREPARACIÓN DEL ENTORNO DE PRUEBAS (FIXTURE AISLADO E IDEMPOTENTE)
   ============================================================================= */
PRINT '--- Limpieza preventiva de pruebas anteriores ---';

DELETE FROM Eventos.Gol WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99801, 99802, 99803, 99804));
DELETE FROM Eventos.Tarjeta WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99801, 99802, 99803, 99804));
DELETE FROM Eventos.Sustitucion WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99801, 99802, 99803, 99804));
DELETE FROM Eventos.Suspension WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99801, 99802, 99803, 99804));
DELETE FROM Eventos.FormacionPartido WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99801, 99802, 99803, 99804));
DELETE FROM Torneo.Partido WHERE nroPartidoOficial IN (99801, 99802, 99803, 99804);
DELETE FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test Eventos';
DELETE FROM Torneo.Fase WHERE idFase = 998;
DELETE FROM Equipos.Staff WHERE apellido IN (N'Staff Test Local', N'Staff Test Ajeno');
DELETE FROM Equipos.Jugador WHERE apellido IN (N'Jugador Local A', N'Jugador Local B', N'Jugador Local C', N'Jugador Visitante X', N'Jugador Visitante Y');
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('EVL', 'EVV', 'EVX');
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('L1', 'V1', 'X1');
GO

PRINT '--- Creando datos auxiliares de prueba ---';

-- Países y selecciones: local (EVL), visitante (EVV) y una ajena a todos los partidos (EVX)
INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3) VALUES ('Pais Eventos Local', 'L1', 'EVL');
INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3) VALUES ('Pais Eventos Visitante', 'V1', 'EVV');
INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3) VALUES ('Pais Eventos Extra', 'X1', 'EVX');

DECLARE @idPaisL int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'L1');
DECLARE @idPaisV int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'V1');
DECLARE @idPaisX int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'X1');

INSERT INTO Equipos.Seleccion (idPais, abreviacion, confederacion) VALUES (@idPaisL, 'EVL', 'CONMEBOL');
INSERT INTO Equipos.Seleccion (idPais, abreviacion, confederacion) VALUES (@idPaisV, 'EVV', 'UEFA');
INSERT INTO Equipos.Seleccion (idPais, abreviacion, confederacion) VALUES (@idPaisX, 'EVX', 'AFC');

DECLARE @idSelL int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'EVL');
DECLARE @idSelV int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'EVV');
DECLARE @idSelX int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'EVX');

-- Jugadores (A, B, C locales; X, Y visitantes) y staff (local y de la selección ajena)
INSERT INTO Equipos.Jugador (nombre, apellido, posicion) VALUES (N'Lionel', N'Jugador Local A', 'Delantero');
INSERT INTO Equipos.Jugador (nombre, apellido, posicion) VALUES (N'Rodrigo', N'Jugador Local B', 'Mediocampista');
INSERT INTO Equipos.Jugador (nombre, apellido, posicion) VALUES (N'Emiliano', N'Jugador Local C', 'Arquero');
INSERT INTO Equipos.Jugador (nombre, apellido, posicion) VALUES (N'Kylian', N'Jugador Visitante X', 'Delantero');
INSERT INTO Equipos.Jugador (nombre, apellido, posicion) VALUES (N'Antoine', N'Jugador Visitante Y', 'Delantero');

INSERT INTO Equipos.Staff (idSeleccion, nombre, apellido, rol) VALUES (@idSelL, N'Lionel', N'Staff Test Local', 'Director Principal');
INSERT INTO Equipos.Staff (idSeleccion, nombre, apellido, rol) VALUES (@idSelX, N'Ajeno', N'Staff Test Ajeno', 'Ayudante');

-- Fase y sede
INSERT INTO Torneo.Fase (idFase, nombre, esEliminatoria, orden) VALUES (998, 'Fase Test Eventos', 0, 98);
INSERT INTO Torneo.Sede (nombreEstadio, ciudad, idPais, husoHorario) VALUES ('Estadio Test Eventos', 'Ciudad Eventos', @idPaisX, 'UTC');
DECLARE @idSede int = (SELECT idSede FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test Eventos');

-- Períodos 1 y 2: se crean solo si faltan y se registran en #periodosCreados
-- (las tablas #temp sobreviven entre lotes de la misma conexión) para borrar
-- en la limpieza final únicamente los que creó este script.
IF OBJECT_ID('tempdb..#periodosCreados') IS NOT NULL DROP TABLE #periodosCreados;
CREATE TABLE #periodosCreados (idPeriodo tinyint PRIMARY KEY);

IF NOT EXISTS (SELECT 1 FROM Torneo.Periodo WHERE idPeriodo = 1)
BEGIN
    INSERT INTO Torneo.Periodo (idPeriodo, nombre, orden) VALUES (1, 'Primer Tiempo', 1);
    INSERT INTO #periodosCreados (idPeriodo) VALUES (1);
END;
IF NOT EXISTS (SELECT 1 FROM Torneo.Periodo WHERE idPeriodo = 2)
BEGIN
    INSERT INTO Torneo.Periodo (idPeriodo, nombre, orden) VALUES (2, 'Segundo Tiempo', 2);
    INSERT INTO #periodosCreados (idPeriodo) VALUES (2);
END;

-- Partidos de prueba: 99801 Programado, 99802 Finalizado, 99803 En juego, 99804 Suspendido
INSERT INTO Torneo.Partido (nroPartidoOficial, idSede, idSeleccionLocal, idSeleccionVisitante, fase, fechaHoraUTC, estado)
VALUES (99801, @idSede, @idSelL, @idSelV, 998, '2026-06-20 18:00:00', 'Programado');
INSERT INTO Torneo.Partido (nroPartidoOficial, idSede, idSeleccionLocal, idSeleccionVisitante, fase, fechaHoraUTC, estado, golLocal, golVisitante)
VALUES (99802, @idSede, @idSelL, @idSelV, 998, '2026-06-19 18:00:00', 'Finalizado', 2, 1);
INSERT INTO Torneo.Partido (nroPartidoOficial, idSede, idSeleccionLocal, idSeleccionVisitante, fase, fechaHoraUTC, estado)
VALUES (99803, @idSede, @idSelL, @idSelV, 998, '2026-06-20 20:00:00', 'En juego');
INSERT INTO Torneo.Partido (nroPartidoOficial, idSede, idSeleccionLocal, idSeleccionVisitante, fase, fechaHoraUTC, estado)
VALUES (99804, @idSede, @idSelL, @idSelV, 998, '2026-06-21 18:00:00', 'Suspendido');

DECLARE @idPartFin   int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99802);
DECLARE @idPartJuego int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99803);
DECLARE @idPartSusp  int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99804);
DECLARE @idJA int = (SELECT id FROM Equipos.Jugador WHERE apellido = N'Jugador Local A');
DECLARE @idJB int = (SELECT id FROM Equipos.Jugador WHERE apellido = N'Jugador Local B');
DECLARE @idJC int = (SELECT id FROM Equipos.Jugador WHERE apellido = N'Jugador Local C');
DECLARE @idJX int = (SELECT id FROM Equipos.Jugador WHERE apellido = N'Jugador Visitante X');

-- Formaciones cargadas con INSERT directo: FormacionPartido_Alta rechaza altas en
-- partidos finalizados o en juego, pero en la realidad la formación se carga
-- antes del inicio. El fixture simula ese estado previo.
-- 99803 (En juego): A, B, C (locales) y X (visitante). Y queda fuera de la formación.
INSERT INTO Eventos.FormacionPartido (idPartido, idSeleccion, idJugador, titular, posicion) VALUES (@idPartJuego, @idSelL, @idJA, 1, 'Delantero');
INSERT INTO Eventos.FormacionPartido (idPartido, idSeleccion, idJugador, titular, posicion) VALUES (@idPartJuego, @idSelL, @idJB, 1, 'Mediocampista');
INSERT INTO Eventos.FormacionPartido (idPartido, idSeleccion, idJugador, titular, posicion) VALUES (@idPartJuego, @idSelL, @idJC, 0, NULL);
INSERT INTO Eventos.FormacionPartido (idPartido, idSeleccion, idJugador, titular, posicion) VALUES (@idPartJuego, @idSelV, @idJX, 1, 'Delantero');
-- 99802 (Finalizado): B sin incidencias, para la regla de estado en Modificación/Baja.
INSERT INTO Eventos.FormacionPartido (idPartido, idSeleccion, idJugador, titular, posicion) VALUES (@idPartFin, @idSelL, @idJB, 1, 'Mediocampista');
-- 99804 (Suspendido): A con un gol. Al no estar finalizado ni en juego, la
-- regla de incidencias de Modificación/Baja se evalúa sin que la tape la de estado.
INSERT INTO Eventos.FormacionPartido (idPartido, idSeleccion, idJugador, titular, posicion) VALUES (@idPartSusp, @idSelL, @idJA, 1, 'Delantero');
INSERT INTO Eventos.Gol (idPartido, idJugador, idAsistidor, minuto, minutoAdicional, tipo, idPeriodo) VALUES (@idPartSusp, @idJA, NULL, 30, NULL, 'Jugada', 1);

PRINT 'Fixture de pruebas inicializado con éxito.';
PRINT '';
GO

/* =============================================================================
   SECCIÓN 1: Eventos.FormacionPartido
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 1. PRUEBAS: Eventos.FormacionPartido';
PRINT '--------------------------------------------------------------------------------';

DECLARE @idPartProg  int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99801);
DECLARE @idPartFin   int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99802);
DECLARE @idPartSusp  int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99804);
DECLARE @idSelL int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'EVL');
DECLARE @idSelX int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'EVX');
DECLARE @idJA int = (SELECT id FROM Equipos.Jugador WHERE apellido = N'Jugador Local A');
DECLARE @idJB int = (SELECT id FROM Equipos.Jugador WHERE apellido = N'Jugador Local B');
DECLARE @idJC int = (SELECT id FROM Equipos.Jugador WHERE apellido = N'Jugador Local C');
DECLARE @idFormFin  int = (SELECT id FROM Eventos.FormacionPartido WHERE idPartido = @idPartFin AND idJugador = @idJB);
DECLARE @idFormSusp int = (SELECT id FROM Eventos.FormacionPartido WHERE idPartido = @idPartSusp AND idJugador = @idJA);
DECLARE @idFormacion int;

-- PRUEBA 1.1: Alta exitosa de un jugador titular en un partido programado
-- Resultado esperado: Inserción correcta con ID generado.
BEGIN TRY
    EXEC Eventos.FormacionPartido_Alta @idPartido = @idPartProg, @idSeleccion = @idSelL, @idJugador = @idJA,
         @titular = 1, @posicion = 'Delantero', @id = @idFormacion OUTPUT;
    SELECT 'ALTA 1.1' AS momento, id, idPartido, idSeleccion, idJugador, titular, posicion FROM Eventos.FormacionPartido WHERE id = @idFormacion;
    IF @idFormacion IS NOT NULL
        PRINT '[OK] PRUEBA 1.1: Formación dada de alta con ID = ' + CAST(@idFormacion AS varchar(10));
    ELSE PRINT '[FALLO] PRUEBA 1.1: No se devolvió el ID generado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.2: Alta con partido inexistente
-- Resultado esperado: THROW 50001 "- El partido especificado no existe."
BEGIN TRY
    EXEC Eventos.FormacionPartido_Alta @idPartido = -999, @idSeleccion = @idSelL, @idJugador = @idJC, @titular = 1;
    PRINT '[FALLO] PRUEBA 1.2: No detectó el partido inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%partido especificado no existe%'
        PRINT '[OK] PRUEBA 1.2: Partido inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 1.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.3: Alta con selección inexistente
-- Resultado esperado: THROW 50001 "- La selección especificada no existe."
BEGIN TRY
    EXEC Eventos.FormacionPartido_Alta @idPartido = @idPartProg, @idSeleccion = -999, @idJugador = @idJC, @titular = 1;
    PRINT '[FALLO] PRUEBA 1.3: No detectó la selección inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%selección especificada no existe%'
        PRINT '[OK] PRUEBA 1.3: Selección inexistente rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 1.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.4: Alta con jugador inexistente
-- Resultado esperado: THROW 50001 "- El jugador especificado no existe."
BEGIN TRY
    EXEC Eventos.FormacionPartido_Alta @idPartido = @idPartProg, @idSeleccion = @idSelL, @idJugador = -999, @titular = 1;
    PRINT '[FALLO] PRUEBA 1.4: No detectó el jugador inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%jugador especificado no existe%'
        PRINT '[OK] PRUEBA 1.4: Jugador inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 1.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.5: Alta sin indicar titularidad
-- Resultado esperado: THROW 50001 "- Debe indicar si el jugador es titular (1) o suplente (0)."
BEGIN TRY
    EXEC Eventos.FormacionPartido_Alta @idPartido = @idPartProg, @idSeleccion = @idSelL, @idJugador = @idJC, @titular = NULL;
    PRINT '[FALLO] PRUEBA 1.5: No detectó la titularidad nula.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%Debe indicar si el jugador es titular%'
        PRINT '[OK] PRUEBA 1.5: Titularidad nula rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 1.5: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.6: Alta con posición táctica inválida
-- Resultado esperado: THROW 50001 "- La posición táctica debe ser Arquero, Defensor, Mediocampista o Delantero."
BEGIN TRY
    EXEC Eventos.FormacionPartido_Alta @idPartido = @idPartProg, @idSeleccion = @idSelL, @idJugador = @idJC, @titular = 1, @posicion = 'Volante';
    PRINT '[FALLO] PRUEBA 1.6: No detectó la posición inválida.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%posición táctica debe ser%'
        PRINT '[OK] PRUEBA 1.6: Posición inválida rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 1.6: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.7: Alta con una selección que no disputa el partido
-- Resultado esperado: THROW 50001 "- La selección especificada no disputa el partido indicado."
BEGIN TRY
    EXEC Eventos.FormacionPartido_Alta @idPartido = @idPartProg, @idSeleccion = @idSelX, @idJugador = @idJC, @titular = 1;
    PRINT '[FALLO] PRUEBA 1.7: Permitió una selección ajena al partido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%no disputa el partido indicado%'
        PRINT '[OK] PRUEBA 1.7: Selección ajena al partido rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 1.7: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.8: Alta de un jugador ya registrado en la formación del partido (A, cargado en 1.1)
-- Resultado esperado: THROW 50001 "- El jugador ya se encuentra registrado en la formación de este partido."
BEGIN TRY
    EXEC Eventos.FormacionPartido_Alta @idPartido = @idPartProg, @idSeleccion = @idSelL, @idJugador = @idJA, @titular = 0;
    PRINT '[FALLO] PRUEBA 1.8: Permitió un jugador duplicado en la formación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%ya se encuentra registrado en la formación%'
        PRINT '[OK] PRUEBA 1.8: Jugador duplicado rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 1.8: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.9: Alta en un partido finalizado
-- Resultado esperado: THROW 50001 "- No se pueden agregar jugadores a la formación de un partido ya finalizado o que se encuentra en juego."
BEGIN TRY
    EXEC Eventos.FormacionPartido_Alta @idPartido = @idPartFin, @idSeleccion = @idSelL, @idJugador = @idJC, @titular = 1;
    PRINT '[FALLO] PRUEBA 1.9: Permitió el alta en un partido finalizado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%No se pueden agregar jugadores%finalizado o que se encuentra en juego%'
        PRINT '[OK] PRUEBA 1.9: Alta en partido finalizado rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 1.9: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.10: Alta con 3 errores simultáneos (partido inexistente, titular nulo, posición inválida)
-- Resultado esperado: THROW 50001 con los 3 mensajes juntos.
BEGIN TRY
    EXEC Eventos.FormacionPartido_Alta @idPartido = -999, @idSeleccion = @idSelL, @idJugador = @idJC, @titular = NULL, @posicion = 'Volante';
    PRINT '[FALLO] PRUEBA 1.10: No detectó los errores acumulados.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE '%partido especificado no existe%'
       AND ERROR_MESSAGE() LIKE '%Debe indicar si el jugador es titular%'
       AND ERROR_MESSAGE() LIKE N'%posición táctica debe ser%'
        PRINT '[OK] PRUEBA 1.10: Acumulación de 3 errores verificada.';
    ELSE PRINT '[FALLO] PRUEBA 1.10: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.11: Modificación de una formación inexistente
-- Resultado esperado: THROW 50001 "- El registro de formación a modificar no existe."
BEGIN TRY
    EXEC Eventos.FormacionPartido_Modificacion @id = -999, @idPartido = @idPartProg, @idSeleccion = @idSelL, @idJugador = @idJC, @titular = 1;
    PRINT '[FALLO] PRUEBA 1.11: No detectó la formación inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%formación a modificar no existe%'
        PRINT '[OK] PRUEBA 1.11: Formación inexistente rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 1.11: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.12: Modificación exitosa (A pasa a suplente y Mediocampista)
-- Resultado esperado: Registro actualizado; evidencia antes/después.
BEGIN TRY
    SELECT 'ANTES 1.12' AS momento, id, idJugador, titular, posicion FROM Eventos.FormacionPartido WHERE id = @idFormacion;
    EXEC Eventos.FormacionPartido_Modificacion @id = @idFormacion, @idPartido = @idPartProg, @idSeleccion = @idSelL,
         @idJugador = @idJA, @titular = 0, @posicion = 'Mediocampista';
    SELECT 'DESPUES 1.12' AS momento, id, idJugador, titular, posicion FROM Eventos.FormacionPartido WHERE id = @idFormacion;
    IF EXISTS (SELECT 1 FROM Eventos.FormacionPartido WHERE id = @idFormacion AND titular = 0 AND posicion = 'Mediocampista')
        PRINT '[OK] PRUEBA 1.12: Formación modificada con éxito.';
    ELSE PRINT '[FALLO] PRUEBA 1.12: El registro no quedó con los valores esperados.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.12: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.13: Modificación de una formación de un partido finalizado
-- Resultado esperado: THROW 50001 "- No se puede modificar la formación de un partido ya finalizado o que se encuentra en juego."
BEGIN TRY
    EXEC Eventos.FormacionPartido_Modificacion @id = @idFormFin, @idPartido = @idPartFin, @idSeleccion = @idSelL, @idJugador = @idJB, @titular = 0;
    PRINT '[FALLO] PRUEBA 1.13: Permitió modificar la formación de un partido finalizado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND @idFormFin IS NOT NULL
       AND ERROR_MESSAGE() NOT LIKE N'%formación a modificar no existe%'
       AND ERROR_MESSAGE() LIKE N'%No se puede modificar la formación de un partido ya finalizado%'
        PRINT '[OK] PRUEBA 1.13: Modificación en partido finalizado rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 1.13: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.14: Traslado de una formación (partido programado) a un partido finalizado
-- Resultado esperado: THROW 50001 "- No se puede trasladar la formación a un partido ya finalizado o en juego."
BEGIN TRY
    EXEC Eventos.FormacionPartido_Modificacion @id = @idFormacion, @idPartido = @idPartFin, @idSeleccion = @idSelL, @idJugador = @idJA, @titular = 0;
    PRINT '[FALLO] PRUEBA 1.14: Permitió trasladar la formación a un partido finalizado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND @idFormacion IS NOT NULL
       AND ERROR_MESSAGE() NOT LIKE N'%formación a modificar no existe%'
       AND ERROR_MESSAGE() LIKE N'%No se puede trasladar la formación%'
        PRINT '[OK] PRUEBA 1.14: Traslado a partido finalizado rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 1.14: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.15: Cambio de jugador en una formación con incidencias (A tiene un gol en el partido suspendido)
-- Resultado esperado: THROW 50001 "- No se puede modificar el jugador, la selección o el partido porque registra incidencias..."
BEGIN TRY
    EXEC Eventos.FormacionPartido_Modificacion @id = @idFormSusp, @idPartido = @idPartSusp, @idSeleccion = @idSelL, @idJugador = @idJB, @titular = 1;
    PRINT '[FALLO] PRUEBA 1.15: Permitió cambiar al jugador de una formación con incidencias.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND @idFormSusp IS NOT NULL
       AND ERROR_MESSAGE() NOT LIKE N'%formación a modificar no existe%'
       AND ERROR_MESSAGE() LIKE '%porque registra incidencias%'
        PRINT '[OK] PRUEBA 1.15: Cambio de jugador con incidencias rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 1.15: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.16: Baja de una formación inexistente
-- Resultado esperado: THROW 50001 "- El registro de formación a eliminar no existe."
BEGIN TRY
    EXEC Eventos.FormacionPartido_Baja @id = -999;
    PRINT '[FALLO] PRUEBA 1.16: No detectó la formación inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%formación a eliminar no existe%'
        PRINT '[OK] PRUEBA 1.16: Baja de formación inexistente rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 1.16: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.17: Baja de una formación de un partido finalizado
-- Resultado esperado: THROW 50001 "- No se puede eliminar a un jugador de la formación de un partido ya finalizado o en juego."
BEGIN TRY
    EXEC Eventos.FormacionPartido_Baja @id = @idFormFin;
    PRINT '[FALLO] PRUEBA 1.17: Permitió la baja en un partido finalizado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND @idFormFin IS NOT NULL
       AND ERROR_MESSAGE() NOT LIKE N'%formación a eliminar no existe%'
       AND ERROR_MESSAGE() LIKE N'%No se puede eliminar a un jugador de la formación de un partido ya finalizado%'
        PRINT '[OK] PRUEBA 1.17: Baja en partido finalizado rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 1.17: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.18: Baja de una formación con incidencias (A tiene un gol en el partido suspendido)
-- Resultado esperado: THROW 50001 "- No se puede eliminar al jugador de la formación porque registra goles o asistencias en este partido."
BEGIN TRY
    EXEC Eventos.FormacionPartido_Baja @id = @idFormSusp;
    PRINT '[FALLO] PRUEBA 1.18: Permitió la baja de una formación con goles.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND @idFormSusp IS NOT NULL
       AND ERROR_MESSAGE() NOT LIKE N'%formación a eliminar no existe%'
       AND ERROR_MESSAGE() LIKE '%registra goles o asistencias%'
        PRINT '[OK] PRUEBA 1.18: Baja de formación con goles rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 1.18: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.19: Baja exitosa de la formación creada en 1.1
-- Resultado esperado: Registro eliminado; evidencia antes/después.
BEGIN TRY
    SELECT 'ANTES 1.19' AS momento, COUNT(*) AS filas FROM Eventos.FormacionPartido WHERE id = @idFormacion;
    EXEC Eventos.FormacionPartido_Baja @id = @idFormacion;
    SELECT 'DESPUES 1.19' AS momento, COUNT(*) AS filas FROM Eventos.FormacionPartido WHERE id = @idFormacion;
    IF NOT EXISTS (SELECT 1 FROM Eventos.FormacionPartido WHERE id = @idFormacion)
        PRINT '[OK] PRUEBA 1.19: Formación eliminada con éxito.';
    ELSE PRINT '[FALLO] PRUEBA 1.19: La formación sigue existiendo.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.19: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   SECCIÓN 2: Eventos.Gol   (partido 99803 'En juego' salvo indicación)
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 2. PRUEBAS: Eventos.Gol';
PRINT '--------------------------------------------------------------------------------';

DECLARE @idPartProg  int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99801);
DECLARE @idPartJuego int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99803);
DECLARE @idJA int = (SELECT id FROM Equipos.Jugador WHERE apellido = N'Jugador Local A');
DECLARE @idJB int = (SELECT id FROM Equipos.Jugador WHERE apellido = N'Jugador Local B');
DECLARE @idJX int = (SELECT id FROM Equipos.Jugador WHERE apellido = N'Jugador Visitante X');
DECLARE @idJY int = (SELECT id FROM Equipos.Jugador WHERE apellido = N'Jugador Visitante Y');
DECLARE @idGol int, @idGolPenal int, @idGol120 int, @idGolAdic int;

-- PRUEBA 2.1: Alta exitosa de un gol de jugada con asistencia
-- Resultado esperado: Inserción correcta con ID generado.
BEGIN TRY
    EXEC Eventos.Gol_Alta @idPartido = @idPartJuego, @idJugador = @idJA, @idAsistidor = @idJB, @minuto = 30,
         @tipo = 'Jugada', @idPeriodo = 1, @idGol = @idGol OUTPUT;
    SELECT 'ALTA 2.1' AS momento, * FROM Eventos.Gol WHERE idGol = @idGol;
    IF @idGol IS NOT NULL PRINT '[OK] PRUEBA 2.1: Gol con asistencia registrado con ID = ' + CAST(@idGol AS varchar(10));
    ELSE PRINT '[FALLO] PRUEBA 2.1: No se devolvió el ID generado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.2: Alta exitosa de un gol de penal en la definición (minuto NULL)
-- Resultado esperado: Inserción correcta con minuto NULL.
BEGIN TRY
    EXEC Eventos.Gol_Alta @idPartido = @idPartJuego, @idJugador = @idJX, @minuto = NULL, @tipo = 'Penal', @idPeriodo = 2, @idGol = @idGolPenal OUTPUT;
    SELECT 'ALTA 2.2' AS momento, * FROM Eventos.Gol WHERE idGol = @idGolPenal;
    IF EXISTS (SELECT 1 FROM Eventos.Gol WHERE idGol = @idGolPenal AND minuto IS NULL AND tipo = 'Penal')
        PRINT '[OK] PRUEBA 2.2: Gol de penal sin minuto registrado.';
    ELSE PRINT '[FALLO] PRUEBA 2.2: El registro no quedó con los valores esperados.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.3: Valor límite - gol en el minuto 120
-- Resultado esperado: Inserción correcta (120 es el máximo permitido).
BEGIN TRY
    EXEC Eventos.Gol_Alta @idPartido = @idPartJuego, @idJugador = @idJA, @minuto = 120, @tipo = 'Cabeza', @idPeriodo = 2, @idGol = @idGol120 OUTPUT;
    IF EXISTS (SELECT 1 FROM Eventos.Gol WHERE idGol = @idGol120 AND minuto = 120)
        PRINT '[OK] PRUEBA 2.3: Gol en el minuto 120 aceptado.';
    ELSE PRINT '[FALLO] PRUEBA 2.3: El gol no quedó registrado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.4: Valor límite - minuto adicional sobre el minuto 90 (90+3)
-- Resultado esperado: Inserción correcta (90 es un minuto de cierre reglamentario).
BEGIN TRY
    EXEC Eventos.Gol_Alta @idPartido = @idPartJuego, @idJugador = @idJB, @minuto = 90, @minutoAdicional = 3,
         @tipo = 'Tiro libre', @idPeriodo = 2, @idGol = @idGolAdic OUTPUT;
    IF EXISTS (SELECT 1 FROM Eventos.Gol WHERE idGol = @idGolAdic AND minuto = 90 AND minutoAdicional = 3)
        PRINT '[OK] PRUEBA 2.4: Gol en el minuto 90+3 aceptado.';
    ELSE PRINT '[FALLO] PRUEBA 2.4: El gol no quedó registrado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.5: Alta con partido inexistente
-- Resultado esperado: THROW 50001 "- El partido especificado no existe."
BEGIN TRY
    EXEC Eventos.Gol_Alta @idPartido = -999, @idJugador = @idJA, @minuto = 10, @tipo = 'Jugada', @idPeriodo = 1;
    PRINT '[FALLO] PRUEBA 2.5: No detectó el partido inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%partido especificado no existe%'
        PRINT '[OK] PRUEBA 2.5: Partido inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.5: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.6: Alta con autor inexistente
-- Resultado esperado: THROW 50001 "- El jugador autor del gol no existe."
BEGIN TRY
    EXEC Eventos.Gol_Alta @idPartido = @idPartJuego, @idJugador = -999, @minuto = 10, @tipo = 'Jugada', @idPeriodo = 1;
    PRINT '[FALLO] PRUEBA 2.6: No detectó el autor inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%jugador autor del gol no existe%'
        PRINT '[OK] PRUEBA 2.6: Autor inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.6: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.7: Alta con período inexistente
-- Resultado esperado: THROW 50001 "- El período de juego especificado no existe."
BEGIN TRY
    EXEC Eventos.Gol_Alta @idPartido = @idPartJuego, @idJugador = @idJA, @minuto = 10, @tipo = 'Jugada', @idPeriodo = 99;
    PRINT '[FALLO] PRUEBA 2.7: No detectó el período inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%período de juego especificado no existe%'
        PRINT '[OK] PRUEBA 2.7: Período inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.7: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.8: Alta con asistidor inexistente
-- Resultado esperado: THROW 50001 "- El jugador asistidor especificado no existe."
BEGIN TRY
    EXEC Eventos.Gol_Alta @idPartido = @idPartJuego, @idJugador = @idJA, @idAsistidor = -999, @minuto = 10, @tipo = 'Jugada', @idPeriodo = 1;
    PRINT '[FALLO] PRUEBA 2.8: No detectó el asistidor inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%asistidor especificado no existe%'
        PRINT '[OK] PRUEBA 2.8: Asistidor inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.8: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.9: Alta con el autor como su propio asistidor
-- Resultado esperado: THROW 50001 "- El asistidor no puede ser el mismo jugador que convirtió el gol."
BEGIN TRY
    EXEC Eventos.Gol_Alta @idPartido = @idPartJuego, @idJugador = @idJA, @idAsistidor = @idJA, @minuto = 10, @tipo = 'Jugada', @idPeriodo = 1;
    PRINT '[FALLO] PRUEBA 2.9: Permitió que el autor se asista a sí mismo.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%asistidor no puede ser el mismo jugador%'
        PRINT '[OK] PRUEBA 2.9: Autoasistencia rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 2.9: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.10: Alta sin tipo de gol
-- Resultado esperado: THROW 50001 "- El tipo de gol es obligatorio."
BEGIN TRY
    EXEC Eventos.Gol_Alta @idPartido = @idPartJuego, @idJugador = @idJA, @minuto = 10, @tipo = NULL, @idPeriodo = 1;
    PRINT '[FALLO] PRUEBA 2.10: No detectó el tipo de gol nulo.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%tipo de gol es obligatorio%'
        PRINT '[OK] PRUEBA 2.10: Tipo de gol nulo rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.10: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.11: Alta con un tipo de gol fuera del dominio permitido
-- Resultado esperado: THROW 50001 "- El tipo de gol debe ser Jugada, Penal, Tiro libre, En contra o Cabeza."
BEGIN TRY
    EXEC Eventos.Gol_Alta @idPartido = @idPartJuego, @idJugador = @idJA, @minuto = 10, @tipo = 'Chilena', @idPeriodo = 1;
    PRINT '[FALLO] PRUEBA 2.11: Permitió un tipo de gol fuera del dominio.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%tipo de gol debe ser Jugada, Penal, Tiro libre, En contra o Cabeza%'
        PRINT '[OK] PRUEBA 2.11: Tipo de gol fuera del dominio rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.11: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.12: Valor límite - gol en el minuto 121
-- Resultado esperado: THROW 50001 "- El minuto del gol debe estar comprendido entre 0 y 120."
BEGIN TRY
    EXEC Eventos.Gol_Alta @idPartido = @idPartJuego, @idJugador = @idJA, @minuto = 121, @tipo = 'Jugada', @idPeriodo = 2;
    PRINT '[FALLO] PRUEBA 2.12: Permitió el minuto 121.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%minuto del gol debe estar comprendido entre 0 y 120%'
        PRINT '[OK] PRUEBA 2.12: Minuto 121 rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.12: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.13: Alta con minuto adicional fuera de un minuto de cierre (30+2)
-- Resultado esperado: THROW 50001 "- El minuto adicional solo es válido en los minutos de cierre reglamentario..."
BEGIN TRY
    EXEC Eventos.Gol_Alta @idPartido = @idPartJuego, @idJugador = @idJA, @minuto = 30, @minutoAdicional = 2, @tipo = 'Jugada', @idPeriodo = 1;
    PRINT '[FALLO] PRUEBA 2.13: Permitió minuto adicional en el minuto 30.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%minuto adicional solo es válido%'
        PRINT '[OK] PRUEBA 2.13: Minuto adicional inválido rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.13: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.14: Alta en un partido programado
-- Resultado esperado: THROW 50001 "- No se pueden registrar goles en un partido que todavía se encuentra en estado programado."
BEGIN TRY
    EXEC Eventos.Gol_Alta @idPartido = @idPartProg, @idJugador = @idJA, @minuto = 10, @tipo = 'Jugada', @idPeriodo = 1;
    PRINT '[FALLO] PRUEBA 2.14: Permitió un gol en un partido programado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%No se pueden registrar goles en un partido%programado%'
        PRINT '[OK] PRUEBA 2.14: Gol en partido programado rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.14: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.15: Alta con un autor que no está en la formación (Y)
-- Resultado esperado: THROW 50001 "- El autor del gol debe estar registrado en la formación del partido."
BEGIN TRY
    EXEC Eventos.Gol_Alta @idPartido = @idPartJuego, @idJugador = @idJY, @minuto = 10, @tipo = 'Jugada', @idPeriodo = 1;
    PRINT '[FALLO] PRUEBA 2.15: Permitió un autor fuera de la formación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%autor del gol debe estar registrado en la formación%'
        PRINT '[OK] PRUEBA 2.15: Autor fuera de la formación rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.15: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.16: Alta con un asistidor que no está en la formación (Y)
-- Resultado esperado: THROW 50001 "- El jugador asistidor debe estar registrado en la formación del partido."
BEGIN TRY
    EXEC Eventos.Gol_Alta @idPartido = @idPartJuego, @idJugador = @idJA, @idAsistidor = @idJY, @minuto = 10, @tipo = 'Jugada', @idPeriodo = 1;
    PRINT '[FALLO] PRUEBA 2.16: Permitió un asistidor fuera de la formación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%asistidor debe estar registrado en la formación%'
        PRINT '[OK] PRUEBA 2.16: Asistidor fuera de la formación rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.16: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.17: Alta con un asistidor de la selección rival (A local, X visitante)
-- Resultado esperado: THROW 50001 "- El asistidor debe pertenecer a la misma selección que el autor del gol."
BEGIN TRY
    EXEC Eventos.Gol_Alta @idPartido = @idPartJuego, @idJugador = @idJA, @idAsistidor = @idJX, @minuto = 10, @tipo = 'Jugada', @idPeriodo = 1;
    PRINT '[FALLO] PRUEBA 2.17: Permitió un asistidor de la selección rival.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%asistidor debe pertenecer a la misma selección%'
        PRINT '[OK] PRUEBA 2.17: Asistidor de otra selección rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.17: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.18: Alta con 3 errores simultáneos (período inexistente, tipo inválido, minuto 121)
-- Resultado esperado: THROW 50001 con los 3 mensajes juntos.
BEGIN TRY
    EXEC Eventos.Gol_Alta @idPartido = @idPartJuego, @idJugador = @idJA, @minuto = 121, @tipo = 'Chilena', @idPeriodo = 99;
    PRINT '[FALLO] PRUEBA 2.18: No detectó los errores acumulados.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'%período de juego especificado no existe%'
       AND ERROR_MESSAGE() LIKE '%tipo de gol debe ser%'
       AND ERROR_MESSAGE() LIKE '%minuto del gol debe estar comprendido%'
        PRINT '[OK] PRUEBA 2.18: Acumulación de 3 errores verificada.';
    ELSE PRINT '[FALLO] PRUEBA 2.18: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.19: Modificación de un gol inexistente
-- Resultado esperado: THROW 50001 "- El registro del gol a modificar no existe."
BEGIN TRY
    EXEC Eventos.Gol_Modificacion @idGol = -999, @idPartido = @idPartJuego, @idJugador = @idJA, @minuto = 10, @tipo = 'Jugada', @idPeriodo = 1;
    PRINT '[FALLO] PRUEBA 2.19: No detectó el gol inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%gol a modificar no existe%'
        PRINT '[OK] PRUEBA 2.19: Gol inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.19: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.20: Modificación exitosa del gol de 2.1 (minuto 35, tiro libre, sin asistencia)
-- Resultado esperado: Registro actualizado; evidencia antes/después.
BEGIN TRY
    SELECT 'ANTES 2.20' AS momento, * FROM Eventos.Gol WHERE idGol = @idGol;
    EXEC Eventos.Gol_Modificacion @idGol = @idGol, @idPartido = @idPartJuego, @idJugador = @idJA, @idAsistidor = NULL,
         @minuto = 35, @tipo = 'Tiro libre', @idPeriodo = 1;
    SELECT 'DESPUES 2.20' AS momento, * FROM Eventos.Gol WHERE idGol = @idGol;
    IF EXISTS (SELECT 1 FROM Eventos.Gol WHERE idGol = @idGol AND minuto = 35 AND tipo = 'Tiro libre' AND idAsistidor IS NULL)
        PRINT '[OK] PRUEBA 2.20: Gol modificado con éxito.';
    ELSE PRINT '[FALLO] PRUEBA 2.20: El registro no quedó con los valores esperados.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.20: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.21: Baja de un gol inexistente
-- Resultado esperado: THROW 50001 "- El registro de gol a eliminar no existe."
BEGIN TRY
    EXEC Eventos.Gol_Baja @idGol = -999;
    PRINT '[FALLO] PRUEBA 2.21: No detectó el gol inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%gol a eliminar no existe%'
        PRINT '[OK] PRUEBA 2.21: Baja de gol inexistente rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 2.21: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.22: Baja exitosa del gol de 2.1
-- Resultado esperado: Registro eliminado; evidencia antes/después.
BEGIN TRY
    SELECT 'ANTES 2.22' AS momento, COUNT(*) AS filas FROM Eventos.Gol WHERE idGol = @idGol;
    EXEC Eventos.Gol_Baja @idGol = @idGol;
    SELECT 'DESPUES 2.22' AS momento, COUNT(*) AS filas FROM Eventos.Gol WHERE idGol = @idGol;
    IF NOT EXISTS (SELECT 1 FROM Eventos.Gol WHERE idGol = @idGol)
        PRINT '[OK] PRUEBA 2.22: Gol eliminado con éxito.';
    ELSE PRINT '[FALLO] PRUEBA 2.22: El gol sigue existiendo.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.22: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   SECCIÓN 3: Eventos.Tarjeta   (partido 99803 'En juego' salvo indicación)
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 3. PRUEBAS: Eventos.Tarjeta';
PRINT '--------------------------------------------------------------------------------';

DECLARE @idPartProg  int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99801);
DECLARE @idPartJuego int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99803);
DECLARE @idJA int = (SELECT id FROM Equipos.Jugador WHERE apellido = N'Jugador Local A');
DECLARE @idJY int = (SELECT id FROM Equipos.Jugador WHERE apellido = N'Jugador Visitante Y');
DECLARE @idStaffL int = (SELECT id FROM Equipos.Staff WHERE apellido = N'Staff Test Local');
DECLARE @idStaffX int = (SELECT id FROM Equipos.Staff WHERE apellido = N'Staff Test Ajeno');
DECLARE @idTarjeta int, @idTarjetaRoja int;

-- PRUEBA 3.1: Alta exitosa de una amarilla a un jugador
-- Resultado esperado: Inserción correcta con ID generado.
BEGIN TRY
    EXEC Eventos.Tarjeta_Alta @idPartido = @idPartJuego, @idJugador = @idJA, @idPeriodo = 1, @color = 'A', @minuto = 25,
         @motivo = 'Juego brusco', @idTarjeta = @idTarjeta OUTPUT;
    SELECT 'ALTA 3.1' AS momento, * FROM Eventos.Tarjeta WHERE idTarjeta = @idTarjeta;
    IF @idTarjeta IS NOT NULL PRINT '[OK] PRUEBA 3.1: Amarilla registrada con ID = ' + CAST(@idTarjeta AS varchar(10));
    ELSE PRINT '[FALLO] PRUEBA 3.1: No se devolvió el ID generado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 3.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.2: Alta exitosa de una roja directa a un integrante del cuerpo técnico
-- Resultado esperado: Inserción correcta con idStaff y tipoRoja = 'Directa'.
BEGIN TRY
    EXEC Eventos.Tarjeta_Alta @idPartido = @idPartJuego, @idStaff = @idStaffL, @idPeriodo = 2, @color = 'R', @minuto = 70,
         @motivo = 'Protestas', @tipoRoja = 'Directa', @idTarjeta = @idTarjetaRoja OUTPUT;
    SELECT 'ALTA 3.2' AS momento, * FROM Eventos.Tarjeta WHERE idTarjeta = @idTarjetaRoja;
    IF EXISTS (SELECT 1 FROM Eventos.Tarjeta WHERE idTarjeta = @idTarjetaRoja AND idStaff = @idStaffL AND tipoRoja = 'Directa')
        PRINT '[OK] PRUEBA 3.2: Roja directa al cuerpo técnico registrada.';
    ELSE PRINT '[FALLO] PRUEBA 3.2: El registro no quedó con los valores esperados.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 3.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.3: Alta con partido inexistente
-- Resultado esperado: THROW 50001 "- El partido especificado no existe."
BEGIN TRY
    EXEC Eventos.Tarjeta_Alta @idPartido = -999, @idJugador = @idJA, @idPeriodo = 1, @color = 'A', @minuto = 10;
    PRINT '[FALLO] PRUEBA 3.3: No detectó el partido inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%partido especificado no existe%'
        PRINT '[OK] PRUEBA 3.3: Partido inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 3.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.4: Alta con período inexistente
-- Resultado esperado: THROW 50001 "- El período de juego especificado no existe."
BEGIN TRY
    EXEC Eventos.Tarjeta_Alta @idPartido = @idPartJuego, @idJugador = @idJA, @idPeriodo = 99, @color = 'A', @minuto = 10;
    PRINT '[FALLO] PRUEBA 3.4: No detectó el período inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%período de juego especificado no existe%'
        PRINT '[OK] PRUEBA 3.4: Período inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 3.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.5: Alta sin jugador ni integrante del cuerpo técnico
-- Resultado esperado: THROW 50001 "- Debe especificar exactamente a un jugador o a un integrante del cuerpo técnico, no ambos ni ninguno."
BEGIN TRY
    EXEC Eventos.Tarjeta_Alta @idPartido = @idPartJuego, @idJugador = NULL, @idStaff = NULL, @idPeriodo = 1, @color = 'A', @minuto = 10;
    PRINT '[FALLO] PRUEBA 3.5: Permitió una tarjeta sin destinatario.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%exactamente a un jugador o a un integrante%'
        PRINT '[OK] PRUEBA 3.5: Tarjeta sin destinatario rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 3.5: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.6: Alta con jugador inexistente
-- Resultado esperado: THROW 50001 "- El jugador especificado no existe."
BEGIN TRY
    EXEC Eventos.Tarjeta_Alta @idPartido = @idPartJuego, @idJugador = -999, @idPeriodo = 1, @color = 'A', @minuto = 10;
    PRINT '[FALLO] PRUEBA 3.6: No detectó el jugador inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%jugador especificado no existe%'
        PRINT '[OK] PRUEBA 3.6: Jugador inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 3.6: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.7: Alta a un jugador que no está en la formación (Y)
-- Resultado esperado: THROW 50001 "- El jugador amonestado/expulsado debe estar registrado en la formación del partido."
BEGIN TRY
    EXEC Eventos.Tarjeta_Alta @idPartido = @idPartJuego, @idJugador = @idJY, @idPeriodo = 1, @color = 'A', @minuto = 10;
    PRINT '[FALLO] PRUEBA 3.7: Permitió amonestar a un jugador fuera de la formación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%amonestado/expulsado debe estar registrado en la formación%'
        PRINT '[OK] PRUEBA 3.7: Jugador fuera de la formación rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 3.7: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.8: Alta con integrante del cuerpo técnico inexistente
-- Resultado esperado: THROW 50001 "- El integrante del cuerpo técnico especificado no existe."
BEGIN TRY
    EXEC Eventos.Tarjeta_Alta @idPartido = @idPartJuego, @idStaff = -999, @idPeriodo = 1, @color = 'A', @minuto = 10;
    PRINT '[FALLO] PRUEBA 3.8: No detectó el staff inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%cuerpo técnico especificado no existe%'
        PRINT '[OK] PRUEBA 3.8: Staff inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 3.8: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.9: Alta a un integrante del cuerpo técnico de una selección ajena al partido
-- Resultado esperado: THROW 50001 "- El integrante del cuerpo técnico no pertenece a ninguna de las selecciones que disputan el partido."
BEGIN TRY
    EXEC Eventos.Tarjeta_Alta @idPartido = @idPartJuego, @idStaff = @idStaffX, @idPeriodo = 1, @color = 'A', @minuto = 10;
    PRINT '[FALLO] PRUEBA 3.9: Permitió amonestar a un staff ajeno al partido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%no pertenece a ninguna de las selecciones%'
        PRINT '[OK] PRUEBA 3.9: Staff ajeno al partido rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 3.9: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.10: Alta con color inválido ('V')
-- Resultado esperado: THROW 50001 "- El color de la tarjeta debe ser 'A' (amarilla) o 'R' (roja)."
BEGIN TRY
    EXEC Eventos.Tarjeta_Alta @idPartido = @idPartJuego, @idJugador = @idJA, @idPeriodo = 1, @color = 'V', @minuto = 10;
    PRINT '[FALLO] PRUEBA 3.10: Permitió un color inválido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%color de la tarjeta debe ser%'
        PRINT '[OK] PRUEBA 3.10: Color inválido rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 3.10: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.11: Alta de una amarilla con tipo de expulsión
-- Resultado esperado: THROW 50001 "- Las tarjetas amarillas no deben indicar tipo de expulsión."
BEGIN TRY
    EXEC Eventos.Tarjeta_Alta @idPartido = @idPartJuego, @idJugador = @idJA, @idPeriodo = 1, @color = 'A', @minuto = 10, @tipoRoja = 'Directa';
    PRINT '[FALLO] PRUEBA 3.11: Permitió una amarilla con tipo de expulsión.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%amarillas no deben indicar tipo%'
        PRINT '[OK] PRUEBA 3.11: Amarilla con tipo de expulsión rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 3.11: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.12: Alta de una roja sin tipo de expulsión
-- Resultado esperado: THROW 50001 "- Para tarjetas rojas, el tipo debe ser 'Directa' o 'Doble amarilla'."
BEGIN TRY
    EXEC Eventos.Tarjeta_Alta @idPartido = @idPartJuego, @idJugador = @idJA, @idPeriodo = 1, @color = 'R', @minuto = 10, @tipoRoja = NULL;
    PRINT '[FALLO] PRUEBA 3.12: Permitió una roja sin tipo.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%Para tarjetas rojas, el tipo debe ser%'
        PRINT '[OK] PRUEBA 3.12: Roja sin tipo rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 3.12: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.13: Alta sin minuto
-- Resultado esperado: THROW 50001 "- El minuto de la tarjeta es obligatorio y debe encontrarse entre 0 y 120."
BEGIN TRY
    EXEC Eventos.Tarjeta_Alta @idPartido = @idPartJuego, @idJugador = @idJA, @idPeriodo = 1, @color = 'A', @minuto = NULL;
    PRINT '[FALLO] PRUEBA 3.13: Permitió una tarjeta sin minuto.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%minuto de la tarjeta es obligatorio%'
        PRINT '[OK] PRUEBA 3.13: Tarjeta sin minuto rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 3.13: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.14: Alta con minuto adicional fuera de un minuto de cierre (30+2)
-- Resultado esperado: THROW 50001 "- El minuto adicional solo es válido en los minutos de cierre reglamentario..."
BEGIN TRY
    EXEC Eventos.Tarjeta_Alta @idPartido = @idPartJuego, @idJugador = @idJA, @idPeriodo = 1, @color = 'A', @minuto = 30, @minutoAdicional = 2;
    PRINT '[FALLO] PRUEBA 3.14: Permitió minuto adicional en el minuto 30.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%minuto adicional solo es válido%'
        PRINT '[OK] PRUEBA 3.14: Minuto adicional inválido rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 3.14: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.15: Alta en un partido programado (staff local, que sí pertenece al partido)
-- Resultado esperado: THROW 50001 "- No se pueden registrar tarjetas en un partido que todavía se encuentra en estado programado."
BEGIN TRY
    EXEC Eventos.Tarjeta_Alta @idPartido = @idPartProg, @idStaff = @idStaffL, @idPeriodo = 1, @color = 'A', @minuto = 10;
    PRINT '[FALLO] PRUEBA 3.15: Permitió una tarjeta en un partido programado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%No se pueden registrar tarjetas en un partido%programado%'
        PRINT '[OK] PRUEBA 3.15: Tarjeta en partido programado rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 3.15: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.16: Alta con 3 errores simultáneos (período inexistente, color inválido, minuto nulo)
-- Resultado esperado: THROW 50001 con los 3 mensajes juntos.
BEGIN TRY
    EXEC Eventos.Tarjeta_Alta @idPartido = @idPartJuego, @idJugador = @idJA, @idPeriodo = 99, @color = 'V', @minuto = NULL;
    PRINT '[FALLO] PRUEBA 3.16: No detectó los errores acumulados.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'%período de juego especificado no existe%'
       AND ERROR_MESSAGE() LIKE '%color de la tarjeta debe ser%'
       AND ERROR_MESSAGE() LIKE '%minuto de la tarjeta es obligatorio%'
        PRINT '[OK] PRUEBA 3.16: Acumulación de 3 errores verificada.';
    ELSE PRINT '[FALLO] PRUEBA 3.16: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.17: Modificación de una tarjeta inexistente
-- Resultado esperado: THROW 50001 "- El registro de la tarjeta a modificar no existe."
BEGIN TRY
    EXEC Eventos.Tarjeta_Modificacion @idTarjeta = -999, @idPartido = @idPartJuego, @idJugador = @idJA, @idPeriodo = 1, @color = 'A', @minuto = 10;
    PRINT '[FALLO] PRUEBA 3.17: No detectó la tarjeta inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%tarjeta a modificar no existe%'
        PRINT '[OK] PRUEBA 3.17: Tarjeta inexistente rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 3.17: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.18: Modificación exitosa de la amarilla de 3.1 a roja por doble amarilla
-- Resultado esperado: Registro actualizado; evidencia antes/después.
BEGIN TRY
    SELECT 'ANTES 3.18' AS momento, * FROM Eventos.Tarjeta WHERE idTarjeta = @idTarjeta;
    EXEC Eventos.Tarjeta_Modificacion @idTarjeta = @idTarjeta, @idPartido = @idPartJuego, @idJugador = @idJA, @idPeriodo = 2,
         @color = 'R', @minuto = 80, @motivo = 'Segunda amarilla', @tipoRoja = 'Doble amarilla';
    SELECT 'DESPUES 3.18' AS momento, * FROM Eventos.Tarjeta WHERE idTarjeta = @idTarjeta;
    IF EXISTS (SELECT 1 FROM Eventos.Tarjeta WHERE idTarjeta = @idTarjeta AND color = 'R' AND tipoRoja = 'Doble amarilla' AND minuto = 80)
        PRINT '[OK] PRUEBA 3.18: Tarjeta modificada con éxito.';
    ELSE PRINT '[FALLO] PRUEBA 3.18: El registro no quedó con los valores esperados.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 3.18: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.19: Baja de una tarjeta inexistente
-- Resultado esperado: THROW 50001 "- El registro de la tarjeta a eliminar no existe."
BEGIN TRY
    EXEC Eventos.Tarjeta_Baja @idTarjeta = -999;
    PRINT '[FALLO] PRUEBA 3.19: No detectó la tarjeta inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%tarjeta a eliminar no existe%'
        PRINT '[OK] PRUEBA 3.19: Baja de tarjeta inexistente rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 3.19: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.20: Baja exitosa de la tarjeta de 3.1
-- Resultado esperado: Registro eliminado; evidencia antes/después.
BEGIN TRY
    SELECT 'ANTES 3.20' AS momento, COUNT(*) AS filas FROM Eventos.Tarjeta WHERE idTarjeta = @idTarjeta;
    EXEC Eventos.Tarjeta_Baja @idTarjeta = @idTarjeta;
    SELECT 'DESPUES 3.20' AS momento, COUNT(*) AS filas FROM Eventos.Tarjeta WHERE idTarjeta = @idTarjeta;
    IF NOT EXISTS (SELECT 1 FROM Eventos.Tarjeta WHERE idTarjeta = @idTarjeta)
        PRINT '[OK] PRUEBA 3.20: Tarjeta eliminada con éxito.';
    ELSE PRINT '[FALLO] PRUEBA 3.20: La tarjeta sigue existiendo.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 3.20: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   SECCIÓN 4: Eventos.Sustitucion   (partido 99803 'En juego' salvo indicación)
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 4. PRUEBAS: Eventos.Sustitucion';
PRINT '--------------------------------------------------------------------------------';

DECLARE @idPartProg  int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99801);
DECLARE @idPartJuego int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99803);
DECLARE @idJB int = (SELECT id FROM Equipos.Jugador WHERE apellido = N'Jugador Local B');
DECLARE @idJC int = (SELECT id FROM Equipos.Jugador WHERE apellido = N'Jugador Local C');
DECLARE @idJX int = (SELECT id FROM Equipos.Jugador WHERE apellido = N'Jugador Visitante X');
DECLARE @idJY int = (SELECT id FROM Equipos.Jugador WHERE apellido = N'Jugador Visitante Y');
DECLARE @idSust int;

-- PRUEBA 4.1: Alta exitosa de una sustitución táctica (entra C, sale B)
-- Resultado esperado: Inserción correcta con ID generado.
BEGIN TRY
    EXEC Eventos.Sustitucion_Alta @idPartido = @idPartJuego, @idIngresa = @idJC, @idSale = @idJB, @idPeriodo = 2, @minuto = 60,
         @motivo = 'Tactico', @id = @idSust OUTPUT;
    SELECT 'ALTA 4.1' AS momento, * FROM Eventos.Sustitucion WHERE id = @idSust;
    IF @idSust IS NOT NULL PRINT '[OK] PRUEBA 4.1: Sustitución registrada con ID = ' + CAST(@idSust AS varchar(10));
    ELSE PRINT '[FALLO] PRUEBA 4.1: No se devolvió el ID generado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 4.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.2: Alta con partido inexistente
-- Resultado esperado: THROW 50001 "- El partido especificado no existe."
BEGIN TRY
    EXEC Eventos.Sustitucion_Alta @idPartido = -999, @idIngresa = @idJC, @idSale = @idJB, @idPeriodo = 2, @minuto = 60, @motivo = 'Tactico';
    PRINT '[FALLO] PRUEBA 4.2: No detectó el partido inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%partido especificado no existe%'
        PRINT '[OK] PRUEBA 4.2: Partido inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 4.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.3: Alta con jugador que ingresa inexistente
-- Resultado esperado: THROW 50001 "- El jugador que ingresa no existe."
BEGIN TRY
    EXEC Eventos.Sustitucion_Alta @idPartido = @idPartJuego, @idIngresa = -999, @idSale = @idJB, @idPeriodo = 2, @minuto = 60, @motivo = 'Tactico';
    PRINT '[FALLO] PRUEBA 4.3: No detectó el jugador que ingresa inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%jugador que ingresa no existe%'
        PRINT '[OK] PRUEBA 4.3: Jugador que ingresa inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 4.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.4: Alta con jugador que sale inexistente
-- Resultado esperado: THROW 50001 "- El jugador que sale no existe."
BEGIN TRY
    EXEC Eventos.Sustitucion_Alta @idPartido = @idPartJuego, @idIngresa = @idJC, @idSale = -999, @idPeriodo = 2, @minuto = 60, @motivo = 'Tactico';
    PRINT '[FALLO] PRUEBA 4.4: No detectó el jugador que sale inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%jugador que sale no existe%'
        PRINT '[OK] PRUEBA 4.4: Jugador que sale inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 4.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.5: Alta con período inexistente
-- Resultado esperado: THROW 50001 "- El período de juego especificado no existe."
BEGIN TRY
    EXEC Eventos.Sustitucion_Alta @idPartido = @idPartJuego, @idIngresa = @idJC, @idSale = @idJB, @idPeriodo = 99, @minuto = 60, @motivo = 'Tactico';
    PRINT '[FALLO] PRUEBA 4.5: No detectó el período inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%período de juego especificado no existe%'
        PRINT '[OK] PRUEBA 4.5: Período inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 4.5: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.6: Alta con el mismo jugador entrando y saliendo
-- Resultado esperado: THROW 50001 "- El jugador que ingresa y el que sale deben ser distintos."
BEGIN TRY
    EXEC Eventos.Sustitucion_Alta @idPartido = @idPartJuego, @idIngresa = @idJB, @idSale = @idJB, @idPeriodo = 2, @minuto = 60, @motivo = 'Tactico';
    PRINT '[FALLO] PRUEBA 4.6: Permitió el mismo jugador en ambos lados.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%deben ser distintos%'
        PRINT '[OK] PRUEBA 4.6: Mismo jugador rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 4.6: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.7: Alta con motivo inválido
-- Resultado esperado: THROW 50001 "- El motivo de la sustitución debe ser Tactico, Lesion o Precaucion."
BEGIN TRY
    EXEC Eventos.Sustitucion_Alta @idPartido = @idPartJuego, @idIngresa = @idJC, @idSale = @idJB, @idPeriodo = 2, @minuto = 60, @motivo = 'Cansancio';
    PRINT '[FALLO] PRUEBA 4.7: Permitió un motivo inválido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%motivo de la sustitución debe ser%'
        PRINT '[OK] PRUEBA 4.7: Motivo inválido rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 4.7: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.8: Alta sin minuto
-- Resultado esperado: THROW 50001 "- El minuto de la sustitución es obligatorio y debe encontrarse entre 0 y 120."
BEGIN TRY
    EXEC Eventos.Sustitucion_Alta @idPartido = @idPartJuego, @idIngresa = @idJC, @idSale = @idJB, @idPeriodo = 2, @minuto = NULL, @motivo = 'Tactico';
    PRINT '[FALLO] PRUEBA 4.8: Permitió una sustitución sin minuto.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%minuto de la sustitución es obligatorio%'
        PRINT '[OK] PRUEBA 4.8: Sustitución sin minuto rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 4.8: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.9: Alta con minuto adicional fuera de un minuto de cierre (60+2)
-- Resultado esperado: THROW 50001 "- El minuto adicional solo es válido en los minutos de cierre reglamentario..."
BEGIN TRY
    EXEC Eventos.Sustitucion_Alta @idPartido = @idPartJuego, @idIngresa = @idJC, @idSale = @idJB, @idPeriodo = 2, @minuto = 60, @minutoAdicional = 2, @motivo = 'Tactico';
    PRINT '[FALLO] PRUEBA 4.9: Permitió minuto adicional en el minuto 60.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%minuto adicional solo es válido%'
        PRINT '[OK] PRUEBA 4.9: Minuto adicional inválido rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 4.9: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.10: Alta en un partido programado
-- Resultado esperado: THROW 50001 "- No se pueden registrar sustituciones en un partido que todavía se encuentra en estado programado."
BEGIN TRY
    EXEC Eventos.Sustitucion_Alta @idPartido = @idPartProg, @idIngresa = @idJC, @idSale = @idJB, @idPeriodo = 2, @minuto = 60, @motivo = 'Tactico';
    PRINT '[FALLO] PRUEBA 4.10: Permitió una sustitución en un partido programado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%No se pueden registrar sustituciones en un partido%programado%'
        PRINT '[OK] PRUEBA 4.10: Sustitución en partido programado rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 4.10: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.11: Alta con un jugador que sale y no está en la formación (Y)
-- Resultado esperado: THROW 50001 "- El jugador que sale debe estar registrado en la formación del partido."
BEGIN TRY
    EXEC Eventos.Sustitucion_Alta @idPartido = @idPartJuego, @idIngresa = @idJC, @idSale = @idJY, @idPeriodo = 2, @minuto = 60, @motivo = 'Tactico';
    PRINT '[FALLO] PRUEBA 4.11: Permitió que salga un jugador fuera de la formación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%jugador que sale debe estar registrado en la formación%'
        PRINT '[OK] PRUEBA 4.11: Jugador que sale fuera de la formación rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 4.11: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.12: Alta con un jugador que ingresa y no está en la formación (Y)
-- Resultado esperado: THROW 50001 "- El jugador que ingresa debe estar registrado en la formación del partido."
BEGIN TRY
    EXEC Eventos.Sustitucion_Alta @idPartido = @idPartJuego, @idIngresa = @idJY, @idSale = @idJB, @idPeriodo = 2, @minuto = 60, @motivo = 'Tactico';
    PRINT '[FALLO] PRUEBA 4.12: Permitió que ingrese un jugador fuera de la formación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%jugador que ingresa debe estar registrado en la formación%'
        PRINT '[OK] PRUEBA 4.12: Jugador que ingresa fuera de la formación rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 4.12: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.13: Alta con jugadores de selecciones distintas (entra X visitante, sale B local)
-- Resultado esperado: THROW 50001 "- Ambos jugadores deben pertenecer a la misma selección en el partido."
BEGIN TRY
    EXEC Eventos.Sustitucion_Alta @idPartido = @idPartJuego, @idIngresa = @idJX, @idSale = @idJB, @idPeriodo = 2, @minuto = 60, @motivo = 'Tactico';
    PRINT '[FALLO] PRUEBA 4.13: Permitió una sustitución entre selecciones distintas.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%Ambos jugadores deben pertenecer a la misma selección%'
        PRINT '[OK] PRUEBA 4.13: Sustitución entre selecciones distintas rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 4.13: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.14: Alta con 3 errores simultáneos (período inexistente, motivo inválido, minuto nulo)
-- Resultado esperado: THROW 50001 con los 3 mensajes juntos.
BEGIN TRY
    EXEC Eventos.Sustitucion_Alta @idPartido = @idPartJuego, @idIngresa = @idJC, @idSale = @idJB, @idPeriodo = 99, @minuto = NULL, @motivo = 'Cansancio';
    PRINT '[FALLO] PRUEBA 4.14: No detectó los errores acumulados.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'%período de juego especificado no existe%'
       AND ERROR_MESSAGE() LIKE N'%motivo de la sustitución debe ser%'
       AND ERROR_MESSAGE() LIKE N'%minuto de la sustitución es obligatorio%'
        PRINT '[OK] PRUEBA 4.14: Acumulación de 3 errores verificada.';
    ELSE PRINT '[FALLO] PRUEBA 4.14: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.15: Modificación de una sustitución inexistente
-- Resultado esperado: THROW 50001 "- El registro de la sustitución a modificar no existe."
BEGIN TRY
    EXEC Eventos.Sustitucion_Modificacion @id = -999, @idPartido = @idPartJuego, @idIngresa = @idJC, @idSale = @idJB, @idPeriodo = 2, @minuto = 60, @motivo = 'Tactico';
    PRINT '[FALLO] PRUEBA 4.15: No detectó la sustitución inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%sustitución a modificar no existe%'
        PRINT '[OK] PRUEBA 4.15: Sustitución inexistente rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 4.15: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.16: Modificación exitosa de la sustitución de 4.1 (motivo Lesion, minuto 65)
-- Resultado esperado: Registro actualizado; evidencia antes/después.
BEGIN TRY
    SELECT 'ANTES 4.16' AS momento, * FROM Eventos.Sustitucion WHERE id = @idSust;
    EXEC Eventos.Sustitucion_Modificacion @id = @idSust, @idPartido = @idPartJuego, @idIngresa = @idJC, @idSale = @idJB, @idPeriodo = 2,
         @minuto = 65, @motivo = 'Lesion';
    SELECT 'DESPUES 4.16' AS momento, * FROM Eventos.Sustitucion WHERE id = @idSust;
    IF EXISTS (SELECT 1 FROM Eventos.Sustitucion WHERE id = @idSust AND minuto = 65 AND motivo = 'Lesion')
        PRINT '[OK] PRUEBA 4.16: Sustitución modificada con éxito.';
    ELSE PRINT '[FALLO] PRUEBA 4.16: El registro no quedó con los valores esperados.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 4.16: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.17: Baja de una sustitución inexistente
-- Resultado esperado: THROW 50001 "- El registro de la sustitución a eliminar no existe."
BEGIN TRY
    EXEC Eventos.Sustitucion_Baja @id = -999;
    PRINT '[FALLO] PRUEBA 4.17: No detectó la sustitución inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%sustitución a eliminar no existe%'
        PRINT '[OK] PRUEBA 4.17: Baja de sustitución inexistente rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 4.17: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.18: Baja exitosa de la sustitución de 4.1
-- Resultado esperado: Registro eliminado; evidencia antes/después.
BEGIN TRY
    SELECT 'ANTES 4.18' AS momento, COUNT(*) AS filas FROM Eventos.Sustitucion WHERE id = @idSust;
    EXEC Eventos.Sustitucion_Baja @id = @idSust;
    SELECT 'DESPUES 4.18' AS momento, COUNT(*) AS filas FROM Eventos.Sustitucion WHERE id = @idSust;
    IF NOT EXISTS (SELECT 1 FROM Eventos.Sustitucion WHERE id = @idSust)
        PRINT '[OK] PRUEBA 4.18: Sustitución eliminada con éxito.';
    ELSE PRINT '[FALLO] PRUEBA 4.18: La sustitución sigue existiendo.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 4.18: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   SECCIÓN 5: Eventos.Suspension   (partido 99802 'Finalizado')
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 5. PRUEBAS: Eventos.Suspension';
PRINT '--------------------------------------------------------------------------------';

DECLARE @idPartFin int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99802);
DECLARE @idJA int = (SELECT id FROM Equipos.Jugador WHERE apellido = N'Jugador Local A');
DECLARE @idStaffL int = (SELECT id FROM Equipos.Staff WHERE apellido = N'Staff Test Local');
DECLARE @idSusp int;

-- PRUEBA 5.1: Alta exitosa de una suspensión de 2 partidos a un jugador
-- Resultado esperado: Inserción correcta con ID generado.
BEGIN TRY
    EXEC Eventos.Suspension_Alta @idPartido = @idPartFin, @idJugador = @idJA, @cantPartidos = 2, @partidosRestantes = 2, @id = @idSusp OUTPUT;
    SELECT 'ALTA 5.1' AS momento, * FROM Eventos.Suspension WHERE id = @idSusp;
    IF @idSusp IS NOT NULL PRINT '[OK] PRUEBA 5.1: Suspensión registrada con ID = ' + CAST(@idSusp AS varchar(10));
    ELSE PRINT '[FALLO] PRUEBA 5.1: No se devolvió el ID generado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 5.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 5.2: Alta con partido inexistente
-- Resultado esperado: THROW 50001 "- El partido especificado no existe."
BEGIN TRY
    EXEC Eventos.Suspension_Alta @idPartido = -999, @idJugador = @idJA, @cantPartidos = 1, @partidosRestantes = 1;
    PRINT '[FALLO] PRUEBA 5.2: No detectó el partido inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%partido especificado no existe%'
        PRINT '[OK] PRUEBA 5.2: Partido inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 5.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 5.3: Alta indicando jugador y cuerpo técnico a la vez
-- Resultado esperado: THROW 50001 "- Debe especificar exactamente a un jugador o a un integrante del cuerpo técnico, no ambos ni ninguno."
BEGIN TRY
    EXEC Eventos.Suspension_Alta @idPartido = @idPartFin, @idJugador = @idJA, @idStaff = @idStaffL, @cantPartidos = 1, @partidosRestantes = 1;
    PRINT '[FALLO] PRUEBA 5.3: Permitió jugador y staff a la vez.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%exactamente a un jugador o a un integrante%'
        PRINT '[OK] PRUEBA 5.3: Jugador y staff a la vez rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 5.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 5.4: Alta con jugador inexistente
-- Resultado esperado: THROW 50001 "- El jugador especificado no existe."
BEGIN TRY
    EXEC Eventos.Suspension_Alta @idPartido = @idPartFin, @idJugador = -999, @cantPartidos = 1, @partidosRestantes = 1;
    PRINT '[FALLO] PRUEBA 5.4: No detectó el jugador inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%jugador especificado no existe%'
        PRINT '[OK] PRUEBA 5.4: Jugador inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 5.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 5.5: Alta con integrante del cuerpo técnico inexistente
-- Resultado esperado: THROW 50001 "- El integrante del cuerpo técnico especificado no existe."
BEGIN TRY
    EXEC Eventos.Suspension_Alta @idPartido = @idPartFin, @idStaff = -999, @cantPartidos = 1, @partidosRestantes = 1;
    PRINT '[FALLO] PRUEBA 5.5: No detectó el staff inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%cuerpo técnico especificado no existe%'
        PRINT '[OK] PRUEBA 5.5: Staff inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 5.5: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 5.6: Alta con cantidad de partidos igual a cero
-- Resultado esperado: THROW 50001 "- La cantidad total de partidos sancionados debe ser mayor a cero."
BEGIN TRY
    EXEC Eventos.Suspension_Alta @idPartido = @idPartFin, @idJugador = @idJA, @cantPartidos = 0, @partidosRestantes = 0;
    PRINT '[FALLO] PRUEBA 5.6: Permitió una sanción de cero partidos.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%debe ser mayor a cero%'
        PRINT '[OK] PRUEBA 5.6: Sanción de cero partidos rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 5.6: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 5.7: Alta con más partidos restantes que el total de la sanción (3 de 2)
-- Resultado esperado: THROW 50001 "- La cantidad de partidos restantes no puede superar el total de partidos de la sanción."
BEGIN TRY
    EXEC Eventos.Suspension_Alta @idPartido = @idPartFin, @idJugador = @idJA, @cantPartidos = 2, @partidosRestantes = 3;
    PRINT '[FALLO] PRUEBA 5.7: Permitió más restantes que el total.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%restantes no puede superar el total%'
        PRINT '[OK] PRUEBA 5.7: Restantes mayores al total rechazados.';
    ELSE PRINT '[FALLO] PRUEBA 5.7: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 5.8: Alta con 3 errores simultáneos (partido inexistente, sin destinatario, cantidad cero)
-- Resultado esperado: THROW 50001 con los 3 mensajes juntos.
BEGIN TRY
    EXEC Eventos.Suspension_Alta @idPartido = -999, @idJugador = NULL, @idStaff = NULL, @cantPartidos = 0, @partidosRestantes = 0;
    PRINT '[FALLO] PRUEBA 5.8: No detectó los errores acumulados.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE '%partido especificado no existe%'
       AND ERROR_MESSAGE() LIKE '%exactamente a un jugador o a un integrante%'
       AND ERROR_MESSAGE() LIKE '%debe ser mayor a cero%'
        PRINT '[OK] PRUEBA 5.8: Acumulación de 3 errores verificada.';
    ELSE PRINT '[FALLO] PRUEBA 5.8: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 5.9: Modificación de una suspensión inexistente
-- Resultado esperado: THROW 50001 "- El registro de suspensión a modificar no existe."
BEGIN TRY
    EXEC Eventos.Suspension_Modificacion @id = -999, @idPartido = @idPartFin, @idJugador = @idJA, @cantPartidos = 1, @partidosRestantes = 1;
    PRINT '[FALLO] PRUEBA 5.9: No detectó la suspensión inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%suspensión a modificar no existe%'
        PRINT '[OK] PRUEBA 5.9: Suspensión inexistente rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 5.9: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 5.10: Modificación exitosa de la suspensión de 5.1 (pasa al cuerpo técnico, 3 partidos, 1 restante)
-- Resultado esperado: Registro actualizado; evidencia antes/después.
BEGIN TRY
    SELECT 'ANTES 5.10' AS momento, * FROM Eventos.Suspension WHERE id = @idSusp;
    EXEC Eventos.Suspension_Modificacion @id = @idSusp, @idPartido = @idPartFin, @idJugador = NULL, @idStaff = @idStaffL,
         @cantPartidos = 3, @partidosRestantes = 1;
    SELECT 'DESPUES 5.10' AS momento, * FROM Eventos.Suspension WHERE id = @idSusp;
    IF EXISTS (SELECT 1 FROM Eventos.Suspension WHERE id = @idSusp AND idStaff = @idStaffL AND idJugador IS NULL AND cantPartidos = 3 AND partidosRestantes = 1)
        PRINT '[OK] PRUEBA 5.10: Suspensión modificada con éxito.';
    ELSE PRINT '[FALLO] PRUEBA 5.10: El registro no quedó con los valores esperados.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 5.10: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 5.11: Baja de una suspensión inexistente
-- Resultado esperado: THROW 50001 "- El registro de suspensión a eliminar no existe."
BEGIN TRY
    EXEC Eventos.Suspension_Baja @id = -999;
    PRINT '[FALLO] PRUEBA 5.11: No detectó la suspensión inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%suspensión a eliminar no existe%'
        PRINT '[OK] PRUEBA 5.11: Baja de suspensión inexistente rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 5.11: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 5.12: Baja exitosa de la suspensión de 5.1
-- Resultado esperado: Registro eliminado; evidencia antes/después.
BEGIN TRY
    SELECT 'ANTES 5.12' AS momento, COUNT(*) AS filas FROM Eventos.Suspension WHERE id = @idSusp;
    EXEC Eventos.Suspension_Baja @id = @idSusp;
    SELECT 'DESPUES 5.12' AS momento, COUNT(*) AS filas FROM Eventos.Suspension WHERE id = @idSusp;
    IF NOT EXISTS (SELECT 1 FROM Eventos.Suspension WHERE id = @idSusp)
        PRINT '[OK] PRUEBA 5.12: Suspensión eliminada con éxito.';
    ELSE PRINT '[FALLO] PRUEBA 5.12: La suspensión sigue existiendo.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 5.12: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   LIMPIEZA FINAL DEL ENTORNO DE PRUEBAS
   ============================================================================= */
PRINT '--- Limpiando fixture auxiliar de pruebas ---';

DELETE FROM Eventos.Gol WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99801, 99802, 99803, 99804));
DELETE FROM Eventos.Tarjeta WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99801, 99802, 99803, 99804));
DELETE FROM Eventos.Sustitucion WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99801, 99802, 99803, 99804));
DELETE FROM Eventos.Suspension WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99801, 99802, 99803, 99804));
DELETE FROM Eventos.FormacionPartido WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99801, 99802, 99803, 99804));
DELETE FROM Torneo.Partido WHERE nroPartidoOficial IN (99801, 99802, 99803, 99804);
DELETE FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test Eventos';
DELETE FROM Torneo.Fase WHERE idFase = 998;
DELETE FROM Equipos.Staff WHERE apellido IN (N'Staff Test Local', N'Staff Test Ajeno');
DELETE FROM Equipos.Jugador WHERE apellido IN (N'Jugador Local A', N'Jugador Local B', N'Jugador Local C', N'Jugador Visitante X', N'Jugador Visitante Y');
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('EVL', 'EVV', 'EVX');
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('L1', 'V1', 'X1');

-- Períodos: solo los que insertó este script (ya no quedan eventos que los referencien)
IF OBJECT_ID('tempdb..#periodosCreados') IS NOT NULL
BEGIN
    DELETE FROM Torneo.Periodo WHERE idPeriodo IN (SELECT idPeriodo FROM #periodosCreados);
    DROP TABLE #periodosCreados;
END;

PRINT 'Fixture de pruebas limpiado con éxito.';
PRINT '================================================================================';
PRINT ' BATERÍA DE PRUEBAS DE EVENTOS FINALIZADA: 91 pruebas';
PRINT '   1. FormacionPartido: 19 | 2. Gol: 22 | 3. Tarjeta: 20 | 4. Sustitucion: 18 | 5. Suspension: 12';
PRINT '================================================================================';
GO
