/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 10/11/2026

 Objetivo    : Cargar con las APIs los datos que completan la carga base:
               - PBI per cápita de cada país (Banco Mundial) en Torneo.Pais.
                 Lo necesita la asignación de publicidad por mercado.
               - Tipo de cambio de cada moneda por 1 USD (Frankfurter) en
                 Publicidad.TipoCambio, un día por cada fecha entre el primer
                 y el último partido cargado (sin pasar de hoy). Lo necesita el
                 reporte de la pauta en otras monedas.

 Uso         : Corre después de 50a (necesita los países y las monedas) y de
               50c (necesita las fechas de los partidos). Requiere internet y
               "Ole Automation Procedures" habilitado (ver 43_Importar_APIs.sql).
               Si no hay internet, el script no corta la ejecución de los demás:
               informa el motivo y se puede volver a correr cuando haya
               conexión. Es idempotente: repetirlo no duplica ni vuelve a
               modificar lo que ya está cargado.
================================================================================
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

/* =============================================================================
   PBI PER CÁPITA (Banco Mundial)
   ============================================================================= */
BEGIN TRY
    EXEC Torneo.Importar_PBIBancoMundial;
END TRY
BEGIN CATCH
    PRINT CONCAT('No se pudo cargar el PBI del Banco Mundial: ', ERROR_MESSAGE());
    PRINT 'Volver a ejecutar EXEC Torneo.Importar_PBIBancoMundial cuando haya conexión.';
END CATCH;
GO

/* =============================================================================
   TIPO DE CAMBIO (Frankfurter): desde el primer hasta el último día de partidos
   ============================================================================= */
DECLARE @desde date = (SELECT MIN(CAST(fechaHoraUTC AS date)) FROM Torneo.Partido);
DECLARE @hasta date = (SELECT MAX(CAST(fechaHoraUTC AS date)) FROM Torneo.Partido);

IF @hasta > CAST(GETDATE() AS date)
    SET @hasta = CAST(GETDATE() AS date);
IF @desde IS NULL OR @desde > @hasta       -- sin partidos o con partidos futuros: la última cotización
BEGIN
    SET @desde = NULL;
    SET @hasta = NULL;
END;

BEGIN TRY
    EXEC Publicidad.Importar_TipoCambioFrankfurter @fechaDesde = @desde, @fechaHasta = @hasta;
END TRY
BEGIN CATCH
    PRINT CONCAT('No se pudo cargar el tipo de cambio de Frankfurter: ', ERROR_MESSAGE());
    PRINT 'Volver a ejecutar EXEC Publicidad.Importar_TipoCambioFrankfurter cuando haya conexión.';
END CATCH;
GO

-- Resumen de la carga
SELECT COUNT(*) AS paises, SUM(CASE WHEN pbiPerCapita IS NOT NULL THEN 1 ELSE 0 END) AS paisesConPBI
FROM Torneo.Pais;
SELECT COUNT(DISTINCT moneda) AS monedas, COUNT(*) AS cotizaciones, MIN(fecha) AS desde, MAX(fecha) AS hasta
FROM Publicidad.TipoCambio;
GO
