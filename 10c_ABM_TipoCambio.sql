/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 09/11/2026

 Objetivo    : Procedimientos almacenados de Alta, Baja y Modificación (ABM)
               de Publicidad.TipoCambio (cotizaciones que carga la API
               Frankfurter, expresadas en unidades de la moneda por 1 USD).

 Estándares aplicados:
 - Cada SP revisa todas las condiciones, acumula las que fallan en @errores
   y, si hay alguna, corta con un único THROW 50001 que las informa juntas.
 - La clave es moneda + fecha: la modificación solo cambia la cotización.
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- 1. ALTA DE COTIZACIÓN
CREATE OR ALTER PROCEDURE Publicidad.TipoCambio_Alta
    @moneda         varchar(10),
    @fecha          date,
    @cotizacionUSD  decimal(18,6)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @moneda = UPPER(LTRIM(RTRIM(@moneda)));

    IF @moneda IS NULL OR @moneda COLLATE Latin1_General_BIN NOT LIKE '[A-Z][A-Z][A-Z]'
        SET @errores += CHAR(10) + N'- La moneda debe ser un código ISO 4217 de 3 letras.';

    IF @fecha IS NULL
        SET @errores += CHAR(10) + N'- La fecha de la cotización es obligatoria.';
    ELSE IF @fecha > CAST(GETDATE() AS date)
        SET @errores += CHAR(10) + N'- La fecha de la cotización no puede ser futura.';

    IF @cotizacionUSD IS NULL OR @cotizacionUSD <= 0
        SET @errores += CHAR(10) + N'- La cotización es obligatoria y debe ser mayor a cero.';
    ELSE IF @moneda = 'USD' AND @cotizacionUSD <> 1
        SET @errores += CHAR(10) + N'- La cotización del USD contra sí mismo debe ser 1.';

    IF EXISTS (SELECT 1 FROM Publicidad.TipoCambio WHERE moneda = @moneda AND fecha = @fecha)
        SET @errores += CHAR(10) + N'- Ya existe una cotización para esa moneda y fecha.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de alta la cotización:' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Publicidad.TipoCambio (moneda, fecha, cotizacionUSD)
    VALUES (@moneda, @fecha, @cotizacionUSD);
END
GO

-- 2. MODIFICACIÓN DE COTIZACIÓN
CREATE OR ALTER PROCEDURE Publicidad.TipoCambio_Modificacion
    @moneda         varchar(10),
    @fecha          date,
    @cotizacionUSD  decimal(18,6)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @moneda = UPPER(LTRIM(RTRIM(@moneda)));

    IF NOT EXISTS (SELECT 1 FROM Publicidad.TipoCambio WHERE moneda = @moneda AND fecha = @fecha)
        SET @errores += CHAR(10) + N'- No existe una cotización para esa moneda y fecha.';

    IF @cotizacionUSD IS NULL OR @cotizacionUSD <= 0
        SET @errores += CHAR(10) + N'- La cotización es obligatoria y debe ser mayor a cero.';
    ELSE IF @moneda = 'USD' AND @cotizacionUSD <> 1
        SET @errores += CHAR(10) + N'- La cotización del USD contra sí mismo debe ser 1.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo modificar la cotización:' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Publicidad.TipoCambio
    SET cotizacionUSD = @cotizacionUSD
    WHERE moneda = @moneda AND fecha = @fecha;
END
GO

-- 3. BAJA DE COTIZACIÓN
CREATE OR ALTER PROCEDURE Publicidad.TipoCambio_Baja
    @moneda  varchar(10),
    @fecha   date
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @moneda = UPPER(LTRIM(RTRIM(@moneda)));

    IF NOT EXISTS (SELECT 1 FROM Publicidad.TipoCambio WHERE moneda = @moneda AND fecha = @fecha)
        SET @errores += CHAR(10) + N'- No existe una cotización para esa moneda y fecha.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de baja la cotización:' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Publicidad.TipoCambio
    WHERE moneda = @moneda AND fecha = @fecha;
END
GO
