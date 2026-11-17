/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 17/11/2026

 Objetivo    : Procedimientos Almacenados de reportes correspondientes al módulo
               de Publicidad (Entrega 7):
               1. Publicidad.Reporte_OcupacionPublicitaria
                  Ocupación de los 4 espacios publicitarios por sede y partido,
                  con anunciantes exhibidos e ingresos generados (USD).
               2. Publicidad.Reporte_MatrizPrimeTime
                  Tabla cruzada (PIVOT) que cruza los partidos del torneo con
                  los países/mercados objetivo de las campañas publicitarias,
                  indicando si el encuentro se disputa en prime time local.
               3. Publicidad.Reporte_IngresosPorMoneda
                  Liquidación y conversión de la pauta publicitaria a diferentes
                  monedas extranjeras mediante la tabla Publicidad.TipoCambio.

 Estándares  :
   - Manejo de errores acumulativo con THROW 50001 ante parámetros inválidos.
   - Retorno de conjuntos tabulares limpios (una fila = un hecho) sin filas
     de totales mezcladas, aptos para herramientas de BI (Entrega 9).
   - Cálculos analíticos de totales y acumulados mediante funciones de ventana.
   - SQL dinámico estrictamente acotado y justificado para el PIVOT de mercados,
     con nombres de columnas saneados mediante QUOTENAME().
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- 1. REPORTE: OCUPACIÓN PUBLICITARIA POR SEDE Y PARTIDO CON INGRESOS GENERADOS
-- =============================================================================
/*
   Muestra qué anunciantes ocuparon los cuatro (4) espacios publicitarios de cada
   partido disputado o programado, qué pieza de contenido se exhibió, el criterio
   de asignación aplicado y los montos facturados en USD.

   Aplica LEFT JOIN sobre Publicidad.UbicacionPublicitaria para garantizar que se
   visibilicen los 4 espacios de cada partido, reflejando huecos si los hubiere.
   Distingue entre ingresos confirmados (proyectados) e ingresos exhibidos
   (efectivamente cumplidos y facturables).

   Parámetros opcionales de filtrado:
     @idSede    int = NULL  -> Filtra por sede del encuentro.
     @idFase    int = NULL  -> Filtra por fase de la competición.
     @idPartido int = NULL  -> Filtra por un partido específico.
*/
CREATE OR ALTER PROCEDURE Publicidad.Reporte_OcupacionPublicitaria
    @idSede    int = NULL,
    @idFase    int = NULL,
    @idPartido int = NULL
AS
BEGIN
    SET NOCOUNT ON;

    /* -------------------------------------------------------------------------
       1. Validación acumulativa de parámetros (patrón del proyecto)
    ------------------------------------------------------------------------- */
    DECLARE @errores nvarchar(2000) = N'';

    IF @idSede IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Torneo.Sede WHERE idSede = @idSede)
        SET @errores = CONCAT(@errores, CHAR(10), N'- La sede indicada no existe (idSede: ', CAST(@idSede AS nvarchar(10)), N').');

    IF @idFase IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = @idFase)
        SET @errores = CONCAT(@errores, CHAR(10), N'- La fase indicada no existe (idFase: ', CAST(@idFase AS nvarchar(10)), N').');

    IF @idPartido IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido)
        SET @errores = CONCAT(@errores, CHAR(10), N'- El partido indicado no existe (idPartido: ', CAST(@idPartido AS nvarchar(10)), N').');

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo generar el reporte de ocupación publicitaria:' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- Parámetro configurable del reglamento
    DECLARE @maxEspacios int = ISNULL(
        (SELECT valor FROM Sistema.Parametro WHERE clave = 'MAX_ESPACIOS_PARTIDO'), 4);

    /* -------------------------------------------------------------------------
       2. Consulta del reporte (tabla limpia con totales analíticos)
    ------------------------------------------------------------------------- */
    SELECT
        -- Identificación y programación del partido
        p.idPartido,
        p.nroPartidoOficial,
        f.nombre                                            AS fase,
        s.nombreEstadio                                     AS sede,
        s.ciudad                                            AS ciudadSede,
        ps.nombre                                           AS paisSede,
        paL.nombre                                          AS seleccionLocal,
        paV.nombre                                          AS seleccionVisitante,
        CONCAT(paL.nombre, N' vs. ', paV.nombre)            AS partido,
        p.fechaHoraUTC,
        Publicidad.fn_HoraLocal(p.fechaHoraUTC, s.husoHorario) AS horaLocalSede,
        p.estado                                            AS estadoPartido,

        -- Detalle del espacio y la exhibición publicitaria
        u.idUbicacion,
        u.nombre                                            AS ubicacionPublicitaria,
        a.nombre                                            AS anunciante,
        a.rubro                                             AS rubroAnunciante,
        paAnun.nombre                                       AS paisAnunciante,
        c.nombre                                            AS campania,
        pc.descripcion                                      AS piezaContenido,
        pc.idioma                                           AS idiomaPieza,
        CASE ep.criterioAplicado
            WHEN 1 THEN N'1: Selección participante'
            WHEN 2 THEN N'2: Mayor PBI per cápita'
            WHEN 3 THEN N'3: Prime time local'
            ELSE N'Sin asignación'
        END                                                 AS criterioAplicado,
        ISNULL(ep.estado, N'Libre')                         AS estadoExhibicion,
        ISNULL(ep.montoUSD, 0.00)                           AS tarifaUSD,

        -- Indicadores de ocupación por partido
        COUNT(ep.idPieza) OVER (PARTITION BY p.idPartido)   AS espaciosOcupados,
        @maxEspacios                                        AS espaciosTotales,
        CAST(COUNT(ep.idPieza) OVER (PARTITION BY p.idPartido) * 100.0 / @maxEspacios AS decimal(5,2)) AS porcentajeOcupacion,

        -- Ingresos por estado (facturable vs. proyectado)
        SUM(CASE WHEN ep.estado = 'Exhibida'   THEN ep.montoUSD ELSE 0.00 END) OVER (PARTITION BY p.idPartido) AS ingresosExhibidosPartidoUSD,
        SUM(CASE WHEN ep.estado = 'Confirmada' THEN ep.montoUSD ELSE 0.00 END) OVER (PARTITION BY p.idPartido) AS ingresosConfirmadosPartidoUSD,
        SUM(ISNULL(ep.montoUSD, 0.00)) OVER (PARTITION BY p.idPartido)                                         AS totalIngresosPartidoUSD,

        -- Acumulado cronológico de ingresos por sede
        SUM(ISNULL(ep.montoUSD, 0.00)) OVER (
            PARTITION BY p.idSede 
            ORDER BY p.fechaHoraUTC, p.idPartido, u.idUbicacion 
            ROWS UNBOUNDED PRECEDING
        )                                                   AS acumuladoSedeUSD

    FROM Torneo.Partido                     p
    INNER JOIN Torneo.Fase                  f      ON f.idFase = p.fase
    INNER JOIN Torneo.Sede                  s      ON s.idSede = p.idSede
    INNER JOIN Torneo.Pais                  ps     ON ps.id = s.idPais
    INNER JOIN Equipos.Seleccion            sL     ON sL.id = p.idSeleccionLocal
    INNER JOIN Torneo.Pais                  paL    ON paL.id = sL.idPais
    INNER JOIN Equipos.Seleccion            sV     ON sV.id = p.idSeleccionVisitante
    INNER JOIN Torneo.Pais                  paV    ON paV.id = sV.idPais
    CROSS JOIN Publicidad.UbicacionPublicitaria u
    LEFT JOIN  Publicidad.ExhibicionPublicitaria ep ON ep.idPartido = p.idPartido 
                                                   AND ep.idUbicacion = u.idUbicacion
    LEFT JOIN  Publicidad.PiezaContenido    pc     ON pc.id = ep.idPieza
    LEFT JOIN  Publicidad.Campania          c      ON c.idCampania = pc.idCampania
    LEFT JOIN  Publicidad.Anunciante        a      ON a.id = c.idAnunciante
    LEFT JOIN  Torneo.Pais                  paAnun ON paAnun.id = a.idPais

    WHERE (@idSede    IS NULL OR p.idSede    = @idSede)
      AND (@idFase    IS NULL OR p.fase      = @idFase)
      AND (@idPartido IS NULL OR p.idPartido = @idPartido)

    ORDER BY p.fechaHoraUTC, p.nroPartidoOficial, u.idUbicacion;
END;
GO

-- =============================================================================
-- 2. REPORTE: MATRIZ DE PRIME TIME (TABLA CRUZADA / PIVOT)
-- =============================================================================
/*
   Construye una matriz donde cada fila representa un partido del torneo y cada
   columna representa un país/mercado objetivo de las piezas publicitarias
   registradas en Publicidad.PiezaMercado. La celda indica si el horario de inicio
   del partido (convertido a la hora local mediante Publicidad.fn_HoraLocal)
   cae dentro de la franja prime time (19:00 a 23:00 locales, evaluado mediante
   Publicidad.fn_EsPrimeTime y los parámetros de Sistema.Parametro).

   JUSTIFICACIÓN DE SQL DINÁMICO:
   La instrucción PIVOT de T-SQL requiere que las columnas pivotadas estén
   listadas literalmente en la cláusula FOR ... IN (...). Dado que los países
   destino de pauta provienen de la tabla Publicidad.PiezaMercado y pueden
   ampliarse dinámicamente con nuevas campañas o anunciantes, no es viable
   un PIVOT rígido. Se ensambla la lista de columnas utilizando STRING_AGG()
   y QUOTENAME() para sanear los identificadores y prevenir inyección SQL.

   Parámetros opcionales:
     @idFase    int = NULL  -> Permite filtrar la matriz por fase.
     @idPartido int = NULL  -> Permite filtrar por un partido específico.
*/
CREATE OR ALTER PROCEDURE Publicidad.Reporte_MatrizPrimeTime
    @idFase    int = NULL,
    @idPartido int = NULL
AS
BEGIN
    SET NOCOUNT ON;

    /* -------------------------------------------------------------------------
       1. Validación acumulativa de parámetros
    ------------------------------------------------------------------------- */
    DECLARE @errores nvarchar(2000) = N'';

    IF @idFase IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = @idFase)
        SET @errores = CONCAT(@errores, CHAR(10), N'- La fase indicada no existe (idFase: ', CAST(@idFase AS nvarchar(10)), N').');

    IF @idPartido IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido)
        SET @errores = CONCAT(@errores, CHAR(10), N'- El partido indicado no existe (idPartido: ', CAST(@idPartido AS nvarchar(10)), N').');

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo generar la matriz de prime time:' + @errores;
        THROW 50001, @errores, 1;
    END;

    /* -------------------------------------------------------------------------
       2. Obtención de mercados publicitarios y armado dinámico de columnas
    ------------------------------------------------------------------------- */
    DECLARE @columnasPivot nvarchar(max);
    DECLARE @columnasSelect nvarchar(max);

    -- Se toman únicamente los países presentes como mercados en PiezaMercado
    SELECT 
        @columnasPivot = STRING_AGG(CAST(QUOTENAME(x.nombrePais) AS nvarchar(max)), N', ') 
                         WITHIN GROUP (ORDER BY x.nombrePais),
        @columnasSelect = STRING_AGG(CAST(CONCAT(N'ISNULL(', QUOTENAME(x.nombrePais), N', ''NO'') AS ', QUOTENAME(x.nombrePais)) AS nvarchar(max)), N', ')
                          WITHIN GROUP (ORDER BY x.nombrePais)
    FROM (
        SELECT DISTINCT pa.nombre AS nombrePais
        FROM Publicidad.PiezaMercado pm
        INNER JOIN Torneo.Pais pa ON pa.id = pm.idPais
        WHERE pa.husoHorario IS NOT NULL
    ) x;

    IF @columnasPivot IS NULL
    BEGIN
        ;THROW 50001, N'No se registran mercados publicitarios con huso horario válido para generar la matriz.', 1;
    END;

    /* -------------------------------------------------------------------------
       3. Construcción y ejecución de la consulta PIVOT dinámica
    ------------------------------------------------------------------------- */
    DECLARE @sql nvarchar(max);

    SET @sql = N'
    WITH PartidosMercados AS (
        SELECT
            p.nroPartidoOficial,
            f.nombre                                            AS fase,
            CONCAT(paLS.nombre, '' vs. '', paVS.nombre)         AS partido,
            p.fechaHoraUTC,
            pa.nombre                                           AS mercado,
            CASE 
                WHEN Publicidad.fn_EsPrimeTime(p.fechaHoraUTC, pa.husoHorario) = 1 
                THEN ''SÍ'' 
                ELSE ''NO'' 
            END                                                 AS enPrimeTime
        FROM Torneo.Partido          p
        INNER JOIN Torneo.Fase       f   ON f.idFase = p.fase
        INNER JOIN Equipos.Seleccion sLS ON sLS.id = p.idSeleccionLocal
        INNER JOIN Torneo.Pais       paLS ON paLS.id = sLS.idPais
        INNER JOIN Equipos.Seleccion sVS ON sVS.id = p.idSeleccionVisitante
        INNER JOIN Torneo.Pais       paVS ON paVS.id = sVS.idPais
        CROSS JOIN (
            SELECT DISTINCT paSub.id, paSub.nombre, paSub.husoHorario
            FROM Publicidad.PiezaMercado pmSub
            INNER JOIN Torneo.Pais paSub ON paSub.id = pmSub.idPais
            WHERE paSub.husoHorario IS NOT NULL
        ) pa
        WHERE (@idFaseSub    IS NULL OR p.fase      = @idFaseSub)
          AND (@idPartidoSub IS NULL OR p.idPartido = @idPartidoSub)
    )
    SELECT
        nroPartidoOficial,
        fase,
        partido,
        fechaHoraUTC,
        ' + @columnasSelect + N'
    FROM PartidosMercados
    PIVOT (
        MAX(enPrimeTime)
        FOR mercado IN (' + @columnasPivot + N')
    ) AS pvt
    ORDER BY fechaHoraUTC, nroPartidoOficial;';

    EXEC sp_executesql 
        @stmt   = @sql,
        @params = N'@idFaseSub int, @idPartidoSub int',
        @idFaseSub    = @idFase,
        @idPartidoSub = @idPartido;
END;
GO

-- =============================================================================
-- 3. REPORTE: PAUTA CONVERTIDA A DISTINTAS MONEDAS (Publicidad.TipoCambio)
-- =============================================================================
/*
   Valoriza los ingresos publicitarios generados por el torneo convirtiéndolos
   a monedas extranjeras mediante las cotizaciones de Publicidad.TipoCambio.
   
   Reglas de conversión:
     1. Si @monedaDestino está especificada:
        Convierte todas las pautas a esa moneda.
     2. Si @monedaDestino es NULL:
        Liquida la pauta de cada anunciante en su propia moneda de facturación
        (Publicidad.Anunciante.monedaFacturacion).
     3. Cotización utilizada (OUTER APPLY):
        Busca la cotización más reciente con fecha menor o igual a la del partido.
        Si no existe ninguna fecha previa, toma la más cercana disponible.
     4. USD:
        Si la moneda es USD, la cotización es fija 1.000000.
     5. Cálculo:
        montoConvertido = montoUSD * cotizacionUSD (según la definición del schema:
        unidades de moneda por cada 1 USD).
*/
CREATE OR ALTER PROCEDURE Publicidad.Reporte_IngresosPorMoneda
    @monedaDestino char(3) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    /* -------------------------------------------------------------------------
       1. Validación acumulativa de parámetros
    ------------------------------------------------------------------------- */
    DECLARE @errores nvarchar(2000) = N'';

    IF @monedaDestino IS NOT NULL
    BEGIN
        IF @monedaDestino <> 'USD' AND NOT EXISTS (SELECT 1 FROM Publicidad.TipoCambio WHERE moneda = @monedaDestino)
            SET @errores = CONCAT(@errores, CHAR(10), N'- No se registran cotizaciones para la moneda de destino indicada (''', @monedaDestino, N''').');
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo generar el reporte de ingresos por moneda:' + @errores;
        THROW 50001, @errores, 1;
    END;

    /* -------------------------------------------------------------------------
       2. Consulta de liquidación multimoneda
    ------------------------------------------------------------------------- */
    WITH DetalleLiquidacion AS (
        SELECT
            p.nroPartidoOficial,
            f.nombre                                            AS fase,
            CONCAT(paL3.nombre, N' vs. ', paV3.nombre)          AS partido,
            p.fechaHoraUTC,
            a.id                                                AS idAnunciante,
            a.nombre                                            AS anunciante,
            a.rubro                                             AS rubroAnunciante,
            a.monedaFacturacion                                 AS monedaFacturacionAnunciante,
            u.idUbicacion,
            u.nombre                                            AS ubicacion,
            pc.descripcion                                      AS pieza,
            ep.estado                                           AS estadoExhibicion,
            ep.montoUSD,

            -- Determinación de la moneda en que se liquidará este registro
            CASE 
                WHEN @monedaDestino IS NOT NULL THEN @monedaDestino
                ELSE a.monedaFacturacion
            END                                                 AS monedaLiquidacion,
            CAST(p.fechaHoraUTC AS date)                        AS fechaPartido
        FROM Publicidad.ExhibicionPublicitaria ep
        INNER JOIN Torneo.Partido              p    ON p.idPartido = ep.idPartido
        INNER JOIN Torneo.Fase                 f    ON f.idFase = p.fase
        INNER JOIN Equipos.Seleccion           sL3  ON sL3.id = p.idSeleccionLocal
        INNER JOIN Torneo.Pais                 paL3 ON paL3.id = sL3.idPais
        INNER JOIN Equipos.Seleccion           sV3  ON sV3.id = p.idSeleccionVisitante
        INNER JOIN Torneo.Pais                 paV3 ON paV3.id = sV3.idPais
        INNER JOIN Publicidad.UbicacionPublicitaria u ON u.idUbicacion = ep.idUbicacion
        INNER JOIN Publicidad.PiezaContenido   pc ON pc.id = ep.idPieza
        INNER JOIN Publicidad.Campania         c  ON c.idCampania = pc.idCampania
        INNER JOIN Publicidad.Anunciante       a  ON a.id = c.idAnunciante
    )
    SELECT
        d.nroPartidoOficial,
        d.fase,
        d.partido,
        d.fechaHoraUTC,
        d.anunciante,
        d.rubroAnunciante,
        d.monedaFacturacionAnunciante,
        d.idUbicacion,
        d.ubicacion,
        d.pieza,
        d.estadoExhibicion,
        d.montoUSD,

        -- Moneda y tasa de cambio aplicada
        d.monedaLiquidacion,
        CASE 
            WHEN d.monedaLiquidacion = 'USD' THEN 1.000000
            ELSE cot.cotizacionUSD
        END                                                     AS cotizacionAplicada,
        CASE 
            WHEN d.monedaLiquidacion = 'USD' THEN d.fechaPartido
            ELSE cot.fecha
        END                                                     AS fechaCotizacionUsada,

        -- Importe convertido
        CASE
            WHEN d.monedaLiquidacion = 'USD' OR cot.cotizacionUSD IS NOT NULL
            THEN ROUND(
                    d.montoUSD * CASE WHEN d.monedaLiquidacion = 'USD' THEN 1.000000 ELSE cot.cotizacionUSD END,
                    2
                 )
            ELSE NULL
        END                                                     AS montoLiquidado,

        -- Totales analíticos para BI
        SUM(CASE
                WHEN d.monedaLiquidacion = 'USD' OR cot.cotizacionUSD IS NOT NULL
                THEN ROUND(d.montoUSD * CASE WHEN d.monedaLiquidacion = 'USD' THEN 1.000000 ELSE cot.cotizacionUSD END, 2)
                ELSE NULL
            END)
            OVER (PARTITION BY d.monedaLiquidacion, d.idAnunciante) AS totalLiquidadoPorAnunciante,

        SUM(CASE
                WHEN d.monedaLiquidacion = 'USD' OR cot.cotizacionUSD IS NOT NULL
                THEN ROUND(d.montoUSD * CASE WHEN d.monedaLiquidacion = 'USD' THEN 1.000000 ELSE cot.cotizacionUSD END, 2)
                ELSE NULL
            END)
            OVER (PARTITION BY d.monedaLiquidacion)             AS totalGeneralLiquidadoMoneda

    FROM DetalleLiquidacion d
    OUTER APPLY (
        SELECT TOP 1 
            tc.cotizacionUSD,
            tc.fecha
        FROM Publicidad.TipoCambio tc
        WHERE tc.moneda = d.monedaLiquidacion
        ORDER BY 
            -- Prioriza cotizaciones previas o iguales a la fecha del partido
            CASE WHEN tc.fecha <= d.fechaPartido THEN 0 ELSE 1 END,
            ABS(DATEDIFF(DAY, tc.fecha, d.fechaPartido)) ASC
    ) cot
    ORDER BY d.fechaHoraUTC, d.nroPartidoOficial, d.idUbicacion;
END;
GO
