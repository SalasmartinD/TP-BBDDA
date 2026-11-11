/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel - 45066788
               Salas, Martín Daniel - 45205702
               Zito Padró, Ezequiel Nehuén - 46097917
 Fecha       : 09/11/2026

 Objetivo    : Suite de pruebas unitarias para 21_SP_Negocio_Arbitraje_Eventos.sql.
               Cubre los 4 procedimientos de negocio:
               - Eventos.RegistrarFormacion
               - Eventos.RegistrarCambio
               - Eventos.RegistrarTarjeta
               - Arbitraje.DesignarCuerpoArbitral
               y el camino entre ellos: la suspensión generada por tarjetas se
               cumple al registrar la formación del partido siguiente.

 Estándares aplicados:
 - Relación 1:1 con 21_SP_Negocio_Arbitraje_Eventos.sql.
 - Una prueba negativa por cada mensaje de validación, verificando el código
   50002 y el texto del error.
 - Un caso exitoso por SP con evidencia (SELECT) y una prueba de acumulación
   de errores (2 o 3 fallos) por SP.
 - Valores límite solo donde el límite es la regla: suplentes (justo / uno
   más), cambios (5º / 6º), ventanas (3ª / 4ª y ventana ya usada) y cambio
   extra en el alargue (pasa / el siguiente se rechaza).
 - Casos obligatorios de la consigna rotulados como CASO OBLIGATORIO 1..4.
 - Idempotencia: limpieza preventiva al inicio y final en orden inverso de FK
   (incluye lo que generan los SP: suspensiones, rojas por doble amarilla,
   cuerpo arbitral y esquemas). Los parámetros de Sistema.Parametro se guardan,
   se fijan valores de prueba y se restauran al final; los períodos que crea
   el fixture se registran y se borran al terminar.
================================================================================
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

PRINT '================================================================================';
PRINT ' INICIANDO BATERÍA DE PRUEBAS: 21_SP_Negocio_Arbitraje_Eventos.sql';
PRINT '================================================================================';
GO

/* =============================================================================
   PREPARACIÓN DEL ENTORNO DE PRUEBAS (FIXTURE AISLADO E IDEMPOTENTE)
   Códigos reservados: países Q1-Q4, selecciones QNA/QNB/QNC, partidos
   99701-99705, fases 9901/9902, jugadores 'QNeg Jugador %', árbitros
   'QNeg Arbitro %'.
   ============================================================================= */
PRINT '--- Limpieza preventiva de pruebas anteriores ---';

DELETE FROM Arbitraje.InformeArbitral WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99701, 99702, 99703, 99704, 99705));
DELETE FROM Arbitraje.cuerpoArbitral  WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99701, 99702, 99703, 99704, 99705))
                                         OR idArbitro IN (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido LIKE N'QNeg Arbitro %');
DELETE FROM Eventos.Gol               WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99701, 99702, 99703, 99704, 99705));
DELETE FROM Eventos.Tarjeta           WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99701, 99702, 99703, 99704, 99705));
DELETE FROM Eventos.Sustitucion       WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99701, 99702, 99703, 99704, 99705));
DELETE FROM Eventos.Suspension        WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99701, 99702, 99703, 99704, 99705))
                                         OR idJugador IN (SELECT id FROM Equipos.Jugador WHERE apellido LIKE N'QNeg Jugador %');
DELETE FROM Eventos.FormacionPartido  WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99701, 99702, 99703, 99704, 99705));
DELETE FROM Torneo.Partido WHERE nroPartidoOficial IN (99701, 99702, 99703, 99704, 99705);
DELETE FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test Negocio';
DELETE FROM Torneo.Fase WHERE idFase IN (9901, 9902);
DELETE FROM Arbitraje.Arbitro WHERE apellido LIKE N'QNeg Arbitro %';
DELETE FROM Equipos.ListadoJugadores WHERE idJugador IN (SELECT id FROM Equipos.Jugador WHERE apellido LIKE N'QNeg Jugador %');
DELETE FROM Equipos.Jugador WHERE apellido LIKE N'QNeg Jugador %';
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('QNA', 'QNB', 'QNC');
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('Q1', 'Q2', 'Q3', 'Q4');
GO

PRINT '--- Creando datos auxiliares de prueba ---';

-- Parámetros del reglamento: se guardan los originales (las tablas #temp
-- sobreviven entre lotes de la misma conexión), se fijan valores de prueba y
-- en la limpieza final se restauran (UPDATE al original o DELETE si no existía).
IF OBJECT_ID('tempdb..#parametrosOriginales') IS NOT NULL DROP TABLE #parametrosOriginales;
CREATE TABLE #parametrosOriginales (
    clave          varchar(50) PRIMARY KEY,
    valorPrueba    int         NOT NULL,
    existia        bit         NOT NULL,
    valorOriginal  int         NULL
);

INSERT INTO #parametrosOriginales (clave, valorPrueba, existia, valorOriginal)
SELECT k.clave, k.valorPrueba, CASE WHEN p.clave IS NULL THEN 0 ELSE 1 END, p.valor
FROM (VALUES ('MAX_SUPLENTES', 15), ('MAX_CAMBIOS', 5), ('MAX_VENTANAS', 3),
             ('CAMBIO_EXTRA_ALARGUE', 1), ('AMARILLAS_SUSPENSION', 2)) k (clave, valorPrueba)
LEFT JOIN Sistema.Parametro p ON p.clave = k.clave;

UPDATE p SET valor = o.valorPrueba
FROM Sistema.Parametro p
JOIN #parametrosOriginales o ON o.clave = p.clave;

INSERT INTO Sistema.Parametro (clave, valor, descripcion)
SELECT clave, valorPrueba, 'Valor de prueba (81c)'
FROM #parametrosOriginales
WHERE existia = 0;

-- Períodos 1, 2 y 3: se crean solo si faltan y se registran en #periodosCreados
-- para borrar en la limpieza final únicamente los que creó este script.
IF OBJECT_ID('tempdb..#periodosCreados') IS NOT NULL DROP TABLE #periodosCreados;
CREATE TABLE #periodosCreados (idPeriodo tinyint PRIMARY KEY);

INSERT INTO Torneo.Periodo (idPeriodo, nombre, orden)
OUTPUT inserted.idPeriodo INTO #periodosCreados (idPeriodo)
SELECT v.idPeriodo, v.nombre, v.orden
FROM (VALUES (1, 'Primer Tiempo', 1), (2, 'Segundo Tiempo', 2), (3, 'Primer Tiempo Extra', 3)) v (idPeriodo, nombre, orden)
WHERE NOT EXISTS (SELECT 1 FROM Torneo.Periodo p WHERE p.idPeriodo = v.idPeriodo);

-- Países: A, B y C tienen selección; Neutral no (sede y árbitros neutrales)
INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3)
VALUES (N'Pais Negocio A', 'Q1', 'QNA'),
       (N'Pais Negocio B', 'Q2', 'QNB'),
       (N'Pais Negocio C', 'Q3', 'QNC'),
       (N'Pais Negocio Neutral', 'Q4', 'QNN');

INSERT INTO Equipos.Seleccion (idPais, abreviacion, confederacion)
SELECT id, codigoISO3, 'UEFA'
FROM Torneo.Pais
WHERE codigoISO2 IN ('Q1', 'Q2', 'Q3');

-- Jugadores: A01-A27, B01-B26 y C01-C11, todos convocados activos de su
-- selección con dorsal = número. #jug guarda el código y el id de cada uno
-- para buscarlos una sola vez por sección.
IF OBJECT_ID('tempdb..#jug') IS NOT NULL DROP TABLE #jug;
CREATE TABLE #jug (
    codigo    char(3)      PRIMARY KEY,   -- 'A01', 'B12'...
    sel       char(1)      NOT NULL,
    nro       tinyint      NOT NULL,
    posicion  varchar(15)  NOT NULL,
    id        int          NULL
);

WITH Numero AS (
    SELECT d.t * 10 + u.u AS nro
    FROM (VALUES (0), (1), (2)) d (t)
    CROSS JOIN (VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9)) u (u)
)
INSERT INTO #jug (codigo, sel, nro, posicion)
SELECT s.sel + RIGHT('0' + CAST(n.nro AS varchar(2)), 2), s.sel, n.nro,
       CASE WHEN (n.nro - 1) % 11 + 1 = 1 THEN 'Arquero'
            WHEN (n.nro - 1) % 11 + 1 <= 5 THEN 'Defensor'
            WHEN (n.nro - 1) % 11 + 1 <= 8 THEN 'Mediocampista'
            ELSE 'Delantero' END
FROM (VALUES ('A', 27), ('B', 26), ('C', 11)) s (sel, cant)
JOIN Numero n ON n.nro BETWEEN 1 AND s.cant;

INSERT INTO Equipos.Jugador (nombre, apellido, posicion)
SELECT N'Jugador', N'QNeg Jugador ' + codigo, posicion
FROM #jug;

UPDATE j SET id = ej.id
FROM #jug j
JOIN Equipos.Jugador ej ON ej.apellido = N'QNeg Jugador ' + j.codigo;

INSERT INTO Equipos.ListadoJugadores (idSeleccion, idJugador, fechaAlta, dorsal)
SELECT s.id, j.id, '2026-05-01', j.nro
FROM #jug j
JOIN Equipos.Seleccion s ON s.abreviacion = 'QN' + j.sel;

-- Fases propias: 9901 grupos (orden 1) y 9902 dieciseisavos (orden 2)
INSERT INTO Torneo.Fase (idFase, nombre, esEliminatoria, orden)
VALUES (9901, 'Fase Test Negocio Grupos', 0, 1),
       (9902, 'Fase Test Negocio Dieciseisavos', 1, 2);

INSERT INTO Torneo.Sede (nombreEstadio, ciudad, idPais, husoHorario)
SELECT 'Estadio Test Negocio', 'Ciudad Negocio', id, 'UTC'
FROM Torneo.Pais WHERE codigoISO2 = 'Q4';

-- Árbitros: N1-N5 neutrales, A del país de la selección A (conflicto de
-- nacionalidad) y C del país de la selección C (advertencia de cruce)
INSERT INTO Arbitraje.Arbitro (idPais, nombre, apellido, categoria)
SELECT p.id, v.nombre, v.apellido, 'FIFA'
FROM (VALUES ('Q4', N'Neutral', N'QNeg Arbitro N1'),
             ('Q4', N'Neutral', N'QNeg Arbitro N2'),
             ('Q4', N'Neutral', N'QNeg Arbitro N3'),
             ('Q4', N'Neutral', N'QNeg Arbitro N4'),
             ('Q4', N'Neutral', N'QNeg Arbitro N5'),
             ('Q1', N'Local',   N'QNeg Arbitro A'),
             ('Q3', N'Rival',   N'QNeg Arbitro C')) v (iso, nombre, apellido)
JOIN Torneo.Pais p ON p.codigoISO2 = v.iso;

DECLARE @idSede int = (SELECT idSede FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test Negocio');
DECLARE @idSelA int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'QNA');
DECLARE @idSelB int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'QNB');
DECLARE @idSelC int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'QNC');

-- Partidos:
--   99701 A-B grupos  01/07 En juego    (cambios y tarjetas)
--   99702 A-C grupos  05/07 En juego    (tarjetas en otro partido)
--   99703 A-B grupos  10/07 Programado  (formaciones = partido siguiente; designación sin advertencia)
--   99704 A-B 16avos  20/07 Programado  (designación con advertencia de cruce)
--   99705 C-B 16avos  21/07 Programado  (deja a C "en competencia" en la fase eliminatoria)
INSERT INTO Torneo.Partido (nroPartidoOficial, idSede, idSeleccionLocal, idSeleccionVisitante, fase, fechaHoraUTC, estado)
VALUES (99701, @idSede, @idSelA, @idSelB, 9901, '2026-07-01 18:00:00', 'En juego'),
       (99702, @idSede, @idSelA, @idSelC, 9901, '2026-07-05 18:00:00', 'En juego'),
       (99703, @idSede, @idSelA, @idSelB, 9901, '2026-07-10 18:00:00', 'Programado'),
       (99704, @idSede, @idSelA, @idSelB, 9902, '2026-07-20 18:00:00', 'Programado'),
       (99705, @idSede, @idSelC, @idSelB, 9902, '2026-07-21 18:00:00', 'Programado');

-- Formaciones de los partidos en juego cargadas con INSERT directo: el SP
-- rechaza formaciones de partidos en juego, pero en la realidad se cargan
-- antes del inicio. El fixture simula ese estado previo.
--   99701: A01-A11 titulares, A12-A18 suplentes; B01-B11 titulares, B12-B14 suplentes.
--   99702: A01-A11 titulares (C sin formación, para la prueba de estado).
INSERT INTO Eventos.FormacionPartido (idPartido, idSeleccion, idJugador, titular, posicion)
SELECT p.idPartido, s.id, j.id, CASE WHEN j.nro <= 11 THEN 1 ELSE 0 END, j.posicion
FROM #jug j
JOIN Equipos.Seleccion s ON s.abreviacion = 'QN' + j.sel
JOIN Torneo.Partido p    ON p.nroPartidoOficial = 99701
WHERE (j.sel = 'A' AND j.nro <= 18)
   OR (j.sel = 'B' AND j.nro <= 14);

INSERT INTO Eventos.FormacionPartido (idPartido, idSeleccion, idJugador, titular, posicion)
SELECT p.idPartido, @idSelA, j.id, 1, j.posicion
FROM #jug j
JOIN Torneo.Partido p ON p.nroPartidoOficial = 99702
WHERE j.sel = 'A' AND j.nro <= 11;

PRINT 'Fixture de pruebas inicializado con éxito.';
PRINT '';
GO

/* =============================================================================
   SECCIÓN 1: Eventos.RegistrarFormacion   (partido 99703 'Programado')
   La validación de suspendidos (F12) se prueba en la sección 5 (CASO
   OBLIGATORIO 2), cuando las tarjetas de la sección 3 ya generaron la sanción.
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 1. PRUEBAS: Eventos.RegistrarFormacion';
PRINT '--------------------------------------------------------------------------------';

DECLARE @idPartSeg int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99702);
DECLARE @idPartSig int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99703);
DECLARE @idSelA int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'QNA');
DECLARE @idSelB int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'QNB');
DECLARE @idSelC int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'QNC');
DECLARE @idA01 int = (SELECT id FROM #jug WHERE codigo = 'A01');
DECLARE @idB01 int = (SELECT id FROM #jug WHERE codigo = 'B01');
DECLARE @valorParam int, @descParam varchar(200), @esperado nvarchar(400);

-- Listas reutilizadas: 11 titulares de A, 11 titulares de B, B completa
-- (11 titulares + 15 suplentes) y 11 titulares de C. @lista se arma en cada prueba.
DECLARE @listaA11 Eventos.FormacionJugadorLista;
DECLARE @listaB11 Eventos.FormacionJugadorLista;
DECLARE @listaB26 Eventos.FormacionJugadorLista;
DECLARE @listaC11 Eventos.FormacionJugadorLista;
DECLARE @lista    Eventos.FormacionJugadorLista;

INSERT INTO @listaA11 SELECT id, 1, posicion FROM #jug WHERE sel = 'A' AND nro <= 11;
INSERT INTO @listaB11 SELECT id, 1, posicion FROM #jug WHERE sel = 'B' AND nro <= 11;
INSERT INTO @listaB26 SELECT id, CASE WHEN nro <= 11 THEN 1 ELSE 0 END, posicion FROM #jug WHERE sel = 'B';
INSERT INTO @listaC11 SELECT id, 1, posicion FROM #jug WHERE sel = 'C';

-- PRUEBA 1.1: Registro exitoso de la formación visitante (B) con esquema táctico.
--             Valor límite: 11 titulares + 15 suplentes (justo MAX_SUPLENTES = 15).
-- Resultado esperado: 26 filas en FormacionPartido y esquemaVisitante = '4-4-2' (esquemaLocal sin tocar).
BEGIN TRY
    EXEC Eventos.RegistrarFormacion @idPartido = @idPartSig, @idSeleccion = @idSelB, @jugadores = @listaB26, @esquema = '4-4-2';
    SELECT 'FORMACION 1.1' AS momento, titular, COUNT(*) AS jugadores
    FROM Eventos.FormacionPartido WHERE idPartido = @idPartSig AND idSeleccion = @idSelB GROUP BY titular;
    SELECT 'PARTIDO 1.1' AS momento, idPartido, esquemaLocal, esquemaVisitante FROM Torneo.Partido WHERE idPartido = @idPartSig;
    IF (SELECT COUNT(*) FROM Eventos.FormacionPartido WHERE idPartido = @idPartSig AND idSeleccion = @idSelB) = 26
       AND EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartSig AND esquemaVisitante = '4-4-2' AND esquemaLocal IS NULL)
        PRINT '[OK] PRUEBA 1.1: Formación de 11 titulares y 15 suplentes registrada con esquema 4-4-2.';
    ELSE PRINT '[FALLO] PRUEBA 1.1: La formación o el esquema no quedaron con los valores esperados.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.2: Partido inexistente
-- Resultado esperado: THROW 50002 "- El partido especificado no existe."
BEGIN TRY
    EXEC Eventos.RegistrarFormacion @idPartido = -999, @idSeleccion = @idSelA, @jugadores = @listaA11;
    PRINT '[FALLO] PRUEBA 1.2: No detectó el partido inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- El partido especificado no existe.%'
        PRINT '[OK] PRUEBA 1.2: Partido inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 1.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.3: Selección inexistente
-- Resultado esperado: THROW 50002 "- La selección especificada no existe."
BEGIN TRY
    EXEC Eventos.RegistrarFormacion @idPartido = @idPartSig, @idSeleccion = -999, @jugadores = @listaA11;
    PRINT '[FALLO] PRUEBA 1.3: No detectó la selección inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- La selección especificada no existe.%'
        PRINT '[OK] PRUEBA 1.3: Selección inexistente rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 1.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.4: Selección (C) que no disputa el partido (A-B), con sus propios convocados
-- Resultado esperado: THROW 50002 "- La selección especificada no disputa el partido indicado."
BEGIN TRY
    EXEC Eventos.RegistrarFormacion @idPartido = @idPartSig, @idSeleccion = @idSelC, @jugadores = @listaC11;
    PRINT '[FALLO] PRUEBA 1.4: Permitió la formación de una selección ajena al partido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- La selección especificada no disputa el partido indicado.%'
        PRINT '[OK] PRUEBA 1.4: Selección ajena al partido rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 1.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.5: Formación de C en un partido en juego (99702, A-C)
-- Resultado esperado: THROW 50002 "- No se puede registrar la formación de un partido en juego o finalizado."
BEGIN TRY
    EXEC Eventos.RegistrarFormacion @idPartido = @idPartSeg, @idSeleccion = @idSelC, @jugadores = @listaC11;
    PRINT '[FALLO] PRUEBA 1.5: Permitió registrar la formación de un partido en juego.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- No se puede registrar la formación de un partido en juego o finalizado.%'
        PRINT '[OK] PRUEBA 1.5: Formación en partido en juego rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 1.5: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.6: Segunda formación de B en el mismo partido (la de 1.1 ya existe)
-- Resultado esperado: THROW 50002 "- La selección ya tiene una formación registrada para este partido."
BEGIN TRY
    EXEC Eventos.RegistrarFormacion @idPartido = @idPartSig, @idSeleccion = @idSelB, @jugadores = @listaB11;
    PRINT '[FALLO] PRUEBA 1.6: Permitió una segunda formación para la misma selección.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- La selección ya tiene una formación registrada para este partido.%'
        PRINT '[OK] PRUEBA 1.6: Formación duplicada rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 1.6: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.7: Lista de jugadores vacía
-- Resultado esperado: THROW 50002 "- La lista de jugadores está vacía."
DELETE FROM @lista;
BEGIN TRY
    EXEC Eventos.RegistrarFormacion @idPartido = @idPartSig, @idSeleccion = @idSelA, @jugadores = @lista;
    PRINT '[FALLO] PRUEBA 1.7: Permitió una lista vacía.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- La lista de jugadores está vacía.%'
        PRINT '[OK] PRUEBA 1.7: Lista vacía rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 1.7: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.8: Solo 10 titulares (A01-A10)
-- Resultado esperado: THROW 50002 "- La formación titular debe tener exactamente 11 jugadores (se informaron 10)."
DELETE FROM @lista;
INSERT INTO @lista SELECT id, 1, posicion FROM #jug WHERE sel = 'A' AND nro <= 10;
BEGIN TRY
    EXEC Eventos.RegistrarFormacion @idPartido = @idPartSig, @idSeleccion = @idSelA, @jugadores = @lista;
    PRINT '[FALLO] PRUEBA 1.8: Permitió una formación con 10 titulares.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- La formación titular debe tener exactamente 11 jugadores (se informaron 10).%'
        PRINT '[OK] PRUEBA 1.8: Formación con 10 titulares rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 1.8: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.9: Falta el parámetro MAX_SUPLENTES (se borra y se repone en la misma prueba)
-- Resultado esperado: THROW 50002 "- No está configurado el parámetro MAX_SUPLENTES en Sistema.Parametro."
SELECT @valorParam = valor, @descParam = descripcion FROM Sistema.Parametro WHERE clave = 'MAX_SUPLENTES';
DELETE FROM Sistema.Parametro WHERE clave = 'MAX_SUPLENTES';
BEGIN TRY
    EXEC Eventos.RegistrarFormacion @idPartido = @idPartSig, @idSeleccion = @idSelA, @jugadores = @listaA11;
    PRINT '[FALLO] PRUEBA 1.9: No detectó la falta del parámetro MAX_SUPLENTES.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- No está configurado el parámetro MAX_SUPLENTES en Sistema.Parametro.%'
        PRINT '[OK] PRUEBA 1.9: Falta de MAX_SUPLENTES informada.';
    ELSE PRINT '[FALLO] PRUEBA 1.9: ' + ERROR_MESSAGE();
END CATCH;
INSERT INTO Sistema.Parametro (clave, valor, descripcion) VALUES ('MAX_SUPLENTES', @valorParam, @descParam);

-- PRUEBA 1.10: Valor límite - un suplente más que el máximo (11 titulares + 16 suplentes)
-- Resultado esperado: THROW 50002 "- La cantidad de suplentes (16) supera el máximo permitido (15)."
DELETE FROM @lista;
INSERT INTO @lista SELECT id, CASE WHEN nro <= 11 THEN 1 ELSE 0 END, posicion FROM #jug WHERE sel = 'A';
BEGIN TRY
    EXEC Eventos.RegistrarFormacion @idPartido = @idPartSig, @idSeleccion = @idSelA, @jugadores = @lista;
    PRINT '[FALLO] PRUEBA 1.10: Permitió 16 suplentes.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- La cantidad de suplentes (16) supera el máximo permitido (15).%'
        PRINT '[OK] PRUEBA 1.10: 16 suplentes rechazados (máximo 15).';
    ELSE PRINT '[FALLO] PRUEBA 1.10: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.11: Jugador repetido en la lista (A01 como titular y como suplente)
-- Resultado esperado: THROW 50002 "- Hay jugadores repetidos en la lista: <id A01>."
DELETE FROM @lista;
INSERT INTO @lista SELECT idJugador, titular, posicion FROM @listaA11;
INSERT INTO @lista VALUES (@idA01, 0, NULL);
SET @esperado = N'%- Hay jugadores repetidos en la lista: ' + CAST(@idA01 AS nvarchar(12)) + N'.%';
BEGIN TRY
    EXEC Eventos.RegistrarFormacion @idPartido = @idPartSig, @idSeleccion = @idSelA, @jugadores = @lista;
    PRINT '[FALLO] PRUEBA 1.11: Permitió un jugador repetido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE @esperado
        PRINT '[OK] PRUEBA 1.11: Jugador repetido rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 1.11: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.12: Jugador que no es convocado de la selección (B01 en la formación de A)
-- Resultado esperado: THROW 50002 "- Los siguientes jugadores no son convocados activos de la selección: <id B01>."
DELETE FROM @lista;
INSERT INTO @lista SELECT id, 1, posicion FROM #jug WHERE sel = 'A' AND nro <= 10;
INSERT INTO @lista VALUES (@idB01, 1, 'Arquero');
SET @esperado = N'%- Los siguientes jugadores no son convocados activos de la selección: ' + CAST(@idB01 AS nvarchar(12)) + N'.%';
BEGIN TRY
    EXEC Eventos.RegistrarFormacion @idPartido = @idPartSig, @idSeleccion = @idSelA, @jugadores = @lista;
    PRINT '[FALLO] PRUEBA 1.12: Permitió un jugador que no es convocado de la selección.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE @esperado
        PRINT '[OK] PRUEBA 1.12: Jugador no convocado rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 1.12: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.13: Posición fuera del dominio ('Volante')
-- Resultado esperado: THROW 50002 "- Hay posiciones inválidas: deben ser Arquero, Defensor, Mediocampista o Delantero."
DELETE FROM @lista;
INSERT INTO @lista SELECT idJugador, titular, CASE WHEN idJugador = @idA01 THEN 'Volante' ELSE posicion END FROM @listaA11;
BEGIN TRY
    EXEC Eventos.RegistrarFormacion @idPartido = @idPartSig, @idSeleccion = @idSelA, @jugadores = @lista;
    PRINT '[FALLO] PRUEBA 1.13: Permitió una posición inválida.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- Hay posiciones inválidas: deben ser Arquero, Defensor, Mediocampista o Delantero.%'
        PRINT '[OK] PRUEBA 1.13: Posición inválida rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 1.13: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.14: Esquema con formato válido que no suma 10 jugadores de campo ('4-4-3')
-- Resultado esperado: THROW 50002 "- El esquema táctico debe tener números de 1 a 9 separados por guiones que sumen 10 (ej. 4-3-3)."
BEGIN TRY
    EXEC Eventos.RegistrarFormacion @idPartido = @idPartSig, @idSeleccion = @idSelA, @jugadores = @listaA11, @esquema = '4-4-3';
    PRINT '[FALLO] PRUEBA 1.14: Permitió un esquema que suma 11.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- El esquema táctico debe tener números de 1 a 9 separados por guiones que sumen 10%'
        PRINT '[OK] PRUEBA 1.14: Esquema inválido rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 1.14: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.15: 3 errores simultáneos (partido inexistente, 10 titulares, esquema '433')
-- Resultado esperado: THROW 50002 con los 3 mensajes juntos.
DELETE FROM @lista;
INSERT INTO @lista SELECT id, 1, posicion FROM #jug WHERE sel = 'A' AND nro <= 10;
BEGIN TRY
    EXEC Eventos.RegistrarFormacion @idPartido = -999, @idSeleccion = @idSelA, @jugadores = @lista, @esquema = '433';
    PRINT '[FALLO] PRUEBA 1.15: No detectó los errores acumulados.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002
       AND ERROR_MESSAGE() LIKE N'%- El partido especificado no existe.%'
       AND ERROR_MESSAGE() LIKE N'%(se informaron 10)%'
       AND ERROR_MESSAGE() LIKE N'%- El esquema táctico debe tener números de 1 a 9%'
        PRINT '[OK] PRUEBA 1.15: Acumulación de 3 errores verificada.';
    ELSE PRINT '[FALLO] PRUEBA 1.15: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   SECCIÓN 2: Eventos.RegistrarCambio   (partido 99701 'En juego', selección A)
   Parámetros de prueba: MAX_CAMBIOS = 5, MAX_VENTANAS = 3, CAMBIO_EXTRA_ALARGUE = 1.
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 2. PRUEBAS: Eventos.RegistrarCambio';
PRINT '--------------------------------------------------------------------------------';

DECLARE @idPartJuego int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99701);
DECLARE @idPartSig   int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99703);
DECLARE @idA01 int = (SELECT id FROM #jug WHERE codigo = 'A01');
DECLARE @idA02 int = (SELECT id FROM #jug WHERE codigo = 'A02');
DECLARE @idA03 int = (SELECT id FROM #jug WHERE codigo = 'A03');
DECLARE @idA04 int = (SELECT id FROM #jug WHERE codigo = 'A04');
DECLARE @idA05 int = (SELECT id FROM #jug WHERE codigo = 'A05');
DECLARE @idA06 int = (SELECT id FROM #jug WHERE codigo = 'A06');
DECLARE @idA07 int = (SELECT id FROM #jug WHERE codigo = 'A07');
DECLARE @idA12 int = (SELECT id FROM #jug WHERE codigo = 'A12');
DECLARE @idA13 int = (SELECT id FROM #jug WHERE codigo = 'A13');
DECLARE @idA14 int = (SELECT id FROM #jug WHERE codigo = 'A14');
DECLARE @idA15 int = (SELECT id FROM #jug WHERE codigo = 'A15');
DECLARE @idA16 int = (SELECT id FROM #jug WHERE codigo = 'A16');
DECLARE @idA17 int = (SELECT id FROM #jug WHERE codigo = 'A17');
DECLARE @idA18 int = (SELECT id FROM #jug WHERE codigo = 'A18');
DECLARE @idB02 int = (SELECT id FROM #jug WHERE codigo = 'B02');
DECLARE @idB12 int = (SELECT id FROM #jug WHERE codigo = 'B12');
DECLARE @idCambio int, @valorParam int, @descParam varchar(200);

-- PRUEBA 2.1 (CASO OBLIGATORIO 3): Cambio por lesión antes del minuto 20 (sale A01, entra A12 al minuto 15)
-- Resultado esperado: Sustitución registrada con motivo 'Lesion' e ID devuelto.
BEGIN TRY
    EXEC Eventos.RegistrarCambio @idPartido = @idPartJuego, @idSale = @idA01, @idIngresa = @idA12, @idPeriodo = 1,
         @minuto = 15, @motivo = 'Lesion', @id = @idCambio OUTPUT;
    SELECT 'CAMBIO 2.1' AS momento, * FROM Eventos.Sustitucion WHERE id = @idCambio;
    IF EXISTS (SELECT 1 FROM Eventos.Sustitucion
               WHERE id = @idCambio AND idSale = @idA01 AND idIngresa = @idA12 AND minuto = 15 AND motivo = 'Lesion')
        PRINT '[OK] PRUEBA 2.1: Cambio por lesión al minuto 15 registrado con ID = ' + CAST(@idCambio AS varchar(10));
    ELSE PRINT '[FALLO] PRUEBA 2.1: El cambio no quedó con los valores esperados.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.2: Partido inexistente
-- Resultado esperado: THROW 50002 "- El partido especificado no existe."
BEGIN TRY
    EXEC Eventos.RegistrarCambio @idPartido = -999, @idSale = @idA02, @idIngresa = @idA13, @idPeriodo = 1, @minuto = 30, @motivo = 'Tactico';
    PRINT '[FALLO] PRUEBA 2.2: No detectó el partido inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- El partido especificado no existe.%'
        PRINT '[OK] PRUEBA 2.2: Partido inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.3: Cambio en un partido programado (99703, con la formación de B de la prueba 1.1)
-- Resultado esperado: THROW 50002 "- No se pueden registrar cambios en un partido que todavía se encuentra en estado programado."
BEGIN TRY
    EXEC Eventos.RegistrarCambio @idPartido = @idPartSig, @idSale = @idB02, @idIngresa = @idB12, @idPeriodo = 1, @minuto = 30, @motivo = 'Tactico';
    PRINT '[FALLO] PRUEBA 2.3: Permitió un cambio en un partido programado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- No se pueden registrar cambios en un partido que todavía se encuentra en estado programado.%'
        PRINT '[OK] PRUEBA 2.3: Cambio en partido programado rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.4: Período inexistente
-- Resultado esperado: THROW 50002 "- El período de juego especificado no existe."
BEGIN TRY
    EXEC Eventos.RegistrarCambio @idPartido = @idPartJuego, @idSale = @idA02, @idIngresa = @idA13, @idPeriodo = 99, @minuto = 30, @motivo = 'Tactico';
    PRINT '[FALLO] PRUEBA 2.4: No detectó el período inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- El período de juego especificado no existe.%'
        PRINT '[OK] PRUEBA 2.4: Período inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.5: Minuto fuera de rango (121)
-- Resultado esperado: THROW 50002 "- El minuto del cambio es obligatorio y debe encontrarse entre 0 y 120."
BEGIN TRY
    EXEC Eventos.RegistrarCambio @idPartido = @idPartJuego, @idSale = @idA02, @idIngresa = @idA13, @idPeriodo = 2, @minuto = 121, @motivo = 'Tactico';
    PRINT '[FALLO] PRUEBA 2.5: Permitió el minuto 121.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- El minuto del cambio es obligatorio y debe encontrarse entre 0 y 120.%'
        PRINT '[OK] PRUEBA 2.5: Minuto 121 rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.5: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.6: Minuto adicional fuera de un minuto de cierre (30+2)
-- Resultado esperado: THROW 50002 "- El minuto adicional solo es válido en los minutos de cierre reglamentario (45, 90, 105 o 120)."
BEGIN TRY
    EXEC Eventos.RegistrarCambio @idPartido = @idPartJuego, @idSale = @idA02, @idIngresa = @idA13, @idPeriodo = 1,
         @minuto = 30, @minutoAdicional = 2, @motivo = 'Tactico';
    PRINT '[FALLO] PRUEBA 2.6: Permitió minuto adicional en el minuto 30.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- El minuto adicional solo es válido en los minutos de cierre reglamentario (45, 90, 105 o 120).%'
        PRINT '[OK] PRUEBA 2.6: Minuto adicional inválido rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.6: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.7: Motivo fuera del dominio ('Castigo')
-- Resultado esperado: THROW 50002 "- El motivo del cambio debe ser Tactico, Lesion o Precaucion."
BEGIN TRY
    EXEC Eventos.RegistrarCambio @idPartido = @idPartJuego, @idSale = @idA02, @idIngresa = @idA13, @idPeriodo = 1, @minuto = 30, @motivo = 'Castigo';
    PRINT '[FALLO] PRUEBA 2.7: Permitió un motivo inválido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- El motivo del cambio debe ser Tactico, Lesion o Precaucion.%'
        PRINT '[OK] PRUEBA 2.7: Motivo inválido rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.7: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.8: Sale y entra el mismo jugador (A02)
-- Resultado esperado: THROW 50002 "- El jugador que sale y el que entra deben ser distintos."
--                     (también informa que A02, titular, no está en el banco)
BEGIN TRY
    EXEC Eventos.RegistrarCambio @idPartido = @idPartJuego, @idSale = @idA02, @idIngresa = @idA02, @idPeriodo = 1, @minuto = 30, @motivo = 'Tactico';
    PRINT '[FALLO] PRUEBA 2.8: Permitió que salga y entre el mismo jugador.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- El jugador que sale y el que entra deben ser distintos.%'
        PRINT '[OK] PRUEBA 2.8: Mismo jugador en ambos lados rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.8: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.9: Sale un jugador que ya no está en cancha (A01 salió al minuto 15)
-- Resultado esperado: THROW 50002 "- El jugador que sale no está en cancha en ese minuto."
BEGIN TRY
    EXEC Eventos.RegistrarCambio @idPartido = @idPartJuego, @idSale = @idA01, @idIngresa = @idA13, @idPeriodo = 1, @minuto = 30, @motivo = 'Tactico';
    PRINT '[FALLO] PRUEBA 2.9: Permitió sacar a un jugador que no está en cancha.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- El jugador que sale no está en cancha en ese minuto.%'
        PRINT '[OK] PRUEBA 2.9: Jugador fuera de cancha rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.9: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.10: Entra un suplente que ya ingresó (A12 entró al minuto 15)
-- Resultado esperado: THROW 50002 "- El jugador que entra no está disponible en el banco de suplentes."
BEGIN TRY
    EXEC Eventos.RegistrarCambio @idPartido = @idPartJuego, @idSale = @idA02, @idIngresa = @idA12, @idPeriodo = 1, @minuto = 30, @motivo = 'Tactico';
    PRINT '[FALLO] PRUEBA 2.10: Permitió el ingreso de un jugador que ya había entrado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- El jugador que entra no está disponible en el banco de suplentes.%'
        PRINT '[OK] PRUEBA 2.10: Jugador no disponible en el banco rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.10: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.11: Jugadores de selecciones distintas (sale A02, entra B12, suplente de B)
-- Resultado esperado: THROW 50002 "- Los dos jugadores deben pertenecer a la misma selección."
BEGIN TRY
    EXEC Eventos.RegistrarCambio @idPartido = @idPartJuego, @idSale = @idA02, @idIngresa = @idB12, @idPeriodo = 1, @minuto = 30, @motivo = 'Tactico';
    PRINT '[FALLO] PRUEBA 2.11: Permitió un cambio entre selecciones distintas.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- Los dos jugadores deben pertenecer a la misma selección.%'
        PRINT '[OK] PRUEBA 2.11: Cambio entre selecciones distintas rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.11: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.12: Cambio anterior al último registrado de la selección (minuto 10 < 15)
-- Resultado esperado: THROW 50002 "- El cambio no puede ser anterior al último cambio registrado de la selección."
BEGIN TRY
    EXEC Eventos.RegistrarCambio @idPartido = @idPartJuego, @idSale = @idA02, @idIngresa = @idA13, @idPeriodo = 1, @minuto = 10, @motivo = 'Tactico';
    PRINT '[FALLO] PRUEBA 2.12: Permitió un cambio anterior al último registrado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- El cambio no puede ser anterior al último cambio registrado de la selección.%'
        PRINT '[OK] PRUEBA 2.12: Cambio fuera de orden rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.12: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.13: Falta el parámetro MAX_VENTANAS (se borra y se repone en la misma prueba)
-- Resultado esperado: THROW 50002 "- Faltan configurar en Sistema.Parametro: MAX_VENTANAS."
SELECT @valorParam = valor, @descParam = descripcion FROM Sistema.Parametro WHERE clave = 'MAX_VENTANAS';
DELETE FROM Sistema.Parametro WHERE clave = 'MAX_VENTANAS';
BEGIN TRY
    EXEC Eventos.RegistrarCambio @idPartido = @idPartJuego, @idSale = @idA02, @idIngresa = @idA13, @idPeriodo = 1, @minuto = 30, @motivo = 'Tactico';
    PRINT '[FALLO] PRUEBA 2.13: No detectó la falta del parámetro MAX_VENTANAS.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- Faltan configurar en Sistema.Parametro: MAX[_]VENTANAS.%'
        PRINT '[OK] PRUEBA 2.13: Falta de MAX_VENTANAS informada.';
    ELSE PRINT '[FALLO] PRUEBA 2.13: ' + ERROR_MESSAGE();
END CATCH;
INSERT INTO Sistema.Parametro (clave, valor, descripcion) VALUES ('MAX_VENTANAS', @valorParam, @descParam);

-- PRUEBA 2.14: 3 errores simultáneos (período inexistente, minuto adicional en el 30, motivo inválido)
-- Resultado esperado: THROW 50002 con los 3 mensajes juntos.
BEGIN TRY
    EXEC Eventos.RegistrarCambio @idPartido = @idPartJuego, @idSale = @idA02, @idIngresa = @idA13, @idPeriodo = 99,
         @minuto = 30, @minutoAdicional = 2, @motivo = 'Castigo';
    PRINT '[FALLO] PRUEBA 2.14: No detectó los errores acumulados.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002
       AND ERROR_MESSAGE() LIKE N'%- El período de juego especificado no existe.%'
       AND ERROR_MESSAGE() LIKE N'%- El minuto adicional solo es válido%'
       AND ERROR_MESSAGE() LIKE N'%- El motivo del cambio debe ser%'
        PRINT '[OK] PRUEBA 2.14: Acumulación de 3 errores verificada.';
    ELSE PRINT '[FALLO] PRUEBA 2.14: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.15: Valor límite - 3 ventanas permitidas (15', 60' con dos cambios y 75')
-- Resultado esperado: Se aceptan los 3 cambios; la selección queda con 4 cambios en 3 ventanas.
BEGIN TRY
    EXEC Eventos.RegistrarCambio @idPartido = @idPartJuego, @idSale = @idA02, @idIngresa = @idA13, @idPeriodo = 2, @minuto = 60, @motivo = 'Tactico';
    EXEC Eventos.RegistrarCambio @idPartido = @idPartJuego, @idSale = @idA03, @idIngresa = @idA14, @idPeriodo = 2, @minuto = 60, @motivo = 'Tactico';
    EXEC Eventos.RegistrarCambio @idPartido = @idPartJuego, @idSale = @idA04, @idIngresa = @idA15, @idPeriodo = 2, @minuto = 75, @motivo = 'Precaucion';
    SELECT 'CAMBIOS 2.15' AS momento, id, idSale, idIngresa, minuto, motivo FROM Eventos.Sustitucion WHERE idPartido = @idPartJuego ORDER BY id;
    IF (SELECT COUNT(*) FROM Eventos.Sustitucion WHERE idPartido = @idPartJuego) = 4
       AND (SELECT COUNT(DISTINCT minuto) FROM Eventos.Sustitucion WHERE idPartido = @idPartJuego) = 3
        PRINT '[OK] PRUEBA 2.15: 4 cambios en 3 ventanas aceptados.';
    ELSE PRINT '[FALLO] PRUEBA 2.15: La cantidad de cambios o ventanas no es la esperada.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.15: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.16: Valor límite - 4ª ventana (minuto 80, con las 3 ventanas usadas)
-- Resultado esperado: THROW 50002 "- La selección ya usó las 3 ventanas de cambio permitidas."
BEGIN TRY
    EXEC Eventos.RegistrarCambio @idPartido = @idPartJuego, @idSale = @idA05, @idIngresa = @idA16, @idPeriodo = 2, @minuto = 80, @motivo = 'Tactico';
    PRINT '[FALLO] PRUEBA 2.16: Permitió una 4ª ventana de cambios.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- La selección ya usó las 3 ventanas de cambio permitidas.%'
        PRINT '[OK] PRUEBA 2.16: 4ª ventana rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 2.16: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.17: Valor límite - 5º cambio dentro de una ventana ya usada (minuto 75)
-- Resultado esperado: Cambio aceptado (no abre ventana nueva); la selección queda con 5 cambios.
BEGIN TRY
    EXEC Eventos.RegistrarCambio @idPartido = @idPartJuego, @idSale = @idA05, @idIngresa = @idA16, @idPeriodo = 2, @minuto = 75, @motivo = 'Tactico',
         @id = @idCambio OUTPUT;
    SELECT 'CAMBIO 2.17' AS momento, * FROM Eventos.Sustitucion WHERE id = @idCambio;
    IF (SELECT COUNT(*) FROM Eventos.Sustitucion WHERE idPartido = @idPartJuego) = 5
        PRINT '[OK] PRUEBA 2.17: 5º cambio en la ventana del minuto 75 aceptado.';
    ELSE PRINT '[FALLO] PRUEBA 2.17: La selección no quedó con 5 cambios.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.17: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.18: Valor límite - 6º cambio en tiempo reglamentario (misma ventana del 75)
-- Resultado esperado: THROW 50002 "- La selección ya realizó los 5 cambios permitidos."
BEGIN TRY
    EXEC Eventos.RegistrarCambio @idPartido = @idPartJuego, @idSale = @idA06, @idIngresa = @idA17, @idPeriodo = 2, @minuto = 75, @motivo = 'Tactico';
    PRINT '[FALLO] PRUEBA 2.18: Permitió un 6º cambio en tiempo reglamentario.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- La selección ya realizó los 5 cambios permitidos.%'
        PRINT '[OK] PRUEBA 2.18: 6º cambio rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.18: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.19: Cambio extra del alargue (minuto 95): límite 5 + 1 cambios y 3 + 1 ventanas
-- Resultado esperado: Cambio aceptado; la selección queda con 6 cambios.
BEGIN TRY
    EXEC Eventos.RegistrarCambio @idPartido = @idPartJuego, @idSale = @idA06, @idIngresa = @idA17, @idPeriodo = 3, @minuto = 95, @motivo = 'Tactico',
         @id = @idCambio OUTPUT;
    SELECT 'CAMBIO 2.19' AS momento, * FROM Eventos.Sustitucion WHERE id = @idCambio;
    IF (SELECT COUNT(*) FROM Eventos.Sustitucion WHERE idPartido = @idPartJuego) = 6
        PRINT '[OK] PRUEBA 2.19: Cambio extra del alargue aceptado.';
    ELSE PRINT '[FALLO] PRUEBA 2.19: La selección no quedó con 6 cambios.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.19: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.20: Cambio siguiente al extra del alargue (minuto 95, misma ventana)
-- Resultado esperado: THROW 50002 "- La selección ya realizó los 6 cambios permitidos."
BEGIN TRY
    EXEC Eventos.RegistrarCambio @idPartido = @idPartJuego, @idSale = @idA07, @idIngresa = @idA18, @idPeriodo = 3, @minuto = 95, @motivo = 'Tactico';
    PRINT '[FALLO] PRUEBA 2.20: Permitió un 7º cambio en el alargue.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- La selección ya realizó los 6 cambios permitidos.%'
        PRINT '[OK] PRUEBA 2.20: Cambio posterior al extra del alargue rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.20: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   SECCIÓN 3: Eventos.RegistrarTarjeta   (partidos 99701 y 99702 'En juego')
   Parámetro de prueba: AMARILLAS_SUSPENSION = 2.
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 3. PRUEBAS: Eventos.RegistrarTarjeta';
PRINT '--------------------------------------------------------------------------------';

DECLARE @idPartJuego int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99701);
DECLARE @idPartSeg   int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99702);
DECLARE @idPartSig   int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99703);
DECLARE @idA02 int = (SELECT id FROM #jug WHERE codigo = 'A02');
DECLARE @idA09 int = (SELECT id FROM #jug WHERE codigo = 'A09');
DECLARE @idA10 int = (SELECT id FROM #jug WHERE codigo = 'A10');
DECLARE @idA11 int = (SELECT id FROM #jug WHERE codigo = 'A11');
DECLARE @idA19 int = (SELECT id FROM #jug WHERE codigo = 'A19');
DECLARE @idB01 int = (SELECT id FROM #jug WHERE codigo = 'B01');
DECLARE @idTarjeta int;

-- PRUEBA 3.1: Amarilla simple (A11 en 99701, primera amarilla del torneo)
-- Resultado esperado: Tarjeta registrada con tipoRoja NULL y sin suspensión (1 amarilla < 2).
BEGIN TRY
    EXEC Eventos.RegistrarTarjeta @idPartido = @idPartJuego, @idJugador = @idA11, @idPeriodo = 1, @color = 'A',
         @minuto = 20, @motivo = 'Juego brusco', @idTarjeta = @idTarjeta OUTPUT;
    SELECT 'TARJETA 3.1' AS momento, * FROM Eventos.Tarjeta WHERE idTarjeta = @idTarjeta;
    IF EXISTS (SELECT 1 FROM Eventos.Tarjeta WHERE idTarjeta = @idTarjeta AND idJugador = @idA11 AND color = 'A' AND tipoRoja IS NULL)
       AND NOT EXISTS (SELECT 1 FROM Eventos.Suspension WHERE idJugador = @idA11)
        PRINT '[OK] PRUEBA 3.1: Amarilla simple registrada sin suspensión.';
    ELSE PRINT '[FALLO] PRUEBA 3.1: La tarjeta o la suspensión no quedaron como se esperaba.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 3.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.2 (CASO OBLIGATORIO 1, parte a): Expulsión por doble amarilla (A09 en 99701, minutos 30 y 50)
-- Resultado esperado: 2 amarillas + roja 'Doble amarilla' generada al minuto 50 y Suspension de 1 partido.
BEGIN TRY
    EXEC Eventos.RegistrarTarjeta @idPartido = @idPartJuego, @idJugador = @idA09, @idPeriodo = 1, @color = 'A', @minuto = 30, @motivo = 'Mano intencional';
    EXEC Eventos.RegistrarTarjeta @idPartido = @idPartJuego, @idJugador = @idA09, @idPeriodo = 2, @color = 'A', @minuto = 50, @motivo = 'Demora en el juego';
    SELECT 'TARJETAS 3.2' AS momento, idTarjeta, color, minuto, motivo, tipoRoja FROM Eventos.Tarjeta WHERE idPartido = @idPartJuego AND idJugador = @idA09 ORDER BY idTarjeta;
    SELECT 'SUSPENSION 3.2' AS momento, * FROM Eventos.Suspension WHERE idPartido = @idPartJuego AND idJugador = @idA09;
    IF (SELECT COUNT(*) FROM Eventos.Tarjeta WHERE idPartido = @idPartJuego AND idJugador = @idA09 AND color = 'A') = 2
       AND EXISTS (SELECT 1 FROM Eventos.Tarjeta WHERE idPartido = @idPartJuego AND idJugador = @idA09
                   AND color = 'R' AND tipoRoja = 'Doble amarilla' AND minuto = 50)
       AND EXISTS (SELECT 1 FROM Eventos.Suspension WHERE idPartido = @idPartJuego AND idJugador = @idA09
                   AND cantPartidos = 1 AND partidosRestantes = 1)
        PRINT '[OK] PRUEBA 3.2: Doble amarilla genera la roja y 1 partido de suspensión.';
    ELSE PRINT '[FALLO] PRUEBA 3.2: La roja o la suspensión por doble amarilla no son las esperadas.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 3.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.3 (CASO OBLIGATORIO 1, parte b): Roja directa en otro partido (A10 en 99702)
-- Resultado esperado: Roja con tipoRoja 'Directa' y Suspension de 1 partido en 99702.
BEGIN TRY
    EXEC Eventos.RegistrarTarjeta @idPartido = @idPartSeg, @idJugador = @idA10, @idPeriodo = 2, @color = 'R',
         @minuto = 70, @motivo = 'Conducta violenta', @idTarjeta = @idTarjeta OUTPUT;
    SELECT 'TARJETA 3.3' AS momento, * FROM Eventos.Tarjeta WHERE idTarjeta = @idTarjeta;
    SELECT 'SUSPENSION 3.3' AS momento, * FROM Eventos.Suspension WHERE idPartido = @idPartSeg AND idJugador = @idA10;
    IF EXISTS (SELECT 1 FROM Eventos.Tarjeta WHERE idTarjeta = @idTarjeta AND color = 'R' AND tipoRoja = 'Directa')
       AND EXISTS (SELECT 1 FROM Eventos.Suspension WHERE idPartido = @idPartSeg AND idJugador = @idA10
                   AND cantPartidos = 1 AND partidosRestantes = 1)
        PRINT '[OK] PRUEBA 3.3: Roja directa registrada con 1 partido de suspensión.';
    ELSE PRINT '[FALLO] PRUEBA 3.3: La roja directa o su suspensión no son las esperadas.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 3.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.4: Acumulación de amarillas en partidos distintos (2ª amarilla de A11, ahora en 99702)
-- Resultado esperado: Suspension de 1 partido generada en 99702 (ninguna en 99701).
BEGIN TRY
    EXEC Eventos.RegistrarTarjeta @idPartido = @idPartSeg, @idJugador = @idA11, @idPeriodo = 1, @color = 'A', @minuto = 40, @motivo = 'Protestar';
    SELECT 'SUSPENSION 3.4' AS momento, * FROM Eventos.Suspension WHERE idJugador = @idA11;
    IF EXISTS (SELECT 1 FROM Eventos.Suspension WHERE idPartido = @idPartSeg AND idJugador = @idA11
               AND cantPartidos = 1 AND partidosRestantes = 1)
       AND NOT EXISTS (SELECT 1 FROM Eventos.Suspension WHERE idPartido = @idPartJuego AND idJugador = @idA11)
        PRINT '[OK] PRUEBA 3.4: Acumulación de 2 amarillas genera 1 partido de suspensión.';
    ELSE PRINT '[FALLO] PRUEBA 3.4: La suspensión por acumulación no es la esperada.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 3.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.5: Partido inexistente
-- Resultado esperado: THROW 50002 "- El partido especificado no existe."
BEGIN TRY
    EXEC Eventos.RegistrarTarjeta @idPartido = -999, @idJugador = @idA02, @idPeriodo = 1, @color = 'A', @minuto = 10, @motivo = 'Juego brusco';
    PRINT '[FALLO] PRUEBA 3.5: No detectó el partido inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- El partido especificado no existe.%'
        PRINT '[OK] PRUEBA 3.5: Partido inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 3.5: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.6: Tarjeta en un partido programado (B01 en 99703, con formación registrada en 1.1)
-- Resultado esperado: THROW 50002 "- No se pueden registrar tarjetas en un partido que todavía se encuentra en estado programado."
BEGIN TRY
    EXEC Eventos.RegistrarTarjeta @idPartido = @idPartSig, @idJugador = @idB01, @idPeriodo = 1, @color = 'A', @minuto = 10, @motivo = 'Juego brusco';
    PRINT '[FALLO] PRUEBA 3.6: Permitió una tarjeta en un partido programado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- No se pueden registrar tarjetas en un partido que todavía se encuentra en estado programado.%'
        PRINT '[OK] PRUEBA 3.6: Tarjeta en partido programado rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 3.6: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.7: Jugador que no está en la formación del partido (A19, convocado pero no incluido)
-- Resultado esperado: THROW 50002 "- El jugador no está registrado en la formación del partido."
BEGIN TRY
    EXEC Eventos.RegistrarTarjeta @idPartido = @idPartJuego, @idJugador = @idA19, @idPeriodo = 1, @color = 'A', @minuto = 10, @motivo = 'Juego brusco';
    PRINT '[FALLO] PRUEBA 3.7: Permitió una tarjeta a un jugador fuera de la formación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- El jugador no está registrado en la formación del partido.%'
        PRINT '[OK] PRUEBA 3.7: Jugador fuera de la formación rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 3.7: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.8: Tarjeta a un jugador ya expulsado (A09, doble amarilla en 3.2)
-- Resultado esperado: THROW 50002 "- El jugador ya fue expulsado en este partido."
BEGIN TRY
    EXEC Eventos.RegistrarTarjeta @idPartido = @idPartJuego, @idJugador = @idA09, @idPeriodo = 2, @color = 'A', @minuto = 60, @motivo = 'Insultos';
    PRINT '[FALLO] PRUEBA 3.8: Permitió una tarjeta a un jugador expulsado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- El jugador ya fue expulsado en este partido.%'
        PRINT '[OK] PRUEBA 3.8: Tarjeta a jugador expulsado rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 3.8: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.9: Período inexistente
-- Resultado esperado: THROW 50002 "- El período de juego especificado no existe."
BEGIN TRY
    EXEC Eventos.RegistrarTarjeta @idPartido = @idPartJuego, @idJugador = @idA02, @idPeriodo = 99, @color = 'A', @minuto = 10, @motivo = 'Juego brusco';
    PRINT '[FALLO] PRUEBA 3.9: No detectó el período inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- El período de juego especificado no existe.%'
        PRINT '[OK] PRUEBA 3.9: Período inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 3.9: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.10: Color fuera del dominio ('X')
-- Resultado esperado: THROW 50002 "- El color de la tarjeta debe ser A (amarilla) o R (roja)."
BEGIN TRY
    EXEC Eventos.RegistrarTarjeta @idPartido = @idPartJuego, @idJugador = @idA02, @idPeriodo = 1, @color = 'X', @minuto = 10, @motivo = 'Juego brusco';
    PRINT '[FALLO] PRUEBA 3.10: Permitió un color inválido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- El color de la tarjeta debe ser A (amarilla) o R (roja).%'
        PRINT '[OK] PRUEBA 3.10: Color inválido rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 3.10: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.11: Minuto fuera de rango (121)
-- Resultado esperado: THROW 50002 "- El minuto de la tarjeta es obligatorio y debe encontrarse entre 0 y 120."
BEGIN TRY
    EXEC Eventos.RegistrarTarjeta @idPartido = @idPartJuego, @idJugador = @idA02, @idPeriodo = 2, @color = 'A', @minuto = 121, @motivo = 'Juego brusco';
    PRINT '[FALLO] PRUEBA 3.11: Permitió el minuto 121.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- El minuto de la tarjeta es obligatorio y debe encontrarse entre 0 y 120.%'
        PRINT '[OK] PRUEBA 3.11: Minuto 121 rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 3.11: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.12: Minuto adicional fuera de un minuto de cierre (30+2)
-- Resultado esperado: THROW 50002 "- El minuto adicional solo es válido en los minutos de cierre reglamentario (45, 90, 105 o 120)."
BEGIN TRY
    EXEC Eventos.RegistrarTarjeta @idPartido = @idPartJuego, @idJugador = @idA02, @idPeriodo = 1, @color = 'A',
         @minuto = 30, @minutoAdicional = 2, @motivo = 'Juego brusco';
    PRINT '[FALLO] PRUEBA 3.12: Permitió minuto adicional en el minuto 30.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- El minuto adicional solo es válido en los minutos de cierre reglamentario (45, 90, 105 o 120).%'
        PRINT '[OK] PRUEBA 3.12: Minuto adicional inválido rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 3.12: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.13: Motivo vacío (solo espacios)
-- Resultado esperado: THROW 50002 "- El motivo de la tarjeta es obligatorio."
BEGIN TRY
    EXEC Eventos.RegistrarTarjeta @idPartido = @idPartJuego, @idJugador = @idA02, @idPeriodo = 1, @color = 'A', @minuto = 10, @motivo = '   ';
    PRINT '[FALLO] PRUEBA 3.13: Permitió un motivo vacío.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- El motivo de la tarjeta es obligatorio.%'
        PRINT '[OK] PRUEBA 3.13: Motivo vacío rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 3.13: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.14: AMARILLAS_SUSPENSION en 0 (se pone en 0 y se repone en la misma prueba)
-- Resultado esperado: THROW 50002 "- El parámetro AMARILLAS_SUSPENSION no está configurado en Sistema.Parametro (o vale 0)."
UPDATE Sistema.Parametro SET valor = 0 WHERE clave = 'AMARILLAS_SUSPENSION';
BEGIN TRY
    EXEC Eventos.RegistrarTarjeta @idPartido = @idPartJuego, @idJugador = @idA02, @idPeriodo = 1, @color = 'A', @minuto = 10, @motivo = 'Juego brusco';
    PRINT '[FALLO] PRUEBA 3.14: No detectó AMARILLAS_SUSPENSION en 0.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- El parámetro AMARILLAS[_]SUSPENSION no está configurado en Sistema.Parametro (o vale 0).%'
        PRINT '[OK] PRUEBA 3.14: AMARILLAS_SUSPENSION en 0 informado.';
    ELSE PRINT '[FALLO] PRUEBA 3.14: ' + ERROR_MESSAGE();
END CATCH;
UPDATE Sistema.Parametro SET valor = 2 WHERE clave = 'AMARILLAS_SUSPENSION';

-- PRUEBA 3.15: 3 errores simultáneos (período inexistente, color inválido, motivo vacío)
-- Resultado esperado: THROW 50002 con los 3 mensajes juntos.
BEGIN TRY
    EXEC Eventos.RegistrarTarjeta @idPartido = @idPartJuego, @idJugador = @idA02, @idPeriodo = 99, @color = 'X', @minuto = 10, @motivo = '';
    PRINT '[FALLO] PRUEBA 3.15: No detectó los errores acumulados.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002
       AND ERROR_MESSAGE() LIKE N'%- El período de juego especificado no existe.%'
       AND ERROR_MESSAGE() LIKE N'%- El color de la tarjeta debe ser%'
       AND ERROR_MESSAGE() LIKE N'%- El motivo de la tarjeta es obligatorio.%'
        PRINT '[OK] PRUEBA 3.15: Acumulación de 3 errores verificada.';
    ELSE PRINT '[FALLO] PRUEBA 3.15: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   SECCIÓN 4: Arbitraje.DesignarCuerpoArbitral
   99703 = fase de grupos (orden 1); 99704 = dieciseisavos (orden 2). La
   selección C juega 99705 (dieciseisavos) y no perdió: sigue en competencia.
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 4. PRUEBAS: Arbitraje.DesignarCuerpoArbitral';
PRINT '--------------------------------------------------------------------------------';

DECLARE @idPartJuego int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99701);
DECLARE @idPartSig   int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99703);
DECLARE @idPartKO    int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99704);
DECLARE @idN1 int = (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'QNeg Arbitro N1');
DECLARE @idN2 int = (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'QNeg Arbitro N2');
DECLARE @idN3 int = (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'QNeg Arbitro N3');
DECLARE @idN4 int = (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'QNeg Arbitro N4');
DECLARE @idN5 int = (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'QNeg Arbitro N5');
DECLARE @idArbA int = (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'QNeg Arbitro A');
DECLARE @idArbC int = (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'QNeg Arbitro C');
DECLARE @advertencia nvarchar(2000);

-- PRUEBA 4.1: Designación exitosa en fase de grupos, con un VAR del país C (en competencia)
-- Resultado esperado: 5 filas en cuerpoArbitral y @advertencia NULL (en grupos no se advierte el cruce).
BEGIN TRY
    EXEC Arbitraje.DesignarCuerpoArbitral @idPartido = @idPartSig, @idPrincipal = @idN1, @idAsistente1 = @idN2, @idAsistente2 = @idN3,
         @idCuartoArbitro = @idN4, @idVar = @idArbC, @advertencia = @advertencia OUTPUT;
    SELECT 'DESIGNACION 4.1' AS momento, ca.rol, a.apellido, a.nombre
    FROM Arbitraje.cuerpoArbitral ca JOIN Arbitraje.Arbitro a ON a.idArbitro = ca.idArbitro
    WHERE ca.idPartido = @idPartSig ORDER BY ca.id;
    IF (SELECT COUNT(*) FROM Arbitraje.cuerpoArbitral WHERE idPartido = @idPartSig) = 5 AND @advertencia IS NULL
        PRINT '[OK] PRUEBA 4.1: Cuerpo arbitral designado sin advertencia en fase de grupos.';
    ELSE PRINT '[FALLO] PRUEBA 4.1: Designación incompleta o advertencia inesperada: ' + ISNULL(@advertencia, N'(sin advertencia)');
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 4.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.2: Partido inexistente
-- Resultado esperado: THROW 50002 "- El partido especificado no existe."
BEGIN TRY
    EXEC Arbitraje.DesignarCuerpoArbitral @idPartido = -999, @idPrincipal = @idN1, @idAsistente1 = @idN2, @idAsistente2 = @idN3,
         @idCuartoArbitro = @idN4, @idVar = @idN5;
    PRINT '[FALLO] PRUEBA 4.2: No detectó el partido inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- El partido especificado no existe.%'
        PRINT '[OK] PRUEBA 4.2: Partido inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 4.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.3: Partido que no está programado (99701 'En juego')
-- Resultado esperado: THROW 50002 "- Solo se puede designar el cuerpo arbitral de un partido programado."
BEGIN TRY
    EXEC Arbitraje.DesignarCuerpoArbitral @idPartido = @idPartJuego, @idPrincipal = @idN1, @idAsistente1 = @idN2, @idAsistente2 = @idN3,
         @idCuartoArbitro = @idN4, @idVar = @idN5;
    PRINT '[FALLO] PRUEBA 4.3: Permitió designar árbitros en un partido en juego.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- Solo se puede designar el cuerpo arbitral de un partido programado.%'
        PRINT '[OK] PRUEBA 4.3: Designación en partido no programado rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 4.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.4: Partido que ya tiene árbitros designados (99703, designado en 4.1)
-- Resultado esperado: THROW 50002 "- El partido ya tiene árbitros designados."
BEGIN TRY
    EXEC Arbitraje.DesignarCuerpoArbitral @idPartido = @idPartSig, @idPrincipal = @idN1, @idAsistente1 = @idN2, @idAsistente2 = @idN3,
         @idCuartoArbitro = @idN4, @idVar = @idN5;
    PRINT '[FALLO] PRUEBA 4.4: Permitió una segunda designación para el mismo partido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- El partido ya tiene árbitros designados.%'
        PRINT '[OK] PRUEBA 4.4: Segunda designación rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 4.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.5: Roles sin designar (Cuarto Arbitro y VAR en NULL)
-- Resultado esperado: THROW 50002 "- Faltan designar los roles: Cuarto Arbitro, VAR."
BEGIN TRY
    EXEC Arbitraje.DesignarCuerpoArbitral @idPartido = @idPartKO, @idPrincipal = @idN1, @idAsistente1 = @idN2, @idAsistente2 = @idN3,
         @idCuartoArbitro = NULL, @idVar = NULL;
    PRINT '[FALLO] PRUEBA 4.5: Permitió una designación incompleta.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- Faltan designar los roles: Cuarto Arbitro, VAR.%'
        PRINT '[OK] PRUEBA 4.5: Roles faltantes informados.';
    ELSE PRINT '[FALLO] PRUEBA 4.5: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.6: Árbitro inexistente (VAR = -999)
-- Resultado esperado: THROW 50002 "- No existen los árbitros con id: -999."
BEGIN TRY
    EXEC Arbitraje.DesignarCuerpoArbitral @idPartido = @idPartKO, @idPrincipal = @idN1, @idAsistente1 = @idN2, @idAsistente2 = @idN3,
         @idCuartoArbitro = @idN4, @idVar = -999;
    PRINT '[FALLO] PRUEBA 4.6: No detectó el árbitro inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- No existen los árbitros con id: -999.%'
        PRINT '[OK] PRUEBA 4.6: Árbitro inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 4.6: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.7: Un mismo árbitro en dos roles (N1 como Principal y VAR)
-- Resultado esperado: THROW 50002 "- Un mismo árbitro no puede cumplir más de un rol en el partido."
BEGIN TRY
    EXEC Arbitraje.DesignarCuerpoArbitral @idPartido = @idPartKO, @idPrincipal = @idN1, @idAsistente1 = @idN2, @idAsistente2 = @idN3,
         @idCuartoArbitro = @idN4, @idVar = @idN1;
    PRINT '[FALLO] PRUEBA 4.7: Permitió un árbitro en dos roles.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE N'%- Un mismo árbitro no puede cumplir más de un rol en el partido.%'
        PRINT '[OK] PRUEBA 4.7: Árbitro en dos roles rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 4.7: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.8 (CASO OBLIGATORIO 4): Designación rechazada por conflicto de nacionalidad
--             (Principal del país A en el partido A-B)
-- Resultado esperado: THROW 50002 "- El árbitro QNeg Arbitro A, Local (Principal) es de Pais Negocio A, que disputa el partido."
BEGIN TRY
    EXEC Arbitraje.DesignarCuerpoArbitral @idPartido = @idPartKO, @idPrincipal = @idArbA, @idAsistente1 = @idN2, @idAsistente2 = @idN3,
         @idCuartoArbitro = @idN4, @idVar = @idN5;
    PRINT '[FALLO] PRUEBA 4.8: Permitió un árbitro del mismo país que una de las selecciones.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002
       AND ERROR_MESSAGE() LIKE N'%- El árbitro QNeg Arbitro A, Local (Principal) es de Pais Negocio A, que disputa el partido.%'
        PRINT '[OK] PRUEBA 4.8: Conflicto de nacionalidad rechazado con THROW 50002.';
    ELSE PRINT '[FALLO] PRUEBA 4.8: ' + CAST(ERROR_NUMBER() AS varchar(10)) + ' - ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.9: 3 errores simultáneos (Asistente 2 sin designar, VAR inexistente, N1 en dos roles)
-- Resultado esperado: THROW 50002 con los 3 mensajes juntos.
BEGIN TRY
    EXEC Arbitraje.DesignarCuerpoArbitral @idPartido = @idPartKO, @idPrincipal = @idN1, @idAsistente1 = @idN2, @idAsistente2 = NULL,
         @idCuartoArbitro = @idN1, @idVar = -999;
    PRINT '[FALLO] PRUEBA 4.9: No detectó los errores acumulados.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002
       AND ERROR_MESSAGE() LIKE N'%- Faltan designar los roles: Asistente 2.%'
       AND ERROR_MESSAGE() LIKE N'%- No existen los árbitros con id: -999.%'
       AND ERROR_MESSAGE() LIKE N'%- Un mismo árbitro no puede cumplir más de un rol%'
        PRINT '[OK] PRUEBA 4.9: Acumulación de 3 errores verificada.';
    ELSE PRINT '[FALLO] PRUEBA 4.9: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.10: Designación en dieciseisavos con un VAR del país C (C sigue en competencia)
-- Resultado esperado: 5 filas en cuerpoArbitral y @advertencia con la advertencia de cruce del VAR.
SET @advertencia = NULL;
BEGIN TRY
    EXEC Arbitraje.DesignarCuerpoArbitral @idPartido = @idPartKO, @idPrincipal = @idN1, @idAsistente1 = @idN2, @idAsistente2 = @idN3,
         @idCuartoArbitro = @idN4, @idVar = @idArbC, @advertencia = @advertencia OUTPUT;
    SELECT 'DESIGNACION 4.10' AS momento, ca.rol, a.apellido, a.nombre
    FROM Arbitraje.cuerpoArbitral ca JOIN Arbitraje.Arbitro a ON a.idArbitro = ca.idArbitro
    WHERE ca.idPartido = @idPartKO ORDER BY ca.id;
    SELECT 'ADVERTENCIA 4.10' AS momento, @advertencia AS advertencia;
    IF (SELECT COUNT(*) FROM Arbitraje.cuerpoArbitral WHERE idPartido = @idPartKO) = 5
       AND @advertencia = N'Advertencia: el árbitro QNeg Arbitro C, Rival (VAR) es de Pais Negocio C, cuya selección sigue en competencia y podría cruzarse con las selecciones de este partido.'
        PRINT '[OK] PRUEBA 4.10: Designación aceptada con advertencia de cruce.';
    ELSE PRINT '[FALLO] PRUEBA 4.10: Designación incompleta o advertencia inesperada: ' + ISNULL(@advertencia, N'(sin advertencia)');
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 4.10: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   SECCIÓN 5: Cumplimiento de la suspensión en el partido siguiente
   Las tarjetas de la sección 3 dejaron suspendidos (1 partido) a A09 (doble
   amarilla en 99701), A10 (roja directa en 99702) y A11 (acumulación en
   99702). El partido siguiente de A es 99703.
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 5. PRUEBAS: Suspensión cumplida en el partido siguiente (RegistrarFormacion)';
PRINT '--------------------------------------------------------------------------------';

DECLARE @idPartSig int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99703);
DECLARE @idSelA int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'QNA');
DECLARE @idA09 int = (SELECT id FROM #jug WHERE codigo = 'A09');
DECLARE @idA10 int = (SELECT id FROM #jug WHERE codigo = 'A10');
DECLARE @idA11 int = (SELECT id FROM #jug WHERE codigo = 'A11');
DECLARE @lista Eventos.FormacionJugadorLista;
DECLARE @esperado nvarchar(400);

-- PRUEBA 5.1 (CASO OBLIGATORIO 2): Suspendido por acumulación (A11) rechazado como titular en el partido siguiente
--             Titulares A01-A08, A11, A12, A13; suplentes A14-A18.
-- Resultado esperado: THROW 50002 "- Los siguientes jugadores están suspendidos y no pueden integrar la formación: <id A11>."
INSERT INTO @lista
SELECT id, CASE WHEN nro <= 8 OR nro IN (11, 12, 13) THEN 1 ELSE 0 END, posicion
FROM #jug WHERE sel = 'A' AND (nro <= 8 OR nro BETWEEN 11 AND 18);
SET @esperado = N'%- Los siguientes jugadores están suspendidos y no pueden integrar la formación: ' + CAST(@idA11 AS nvarchar(12)) + N'.%';
BEGIN TRY
    EXEC Eventos.RegistrarFormacion @idPartido = @idPartSig, @idSeleccion = @idSelA, @jugadores = @lista;
    PRINT '[FALLO] PRUEBA 5.1: Permitió como titular a un jugador suspendido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE @esperado
        PRINT '[OK] PRUEBA 5.1: Suspendido por acumulación rechazado como titular.';
    ELSE PRINT '[FALLO] PRUEBA 5.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 5.2: Formación de A sin los suspendidos (A14 reemplaza a A11) y con esquema '3-4-1-1-1' (5 líneas: antes se rechazaba)
-- Resultado esperado: Formación registrada, esquemaLocal = '3-4-1-1-1' (y esquemaVisitante sigue
--                     en '4-4-2', el de la prueba 1.1: no se pisa el esquema del rival) y las
--                     suspensiones de A09, A10 y A11 pasan de 1 a 0 partidos restantes.
DELETE FROM @lista;
INSERT INTO @lista
SELECT id, CASE WHEN nro <= 8 OR nro IN (12, 13, 14) THEN 1 ELSE 0 END, posicion
FROM #jug WHERE sel = 'A' AND (nro <= 8 OR nro BETWEEN 12 AND 18);
BEGIN TRY
    SELECT 'ANTES 5.2' AS momento, idPartido, idJugador, cantPartidos, partidosRestantes
    FROM Eventos.Suspension WHERE idJugador IN (@idA09, @idA10, @idA11) ORDER BY idJugador;
    EXEC Eventos.RegistrarFormacion @idPartido = @idPartSig, @idSeleccion = @idSelA, @jugadores = @lista, @esquema = '3-4-1-1-1';
    SELECT 'DESPUES 5.2' AS momento, idPartido, idJugador, cantPartidos, partidosRestantes
    FROM Eventos.Suspension WHERE idJugador IN (@idA09, @idA10, @idA11) ORDER BY idJugador;
    SELECT 'PARTIDO 5.2' AS momento, idPartido, esquemaLocal, esquemaVisitante FROM Torneo.Partido WHERE idPartido = @idPartSig;
    IF (SELECT COUNT(*) FROM Eventos.FormacionPartido WHERE idPartido = @idPartSig AND idSeleccion = @idSelA) = 15
       AND EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartSig AND esquemaLocal = '3-4-1-1-1' AND esquemaVisitante = '4-4-2')
       AND (SELECT COUNT(*) FROM Eventos.Suspension
            WHERE idJugador IN (@idA09, @idA10, @idA11) AND cantPartidos = 1 AND partidosRestantes = 0) = 3
        PRINT '[OK] PRUEBA 5.2: Formación registrada, ambos esquemas cargados y suspensiones de A09, A10 y A11 cumplidas.';
    ELSE PRINT '[FALLO] PRUEBA 5.2: La formación, el esquema o las suspensiones no quedaron como se esperaba.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 5.2: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   LIMPIEZA FINAL DEL ENTORNO DE PRUEBAS
   ============================================================================= */
PRINT '--- Limpiando fixture auxiliar de pruebas ---';

DELETE FROM Arbitraje.InformeArbitral WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99701, 99702, 99703, 99704, 99705));
DELETE FROM Arbitraje.cuerpoArbitral  WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99701, 99702, 99703, 99704, 99705))
                                         OR idArbitro IN (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido LIKE N'QNeg Arbitro %');
DELETE FROM Eventos.Gol               WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99701, 99702, 99703, 99704, 99705));
DELETE FROM Eventos.Tarjeta           WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99701, 99702, 99703, 99704, 99705));
DELETE FROM Eventos.Sustitucion       WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99701, 99702, 99703, 99704, 99705));
DELETE FROM Eventos.Suspension        WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99701, 99702, 99703, 99704, 99705))
                                         OR idJugador IN (SELECT id FROM Equipos.Jugador WHERE apellido LIKE N'QNeg Jugador %');
DELETE FROM Eventos.FormacionPartido  WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99701, 99702, 99703, 99704, 99705));
DELETE FROM Torneo.Partido WHERE nroPartidoOficial IN (99701, 99702, 99703, 99704, 99705);
DELETE FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test Negocio';
DELETE FROM Torneo.Fase WHERE idFase IN (9901, 9902);
DELETE FROM Arbitraje.Arbitro WHERE apellido LIKE N'QNeg Arbitro %';
DELETE FROM Equipos.ListadoJugadores WHERE idJugador IN (SELECT id FROM Equipos.Jugador WHERE apellido LIKE N'QNeg Jugador %');
DELETE FROM Equipos.Jugador WHERE apellido LIKE N'QNeg Jugador %';
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('QNA', 'QNB', 'QNC');
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('Q1', 'Q2', 'Q3', 'Q4');

-- Períodos: solo los que insertó este script (ya no quedan eventos que los referencien)
IF OBJECT_ID('tempdb..#periodosCreados') IS NOT NULL
BEGIN
    DELETE FROM Torneo.Periodo WHERE idPeriodo IN (SELECT idPeriodo FROM #periodosCreados);
    DROP TABLE #periodosCreados;
END;

-- Parámetros: se restaura el valor original o se borra la clave si no existía
IF OBJECT_ID('tempdb..#parametrosOriginales') IS NOT NULL
BEGIN
    UPDATE p SET valor = o.valorOriginal
    FROM Sistema.Parametro p
    JOIN #parametrosOriginales o ON o.clave = p.clave
    WHERE o.existia = 1;

    DELETE p
    FROM Sistema.Parametro p
    JOIN #parametrosOriginales o ON o.clave = p.clave
    WHERE o.existia = 0;

    DROP TABLE #parametrosOriginales;
END;

IF OBJECT_ID('tempdb..#jug') IS NOT NULL DROP TABLE #jug;

PRINT 'Fixture de pruebas limpiado con éxito.';
PRINT '================================================================================';
PRINT ' BATERÍA DE PRUEBAS DE NEGOCIO FINALIZADA: 62 pruebas';
PRINT '   1. RegistrarFormacion: 15 | 2. RegistrarCambio: 20 | 3. RegistrarTarjeta: 15';
PRINT '   4. DesignarCuerpoArbitral: 10 | 5. Suspensión en el partido siguiente: 2';
PRINT '================================================================================';
GO
