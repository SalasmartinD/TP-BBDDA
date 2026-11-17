/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 17/11/2026

 Objetivo    : Actualización de estados de las exhibiciones publicitarias
               (Publicidad.ExhibicionPublicitaria) y carga de cotizaciones
               de respaldo en Publicidad.TipoCambio para las monedas de los
               anunciantes propios (ARS, BRL, JPY, EUR, GBP).

 Orden       : Corre inmediatamente después de 53_Cierre_Partidos.sql.
               Al finalizar los partidos, las exhibiciones de los encuentros
               finalizados pasan a estado 'Exhibida' (hecho económico cumplido,
               facturable). Si algún partido permanece en estado 'Programado',
               sus exhibiciones pasan a 'Confirmada' (ingreso proyectado).
               Todas las actualizaciones se realizan mediante el Stored
               Procedure de ABM Publicidad.ExhibicionPublicitaria_Modificacion.

 Idempotencia: Utiliza un bucle WHILE sobre tabla temporal (sin cursores,
               siguiendo el estándar del proyecto).
               - Estados: solo actualiza filas cuyo estado difiera del objetivo.
               - Cotizaciones: solo inserta si no existe ya una cotización para
                 esa moneda y fecha exactas, por lo que el script puede
                 ejecutarse repetidas veces y en cualquier entorno (con o sin
                 API de tipo de cambio) y converge al mismo estado.
================================================================================
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

/* =============================================================================
   1. ACTUALIZACIÓN DE ESTADOS DE EXHIBICIONES PUBLICITARIAS
   ============================================================================= */
DROP TABLE IF EXISTS #exhibicionesPendientes;
CREATE TABLE #exhibicionesPendientes (
    n            int IDENTITY(1,1) PRIMARY KEY,
    idPartido    int NOT NULL,
    idUbicacion  tinyint NOT NULL,
    nuevoEstado  varchar(15) NOT NULL
);

INSERT INTO #exhibicionesPendientes (idPartido, idUbicacion, nuevoEstado)
SELECT 
    ep.idPartido,
    ep.idUbicacion,
    CASE 
        WHEN p.estado = 'Finalizado' THEN 'Exhibida'
        ELSE 'Confirmada'
    END AS nuevoEstado
FROM Publicidad.ExhibicionPublicitaria ep
JOIN Torneo.Partido p ON p.idPartido = ep.idPartido
WHERE ep.estado <> CASE WHEN p.estado = 'Finalizado' THEN 'Exhibida' ELSE 'Confirmada' END;

DECLARE @idPartidoCur    int;
DECLARE @idUbicacionCur  tinyint;
DECLARE @nuevoEstadoCur  varchar(15);
DECLARE @nCur int = 1, @maxCur int = (SELECT MAX(n) FROM #exhibicionesPendientes);

WHILE @nCur <= @maxCur
BEGIN
    SELECT 
        @idPartidoCur   = idPartido,
        @idUbicacionCur = idUbicacion,
        @nuevoEstadoCur = nuevoEstado
    FROM #exhibicionesPendientes
    WHERE n = @nCur;

    BEGIN TRY
        EXEC Publicidad.ExhibicionPublicitaria_Modificacion
            @idPartido   = @idPartidoCur,
            @idUbicacion = @idUbicacionCur,
            @estado      = @nuevoEstadoCur;
    END TRY
    BEGIN CATCH
        PRINT 'Aviso: No se pudo actualizar estado de exhibición (partido ' 
              + CAST(@idPartidoCur AS varchar(10)) + ', ubicación ' 
              + CAST(@idUbicacionCur AS varchar(5)) + '): ' + ERROR_MESSAGE();
    END CATCH;

    SET @nCur += 1;
END;

GO

/* =============================================================================
   2. COTIZACIONES DE RESPALDO (Plan B ante entornos sin conexión a la API)
   ============================================================================= */
/*
   Se cargan cotizaciones de respaldo para las monedas de los anunciantes propios
   (ARS, BRL, JPY, EUR, GBP) mediante Publicidad.TipoCambio_Alta.
   La única condición de inserción es que no exista ya una cotización para esa
   moneda y fecha exactas (verificada fila por fila dentro del bucle). Esto cubre
   la tabla vacía, la carga parcial de la API y las re-ejecuciones del script,
   sin depender de ninguna condición previa sobre el contenido de la tabla.
   Reporte_IngresosPorMoneda (62) toma la cotización más cercana a la fecha del
   partido, por lo que las fechas de respaldo adicionales no alteran resultados.
   Cotización = unidades de moneda extranjera por 1 USD (definición del schema).
*/
PRINT 'Verificando cotizaciones de respaldo en Publicidad.TipoCambio...';

DROP TABLE IF EXISTS #cotizacionesRespaldo;
CREATE TABLE #cotizacionesRespaldo (
    n              int IDENTITY(1,1) PRIMARY KEY,
    moneda         char(3) NOT NULL,
    fecha          date NOT NULL,
    cotizacionUSD  decimal(18,6) NOT NULL
);

INSERT INTO #cotizacionesRespaldo (moneda, fecha, cotizacionUSD) VALUES
    -- EUR (Euro)
    ('EUR', '2026-06-01', 0.920000),
    ('EUR', '2026-06-15', 0.923000),
    ('EUR', '2026-07-01', 0.918000),
    ('EUR', '2026-07-19', 0.921000),
    -- BRL (Real brasileño)
    ('BRL', '2026-06-01', 5.350000),
    ('BRL', '2026-06-15', 5.400000),
    ('BRL', '2026-07-01', 5.420000),
    ('BRL', '2026-07-19', 5.450000),
    -- GBP (Libra esterlina)
    ('GBP', '2026-06-01', 0.785000),
    ('GBP', '2026-06-15', 0.788000),
    ('GBP', '2026-07-01', 0.784000),
    ('GBP', '2026-07-19', 0.786000),
    -- JPY (Yen japonés)
    ('JPY', '2026-06-01', 155.200000),
    ('JPY', '2026-06-15', 156.400000),
    ('JPY', '2026-07-01', 157.100000),
    ('JPY', '2026-07-19', 156.800000),
    -- ARS (Peso argentino - anunciante YPF)
    ('ARS', '2026-06-01', 1100.000000),
    ('ARS', '2026-06-15', 1120.000000),
    ('ARS', '2026-07-01', 1150.000000),
    ('ARS', '2026-07-19', 1180.000000);

DECLARE @monedaTC       char(3);
DECLARE @fechaTC        date;
DECLARE @cotizacionTC   decimal(18,6);
DECLARE @nTC int = 1, @maxTC int = (SELECT MAX(n) FROM #cotizacionesRespaldo);

WHILE @nTC <= @maxTC
BEGIN
    SELECT 
        @monedaTC      = moneda,
        @fechaTC       = fecha,
        @cotizacionTC  = cotizacionUSD
    FROM #cotizacionesRespaldo
    WHERE n = @nTC;

    IF NOT EXISTS (SELECT 1 FROM Publicidad.TipoCambio WHERE moneda = @monedaTC AND fecha = @fechaTC)
    BEGIN
        BEGIN TRY
            EXEC Publicidad.TipoCambio_Alta
                @moneda        = @monedaTC,
                @fecha         = @fechaTC,
                @cotizacionUSD = @cotizacionTC;
        END TRY
        BEGIN CATCH
            PRINT 'Aviso: No se pudo cargar cotización ' + @monedaTC + ' ' + CAST(@fechaTC AS varchar(10)) + ': ' + ERROR_MESSAGE();
        END CATCH;
    END;

    SET @nTC += 1;
END;

GO

/* =============================================================================
   3. RESUMEN DE CONTROL DE ESTADOS DE EXHIBICIÓN
   ============================================================================= */
SELECT 
    ep.estado,
    COUNT(*)                AS cantidadExhibiciones,
    SUM(ep.montoUSD)        AS totalMontoUSD,
    MIN(ep.montoUSD)        AS tarifaMinUSD,
    MAX(ep.montoUSD)        AS tarifaMaxUSD
FROM Publicidad.ExhibicionPublicitaria ep
GROUP BY ep.estado;

SELECT 
    COUNT(DISTINCT moneda)  AS monedasConCotizacion,
    COUNT(*)                AS totalCotizacionesCargadas
FROM Publicidad.TipoCambio;

GO
