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
               límite de espacios (MAX_ESPACIOS_PARTIDO) y la correcta aplicación
               de los 3 criterios de priorización de piezas publicitarias.

 Estándares aplicados:
 - Relación 1:1 con 22_Negocio_Publicidad.sql.
 - Idempotencia absoluta con limpieza preventiva y final.
 - Validación de errores de negocio (código THROW 50002).
 - Evidencia con SELECT antes y después en casos de éxito.
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
WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99701, 99702));

DELETE FROM Torneo.Partido WHERE nroPartidoOficial IN (99701, 99702);
DELETE FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test Negocio';
DELETE FROM Torneo.Fase WHERE idFase = 997;
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('TNA', 'TNB');
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('NA', 'NB');
GO

PRINT '--- Creando datos auxiliares de prueba ---';

-- Países (uno con selección local, otro visitante)
IF NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE codigoISO2 = 'NA')
    INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3, husoHorario, pbiPerCapita)
    VALUES ('Pais Test Negocio A', 'NA', 'TNA', 'Argentina Standard Time', 12000);

IF NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE codigoISO2 = 'NB')
    INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3, husoHorario, pbiPerCapita)
    VALUES ('Pais Test Negocio B', 'NB', 'TNB', 'W. Europe Standard Time', 50000);

DECLARE @idPaisNA int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'NA');
DECLARE @idPaisNB int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'NB');

-- Selecciones
IF NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE idPais = @idPaisNA)
    INSERT INTO Equipos.Seleccion (idPais, abreviacion, confederacion) VALUES (@idPaisNA, 'TNA', 'CONMEBOL');

IF NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE idPais = @idPaisNB)
    INSERT INTO Equipos.Seleccion (idPais, abreviacion, confederacion) VALUES (@idPaisNB, 'TNB', 'UEFA');

DECLARE @idSelNA int = (SELECT id FROM Equipos.Seleccion WHERE idPais = @idPaisNA);
DECLARE @idSelNB int = (SELECT id FROM Equipos.Seleccion WHERE idPais = @idPaisNB);

-- Fase y Sede
IF NOT EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = 997)
    INSERT INTO Torneo.Fase (idFase, nombre, esEliminatoria, orden) VALUES (997, 'Fase Test Negocio', 0, 97);

IF NOT EXISTS (SELECT 1 FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test Negocio')
    INSERT INTO Torneo.Sede (nombreEstadio, ciudad, idPais, husoHorario)
    VALUES ('Estadio Test Negocio', 'Ciudad Test Negocio', @idPaisNA, 'Argentina Standard Time');

DECLARE @idSedeNegocio int = (SELECT idSede FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test Negocio');

-- Aseguramos que existan las 4 ubicaciones estándar
IF NOT EXISTS (SELECT 1 FROM Publicidad.UbicacionPublicitaria WHERE idUbicacion = 1)
    INSERT INTO Publicidad.UbicacionPublicitaria (idUbicacion, nombre) VALUES (1, 'Cartel Principal');
IF NOT EXISTS (SELECT 1 FROM Publicidad.UbicacionPublicitaria WHERE idUbicacion = 2)
    INSERT INTO Publicidad.UbicacionPublicitaria (idUbicacion, nombre) VALUES (2, 'Perimetral Norte');
IF NOT EXISTS (SELECT 1 FROM Publicidad.UbicacionPublicitaria WHERE idUbicacion = 3)
    INSERT INTO Publicidad.UbicacionPublicitaria (idUbicacion, nombre) VALUES (3, 'Perimetral Sur');
IF NOT EXISTS (SELECT 1 FROM Publicidad.UbicacionPublicitaria WHERE idUbicacion = 4)
    INSERT INTO Publicidad.UbicacionPublicitaria (idUbicacion, nombre) VALUES (4, 'Pantalla Gigante');

-- Tarifas para la fase de prueba 997
MERGE Publicidad.Tarifa AS destino
USING (
    VALUES
        (997, 1, 40000.00),
        (997, 2, 30000.00),
        (997, 3, 30000.00),
        (997, 4, 60000.00)
) AS origen (idFase, idUbicacion, montoUSD)
ON (destino.idFase = origen.idFase AND destino.idUbicacion = origen.idUbicacion)
WHEN NOT MATCHED THEN
    INSERT (idFase, idUbicacion, montoUSD) VALUES (origen.idFase, origen.idUbicacion, origen.montoUSD);

-- Partido 1 (Programado): nroPartidoOficial = 99701
IF NOT EXISTS (SELECT 1 FROM Torneo.Partido WHERE nroPartidoOficial = 99701)
    INSERT INTO Torneo.Partido (nroPartidoOficial, idSede, idSeleccionLocal, idSeleccionVisitante, fase, fechaHoraUTC, estado)
    VALUES (99701, @idSedeNegocio, @idSelNA, @idSelNB, 997, '2026-06-25 18:00:00', 'Programado');

-- Partido 2 (Finalizado): nroPartidoOficial = 99702
IF NOT EXISTS (SELECT 1 FROM Torneo.Partido WHERE nroPartidoOficial = 99702)
    INSERT INTO Torneo.Partido (nroPartidoOficial, idSede, idSeleccionLocal, idSeleccionVisitante, fase, fechaHoraUTC, estado, golLocal, golVisitante)
    VALUES (99702, @idSedeNegocio, @idSelNA, @idSelNB, 997, '2026-06-24 18:00:00', 'Finalizado', 2, 1);

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

-- PRUEBA 3: Asignación automática exitosa a un partido programado
BEGIN TRY
    DECLARE @idPartidoProgramado int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99701);

    PRINT 'Evidencia previa (exhibiciones antes de asignar):';
    SELECT COUNT(*) AS cantExhibicionesPrevias FROM Publicidad.ExhibicionPublicitaria WHERE idPartido = @idPartidoProgramado;

    EXEC Publicidad.AsignarPiezasPartido @idPartido = @idPartidoProgramado;

    DECLARE @cantAsignadas int = (SELECT COUNT(*) FROM Publicidad.ExhibicionPublicitaria WHERE idPartido = @idPartidoProgramado);

    IF @cantAsignadas = 4
        PRINT '[OK] PRUEBA 3: Asignación exitosa de las 4 ubicaciones disponibles.';
    ELSE
        PRINT '[FALLO] PRUEBA 3: Se esperaban 4 exhibiciones pero se asignaron ' + CAST(@cantAsignadas AS varchar(10));

    PRINT 'Detalle de exhibiciones asignadas con sus criterios y montos de tarifa:';
    SELECT ep.idPartido, ep.idUbicacion, u.nombre AS ubicacion, ep.idPieza, pc.descripcion AS pieza,
           ep.criterioAplicado, ep.estado, ep.montoUSD
    FROM Publicidad.ExhibicionPublicitaria ep
    JOIN Publicidad.UbicacionPublicitaria  u  ON u.idUbicacion = ep.idUbicacion
    JOIN Publicidad.PiezaContenido        pc ON pc.id = ep.idPieza
    WHERE ep.idPartido = @idPartidoProgramado
    ORDER BY ep.idUbicacion;
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

/* =============================================================================
   LIMPIEZA FINAL
   ============================================================================= */
PRINT '--- Limpieza final del entorno de pruebas ---';

DELETE FROM Publicidad.ExhibicionPublicitaria
WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99701, 99702));

DELETE FROM Torneo.Partido WHERE nroPartidoOficial IN (99701, 99702);
DELETE FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test Negocio';
DELETE FROM Publicidad.Tarifa WHERE idFase = 997;
DELETE FROM Torneo.Fase WHERE idFase = 997;
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('TNA', 'TNB');
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('NA', 'NB');

PRINT '================================================================================';
PRINT ' BATERÍA DE PRUEBAS COMPLETADA: 22_Negocio_Publicidad.sql';
PRINT '================================================================================';
GO
