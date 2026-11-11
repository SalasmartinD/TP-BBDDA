/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel - 45066788
               Salas, Martin Daniel - 45205702
               Zito Padró, Ezequiel Nehuén - 46097917
 Fecha       : 09/11/2026

 Objetivo    : Suite de pruebas unitarias exhaustivas para 12_ABM_Publicidad.sql.
               Incluye pruebas de casos de éxito y pruebas de error para cada
               una de las validaciones de los SPs de ABM:
               - Publicidad.Anunciante (Alta, Modificación, Baja)
               - Publicidad.Campania (Alta, Modificación, Baja)
               - Publicidad.PiezaContenido (Alta, Modificación, Baja)
               - Publicidad.PiezaMercado (Alta, Baja)
               - Publicidad.UbicacionPublicitaria (Alta, Modificación, Baja)
               - Publicidad.Tarifa (Alta, Modificación, Baja)
               - Publicidad.ExhibicionPublicitaria (Alta, Modificación, Baja)

 Estándares aplicados:
 - Relación 1:1 con 12_ABM_Publicidad.sql.
 - Idempotencia absoluta (limpieza preventiva al inicio y al final).
 - Comprobación de código THROW 50001 y del mensaje de error correspondiente.
 - Evidencia antes/después con SELECT en casos exitosos.
================================================================================
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

PRINT '================================================================================';
PRINT ' INICIANDO BATERÍA DE PRUEBAS EXHAUSTIVA: 12_ABM_Publicidad.sql';
PRINT '================================================================================';
GO

/* =============================================================================
   PREPARACIÓN DEL ENTORNO DE PRUEBAS (FIXTURE AISLADO E IDEMPOTENTE)
   ============================================================================= */
PRINT '--- Limpieza preventiva de pruebas anteriores ---';

DELETE FROM Publicidad.ExhibicionPublicitaria WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99801, 99802));
DELETE FROM Publicidad.PiezaMercado WHERE idPieza IN (SELECT id FROM Publicidad.PiezaContenido WHERE descripcion LIKE 'Test Pieza%');
DELETE FROM Publicidad.PiezaContenido WHERE descripcion LIKE 'Test Pieza%';
DELETE FROM Publicidad.Campania WHERE nombre LIKE 'Test Camp%';
DELETE FROM Publicidad.Anunciante WHERE nombre LIKE 'Test Anunciante%';
DELETE FROM Publicidad.Tarifa WHERE idFase = 998;
DELETE FROM Publicidad.UbicacionPublicitaria WHERE idUbicacion IN (91, 92);
DELETE FROM Torneo.Partido WHERE nroPartidoOficial IN (99801, 99802);
DELETE FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test Publicidad';
DELETE FROM Torneo.Fase WHERE idFase = 998;
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('TPA', 'TPB');
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('XP', 'XQ');
GO

PRINT '--- Creando datos auxiliares de prueba (países, selecciones, partido, fase, sede) ---';

IF NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE codigoISO2 = 'XP')
    INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3, husoHorario, pbiPerCapita)
    VALUES ('Pais Test Publicidad 1', 'XP', 'TXP', 'Argentina Standard Time', 15000);

IF NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE codigoISO2 = 'XQ')
    INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3, husoHorario, pbiPerCapita)
    VALUES ('Pais Test Publicidad 2', 'XQ', 'TXQ', 'W. Europe Standard Time', 45000);

DECLARE @idPaisP1 int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XP');
DECLARE @idPaisP2 int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XQ');

IF NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE idPais = @idPaisP1)
    INSERT INTO Equipos.Seleccion (idPais, abreviacion, confederacion) VALUES (@idPaisP1, 'TPA', 'CONMEBOL');

IF NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE idPais = @idPaisP2)
    INSERT INTO Equipos.Seleccion (idPais, abreviacion, confederacion) VALUES (@idPaisP2, 'TPB', 'UEFA');

DECLARE @idSelP1 int = (SELECT id FROM Equipos.Seleccion WHERE idPais = @idPaisP1);
DECLARE @idSelP2 int = (SELECT id FROM Equipos.Seleccion WHERE idPais = @idPaisP2);

IF NOT EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = 998)
    INSERT INTO Torneo.Fase (idFase, nombre, esEliminatoria, orden) VALUES (998, 'Fase Test Publicidad', 0, 98);

IF NOT EXISTS (SELECT 1 FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test Publicidad')
    INSERT INTO Torneo.Sede (nombreEstadio, ciudad, idPais, husoHorario)
    VALUES ('Estadio Test Publicidad', 'Ciudad Test Pub', @idPaisP1, 'Argentina Standard Time');

DECLARE @idSedeTest int = (SELECT idSede FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test Publicidad');

-- Partido de prueba 99801 (fecha: 2026-06-20)
IF NOT EXISTS (SELECT 1 FROM Torneo.Partido WHERE nroPartidoOficial = 99801)
    INSERT INTO Torneo.Partido (nroPartidoOficial, idSede, idSeleccionLocal, idSeleccionVisitante, fase, fechaHoraUTC, estado)
    VALUES (99801, @idSedeTest, @idSelP1, @idSelP2, 998, '2026-06-20 18:00:00', 'Programado');

PRINT 'Fixture de pruebas inicializado con éxito.';
PRINT '';
GO

/* =============================================================================
   SECCIÓN 1: PRUEBAS SOBRE Publicidad.Anunciante
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 1. PRUEBAS: Publicidad.Anunciante';
PRINT '--------------------------------------------------------------------------------';

-- PRUEBA 1.1: Alta de anunciante exitosa
BEGIN TRY
    DECLARE @idPaisP1 int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XP');
    EXEC Publicidad.Anunciante_Alta
        @nombre = N'Test Anunciante Alfa',
        @rubro = 'Tecnologia',
        @idPais = @idPaisP1,
        @monedaFacturacion = 'USD';

    IF EXISTS (SELECT 1 FROM Publicidad.Anunciante WHERE nombre = N'Test Anunciante Alfa')
        PRINT '[OK] PRUEBA 1.1: Anunciante dado de alta exitosamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 1.1: No se encontró el anunciante insertado.';

    SELECT id, nombre, rubro, idPais, monedaFacturacion FROM Publicidad.Anunciante WHERE nombre = N'Test Anunciante Alfa';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.1: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.2: Error Alta - País inexistente
BEGIN TRY
    EXEC Publicidad.Anunciante_Alta @nombre = N'Test Anunciante Beta', @idPais = 999999;
    PRINT '[FALLO] PRUEBA 1.2: No detectó país inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%pa%s con id%no existe%'
        PRINT '[OK] PRUEBA 1.2: Error país inexistente capturado correctamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 1.2: Error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.3: Error Alta - Nombre duplicado
BEGIN TRY
    DECLARE @idPaisP1 int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XP');
    EXEC Publicidad.Anunciante_Alta @nombre = N'Test Anunciante Alfa', @idPais = @idPaisP1;
    PRINT '[FALLO] PRUEBA 1.3: No detectó nombre duplicado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%Ya existe un anunciante con el nombre%'
        PRINT '[OK] PRUEBA 1.3: Error nombre duplicado capturado correctamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 1.3: Error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.4: Modificación de anunciante exitosa
BEGIN TRY
    DECLARE @idAnunciante int = (SELECT id FROM Publicidad.Anunciante WHERE nombre = N'Test Anunciante Alfa');
    DECLARE @idPaisP2 int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XQ');

    EXEC Publicidad.Anunciante_Modificacion
        @id = @idAnunciante,
        @nombre = N'Test Anunciante Alfa Modificado',
        @rubro = 'Software',
        @idPais = @idPaisP2,
        @monedaFacturacion = 'EUR';

    IF EXISTS (SELECT 1 FROM Publicidad.Anunciante WHERE id = @idAnunciante AND nombre = N'Test Anunciante Alfa Modificado' AND monedaFacturacion = 'EUR')
        PRINT '[OK] PRUEBA 1.4: Anunciante modificado exitosamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 1.4: La modificación no se reflejó correctamente.';

    SELECT id, nombre, rubro, idPais, monedaFacturacion FROM Publicidad.Anunciante WHERE id = @idAnunciante;
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.4: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.5: Error Modificación - Anunciante inexistente
BEGIN TRY
    EXEC Publicidad.Anunciante_Modificacion @id = 999999, @nombre = N'Fantasma', @idPais = 1;
    PRINT '[FALLO] PRUEBA 1.5: No detectó anunciante inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%anunciante con id%no existe%'
        PRINT '[OK] PRUEBA 1.5: Error anunciante inexistente capturado correctamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 1.5: Error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.6: Error Baja - Anunciante con campañas activas
BEGIN TRY
    DECLARE @idAnunciante int = (SELECT id FROM Publicidad.Anunciante WHERE nombre = N'Test Anunciante Alfa Modificado');
    -- Insertamos una campaña activa para provocar el fallo
    INSERT INTO Publicidad.Campania (idAnunciante, nombre, fechaInicio, fechaFin)
    VALUES (@idAnunciante, N'Test Camp Bloqueante', '2026-01-01', '2030-12-31');

    EXEC Publicidad.Anunciante_Baja @id = @idAnunciante;
    PRINT '[FALLO] PRUEBA 1.6: Permitió borrar anunciante con campaña activa.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%campa%as activas%'
        PRINT '[OK] PRUEBA 1.6: Error baja con campañas activas capturado correctamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 1.6: Error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- Limpieza de la campaña para probar baja exitosa
DELETE FROM Publicidad.Campania WHERE nombre = N'Test Camp Bloqueante';
GO

-- PRUEBA 1.7: Baja de anunciante exitosa
BEGIN TRY
    DECLARE @idAnunciante int = (SELECT id FROM Publicidad.Anunciante WHERE nombre = N'Test Anunciante Alfa Modificado');
    EXEC Publicidad.Anunciante_Baja @id = @idAnunciante;

    IF NOT EXISTS (SELECT 1 FROM Publicidad.Anunciante WHERE id = @idAnunciante)
        PRINT '[OK] PRUEBA 1.7: Anunciante eliminado exitosamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 1.7: El anunciante no fue eliminado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.7: ' + ERROR_MESSAGE();
END CATCH;
GO


/* =============================================================================
   SECCIÓN 2: PRUEBAS SOBRE Publicidad.Campania
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 2. PRUEBAS: Publicidad.Campania';
PRINT '--------------------------------------------------------------------------------';

-- Recrear anunciante base para pruebas de campaña
DECLARE @idPaisP1 int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XP');
EXEC Publicidad.Anunciante_Alta @nombre = N'Test Anunciante Base', @idPais = @idPaisP1;
GO

-- PRUEBA 2.1: Alta de campaña exitosa
BEGIN TRY
    DECLARE @idAnunciante int = (SELECT id FROM Publicidad.Anunciante WHERE nombre = N'Test Anunciante Base');
    EXEC Publicidad.Campania_Alta
        @idAnunciante = @idAnunciante,
        @nombre = N'Test Camp Verano 2026',
        @fechaInicio = '2026-06-01',
        @fechaFin = '2026-07-31';

    IF EXISTS (SELECT 1 FROM Publicidad.Campania WHERE nombre = N'Test Camp Verano 2026')
        PRINT '[OK] PRUEBA 2.1: Campaña dada de alta exitosamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 2.1: No se encontró la campaña.';

    SELECT idCampania, idAnunciante, nombre, fechaInicio, fechaFin FROM Publicidad.Campania WHERE nombre = N'Test Camp Verano 2026';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.1: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 2.2: Error Alta - Fechas inconsistentes (fechaFin < fechaInicio)
BEGIN TRY
    DECLARE @idAnunciante int = (SELECT id FROM Publicidad.Anunciante WHERE nombre = N'Test Anunciante Base');
    EXEC Publicidad.Campania_Alta
        @idAnunciante = @idAnunciante,
        @nombre = N'Test Camp Invalida',
        @fechaInicio = '2026-08-01',
        @fechaFin = '2026-07-01';
    PRINT '[FALLO] PRUEBA 2.2: No detectó fechaFin < fechaInicio.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%anterior a la fecha de inicio%'
        PRINT '[OK] PRUEBA 2.2: Error fechas inconsistentes capturado correctamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 2.2: Error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 2.3: Error Alta - Anunciante inexistente
BEGIN TRY
    EXEC Publicidad.Campania_Alta @idAnunciante = 999999, @nombre = N'Camp Fantasma', @fechaInicio = '2026-06-01', @fechaFin = '2026-07-01';
    PRINT '[FALLO] PRUEBA 2.3: No detectó anunciante inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%anunciante con id%no existe%'
        PRINT '[OK] PRUEBA 2.3: Error anunciante inexistente capturado correctamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 2.3: Error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 2.4: Modificación de campaña exitosa
BEGIN TRY
    DECLARE @idCampania int = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Test Camp Verano 2026');
    EXEC Publicidad.Campania_Modificacion
        @idCampania = @idCampania,
        @nombre = N'Test Camp Mundial 2026',
        @fechaInicio = '2026-06-05',
        @fechaFin = '2026-07-25';

    IF EXISTS (SELECT 1 FROM Publicidad.Campania WHERE idCampania = @idCampania AND nombre = N'Test Camp Mundial 2026')
        PRINT '[OK] PRUEBA 2.4: Campaña modificada exitosamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 2.4: No se modificó la campaña.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.4: ' + ERROR_MESSAGE();
END CATCH;
GO


/* =============================================================================
   SECCIÓN 3: PRUEBAS SOBRE Publicidad.PiezaContenido y PiezaMercado
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 3. PRUEBAS: Publicidad.PiezaContenido y PiezaMercado';
PRINT '--------------------------------------------------------------------------------';

-- PRUEBA 3.1: Alta de PiezaContenido exitosa
BEGIN TRY
    DECLARE @idCampania int = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Test Camp Mundial 2026');
    EXEC Publicidad.PiezaContenido_Alta
        @idCampania = @idCampania,
        @descripcion = N'Test Pieza Banner Principal',
        @idioma = 'es';

    IF EXISTS (SELECT 1 FROM Publicidad.PiezaContenido WHERE descripcion = N'Test Pieza Banner Principal')
        PRINT '[OK] PRUEBA 3.1: Pieza de contenido creada exitosamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 3.1: No se encontró la pieza creada.';

    SELECT id, idCampania, descripcion, idioma FROM Publicidad.PiezaContenido WHERE descripcion = N'Test Pieza Banner Principal';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 3.1: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.2: Error Alta - Formato de idioma inválido (no [a-z][a-z])
BEGIN TRY
    DECLARE @idCampania int = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Test Camp Mundial 2026');
    EXEC Publicidad.PiezaContenido_Alta @idCampania = @idCampania, @descripcion = N'Test Pieza Rota', @idioma = '1A';
    PRINT '[FALLO] PRUEBA 3.2: No detectó idioma inválido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%exactamente 2 letras%'
        PRINT '[OK] PRUEBA 3.2: Error formato de idioma capturado correctamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 3.2: Error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.3: Alta de PiezaMercado exitosa
BEGIN TRY
    DECLARE @idPieza int = (SELECT id FROM Publicidad.PiezaContenido WHERE descripcion = N'Test Pieza Banner Principal');
    DECLARE @idPaisP1 int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XP');

    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPieza, @idPais = @idPaisP1;

    IF EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPieza AND idPais = @idPaisP1)
        PRINT '[OK] PRUEBA 3.3: PiezaMercado asignada exitosamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 3.3: No se insertó el registro en PiezaMercado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 3.3: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.4: Error Alta PiezaMercado - Par duplicado
BEGIN TRY
    DECLARE @idPieza int = (SELECT id FROM Publicidad.PiezaContenido WHERE descripcion = N'Test Pieza Banner Principal');
    DECLARE @idPaisP1 int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XP');

    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPieza, @idPais = @idPaisP1;
    PRINT '[FALLO] PRUEBA 3.4: No detectó par duplicado en PiezaMercado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%ya se encuentra registrado%'
        PRINT '[OK] PRUEBA 3.4: Error par duplicado capturado correctamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 3.4: Error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO


/* =============================================================================
   SECCIÓN 4: PRUEBAS SOBRE Publicidad.UbicacionPublicitaria y Tarifa
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 4. PRUEBAS: Publicidad.UbicacionPublicitaria y Tarifa';
PRINT '--------------------------------------------------------------------------------';

-- PRUEBA 4.1: Alta de UbicacionPublicitaria exitosa
BEGIN TRY
    EXEC Publicidad.UbicacionPublicitaria_Alta
        @idUbicacion = 91,
        @nombre = 'Test Ubicacion Led',
        @descripcion = 'Pantalla Led de Prueba';

    IF EXISTS (SELECT 1 FROM Publicidad.UbicacionPublicitaria WHERE idUbicacion = 91)
        PRINT '[OK] PRUEBA 4.1: Ubicación publicitaria dada de alta exitosamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 4.1: No se encontró la ubicación creada.';

    SELECT idUbicacion, nombre, descripcion FROM Publicidad.UbicacionPublicitaria WHERE idUbicacion = 91;
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 4.1: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 4.2: Error Alta Ubicación - ID duplicado
BEGIN TRY
    EXEC Publicidad.UbicacionPublicitaria_Alta @idUbicacion = 91, @nombre = 'Test Otra Ubicacion';
    PRINT '[FALLO] PRUEBA 4.2: No detectó ID duplicado en Ubicación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%con id 91%'
        PRINT '[OK] PRUEBA 4.2: Error ID duplicado capturado correctamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 4.2: Error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 4.3: Alta de Tarifa exitosa
BEGIN TRY
    EXEC Publicidad.Tarifa_Alta @idFase = 998, @idUbicacion = 91, @montoUSD = 50000.00;

    IF EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = 998 AND idUbicacion = 91)
        PRINT '[OK] PRUEBA 4.3: Tarifa dada de alta exitosamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 4.3: No se insertó la tarifa.';

    SELECT idFase, idUbicacion, montoUSD FROM Publicidad.Tarifa WHERE idFase = 998 AND idUbicacion = 91;
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 4.3: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 4.4: Error Alta Tarifa - Monto negativo o cero
BEGIN TRY
    EXEC Publicidad.Tarifa_Alta @idFase = 998, @idUbicacion = 92, @montoUSD = -100.00;
    PRINT '[FALLO] PRUEBA 4.4: No detectó monto negativo en Tarifa.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%mayor a cero%'
        PRINT '[OK] PRUEBA 4.4: Error monto negativo capturado correctamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 4.4: Error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO


/* =============================================================================
   SECCIÓN 5: PRUEBAS SOBRE Publicidad.ExhibicionPublicitaria
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 5. PRUEBAS: Publicidad.ExhibicionPublicitaria';
PRINT '--------------------------------------------------------------------------------';

-- PRUEBA 5.1: Alta de ExhibicionPublicitaria exitosa
BEGIN TRY
    DECLARE @idPartidoTest int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99801);
    DECLARE @idPiezaTest int = (SELECT id FROM Publicidad.PiezaContenido WHERE descripcion = N'Test Pieza Banner Principal');

    EXEC Publicidad.ExhibicionPublicitaria_Alta
        @idPartido = @idPartidoTest,
        @idUbicacion = 91,
        @idPieza = @idPiezaTest,
        @criterioAplicado = 1,
        @estado = 'Propuesta',
        @montoUSD = 50000.00;

    IF EXISTS (SELECT 1 FROM Publicidad.ExhibicionPublicitaria WHERE idPartido = @idPartidoTest AND idUbicacion = 91)
        PRINT '[OK] PRUEBA 5.1: Exhibición publicitaria registrada exitosamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 5.1: No se insertó la exhibición.';

    SELECT idPartido, idUbicacion, idPieza, criterioAplicado, estado, montoUSD
    FROM Publicidad.ExhibicionPublicitaria
    WHERE idPartido = @idPartidoTest AND idUbicacion = 91;
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 5.1: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 5.2: Error Alta Exhibición - Ubicación ya ocupada en el mismo partido
BEGIN TRY
    DECLARE @idPartidoTest int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99801);
    -- Creamos otra pieza para probar la misma ubicación
    DECLARE @idCampania int = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Test Camp Mundial 2026');
    EXEC Publicidad.PiezaContenido_Alta @idCampania = @idCampania, @descripcion = N'Test Pieza Secundaria', @idioma = 'en';
    DECLARE @idPieza2 int = (SELECT id FROM Publicidad.PiezaContenido WHERE descripcion = N'Test Pieza Secundaria');

    EXEC Publicidad.ExhibicionPublicitaria_Alta
        @idPartido = @idPartidoTest,
        @idUbicacion = 91,
        @idPieza = @idPieza2,
        @criterioAplicado = 2,
        @estado = 'Propuesta',
        @montoUSD = 50000.00;

    PRINT '[FALLO] PRUEBA 5.2: Permitió asignar dos piezas a la misma ubicación en un partido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%ya est% ocupada%'
        PRINT '[OK] PRUEBA 5.2: Error ubicación ocupada capturado correctamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 5.2: Error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 5.3: Error Alta Exhibición - Criterio fuera de rango (1 a 3)
BEGIN TRY
    DECLARE @idPartidoTest int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99801);
    DECLARE @idPieza2 int = (SELECT id FROM Publicidad.PiezaContenido WHERE descripcion = N'Test Pieza Secundaria');

    EXEC Publicidad.ExhibicionPublicitaria_Alta
        @idPartido = @idPartidoTest,
        @idUbicacion = 91,
        @idPieza = @idPieza2,
        @criterioAplicado = 99,
        @estado = 'Propuesta',
        @montoUSD = 50000.00;

    PRINT '[FALLO] PRUEBA 5.3: No detectó criterio inválido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%entre 1 y 3%'
        PRINT '[OK] PRUEBA 5.3: Error criterio inválido capturado correctamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 5.3: Error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 5.4: Modificación de Exhibición y Transición de Estado válida
BEGIN TRY
    DECLARE @idPartidoTest int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99801);

    -- Avanzar de Propuesta a Confirmada
    EXEC Publicidad.ExhibicionPublicitaria_Modificacion
        @idPartido = @idPartidoTest,
        @idUbicacion = 91,
        @estado = 'Confirmada';

    IF EXISTS (SELECT 1 FROM Publicidad.ExhibicionPublicitaria WHERE idPartido = @idPartidoTest AND idUbicacion = 91 AND estado = 'Confirmada')
        PRINT '[OK] PRUEBA 5.4a: Estado avanzado a Confirmada exitosamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 5.4a: No se actualizó el estado a Confirmada.';

    -- Avanzar de Confirmada a Exhibida
    EXEC Publicidad.ExhibicionPublicitaria_Modificacion
        @idPartido = @idPartidoTest,
        @idUbicacion = 91,
        @estado = 'Exhibida';

    IF EXISTS (SELECT 1 FROM Publicidad.ExhibicionPublicitaria WHERE idPartido = @idPartidoTest AND idUbicacion = 91 AND estado = 'Exhibida')
        PRINT '[OK] PRUEBA 5.4b: Estado avanzado a Exhibida exitosamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 5.4b: No se actualizó el estado a Exhibida.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 5.4: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 5.5: Error Modificación - Retroceso de estado prohibido (Exhibida -> Propuesta)
BEGIN TRY
    DECLARE @idPartidoTest int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99801);

    EXEC Publicidad.ExhibicionPublicitaria_Modificacion
        @idPartido = @idPartidoTest,
        @idUbicacion = 91,
        @estado = 'Propuesta';

    PRINT '[FALLO] PRUEBA 5.5: Permitió retroceder estado de Exhibida a Propuesta.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%retroceder el estado%'
        PRINT '[OK] PRUEBA 5.5: Error retroceso de estado capturado correctamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 5.5: Error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 5.6: Error Baja Exhibición - Bloqueo de eliminación en estado 'Exhibida'
BEGIN TRY
    DECLARE @idPartidoTest int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99801);

    EXEC Publicidad.ExhibicionPublicitaria_Baja @idPartido = @idPartidoTest, @idUbicacion = 91;
    PRINT '[FALLO] PRUEBA 5.6: Permitió eliminar una exhibición ya exhibida.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%registro hist%rico%'
        PRINT '[OK] PRUEBA 5.6: Error baja de exhibición histórica capturado correctamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 5.6: Error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO


/* =============================================================================
   SECCIÓN 6: BAJAS Y MODIFICACIONES RESTANTES, DEPENDIENTES Y PARÁMETROS NULL
   Cubre los SP que no tenían llamadas en las secciones anteriores:
   Campania_Baja, PiezaContenido_Baja, PiezaContenido_Modificacion,
   PiezaMercado_Baja, UbicacionPublicitaria_Baja, UbicacionPublicitaria_Modificacion,
   Tarifa_Baja y Tarifa_Modificacion.
   Las bajas con dependientes deben fallar con THROW 50001 (no con el error 547
   de clave foránea del motor).
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 6. PRUEBAS: bajas, modificaciones restantes y parámetros NULL';
PRINT '--------------------------------------------------------------------------------';

-- PRUEBA 6.1: Error Baja PiezaContenido - Tiene una exhibición ya realizada (histórica)
BEGIN TRY
    DECLARE @idPieza int = (SELECT id FROM Publicidad.PiezaContenido WHERE descripcion = N'Test Pieza Banner Principal');
    EXEC Publicidad.PiezaContenido_Baja @id = @idPieza;
    PRINT '[FALLO] PRUEBA 6.1: Permitió borrar una pieza con exhibiciones realizadas.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%exhibiciones ya realizadas%'
        PRINT '[OK] PRUEBA 6.1: Error baja de pieza con exhibición histórica capturado correctamente (THROW 50001).';
    ELSE
        PRINT '[FALLO] PRUEBA 6.1: Error inesperado -> ' + CAST(ERROR_NUMBER() AS varchar(10)) + ' ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 6.2: Modificación de PiezaContenido exitosa
BEGIN TRY
    DECLARE @idPieza int = (SELECT id FROM Publicidad.PiezaContenido WHERE descripcion = N'Test Pieza Secundaria');
    EXEC Publicidad.PiezaContenido_Modificacion
        @id = @idPieza,
        @descripcion = N'Test Pieza Secundaria Modificada',
        @idioma = 'pt';

    IF EXISTS (SELECT 1 FROM Publicidad.PiezaContenido WHERE id = @idPieza AND descripcion = N'Test Pieza Secundaria Modificada' AND idioma = 'pt')
        PRINT '[OK] PRUEBA 6.2: Pieza de contenido modificada exitosamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 6.2: La modificación no se reflejó.';

    SELECT id, idCampania, descripcion, idioma FROM Publicidad.PiezaContenido WHERE id = @idPieza;
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 6.2: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 6.3: Error Modificación PiezaContenido - Idioma en mayúsculas ('ES' no cumple 2 letras minúsculas)
BEGIN TRY
    DECLARE @idPieza int = (SELECT id FROM Publicidad.PiezaContenido WHERE descripcion = N'Test Pieza Secundaria Modificada');
    EXEC Publicidad.PiezaContenido_Modificacion @id = @idPieza, @descripcion = N'Test Pieza Secundaria Modificada', @idioma = 'ES';
    PRINT '[FALLO] PRUEBA 6.3: Aceptó un idioma en mayúsculas.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%exactamente 2 letras%'
        PRINT '[OK] PRUEBA 6.3: Error idioma en mayúsculas capturado correctamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 6.3: Error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 6.4: Error Baja PiezaMercado - El par no existe
BEGIN TRY
    DECLARE @idPieza int = (SELECT id FROM Publicidad.PiezaContenido WHERE descripcion = N'Test Pieza Secundaria Modificada');
    DECLARE @idPaisP1 int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XP');
    EXEC Publicidad.PiezaMercado_Baja @idPieza = @idPieza, @idPais = @idPaisP1;
    PRINT '[FALLO] PRUEBA 6.4: No detectó un mercado inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%No existe un mercado registrado%'
        PRINT '[OK] PRUEBA 6.4: Error mercado inexistente capturado correctamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 6.4: Error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 6.5: Baja de PiezaMercado exitosa
BEGIN TRY
    DECLARE @idPieza int = (SELECT id FROM Publicidad.PiezaContenido WHERE descripcion = N'Test Pieza Secundaria Modificada');
    DECLARE @idPaisP2 int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XQ');
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPieza, @idPais = @idPaisP2;

    PRINT 'Evidencia previa (mercados de la pieza):';
    SELECT idPieza, idPais FROM Publicidad.PiezaMercado WHERE idPieza = @idPieza;

    EXEC Publicidad.PiezaMercado_Baja @idPieza = @idPieza, @idPais = @idPaisP2;

    IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPieza AND idPais = @idPaisP2)
        PRINT '[OK] PRUEBA 6.5: Mercado de la pieza eliminado exitosamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 6.5: El mercado no fue eliminado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 6.5: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 6.6: Baja de PiezaContenido exitosa (elimina también sus mercados)
BEGIN TRY
    DECLARE @idPieza int = (SELECT id FROM Publicidad.PiezaContenido WHERE descripcion = N'Test Pieza Secundaria Modificada');
    DECLARE @idPaisP1 int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XP');
    EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPieza, @idPais = @idPaisP1;

    EXEC Publicidad.PiezaContenido_Baja @id = @idPieza;

    IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaContenido WHERE id = @idPieza)
       AND NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPieza)
        PRINT '[OK] PRUEBA 6.6: Pieza de contenido y sus mercados eliminados exitosamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 6.6: La pieza o sus mercados no fueron eliminados.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 6.6: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 6.7: Error Baja Campania - Tiene piezas de contenido (antes llegaba el error 547 del motor)
BEGIN TRY
    DECLARE @idCampania int = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Test Camp Mundial 2026');
    EXEC Publicidad.Campania_Baja @idCampania = @idCampania;
    PRINT '[FALLO] PRUEBA 6.7: Permitió borrar una campaña con piezas.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%piezas de contenido asociadas%'
        PRINT '[OK] PRUEBA 6.7: Error baja de campaña con piezas capturado correctamente (THROW 50001).';
    ELSE
        PRINT '[FALLO] PRUEBA 6.7: Error inesperado -> ' + CAST(ERROR_NUMBER() AS varchar(10)) + ' ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 6.8: Baja de Campania exitosa (campaña sin piezas)
BEGIN TRY
    DECLARE @idAnunciante int = (SELECT id FROM Publicidad.Anunciante WHERE nombre = N'Test Anunciante Base');
    EXEC Publicidad.Campania_Alta @idAnunciante = @idAnunciante, @nombre = N'Test Camp Baja', @fechaInicio = '2026-06-01', @fechaFin = '2026-06-30';
    DECLARE @idCampania int = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Test Camp Baja');

    EXEC Publicidad.Campania_Baja @idCampania = @idCampania;

    IF NOT EXISTS (SELECT 1 FROM Publicidad.Campania WHERE idCampania = @idCampania)
        PRINT '[OK] PRUEBA 6.8: Campaña eliminada exitosamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 6.8: La campaña no fue eliminada.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 6.8: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 6.9: Error Baja Anunciante - Tiene una campaña vencida (antes llegaba el error 547 del motor)
BEGIN TRY
    DECLARE @idAnunciante int = (SELECT id FROM Publicidad.Anunciante WHERE nombre = N'Test Anunciante Base');
    EXEC Publicidad.Campania_Alta @idAnunciante = @idAnunciante, @nombre = N'Test Camp Vencida', @fechaInicio = '2020-01-01', @fechaFin = '2020-12-31';

    EXEC Publicidad.Anunciante_Baja @id = @idAnunciante;
    PRINT '[FALLO] PRUEBA 6.9: Permitió borrar un anunciante con una campaña vencida.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%campa%as vencidas%'
        PRINT '[OK] PRUEBA 6.9: Error baja de anunciante con campaña vencida capturado correctamente (THROW 50001).';
    ELSE
        PRINT '[FALLO] PRUEBA 6.9: Error inesperado -> ' + CAST(ERROR_NUMBER() AS varchar(10)) + ' ' + ERROR_MESSAGE();
END CATCH;

-- Limpieza de la campaña vencida con el SP (también ejercita su baja)
DECLARE @idCampVencida int = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Test Camp Vencida');
IF @idCampVencida IS NOT NULL
    EXEC Publicidad.Campania_Baja @idCampania = @idCampVencida;
GO

-- PRUEBA 6.10: Modificación de UbicacionPublicitaria exitosa
BEGIN TRY
    EXEC Publicidad.UbicacionPublicitaria_Modificacion
        @idUbicacion = 91,
        @nombre = 'Test Ubicacion Led Modificada',
        @descripcion = 'Pantalla Led de Prueba (modificada)';

    IF EXISTS (SELECT 1 FROM Publicidad.UbicacionPublicitaria WHERE idUbicacion = 91 AND nombre = 'Test Ubicacion Led Modificada')
        PRINT '[OK] PRUEBA 6.10: Ubicación publicitaria modificada exitosamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 6.10: La modificación no se reflejó.';

    SELECT idUbicacion, nombre, descripcion FROM Publicidad.UbicacionPublicitaria WHERE idUbicacion = 91;
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 6.10: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 6.11: Error Modificación UbicacionPublicitaria - Ubicación inexistente
BEGIN TRY
    EXEC Publicidad.UbicacionPublicitaria_Modificacion @idUbicacion = 92, @nombre = 'Test Ubicacion Fantasma';
    PRINT '[FALLO] PRUEBA 6.11: No detectó ubicación inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%con id 92%no existe%'
        PRINT '[OK] PRUEBA 6.11: Error ubicación inexistente capturado correctamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 6.11: Error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 6.12: Modificación de Tarifa exitosa
BEGIN TRY
    EXEC Publicidad.Tarifa_Modificacion @idFase = 998, @idUbicacion = 91, @montoUSD = 55000.00;

    IF EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = 998 AND idUbicacion = 91 AND montoUSD = 55000.00)
        PRINT '[OK] PRUEBA 6.12: Tarifa modificada exitosamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 6.12: La modificación no se reflejó.';

    SELECT idFase, idUbicacion, montoUSD FROM Publicidad.Tarifa WHERE idFase = 998 AND idUbicacion = 91;
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 6.12: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 6.13: Error Modificación Tarifa - Monto cero
BEGIN TRY
    EXEC Publicidad.Tarifa_Modificacion @idFase = 998, @idUbicacion = 91, @montoUSD = 0;
    PRINT '[FALLO] PRUEBA 6.13: No detectó monto cero.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%mayor a cero%'
        PRINT '[OK] PRUEBA 6.13: Error monto cero capturado correctamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 6.13: Error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 6.14: Error Baja Tarifa - Hay exhibiciones de esa ubicación en partidos de la fase
BEGIN TRY
    EXEC Publicidad.Tarifa_Baja @idFase = 998, @idUbicacion = 91;
    PRINT '[FALLO] PRUEBA 6.14: Permitió borrar una tarifa con exhibiciones asociadas.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%exhibiciones asociadas%'
        PRINT '[OK] PRUEBA 6.14: Error baja de tarifa con exhibiciones capturado correctamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 6.14: Error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 6.15: Baja de Tarifa exitosa (ubicación auxiliar 92 sin exhibiciones)
BEGIN TRY
    EXEC Publicidad.UbicacionPublicitaria_Alta @idUbicacion = 92, @nombre = 'Test Ubicacion Auxiliar';
    EXEC Publicidad.Tarifa_Alta @idFase = 998, @idUbicacion = 92, @montoUSD = 10000.00;

    EXEC Publicidad.Tarifa_Baja @idFase = 998, @idUbicacion = 92;

    IF NOT EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = 998 AND idUbicacion = 92)
        PRINT '[OK] PRUEBA 6.15: Tarifa eliminada exitosamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 6.15: La tarifa no fue eliminada.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 6.15: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 6.16: Error Baja UbicacionPublicitaria - Tiene tarifas y exhibiciones asociadas
BEGIN TRY
    EXEC Publicidad.UbicacionPublicitaria_Baja @idUbicacion = 91;
    PRINT '[FALLO] PRUEBA 6.16: Permitió borrar una ubicación con tarifas y exhibiciones.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%tarifas asociadas%' AND ERROR_MESSAGE() LIKE '%exhibiciones asociadas%'
        PRINT '[OK] PRUEBA 6.16: Error baja de ubicación con dependientes capturado correctamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 6.16: Error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 6.17: Baja de UbicacionPublicitaria exitosa (ubicación auxiliar 92, ya sin tarifas)
BEGIN TRY
    EXEC Publicidad.UbicacionPublicitaria_Baja @idUbicacion = 92;

    IF NOT EXISTS (SELECT 1 FROM Publicidad.UbicacionPublicitaria WHERE idUbicacion = 92)
        PRINT '[OK] PRUEBA 6.17: Ubicación publicitaria eliminada exitosamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 6.17: La ubicación no fue eliminada.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 6.17: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 6.18: Parámetros NULL - deben dar THROW 50001 y no el error 515 del motor
BEGIN TRY
    EXEC Publicidad.Anunciante_Alta @nombre = N'Test Anunciante Nulo', @idPais = NULL;
    PRINT '[FALLO] PRUEBA 6.18a: Aceptó idPais NULL.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%país con id NULL%'
        PRINT '[OK] PRUEBA 6.18a: Anunciante_Alta con idPais NULL rechazado con THROW 50001.';
    ELSE
        PRINT '[FALLO] PRUEBA 6.18a: Error inesperado -> ' + CAST(ERROR_NUMBER() AS varchar(10)) + ' ' + ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    DECLARE @idPaisNulo int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XP');
    EXEC Publicidad.Anunciante_Alta @nombre = NULL, @idPais = @idPaisNulo;
    PRINT '[FALLO] PRUEBA 6.18b: Aceptó nombre NULL.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%nombre del anunciante es obligatorio%'
        PRINT '[OK] PRUEBA 6.18b: Anunciante_Alta con nombre NULL rechazado con THROW 50001.';
    ELSE
        PRINT '[FALLO] PRUEBA 6.18b: Error inesperado -> ' + CAST(ERROR_NUMBER() AS varchar(10)) + ' ' + ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    DECLARE @idAnuncianteNulo int = (SELECT id FROM Publicidad.Anunciante WHERE nombre = N'Test Anunciante Base');
    EXEC Publicidad.Campania_Alta @idAnunciante = @idAnuncianteNulo, @nombre = N'Test Camp Nula', @fechaInicio = NULL, @fechaFin = '2026-07-01';
    PRINT '[FALLO] PRUEBA 6.18c: Aceptó fechaInicio NULL.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%fecha de inicio es obligatoria%'
        PRINT '[OK] PRUEBA 6.18c: Campania_Alta con fechaInicio NULL rechazada con THROW 50001.';
    ELSE
        PRINT '[FALLO] PRUEBA 6.18c: Error inesperado -> ' + CAST(ERROR_NUMBER() AS varchar(10)) + ' ' + ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    EXEC Publicidad.Tarifa_Alta @idFase = 998, @idUbicacion = 91, @montoUSD = NULL;
    PRINT '[FALLO] PRUEBA 6.18d: Aceptó montoUSD NULL.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%mayor a cero%'
        PRINT '[OK] PRUEBA 6.18d: Tarifa_Alta con montoUSD NULL rechazada con THROW 50001.';
    ELSE
        PRINT '[FALLO] PRUEBA 6.18d: Error inesperado -> ' + CAST(ERROR_NUMBER() AS varchar(10)) + ' ' + ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    DECLARE @idCampaniaNula int = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Test Camp Mundial 2026');
    EXEC Publicidad.PiezaContenido_Alta @idCampania = @idCampaniaNula, @descripcion = N'Test Pieza Nula', @idioma = NULL;
    PRINT '[FALLO] PRUEBA 6.18e: Aceptó idioma NULL.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%exactamente 2 letras%'
        PRINT '[OK] PRUEBA 6.18e: PiezaContenido_Alta con idioma NULL rechazada con THROW 50001.';
    ELSE
        PRINT '[FALLO] PRUEBA 6.18e: Error inesperado -> ' + CAST(ERROR_NUMBER() AS varchar(10)) + ' ' + ERROR_MESSAGE();
END CATCH;
GO


/* =============================================================================
   LIMPIEZA FINAL DEL ENTORNO DE PRUEBAS
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' Limpieza final del entorno de pruebas';
PRINT '--------------------------------------------------------------------------------';

DELETE FROM Publicidad.ExhibicionPublicitaria WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99801, 99802));
DELETE FROM Publicidad.PiezaMercado WHERE idPieza IN (SELECT id FROM Publicidad.PiezaContenido WHERE descripcion LIKE 'Test Pieza%');
DELETE FROM Publicidad.PiezaContenido WHERE descripcion LIKE 'Test Pieza%';
DELETE FROM Publicidad.Campania WHERE nombre LIKE 'Test Camp%';
DELETE FROM Publicidad.Anunciante WHERE nombre LIKE 'Test Anunciante%';
DELETE FROM Publicidad.Tarifa WHERE idFase = 998;
DELETE FROM Publicidad.UbicacionPublicitaria WHERE idUbicacion IN (91, 92);
DELETE FROM Torneo.Partido WHERE nroPartidoOficial IN (99801, 99802);
DELETE FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test Publicidad';
DELETE FROM Torneo.Fase WHERE idFase = 998;
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('TPA', 'TPB');
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('XP', 'XQ');

PRINT '================================================================================';
PRINT ' BATERÍA DE PRUEBAS COMPLETADA: 12_ABM_Publicidad.sql';
PRINT '================================================================================';
GO
