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
               Incluye el caso de un partido en prime time simultáneo en más de
               cuatro mercados candidatos.

 Estándares aplicados:
 - Relación 1:1 con 32_SimulPrimeTime.sql.
 - Autocontenida: crea su propio partido, países, campaña y pieza. No depende
   de 52_CargaPublicidad.sql ni del fixture oficial.
 - Solo usa códigos y números de uso exclusivo de la prueba (países XA a XH,
   fase 996, partido 99601): los códigos ISO que empiezan con X son de
   asignación privada y no chocan con países reales.
 - El partido y la campaña son de 2030: así no hay campañas reales vigentes
   (como las de 52) que sumen mercados al resultado.
 - Idempotencia absoluta con limpieza preventiva y final.
 - Validación de errores (código THROW 50001 en partido inexistente).
 - Verificación precisa del flag esPrimeTime.
 - Requiere 12_ABM_Publicidad.sql, 22_Negocio_Publicidad.sql (funciones) y
   32_SimulPrimeTime.sql.
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
   PREPARACIÓN DEL ENTORNO DE PRUEBAS
   ============================================================================= */
PRINT '--- Limpieza preventiva de pruebas anteriores ---';

DELETE FROM Publicidad.PiezaMercado
WHERE idPieza IN (SELECT id FROM Publicidad.PiezaContenido WHERE descripcion LIKE 'Test Sim Pieza%');
DELETE FROM Publicidad.PiezaContenido WHERE descripcion LIKE 'Test Sim Pieza%';
DELETE FROM Publicidad.Campania WHERE nombre LIKE 'Test Sim Campania%';
DELETE FROM Publicidad.Anunciante WHERE nombre LIKE 'Test Sim Anunciante%';
DELETE FROM Torneo.Partido WHERE nroPartidoOficial = 99601;
DELETE FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test Simul';
DELETE FROM Torneo.Fase WHERE idFase = 996;
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('TSA', 'TSB');
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('XA', 'XB', 'XC', 'XD', 'XE', 'XF', 'XG', 'XH');
GO

PRINT '--- Creando datos auxiliares de prueba ---';

-- Partido 99601: 2030-06-25 18:00 UTC. Hora local y prime time (19 a 23) por país:
--   XA 'Argentina Standard Time'        → 15:00  no   (local)
--   XB 'W. Europe Standard Time'        → 20:00  sí   (visitante)
--   XC 'Romance Standard Time'          → 20:00  sí
--   XD 'Tokyo Standard Time'            → 03:00  no
--   XE 'GMT Standard Time'              → 19:00  sí   (borde inferior, inclusive)
--   XF 'Pacific Standard Time'          → 11:00  no   (sin pieza: solo aparece en PorPais)
--   XG 'Central Europe Standard Time'   → 20:00  sí
--   XH 'E. Europe Standard Time'        → 21:00  sí
-- Los mercados en prime time son 5 (XB, XC, XE, XG, XH): más de cuatro.
INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3, husoHorario, pbiPerCapita)
VALUES ('Pais Test Simul A', 'XA', 'TXA', 'Argentina Standard Time',       12000),
       ('Pais Test Simul B', 'XB', 'TXB', 'W. Europe Standard Time',       50000),
       ('Pais Test Simul C', 'XC', 'TXC', 'Romance Standard Time',         44000),
       ('Pais Test Simul D', 'XD', 'TXD', 'Tokyo Standard Time',           42000),
       ('Pais Test Simul E', 'XE', 'TXE', 'GMT Standard Time',             46000),
       ('Pais Test Simul F', 'XF', 'TXF', 'Pacific Standard Time',         60000),
       ('Pais Test Simul G', 'XG', 'TXG', 'Central Europe Standard Time',  30000),
       ('Pais Test Simul H', 'XH', 'TXH', 'E. Europe Standard Time',       20000);

DECLARE @idPaisXA int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XA');
DECLARE @idPaisXB int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XB');
DECLARE @idPaisXC int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XC');
DECLARE @idPaisXD int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XD');
DECLARE @idPaisXE int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XE');
DECLARE @idPaisXG int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XG');
DECLARE @idPaisXH int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'XH');

INSERT INTO Equipos.Seleccion (idPais, abreviacion, confederacion)
VALUES (@idPaisXA, 'TSA', 'CONMEBOL'),
       (@idPaisXB, 'TSB', 'UEFA');

DECLARE @idSelSA int = (SELECT id FROM Equipos.Seleccion WHERE idPais = @idPaisXA);
DECLARE @idSelSB int = (SELECT id FROM Equipos.Seleccion WHERE idPais = @idPaisXB);

INSERT INTO Torneo.Fase (idFase, nombre, esEliminatoria, orden)
VALUES (996, 'Fase Test Simul', 0, 96);

INSERT INTO Torneo.Sede (nombreEstadio, ciudad, idPais, husoHorario)
VALUES ('Estadio Test Simul', 'Ciudad Test Simul', @idPaisXA, 'Argentina Standard Time');

DECLARE @idSedeSimul int = (SELECT idSede FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test Simul');

INSERT INTO Torneo.Partido (nroPartidoOficial, idSede, idSeleccionLocal, idSeleccionVisitante, fase, fechaHoraUTC, estado)
VALUES (99601, @idSedeSimul, @idSelSA, @idSelSB, 996, '2030-06-25 18:00:00', 'Programado');

-- Anunciante, campaña vigente en la fecha del partido y una pieza con 7 mercados
-- (a través de los SP de 12_ABM_Publicidad.sql). XF queda sin pieza a propósito.
EXEC Publicidad.Anunciante_Alta @nombre = N'Test Sim Anunciante', @idPais = @idPaisXB;
DECLARE @idAnunciante int = (SELECT id FROM Publicidad.Anunciante WHERE nombre = N'Test Sim Anunciante');

EXEC Publicidad.Campania_Alta @idAnunciante = @idAnunciante, @nombre = N'Test Sim Campania', @fechaInicio = '2030-06-01', @fechaFin = '2030-07-31';
DECLARE @idCamp int = (SELECT idCampania FROM Publicidad.Campania WHERE nombre = N'Test Sim Campania');

EXEC Publicidad.PiezaContenido_Alta @idCampania = @idCamp, @descripcion = N'Test Sim Pieza Global', @idioma = 'en';
DECLARE @idPieza int = (SELECT id FROM Publicidad.PiezaContenido WHERE descripcion = N'Test Sim Pieza Global');

EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPieza, @idPais = @idPaisXA;
EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPieza, @idPais = @idPaisXB;
EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPieza, @idPais = @idPaisXC;
EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPieza, @idPais = @idPaisXD;
EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPieza, @idPais = @idPaisXE;
EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPieza, @idPais = @idPaisXG;
EXEC Publicidad.PiezaMercado_Alta @idPieza = @idPieza, @idPais = @idPaisXH;

PRINT 'Fixture de pruebas de simulación inicializado con éxito.';
PRINT '';
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

-- PRUEBA 1.2: Simulación exitosa sobre el partido de prueba (18:00 UTC) con más de 4 mercados en prime time
BEGIN TRY
    DECLARE @idPartidoSim int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99601);

    PRINT 'Resultados de SimularPrimeTimePartido para el partido 99601 (18:00 UTC):';

    -- Tabla temporal para comprobar resultados del result set
    CREATE TABLE #ResultadosPrimeTime (
        idPais           int,
        nombrePais       nvarchar(60),
        husoHorario      varchar(50),
        horaLocalPartido time(0),
        esPrimeTime      bit
    );

    INSERT INTO #ResultadosPrimeTime
    EXEC Publicidad.SimularPrimeTimePartido @idPartido = @idPartidoSim;

    SELECT nombrePais, husoHorario, horaLocalPartido,
           CASE WHEN esPrimeTime = 1 THEN 'PRIME TIME (19-23)' ELSE 'Fuera de prime time' END AS situacion
    FROM #ResultadosPrimeTime
    ORDER BY esPrimeTime DESC, nombrePais ASC;

    -- Validaciones:
    DECLARE @cantMercados int = (SELECT COUNT(*) FROM #ResultadosPrimeTime);
    DECLARE @cantPrimeTime int = (SELECT COUNT(*) FROM #ResultadosPrimeTime WHERE esPrimeTime = 1);
    DECLARE @ptVisitante bit = (SELECT esPrimeTime FROM #ResultadosPrimeTime WHERE nombrePais = 'Pais Test Simul B');
    DECLARE @ptLocal bit = (SELECT esPrimeTime FROM #ResultadosPrimeTime WHERE nombrePais = 'Pais Test Simul A');
    DECLARE @ptBorde bit = (SELECT esPrimeTime FROM #ResultadosPrimeTime WHERE nombrePais = 'Pais Test Simul E');
    DECLARE @horaBorde time(0) = (SELECT horaLocalPartido FROM #ResultadosPrimeTime WHERE nombrePais = 'Pais Test Simul E');

    IF @cantMercados = 7
       AND @cantPrimeTime = 5
       AND @ptVisitante = 1 AND @ptLocal = 0
       AND @ptBorde = 1 AND @horaBorde = '19:00:00'
       AND NOT EXISTS (SELECT 1 FROM #ResultadosPrimeTime WHERE nombrePais = 'Pais Test Simul F')
        PRINT '[OK] PRUEBA 1.2: Simulación correcta. Hay ' + CAST(@cantPrimeTime AS varchar(10)) + ' de ' + CAST(@cantMercados AS varchar(10)) + ' mercados en prime time simultáneamente (> 4), el borde de las 19:00 cuenta y el país sin pieza no aparece.';
    ELSE
        PRINT '[FALLO] PRUEBA 1.2: No se cumplieron las condiciones esperadas (7 mercados, 5 en prime time, 19:00 inclusive, sin el país sin pieza).';

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

-- PRUEBA 2.2: Simulación global por país exitosa (incluye también el país sin pieza)
BEGIN TRY
    DECLARE @idPartidoSim int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 99601);

    PRINT 'Resultados de SimularPrimeTimePorPais para todos los países del catálogo:';

    CREATE TABLE #ResultadosGlobal (
        idPais           int,
        nombrePais       nvarchar(60),
        husoHorario      varchar(50),
        horaLocalPartido time(0),
        esPrimeTime      bit
    );

    INSERT INTO #ResultadosGlobal
    EXEC Publicidad.SimularPrimeTimePorPais @idPartido = @idPartidoSim;

    SELECT nombrePais, husoHorario, horaLocalPartido, esPrimeTime
    FROM #ResultadosGlobal
    WHERE nombrePais LIKE 'Pais Test Simul%'
    ORDER BY nombrePais;

    DECLARE @totalPaises int = (SELECT COUNT(*) FROM #ResultadosGlobal);

    -- Flags esperados para XA a XH: 0, 1, 1, 0, 1, 0, 1, 1
    DECLARE @flagsObtenidos varchar(20) = (
        SELECT STRING_AGG(CAST(esPrimeTime AS varchar(1)), ',') WITHIN GROUP (ORDER BY nombrePais)
        FROM #ResultadosGlobal
        WHERE nombrePais LIKE 'Pais Test Simul%'
    );

    IF @totalPaises >= 8 AND @flagsObtenidos = '0,1,1,0,1,0,1,1'
        PRINT '[OK] PRUEBA 2.2: Simulación global calculó horas locales para ' + CAST(@totalPaises AS varchar(10)) + ' países, con los flags de prime time esperados.';
    ELSE
        PRINT '[FALLO] PRUEBA 2.2: Resultado inesperado (países=' + CAST(@totalPaises AS varchar(10)) + ', flags=' + ISNULL(@flagsObtenidos, 'NULL') + ').';

    DROP TABLE #ResultadosGlobal;
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.2: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   LIMPIEZA FINAL
   ============================================================================= */
PRINT '--- Limpieza final del entorno de pruebas ---';

DELETE FROM Publicidad.PiezaMercado
WHERE idPieza IN (SELECT id FROM Publicidad.PiezaContenido WHERE descripcion LIKE 'Test Sim Pieza%');
DELETE FROM Publicidad.PiezaContenido WHERE descripcion LIKE 'Test Sim Pieza%';
DELETE FROM Publicidad.Campania WHERE nombre LIKE 'Test Sim Campania%';
DELETE FROM Publicidad.Anunciante WHERE nombre LIKE 'Test Sim Anunciante%';
DELETE FROM Torneo.Partido WHERE nroPartidoOficial = 99601;
DELETE FROM Torneo.Sede WHERE nombreEstadio = 'Estadio Test Simul';
DELETE FROM Torneo.Fase WHERE idFase = 996;
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('TSA', 'TSB');
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('XA', 'XB', 'XC', 'XD', 'XE', 'XF', 'XG', 'XH');

PRINT '================================================================================';
PRINT ' BATERÍA DE PRUEBAS COMPLETADA: 32_SimulPrimeTime.sql';
PRINT '================================================================================';
GO
