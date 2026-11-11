/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel - 45066788
               Salas, Martin Daniel - 45205702
               Zito Padró, Ezequiel Nehuén - 46097917
 Fecha       : 09/11/2026

 Objetivo    : Suite de pruebas unitarias para 22_Negocio_Publicidad.sql
               (SP Publicidad.AsignarPiezasPartido).
               Verifica la lógica transaccional de negocio, control de estados,
               límite de espacios (MAX_ESPACIOS_PARTIDO), las condiciones sin
               tarifas o sin candidatas y la aplicación de los 3 criterios de
               priorización: qué piezas se asignan, con qué criterio y en qué
               orden.

 Estándares aplicados:
 - Relación 1:1 con 22_Negocio_Publicidad.sql.
 - Autocontenida: crea sus propios países, selecciones, campañas, piezas,
   ubicaciones, tarifas y partidos. No depende de 52_CargaPublicidad.sql.
 - Solo usa códigos y números de uso exclusivo de la prueba (países XR a XW,
   ubicaciones 95 a 98, fases 995 y 997, partidos 99701 a 99705): los códigos
   ISO que empiezan con X son de asignación privada y no chocan con países
   reales.
 - Los partidos y las campañas son de 2030: así no hay campañas reales
   vigentes (como las de 52) que compitan por los espacios y el resultado no
   depende de los datos cargados.
 - Idempotencia absoluta con limpieza preventiva y final.
 - Validación de errores de negocio (código THROW 50002).
 - Evidencia con SELECT antes y después en casos de éxito.
 - Requiere 12_ABM_Publicidad.sql y 22_Negocio_Publicidad.sql.
================================================================================
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

PRINT '================================================================================';
PRINT ' INICIANDO BATERÍA DE PRUEBAS: 22_Negocio_Publicidad.sql';
PRINT '================================================================================';
GO

/* =============================================================================
   PREPARACIÓN DEL ENTORNO DE PRUEBAS
   ============================================================================= */
PRINT '--- Limpieza preventiva de pruebas anteriores ---';

DELETE FROM Publicidad.ExhibicionPublicitaria
WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 99701 AND 99705);

DELETE FROM Publicidad.PiezaMercado
WHERE idPieza IN (SELECT id FROM Publicidad.PiezaContenido WHERE descripcion LIKE 'Test Neg Pieza%');
DELETE FROM Publicidad.PiezaContenido WHERE descripcion LIKE 'Test Neg Pieza%';
DELETE FROM Publicidad.Campania WHERE nombre LIKE 'Test Neg Campania%';
DELETE FROM Publicidad.Anunciante WHERE nombre LIKE 'Test Neg Anunciante%';
DELETE FROM Publicidad.Tarifa WHERE idFase IN (995, 997);
DELETE FROM Publicidad.UbicacionPublicitaria WHERE idUbicacion BETWEEN 95 AND 98;
DELETE FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 99701 AND 99705;
DELETE FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test Negocio';
DELETE FROM Torneo.Fase WHERE idFase IN (995, 997);
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('TNA', 'TNB');
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('XR', 'XS', 'XT', 'XU', 'XV', 'XW');
GO

PRINT '--- Creando datos auxiliares de prueba ---';

-- Países. XR (local) y XS (visitante) juegan el partido. El resto son mercados.
--   Partido 99701: 2030-06-25 18:00 UTC. Hora local y prime time (19 a 23):
--     XR 'Argentina Standard Time'  → 15:00  no
--     XS 'W. Europe Standard Time'  → 20:00  sí
--     XT 'Romance Standard Time'    → 20:00  sí
--     XU 'Tokyo Standard Time'      → 03:00  no
--     XV 'Tokyo Standard Time'      → 03:00  no
--     XW 'Romance Standard Time'    → 20:00  sí
INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3, husoHorario, pbiPerCapita)
VALUES ('Pais Test Negocio R', 'XR', 'TXR', 'Argentina Standard Time', 12000),
       ('Pais Test Negocio S', 'XS', 'TXS', 'W. Europe Standard Time', 50000),
       ('Pais Test Negocio T', 'XT', 'TXT', 'Romance Standard Time',    30000),
       ('Pais Test Negocio U', 'XU', 'TXU', 'Tokyo Standard Time',      42000),
       ('Pais Test Negocio V', 'XV', 'TXV', 'Tokyo Standard Time',      NULL),
       ('Pais Test Negocio W', 'XW', 'TXW', 'Romance Standard Time',    NULL);

DECLARE @idPaisXR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XR');
DECLARE @idPaisXS int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XS');
DECLARE @idPaisXT int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XT');
DECLARE @idPaisXU int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XU');
DECLARE @idPaisXV int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XV');
DECLARE @idPaisXW int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XW');

-- Selecciones de los dos países que juegan
INSERT INTO Equipos.Seleccion (idPais, abreviacion, confederacion)
VALUES (@idPaisXR, 'TNA', 'CONMEBOL'),
       (@idPaisXS, 'TNB', 'UEFA');

DECLARE @idSelNA int = (SELECT id FROM Equipos.Seleccion WHERE idPais = @idPaisXR);
DECLARE @idSelNB int = (SELECT id FROM Equipos.Seleccion WHERE idPais = @idPaisXS);

-- Fases: 997 con tarifas y 995 sin tarifas
INSERT INTO Torneo.Fase (idFase, nombre, esEliminatoria, orden)
VALUES (997, 'Fase Test Negocio', 0, 97),
       (995, 'Fase Test Negocio Sin Tarifa', 0, 95);

INSERT INTO Torneo.Sede (nombreEstadio, ciudad, idPais, husoHorario)
VALUES ('Estadio Test Negocio', 'Ciudad Test Negocio', @idPaisXR, 'Argentina Standard Time');

DECLARE @idSedeNegocio int = (SELECT idSede FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test Negocio');

-- Ubicaciones propias de la prueba (95 a 98) y tarifas de la fase 997
INSERT INTO Publicidad.UbicacionPublicitaria (idUbicacion, nombre)
VALUES (95, 'Test Neg Ubicacion 1'),
       (96, 'Test Neg Ubicacion 2'),
       (97, 'Test Neg Ubicacion 3'),
       (98, 'Test Neg Ubicacion 4');

INSERT INTO Publicidad.Tarifa (idFase, idUbicacion, montoUSD)
VALUES (997, 95, 40000.00),
       (997, 96, 30000.00),
       (997, 97, 30000.00),
       (997, 98, 60000.00);

-- Partidos de prueba
--   99701 Programado, 2030-06-25 18:00 UTC: caso con más de 4 candidatas
--   99702 Finalizado
--   99703 Programado, 2030-06-27 18:00 UTC: solo quedan vigentes las piezas B
--   99704 Programado, 2030-08-15: no hay ninguna campaña vigente
--   99705 Programado, fase 995: la fase no tiene tarifas
INSERT INTO Torneo.Partido (nroPartidoOficial, idSede, idSeleccionLocal, idSeleccionVisitante, fase, fechaHoraUTC, estado, golLocal, golVisitante)
VALUES (99701, @idSedeNegocio, @idSelNA, @idSelNB, 997, '2030-06-25 18:00:00', 'Programado', NULL, NULL),
       (99702, @idSedeNegocio, @idSelNA, @idSelNB, 997, '2030-06-24 18:00:00', 'Finalizado', 2, 1),
       (99703, @idSedeNegocio, @idSelNA, @idSelNB, 997, '2030-06-27 18:00:00', 'Programado', NULL, NULL),
       (99704, @idSedeNegocio, @idSelNA, @idSelNB, 997, '2030-08-15 18:00:00', 'Programado', NULL, NULL),
       (99705, @idSedeNegocio, @idSelNA, @idSelNB, 995, '2030-06-25 18:00:00', 'Programado', NULL, NULL);

-- Anunciante, campañas y piezas con sus mercados (a través de los SP de 12_ABM_Publicidad.sql)
--   Campaña A: vigente hasta el 2030-06-25 inclusive (piezas 1 a 4)
--   Campaña B: vigente hasta el 2030-07-31 (piezas 5 y 6)
EXEC Publicidad.Anunciante_Alta @nombre = N'Test Neg Anunciante', @idPais = @idPaisXS;
DECLARE @idAnunciante int = (SELECT id FROM Publicidad.Anunciante WHERE nombre = N'Test Neg Anunciante');

EXEC Publicidad.Campania_Alta @idAnunciante = @idAnunciante, @nombre = N'Test Neg Campania A', @fechaInicio = '2030-06-01', @fechaFin = '2030-06-25';
EXEC Publicidad.Campania_Alta @idAnunciante = @idAnunciante, @nombre = N'Test Neg Campania B', @fechaInicio = '2030-06-01', @fechaFin = '2030-07-31';
DECLARE @idCampA int = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Test Neg Campania A');
DECLARE @idCampB int = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Test Neg Campania B');

EXEC Publicidad.PiezaContenido_Alta @idCampania = @idCampA, @descripcion = N'Test Neg Pieza Local',         @idioma = 'es';
EXEC Publicidad.PiezaContenido_Alta @idCampania = @idCampA, @descripcion = N'Test Neg Pieza Visitante',     @idioma = 'es';
EXEC Publicidad.PiezaContenido_Alta @idCampania = @idCampA, @descripcion = N'Test Neg Pieza Pbi Medio',     @idioma = 'es';
EXEC Publicidad.PiezaContenido_Alta @idCampania = @idCampA, @descripcion = N'Test Neg Pieza Pbi Alto',      @idioma = 'es';
EXEC Publicidad.PiezaContenido_Alta @idCampania = @idCampB, @descripcion = N'Test Neg Pieza Sin Criterio',  @idioma = 'es';
EXEC Publicidad.PiezaContenido_Alta @idCampania = @idCampB, @descripcion = N'Test Neg Pieza Prime Time',    @idioma = 'es';

--   Local     → mercado XR (juega, criterio 1, PBI 12000)
--   Visitante → mercado XS (juega, criterio 1, PBI 50000)
--   Pbi Medio → mercado XT (PBI 30000, criterio 2)
--   Pbi Alto  → mercado XU (PBI 42000, criterio 2)
--   Sin Crit. → mercado XV (sin PBI, no juega, fuera de prime time: no cumple ninguno)
--   Prime Time→ mercado XW (sin PBI, no juega, en prime time: criterio 3)
DECLARE @idPz1 int = (SELECT id FROM Publicidad.PiezaContenido WHERE descripcion = N'Test Neg Pieza Local');
DECLARE @idPz2 int = (SELECT id FROM Publicidad.PiezaContenido WHERE descripcion = N'Test Neg Pieza Visitante');
DECLARE @idPz3 int = (SELECT id FROM Publicidad.PiezaContenido WHERE descripcion = N'Test Neg Pieza Pbi Medio');
DECLARE @idPz4 int = (SELECT id FROM Publicidad.PiezaContenido WHERE descripcion = N'Test Neg Pieza Pbi Alto');
DECLARE @idPz5 int = (SELECT id FROM Publicidad.PiezaContenido WHERE descripcion = N'Test Neg Pieza Sin Criterio');
DECLARE @idPz6 int = (SELECT id FROM Publicidad.PiezaContenido WHERE descripcion = N'Test Neg Pieza Prime Time');

EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPz1, @idPais = @idPaisXR;
EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPz2, @idPais = @idPaisXS;
EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPz3, @idPais = @idPaisXT;
EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPz4, @idPais = @idPaisXU;
EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPz5, @idPais = @idPaisXV;
EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPz6, @idPais = @idPaisXW;

PRINT 'Fixture de pruebas de negocio inicializado con éxito.';
PRINT '';
GO

/* =============================================================================
   CASOS DE PRUEBA
   ============================================================================= */

-- PRUEBA 1: Error al intentar asignar a un partido inexistente
BEGIN TRY
    EXEC Publicidad.AsignarPiezasPartido @idPartido = 999999;
    PRINT '[FALLO] PRUEBA 1: No detectó partido inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE '%no existe%'
        PRINT '[OK] PRUEBA 1: Error partido inexistente capturado correctamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 1: Error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 2: Error al intentar asignar a un partido en estado 'Finalizado'
BEGIN TRY
    DECLARE @idPartidoFinalizado int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99702);
    EXEC Publicidad.AsignarPiezasPartido @idPartido = @idPartidoFinalizado;
    PRINT '[FALLO] PRUEBA 2: Permitió asignar piezas a un partido Finalizado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE '%Solo se permite asignar en Programado o En juego%'
        PRINT '[OK] PRUEBA 2: Error estado inválido capturado correctamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 2: Error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3: Asignación automática con 5 candidatas para 4 espacios: se verifica qué piezas,
--           con qué criterio y en qué ubicación quedan asignadas
--   Orden esperado: criterio 1 por PBI (Visitante 50000, Local 12000), luego criterio 2 por PBI
--   (Pbi Alto 42000, Pbi Medio 30000). La pieza de criterio 3 (Prime Time) queda afuera por el
--   límite de 4 y la pieza Sin Criterio no es candidata.
BEGIN TRY
    DECLARE @idPartidoProgramado int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99701);

    PRINT 'Evidencia previa (exhibiciones antes de asignar):';
    SELECT COUNT(*) AS cantExhibicionesPrevias FROM Publicidad.ExhibicionPublicitaria WHERE idPartido = @idPartidoProgramado;

    EXEC Publicidad.AsignarPiezasPartido @idPartido = @idPartidoProgramado;

    PRINT 'Detalle de exhibiciones asignadas con sus criterios y montos de tarifa:';
    SELECT ep.idPartido, ep.idUbicacion, u.nombre AS ubicacion, ep.idPieza, pc.descripcion AS pieza,
           ep.criterioAplicado, ep.estado, ep.montoUSD
    FROM Publicidad.ExhibicionPublicitaria ep
    JOIN Publicidad.UbicacionPublicitaria  u  ON u.idUbicacion = ep.idUbicacion
    JOIN Publicidad.PiezaContenido        pc ON pc.id = ep.idPieza
    WHERE ep.idPartido = @idPartidoProgramado
    ORDER BY ep.idUbicacion;

    DECLARE @detalleObtenido nvarchar(400) = (
        SELECT STRING_AGG(CONCAT(ep.idUbicacion, N':', pc.descripcion, N':', ep.criterioAplicado), N' | ')
               WITHIN GROUP (ORDER BY ep.idUbicacion)
        FROM Publicidad.ExhibicionPublicitaria ep
        JOIN Publicidad.PiezaContenido        pc ON pc.id = ep.idPieza
        WHERE ep.idPartido = @idPartidoProgramado
    );
    DECLARE @detalleEsperado nvarchar(400) =
          N'95:Test Neg Pieza Visitante:1 | 96:Test Neg Pieza Local:1'
        + N' | 97:Test Neg Pieza Pbi Alto:2 | 98:Test Neg Pieza Pbi Medio:2';

    IF @detalleObtenido = @detalleEsperado
        PRINT '[OK] PRUEBA 3: Asignó las 4 piezas esperadas, con su criterio y ubicación (1, 1, 2, 2 por PBI).';
    ELSE
        PRINT '[FALLO] PRUEBA 3: Asignación distinta de la esperada -> ' + ISNULL(@detalleObtenido, N'(sin exhibiciones)');

    IF NOT EXISTS (
        SELECT 1
        FROM Publicidad.ExhibicionPublicitaria ep
        JOIN Publicidad.PiezaContenido pc ON pc.id = ep.idPieza
        WHERE ep.idPartido = @idPartidoProgramado
          AND pc.descripcion IN (N'Test Neg Pieza Sin Criterio', N'Test Neg Pieza Prime Time')
    )
        PRINT '[OK] PRUEBA 3b: La pieza sin criterio y la de criterio 3 (sin lugar) no fueron asignadas.';
    ELSE
        PRINT '[FALLO] PRUEBA 3b: Se asignó una pieza que no correspondía.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 3: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 4: Error al intentar asignar nuevamente a un partido que ya tiene el máximo de 4 piezas
BEGIN TRY
    DECLARE @idPartidoProgramado int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99701);
    EXEC Publicidad.AsignarPiezasPartido @idPartido = @idPartidoProgramado;
    PRINT '[FALLO] PRUEBA 4: Permitió sobreasignar piezas superando el máximo de 4.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE '%ya tiene el máximo%'
        PRINT '[OK] PRUEBA 4: Error partido con máximo de piezas capturado correctamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 4: Error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 5: Criterio 3 solo se etiqueta cuando se cumple
--   En el partido 99703 la campaña A ya no está vigente: quedan las piezas Prime Time (mercado
--   en prime time, sin PBI) y Sin Criterio (no cumple nada). Solo se asigna la primera, con criterio 3.
BEGIN TRY
    DECLARE @idPartidoB int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99703);

    EXEC Publicidad.AsignarPiezasPartido @idPartido = @idPartidoB;

    PRINT 'Detalle de exhibiciones asignadas al partido 99703:';
    SELECT ep.idPartido, ep.idUbicacion, ep.idPieza, pc.descripcion AS pieza, ep.criterioAplicado, ep.montoUSD
    FROM Publicidad.ExhibicionPublicitaria ep
    JOIN Publicidad.PiezaContenido        pc ON pc.id = ep.idPieza
    WHERE ep.idPartido = @idPartidoB;

    IF (SELECT COUNT(*) FROM Publicidad.ExhibicionPublicitaria WHERE idPartido = @idPartidoB) = 1
       AND EXISTS (
            SELECT 1
            FROM Publicidad.ExhibicionPublicitaria ep
            JOIN Publicidad.PiezaContenido pc ON pc.id = ep.idPieza
            WHERE ep.idPartido = @idPartidoB
              AND pc.descripcion = N'Test Neg Pieza Prime Time'
              AND ep.criterioAplicado = 3
       )
        PRINT '[OK] PRUEBA 5: Asignó solo la pieza en prime time, con criterio 3; la pieza sin criterio quedó afuera.';
    ELSE
        PRINT '[FALLO] PRUEBA 5: La asignación no fue la esperada (1 pieza de prime time con criterio 3).';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 5: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 6: Error cuando no hay piezas candidatas (ninguna campaña vigente el día del partido)
BEGIN TRY
    DECLARE @idPartidoSinCand int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99704);
    EXEC Publicidad.AsignarPiezasPartido @idPartido = @idPartidoSinCand;
    PRINT '[FALLO] PRUEBA 6: Terminó sin error aunque no había piezas candidatas.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE '%No hay piezas candidatas%'
        PRINT '[OK] PRUEBA 6: Error sin piezas candidatas capturado correctamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 6: Error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 7: Error cuando la fase del partido no tiene tarifas
BEGIN TRY
    DECLARE @idPartidoSinTarifa int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99705);
    EXEC Publicidad.AsignarPiezasPartido @idPartido = @idPartidoSinTarifa;
    PRINT '[FALLO] PRUEBA 7: Terminó sin error aunque la fase no tiene tarifas.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 AND ERROR_MESSAGE() LIKE '%no tiene tarifas cargadas%'
        PRINT '[OK] PRUEBA 7: Error fase sin tarifas capturado correctamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 7: Error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 8: Funciones Publicidad.fn_HoraLocal y Publicidad.fn_EsPrimeTime
--   Partido de referencia: 2030-06-25 18:00 UTC (horario de verano europeo).
--   Con PRIME_TIME_INICIO = 19 y PRIME_TIME_FIN = 23 (valores por defecto si no hay parámetros).
BEGIN TRY
    DECLARE @utc datetime2(0) = '2030-06-25 18:00:00';
    DECLARE @inicio int = (SELECT valor FROM Sistema.Parametro WHERE clave = 'PRIME_TIME_INICIO');
    DECLARE @fin    int = (SELECT valor FROM Sistema.Parametro WHERE clave = 'PRIME_TIME_FIN');

    IF ISNULL(@inicio, 19) = 19 AND ISNULL(@fin, 23) = 23
    BEGIN
        SELECT Publicidad.fn_HoraLocal(@utc, 'Romance Standard Time')       AS horaRomance,
               Publicidad.fn_HoraLocal(@utc, 'Argentina Standard Time')     AS horaArgentina,
               Publicidad.fn_HoraLocal(@utc, NULL)                          AS horaSinHuso,
               Publicidad.fn_EsPrimeTime(@utc, 'Romance Standard Time')     AS primeRomance,
               Publicidad.fn_EsPrimeTime(@utc, 'GMT Standard Time')         AS primeGmt,
               Publicidad.fn_EsPrimeTime(@utc, 'Argentina Standard Time')   AS primeArgentina,
               Publicidad.fn_EsPrimeTime(@utc, 'Tokyo Standard Time')       AS primeTokyo,
               Publicidad.fn_EsPrimeTime(@utc, NULL)                        AS primeSinHuso;

        IF Publicidad.fn_HoraLocal(@utc, 'Romance Standard Time') = '2030-06-25 20:00:00'
           AND Publicidad.fn_HoraLocal(@utc, 'Argentina Standard Time') = '2030-06-25 15:00:00'
           AND Publicidad.fn_HoraLocal(@utc, NULL) IS NULL
            PRINT '[OK] PRUEBA 8a: fn_HoraLocal convierte de UTC al huso local (y devuelve NULL sin huso).';
        ELSE
            PRINT '[FALLO] PRUEBA 8a: fn_HoraLocal devolvió una hora local inesperada.';

        -- 20:00 (Romance) y 19:00 (GMT en verano, borde inclusive) sí; 15:00 (Argentina) y 03:00 (Tokyo) no
        IF Publicidad.fn_EsPrimeTime(@utc, 'Romance Standard Time') = 1
           AND Publicidad.fn_EsPrimeTime(@utc, 'GMT Standard Time') = 1
           AND Publicidad.fn_EsPrimeTime(@utc, 'Argentina Standard Time') = 0
           AND Publicidad.fn_EsPrimeTime(@utc, 'Tokyo Standard Time') = 0
           AND Publicidad.fn_EsPrimeTime(@utc, NULL) = 0
            PRINT '[OK] PRUEBA 8b: fn_EsPrimeTime marca prime time entre las 19 y las 23 locales (inclusive).';
        ELSE
            PRINT '[FALLO] PRUEBA 8b: fn_EsPrimeTime devolvió un flag inesperado.';
    END
    ELSE
        PRINT '[OMITIDA] PRUEBA 8: PRIME_TIME_INICIO / PRIME_TIME_FIN tienen valores distintos de 19 y 23.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 8: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   LIMPIEZA FINAL
   ============================================================================= */
PRINT '--- Limpieza final del entorno de pruebas ---';

DELETE FROM Publicidad.ExhibicionPublicitaria
WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 99701 AND 99705);

DELETE FROM Publicidad.PiezaMercado
WHERE idPieza IN (SELECT id FROM Publicidad.PiezaContenido WHERE descripcion LIKE 'Test Neg Pieza%');
DELETE FROM Publicidad.PiezaContenido WHERE descripcion LIKE 'Test Neg Pieza%';
DELETE FROM Publicidad.Campania WHERE nombre LIKE 'Test Neg Campania%';
DELETE FROM Publicidad.Anunciante WHERE nombre LIKE 'Test Neg Anunciante%';
DELETE FROM Publicidad.Tarifa WHERE idFase IN (995, 997);
DELETE FROM Publicidad.UbicacionPublicitaria WHERE idUbicacion BETWEEN 95 AND 98;
DELETE FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 99701 AND 99705;
DELETE FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test Negocio';
DELETE FROM Torneo.Fase WHERE idFase IN (995, 997);
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('TNA', 'TNB');
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('XR', 'XS', 'XT', 'XU', 'XV', 'XW');

PRINT '================================================================================';
PRINT ' BATERÍA DE PRUEBAS COMPLETADA: 22_Negocio_Publicidad.sql';
PRINT '================================================================================';
GO
