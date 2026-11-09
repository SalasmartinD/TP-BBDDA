/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel - 45066788
               Salas, Martin Daniel - 45205702
               Zito Padró, Ezequiel Nehuén - 46097917
 Fecha       : 08/11/2026

 Objetivo    : Suite de pruebas unitarias exhaustivas para 11_ABM_Arbitraje.sql.
               Incluye UNA PRUEBA DEDICADA para CADA UNO de los posibles errores
               y validaciones del ABM, además de los casos de éxito y de
               acumulación de fallos:
               - Arbitraje.Arbitro (Alta, Modificación, Baja)
               - Arbitraje.ArbitroIdioma (Alta, Modificación, Baja)
               - Arbitraje.cuerpoArbitral (Alta, Modificación, Baja)
               - Arbitraje.InformeArbitral (Alta, Modificación, Baja)

 Estándares aplicados:
 - Relación 1:1 con 11_ABM_Arbitraje.sql.
 - Idempotencia absoluta (limpieza preventiva al inicio y al final en orden inverso de FK).
 - Comprobación precisa del código THROW 50001 y del texto descriptivo de cada error.
 - Casos exitosos con evidencia antes/después (SELECT).
================================================================================
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

PRINT '================================================================================';
PRINT ' INICIANDO BATERÍA DE PRUEBAS EXHAUSTIVA: 11_ABM_Arbitraje.sql';
PRINT '================================================================================';
GO

/* =============================================================================
   PREPARACIÓN DEL ENTORNO DE PRUEBAS (FIXTURE AISLADO E IDEMPOTENTE)
   ============================================================================= */
PRINT '--- Limpieza preventiva de pruebas anteriores ---';

DELETE FROM Arbitraje.InformeArbitral WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99901, 99902, 99903));
DELETE FROM Arbitraje.cuerpoArbitral WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99901, 99902, 99903));
DELETE FROM Arbitraje.ArbitroIdioma WHERE idArbitro IN (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido IN (N'Collina Test', N'Arbitro Pais Alfa', N'Arbitro Pais Beta', N'Arbitro Duplicado'));
DELETE FROM Arbitraje.Arbitro WHERE apellido IN (N'Collina Test', N'Arbitro Pais Alfa', N'Arbitro Pais Beta', N'Arbitro Duplicado');
DELETE FROM Torneo.Partido WHERE nroPartidoOficial IN (99901, 99902, 99903);
DELETE FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test Arbitraje';
DELETE FROM Torneo.Fase WHERE idFase = 999;
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('TFA', 'TFB');
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('TA', 'TB', 'TN', 'TX');
GO

PRINT '--- Creando datos auxiliares de prueba (países, selecciones, partidos) ---';

-- Países de prueba
IF NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE codigoISO2 = 'TA')
    INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3) VALUES ('Pais Test Alfa', 'TA', 'TFA');
IF NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE codigoISO2 = 'TB')
    INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3) VALUES ('Pais Test Beta', 'TB', 'TFB');
IF NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE codigoISO2 = 'TN')
    INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3) VALUES ('Pais Test Neutro', 'TN', 'TFN');
IF NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE codigoISO2 = 'TX')
    INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3) VALUES ('Pais Test Extra', 'TX', 'TFX');

DECLARE @idPaisA int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'TA');
DECLARE @idPaisB int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'TB');
DECLARE @idPaisNeutro int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'TN');

-- Selecciones de prueba
IF NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE idPais = @idPaisA)
    INSERT INTO Equipos.Seleccion (idPais, abreviacion, confederacion) VALUES (@idPaisA, 'TFA', 'UEFA');
IF NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE idPais = @idPaisB)
    INSERT INTO Equipos.Seleccion (idPais, abreviacion, confederacion) VALUES (@idPaisB, 'TFB', 'CONMEBOL');

DECLARE @idSelA int = (SELECT id FROM Equipos.Seleccion WHERE idPais = @idPaisA);
DECLARE @idSelB int = (SELECT id FROM Equipos.Seleccion WHERE idPais = @idPaisB);

-- Fase y Sede de prueba
IF NOT EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = 999)
    INSERT INTO Torneo.Fase (idFase, nombre, esEliminatoria, orden) VALUES (999, 'Fase Test', 0, 99);

IF NOT EXISTS (SELECT 1 FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test Arbitraje')
    INSERT INTO Torneo.Sede (nombreEstadio, ciudad, idPais, husoHorario)
    VALUES ('Estadio Test Arbitraje', 'Ciudad Test', @idPaisNeutro, 'UTC');

DECLARE @idSedeTest int = (SELECT idSede FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test Arbitraje');

-- Partidos en distintos estados:
-- 1. Partido 99901: Programado
IF NOT EXISTS (SELECT 1 FROM Torneo.Partido WHERE nroPartidoOficial = 99901)
    INSERT INTO Torneo.Partido (nroPartidoOficial, idSede, idSeleccionLocal, idSeleccionVisitante, fase, fechaHoraUTC, estado)
    VALUES (99901, @idSedeTest, @idSelA, @idSelB, 999, '2026-06-15 18:00:00', 'Programado');

-- 2. Partido 99902: Finalizado
IF NOT EXISTS (SELECT 1 FROM Torneo.Partido WHERE nroPartidoOficial = 99902)
    INSERT INTO Torneo.Partido (nroPartidoOficial, idSede, idSeleccionLocal, idSeleccionVisitante, fase, fechaHoraUTC, estado, golLocal, golVisitante)
    VALUES (99902, @idSedeTest, @idSelA, @idSelB, 999, '2026-06-14 18:00:00', 'Finalizado', 1, 0);

-- 3. Partido 99903: En juego
IF NOT EXISTS (SELECT 1 FROM Torneo.Partido WHERE nroPartidoOficial = 99903)
    INSERT INTO Torneo.Partido (nroPartidoOficial, idSede, idSeleccionLocal, idSeleccionVisitante, fase, fechaHoraUTC, estado)
    VALUES (99903, @idSedeTest, @idSelA, @idSelB, 999, '2026-06-15 20:00:00', 'En juego');

PRINT 'Fixture de pruebas inicializado con éxito.';
PRINT '';
GO

/* =============================================================================
   SECCIÓN 1: PRUEBAS SOBRE Arbitraje.Arbitro
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 1. PRUEBAS: Arbitraje.Arbitro';
PRINT '--------------------------------------------------------------------------------';

-- PRUEBA 1.1: Alta de árbitro exitosa
BEGIN TRY
    DECLARE @idPaisNeutro int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'TN');
    DECLARE @idArbitroGenerado int;

    EXEC Arbitraje.Arbitro_Alta
        @idPais             = @idPaisNeutro,
        @nombre             = N'Pierluigi',
        @apellido           = N'Collina Test',
        @categoria          = 'FIFA',
        @genero             = 'Masculino',
        @fechaInternacional = '2015-01-01',
        @idArbitro          = @idArbitroGenerado OUTPUT;

    PRINT '[OK] PRUEBA 1.1: Árbitro dado de alta con ID = ' + CAST(@idArbitroGenerado AS varchar(10));
    SELECT idArbitro, nombre, apellido, categoria, idPais, fechaInternacional FROM Arbitraje.Arbitro WHERE idArbitro = @idArbitroGenerado;
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.1: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.2a: Error Alta - Nombre obligatorio
BEGIN TRY
    DECLARE @idPaisNeutro int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'TN');
    EXEC Arbitraje.Arbitro_Alta @idPais = @idPaisNeutro, @nombre = N'   ', @apellido = N'Test', @categoria = 'FIFA';
    PRINT '[FALLO] PRUEBA 1.2a No detectó nombre vacío.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%nombre del árbitro es obligatorio%'
        PRINT '[OK] PRUEBA 1.2a: Error nombre obligatorio capturado.';
    ELSE PRINT '[FALLO] PRUEBA 1.2a: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.2b: Error Alta - Apellido obligatorio
BEGIN TRY
    DECLARE @idPaisNeutro int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'TN');
    EXEC Arbitraje.Arbitro_Alta @idPais = @idPaisNeutro, @nombre = N'Mario', @apellido = N'', @categoria = 'FIFA';
    PRINT '[FALLO] PRUEBA 1.2b No detectó apellido vacío.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%apellido del árbitro es obligatorio%'
        PRINT '[OK] PRUEBA 1.2b: Error apellido obligatorio capturado.';
    ELSE PRINT '[FALLO] PRUEBA 1.2b: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.2c: Error Alta - País inexistente
BEGIN TRY
    EXEC Arbitraje.Arbitro_Alta @idPais = 999999, @nombre = N'Mario', @apellido = N'Rossi', @categoria = 'FIFA';
    PRINT '[FALLO] PRUEBA 1.2c No detectó país inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%país especificado no existe%'
        PRINT '[OK] PRUEBA 1.2c: Error país inexistente capturado.';
    ELSE PRINT '[FALLO] PRUEBA 1.2c: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.2d: Error Alta - Categoría permitida
BEGIN TRY
    DECLARE @idPaisNeutro int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'TN');
    EXEC Arbitraje.Arbitro_Alta @idPais = @idPaisNeutro, @nombre = N'Mario', @apellido = N'Rossi', @categoria = 'BARRIAL';
    PRINT '[FALLO] PRUEBA 1.2d No detectó categoría inválida.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%La categoría debe ser ''FIFA'' o ''Confederacion''%'
        PRINT '[OK] PRUEBA 1.2d: Error categoría inválida capturado.';
    ELSE PRINT '[FALLO] PRUEBA 1.2d: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.2e: Error Alta - Fecha internacional no futura
BEGIN TRY
    DECLARE @idPaisNeutro int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'TN');
    EXEC Arbitraje.Arbitro_Alta @idPais = @idPaisNeutro, @nombre = N'Mario', @apellido = N'Rossi', @categoria = 'FIFA', @fechaInternacional = '2099-01-01';
    PRINT '[FALLO] PRUEBA 1.2e No detectó fecha futura.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%fecha de obtención de categoría internacional no puede ser futura%'
        PRINT '[OK] PRUEBA 1.2e: Error fecha internacional futura capturado.';
    ELSE PRINT '[FALLO] PRUEBA 1.2e: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.2f: Error Alta - Unicidad de árbitro por país, nombre y apellido
BEGIN TRY
    DECLARE @idPaisNeutro int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'TN');
    EXEC Arbitraje.Arbitro_Alta @idPais = @idPaisNeutro, @nombre = N'Pierluigi', @apellido = N'Collina Test', @categoria = 'FIFA';
    PRINT '[FALLO] PRUEBA 1.2f No detectó árbitro duplicado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%Ya existe un árbitro registrado con el mismo nombre y apellido%'
        PRINT '[OK] PRUEBA 1.2f: Error árbitro duplicado capturado.';
    ELSE PRINT '[FALLO] PRUEBA 1.2f: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.2g: Error Alta - Múltiples fallos acumulados en un único THROW
BEGIN TRY
    EXEC Arbitraje.Arbitro_Alta @idPais = 999999, @nombre = N'', @apellido = N'   ', @categoria = 'OTRA', @fechaInternacional = '2099-12-31';
    PRINT '[FALLO] PRUEBA 1.2g No arrojó excepción acumulativa.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 
       AND ERROR_MESSAGE() LIKE '%nombre del árbitro es obligatorio%'
       AND ERROR_MESSAGE() LIKE '%apellido del árbitro es obligatorio%'
       AND ERROR_MESSAGE() LIKE '%país especificado no existe%'
       AND ERROR_MESSAGE() LIKE '%La categoría debe ser ''FIFA'' o ''Confederacion''%'
       AND ERROR_MESSAGE() LIKE '%fecha de obtención de categoría internacional no puede ser futura%'
        PRINT '[OK] PRUEBA 1.2g: Acumulación de 5 errores simultáneos verificada correctamente.';
    ELSE PRINT '[FALLO] PRUEBA 1.2g: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.3: Modificación de árbitro exitosa
BEGIN TRY
    DECLARE @idArbitro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    DECLARE @idPaisNeutro int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'TN');

    EXEC Arbitraje.Arbitro_Modificacion
        @idArbitro          = @idArbitro,
        @idPais             = @idPaisNeutro,
        @nombre             = N'Pierluigi',
        @apellido           = N'Collina Test',
        @categoria          = 'Confederacion',
        @genero             = 'Masculino',
        @fechaInternacional = '2016-05-10';

    PRINT '[OK] PRUEBA 1.3: Modificación exitosa.';
    SELECT idArbitro, nombre, apellido, categoria, fechaInternacional FROM Arbitraje.Arbitro WHERE idArbitro = @idArbitro;
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.3: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.4a: Error Modificación - Árbitro inexistente
BEGIN TRY
    EXEC Arbitraje.Arbitro_Modificacion @idArbitro = -999, @idPais = 1, @nombre = N'A', @apellido = N'B', @categoria = 'FIFA';
    PRINT '[FALLO] PRUEBA 1.4a No detectó árbitro inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%árbitro a modificar no existe%'
        PRINT '[OK] PRUEBA 1.4a: Error árbitro inexistente capturado.';
    ELSE PRINT '[FALLO] PRUEBA 1.4a: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.4b: Error Modificación - Nombre obligatorio
BEGIN TRY
    DECLARE @idArbitro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    DECLARE @idPaisNeutro int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'TN');
    EXEC Arbitraje.Arbitro_Modificacion @idArbitro = @idArbitro, @idPais = @idPaisNeutro, @nombre = N'   ', @apellido = N'Collina Test', @categoria = 'FIFA';
    PRINT '[FALLO] PRUEBA 1.4b No detectó nombre vacío.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%nombre del árbitro es obligatorio%'
        PRINT '[OK] PRUEBA 1.4b: Error nombre obligatorio capturado.';
    ELSE PRINT '[FALLO] PRUEBA 1.4b: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.4c: Error Modificación - Apellido obligatorio
BEGIN TRY
    DECLARE @idArbitro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    DECLARE @idPaisNeutro int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'TN');
    EXEC Arbitraje.Arbitro_Modificacion @idArbitro = @idArbitro, @idPais = @idPaisNeutro, @nombre = N'Pierluigi', @apellido = N'', @categoria = 'FIFA';
    PRINT '[FALLO] PRUEBA 1.4c No detectó apellido vacío.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%apellido del árbitro es obligatorio%'
        PRINT '[OK] PRUEBA 1.4c: Error apellido obligatorio capturado.';
    ELSE PRINT '[FALLO] PRUEBA 1.4c: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.4d: Error Modificación - País inexistente
BEGIN TRY
    DECLARE @idArbitro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    EXEC Arbitraje.Arbitro_Modificacion @idArbitro = @idArbitro, @idPais = 999999, @nombre = N'Pierluigi', @apellido = N'Collina Test', @categoria = 'FIFA';
    PRINT '[FALLO] PRUEBA 1.4d No detectó país inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%país especificado no existe%'
        PRINT '[OK] PRUEBA 1.4d: Error país inexistente capturado.';
    ELSE PRINT '[FALLO] PRUEBA 1.4d: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.4e: Error Modificación - Categoría permitida
BEGIN TRY
    DECLARE @idArbitro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    DECLARE @idPaisNeutro int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'TN');
    EXEC Arbitraje.Arbitro_Modificacion @idArbitro = @idArbitro, @idPais = @idPaisNeutro, @nombre = N'Pierluigi', @apellido = N'Collina Test', @categoria = 'LOCAL';
    PRINT '[FALLO] PRUEBA 1.4e No detectó categoría inválida.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%La categoría debe ser ''FIFA'' o ''Confederacion''%'
        PRINT '[OK] PRUEBA 1.4e: Error categoría inválida capturado.';
    ELSE PRINT '[FALLO] PRUEBA 1.4e: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.4f: Error Modificación - Fecha internacional no futura
BEGIN TRY
    DECLARE @idArbitro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    DECLARE @idPaisNeutro int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'TN');
    EXEC Arbitraje.Arbitro_Modificacion @idArbitro = @idArbitro, @idPais = @idPaisNeutro, @nombre = N'Pierluigi', @apellido = N'Collina Test', @categoria = 'FIFA', @fechaInternacional = '2099-01-01';
    PRINT '[FALLO] PRUEBA 1.4f No detectó fecha futura.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%fecha de obtención de categoría internacional no puede ser futura%'
        PRINT '[OK] PRUEBA 1.4f: Error fecha futura capturado.';
    ELSE PRINT '[FALLO] PRUEBA 1.4f: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.4g: Error Modificación - Duplicado con otro árbitro del mismo país
BEGIN TRY
    DECLARE @idPaisNeutro int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'TN');
    DECLARE @idArbitroAux int;

    -- Damos de alta un segundo árbitro
    EXEC Arbitraje.Arbitro_Alta @idPais = @idPaisNeutro, @nombre = N'Roberto', @apellido = N'Arbitro Duplicado', @categoria = 'FIFA', @idArbitro = @idArbitroAux OUTPUT;

    -- Intentamos renombrar al segundo con el nombre del primero
    EXEC Arbitraje.Arbitro_Modificacion @idArbitro = @idArbitroAux, @idPais = @idPaisNeutro, @nombre = N'Pierluigi', @apellido = N'Collina Test', @categoria = 'FIFA';
    PRINT '[FALLO] PRUEBA 1.4g No detectó conflicto de duplicidad con otro árbitro.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%Ya existe otro árbitro registrado con el mismo nombre y apellido%'
        PRINT '[OK] PRUEBA 1.4g: Error duplicado contra otro árbitro capturado.';
    ELSE PRINT '[FALLO] PRUEBA 1.4g: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.4h: Error Modificación - Conflicto de nacionalidad si se cambia país a uno con partidos asignados
BEGIN TRY
    DECLARE @idArbitroAux int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Arbitro Duplicado');
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idPaisA int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'TA');

    -- Lo designamos en el partido (su país actual TN es neutral)
    EXEC Arbitraje.cuerpoArbitral_Alta @idPartido = @idPartido, @idArbitro = @idArbitroAux, @rol = 'Cuarto Arbitro';

    -- Intentamos cambiar su nacionalidad al país Alfa (que juega ese partido)
    EXEC Arbitraje.Arbitro_Modificacion @idArbitro = @idArbitroAux, @idPais = @idPaisA, @nombre = N'Roberto', @apellido = N'Arbitro Duplicado', @categoria = 'FIFA';
    PRINT '[FALLO] PRUEBA 1.4h No detectó conflicto de nacionalidad por cambio de país.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%conflicto de nacionalidad en partidos donde ya se encuentra designado%'
        PRINT '[OK] PRUEBA 1.4h: Error conflicto de nacionalidad en modificación de país capturado.';
    ELSE PRINT '[FALLO] PRUEBA 1.4h: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.5a: Error Baja - Árbitro inexistente
BEGIN TRY
    EXEC Arbitraje.Arbitro_Baja @idArbitro = -999;
    PRINT '[FALLO] PRUEBA 1.5a No detectó árbitro inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%árbitro a eliminar no existe%'
        PRINT '[OK] PRUEBA 1.5a: Error árbitro a eliminar no existe capturado.';
    ELSE PRINT '[FALLO] PRUEBA 1.5a: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.5b: Error Baja - Árbitro con designaciones vigentes
BEGIN TRY
    DECLARE @idArbitroAux int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Arbitro Duplicado');
    EXEC Arbitraje.Arbitro_Baja @idArbitro = @idArbitroAux;
    PRINT '[FALLO] PRUEBA 1.5b Permitió eliminar árbitro con designaciones.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%posee designaciones en partidos%'
        PRINT '[OK] PRUEBA 1.5b: Error árbitro con designaciones capturado.';
    ELSE PRINT '[FALLO] PRUEBA 1.5b: ' + ERROR_MESSAGE();
END CATCH;
GO

-- Limpieza del árbitro auxiliar y su designación para los siguientes bloques
DECLARE @idArbitroAux int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Arbitro Duplicado');
DELETE FROM Arbitraje.cuerpoArbitral WHERE idArbitro = @idArbitroAux;
DELETE FROM Arbitraje.Arbitro WHERE idArbitro = @idArbitroAux;
GO

/* =============================================================================
   SECCIÓN 2: PRUEBAS SOBRE Arbitraje.ArbitroIdioma
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 2. PRUEBAS: Arbitraje.ArbitroIdioma';
PRINT '--------------------------------------------------------------------------------';

-- PRUEBA 2.1: Alta exitosa de idioma
BEGIN TRY
    DECLARE @idArbitro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    EXEC Arbitraje.ArbitroIdioma_Alta @idArbitro = @idArbitro, @idioma = 'it';
    PRINT '[OK] PRUEBA 2.1: Idioma "it" registrado con éxito.';
    SELECT idArbitro, idioma FROM Arbitraje.ArbitroIdioma WHERE idArbitro = @idArbitro;
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.1: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 2.2a: Error Alta - Árbitro inexistente
BEGIN TRY
    EXEC Arbitraje.ArbitroIdioma_Alta @idArbitro = -999, @idioma = 'en';
    PRINT '[FALLO] PRUEBA 2.2a No detectó árbitro inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%árbitro especificado no existe%'
        PRINT '[OK] PRUEBA 2.2a: Error árbitro inexistente capturado.';
    ELSE PRINT '[FALLO] PRUEBA 2.2a: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 2.2b: Error Alta - Formato ISO inválido (cadena larga, corta o dígitos)
BEGIN TRY
    DECLARE @idArbitro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    EXEC Arbitraje.ArbitroIdioma_Alta @idArbitro = @idArbitro, @idioma = 'esp';
    PRINT '[FALLO] PRUEBA 2.2b No detectó código no ISO.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%código de idioma debe componerse exactamente de dos letras%'
        PRINT '[OK] PRUEBA 2.2b: Error formato ISO inválido capturado.';
    ELSE PRINT '[FALLO] PRUEBA 2.2b: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 2.2c: Error Alta - Idioma duplicado
BEGIN TRY
    DECLARE @idArbitro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    EXEC Arbitraje.ArbitroIdioma_Alta @idArbitro = @idArbitro, @idioma = 'it';
    PRINT '[FALLO] PRUEBA 2.2c No detectó idioma duplicado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%idioma ya se encuentra registrado%'
        PRINT '[OK] PRUEBA 2.2c: Error idioma duplicado capturado.';
    ELSE PRINT '[FALLO] PRUEBA 2.2c: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 2.3: Modificación exitosa de idioma ('it' a 'en')
BEGIN TRY
    DECLARE @idArbitro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    EXEC Arbitraje.ArbitroIdioma_Modificacion @idArbitro = @idArbitro, @idiomaActual = 'it', @idiomaNuevo = 'en';
    PRINT '[OK] PRUEBA 2.3: Idioma modificado de "it" a "en".';
    SELECT idArbitro, idioma FROM Arbitraje.ArbitroIdioma WHERE idArbitro = @idArbitro;
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.3: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 2.4a: Error Modificación - Árbitro inexistente
BEGIN TRY
    EXEC Arbitraje.ArbitroIdioma_Modificacion @idArbitro = -999, @idiomaActual = 'en', @idiomaNuevo = 'fr';
    PRINT '[FALLO] PRUEBA 2.4a No detectó árbitro inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%árbitro especificado no existe%'
        PRINT '[OK] PRUEBA 2.4a: Error árbitro inexistente capturado.';
    ELSE PRINT '[FALLO] PRUEBA 2.4a: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 2.4b: Error Modificación - Idioma actual no registrado
BEGIN TRY
    DECLARE @idArbitro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    EXEC Arbitraje.ArbitroIdioma_Modificacion @idArbitro = @idArbitro, @idiomaActual = 'de', @idiomaNuevo = 'fr';
    PRINT '[FALLO] PRUEBA 2.4b No detectó que el idioma actual no existía.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%no posee registrado el idioma actual%'
        PRINT '[OK] PRUEBA 2.4b: Error idioma actual no registrado capturado.';
    ELSE PRINT '[FALLO] PRUEBA 2.4b: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 2.4c: Error Modificación - Idioma nuevo no ISO
BEGIN TRY
    DECLARE @idArbitro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    EXEC Arbitraje.ArbitroIdioma_Modificacion @idArbitro = @idArbitro, @idiomaActual = 'en', @idiomaNuevo = '12';
    PRINT '[FALLO] PRUEBA 2.4c No detectó nuevo idioma no ISO.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%nuevo código de idioma debe componerse exactamente%'
        PRINT '[OK] PRUEBA 2.4c: Error nuevo idioma no ISO capturado.';
    ELSE PRINT '[FALLO] PRUEBA 2.4c: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 2.4d: Error Modificación - Idioma nuevo idéntico al actual
BEGIN TRY
    DECLARE @idArbitro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    EXEC Arbitraje.ArbitroIdioma_Modificacion @idArbitro = @idArbitro, @idiomaActual = 'en', @idiomaNuevo = 'en';
    PRINT '[FALLO] PRUEBA 2.4d No detectó idiomas idénticos.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%nuevo idioma no puede ser idéntico al idioma actual%'
        PRINT '[OK] PRUEBA 2.4d: Error idiomas idénticos capturado.';
    ELSE PRINT '[FALLO] PRUEBA 2.4d: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 2.4e: Error Modificación - Nuevo idioma ya registrado
BEGIN TRY
    DECLARE @idArbitro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    -- Agregamos 'fr'
    EXEC Arbitraje.ArbitroIdioma_Alta @idArbitro = @idArbitro, @idioma = 'fr';
    -- Intentamos cambiar 'en' por 'fr' que ya lo tiene
    EXEC Arbitraje.ArbitroIdioma_Modificacion @idArbitro = @idArbitro, @idiomaActual = 'en', @idiomaNuevo = 'fr';
    PRINT '[FALLO] PRUEBA 2.4e No detectó colisión con idioma preexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%nuevo idioma ya se encuentra registrado%'
        PRINT '[OK] PRUEBA 2.4e: Error nuevo idioma ya registrado capturado.';
    ELSE PRINT '[FALLO] PRUEBA 2.4e: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 2.5a: Error Baja - Árbitro inexistente
BEGIN TRY
    EXEC Arbitraje.ArbitroIdioma_Baja @idArbitro = -999, @idioma = 'en';
    PRINT '[FALLO] PRUEBA 2.5a No detectó árbitro inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%árbitro especificado no existe%'
        PRINT '[OK] PRUEBA 2.5a: Error árbitro inexistente capturado.';
    ELSE PRINT '[FALLO] PRUEBA 2.5a: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 2.5b: Error Baja - Idioma no registrado
BEGIN TRY
    DECLARE @idArbitro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    EXEC Arbitraje.ArbitroIdioma_Baja @idArbitro = @idArbitro, @idioma = 'pt';
    PRINT '[FALLO] PRUEBA 2.5b No detectó idioma no registrado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%no posee registrado el idioma indicado%'
        PRINT '[OK] PRUEBA 2.5b: Error idioma no registrado capturado.';
    ELSE PRINT '[FALLO] PRUEBA 2.5b: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 2.6: Baja exitosa de idiomas
BEGIN TRY
    DECLARE @idArbitro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    EXEC Arbitraje.ArbitroIdioma_Baja @idArbitro = @idArbitro, @idioma = 'fr';
    EXEC Arbitraje.ArbitroIdioma_Baja @idArbitro = @idArbitro, @idioma = 'en';
    PRINT '[OK] PRUEBA 2.6: Bajas de idiomas ejecutadas con éxito.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.6: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   SECCIÓN 3: PRUEBAS SOBRE Arbitraje.cuerpoArbitral
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 3. PRUEBAS: Arbitraje.cuerpoArbitral';
PRINT '--------------------------------------------------------------------------------';

-- PRUEBA 3.1: Alta de designación exitosa con árbitro neutral
BEGIN TRY
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    DECLARE @idDesignacion int;

    EXEC Arbitraje.cuerpoArbitral_Alta
        @idPartido = @idPartido,
        @idArbitro = @idArbitroNeutro,
        @rol       = 'Principal',
        @id        = @idDesignacion OUTPUT;

    PRINT '[OK] PRUEBA 3.1: Designación exitosa con ID = ' + CAST(@idDesignacion AS varchar(10));
    SELECT id, idPartido, idArbitro, rol FROM Arbitraje.cuerpoArbitral WHERE id = @idDesignacion;
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 3.1: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.2a: Error Alta - Partido inexistente
-- Resultado esperado: Fallo con THROW 50001 y mensaje "- El partido especificado no existe."
BEGIN TRY
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    EXEC Arbitraje.cuerpoArbitral_Alta @idPartido = 999999, @idArbitro = @idArbitroNeutro, @rol = 'VAR';
    PRINT '[FALLO] PRUEBA 3.2a No detectó partido inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%partido especificado no existe%'
        PRINT '[OK] PRUEBA 3.2a: Error partido inexistente capturado.';
    ELSE PRINT '[FALLO] PRUEBA 3.2a: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.2b: Error Alta - Árbitro inexistente
-- Resultado esperado: Fallo con THROW 50001 y mensaje "- El árbitro especificado no existe."
BEGIN TRY
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    EXEC Arbitraje.cuerpoArbitral_Alta @idPartido = @idPartido, @idArbitro = -999, @rol = 'VAR';
    PRINT '[FALLO] PRUEBA 3.2b No detectó árbitro inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%árbitro especificado no existe%'
        PRINT '[OK] PRUEBA 3.2b: Error árbitro inexistente capturado.';
    ELSE PRINT '[FALLO] PRUEBA 3.2b: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.2c: Error Alta - Rol inválido
-- Resultado esperado: Fallo con THROW 50001 y mensaje conteniendo "El rol arbitral debe ser Principal, Asistente 1..."
BEGIN TRY
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    EXEC Arbitraje.cuerpoArbitral_Alta @idPartido = @idPartido, @idArbitro = @idArbitroNeutro, @rol = 'JuezDeLinea';
    PRINT '[FALLO] PRUEBA 3.2c No detectó rol inválido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%rol arbitral debe ser Principal%'
        PRINT '[OK] PRUEBA 3.2c: Error rol inválido capturado.';
    ELSE PRINT '[FALLO] PRUEBA 3.2c: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.2d1: Error Alta - Partido ya en estado 'Finalizado'
-- Resultado esperado: Fallo con THROW 50001 y mensaje "- No se pueden asignar árbitros a un partido ya finalizado o que se encuentra en juego."
BEGIN TRY
    DECLARE @idPartidoFin int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99902);
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    EXEC Arbitraje.cuerpoArbitral_Alta @idPartido = @idPartidoFin, @idArbitro = @idArbitroNeutro, @rol = 'VAR';
    PRINT '[FALLO] PRUEBA 3.2d1 Permitió asignar en partido finalizado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%partido ya finalizado o que se encuentra en juego%'
        PRINT '[OK] PRUEBA 3.2d1: Error partido finalizado capturado.';
    ELSE PRINT '[FALLO] PRUEBA 3.2d1: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.2d2: Error Alta - Partido actualmente en estado 'En juego'
-- Resultado esperado: Fallo con THROW 50001 y mensaje "- No se pueden asignar árbitros a un partido ya finalizado o que se encuentra en juego."
BEGIN TRY
    DECLARE @idPartidoJuego int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99903);
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    EXEC Arbitraje.cuerpoArbitral_Alta @idPartido = @idPartidoJuego, @idArbitro = @idArbitroNeutro, @rol = 'VAR';
    PRINT '[FALLO] PRUEBA 3.2d2 Permitió asignar en partido en juego.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%partido ya finalizado o que se encuentra en juego%'
        PRINT '[OK] PRUEBA 3.2d2: Error partido en juego capturado.';
    ELSE PRINT '[FALLO] PRUEBA 3.2d2: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.2e: Error Alta - Rol ya cubierto en este partido
-- Resultado esperado: Fallo con THROW 50001 y mensaje "- El rol ya se encuentra cubierto por otro árbitro en este partido."
BEGIN TRY
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idPaisExtra int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'TX');
    DECLARE @idOtroArbitro int;

    IF NOT EXISTS (SELECT 1 FROM Arbitraje.Arbitro WHERE apellido = N'Arbitro Pais Beta')
        INSERT INTO Arbitraje.Arbitro (idPais, nombre, apellido, categoria) VALUES (@idPaisExtra, N'Howard', N'Arbitro Pais Beta', 'FIFA');
    SET @idOtroArbitro = (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Arbitro Pais Beta');

    -- Intentamos asignarlo también como 'Principal' (ya ocupado por Collina)
    EXEC Arbitraje.cuerpoArbitral_Alta @idPartido = @idPartido, @idArbitro = @idOtroArbitro, @rol = 'Principal';
    PRINT '[FALLO] PRUEBA 3.2e Permitió dos árbitros con el rol Principal.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%rol ya se encuentra cubierto por otro árbitro%'
        PRINT '[OK] PRUEBA 3.2e: Error rol ya cubierto capturado.';
    ELSE PRINT '[FALLO] PRUEBA 3.2e: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.2f: Error Alta - Árbitro ya posee otro rol en este partido
-- Resultado esperado: Fallo con THROW 50001 y mensaje "- El árbitro ya posee otro rol asignado en este mismo partido."
BEGIN TRY
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    -- Collina ya es Principal, intentamos darle VAR
    EXEC Arbitraje.cuerpoArbitral_Alta @idPartido = @idPartido, @idArbitro = @idArbitroNeutro, @rol = 'VAR';
    PRINT '[FALLO] PRUEBA 3.2f Permitió asignar dos roles al mismo árbitro.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%árbitro ya posee otro rol asignado en este mismo partido%'
        PRINT '[OK] PRUEBA 3.2f: Error árbitro con rol duplicado capturado.';
    ELSE PRINT '[FALLO] PRUEBA 3.2f: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.2g1: Error Alta - Conflicto de nacionalidad con Selección Local (País Alfa)
-- Resultado esperado: Fallo con THROW 50001 y mensaje "- Conflicto de nacionalidad: el árbitro es de la misma nacionalidad que una de las selecciones del partido."
BEGIN TRY
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idPaisA int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'TA');
    DECLARE @idArbitroAlfa int;

    IF NOT EXISTS (SELECT 1 FROM Arbitraje.Arbitro WHERE apellido = N'Arbitro Pais Alfa')
        INSERT INTO Arbitraje.Arbitro (idPais, nombre, apellido, categoria) VALUES (@idPaisA, N'Néstor', N'Arbitro Pais Alfa', 'FIFA');
    SET @idArbitroAlfa = (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Arbitro Pais Alfa');

    EXEC Arbitraje.cuerpoArbitral_Alta @idPartido = @idPartido, @idArbitro = @idArbitroAlfa, @rol = 'Asistente 1';
    PRINT '[FALLO] PRUEBA 3.2g1 Permitió designar árbitro con nacionalidad local.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%Conflicto de nacionalidad%'
        PRINT '[OK] PRUEBA 3.2g1: Error conflicto de nacionalidad con local capturado.';
    ELSE PRINT '[FALLO] PRUEBA 3.2g1: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.2g2: Error Alta - Conflicto de nacionalidad con Selección Visitante (País Beta)
-- Resultado esperado: Fallo con THROW 50001 y mensaje "- Conflicto de nacionalidad: el árbitro es de la misma nacionalidad que una de las selecciones del partido."
BEGIN TRY
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idPaisB int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'TB');
    DECLARE @idArbitroBeta int;

    IF NOT EXISTS (SELECT 1 FROM Arbitraje.Arbitro WHERE apellido = N'Arbitro Pais Beta')
        INSERT INTO Arbitraje.Arbitro (idPais, nombre, apellido, categoria) VALUES (@idPaisB, N'Wilmar', N'Arbitro Pais Beta', 'FIFA');
    ELSE
        UPDATE Arbitraje.Arbitro SET idPais = @idPaisB WHERE apellido = N'Arbitro Pais Beta';
    SET @idArbitroBeta = (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Arbitro Pais Beta');

    EXEC Arbitraje.cuerpoArbitral_Alta @idPartido = @idPartido, @idArbitro = @idArbitroBeta, @rol = 'Asistente 2';
    PRINT '[FALLO] PRUEBA 3.2g2 Permitió designar árbitro con nacionalidad visitante.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%Conflicto de nacionalidad%'
        PRINT '[OK] PRUEBA 3.2g2: Error conflicto de nacionalidad con visitante capturado.';
    ELSE PRINT '[FALLO] PRUEBA 3.2g2: ' + ERROR_MESSAGE();
END CATCH;
-- Revertimos país de Arbitro Beta a neutro/extra TX
UPDATE Arbitraje.Arbitro SET idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'TX') WHERE apellido = N'Arbitro Pais Beta';
GO

-- PRUEBA 3.2h: Error Alta - Acumulación masiva de errores (Partido inexistente + Árbitro inexistente + Rol inválido)
-- Resultado esperado: Fallo con THROW 50001 conteniendo los 3 errores acumulados en una única respuesta
BEGIN TRY
    EXEC Arbitraje.cuerpoArbitral_Alta @idPartido = -99999, @idArbitro = -99999, @rol = 'RolInexistente';
    PRINT '[FALLO] PRUEBA 3.2h No detectó fallas acumuladas en el alta.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE '%partido especificado no existe%'
       AND ERROR_MESSAGE() LIKE '%árbitro especificado no existe%'
       AND ERROR_MESSAGE() LIKE '%rol arbitral debe ser Principal%'
        PRINT '[OK] PRUEBA 3.2h: Acumulación masiva de 3 errores en Alta verificada con éxito.';
    ELSE PRINT '[FALLO] PRUEBA 3.2h: No acumuló todos los errores esperados -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.3: Modificación de designación exitosa ('Principal' a 'VAR')
-- Resultado esperado: Ejecución exitosa y actualización reflejada en Arbitraje.cuerpoArbitral
BEGIN TRY
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    DECLARE @idDesignacion int = (SELECT id FROM Arbitraje.cuerpoArbitral WHERE idPartido = @idPartido AND idArbitro = @idArbitroNeutro);

    EXEC Arbitraje.cuerpoArbitral_Modificacion @id = @idDesignacion, @idPartido = @idPartido, @idArbitro = @idArbitroNeutro, @rol = 'VAR';
    PRINT '[OK] PRUEBA 3.3: Designación modificada a VAR con éxito.';
    SELECT id, idPartido, idArbitro, rol FROM Arbitraje.cuerpoArbitral WHERE id = @idDesignacion;
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 3.3: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.4a: Error Modificación - Designación inexistente
-- Resultado esperado: Fallo con THROW 50001 y mensaje "- La designación arbitral a modificar no existe."
BEGIN TRY
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    EXEC Arbitraje.cuerpoArbitral_Modificacion @id = -999, @idPartido = @idPartido, @idArbitro = @idArbitroNeutro, @rol = 'VAR';
    PRINT '[FALLO] PRUEBA 3.4a No detectó designación inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%designación arbitral a modificar no existe%'
        PRINT '[OK] PRUEBA 3.4a: Error designación inexistente capturado.';
    ELSE PRINT '[FALLO] PRUEBA 3.4a: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.4b: Error Modificación - Partido destino inexistente
-- Resultado esperado: Fallo con THROW 50001 y mensaje "- El partido especificado no existe."
BEGIN TRY
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idDesignacion int = (SELECT TOP 1 id FROM Arbitraje.cuerpoArbitral WHERE idPartido = @idPartido);
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    EXEC Arbitraje.cuerpoArbitral_Modificacion @id = @idDesignacion, @idPartido = 999999, @idArbitro = @idArbitroNeutro, @rol = 'VAR';
    PRINT '[FALLO] PRUEBA 3.4b No detectó partido inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%partido especificado no existe%'
        PRINT '[OK] PRUEBA 3.4b: Error partido inexistente capturado.';
    ELSE PRINT '[FALLO] PRUEBA 3.4b: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.4c: Error Modificación - Árbitro inexistente
-- Resultado esperado: Fallo con THROW 50001 y mensaje "- El árbitro especificado no existe."
BEGIN TRY
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idDesignacion int = (SELECT TOP 1 id FROM Arbitraje.cuerpoArbitral WHERE idPartido = @idPartido);
    EXEC Arbitraje.cuerpoArbitral_Modificacion @id = @idDesignacion, @idPartido = @idPartido, @idArbitro = -999, @rol = 'VAR';
    PRINT '[FALLO] PRUEBA 3.4c No detectó árbitro inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%árbitro especificado no existe%'
        PRINT '[OK] PRUEBA 3.4c: Error árbitro inexistente capturado.';
    ELSE PRINT '[FALLO] PRUEBA 3.4c: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.4d: Error Modificación - Rol inválido
-- Resultado esperado: Fallo con THROW 50001 y mensaje conteniendo "El rol arbitral debe ser Principal, Asistente 1..."
BEGIN TRY
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idDesignacion int = (SELECT TOP 1 id FROM Arbitraje.cuerpoArbitral WHERE idPartido = @idPartido);
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    EXEC Arbitraje.cuerpoArbitral_Modificacion @id = @idDesignacion, @idPartido = @idPartido, @idArbitro = @idArbitroNeutro, @rol = 'INVENTADO';
    PRINT '[FALLO] PRUEBA 3.4d No detectó rol inválido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%rol arbitral debe ser Principal%'
        PRINT '[OK] PRUEBA 3.4d: Error rol inválido capturado.';
    ELSE PRINT '[FALLO] PRUEBA 3.4d: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.4e1: Error Modificación - Partido original en estado 'Finalizado'
-- Resultado esperado: Fallo con THROW 50001 y mensaje "- No se pueden modificar designaciones de un partido ya finalizado o en juego."
BEGIN TRY
    DECLARE @idPartidoFin int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99902);
    DECLARE @idArbitroBeta int = (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Arbitro Pais Beta');
    DECLARE @idDesigFin int;

    INSERT INTO Arbitraje.cuerpoArbitral (idPartido, idArbitro, rol) VALUES (@idPartidoFin, @idArbitroBeta, 'Principal');
    SET @idDesigFin = SCOPE_IDENTITY();

    EXEC Arbitraje.cuerpoArbitral_Modificacion @id = @idDesigFin, @idPartido = @idPartidoFin, @idArbitro = @idArbitroBeta, @rol = 'VAR';
    PRINT '[FALLO] PRUEBA 3.4e1 Permitió modificar designación de partido finalizado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%partido ya finalizado o en juego%'
        PRINT '[OK] PRUEBA 3.4e1: Error partido original finalizado capturado.';
    ELSE PRINT '[FALLO] PRUEBA 3.4e1: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.4e2: Error Modificación - Partido original en estado 'En juego'
-- Resultado esperado: Fallo con THROW 50001 y mensaje "- No se pueden modificar designaciones de un partido ya finalizado o en juego."
BEGIN TRY
    DECLARE @idPartidoJuego int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99903);
    DECLARE @idArbitroBeta int = (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Arbitro Pais Beta');
    DECLARE @idDesigJuego int;

    INSERT INTO Arbitraje.cuerpoArbitral (idPartido, idArbitro, rol) VALUES (@idPartidoJuego, @idArbitroBeta, 'Principal');
    SET @idDesigJuego = SCOPE_IDENTITY();

    EXEC Arbitraje.cuerpoArbitral_Modificacion @id = @idDesigJuego, @idPartido = @idPartidoJuego, @idArbitro = @idArbitroBeta, @rol = 'VAR';
    PRINT '[FALLO] PRUEBA 3.4e2 Permitió modificar designación de partido en juego.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%partido ya finalizado o en juego%'
        PRINT '[OK] PRUEBA 3.4e2: Error partido original en juego capturado.';
    ELSE PRINT '[FALLO] PRUEBA 3.4e2: ' + ERROR_MESSAGE();
END CATCH;
DELETE FROM Arbitraje.cuerpoArbitral WHERE id = @idDesigJuego;
GO

-- PRUEBA 3.4f1: Error Modificación - Partido destino en estado 'Finalizado'
-- Resultado esperado: Fallo con THROW 50001 y mensaje "- No se puede trasladar la designación a un partido ya finalizado o en juego."
BEGIN TRY
    DECLARE @idPartidoProg int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idPartidoFin int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99902);
    DECLARE @idDesigProg int = (SELECT TOP 1 id FROM Arbitraje.cuerpoArbitral WHERE idPartido = @idPartidoProg);
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');

    EXEC Arbitraje.cuerpoArbitral_Modificacion @id = @idDesigProg, @idPartido = @idPartidoFin, @idArbitro = @idArbitroNeutro, @rol = 'Cuarto Arbitro';
    PRINT '[FALLO] PRUEBA 3.4f1 Permitió trasladar designación a partido finalizado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%trasladar la designación a un partido ya finalizado o en juego%'
        PRINT '[OK] PRUEBA 3.4f1: Error traslado a partido finalizado capturado.';
    ELSE PRINT '[FALLO] PRUEBA 3.4f1: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.4f2: Error Modificación - Partido destino en estado 'En juego'
-- Resultado esperado: Fallo con THROW 50001 y mensaje "- No se puede trasladar la designación a un partido ya finalizado o en juego."
BEGIN TRY
    DECLARE @idPartidoProg int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idPartidoJuego int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99903);
    DECLARE @idDesigProg int = (SELECT TOP 1 id FROM Arbitraje.cuerpoArbitral WHERE idPartido = @idPartidoProg);
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');

    EXEC Arbitraje.cuerpoArbitral_Modificacion @id = @idDesigProg, @idPartido = @idPartidoJuego, @idArbitro = @idArbitroNeutro, @rol = 'Cuarto Arbitro';
    PRINT '[FALLO] PRUEBA 3.4f2 Permitió trasladar designación a partido en juego.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%trasladar la designación a un partido ya finalizado o en juego%'
        PRINT '[OK] PRUEBA 3.4f2: Error traslado a partido en juego capturado.';
    ELSE PRINT '[FALLO] PRUEBA 3.4f2: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.4g: Error Modificación - Cambio de árbitro/partido bloqueado si ya existen informes arbitrales
-- Resultado esperado: Fallo con THROW 50001 y mensaje "- No se puede modificar el árbitro o partido de la designación porque ya posee informes arbitrales registrados."
BEGIN TRY
    DECLARE @idPartidoFin int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99902);
    DECLARE @idArbitroBeta int = (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Arbitro Pais Beta');
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    DECLARE @idDesigFin int = (SELECT id FROM Arbitraje.cuerpoArbitral WHERE idPartido = @idPartidoFin AND idArbitro = @idArbitroBeta);

    -- Insertamos informe arbitral vinculado
    INSERT INTO Arbitraje.InformeArbitral (idPartido, idArbitro, fecha, esSancion, detalle)
    VALUES (@idPartidoFin, @idArbitroBeta, '2026-06-14', 0, 'Informe del partido');

    -- Temporalmente pasamos el partido a 'Programado' para aislar la validación de informes
    UPDATE Torneo.Partido SET estado = 'Programado' WHERE idPartido = @idPartidoFin;

    -- Intentamos cambiar el árbitro de la designación que tiene informe
    EXEC Arbitraje.cuerpoArbitral_Modificacion @id = @idDesigFin, @idPartido = @idPartidoFin, @idArbitro = @idArbitroNeutro, @rol = 'Principal';
    PRINT '[FALLO] PRUEBA 3.4g Permitió cambiar árbitro de una designación con informes registrados.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%ya posee informes arbitrales registrados%'
        PRINT '[OK] PRUEBA 3.4g: Error modificación de árbitro con informes arbitrales capturado.';
    ELSE PRINT '[FALLO] PRUEBA 3.4g: ' + ERROR_MESSAGE();
END CATCH;
-- Revertimos estado del partido 99902 y eliminamos informe auxiliar
UPDATE Torneo.Partido SET estado = 'Finalizado' WHERE nroPartidoOficial = 99902;
DELETE FROM Arbitraje.InformeArbitral WHERE idPartido = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99902);
DELETE FROM Arbitraje.cuerpoArbitral WHERE idPartido = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99902);
GO

-- PRUEBA 3.4h: Error Modificación - Rol ya cubierto por otro árbitro
-- Resultado esperado: Fallo con THROW 50001 y mensaje "- El rol ya se encuentra cubierto por otro árbitro en este partido."
BEGIN TRY
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idArbitroBeta int = (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Arbitro Pais Beta');
    DECLARE @idDesigBeta int;

    -- Asignamos al árbitro Beta como Asistente 1
    EXEC Arbitraje.cuerpoArbitral_Alta @idPartido = @idPartido, @idArbitro = @idArbitroBeta, @rol = 'Asistente 1', @id = @idDesigBeta OUTPUT;

    -- Intentamos cambiar al árbitro Beta a 'VAR' (que ya está cubierto por Collina)
    EXEC Arbitraje.cuerpoArbitral_Modificacion @id = @idDesigBeta, @idPartido = @idPartido, @idArbitro = @idArbitroBeta, @rol = 'VAR';
    PRINT '[FALLO] PRUEBA 3.4h Permitió modificar a un rol ya cubierto.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%rol ya se encuentra cubierto por otro árbitro%'
        PRINT '[OK] PRUEBA 3.4h: Error rol ya cubierto en modificación capturado.';
    ELSE PRINT '[FALLO] PRUEBA 3.4h: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.4i: Error Modificación - Árbitro ya posee otro rol en el partido
-- Resultado esperado: Fallo con THROW 50001 y mensaje "- El árbitro ya posee otro rol asignado en este mismo partido."
BEGIN TRY
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    DECLARE @idDesigBeta int = (SELECT id FROM Arbitraje.cuerpoArbitral WHERE idPartido = @idPartido AND rol = 'Asistente 1');

    -- Intentamos asignar en la designación de Asistente 1 a Collina (que ya es VAR)
    EXEC Arbitraje.cuerpoArbitral_Modificacion @id = @idDesigBeta, @idPartido = @idPartido, @idArbitro = @idArbitroNeutro, @rol = 'Asistente 1';
    PRINT '[FALLO] PRUEBA 3.4i Permitió duplicar árbitro en distintos roles.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%árbitro ya posee otro rol asignado en este mismo partido%'
        PRINT '[OK] PRUEBA 3.4i: Error árbitro con otro rol en modificación capturado.';
    ELSE PRINT '[FALLO] PRUEBA 3.4i: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.4j1: Error Modificación - Conflicto de nacionalidad con Selección Local (País Alfa)
-- Resultado esperado: Fallo con THROW 50001 y mensaje "- Conflicto de nacionalidad: el árbitro es de la misma nacionalidad que una de las selecciones del partido."
BEGIN TRY
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idArbitroAlfa int = (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Arbitro Pais Alfa');
    DECLARE @idDesigBeta int = (SELECT id FROM Arbitraje.cuerpoArbitral WHERE idPartido = @idPartido AND rol = 'Asistente 1');

    EXEC Arbitraje.cuerpoArbitral_Modificacion @id = @idDesigBeta, @idPartido = @idPartido, @idArbitro = @idArbitroAlfa, @rol = 'Asistente 1';
    PRINT '[FALLO] PRUEBA 3.4j1 Permitió conflicto de nacionalidad con selección local en modificación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%Conflicto de nacionalidad%'
        PRINT '[OK] PRUEBA 3.4j1: Error conflicto de nacionalidad con local en modificación capturado.';
    ELSE PRINT '[FALLO] PRUEBA 3.4j1: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.4j2: Error Modificación - Conflicto de nacionalidad con Selección Visitante (País Beta)
-- Resultado esperado: Fallo con THROW 50001 y mensaje "- Conflicto de nacionalidad: el árbitro es de la misma nacionalidad que una de las selecciones del partido."
BEGIN TRY
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idPaisB int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'TB');
    DECLARE @idArbitroBeta int = (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Arbitro Pais Beta');
    DECLARE @idDesigBeta int = (SELECT id FROM Arbitraje.cuerpoArbitral WHERE idPartido = @idPartido AND rol = 'Asistente 1');

    -- Cambiamos temporalmente país de Arbitro Beta a TB para generar el conflicto
    UPDATE Arbitraje.Arbitro SET idPais = @idPaisB WHERE idArbitro = @idArbitroBeta;

    EXEC Arbitraje.cuerpoArbitral_Modificacion @id = @idDesigBeta, @idPartido = @idPartido, @idArbitro = @idArbitroBeta, @rol = 'Asistente 1';
    PRINT '[FALLO] PRUEBA 3.4j2 Permitió conflicto de nacionalidad con selección visitante en modificación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%Conflicto de nacionalidad%'
        PRINT '[OK] PRUEBA 3.4j2: Error conflicto de nacionalidad con visitante en modificación capturado.';
    ELSE PRINT '[FALLO] PRUEBA 3.4j2: ' + ERROR_MESSAGE();
END CATCH;
-- Revertimos país de Arbitro Beta a neutral TX
UPDATE Arbitraje.Arbitro SET idPais = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'TX') WHERE apellido = N'Arbitro Pais Beta';
GO

-- PRUEBA 3.4k: Error Modificación - Acumulación masiva de errores (Designación inexistente + Partido inexistente + Árbitro inexistente + Rol inválido)
-- Resultado esperado: Fallo con THROW 50001 conteniendo las 4 fallas agrupadas en el mensaje
BEGIN TRY
    EXEC Arbitraje.cuerpoArbitral_Modificacion @id = -99999, @idPartido = -99999, @idArbitro = -99999, @rol = 'RolInexistente';
    PRINT '[FALLO] PRUEBA 3.4k No detectó fallas acumuladas en modificación.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE '%designación arbitral a modificar no existe%'
       AND ERROR_MESSAGE() LIKE '%partido especificado no existe%'
       AND ERROR_MESSAGE() LIKE '%árbitro especificado no existe%'
       AND ERROR_MESSAGE() LIKE '%rol arbitral debe ser Principal%'
        PRINT '[OK] PRUEBA 3.4k: Acumulación masiva de 4 errores en Modificación verificada con éxito.';
    ELSE PRINT '[FALLO] PRUEBA 3.4k: No acumuló todos los errores esperados -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.5a: Error Baja - Designación inexistente
-- Resultado esperado: Fallo con THROW 50001 y mensaje "- La designación arbitral a eliminar no existe."
BEGIN TRY
    EXEC Arbitraje.cuerpoArbitral_Baja @id = -999;
    PRINT '[FALLO] PRUEBA 3.5a No detectó designación inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%designación arbitral a eliminar no existe%'
        PRINT '[OK] PRUEBA 3.5a: Error designación a eliminar inexistente capturado.';
    ELSE PRINT '[FALLO] PRUEBA 3.5a: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.5b1: Error Baja - Partido en estado 'Finalizado'
-- Resultado esperado: Fallo con THROW 50001 y mensaje "- No se puede eliminar la designación arbitral de un partido ya finalizado o en juego."
BEGIN TRY
    DECLARE @idPartidoFin int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99902);
    DECLARE @idArbitroBeta int = (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Arbitro Pais Beta');
    DECLARE @idDesigFin int;

    INSERT INTO Arbitraje.cuerpoArbitral (idPartido, idArbitro, rol) VALUES (@idPartidoFin, @idArbitroBeta, 'Principal');
    SET @idDesigFin = SCOPE_IDENTITY();

    EXEC Arbitraje.cuerpoArbitral_Baja @id = @idDesigFin;
    PRINT '[FALLO] PRUEBA 3.5b1 Permitió dar de baja designación en partido finalizado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%partido ya finalizado o en juego%'
        PRINT '[OK] PRUEBA 3.5b1: Error baja en partido finalizado capturado.';
    ELSE PRINT '[FALLO] PRUEBA 3.5b1: ' + ERROR_MESSAGE();
END CATCH;
DELETE FROM Arbitraje.cuerpoArbitral WHERE id = @idDesigFin;
GO

-- PRUEBA 3.5b2: Error Baja - Partido actualmente en estado 'En juego'
-- Resultado esperado: Fallo con THROW 50001 y mensaje "- No se puede eliminar la designación arbitral de un partido ya finalizado o en juego."
BEGIN TRY
    DECLARE @idPartidoJuego int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99903);
    DECLARE @idArbitroBeta int = (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Arbitro Pais Beta');
    DECLARE @idDesigJuego int;

    INSERT INTO Arbitraje.cuerpoArbitral (idPartido, idArbitro, rol) VALUES (@idPartidoJuego, @idArbitroBeta, 'Principal');
    SET @idDesigJuego = SCOPE_IDENTITY();

    EXEC Arbitraje.cuerpoArbitral_Baja @id = @idDesigJuego;
    PRINT '[FALLO] PRUEBA 3.5b2 Permitió dar de baja designación en partido en juego.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%partido ya finalizado o en juego%'
        PRINT '[OK] PRUEBA 3.5b2: Error baja en partido en juego capturado.';
    ELSE PRINT '[FALLO] PRUEBA 3.5b2: ' + ERROR_MESSAGE();
END CATCH;
DELETE FROM Arbitraje.cuerpoArbitral WHERE id = @idDesigJuego;
GO

-- PRUEBA 3.5c: Error Baja - Árbitro posee informes arbitrales para este partido
-- Resultado esperado: Fallo con THROW 50001 y mensaje "- No se puede eliminar la designación porque el árbitro posee informes arbitrales registrados para este partido."
BEGIN TRY
    DECLARE @idPartidoProg int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idArbitroBeta int = (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Arbitro Pais Beta');
    DECLARE @idDesigBeta int = (SELECT id FROM Arbitraje.cuerpoArbitral WHERE idPartido = @idPartidoProg AND idArbitro = @idArbitroBeta);

    -- Insertamos informe asociado
    INSERT INTO Arbitraje.InformeArbitral (idPartido, idArbitro, fecha, esSancion, detalle)
    VALUES (@idPartidoProg, @idArbitroBeta, '2026-06-15', 0, 'Informe test');

    EXEC Arbitraje.cuerpoArbitral_Baja @id = @idDesigBeta;
    PRINT '[FALLO] PRUEBA 3.5c Permitió eliminar designación con informes vinculados.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%posee informes arbitrales registrados para este partido%'
        PRINT '[OK] PRUEBA 3.5c: Error baja con informes vinculados capturado.';
    ELSE PRINT '[FALLO] PRUEBA 3.5c: ' + ERROR_MESSAGE();
END CATCH;
DELETE FROM Arbitraje.InformeArbitral WHERE idPartido = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
GO

-- PRUEBA 3.6: Baja exitosa de designación auxiliar
-- Resultado esperado: Eliminación limpia del registro sin errores
BEGIN TRY
    DECLARE @idPartidoProg int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idArbitroBeta int = (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Arbitro Pais Beta');
    DECLARE @idDesigBeta int = (SELECT id FROM Arbitraje.cuerpoArbitral WHERE idPartido = @idPartidoProg AND idArbitro = @idArbitroBeta);

    EXEC Arbitraje.cuerpoArbitral_Baja @id = @idDesigBeta;
    PRINT '[OK] PRUEBA 3.6: Baja de designación auxiliar ejecutada con éxito.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 3.6: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   SECCIÓN 4: PRUEBAS SOBRE Arbitraje.InformeArbitral
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 4. PRUEBAS: Arbitraje.InformeArbitral';
PRINT '--------------------------------------------------------------------------------';

-- PRUEBA 4.2d: Error Alta - Partido aún programado
BEGIN TRY
    DECLARE @idPartidoProg int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');

    EXEC Arbitraje.InformeArbitral_Alta @idPartido = @idPartidoProg, @idArbitro = @idArbitroNeutro, @fecha = '2026-06-16', @esSancion = 0, @detalle = N'Informe prematuro';
    PRINT '[FALLO] PRUEBA 4.2d Permitió registrar informe en partido programado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%todavía se encuentra programado%'
        PRINT '[OK] PRUEBA 4.2d: Error informe en partido programado capturado.';
    ELSE PRINT '[FALLO] PRUEBA 4.2d: ' + ERROR_MESSAGE();
END CATCH;
GO

-- Transición del partido 99901 a Finalizado para probar altas válidas de informes post-partido
UPDATE Torneo.Partido SET estado = 'Finalizado', golLocal = 2, golVisitante = 1 WHERE nroPartidoOficial = 99901;
GO

-- PRUEBA 4.2a: Error Alta - Partido inexistente
BEGIN TRY
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    EXEC Arbitraje.InformeArbitral_Alta @idPartido = 999999, @idArbitro = @idArbitroNeutro, @fecha = '2026-06-16', @esSancion = 0, @detalle = N'Test';
    PRINT '[FALLO] PRUEBA 4.2a No detectó partido inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%partido especificado no existe%'
        PRINT '[OK] PRUEBA 4.2a: Error partido inexistente capturado.';
    ELSE PRINT '[FALLO] PRUEBA 4.2a: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 4.2b: Error Alta - Árbitro inexistente
BEGIN TRY
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    EXEC Arbitraje.InformeArbitral_Alta @idPartido = @idPartido, @idArbitro = -999, @fecha = '2026-06-16', @esSancion = 0, @detalle = N'Test';
    PRINT '[FALLO] PRUEBA 4.2b No detectó árbitro inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%árbitro especificado no existe%'
        PRINT '[OK] PRUEBA 4.2b: Error árbitro inexistente capturado.';
    ELSE PRINT '[FALLO] PRUEBA 4.2b: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 4.2c: Error Alta - Árbitro no formó parte del cuerpo arbitral
BEGIN TRY
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idArbitroAjeno int = (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Arbitro Pais Alfa');

    EXEC Arbitraje.InformeArbitral_Alta @idPartido = @idPartido, @idArbitro = @idArbitroAjeno, @fecha = '2026-06-16', @esSancion = 0, @detalle = N'Informe ajeno';
    PRINT '[FALLO] PRUEBA 4.2c Permitió informe de árbitro ajeno al partido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%árbitro no formó parte del cuerpo arbitral%'
        PRINT '[OK] PRUEBA 4.2c: Error árbitro no participante capturado.';
    ELSE PRINT '[FALLO] PRUEBA 4.2c: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 4.2e: Error Alta - Fecha nula
BEGIN TRY
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');

    EXEC Arbitraje.InformeArbitral_Alta @idPartido = @idPartido, @idArbitro = @idArbitroNeutro, @fecha = NULL, @esSancion = 0, @detalle = N'Informe sin fecha';
    PRINT '[FALLO] PRUEBA 4.2e No detectó fecha nula.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%fecha del informe es obligatoria%'
        PRINT '[OK] PRUEBA 4.2e: Error fecha obligatoria capturado.';
    ELSE PRINT '[FALLO] PRUEBA 4.2e: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 4.2f: Error Alta - Fecha anterior a la disputa del partido
BEGIN TRY
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');

    -- El partido se jugó el 2026-06-15; intentamos fecha 2026-06-10
    EXEC Arbitraje.InformeArbitral_Alta @idPartido = @idPartido, @idArbitro = @idArbitroNeutro, @fecha = '2026-06-10', @esSancion = 0, @detalle = N'Informe fecha vieja';
    PRINT '[FALLO] PRUEBA 4.2f No detectó fecha anterior a la del partido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%no puede ser anterior a la fecha de disputa%'
        PRINT '[OK] PRUEBA 4.2f: Error fecha anterior a partido capturado.';
    ELSE PRINT '[FALLO] PRUEBA 4.2f: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 4.2g: Error Alta - Bandera esSancion nula
BEGIN TRY
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');

    EXEC Arbitraje.InformeArbitral_Alta @idPartido = @idPartido, @idArbitro = @idArbitroNeutro, @fecha = '2026-06-16', @esSancion = NULL, @detalle = N'Informe sin tipo';
    PRINT '[FALLO] PRUEBA 4.2g No detectó esSancion nula.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%Debe indicar si el informe corresponde a una sanción%'
        PRINT '[OK] PRUEBA 4.2g: Error bandera esSancion obligatoria capturado.';
    ELSE PRINT '[FALLO] PRUEBA 4.2g: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 4.2h: Error Alta - Sanción requiere detalle obligatorio
BEGIN TRY
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');

    EXEC Arbitraje.InformeArbitral_Alta @idPartido = @idPartido, @idArbitro = @idArbitroNeutro, @fecha = '2026-06-16', @esSancion = 1, @detalle = N'   ';
    PRINT '[FALLO] PRUEBA 4.2h Permitió registrar sanción sin detalle.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%requieren consignar el detalle de la sanción%'
        PRINT '[OK] PRUEBA 4.2h: Error sanción sin detalle capturado.';
    ELSE PRINT '[FALLO] PRUEBA 4.2h: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 4.1: Alta de informe arbitral exitoso
BEGIN TRY
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    DECLARE @idInformeGenerado int;

    EXEC Arbitraje.InformeArbitral_Alta
        @idPartido  = @idPartido,
        @idArbitro  = @idArbitroNeutro,
        @fecha      = '2026-06-16',
        @esSancion  = 1,
        @detalle    = N'Sanción por conducta antideportiva en el banco de suplentes.',
        @id         = @idInformeGenerado OUTPUT;

    PRINT '[OK] PRUEBA 4.1: Informe arbitral registrado con ID = ' + CAST(@idInformeGenerado AS varchar(10));
    SELECT id, idPartido, idArbitro, fecha, esSancion, detalle FROM Arbitraje.InformeArbitral WHERE id = @idInformeGenerado;
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 4.1: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 4.3: Modificación exitosa de informe arbitral
BEGIN TRY
    DECLARE @idInforme int = (SELECT TOP 1 id FROM Arbitraje.InformeArbitral WHERE detalle LIKE '%conducta antideportiva%');
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');

    EXEC Arbitraje.InformeArbitral_Modificacion
        @id        = @idInforme,
        @idPartido = @idPartido,
        @idArbitro = @idArbitroNeutro,
        @fecha     = '2026-06-17',
        @esSancion = 1,
        @detalle   = N'Sanción ratificada con apercibimiento formal del tribunal disciplinario.';

    PRINT '[OK] PRUEBA 4.3: Informe arbitral modificado con éxito.';
    SELECT id, fecha, esSancion, detalle FROM Arbitraje.InformeArbitral WHERE id = @idInforme;
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 4.3: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 4.4a: Error Modificación - Informe inexistente
BEGIN TRY
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');

    EXEC Arbitraje.InformeArbitral_Modificacion @id = -999, @idPartido = @idPartido, @idArbitro = @idArbitroNeutro, @fecha = '2026-06-17', @esSancion = 0, @detalle = N'Test';
    PRINT '[FALLO] PRUEBA 4.4a No detectó informe inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%informe arbitral a modificar no existe%'
        PRINT '[OK] PRUEBA 4.4a: Error informe a modificar inexistente capturado.';
    ELSE PRINT '[FALLO] PRUEBA 4.4a: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 4.4b: Error Modificación - Partido inexistente
BEGIN TRY
    DECLARE @idInforme int = (SELECT TOP 1 id FROM Arbitraje.InformeArbitral WHERE detalle LIKE '%apercibimiento formal%');
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');

    EXEC Arbitraje.InformeArbitral_Modificacion @id = @idInforme, @idPartido = 999999, @idArbitro = @idArbitroNeutro, @fecha = '2026-06-17', @esSancion = 0, @detalle = N'Test';
    PRINT '[FALLO] PRUEBA 4.4b No detectó partido inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%partido especificado no existe%'
        PRINT '[OK] PRUEBA 4.4b: Error partido inexistente en modificación capturado.';
    ELSE PRINT '[FALLO] PRUEBA 4.4b: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 4.4c: Error Modificación - Árbitro inexistente
BEGIN TRY
    DECLARE @idInforme int = (SELECT TOP 1 id FROM Arbitraje.InformeArbitral WHERE detalle LIKE '%apercibimiento formal%');
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);

    EXEC Arbitraje.InformeArbitral_Modificacion @id = @idInforme, @idPartido = @idPartido, @idArbitro = -999, @fecha = '2026-06-17', @esSancion = 0, @detalle = N'Test';
    PRINT '[FALLO] PRUEBA 4.4c No detectó árbitro inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%árbitro especificado no existe%'
        PRINT '[OK] PRUEBA 4.4c: Error árbitro inexistente en modificación capturado.';
    ELSE PRINT '[FALLO] PRUEBA 4.4c: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 4.4d: Error Modificación - Árbitro no formó parte del cuerpo arbitral
BEGIN TRY
    DECLARE @idInforme int = (SELECT TOP 1 id FROM Arbitraje.InformeArbitral WHERE detalle LIKE '%apercibimiento formal%');
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idArbitroAjeno int = (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Arbitro Pais Alfa');

    EXEC Arbitraje.InformeArbitral_Modificacion @id = @idInforme, @idPartido = @idPartido, @idArbitro = @idArbitroAjeno, @fecha = '2026-06-17', @esSancion = 0, @detalle = N'Test';
    PRINT '[FALLO] PRUEBA 4.4d Permitió modificar informe asignándolo a árbitro ajeno.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%árbitro no formó parte del cuerpo arbitral%'
        PRINT '[OK] PRUEBA 4.4d: Error árbitro no participante en modificación capturado.';
    ELSE PRINT '[FALLO] PRUEBA 4.4d: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 4.4e: Error Modificación - Partido en estado programado
BEGIN TRY
    DECLARE @idInforme int = (SELECT TOP 1 id FROM Arbitraje.InformeArbitral WHERE detalle LIKE '%apercibimiento formal%');
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');
    DECLARE @idPartidoProg int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);

    -- Pasamos temporalmente a programado para verificar el chequeo
    UPDATE Torneo.Partido SET estado = 'Programado', golLocal = NULL, golVisitante = NULL WHERE nroPartidoOficial = 99901;

    EXEC Arbitraje.InformeArbitral_Modificacion
        @id        = @idInforme,
        @idPartido = @idPartidoProg,
        @idArbitro = @idArbitroNeutro,
        @fecha     = '2026-06-17',
        @esSancion = 0,
        @detalle   = N'Test';
    PRINT '[FALLO] PRUEBA 4.4e Permitió modificar informe en partido programado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%todavía se encuentra programado%'
        PRINT '[OK] PRUEBA 4.4e: Error modificación en partido programado capturado.';
    ELSE PRINT '[FALLO] PRUEBA 4.4e: ' + ERROR_MESSAGE();
END CATCH;
UPDATE Torneo.Partido SET estado = 'Finalizado', golLocal = 2, golVisitante = 1 WHERE nroPartidoOficial = 99901;
GO

-- PRUEBA 4.4f: Error Modificación - Fecha nula
BEGIN TRY
    DECLARE @idInforme int = (SELECT TOP 1 id FROM Arbitraje.InformeArbitral WHERE detalle LIKE '%apercibimiento formal%');
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');

    EXEC Arbitraje.InformeArbitral_Modificacion @id = @idInforme, @idPartido = @idPartido, @idArbitro = @idArbitroNeutro, @fecha = NULL, @esSancion = 0, @detalle = N'Test';
    PRINT '[FALLO] PRUEBA 4.4f No detectó fecha nula.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%fecha del informe es obligatoria%'
        PRINT '[OK] PRUEBA 4.4f: Error fecha nula en modificación capturado.';
    ELSE PRINT '[FALLO] PRUEBA 4.4f: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 4.4g: Error Modificación - Fecha anterior al partido
BEGIN TRY
    DECLARE @idInforme int = (SELECT TOP 1 id FROM Arbitraje.InformeArbitral WHERE detalle LIKE '%apercibimiento formal%');
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');

    EXEC Arbitraje.InformeArbitral_Modificacion @id = @idInforme, @idPartido = @idPartido, @idArbitro = @idArbitroNeutro, @fecha = '2026-06-01', @esSancion = 0, @detalle = N'Test';
    PRINT '[FALLO] PRUEBA 4.4g No detectó fecha anterior al partido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%no puede ser anterior a la fecha de disputa%'
        PRINT '[OK] PRUEBA 4.4g: Error fecha anterior en modificación capturado.';
    ELSE PRINT '[FALLO] PRUEBA 4.4g: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 4.4h: Error Modificación - Bandera esSancion nula
BEGIN TRY
    DECLARE @idInforme int = (SELECT TOP 1 id FROM Arbitraje.InformeArbitral WHERE detalle LIKE '%apercibimiento formal%');
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');

    EXEC Arbitraje.InformeArbitral_Modificacion @id = @idInforme, @idPartido = @idPartido, @idArbitro = @idArbitroNeutro, @fecha = '2026-06-17', @esSancion = NULL, @detalle = N'Test';
    PRINT '[FALLO] PRUEBA 4.4h No detectó esSancion nula.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%Debe indicar si el informe corresponde a una sanción%'
        PRINT '[OK] PRUEBA 4.4h: Error esSancion nula en modificación capturado.';
    ELSE PRINT '[FALLO] PRUEBA 4.4h: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 4.4i: Error Modificación - Sanción sin detalle
BEGIN TRY
    DECLARE @idInforme int = (SELECT TOP 1 id FROM Arbitraje.InformeArbitral WHERE detalle LIKE '%apercibimiento formal%');
    DECLARE @idPartido int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');

    EXEC Arbitraje.InformeArbitral_Modificacion @id = @idInforme, @idPartido = @idPartido, @idArbitro = @idArbitroNeutro, @fecha = '2026-06-17', @esSancion = 1, @detalle = N'';
    PRINT '[FALLO] PRUEBA 4.4i Permitió modificar sanción dejándola sin detalle.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%requieren consignar el detalle de la sanción%'
        PRINT '[OK] PRUEBA 4.4i: Error sanción sin detalle en modificación capturado.';
    ELSE PRINT '[FALLO] PRUEBA 4.4i: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 4.5a: Error Baja - Informe inexistente
BEGIN TRY
    EXEC Arbitraje.InformeArbitral_Baja @id = -999;
    PRINT '[FALLO] PRUEBA 4.5a No detectó informe inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%informe arbitral a eliminar no existe%'
        PRINT '[OK] PRUEBA 4.5a: Error informe a eliminar inexistente capturado.';
    ELSE PRINT '[FALLO] PRUEBA 4.5a: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 4.6: Baja exitosa de informe arbitral
BEGIN TRY
    DECLARE @idInforme int = (SELECT TOP 1 id FROM Arbitraje.InformeArbitral WHERE detalle LIKE '%apercibimiento formal%');
    EXEC Arbitraje.InformeArbitral_Baja @id = @idInforme;
    PRINT '[OK] PRUEBA 4.6: Baja de informe arbitral ejecutada con éxito.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 4.6: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   SECCIÓN 5: PRUEBAS COMPLEMENTARIAS DE INTEGRIDAD Y BAJAS EN CASCADA
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 5. PRUEBAS: Integridad final y baja en cascada segura';
PRINT '--------------------------------------------------------------------------------';

-- Revertimos el partido a Programado para dar de baja la designación de Collina
UPDATE Torneo.Partido SET estado = 'Programado', golLocal = NULL, golVisitante = NULL WHERE nroPartidoOficial = 99901;

-- Baja de designación de Collina
DECLARE @idPartidoProg int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99901);
DECLARE @idDesigCollina int = (SELECT id FROM Arbitraje.cuerpoArbitral WHERE idPartido = @idPartidoProg);
EXEC Arbitraje.cuerpoArbitral_Baja @id = @idDesigCollina;
PRINT '[OK] PRUEBA 5.1: Designación de Collina removida correctamente.';
GO

-- PRUEBA 5.2: Baja de árbitro con verificación atómica de borrado en cascada de idiomas
BEGIN TRY
    DECLARE @idArbitroNeutro int = (SELECT TOP 1 idArbitro FROM Arbitraje.Arbitro WHERE apellido = N'Collina Test');

    -- Insertamos idioma para probar la cascada manual de Arbitro_Baja
    EXEC Arbitraje.ArbitroIdioma_Alta @idArbitro = @idArbitroNeutro, @idioma = 'es';

    -- Ejecutamos la baja del árbitro
    EXEC Arbitraje.Arbitro_Baja @idArbitro = @idArbitroNeutro;
    PRINT '[OK] PRUEBA 5.2: Árbitro Collina y sus idiomas eliminados en cascada de forma atómica.';

    -- Evidencia de eliminación total
    SELECT COUNT(*) AS [ExisteArbitroCollina] FROM Arbitraje.Arbitro WHERE idArbitro = @idArbitroNeutro;
    SELECT COUNT(*) AS [ExistenIdiomasCollina] FROM Arbitraje.ArbitroIdioma WHERE idArbitro = @idArbitroNeutro;
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 5.2: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   LIMPIEZA FINAL DEL ENTORNO DE PRUEBAS
   ============================================================================= */
PRINT '--- Limpiando fixture auxiliar de pruebas ---';

DELETE FROM Arbitraje.InformeArbitral WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99901, 99902, 99903));
DELETE FROM Arbitraje.cuerpoArbitral WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial IN (99901, 99902, 99903));
DELETE FROM Arbitraje.ArbitroIdioma WHERE idArbitro IN (SELECT idArbitro FROM Arbitraje.Arbitro WHERE apellido IN (N'Collina Test', N'Arbitro Pais Alfa', N'Arbitro Pais Beta', N'Arbitro Duplicado'));
DELETE FROM Arbitraje.Arbitro WHERE apellido IN (N'Collina Test', N'Arbitro Pais Alfa', N'Arbitro Pais Beta', N'Arbitro Duplicado');
DELETE FROM Torneo.Partido WHERE nroPartidoOficial IN (99901, 99902, 99903);
DELETE FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test Arbitraje';
DELETE FROM Torneo.Fase WHERE idFase = 999;
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('TFA', 'TFB');
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('TA', 'TB', 'TN', 'TX');

PRINT 'Fixture de pruebas limpiado con éxito.';
PRINT '================================================================================';
PRINT ' BATERÍA DE PRUEBAS EXHAUSTIVA FINALIZADA';
PRINT '================================================================================';
GO
