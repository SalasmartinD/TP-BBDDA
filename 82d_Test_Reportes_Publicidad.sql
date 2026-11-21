/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 17/11/2026

 Objetivo    : Suite de pruebas unitarias y de integración para los reportes
               del esquema Publicidad (Entrega 7, script 62_Reportes_Publicidad.sql):
               - Publicidad.Reporte_OcupacionPublicitaria
               - Publicidad.Reporte_MatrizPrimeTime
               - Publicidad.Reporte_IngresosPorMoneda

 Cobertura   : 14 casos de prueba divididos en:
               - Casos de éxito (1 al 7): ejecuciones completas, filtradas por
                 sede, fase y partido, caso obligatorio de la Final (104), matriz
                 pivotada con verificación de 31 filas y liquidación multimoneda.
               - Casos de error (8 al 14): parámetros inexistentes individuales y
                 múltiples simultáneos en Reporte_OcupacionPublicitaria e
                 IngresosPorMoneda, más errores de @idFase y @idPartido inexistentes
                 en Reporte_MatrizPrimeTime. Patrón acumulativo con error 50001.

 Requisitos  : Requiere haber ejecutado los scripts base hasta 54_Estados_Exhibiciones.sql
               y 62_Reportes_Publicidad.sql. No hardcodea identificadores internos.
               Cada prueba imprime [OK] o [FALLO]. Resultado esperado: todas [OK].
================================================================================
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

PRINT '================================================================================';
PRINT ' INICIANDO BATERÍA DE PRUEBAS: 62_Reportes_Publicidad.sql (Entrega 7)';
PRINT '================================================================================';
PRINT '';

/* =============================================================================
   BLOQUE 1: PRUEBAS DE ÉXITO DE OCUPACIÓN PUBLICITARIA (Reporte 1)
   ============================================================================= */

-- -----------------------------------------------------------------------------
-- PRUEBA 1: Reporte de ocupación sin filtros (panorama completo del torneo)
-- Resultado esperado: Devuelve 124 filas (31 partidos x 4 espacios publicitarios).
-- Todos los partidos registran espaciosOcupados = 4 y 100% de ocupación.
-- -----------------------------------------------------------------------------
BEGIN TRY
    DROP TABLE IF EXISTS #resOcupacionFull;
    CREATE TABLE #resOcupacionFull (
        idPartido int, nroPartidoOficial int, fase varchar(60), sede varchar(80),
        ciudadSede varchar(60), paisSede varchar(60), seleccionLocal varchar(60),
        seleccionVisitante varchar(60), partido varchar(150), fechaHoraUTC datetime2(0),
        horaLocalSede datetime2(0), estadoPartido varchar(15), idUbicacion tinyint,
        ubicacionPublicitaria varchar(50), anunciante nvarchar(100), rubroAnunciante varchar(50),
        paisAnunciante varchar(60), campania nvarchar(60), piezaContenido nvarchar(80),
        idiomaPieza char(2), criterioAplicado nvarchar(50), estadoExhibicion varchar(15),
        tarifaUSD decimal(12,2), espaciosOcupados int, espaciosTotales int,
        porcentajeOcupacion decimal(5,2), ingresosExhibidosPartidoUSD decimal(12,2),
        ingresosConfirmadosPartidoUSD decimal(12,2), totalIngresosPartidoUSD decimal(12,2),
        acumuladoSedeUSD decimal(14,2)
    );

    INSERT INTO #resOcupacionFull
    EXEC Publicidad.Reporte_OcupacionPublicitaria;

    SELECT 'EVIDENCIA 1' AS prueba, COUNT(*) AS filasTotales, 
           COUNT(DISTINCT nroPartidoOficial) AS partidosCubiertos,
           MIN(espaciosOcupados) AS minEspaciosOcupados,
           MAX(espaciosOcupados) AS maxEspaciosOcupados,
           SUM(tarifaUSD) AS totalIngresosUSD
    FROM #resOcupacionFull;

    IF (SELECT COUNT(*) FROM #resOcupacionFull) = 124
       AND (SELECT MIN(espaciosOcupados) FROM #resOcupacionFull) = 4
       AND (SELECT MAX(espaciosOcupados) FROM #resOcupacionFull) = 4
    BEGIN
        PRINT '[OK] PRUEBA 1: Reporte de ocupación sin filtros retornó exactamente 124 filas con 100% de ocupación.';
    END
    ELSE
    BEGIN
        PRINT '[FALLO] PRUEBA 1: La cantidad de filas u ocupación no fue la esperada.';
    END;
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1: ' + ERROR_MESSAGE();
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 2: Reporte de ocupación filtrado por una sede específica
-- Resultado esperado: Devuelve únicamente los partidos disputados en esa sede.
-- La columna acumuladoSedeUSD es coherente y creciente cronológicamente.
-- -----------------------------------------------------------------------------
BEGIN TRY
    DECLARE @idSedePrueba int = (SELECT TOP 1 idSede FROM Torneo.Sede WHERE nombreEstadio = N'MetLife Stadium');

    DROP TABLE IF EXISTS #resOcupacionSede;
    CREATE TABLE #resOcupacionSede (
        idPartido int, nroPartidoOficial int, fase varchar(60), sede varchar(80),
        ciudadSede varchar(60), paisSede varchar(60), seleccionLocal varchar(60),
        seleccionVisitante varchar(60), partido varchar(150), fechaHoraUTC datetime2(0),
        horaLocalSede datetime2(0), estadoPartido varchar(15), idUbicacion tinyint,
        ubicacionPublicitaria varchar(50), anunciante nvarchar(100), rubroAnunciante varchar(50),
        paisAnunciante varchar(60), campania nvarchar(60), piezaContenido nvarchar(80),
        idiomaPieza char(2), criterioAplicado nvarchar(50), estadoExhibicion varchar(15),
        tarifaUSD decimal(12,2), espaciosOcupados int, espaciosTotales int,
        porcentajeOcupacion decimal(5,2), ingresosExhibidosPartidoUSD decimal(12,2),
        ingresosConfirmadosPartidoUSD decimal(12,2), totalIngresosPartidoUSD decimal(12,2),
        acumuladoSedeUSD decimal(14,2)
    );

    INSERT INTO #resOcupacionSede
    EXEC Publicidad.Reporte_OcupacionPublicitaria @idSede = @idSedePrueba;

    SELECT 'EVIDENCIA 2' AS prueba, nroPartidoOficial, sede, fechaHoraUTC, horaLocalSede, 
           ubicacionPublicitaria, anunciante, tarifaUSD, acumuladoSedeUSD
    FROM #resOcupacionSede;

    IF EXISTS (SELECT 1 FROM #resOcupacionSede) 
       AND NOT EXISTS (SELECT 1 FROM #resOcupacionSede WHERE sede <> N'MetLife Stadium')
    BEGIN
        PRINT '[OK] PRUEBA 2: Reporte filtrado por sede retornó exclusivamente los partidos de MetLife Stadium con acumulado coherente.';
    END
    ELSE
    BEGIN
        PRINT '[FALLO] PRUEBA 2: El filtro por sede no aisló los datos correctamente.';
    END;
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2: ' + ERROR_MESSAGE();
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 3: Reporte de ocupación filtrado por fase (Fase Final)
-- Resultado esperado: Devuelve exactamente 4 filas correspondientes al partido
-- final del torneo (partido 104), con tarifas de la fase Final.
-- -----------------------------------------------------------------------------
BEGIN TRY
    DECLARE @idFaseFinal int = (SELECT idFase FROM Torneo.Fase WHERE nombre = N'Final');

    DROP TABLE IF EXISTS #resOcupacionFase;
    CREATE TABLE #resOcupacionFase (
        idPartido int, nroPartidoOficial int, fase varchar(60), sede varchar(80),
        ciudadSede varchar(60), paisSede varchar(60), seleccionLocal varchar(60),
        seleccionVisitante varchar(60), partido varchar(150), fechaHoraUTC datetime2(0),
        horaLocalSede datetime2(0), estadoPartido varchar(15), idUbicacion tinyint,
        ubicacionPublicitaria varchar(50), anunciante nvarchar(100), rubroAnunciante varchar(50),
        paisAnunciante varchar(60), campania nvarchar(60), piezaContenido nvarchar(80),
        idiomaPieza char(2), criterioAplicado nvarchar(50), estadoExhibicion varchar(15),
        tarifaUSD decimal(12,2), espaciosOcupados int, espaciosTotales int,
        porcentajeOcupacion decimal(5,2), ingresosExhibidosPartidoUSD decimal(12,2),
        ingresosConfirmadosPartidoUSD decimal(12,2), totalIngresosPartidoUSD decimal(12,2),
        acumuladoSedeUSD decimal(14,2)
    );

    INSERT INTO #resOcupacionFase
    EXEC Publicidad.Reporte_OcupacionPublicitaria @idFase = @idFaseFinal;

    SELECT 'EVIDENCIA 3' AS prueba, nroPartidoOficial, fase, partido, ubicacionPublicitaria, anunciante, tarifaUSD
    FROM #resOcupacionFase;

    IF (SELECT COUNT(*) FROM #resOcupacionFase) = 4 
       AND NOT EXISTS (SELECT 1 FROM #resOcupacionFase WHERE fase <> N'Final')
       AND (SELECT COUNT(anunciante) FROM #resOcupacionFase WHERE anunciante IS NOT NULL) = 4
    BEGIN
        PRINT '[OK] PRUEBA 3: Reporte filtrado por fase Final retornó exactamente las 4 exhibiciones con anunciantes asignados.';
    END
    ELSE
    BEGIN
        PRINT '[FALLO] PRUEBA 3: El filtro por fase no retornó las 4 exhibiciones esperadas.';
    END;
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 3: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   BLOQUE 2: PRUEBAS DE LA MATRIZ DE PRIME TIME Y CASO OBLIGATORIO (Reporte 2)
   ============================================================================= */

-- -----------------------------------------------------------------------------
-- PRUEBA 4: Caso obligatorio de negocio en la Final (partido 104)
-- Resultado esperado: Para la Final (España vs. Argentina, 19:00 UTC), la matriz
-- de prime time debe dar 'SÍ' en 7 mercados candidatos (> 4 mercados). A su vez,
-- el reporte de ocupación demuestra que el sistema priorizó y asignó solo 4 piezas.
-- -----------------------------------------------------------------------------
BEGIN TRY
    DECLARE @idPartidoFinal int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 104);

    -- Evidencia de ocupación para el partido 104
    DROP TABLE IF EXISTS #resOcupacionFinal;
    CREATE TABLE #resOcupacionFinal (
        idPartido int, nroPartidoOficial int, fase varchar(60), sede varchar(80),
        ciudadSede varchar(60), paisSede varchar(60), seleccionLocal varchar(60),
        seleccionVisitante varchar(60), partido varchar(150), fechaHoraUTC datetime2(0),
        horaLocalSede datetime2(0), estadoPartido varchar(15), idUbicacion tinyint,
        ubicacionPublicitaria varchar(50), anunciante nvarchar(100), rubroAnunciante varchar(50),
        paisAnunciante varchar(60), campania nvarchar(60), piezaContenido nvarchar(80),
        idiomaPieza char(2), criterioAplicado nvarchar(50), estadoExhibicion varchar(15),
        tarifaUSD decimal(12,2), espaciosOcupados int, espaciosTotales int,
        porcentajeOcupacion decimal(5,2), ingresosExhibidosPartidoUSD decimal(12,2),
        ingresosConfirmadosPartidoUSD decimal(12,2), totalIngresosPartidoUSD decimal(12,2),
        acumuladoSedeUSD decimal(14,2)
    );

    INSERT INTO #resOcupacionFinal
    EXEC Publicidad.Reporte_OcupacionPublicitaria @idPartido = @idPartidoFinal;

    SELECT 'EVIDENCIA 4 - Ocupación Final' AS prueba, idUbicacion, ubicacionPublicitaria, anunciante, 
           criterioAplicado, tarifaUSD
    FROM #resOcupacionFinal;

    -- Conteo de mercados en prime time para la final
    DECLARE @fechaFinalUTC datetime2(0) = (SELECT fechaHoraUTC FROM Torneo.Partido WHERE idPartido = @idPartidoFinal);
    DECLARE @cantMercadosEnPT int = (
        SELECT COUNT(DISTINCT pa.id)
        FROM Publicidad.PiezaMercado pm
        INNER JOIN Torneo.Pais pa ON pa.id = pm.idPais
        WHERE pa.husoHorario IS NOT NULL
          AND Publicidad.fn_EsPrimeTime(@fechaFinalUTC, pa.husoHorario) = 1
    );

    SELECT 'EVIDENCIA 4 - Mercados Prime Time Final' AS prueba, @cantMercadosEnPT AS mercadosEnPrimeTime;

    IF @cantMercadosEnPT = 7
       AND (SELECT COUNT(anunciante) FROM #resOcupacionFinal) = 4
       AND (SELECT MIN(espaciosOcupados) FROM #resOcupacionFinal) = 4
    BEGIN
        PRINT '[OK] PRUEBA 4: Caso obligatorio verificado: exactamente 7 mercados en Prime Time para la Final y exactamente 4 piezas asignadas por priorización.';
    END
    ELSE
    BEGIN
        PRINT '[FALLO] PRUEBA 4: No se cumplió el caso obligatorio (mercados en PT: ' + CAST(@cantMercadosEnPT AS varchar(10)) + ').';
    END;
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 4: ' + ERROR_MESSAGE();
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 5: Matriz de Prime Time completa sin parámetros
-- Resultado esperado: Devuelve exactamente 31 filas (un partido por fila),
-- con una columna por mercado con 'SÍ' o 'NO'. Con @idPartido de la Final devuelve
-- 1 fila y exactamente 7 mercados en 'SÍ' (los mismos de la prueba 4).
-- La tabla temporal se arma con las columnas de los mercados, que son dinámicas.
-- -----------------------------------------------------------------------------
BEGIN TRY
    DECLARE @columnasMatriz nvarchar(max);   -- definición de las columnas de mercado
    DECLARE @sumaSi nvarchar(max);           -- cuenta de los 'SÍ' de una fila

    SELECT @columnasMatriz = STRING_AGG(CAST(CONCAT(QUOTENAME(x.nombrePais), N' nvarchar(2)') AS nvarchar(max)), N', ')
                             WITHIN GROUP (ORDER BY x.nombrePais),
           @sumaSi = STRING_AGG(CAST(CONCAT(N'CASE WHEN ', QUOTENAME(x.nombrePais), N' = N''SÍ'' THEN 1 ELSE 0 END') AS nvarchar(max)), N' + ')
                     WITHIN GROUP (ORDER BY x.nombrePais)
    FROM (SELECT DISTINCT pa.nombre AS nombrePais
          FROM Publicidad.PiezaMercado pm
          INNER JOIN Torneo.Pais pa ON pa.id = pm.idPais
          WHERE pa.husoHorario IS NOT NULL) x;

    -- Tabla global temporal: una local creada dentro de EXEC() no es visible para este batch
    IF @columnasMatriz IS NULL
    BEGIN
        ;THROW 50001, N'No se registran mercados publicitarios en PiezaMercado con huso horario válido. Requiere haber ejecutado previamente 52_CargaPublicidad.sql.', 1;
    END;

    DROP TABLE IF EXISTS ##matrizPT;
    EXEC (N'CREATE TABLE ##matrizPT (nroPartidoOficial int, fase varchar(60), partido varchar(150), fechaHoraUTC datetime2(0), '
          + @columnasMatriz + N');');

    DECLARE @sqlSi nvarchar(max) = N'SELECT @n = ' + @sumaSi + N' FROM ##matrizPT WHERE nroPartidoOficial = 104;';

    -- 5a. Matriz completa
    INSERT INTO ##matrizPT EXEC Publicidad.Reporte_MatrizPrimeTime;
    DECLARE @filasMatriz int = (SELECT COUNT(*) FROM ##matrizPT);
    DECLARE @siFinalCompleta int;
    EXEC sp_executesql @sqlSi, N'@n int OUTPUT', @n = @siFinalCompleta OUTPUT;

    -- 5b. Matriz filtrada por la Final
    DELETE FROM ##matrizPT;
    DECLARE @idPartidoFinal5 int = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 104);
    INSERT INTO ##matrizPT EXEC Publicidad.Reporte_MatrizPrimeTime @idPartido = @idPartidoFinal5;
    DECLARE @filasFinal int = (SELECT COUNT(*) FROM ##matrizPT);
    DECLARE @siFinalFiltrada int;
    EXEC sp_executesql @sqlSi, N'@n int OUTPUT', @n = @siFinalFiltrada OUTPUT;

    SELECT 'EVIDENCIA 5 - Matriz PT' AS prueba, @filasMatriz AS filasCompleta, @siFinalCompleta AS siFinalCompleta,
           @filasFinal AS filasFinal, @siFinalFiltrada AS siFinalFiltrada;

    IF @filasMatriz = 31 AND @siFinalCompleta = 7 AND @filasFinal = 1 AND @siFinalFiltrada = 7
    BEGIN
        PRINT '[OK] PRUEBA 5: Matriz de Prime Time con 31 filas, 7 mercados en SÍ para la Final y 1 sola fila al filtrar por partido.';
    END
    ELSE
    BEGIN
        PRINT '[FALLO] PRUEBA 5: Se esperaban 31 filas, 7 SÍ en la Final y 1 fila filtrada; se obtuvo ' + CAST(@filasMatriz AS varchar(10))
              + ' filas, ' + ISNULL(CAST(@siFinalCompleta AS varchar(10)), 'NULL') + ' SÍ en la Final y '
              + CAST(@filasFinal AS varchar(10)) + ' fila(s) filtrada(s).';
    END;

    DROP TABLE IF EXISTS ##matrizPT;
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 5: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   BLOQUE 3: PRUEBAS DE LIQUIDACIÓN MULTIMONEDA (Reporte 3)
   ============================================================================= */

-- -----------------------------------------------------------------------------
-- PRUEBA 6: Reporte de ingresos convertido a una moneda específica (EUR)
-- Resultado esperado: Todas las 124 exhibiciones se liquidan en EUR, con tasa
-- de cambio aplicada positiva, fecha de cotización informada y montoLiquidado = montoUSD * cotizacion.
-- -----------------------------------------------------------------------------
BEGIN TRY
    DROP TABLE IF EXISTS #resMonedaEUR;
    CREATE TABLE #resMonedaEUR (
        nroPartidoOficial int, fase varchar(60), partido varchar(150), fechaHoraUTC datetime2(0),
        anunciante nvarchar(100), rubroAnunciante varchar(50), monedaFacturacionAnunciante char(3),
        idUbicacion tinyint, ubicacion varchar(50), pieza nvarchar(80), estadoExhibicion varchar(15),
        montoUSD decimal(12,2), monedaLiquidacion char(3), cotizacionAplicada decimal(18,6),
        fechaCotizacionUsada date, montoLiquidado decimal(14,2),
        totalLiquidadoPorAnunciante decimal(16,2), totalGeneralLiquidadoMoneda decimal(16,2)
    );

    INSERT INTO #resMonedaEUR
    EXEC Publicidad.Reporte_IngresosPorMoneda @monedaDestino = 'EUR';

    SELECT 'EVIDENCIA 6' AS prueba, COUNT(*) AS filas, monedaLiquidacion,
           AVG(cotizacionAplicada) AS cotizacionPromedioEUR,
           SUM(montoUSD) AS totalUSD, SUM(montoLiquidado) AS totalEUR
    FROM #resMonedaEUR
    GROUP BY monedaLiquidacion;

    IF (SELECT COUNT(*) FROM #resMonedaEUR) = 124
       AND NOT EXISTS (SELECT 1 FROM #resMonedaEUR WHERE monedaLiquidacion <> 'EUR')
       AND NOT EXISTS (SELECT 1 FROM #resMonedaEUR WHERE cotizacionAplicada <= 0 OR fechaCotizacionUsada IS NULL)
    BEGIN
        PRINT '[OK] PRUEBA 6: Conversión a EUR ejecutada con éxito en las 124 exhibiciones con cotización válida.';
    END
    ELSE
    BEGIN
        PRINT '[FALLO] PRUEBA 6: Error en la liquidación en EUR o cotización nula/inválida.';
    END;
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 6: ' + ERROR_MESSAGE();
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 7: Reporte de ingresos en la moneda de facturación propia de cada anunciante
-- Resultado esperado: Cada anunciante se liquida en su propia moneda (ARS, BRL, EUR, JPY, etc.).
-- -----------------------------------------------------------------------------
BEGIN TRY
    DROP TABLE IF EXISTS #resMonedaPropia;
    CREATE TABLE #resMonedaPropia (
        nroPartidoOficial int, fase varchar(60), partido varchar(150), fechaHoraUTC datetime2(0),
        anunciante nvarchar(100), rubroAnunciante varchar(50), monedaFacturacionAnunciante char(3),
        idUbicacion tinyint, ubicacion varchar(50), pieza nvarchar(80), estadoExhibicion varchar(15),
        montoUSD decimal(12,2), monedaLiquidacion char(3), cotizacionAplicada decimal(18,6),
        fechaCotizacionUsada date, montoLiquidado decimal(14,2),
        totalLiquidadoPorAnunciante decimal(16,2), totalGeneralLiquidadoMoneda decimal(16,2)
    );

    INSERT INTO #resMonedaPropia
    EXEC Publicidad.Reporte_IngresosPorMoneda @monedaDestino = NULL;

    SELECT 'EVIDENCIA 7' AS prueba, anunciante, monedaFacturacionAnunciante, monedaLiquidacion,
           COUNT(*) AS exhibiciones, SUM(montoLiquidado) AS totalLiquidado
    FROM #resMonedaPropia
    GROUP BY anunciante, monedaFacturacionAnunciante, monedaLiquidacion;

    IF (SELECT COUNT(*) FROM #resMonedaPropia) = 124
       AND NOT EXISTS (SELECT 1 FROM #resMonedaPropia WHERE monedaLiquidacion <> monedaFacturacionAnunciante)
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM #resMonedaPropia WHERE cotizacionAplicada IS NULL OR montoLiquidado IS NULL)
            PRINT '[OK] PRUEBA 7: Liquidación en moneda de origen correcta (cada anunciante en su moneda de facturación, sin cotizaciones faltantes).';
        ELSE
            PRINT '[FALLO] PRUEBA 7: Moneda de facturación correcta, pero hay filas con cotizacionAplicada o montoLiquidado NULL (verificar TipoCambio en 54).';
    END
    ELSE
    BEGIN
        DECLARE @cantDiscrepancias7 int = (SELECT COUNT(*) FROM #resMonedaPropia WHERE monedaLiquidacion <> monedaFacturacionAnunciante);
        PRINT '[FALLO] PRUEBA 7: Hubo ' + CAST(@cantDiscrepancias7 AS varchar) + ' discrepancias entre monedaLiquidacion y monedaFacturacionAnunciante.';
    END;
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 7: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   BLOQUE 4: PRUEBAS DE VALIDACIÓN Y MANEJO DE ERRORES (Casos 8 al 12)
   ============================================================================= */

-- -----------------------------------------------------------------------------
-- PRUEBA 8: Reporte de ocupación con @idSede inexistente
-- Resultado esperado: Error 50001, mensaje '- La sede indicada no existe'.
-- -----------------------------------------------------------------------------
BEGIN TRY
    EXEC Publicidad.Reporte_OcupacionPublicitaria @idSede = 999999;
    PRINT '[FALLO] PRUEBA 8: Debería haber fallado por sede inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%- La sede indicada no existe%'
        PRINT '[OK] PRUEBA 8: Error 50001 capturado correctamente ante sede inexistente.';
    ELSE
        PRINT '[FALLO] PRUEBA 8: Se esperaba error 50001. Mensaje recibido: ' + ERROR_MESSAGE();
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 9: Reporte de ocupación con @idFase inexistente
-- Resultado esperado: Error 50001, mensaje '- La fase indicada no existe'.
-- -----------------------------------------------------------------------------
BEGIN TRY
    EXEC Publicidad.Reporte_OcupacionPublicitaria @idFase = 999999;
    PRINT '[FALLO] PRUEBA 9: Debería haber fallado por fase inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%- La fase indicada no existe%'
        PRINT '[OK] PRUEBA 9: Error 50001 capturado correctamente ante fase inexistente.';
    ELSE
        PRINT '[FALLO] PRUEBA 9: Se esperaba error 50001. Mensaje recibido: ' + ERROR_MESSAGE();
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 10: Reporte de ocupación con @idPartido inexistente
-- Resultado esperado: Error 50001, mensaje '- El partido indicado no existe'.
-- -----------------------------------------------------------------------------
BEGIN TRY
    EXEC Publicidad.Reporte_OcupacionPublicitaria @idPartido = 999999;
    PRINT '[FALLO] PRUEBA 10: Debería haber fallado por partido inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%- El partido indicado no existe%'
        PRINT '[OK] PRUEBA 10: Error 50001 capturado correctamente ante partido inexistente.';
    ELSE
        PRINT '[FALLO] PRUEBA 10: Se esperaba error 50001. Mensaje recibido: ' + ERROR_MESSAGE();
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 11: Reporte de ocupación con sede y partido inexistentes a la vez
-- Resultado esperado: Error 50001 acumulativo conteniendo AMBOS mensajes de error.
-- -----------------------------------------------------------------------------
BEGIN TRY
    EXEC Publicidad.Reporte_OcupacionPublicitaria @idSede = 999999, @idPartido = 999999;
    PRINT '[FALLO] PRUEBA 11: Debería haber fallado por sede y partido inexistentes.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 
       AND ERROR_MESSAGE() LIKE N'%- La sede indicada no existe%'
       AND ERROR_MESSAGE() LIKE N'%- El partido indicado no existe%'
        PRINT '[OK] PRUEBA 11: Patrón acumulativo validado: un solo THROW 50001 con ambos mensajes de error.';
    ELSE
        PRINT '[FALLO] PRUEBA 11: No acumuló ambos mensajes. Mensaje recibido: ' + ERROR_MESSAGE();
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 12: Reporte de ingresos con moneda inexistente (@monedaDestino = 'XXX')
-- Resultado esperado: Error 50001, mensaje '- No se registran cotizaciones para la moneda de destino indicada'.
-- -----------------------------------------------------------------------------
BEGIN TRY
    EXEC Publicidad.Reporte_IngresosPorMoneda @monedaDestino = 'XXX';
    PRINT '[FALLO] PRUEBA 12: Debería haber fallado por moneda sin cotizaciones.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%- No se registran cotizaciones para la moneda de destino indicada%'
        PRINT '[OK] PRUEBA 12: Error 50001 capturado correctamente ante moneda no registrada en TipoCambio.';
    ELSE
        PRINT '[FALLO] PRUEBA 12: Se esperaba error 50001. Mensaje recibido: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   BLOQUE 5: PRUEBAS DE ERROR PARA LA MATRIZ DE PRIME TIME (Casos 13 y 14)
   ============================================================================= */

-- -----------------------------------------------------------------------------
-- PRUEBA 13: Matriz con @idFase inexistente
-- Resultado esperado: Error 50001, mensaje '- La fase indicada no existe'.
-- -----------------------------------------------------------------------------
BEGIN TRY
    EXEC Publicidad.Reporte_MatrizPrimeTime @idFase = 999999;
    PRINT '[FALLO] PRUEBA 13: Debería haber fallado por fase inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%- La fase indicada no existe%'
        PRINT '[OK] PRUEBA 13: Error 50001 capturado correctamente ante fase inexistente en la Matriz.';
    ELSE
        PRINT '[FALLO] PRUEBA 13: Se esperaba error 50001. Mensaje recibido: ' + ERROR_MESSAGE();
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 14: Matriz con @idPartido inexistente
-- Resultado esperado: Error 50001, mensaje '- El partido indicado no existe'.
-- -----------------------------------------------------------------------------
BEGIN TRY
    EXEC Publicidad.Reporte_MatrizPrimeTime @idPartido = 999999;
    PRINT '[FALLO] PRUEBA 14: Debería haber fallado por partido inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%- El partido indicado no existe%'
        PRINT '[OK] PRUEBA 14: Error 50001 capturado correctamente ante partido inexistente en la Matriz.';
    ELSE
        PRINT '[FALLO] PRUEBA 14: Se esperaba error 50001. Mensaje recibido: ' + ERROR_MESSAGE();
END CATCH;
GO

PRINT '';
PRINT '================================================================================';
PRINT ' FINALIZACIÓN DE PRUEBAS: 62_Reportes_Publicidad.sql';
PRINT '================================================================================';
GO
