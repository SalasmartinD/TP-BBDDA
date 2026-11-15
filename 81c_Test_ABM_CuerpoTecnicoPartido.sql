/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel - 45066788
               Salas, Martín Daniel - 45205702
               Zito Padró, Ezequiel Nehuén - 46097917
 Fecha       : 15/11/2026

 Objetivo    : Suite de pruebas unitarias para 11c_ABM_CuerpoTecnicoPartido.sql.
               Cubre el Alta, la Modificación (reemplazo de un integrante por
               otro) y la Baja de Eventos.CuerpoTecnicoPartido.

 Estándares aplicados:
 - Relación 1:1 con 11c_ABM_CuerpoTecnicoPartido.sql.
 - Alta: un caso exitoso con evidencia (SELECT) y una prueba negativa por cada
   mensaje de validación, verificando el código 50001 y el texto del error.
 - Una prueba de acumulación de 3 errores simultáneos.
 - Modificación y Baja: integrante inexistente en el partido, un caso exitoso
   con SELECT antes/después y solo las reglas propias de cada operación
   (identidad, tarjetas registradas, reemplazo Director Principal por Director
   Principal que SÍ se permite).
 - Idempotencia: limpieza preventiva al inicio y final en orden inverso de FK.
   Las tarjetas de staff del fixture se insertan en un partido programado con
   INSERT directo (el SP de tarjetas las rechazaría), igual que las
   formaciones y el cuerpo técnico en 81b.
================================================================================
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

PRINT '================================================================================';
PRINT ' INICIANDO BATERÍA DE PRUEBAS: 11c_ABM_CuerpoTecnicoPartido.sql';
PRINT '================================================================================';
GO

/* =============================================================================
   PREPARACIÓN DEL ENTORNO DE PRUEBAS (FIXTURE AISLADO E IDEMPOTENTE)
   Partidos 99950-99955:
     99950 Finalizado (01/07): suspensión activa de un integrante (pru. 1.7 y 1.9)
     99951 Programado (10/07): Alta/Baja. Cuerpo técnico: Director Principal local
     99952 Finalizado (09/07): integrante suspendido ya figurando (pru. 1.9)
     99953 En juego   (10/07): integrante local figurando (pru. 1.5 y 3.3)
     99954 Programado (11/07): ayudante visitante con tarjeta (pru. 2.4 y 3.4)
     99955 Programado (12/07): Modificación. Cuerpo técnico: ayudante y Director
                               Principal locales + Director Principal visitante
   ============================================================================= */
PRINT '--- Limpieza preventiva de pruebas anteriores ---';

-- Suspension referencia a Tarjeta (FK_Suspension_Tarjeta): se borra antes que Tarjeta
DELETE FROM Eventos.Suspension WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 99950 AND 99955)
                                   OR idStaff IN (SELECT id FROM Equipos.Staff WHERE apellido LIKE N'CT Test%');
DELETE FROM Eventos.Tarjeta WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 99950 AND 99955);
DELETE FROM Eventos.CuerpoTecnicoPartido WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 99950 AND 99955)
                                             OR idStaff IN (SELECT id FROM Equipos.Staff WHERE apellido LIKE N'CT Test%');
DELETE FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 99950 AND 99955;
DELETE FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test CuerpoTec';
DELETE FROM Torneo.Fase WHERE idFase = 997;
DELETE FROM Equipos.Staff WHERE apellido LIKE N'CT Test%';
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('CTL', 'CTV', 'CTX');
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('W1', 'W2', 'W3');
GO

PRINT '--- Creando datos auxiliares de prueba ---';

-- Países y selecciones: local (CTL), visitante (CTV) y una ajena a todos los partidos (CTX)
INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3) VALUES ('Pais CuerpoTec Local', 'W1', 'CTL');
INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3) VALUES ('Pais CuerpoTec Visitante', 'W2', 'CTV');
INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3) VALUES ('Pais CuerpoTec Extra', 'W3', 'CTX');

DECLARE @idPaisL int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'W1');
DECLARE @idPaisV int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'W2');
DECLARE @idPaisX int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'W3');

INSERT INTO Equipos.Seleccion (idPais, abreviacion, confederacion) VALUES (@idPaisL, 'CTL', 'CONMEBOL');
INSERT INTO Equipos.Seleccion (idPais, abreviacion, confederacion) VALUES (@idPaisV, 'CTV', 'UEFA');
INSERT INTO Equipos.Seleccion (idPais, abreviacion, confederacion) VALUES (@idPaisX, 'CTX', 'AFC');

DECLARE @idSelL int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'CTL');
DECLARE @idSelV int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'CTV');
DECLARE @idSelX int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'CTX');

-- Staff: local (2 Directores Principales, 2 ayudantes y un ayudante con suspensión),
-- visitante (Director Principal y ayudante) y uno de la selección ajena
INSERT INTO Equipos.Staff (idSeleccion, nombre, apellido, rol) VALUES (@idSelL, N'Diego',   N'CT Test DirLocal1',   'Director Principal');
INSERT INTO Equipos.Staff (idSeleccion, nombre, apellido, rol) VALUES (@idSelL, N'Marcelo', N'CT Test DirLocal2',   'Director Principal');
INSERT INTO Equipos.Staff (idSeleccion, nombre, apellido, rol) VALUES (@idSelL, N'Walter',  N'CT Test AyuLocal1',   'Ayudante');
INSERT INTO Equipos.Staff (idSeleccion, nombre, apellido, rol) VALUES (@idSelL, N'Pablo',   N'CT Test AyuLocal2',   'Ayudante');
INSERT INTO Equipos.Staff (idSeleccion, nombre, apellido, rol) VALUES (@idSelL, N'Hernan',  N'CT Test Suspendido',  'Ayudante');
INSERT INTO Equipos.Staff (idSeleccion, nombre, apellido, rol) VALUES (@idSelV, N'Didier',  N'CT Test DirVisit',    'Director Principal');
INSERT INTO Equipos.Staff (idSeleccion, nombre, apellido, rol) VALUES (@idSelV, N'Guy',     N'CT Test AyuVisit',    'Ayudante');
INSERT INTO Equipos.Staff (idSeleccion, nombre, apellido, rol) VALUES (@idSelX, N'Ajeno',   N'CT Test Ajeno',       'Ayudante');

-- Fase y sede
INSERT INTO Torneo.Fase (idFase, nombre, esEliminatoria, orden) VALUES (997, 'Fase Test CuerpoTec', 0, 97);
INSERT INTO Torneo.Sede (nombreEstadio, ciudad, idPais, husoHorario) VALUES ('Estadio Test CuerpoTec', 'Ciudad CuerpoTec', @idPaisX, 'UTC');
DECLARE @idSede int = (SELECT idSede FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test CuerpoTec');

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

-- Partidos de prueba (ver cabecera del fixture)
INSERT INTO Torneo.Partido (nroPartidoOficial, idSede, idSeleccionLocal, idSeleccionVisitante, fase, fechaHoraUTC, estado, golLocal, golVisitante)
VALUES (99950, @idSede, @idSelL, @idSelV, 997, '2026-07-01 18:00:00', 'Finalizado', 1, 0);
INSERT INTO Torneo.Partido (nroPartidoOficial, idSede, idSeleccionLocal, idSeleccionVisitante, fase, fechaHoraUTC, estado)
VALUES (99951, @idSede, @idSelL, @idSelV, 997, '2026-07-10 18:00:00', 'Programado');
INSERT INTO Torneo.Partido (nroPartidoOficial, idSede, idSeleccionLocal, idSeleccionVisitante, fase, fechaHoraUTC, estado, golLocal, golVisitante)
VALUES (99952, @idSede, @idSelL, @idSelV, 997, '2026-07-09 18:00:00', 'Finalizado', 2, 1);
INSERT INTO Torneo.Partido (nroPartidoOficial, idSede, idSeleccionLocal, idSeleccionVisitante, fase, fechaHoraUTC, estado)
VALUES (99953, @idSede, @idSelL, @idSelV, 997, '2026-07-10 20:00:00', 'En juego');
INSERT INTO Torneo.Partido (nroPartidoOficial, idSede, idSeleccionLocal, idSeleccionVisitante, fase, fechaHoraUTC, estado)
VALUES (99954, @idSede, @idSelL, @idSelV, 997, '2026-07-11 18:00:00', 'Programado');
INSERT INTO Torneo.Partido (nroPartidoOficial, idSede, idSeleccionLocal, idSeleccionVisitante, fase, fechaHoraUTC, estado)
VALUES (99955, @idSede, @idSelL, @idSelV, 997, '2026-07-12 18:00:00', 'Programado');

DECLARE @idP0 int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99950);
DECLARE @idP1 int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99951);
DECLARE @idP2 int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99952);
DECLARE @idP3 int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99953);
DECLARE @idP4 int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99954);
DECLARE @idP5 int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99955);
DECLARE @idDL1 int = (SELECT id FROM Equipos.Staff WHERE apellido = N'CT Test DirLocal1');
DECLARE @idAL1 int = (SELECT id FROM Equipos.Staff WHERE apellido = N'CT Test AyuLocal1');
DECLARE @idSS  int = (SELECT id FROM Equipos.Staff WHERE apellido = N'CT Test Suspendido');
DECLARE @idDV  int = (SELECT id FROM Equipos.Staff WHERE apellido = N'CT Test DirVisit');
DECLARE @idAV  int = (SELECT id FROM Equipos.Staff WHERE apellido = N'CT Test AyuVisit');

-- Suspensión activa del ayudante suspendido, originada en el partido más antiguo (99950)
INSERT INTO Eventos.Suspension (idPartido, idStaff, cantPartidos, partidosRestantes) VALUES (@idP0, @idSS, 2, 1);

-- Cuerpo técnico cargado con INSERT directo: el SP Alta rechaza partidos finalizados o
-- en juego, pero en la realidad el cuerpo técnico se carga antes del inicio.
INSERT INTO Eventos.CuerpoTecnicoPartido (idPartido, idStaff) VALUES (@idP1, @idDL1);
INSERT INTO Eventos.CuerpoTecnicoPartido (idPartido, idStaff) VALUES (@idP2, @idSS);
INSERT INTO Eventos.CuerpoTecnicoPartido (idPartido, idStaff) VALUES (@idP3, @idAL1);
INSERT INTO Eventos.CuerpoTecnicoPartido (idPartido, idStaff) VALUES (@idP4, @idAV);
INSERT INTO Eventos.CuerpoTecnicoPartido (idPartido, idStaff) VALUES (@idP5, @idAL1);
INSERT INTO Eventos.CuerpoTecnicoPartido (idPartido, idStaff) VALUES (@idP5, @idDL1);
INSERT INTO Eventos.CuerpoTecnicoPartido (idPartido, idStaff) VALUES (@idP5, @idDV);

-- Tarjeta de staff en el partido 99954 (el ayudante visitante ya fue amonestado)
INSERT INTO Eventos.Tarjeta (idPartido, idStaff, idPeriodo, color, minuto, motivo) VALUES (@idP4, @idAV, 1, 'A', 30, 'Protestas');

PRINT 'Fixture de pruebas inicializado con éxito.';
PRINT '';
GO

/* =============================================================================
   SECCIÓN 1: Eventos.CuerpoTecnicoPartido_Alta
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 1. PRUEBAS: Eventos.CuerpoTecnicoPartido_Alta';
PRINT '--------------------------------------------------------------------------------';

DECLARE @idP1 int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99951);
DECLARE @idP2 int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99952);
DECLARE @idP3 int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99953);
DECLARE @idDL2 int = (SELECT id FROM Equipos.Staff WHERE apellido = N'CT Test DirLocal2');
DECLARE @idAL1 int = (SELECT id FROM Equipos.Staff WHERE apellido = N'CT Test AyuLocal1');
DECLARE @idAL2 int = (SELECT id FROM Equipos.Staff WHERE apellido = N'CT Test AyuLocal2');
DECLARE @idSS  int = (SELECT id FROM Equipos.Staff WHERE apellido = N'CT Test Suspendido');
DECLARE @idAJ  int = (SELECT id FROM Equipos.Staff WHERE apellido = N'CT Test Ajeno');

-- PRUEBA 1.1: Alta exitosa de un ayudante local en el partido programado 99951
-- Resultado esperado: Fila insertada en Eventos.CuerpoTecnicoPartido.
BEGIN TRY
    SELECT 'ANTES 1.1' AS momento, COUNT(*) AS integrantes FROM Eventos.CuerpoTecnicoPartido WHERE idPartido = @idP1;
    EXEC Eventos.CuerpoTecnicoPartido_Alta @idPartido = @idP1, @idStaff = @idAL1;
    SELECT 'DESPUES 1.1' AS momento, c.idPartido, c.idStaff, s.apellido, s.rol
    FROM Eventos.CuerpoTecnicoPartido c JOIN Equipos.Staff s ON s.id = c.idStaff
    WHERE c.idPartido = @idP1 ORDER BY s.apellido;
    IF EXISTS (SELECT 1 FROM Eventos.CuerpoTecnicoPartido WHERE idPartido = @idP1 AND idStaff = @idAL1)
        PRINT '[OK] PRUEBA 1.1: Integrante agregado al cuerpo técnico del partido.';
    ELSE PRINT '[FALLO] PRUEBA 1.1: La fila no quedó registrada.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.2: Alta con partido inexistente
-- Resultado esperado: THROW 50001 "No se pudo registrar el integrante en el cuerpo técnico del partido:" + "- El partido especificado no existe."
BEGIN TRY
    EXEC Eventos.CuerpoTecnicoPartido_Alta @idPartido = -999, @idStaff = @idAL2;
    PRINT '[FALLO] PRUEBA 1.2: No detectó el partido inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'No se pudo registrar el integrante en el cuerpo técnico del partido:%'
       AND ERROR_MESSAGE() LIKE N'%- El partido especificado no existe.%'
        PRINT '[OK] PRUEBA 1.2: Partido inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 1.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.3: Alta con integrante del cuerpo técnico inexistente
-- Resultado esperado: THROW 50001 "- El integrante del cuerpo técnico especificado no existe."
BEGIN TRY
    EXEC Eventos.CuerpoTecnicoPartido_Alta @idPartido = @idP1, @idStaff = -999;
    PRINT '[FALLO] PRUEBA 1.3: No detectó el integrante inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%- El integrante del cuerpo técnico especificado no existe.%'
        PRINT '[OK] PRUEBA 1.3: Integrante inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 1.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.4: Alta de un integrante de una selección que no disputa el partido
-- Resultado esperado: THROW 50001 "- El integrante del cuerpo técnico no pertenece a ninguna de las selecciones que disputan el partido."
BEGIN TRY
    EXEC Eventos.CuerpoTecnicoPartido_Alta @idPartido = @idP1, @idStaff = @idAJ;
    PRINT '[FALLO] PRUEBA 1.4: Permitió un integrante de una selección ajena al partido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'%- El integrante del cuerpo técnico no pertenece a ninguna de las selecciones que disputan el partido.%'
        PRINT '[OK] PRUEBA 1.4: Integrante de selección ajena rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 1.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.5: Alta en un partido en juego (el partido finalizado usa la misma regla)
-- Resultado esperado: THROW 50001 "- No se pueden agregar integrantes al cuerpo técnico de un partido ya finalizado o que se encuentra en juego."
BEGIN TRY
    EXEC Eventos.CuerpoTecnicoPartido_Alta @idPartido = @idP3, @idStaff = @idAL2;
    PRINT '[FALLO] PRUEBA 1.5: Permitió el alta en un partido en juego.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'%- No se pueden agregar integrantes al cuerpo técnico de un partido ya finalizado o que se encuentra en juego.%'
        PRINT '[OK] PRUEBA 1.5: Alta en partido en juego rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 1.5: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.6: Alta de un integrante que ya figura en el partido (AyuLocal1, cargado en 1.1)
-- Resultado esperado: THROW 50001 "- El integrante ya figura en el cuerpo técnico de este partido."
BEGIN TRY
    EXEC Eventos.CuerpoTecnicoPartido_Alta @idPartido = @idP1, @idStaff = @idAL1;
    PRINT '[FALLO] PRUEBA 1.6: Permitió un integrante duplicado en el partido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%- El integrante ya figura en el cuerpo técnico de este partido.%'
        PRINT '[OK] PRUEBA 1.6: Integrante duplicado rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 1.6: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.7: Alta de un integrante con suspensión activa (generada en el partido 99950, anterior al 99951)
-- Resultado esperado: THROW 50001 "- El integrante del cuerpo técnico está suspendido y no puede figurar en el partido."
BEGIN TRY
    EXEC Eventos.CuerpoTecnicoPartido_Alta @idPartido = @idP1, @idStaff = @idSS;
    PRINT '[FALLO] PRUEBA 1.7: Permitió agregar a un integrante suspendido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'%- El integrante del cuerpo técnico está suspendido y no puede figurar en el partido.%'
        PRINT '[OK] PRUEBA 1.7: Integrante suspendido rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 1.7: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.8: Alta de un segundo Director Principal de la misma selección (el partido 99951 ya tiene a DirLocal1)
-- Resultado esperado: THROW 50001 "- La selección ya tiene otro director principal en el cuerpo técnico de este partido."
BEGIN TRY
    EXEC Eventos.CuerpoTecnicoPartido_Alta @idPartido = @idP1, @idStaff = @idDL2;
    PRINT '[FALLO] PRUEBA 1.8: Permitió un segundo Director Principal de la misma selección.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'%- La selección ya tiene otro director principal en el cuerpo técnico de este partido.%'
        PRINT '[OK] PRUEBA 1.8: Segundo Director Principal rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 1.8: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.9: Alta con 3 errores simultáneos (partido finalizado, integrante que ya figura y está suspendido)
-- Resultado esperado: THROW 50001 con los 3 mensajes juntos.
BEGIN TRY
    EXEC Eventos.CuerpoTecnicoPartido_Alta @idPartido = @idP2, @idStaff = @idSS;
    PRINT '[FALLO] PRUEBA 1.9: No detectó los errores acumulados.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'%- No se pueden agregar integrantes al cuerpo técnico de un partido ya finalizado o que se encuentra en juego.%'
       AND ERROR_MESSAGE() LIKE N'%- El integrante ya figura en el cuerpo técnico de este partido.%'
       AND ERROR_MESSAGE() LIKE N'%- El integrante del cuerpo técnico está suspendido y no puede figurar en el partido.%'
        PRINT '[OK] PRUEBA 1.9: Acumulación de 3 errores verificada.';
    ELSE PRINT '[FALLO] PRUEBA 1.9: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   SECCIÓN 2: Eventos.CuerpoTecnicoPartido_Modificacion
   (partido 99955 Programado: AyuLocal1, DirLocal1 y DirVisit; 99954: AyuVisit con tarjeta)
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 2. PRUEBAS: Eventos.CuerpoTecnicoPartido_Modificacion';
PRINT '--------------------------------------------------------------------------------';

DECLARE @idP3 int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99953);
DECLARE @idP4 int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99954);
DECLARE @idP5 int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99955);
DECLARE @idDL1 int = (SELECT id FROM Equipos.Staff WHERE apellido = N'CT Test DirLocal1');
DECLARE @idDL2 int = (SELECT id FROM Equipos.Staff WHERE apellido = N'CT Test DirLocal2');
DECLARE @idAL1 int = (SELECT id FROM Equipos.Staff WHERE apellido = N'CT Test AyuLocal1');
DECLARE @idAL2 int = (SELECT id FROM Equipos.Staff WHERE apellido = N'CT Test AyuLocal2');
DECLARE @idDV  int = (SELECT id FROM Equipos.Staff WHERE apellido = N'CT Test DirVisit');
DECLARE @idAV  int = (SELECT id FROM Equipos.Staff WHERE apellido = N'CT Test AyuVisit');
DECLARE @idAJ  int = (SELECT id FROM Equipos.Staff WHERE apellido = N'CT Test Ajeno');

-- PRUEBA 2.1: Reemplazo exitoso de AyuLocal1 por AyuLocal2 en el partido 99955
-- Resultado esperado: AyuLocal2 figura en el partido y AyuLocal1 ya no; evidencia antes/después.
BEGIN TRY
    SELECT 'ANTES 2.1' AS momento, s.apellido, s.rol
    FROM Eventos.CuerpoTecnicoPartido c JOIN Equipos.Staff s ON s.id = c.idStaff
    WHERE c.idPartido = @idP5 ORDER BY s.apellido;
    EXEC Eventos.CuerpoTecnicoPartido_Modificacion @idPartido = @idP5, @idStaffActual = @idAL1, @idStaffNuevo = @idAL2;
    SELECT 'DESPUES 2.1' AS momento, s.apellido, s.rol
    FROM Eventos.CuerpoTecnicoPartido c JOIN Equipos.Staff s ON s.id = c.idStaff
    WHERE c.idPartido = @idP5 ORDER BY s.apellido;
    IF EXISTS (SELECT 1 FROM Eventos.CuerpoTecnicoPartido WHERE idPartido = @idP5 AND idStaff = @idAL2)
       AND NOT EXISTS (SELECT 1 FROM Eventos.CuerpoTecnicoPartido WHERE idPartido = @idP5 AND idStaff = @idAL1)
        PRINT '[OK] PRUEBA 2.1: Integrante reemplazado con éxito.';
    ELSE PRINT '[FALLO] PRUEBA 2.1: El cuerpo técnico no quedó con los valores esperados.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.2: Reemplazo de un integrante actual que no figura en el partido (AJ no está en el 99955)
-- Resultado esperado: THROW 50001 "No se pudo modificar el cuerpo técnico del partido:" + "- El integrante actual no figura en el cuerpo técnico de este partido."
BEGIN TRY
    EXEC Eventos.CuerpoTecnicoPartido_Modificacion @idPartido = @idP5, @idStaffActual = @idAJ, @idStaffNuevo = @idAV;
    PRINT '[FALLO] PRUEBA 2.2: No detectó que el integrante actual no figura.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'No se pudo modificar el cuerpo técnico del partido:%'
       AND ERROR_MESSAGE() LIKE N'%- El integrante actual no figura en el cuerpo técnico de este partido.%'
        PRINT '[OK] PRUEBA 2.2: Integrante actual que no figura rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.3: Reemplazo de un integrante por sí mismo (DirVisit figura en el 99955)
-- Resultado esperado: THROW 50001 "- El nuevo integrante no puede ser idéntico al actual."
BEGIN TRY
    EXEC Eventos.CuerpoTecnicoPartido_Modificacion @idPartido = @idP5, @idStaffActual = @idDV, @idStaffNuevo = @idDV;
    PRINT '[FALLO] PRUEBA 2.3: Permitió reemplazar a un integrante por sí mismo.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%- El nuevo integrante no puede ser idéntico al actual.%'
        PRINT '[OK] PRUEBA 2.3: Reemplazo por el mismo integrante rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.4: Reemplazo de un integrante que registra tarjetas en el partido (AyuVisit tiene una amarilla en el 99954)
-- Resultado esperado: THROW 50001 "- No se puede reemplazar al integrante actual porque registra tarjetas en este partido."
BEGIN TRY
    EXEC Eventos.CuerpoTecnicoPartido_Modificacion @idPartido = @idP4, @idStaffActual = @idAV, @idStaffNuevo = @idAL1;
    PRINT '[FALLO] PRUEBA 2.4: Permitió reemplazar a un integrante con tarjetas.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'%- No se puede reemplazar al integrante actual porque registra tarjetas en este partido.%'
        PRINT '[OK] PRUEBA 2.4: Reemplazo de integrante con tarjetas rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.5: Reemplazo de un Director Principal por otro Director Principal de la misma selección (DirLocal1 por DirLocal2)
-- Resultado esperado: Reemplazo PERMITIDO (el actual se excluye de la regla de un solo Director Principal); evidencia antes/después.
BEGIN TRY
    SELECT 'ANTES 2.5' AS momento, s.apellido, s.rol
    FROM Eventos.CuerpoTecnicoPartido c JOIN Equipos.Staff s ON s.id = c.idStaff
    WHERE c.idPartido = @idP5 ORDER BY s.apellido;
    EXEC Eventos.CuerpoTecnicoPartido_Modificacion @idPartido = @idP5, @idStaffActual = @idDL1, @idStaffNuevo = @idDL2;
    SELECT 'DESPUES 2.5' AS momento, s.apellido, s.rol
    FROM Eventos.CuerpoTecnicoPartido c JOIN Equipos.Staff s ON s.id = c.idStaff
    WHERE c.idPartido = @idP5 ORDER BY s.apellido;
    IF EXISTS (SELECT 1 FROM Eventos.CuerpoTecnicoPartido WHERE idPartido = @idP5 AND idStaff = @idDL2)
       AND NOT EXISTS (SELECT 1 FROM Eventos.CuerpoTecnicoPartido WHERE idPartido = @idP5 AND idStaff = @idDL1)
        PRINT '[OK] PRUEBA 2.5: Director Principal reemplazado por otro Director Principal.';
    ELSE PRINT '[FALLO] PRUEBA 2.5: El cuerpo técnico no quedó con los valores esperados.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.5: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.6: Reemplazo en un partido en juego (AyuLocal1 figura en el 99953; AyuLocal2 es un reemplazo válido)
-- Resultado esperado: THROW 50001 "- No se puede modificar el cuerpo técnico de un partido ya finalizado o que se encuentra en juego."
BEGIN TRY
    EXEC Eventos.CuerpoTecnicoPartido_Modificacion @idPartido = @idP3, @idStaffActual = @idAL1, @idStaffNuevo = @idAL2;
    PRINT '[FALLO] PRUEBA 2.6: Permitió modificar el cuerpo técnico de un partido en juego.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'%- No se puede modificar el cuerpo técnico de un partido ya finalizado o que se encuentra en juego.%'
        PRINT '[OK] PRUEBA 2.6: Modificación en partido en juego rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 2.6: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   SECCIÓN 3: Eventos.CuerpoTecnicoPartido_Baja
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 3. PRUEBAS: Eventos.CuerpoTecnicoPartido_Baja';
PRINT '--------------------------------------------------------------------------------';

DECLARE @idP1 int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99951);
DECLARE @idP3 int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99953);
DECLARE @idP4 int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99954);
DECLARE @idP5 int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99955);
DECLARE @idAL1 int = (SELECT id FROM Equipos.Staff WHERE apellido = N'CT Test AyuLocal1');
DECLARE @idAV  int = (SELECT id FROM Equipos.Staff WHERE apellido = N'CT Test AyuVisit');

-- PRUEBA 3.1: Baja de un integrante que no figura en el partido (AyuVisit no está en el 99955)
-- Resultado esperado: THROW 50001 "No se pudo dar de baja al integrante del cuerpo técnico del partido:" + "- El integrante no figura en el cuerpo técnico de este partido."
BEGIN TRY
    EXEC Eventos.CuerpoTecnicoPartido_Baja @idPartido = @idP5, @idStaff = @idAV;
    PRINT '[FALLO] PRUEBA 3.1: No detectó que el integrante no figura.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'No se pudo dar de baja al integrante del cuerpo técnico del partido:%'
       AND ERROR_MESSAGE() LIKE N'%- El integrante no figura en el cuerpo técnico de este partido.%'
        PRINT '[OK] PRUEBA 3.1: Baja de integrante que no figura rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 3.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.2: Baja exitosa de AyuLocal1 del partido 99951 (cargado en la prueba 1.1)
-- Resultado esperado: Fila eliminada; evidencia antes/después.
BEGIN TRY
    SELECT 'ANTES 3.2' AS momento, COUNT(*) AS filas FROM Eventos.CuerpoTecnicoPartido WHERE idPartido = @idP1 AND idStaff = @idAL1;
    EXEC Eventos.CuerpoTecnicoPartido_Baja @idPartido = @idP1, @idStaff = @idAL1;
    SELECT 'DESPUES 3.2' AS momento, COUNT(*) AS filas FROM Eventos.CuerpoTecnicoPartido WHERE idPartido = @idP1 AND idStaff = @idAL1;
    IF NOT EXISTS (SELECT 1 FROM Eventos.CuerpoTecnicoPartido WHERE idPartido = @idP1 AND idStaff = @idAL1)
        PRINT '[OK] PRUEBA 3.2: Integrante dado de baja con éxito.';
    ELSE PRINT '[FALLO] PRUEBA 3.2: El integrante sigue figurando en el partido.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 3.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.3: Baja de un integrante en un partido en juego (AyuLocal1 figura en el 99953)
-- Resultado esperado: THROW 50001 "- No se puede eliminar a un integrante del cuerpo técnico de un partido ya finalizado o en juego."
BEGIN TRY
    EXEC Eventos.CuerpoTecnicoPartido_Baja @idPartido = @idP3, @idStaff = @idAL1;
    PRINT '[FALLO] PRUEBA 3.3: Permitió la baja en un partido en juego.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'%- No se puede eliminar a un integrante del cuerpo técnico de un partido ya finalizado o en juego.%'
        PRINT '[OK] PRUEBA 3.3: Baja en partido en juego rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 3.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.4: Baja de un integrante que registra tarjetas en el partido (AyuVisit tiene una amarilla en el 99954)
-- Resultado esperado: THROW 50001 "- No se puede eliminar al integrante del cuerpo técnico porque registra tarjetas en este partido."
BEGIN TRY
    EXEC Eventos.CuerpoTecnicoPartido_Baja @idPartido = @idP4, @idStaff = @idAV;
    PRINT '[FALLO] PRUEBA 3.4: Permitió la baja de un integrante con tarjetas.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'%- No se puede eliminar al integrante del cuerpo técnico porque registra tarjetas en este partido.%'
        PRINT '[OK] PRUEBA 3.4: Baja de integrante con tarjetas rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 3.4: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   LIMPIEZA FINAL DEL ENTORNO DE PRUEBAS
   ============================================================================= */
PRINT '--- Limpiando fixture auxiliar de pruebas ---';

-- Suspension referencia a Tarjeta (FK_Suspension_Tarjeta): se borra antes que Tarjeta
DELETE FROM Eventos.Suspension WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 99950 AND 99955)
                                   OR idStaff IN (SELECT id FROM Equipos.Staff WHERE apellido LIKE N'CT Test%');
DELETE FROM Eventos.Tarjeta WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 99950 AND 99955);
DELETE FROM Eventos.CuerpoTecnicoPartido WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 99950 AND 99955)
                                             OR idStaff IN (SELECT id FROM Equipos.Staff WHERE apellido LIKE N'CT Test%');
DELETE FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 99950 AND 99955;
DELETE FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test CuerpoTec';
DELETE FROM Torneo.Fase WHERE idFase = 997;
DELETE FROM Equipos.Staff WHERE apellido LIKE N'CT Test%';
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('CTL', 'CTV', 'CTX');
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('W1', 'W2', 'W3');

-- Período: solo si lo insertó este script (ya no quedan tarjetas que lo referencien)
IF OBJECT_ID('tempdb..#periodosCreados') IS NOT NULL
BEGIN
    DELETE FROM Torneo.Periodo WHERE idPeriodo IN (SELECT idPeriodo FROM #periodosCreados);
    DROP TABLE #periodosCreados;
END;

PRINT 'Fixture de pruebas limpiado con éxito.';
PRINT '================================================================================';
PRINT ' BATERÍA DE PRUEBAS DE CUERPO TÉCNICO FINALIZADA: 19 pruebas';
PRINT '   1. Alta: 9 | 2. Modificación: 6 | 3. Baja: 4';
PRINT '================================================================================';
GO
