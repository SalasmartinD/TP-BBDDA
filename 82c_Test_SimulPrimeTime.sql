/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel - 45066788
               Salas, Martin Daniel - 45205702
               Zito Padró, Ezequiel Nehuén - 46097917
 Fecha       : 09/11/2026

 Objetivo    : Suite de pruebas unitarias para 32_SimulPrimeTime.sql
               - Publicidad.SimularPrimeTimePartido (filtra mercados candidatos)
               - Publicidad.SimularPrimeTimePorPais (todos los países registrados)
               Verifica conversiones AT TIME ZONE, franja horaria contra
               Sistema.Parametro (PRIME_TIME_INICIO / PRIME_TIME_FIN) y validaciones.

 Estándares aplicados:
 - Relación 1:1 con 32_SimulPrimeTime.sql.
 - Idempotencia absoluta.
 - Validación de errores (código THROW 50001 en partido inexistente).
 - Verificación precisa del flag esPrimeTime.
================================================================================
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

PRINT '================================================================================';
PRINT ' INICIANDO BATERÍA DE PRUEBAS: 32_SimulPrimeTime.sql';
PRINT '================================================================================';
GO

/* =============================================================================
   CASOS DE PRUEBA: Publicidad.SimularPrimeTimePartido
   ============================================================================= */

-- PRUEBA 1.1: Error al simular con partido inexistente
BEGIN TRY
    EXEC Publicidad.SimularPrimeTimePartido @idPartido = 999999;
    PRINT '[FALLO] PRUEBA 1.1: No detectó partido inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%no existe%'
        PRINT '[OK] PRUEBA 1.1: Error partido inexistente capturado correctamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 1.1: Error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.2: Simulación exitosa sobre el partido del CASO OBLIGATORIO (Argentina vs Brasil 18:00 UTC)
BEGIN TRY
    -- Obtenemos el id del partido oficial 1 cargado por el seed
    DECLARE @idPartidoCasoObligatorio int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 1);

    PRINT 'Resultados de SimularPrimeTimePartido para el partido oficial 1 (18:00 UTC):';
    
    -- Tabla temporal para comprobar resultados del result set
    CREATE TABLE #ResultadosPrimeTime (
        idPais           int,
        nombrePais       nvarchar(60),
        husoHorario      varchar(50),
        horaLocalPartido time(0),
        esPrimeTime      bit
    );

    INSERT INTO #ResultadosPrimeTime
    EXEC Publicidad.SimularPrimeTimePartido @idPartido = @idPartidoCasoObligatorio;

    SELECT nombrePais, husoHorario, horaLocalPartido,
           CASE WHEN esPrimeTime = 1 THEN 'PRIME TIME (19-23)' ELSE 'Fuera de prime time' END AS situacion
    FROM #ResultadosPrimeTime
    ORDER BY esPrimeTime DESC, nombrePais ASC;

    -- Validaciones:
    DECLARE @cantPrimeTime int = (SELECT COUNT(*) FROM #ResultadosPrimeTime WHERE esPrimeTime = 1);
    DECLARE @ptAlemania bit = (SELECT esPrimeTime FROM #ResultadosPrimeTime WHERE nombrePais = 'Alemania');
    DECLARE @ptArgentina bit = (SELECT esPrimeTime FROM #ResultadosPrimeTime WHERE nombrePais = 'Argentina');

    IF @cantPrimeTime > 4 AND @ptAlemania = 1 AND @ptArgentina = 0
        PRINT '[OK] PRUEBA 1.2: Simulación correcta. Hay ' + CAST(@cantPrimeTime AS varchar(10)) + ' mercados en prime time simultáneamente (> 4, cumple caso obligatorio).';
    ELSE
        PRINT '[FALLO] PRUEBA 1.2: No se cumplieron las condiciones esperadas del caso obligatorio.';

    DROP TABLE #ResultadosPrimeTime;
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.2: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   CASOS DE PRUEBA: Publicidad.SimularPrimeTimePorPais
   ============================================================================= */

-- PRUEBA 2.1: Error al simular con partido inexistente en versión por país
BEGIN TRY
    EXEC Publicidad.SimularPrimeTimePorPais @idPartido = 999999;
    PRINT '[FALLO] PRUEBA 2.1: No detectó partido inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE '%no existe%'
        PRINT '[OK] PRUEBA 2.1: Error partido inexistente capturado correctamente.';
    ELSE
        PRINT '[FALLO] PRUEBA 2.1: Error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 2.2: Simulación global por país exitosa
BEGIN TRY
    DECLARE @idPartidoCasoObligatorio int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 1);

    PRINT 'Resultados de SimularPrimeTimePorPais para todos los países del catálogo:';

    CREATE TABLE #ResultadosGlobal (
        idPais           int,
        nombrePais       nvarchar(60),
        husoHorario      varchar(50),
        horaLocalPartido time(0),
        esPrimeTime      bit
    );

    INSERT INTO #ResultadosGlobal
    EXEC Publicidad.SimularPrimeTimePorPais @idPartido = @idPartidoCasoObligatorio;

    SELECT nombrePais, husoHorario, horaLocalPartido, esPrimeTime
    FROM #ResultadosGlobal
    ORDER BY nombrePais;

    DECLARE @totalPaises int = (SELECT COUNT(*) FROM #ResultadosGlobal);

    IF @totalPaises >= 10
        PRINT '[OK] PRUEBA 2.2: Simulación global calculó horas locales para ' + CAST(@totalPaises AS varchar(10)) + ' países.';
    ELSE
        PRINT '[FALLO] PRUEBA 2.2: Se esperaban al menos 10 países con hora calculada.';

    DROP TABLE #ResultadosGlobal;
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.2: ' + ERROR_MESSAGE();
END CATCH;
GO

PRINT '================================================================================';
PRINT ' BATERÍA DE PRUEBAS COMPLETADA: 32_SimulPrimeTime.sql';
PRINT '================================================================================';
GO
