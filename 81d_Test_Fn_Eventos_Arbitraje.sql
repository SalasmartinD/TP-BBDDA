/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel - 45066788
               Salas, Martín Daniel - 45205702
               Zito Padró, Ezequiel Nehuén - 46097917
 Fecha       : 09/11/2026

 Objetivo    : Suite de pruebas unitarias para 31_Fn_Eventos_Arbitraje.sql.
               Cubre:
               - Eventos.fn_EquipoEnCancha
               - Eventos.vw_HistorialTitularidad
               - Arbitraje.vw_HistorialArbitro

 Estándares aplicados:
 - Relación 1:1 con 31_Fn_Eventos_Arbitraje.sql.
 - Un partido de prueba con formación, un cambio, tarjetas, árbitros e
   informes conocidos; cada prueba compara el resultado de la función o la
   vista con los valores esperados y muestra la evidencia con SELECT.
 - Idempotencia: limpieza preventiva al inicio y final en orden inverso de FK;
   los períodos que crea el fixture se registran y se borran al terminar.
================================================================================
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

PRINT '================================================================================';
PRINT ' INICIANDO BATERÍA DE PRUEBAS: 31_Fn_Eventos_Arbitraje.sql';
PRINT '================================================================================';
GO

/* =============================================================================
   PREPARACIÓN DEL ENTORNO DE PRUEBAS (FIXTURE AISLADO E IDEMPOTENTE)
   Códigos reservados: países R1-R3, selecciones QDA/QDB, partido 99601,
   fase 9911, jugadores 'QFn Jugador %', árbitros 'QFn Arbitro %'.
   ============================================================================= */
PRINT '--- Limpieza preventiva de pruebas anteriores ---';

DELETE FROM Arbitraje.InformeArbitral WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99601);
DELETE FROM Arbitraje.cuerpoArbitral  WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99601);
DELETE FROM Eventos.Gol               WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99601);
DELETE FROM Eventos.Tarjeta           WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99601);
DELETE FROM Eventos.Sustitucion       WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99601);
DELETE FROM Eventos.Suspension        WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99601);
DELETE FROM Eventos.FormacionPartido  WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99601);
DELETE FROM Torneo.Partido WHERE nroPartidoOficial = 99601;
DELETE FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test Funciones';
DELETE FROM Torneo.Fase WHERE idFase = 9911;
DELETE FROM Arbitraje.Arbitro WHERE apellido LIKE N'QFn Arbitro %';
DELETE FROM Equipos.ListadoJugadores WHERE idJugador IN (SELECT id FROM Equipos.Jugador WHERE apellido LIKE N'QFn Jugador %');
DELETE FROM Equipos.Jugador WHERE apellido LIKE N'QFn Jugador %';
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('QDA', 'QDB');
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('R1', 'R2', 'R3');
GO

PRINT '--- Creando datos auxiliares de prueba ---';

-- Períodos 1 y 2: se crean solo si faltan y se registran en #periodosCreados
IF OBJECT_ID('tempdb..#periodosCreados') IS NOT NULL DROP TABLE #periodosCreados;
CREATE TABLE #periodosCreados (idPeriodo tinyint PRIMARY KEY);

INSERT INTO Torneo.Periodo (idPeriodo, nombre, orden)
OUTPUT inserted.idPeriodo INTO #periodosCreados (idPeriodo)
SELECT v.idPeriodo, v.nombre, v.orden
FROM (VALUES (1, 'Primer Tiempo', 1), (2, 'Segundo Tiempo', 2)) v (idPeriodo, nombre, orden)
WHERE NOT EXISTS (SELECT 1 FROM Torneo.Periodo p WHERE p.idPeriodo = v.idPeriodo);

-- Países y selecciones: A (local), B (visitante) y un país neutral (sede y árbitros)
INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3)
VALUES (N'Pais Funciones A', 'R1', 'QDA'),
       (N'Pais Funciones B', 'R2', 'QDB'),
       (N'Pais Funciones Neutral', 'R3', 'QDN');

INSERT INTO Equipos.Seleccion (idPais, abreviacion, confederacion)
SELECT id, codigoISO3, 'CONMEBOL'
FROM Torneo.Pais
WHERE codigoISO2 IN ('R1', 'R2');

-- Jugadores A01-A12 y B01-B12, convocados con dorsal = número + 10
IF OBJECT_ID('tempdb..#jug') IS NOT NULL DROP TABLE #jug;
CREATE TABLE #jug (
    codigo    char(3)      PRIMARY KEY,
    sel       char(1)      NOT NULL,
    nro       tinyint      NOT NULL,
    posicion  varchar(15)  NOT NULL,
    id        int          NULL
);

INSERT INTO #jug (codigo, sel, nro, posicion)
SELECT s.sel + RIGHT('0' + CAST(n.nro AS varchar(2)), 2), s.sel, n.nro,
       CASE WHEN n.nro IN (1, 12) THEN 'Arquero'
            WHEN n.nro <= 5 THEN 'Defensor'
            WHEN n.nro <= 8 THEN 'Mediocampista'
            ELSE 'Delantero' END
FROM (VALUES ('A'), ('B')) s (sel)
CROSS JOIN (VALUES (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12)) n (nro);

INSERT INTO Equipos.Jugador (nombre, apellido, posicion)
SELECT N'Jugador', N'QFn Jugador ' + codigo, posicion
FROM #jug;

UPDATE j SET id = ej.id
FROM #jug j
JOIN Equipos.Jugador ej ON ej.apellido = N'QFn Jugador ' + j.codigo;

INSERT INTO Equipos.ListadoJugadores (idSeleccion, idJugador, fechaAlta, dorsal)
SELECT s.id, j.id, '2026-05-01', j.nro + 10
FROM #jug j
JOIN Equipos.Seleccion s ON s.abreviacion = 'QD' + j.sel;

-- Fase, sede y partido finalizado A 2 - B 1
INSERT INTO Torneo.Fase (idFase, nombre, esEliminatoria, orden) VALUES (9911, 'Fase Test Funciones', 0, 1);

INSERT INTO Torneo.Sede (nombreEstadio, ciudad, idPais, husoHorario)
SELECT 'Estadio Test Funciones', 'Ciudad Funciones', id, 'UTC'
FROM Torneo.Pais WHERE codigoISO2 = 'R3';

INSERT INTO Torneo.Partido (nroPartidoOficial, idSede, idSeleccionLocal, idSeleccionVisitante, fase, fechaHoraUTC, estado, golLocal, golVisitante)
SELECT 99601, sd.idSede, sa.id, sb.id, 9911, '2026-07-02 18:00:00', 'Finalizado', 2, 1
FROM Torneo.Sede sd
JOIN Equipos.Seleccion sa ON sa.abreviacion = 'QDA'
JOIN Equipos.Seleccion sb ON sb.abreviacion = 'QDB'
WHERE sd.nombreEstadio = 'Estadio Test Funciones';

DECLARE @idPart int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99601);

-- Formación: 01-11 titulares y 12 suplente en cada selección
INSERT INTO Eventos.FormacionPartido (idPartido, idSeleccion, idJugador, titular, posicion)
SELECT @idPart, s.id, j.id, CASE WHEN j.nro <= 11 THEN 1 ELSE 0 END, j.posicion
FROM #jug j
JOIN Equipos.Seleccion s ON s.abreviacion = 'QD' + j.sel;

-- Incidencias: cambio al 30 (sale A05, entra A12), amarillas a A03 (20) y
-- B02 (40), roja directa a B07 (50)
INSERT INTO Eventos.Sustitucion (idPartido, idIngresa, idSale, idPeriodo, minuto, motivo)
VALUES (@idPart, (SELECT id FROM #jug WHERE codigo = 'A12'), (SELECT id FROM #jug WHERE codigo = 'A05'), 1, 30, 'Tactico');

INSERT INTO Eventos.Tarjeta (idPartido, idJugador, idPeriodo, color, minuto, motivo, tipoRoja)
VALUES (@idPart, (SELECT id FROM #jug WHERE codigo = 'A03'), 1, 'A', 20, 'Juego brusco', NULL),
       (@idPart, (SELECT id FROM #jug WHERE codigo = 'B02'), 1, 'A', 40, 'Protestar', NULL),
       (@idPart, (SELECT id FROM #jug WHERE codigo = 'B07'), 2, 'R', 50, 'Conducta violenta', 'Directa');

-- Árbitros: Uno (Principal, con 2 informes y 1 sanción) y Dos (Asistente 1, sin informes)
INSERT INTO Arbitraje.Arbitro (idPais, nombre, apellido, categoria)
SELECT p.id, v.nombre, v.apellido, 'FIFA'
FROM (VALUES (N'Neutral', N'QFn Arbitro Uno'), (N'Neutral', N'QFn Arbitro Dos')) v (nombre, apellido)
CROSS JOIN Torneo.Pais p
WHERE p.codigoISO2 = 'R3';

DECLARE @idArbUno int = (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'QFn Arbitro Uno');
DECLARE @idArbDos int = (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'QFn Arbitro Dos');

INSERT INTO Arbitraje.cuerpoArbitral (idArbitro, idPartido, rol)
VALUES (@idArbUno, @idPart, 'Principal'),
       (@idArbDos, @idPart, 'Asistente 1');

INSERT INTO Arbitraje.InformeArbitral (idPartido, idArbitro, fecha, esSancion, detalle)
VALUES (@idPart, @idArbUno, '2026-07-03', 0, N'Informe uno'),
       (@idPart, @idArbUno, '2026-07-04', 0, N'Informe dos'),
       (@idPart, @idArbUno, '2026-07-05', 1, N'Sancion por error grave');

PRINT 'Fixture de pruebas inicializado con éxito.';
PRINT '';
GO

/* =============================================================================
   SECCIÓN 1: Eventos.fn_EquipoEnCancha
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 1. PRUEBAS: Eventos.fn_EquipoEnCancha';
PRINT '--------------------------------------------------------------------------------';

DECLARE @idPart int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99601);
DECLARE @idSelA int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'QDA');
DECLARE @idSelB int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'QDB');
DECLARE @idA05 int = (SELECT id FROM #jug WHERE codigo = 'A05');
DECLARE @idA12 int = (SELECT id FROM #jug WHERE codigo = 'A12');
DECLARE @idB07 int = (SELECT id FROM #jug WHERE codigo = 'B07');

-- PRUEBA 1.1: Minuto 0 - los 22 titulares en cancha
-- Resultado esperado: 22 filas (11 por selección); A05 con dorsal 15, selección 'Pais Funciones A', titular y sin minutoIngreso.
BEGIN TRY
    SELECT 'MINUTO 0' AS momento, * FROM Eventos.fn_EquipoEnCancha(@idPart, 0) ORDER BY idSeleccion, dorsal;
    IF (SELECT COUNT(*) FROM Eventos.fn_EquipoEnCancha(@idPart, 0)) = 22
       AND (SELECT COUNT(*) FROM Eventos.fn_EquipoEnCancha(@idPart, 0) WHERE idSeleccion = @idSelA) = 11
       AND EXISTS (SELECT 1 FROM Eventos.fn_EquipoEnCancha(@idPart, 0)
                   WHERE idJugador = @idA05 AND dorsal = 15 AND seleccion = N'Pais Funciones A'
                     AND esTitular = 1 AND minutoIngreso IS NULL)
        PRINT '[OK] PRUEBA 1.1: 22 titulares en cancha al minuto 0.';
    ELSE PRINT '[FALLO] PRUEBA 1.1: El equipo en cancha al minuto 0 no es el esperado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.2: Minuto 29 - todavía no se hizo el cambio del 30
-- Resultado esperado: 22 filas; A05 en cancha y A12 no.
BEGIN TRY
    IF (SELECT COUNT(*) FROM Eventos.fn_EquipoEnCancha(@idPart, 29)) = 22
       AND EXISTS (SELECT 1 FROM Eventos.fn_EquipoEnCancha(@idPart, 29) WHERE idJugador = @idA05)
       AND NOT EXISTS (SELECT 1 FROM Eventos.fn_EquipoEnCancha(@idPart, 29) WHERE idJugador = @idA12)
        PRINT '[OK] PRUEBA 1.2: Al minuto 29 sigue A05 y A12 está en el banco.';
    ELSE PRINT '[FALLO] PRUEBA 1.2: El equipo en cancha al minuto 29 no es el esperado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.3: Minuto 30 - cambio realizado (sale A05, entra A12)
-- Resultado esperado: 22 filas; A05 fuera y A12 en cancha como suplente con minutoIngreso = 30.
BEGIN TRY
    SELECT 'MINUTO 30' AS momento, * FROM Eventos.fn_EquipoEnCancha(@idPart, 30) WHERE idSeleccion = @idSelA ORDER BY dorsal;
    IF (SELECT COUNT(*) FROM Eventos.fn_EquipoEnCancha(@idPart, 30)) = 22
       AND NOT EXISTS (SELECT 1 FROM Eventos.fn_EquipoEnCancha(@idPart, 30) WHERE idJugador = @idA05)
       AND EXISTS (SELECT 1 FROM Eventos.fn_EquipoEnCancha(@idPart, 30)
                   WHERE idJugador = @idA12 AND esTitular = 0 AND minutoIngreso = 30)
        PRINT '[OK] PRUEBA 1.3: Al minuto 30 A12 reemplaza a A05 (minutoIngreso = 30).';
    ELSE PRINT '[FALLO] PRUEBA 1.3: El equipo en cancha al minuto 30 no es el esperado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.4: Minuto 60 - después de la roja a B07 (minuto 50)
-- Resultado esperado: 21 filas; B queda con 10 jugadores y B07 no figura.
BEGIN TRY
    SELECT 'MINUTO 60' AS momento, idSeleccion, COUNT(*) AS enCancha FROM Eventos.fn_EquipoEnCancha(@idPart, 60) GROUP BY idSeleccion;
    IF (SELECT COUNT(*) FROM Eventos.fn_EquipoEnCancha(@idPart, 60)) = 21
       AND (SELECT COUNT(*) FROM Eventos.fn_EquipoEnCancha(@idPart, 60) WHERE idSeleccion = @idSelB) = 10
       AND NOT EXISTS (SELECT 1 FROM Eventos.fn_EquipoEnCancha(@idPart, 60) WHERE idJugador = @idB07)
        PRINT '[OK] PRUEBA 1.4: Al minuto 60 hay 21 en cancha (B07 expulsado).';
    ELSE PRINT '[FALLO] PRUEBA 1.4: El equipo en cancha al minuto 60 no es el esperado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.5: Partido inexistente
-- Resultado esperado: 0 filas.
BEGIN TRY
    IF NOT EXISTS (SELECT 1 FROM Eventos.fn_EquipoEnCancha(-999, 30))
        PRINT '[OK] PRUEBA 1.5: Partido inexistente devuelve un conjunto vacío.';
    ELSE PRINT '[FALLO] PRUEBA 1.5: La función devolvió filas para un partido inexistente.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.5: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   SECCIÓN 2: Eventos.vw_HistorialTitularidad
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 2. PRUEBAS: Eventos.vw_HistorialTitularidad';
PRINT '--------------------------------------------------------------------------------';

DECLARE @idPart int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99601);
DECLARE @idA01 int = (SELECT id FROM #jug WHERE codigo = 'A01');
DECLARE @idA05 int = (SELECT id FROM #jug WHERE codigo = 'A05');
DECLARE @idA12 int = (SELECT id FROM #jug WHERE codigo = 'A12');
DECLARE @idB07 int = (SELECT id FROM #jug WHERE codigo = 'B07');

SELECT 'HISTORIAL TITULARIDAD' AS momento, * FROM Eventos.vw_HistorialTitularidad
WHERE idPartido = @idPart AND idJugador IN (@idA01, @idA05, @idA12, @idB07) ORDER BY idJugador;

-- PRUEBA 2.1: Titular que jugó todo el partido (A01)
-- Resultado esperado: condicion 'Titular', sin minutoIngreso ni minutoSalida, no expulsado,
--                     rival 'Pais Funciones B' y fase 'Fase Test Funciones'; 24 filas en el partido.
BEGIN TRY
    IF (SELECT COUNT(*) FROM Eventos.vw_HistorialTitularidad WHERE idPartido = @idPart) = 24
       AND EXISTS (SELECT 1 FROM Eventos.vw_HistorialTitularidad
                   WHERE idPartido = @idPart AND idJugador = @idA01 AND titular = 1 AND condicion = 'Titular'
                     AND minutoIngreso IS NULL AND minutoSalida IS NULL AND expulsado = 0
                     AND rival = N'Pais Funciones B' AND fase = 'Fase Test Funciones' AND seleccion = N'Pais Funciones A')
        PRINT '[OK] PRUEBA 2.1: Titular sin cambios informado correctamente.';
    ELSE PRINT '[FALLO] PRUEBA 2.1: La fila del titular A01 no es la esperada.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.2: Suplente que ingresó al minuto 30 (A12)
-- Resultado esperado: condicion 'Suplente', minutoIngreso = 30, minutoSalida NULL.
BEGIN TRY
    IF EXISTS (SELECT 1 FROM Eventos.vw_HistorialTitularidad
               WHERE idPartido = @idPart AND idJugador = @idA12 AND titular = 0 AND condicion = 'Suplente'
                 AND minutoIngreso = 30 AND minutoSalida IS NULL AND expulsado = 0)
        PRINT '[OK] PRUEBA 2.2: Suplente que ingresó informado con minutoIngreso = 30.';
    ELSE PRINT '[FALLO] PRUEBA 2.2: La fila del suplente A12 no es la esperada.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.3: Titular que salió al minuto 30 (A05)
-- Resultado esperado: condicion 'Titular', minutoIngreso NULL, minutoSalida = 30.
BEGIN TRY
    IF EXISTS (SELECT 1 FROM Eventos.vw_HistorialTitularidad
               WHERE idPartido = @idPart AND idJugador = @idA05 AND condicion = 'Titular'
                 AND minutoIngreso IS NULL AND minutoSalida = 30)
        PRINT '[OK] PRUEBA 2.3: Titular reemplazado informado con minutoSalida = 30.';
    ELSE PRINT '[FALLO] PRUEBA 2.3: La fila del titular A05 no es la esperada.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.4: Jugador expulsado (B07, roja directa)
-- Resultado esperado: expulsado = 1 y rival 'Pais Funciones A'.
BEGIN TRY
    IF EXISTS (SELECT 1 FROM Eventos.vw_HistorialTitularidad
               WHERE idPartido = @idPart AND idJugador = @idB07 AND expulsado = 1 AND rival = N'Pais Funciones A')
        PRINT '[OK] PRUEBA 2.4: Jugador expulsado informado con expulsado = 1.';
    ELSE PRINT '[FALLO] PRUEBA 2.4: La fila del expulsado B07 no es la esperada.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.4: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   SECCIÓN 3: Arbitraje.vw_HistorialArbitro
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 3. PRUEBAS: Arbitraje.vw_HistorialArbitro';
PRINT '--------------------------------------------------------------------------------';

DECLARE @idPart int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99601);
DECLARE @idArbUno int = (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'QFn Arbitro Uno');
DECLARE @idArbDos int = (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'QFn Arbitro Dos');

SELECT 'HISTORIAL ARBITRO' AS momento, * FROM Arbitraje.vw_HistorialArbitro WHERE idPartido = @idPart ORDER BY idArbitro;

-- PRUEBA 3.1: Datos del partido y tarjetas (árbitro Uno, Principal)
-- Resultado esperado: 1 fila; Pais Funciones A 2 - 1 Pais Funciones B, Finalizado; 2 amarillas y 1 roja.
BEGIN TRY
    IF (SELECT COUNT(*) FROM Arbitraje.vw_HistorialArbitro WHERE idPartido = @idPart AND idArbitro = @idArbUno) = 1
       AND EXISTS (SELECT 1 FROM Arbitraje.vw_HistorialArbitro
                   WHERE idPartido = @idPart AND idArbitro = @idArbUno AND rol = 'Principal'
                     AND arbitro = N'QFn Arbitro Uno, Neutral' AND paisArbitro = N'Pais Funciones Neutral'
                     AND seleccionLocal = N'Pais Funciones A' AND seleccionVisitante = N'Pais Funciones B'
                     AND golLocal = 2 AND golVisitante = 1 AND estado = 'Finalizado'
                     AND amarillas = 2 AND rojas = 1)
        PRINT '[OK] PRUEBA 3.1: Partido dirigido con resultado y tarjetas correctos.';
    ELSE PRINT '[FALLO] PRUEBA 3.1: La fila del árbitro Uno no tiene los datos esperados.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 3.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.2: Informes y sanciones del árbitro Uno
-- Resultado esperado: cantInformes = 2, cantSanciones = 1 y detalle en orden de fecha separado por ' | '.
BEGIN TRY
    IF EXISTS (SELECT 1 FROM Arbitraje.vw_HistorialArbitro
               WHERE idPartido = @idPart AND idArbitro = @idArbUno AND cantInformes = 2 AND cantSanciones = 1
                 AND detalleInformes = N'Informe uno | Informe dos | Sancion por error grave')
        PRINT '[OK] PRUEBA 3.2: Informes, sanciones y detalle del árbitro Uno correctos.';
    ELSE PRINT '[FALLO] PRUEBA 3.2: Los informes del árbitro Uno no son los esperados.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 3.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.3: Árbitro sin informes (Dos, Asistente 1)
-- Resultado esperado: cantInformes = 0, cantSanciones = 0 y detalleInformes NULL (las tarjetas del partido igual se informan).
BEGIN TRY
    IF EXISTS (SELECT 1 FROM Arbitraje.vw_HistorialArbitro
               WHERE idPartido = @idPart AND idArbitro = @idArbDos AND rol = 'Asistente 1'
                 AND cantInformes = 0 AND cantSanciones = 0 AND detalleInformes IS NULL
                 AND amarillas = 2 AND rojas = 1)
        PRINT '[OK] PRUEBA 3.3: Árbitro sin informes con conteos en 0.';
    ELSE PRINT '[FALLO] PRUEBA 3.3: La fila del árbitro Dos no es la esperada.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 3.3: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   LIMPIEZA FINAL DEL ENTORNO DE PRUEBAS
   ============================================================================= */
PRINT '--- Limpiando fixture auxiliar de pruebas ---';

DELETE FROM Arbitraje.InformeArbitral WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99601);
DELETE FROM Arbitraje.cuerpoArbitral  WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99601);
DELETE FROM Eventos.Gol               WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99601);
DELETE FROM Eventos.Tarjeta           WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99601);
DELETE FROM Eventos.Sustitucion       WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99601);
DELETE FROM Eventos.Suspension        WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99601);
DELETE FROM Eventos.FormacionPartido  WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99601);
DELETE FROM Torneo.Partido WHERE nroPartidoOficial = 99601;
DELETE FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test Funciones';
DELETE FROM Torneo.Fase WHERE idFase = 9911;
DELETE FROM Arbitraje.Arbitro WHERE apellido LIKE N'QFn Arbitro %';
DELETE FROM Equipos.ListadoJugadores WHERE idJugador IN (SELECT id FROM Equipos.Jugador WHERE apellido LIKE N'QFn Jugador %');
DELETE FROM Equipos.Jugador WHERE apellido LIKE N'QFn Jugador %';
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('QDA', 'QDB');
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('R1', 'R2', 'R3');

-- Períodos: solo los que insertó este script
IF OBJECT_ID('tempdb..#periodosCreados') IS NOT NULL
BEGIN
    DELETE FROM Torneo.Periodo WHERE idPeriodo IN (SELECT idPeriodo FROM #periodosCreados);
    DROP TABLE #periodosCreados;
END;

IF OBJECT_ID('tempdb..#jug') IS NOT NULL DROP TABLE #jug;

PRINT 'Fixture de pruebas limpiado con éxito.';
PRINT '================================================================================';
PRINT ' BATERÍA DE PRUEBAS DE FUNCIONES Y VISTAS FINALIZADA: 12 pruebas';
PRINT '   1. fn_EquipoEnCancha: 5 | 2. vw_HistorialTitularidad: 4 | 3. vw_HistorialArbitro: 3';
PRINT '================================================================================';
GO
