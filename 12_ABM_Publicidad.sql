/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 09/11/2026

 Objetivo    : Stored Procedures de Alta, Baja y Modificación para las tablas
               del esquema Publicidad: Anunciante, Campania, PiezaContenido,
               PiezaMercado, UbicacionPublicitaria, Tarifa y ExhibicionPublicitaria.
               Patrón de validación: acumular errores en @errores y lanzar un
               único THROW 50001 con todos los problemas juntos.
================================================================================
*/

USE MundialFutbol;
GO

-- ============================================================================
-- 1. Publicidad.Anunciante_Alta
-- ============================================================================
CREATE OR ALTER PROCEDURE Publicidad.Anunciante_Alta
    @nombre             nvarchar(100),
    @rubro              varchar(50)  = NULL,
    @idPais             int,
    @monedaFacturacion  char(3)      = 'USD'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores nvarchar(2000) = N'';

    -- Validación: el país existe
    IF NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE id = @idPais)
        SET @errores = @errores + CHAR(10) + N'- El país con id ' + CAST(@idPais AS nvarchar) + N' no existe.';

    -- Validación: nombre no duplicado
    IF EXISTS (SELECT 1 FROM Publicidad.Anunciante WHERE nombre = @nombre)
        SET @errores = @errores + CHAR(10) + N'- Ya existe un anunciante con el nombre ''' + @nombre + N'''.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de alta el Anunciante:' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Publicidad.Anunciante (nombre, rubro, idPais, monedaFacturacion)
    VALUES (@nombre, @rubro, @idPais, @monedaFacturacion);
END;
GO

-- ============================================================================
-- 2. Publicidad.Anunciante_Baja
-- ============================================================================
CREATE OR ALTER PROCEDURE Publicidad.Anunciante_Baja
    @id int
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores nvarchar(2000) = N'';

    -- Validación: el anunciante existe
    IF NOT EXISTS (SELECT 1 FROM Publicidad.Anunciante WHERE id = @id)
        SET @errores = @errores + CHAR(10) + N'- El anunciante con id ' + CAST(@id AS nvarchar) + N' no existe.';

    -- Validación: no tiene campañas activas
    IF EXISTS (
        SELECT 1
        FROM Publicidad.Campania
        WHERE idAnunciante = @id
          AND fechaFin >= CAST(GETDATE() AS date)
    )
        SET @errores = @errores + CHAR(10) + N'- El anunciante tiene campañas activas. Primero hay que cerrar las campañas vigentes.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de baja el Anunciante:' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Publicidad.Anunciante WHERE id = @id;
END;
GO

-- ============================================================================
-- 3. Publicidad.Anunciante_Modificacion
-- ============================================================================
CREATE OR ALTER PROCEDURE Publicidad.Anunciante_Modificacion
    @id                 int,
    @nombre             nvarchar(100),
    @rubro              varchar(50)  = NULL,
    @idPais             int,
    @monedaFacturacion  char(3)      = 'USD'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores nvarchar(2000) = N'';

    -- Validación: el anunciante existe
    IF NOT EXISTS (SELECT 1 FROM Publicidad.Anunciante WHERE id = @id)
        SET @errores = @errores + CHAR(10) + N'- El anunciante con id ' + CAST(@id AS nvarchar) + N' no existe.';

    -- Validación: el nuevo país existe
    IF NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE id = @idPais)
        SET @errores = @errores + CHAR(10) + N'- El país con id ' + CAST(@idPais AS nvarchar) + N' no existe.';

    -- Validación: nombre no usado por otro anunciante distinto
    IF EXISTS (SELECT 1 FROM Publicidad.Anunciante WHERE nombre = @nombre AND id <> @id)
        SET @errores = @errores + CHAR(10) + N'- Ya existe otro anunciante con el nombre ''' + @nombre + N'''.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo modificar el Anunciante:' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Publicidad.Anunciante
    SET nombre            = @nombre,
        rubro             = @rubro,
        idPais            = @idPais,
        monedaFacturacion = @monedaFacturacion
    WHERE id = @id;
END;
GO

-- ============================================================================
-- 4. Publicidad.Campania_Alta
-- ============================================================================
CREATE OR ALTER PROCEDURE Publicidad.Campania_Alta
    @idAnunciante   int,
    @nombre         nvarchar(60),
    @fechaInicio    date,
    @fechaFin       date
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores nvarchar(2000) = N'';

    -- Validación: el anunciante existe
    IF NOT EXISTS (SELECT 1 FROM Publicidad.Anunciante WHERE id = @idAnunciante)
        SET @errores = @errores + CHAR(10) + N'- El anunciante con id ' + CAST(@idAnunciante AS nvarchar) + N' no existe.';

    -- Validación: fechaFin >= fechaInicio
    IF @fechaFin < @fechaInicio
        SET @errores = @errores + CHAR(10) + N'- La fecha de fin no puede ser anterior a la fecha de inicio.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de alta la Campaña:' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Publicidad.Campania (idAnunciante, nombre, fechaInicio, fechaFin)
    VALUES (@idAnunciante, @nombre, @fechaInicio, @fechaFin);
END;
GO

-- ============================================================================
-- 5. Publicidad.Campania_Baja
-- ============================================================================
CREATE OR ALTER PROCEDURE Publicidad.Campania_Baja
    @idCampania int
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores nvarchar(2000) = N'';

    -- Validación: la campaña existe
    IF NOT EXISTS (SELECT 1 FROM Publicidad.Campania WHERE idCampania = @idCampania)
        SET @errores = @errores + CHAR(10) + N'- La campaña con id ' + CAST(@idCampania AS nvarchar) + N' no existe.';

    -- Validación: no tiene piezas asignadas en exhibiciones activas
    IF EXISTS (
        SELECT 1
        FROM Publicidad.ExhibicionPublicitaria ep
        INNER JOIN Publicidad.PiezaContenido pc ON pc.id = ep.idPieza
        WHERE pc.idCampania = @idCampania
          AND ep.estado IN (N'Propuesta', N'Confirmada')
    )
        SET @errores = @errores + CHAR(10) + N'- La campaña tiene piezas con exhibiciones activas (en estado Propuesta o Confirmada). Primero deben resolverse esas exhibiciones.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de baja la Campaña:' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Publicidad.Campania WHERE idCampania = @idCampania;
END;
GO

-- ============================================================================
-- 6. Publicidad.Campania_Modificacion
-- ============================================================================
CREATE OR ALTER PROCEDURE Publicidad.Campania_Modificacion
    @idCampania     int,
    @nombre         nvarchar(60),
    @fechaInicio    date,
    @fechaFin       date
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores nvarchar(2000) = N'';

    -- Validación: la campaña existe
    IF NOT EXISTS (SELECT 1 FROM Publicidad.Campania WHERE idCampania = @idCampania)
        SET @errores = @errores + CHAR(10) + N'- La campaña con id ' + CAST(@idCampania AS nvarchar) + N' no existe.';

    -- Validación: fechaFin >= fechaInicio
    IF @fechaFin < @fechaInicio
        SET @errores = @errores + CHAR(10) + N'- La fecha de fin no puede ser anterior a la fecha de inicio.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo modificar la Campaña:' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Publicidad.Campania
    SET nombre       = @nombre,
        fechaInicio  = @fechaInicio,
        fechaFin     = @fechaFin
    WHERE idCampania = @idCampania;
END;
GO

-- ============================================================================
-- 7. Publicidad.PiezaContenido_Alta
-- ============================================================================
CREATE OR ALTER PROCEDURE Publicidad.PiezaContenido_Alta
    @idCampania     int,
    @descripcion    nvarchar(80),
    @idioma         char(2)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores nvarchar(2000) = N'';

    -- Validación: la campaña existe
    IF NOT EXISTS (SELECT 1 FROM Publicidad.Campania WHERE idCampania = @idCampania)
        SET @errores = @errores + CHAR(10) + N'- La campaña con id ' + CAST(@idCampania AS nvarchar) + N' no existe.';

    -- Validación: idioma con exactamente 2 caracteres alfabéticos en minúscula
    IF @idioma NOT LIKE '[a-z][a-z]'
        SET @errores = @errores + CHAR(10) + N'- El idioma debe contener exactamente 2 letras minúsculas (ej.: ''es'', ''en'', ''pt'').';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de alta la Pieza de Contenido:' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Publicidad.PiezaContenido (idCampania, descripcion, idioma)
    VALUES (@idCampania, @descripcion, @idioma);
END;
GO

-- ============================================================================
-- 8. Publicidad.PiezaContenido_Baja
-- ============================================================================
CREATE OR ALTER PROCEDURE Publicidad.PiezaContenido_Baja
    @id int
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores nvarchar(2000) = N'';

    -- Validación: la pieza existe
    IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaContenido WHERE id = @id)
        SET @errores = @errores + CHAR(10) + N'- La pieza de contenido con id ' + CAST(@id AS nvarchar) + N' no existe.';

    -- Validación: no tiene exhibiciones activas
    IF EXISTS (
        SELECT 1
        FROM Publicidad.ExhibicionPublicitaria
        WHERE idPieza = @id
          AND estado IN (N'Propuesta', N'Confirmada')
    )
        SET @errores = @errores + CHAR(10) + N'- La pieza tiene exhibiciones activas (en estado Propuesta o Confirmada). Primero deben resolverse esas exhibiciones.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de baja la Pieza de Contenido:' + @errores;
        THROW 50001, @errores, 1;
    END;

    BEGIN TRANSACTION;
    BEGIN TRY
        -- Primero eliminar los mercados asociados
        DELETE FROM Publicidad.PiezaMercado WHERE idPieza = @id;

        -- Luego eliminar la pieza
        DELETE FROM Publicidad.PiezaContenido WHERE id = @id;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- ============================================================================
-- 9. Publicidad.PiezaContenido_Modificacion
-- ============================================================================
CREATE OR ALTER PROCEDURE Publicidad.PiezaContenido_Modificacion
    @id             int,
    @descripcion    nvarchar(80),
    @idioma         char(2)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores nvarchar(2000) = N'';

    -- Validación: la pieza existe
    IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaContenido WHERE id = @id)
        SET @errores = @errores + CHAR(10) + N'- La pieza de contenido con id ' + CAST(@id AS nvarchar) + N' no existe.';

    -- Validación: formato de idioma
    IF @idioma NOT LIKE '[a-z][a-z]'
        SET @errores = @errores + CHAR(10) + N'- El idioma debe contener exactamente 2 letras minúsculas (ej.: ''es'', ''en'', ''pt'').';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo modificar la Pieza de Contenido:' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Publicidad.PiezaContenido
    SET descripcion = @descripcion,
        idioma      = @idioma
    WHERE id = @id;
END;
GO

-- ============================================================================
-- 10. Publicidad.PiezaMercado_Alta
-- ============================================================================
CREATE OR ALTER PROCEDURE Publicidad.PiezaMercado_Alta
    @idPieza    int,
    @idPais     int
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores nvarchar(2000) = N'';

    -- Validación: la pieza existe
    IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaContenido WHERE id = @idPieza)
        SET @errores = @errores + CHAR(10) + N'- La pieza de contenido con id ' + CAST(@idPieza AS nvarchar) + N' no existe.';

    -- Validación: el país existe
    IF NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE id = @idPais)
        SET @errores = @errores + CHAR(10) + N'- El país con id ' + CAST(@idPais AS nvarchar) + N' no existe.';

    -- Validación: el par (idPieza, idPais) no existe ya
    IF EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPieza AND idPais = @idPais)
        SET @errores = @errores + CHAR(10) + N'- El mercado para la pieza ' + CAST(@idPieza AS nvarchar) + N' y el país ' + CAST(@idPais AS nvarchar) + N' ya se encuentra registrado.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de alta la Pieza de Mercado:' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Publicidad.PiezaMercado (idPieza, idPais)
    VALUES (@idPieza, @idPais);
END;
GO

-- ============================================================================
-- 11. Publicidad.PiezaMercado_Baja
-- ============================================================================
CREATE OR ALTER PROCEDURE Publicidad.PiezaMercado_Baja
    @idPieza    int,
    @idPais     int
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores nvarchar(2000) = N'';

    -- Validación: el par (idPieza, idPais) existe
    IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPieza = @idPieza AND idPais = @idPais)
        SET @errores = @errores + CHAR(10) + N'- No existe un mercado registrado para la pieza ' + CAST(@idPieza AS nvarchar) + N' y el país ' + CAST(@idPais AS nvarchar) + N'.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de baja la Pieza de Mercado:' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Publicidad.PiezaMercado
    WHERE idPieza = @idPieza AND idPais = @idPais;
END;
GO

-- ============================================================================
-- 12. Publicidad.UbicacionPublicitaria_Alta
-- ============================================================================
CREATE OR ALTER PROCEDURE Publicidad.UbicacionPublicitaria_Alta
    @idUbicacion    tinyint,
    @nombre         varchar(50),
    @descripcion    varchar(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores nvarchar(2000) = N'';

    -- Validación: idUbicacion no existe aún (catálogo manual)
    IF EXISTS (SELECT 1 FROM Publicidad.UbicacionPublicitaria WHERE idUbicacion = @idUbicacion)
        SET @errores = @errores + CHAR(10) + N'- Ya existe una ubicación publicitaria con id ' + CAST(@idUbicacion AS nvarchar) + N'.';

    -- Validación: nombre no duplicado
    IF EXISTS (SELECT 1 FROM Publicidad.UbicacionPublicitaria WHERE nombre = @nombre)
        SET @errores = @errores + CHAR(10) + N'- Ya existe una ubicación publicitaria con el nombre ''' + @nombre + N'''.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de alta la Ubicación Publicitaria:' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Publicidad.UbicacionPublicitaria (idUbicacion, nombre, descripcion)
    VALUES (@idUbicacion, @nombre, @descripcion);
END;
GO

-- ============================================================================
-- 13. Publicidad.UbicacionPublicitaria_Baja
-- ============================================================================
CREATE OR ALTER PROCEDURE Publicidad.UbicacionPublicitaria_Baja
    @idUbicacion tinyint
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores nvarchar(2000) = N'';

    -- Validación: la ubicación existe
    IF NOT EXISTS (SELECT 1 FROM Publicidad.UbicacionPublicitaria WHERE idUbicacion = @idUbicacion)
        SET @errores = @errores + CHAR(10) + N'- La ubicación publicitaria con id ' + CAST(@idUbicacion AS nvarchar) + N' no existe.';

    -- Validación: no tiene tarifas asociadas
    IF EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idUbicacion = @idUbicacion)
        SET @errores = @errores + CHAR(10) + N'- La ubicación tiene tarifas asociadas. Primero deben eliminarse las tarifas.';

    -- Validación: no tiene exhibiciones asociadas
    IF EXISTS (SELECT 1 FROM Publicidad.ExhibicionPublicitaria WHERE idUbicacion = @idUbicacion)
        SET @errores = @errores + CHAR(10) + N'- La ubicación tiene exhibiciones asociadas. Primero deben eliminarse las exhibiciones.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de baja la Ubicación Publicitaria:' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Publicidad.UbicacionPublicitaria WHERE idUbicacion = @idUbicacion;
END;
GO

-- ============================================================================
-- 14. Publicidad.UbicacionPublicitaria_Modificacion
-- ============================================================================
CREATE OR ALTER PROCEDURE Publicidad.UbicacionPublicitaria_Modificacion
    @idUbicacion    tinyint,
    @nombre         varchar(50),
    @descripcion    varchar(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores nvarchar(2000) = N'';

    -- Validación: la ubicación existe
    IF NOT EXISTS (SELECT 1 FROM Publicidad.UbicacionPublicitaria WHERE idUbicacion = @idUbicacion)
        SET @errores = @errores + CHAR(10) + N'- La ubicación publicitaria con id ' + CAST(@idUbicacion AS nvarchar) + N' no existe.';

    -- Validación: el nuevo nombre no lo usa otra ubicación distinta
    IF EXISTS (SELECT 1 FROM Publicidad.UbicacionPublicitaria WHERE nombre = @nombre AND idUbicacion <> @idUbicacion)
        SET @errores = @errores + CHAR(10) + N'- Ya existe otra ubicación publicitaria con el nombre ''' + @nombre + N'''.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo modificar la Ubicación Publicitaria:' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Publicidad.UbicacionPublicitaria
    SET nombre      = @nombre,
        descripcion = @descripcion
    WHERE idUbicacion = @idUbicacion;
END;
GO

-- ============================================================================
-- 15. Publicidad.Tarifa_Alta
-- ============================================================================
CREATE OR ALTER PROCEDURE Publicidad.Tarifa_Alta
    @idFase         int,
    @idUbicacion    tinyint,
    @montoUSD       decimal(12,2)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores nvarchar(2000) = N'';

    -- Validación: la fase existe
    IF NOT EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = @idFase)
        SET @errores = @errores + CHAR(10) + N'- La fase con id ' + CAST(@idFase AS nvarchar) + N' no existe.';

    -- Validación: la ubicación existe
    IF NOT EXISTS (SELECT 1 FROM Publicidad.UbicacionPublicitaria WHERE idUbicacion = @idUbicacion)
        SET @errores = @errores + CHAR(10) + N'- La ubicación publicitaria con id ' + CAST(@idUbicacion AS nvarchar) + N' no existe.';

    -- Validación: el par (idFase, idUbicacion) no existe ya
    IF EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = @idFase AND idUbicacion = @idUbicacion)
        SET @errores = @errores + CHAR(10) + N'- Ya existe una tarifa para la fase ' + CAST(@idFase AS nvarchar) + N' y la ubicación ' + CAST(@idUbicacion AS nvarchar) + N'.';

    -- Validación: montoUSD > 0
    IF @montoUSD <= 0
        SET @errores = @errores + CHAR(10) + N'- El monto en USD debe ser mayor a cero.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de alta la Tarifa:' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Publicidad.Tarifa (idFase, idUbicacion, montoUSD)
    VALUES (@idFase, @idUbicacion, @montoUSD);
END;
GO

-- ============================================================================
-- 16. Publicidad.Tarifa_Baja
-- ============================================================================
CREATE OR ALTER PROCEDURE Publicidad.Tarifa_Baja
    @idFase         int,
    @idUbicacion    tinyint
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores nvarchar(2000) = N'';

    -- Validación: la tarifa existe
    IF NOT EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = @idFase AND idUbicacion = @idUbicacion)
        SET @errores = @errores + CHAR(10) + N'- La tarifa para la fase ' + CAST(@idFase AS nvarchar) + N' y la ubicación ' + CAST(@idUbicacion AS nvarchar) + N' no existe.';

    -- Validación: no hay exhibiciones que referencien esa ubicación y fase (via el partido de esa fase)
    IF EXISTS (
        SELECT 1
        FROM Publicidad.ExhibicionPublicitaria ep
        INNER JOIN Torneo.Partido p ON p.idPartido = ep.idPartido
        WHERE ep.idUbicacion = @idUbicacion
          AND p.fase = @idFase
    )
        SET @errores = @errores + CHAR(10) + N'- Existen exhibiciones asociadas a esa ubicación en partidos de la fase ' + CAST(@idFase AS nvarchar) + N'. Primero deben eliminarse las exhibiciones correspondientes.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de baja la Tarifa:' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Publicidad.Tarifa
    WHERE idFase = @idFase AND idUbicacion = @idUbicacion;
END;
GO

-- ============================================================================
-- 17. Publicidad.Tarifa_Modificacion
-- ============================================================================
CREATE OR ALTER PROCEDURE Publicidad.Tarifa_Modificacion
    @idFase         int,
    @idUbicacion    tinyint,
    @montoUSD       decimal(12,2)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores nvarchar(2000) = N'';

    -- Validación: la tarifa existe
    IF NOT EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = @idFase AND idUbicacion = @idUbicacion)
        SET @errores = @errores + CHAR(10) + N'- La tarifa para la fase ' + CAST(@idFase AS nvarchar) + N' y la ubicación ' + CAST(@idUbicacion AS nvarchar) + N' no existe.';

    -- Validación: montoUSD > 0
    IF @montoUSD <= 0
        SET @errores = @errores + CHAR(10) + N'- El monto en USD debe ser mayor a cero.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo modificar la Tarifa:' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Publicidad.Tarifa
    SET montoUSD = @montoUSD
    WHERE idFase = @idFase AND idUbicacion = @idUbicacion;
END;
GO

-- ============================================================================
-- 18. Publicidad.ExhibicionPublicitaria_Alta
-- ============================================================================
CREATE OR ALTER PROCEDURE Publicidad.ExhibicionPublicitaria_Alta
    @idPartido          int,
    @idUbicacion        tinyint,
    @idPieza            int,
    @criterioAplicado   tinyint,
    @estado             varchar(15)   = 'Propuesta',
    @montoUSD           decimal(12,2)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores        nvarchar(2000) = N'';
    DECLARE @maxEspacios    int;
    DECLARE @cantActuales   int;
    DECLARE @fechaPartido   date;
    DECLARE @fechaInicio    date;
    DECLARE @fechaFin       date;

    -- Validación: el partido existe
    IF NOT EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido)
        SET @errores = @errores + CHAR(10) + N'- El partido con id ' + CAST(@idPartido AS nvarchar) + N' no existe.';

    -- Validación: la ubicación existe
    IF NOT EXISTS (SELECT 1 FROM Publicidad.UbicacionPublicitaria WHERE idUbicacion = @idUbicacion)
        SET @errores = @errores + CHAR(10) + N'- La ubicación publicitaria con id ' + CAST(@idUbicacion AS nvarchar) + N' no existe.';

    -- Validación: la pieza existe
    IF NOT EXISTS (SELECT 1 FROM Publicidad.PiezaContenido WHERE id = @idPieza)
        SET @errores = @errores + CHAR(10) + N'- La pieza de contenido con id ' + CAST(@idPieza AS nvarchar) + N' no existe.';

    -- Validación: la pieza no está ya asignada al partido (UNIQUE por partido)
    IF EXISTS (
        SELECT 1
        FROM Publicidad.ExhibicionPublicitaria
        WHERE idPartido = @idPartido
          AND idPieza   = @idPieza
    )
        SET @errores = @errores + CHAR(10) + N'- La pieza ' + CAST(@idPieza AS nvarchar) + N' ya está asignada al partido ' + CAST(@idPartido AS nvarchar) + N'.';

    -- Validación: la ubicación no está ya ocupada en ese partido
    IF EXISTS (
        SELECT 1
        FROM Publicidad.ExhibicionPublicitaria
        WHERE idPartido  = @idPartido
          AND idUbicacion = @idUbicacion
    )
        SET @errores = @errores + CHAR(10) + N'- La ubicación ' + CAST(@idUbicacion AS nvarchar) + N' ya está ocupada en el partido ' + CAST(@idPartido AS nvarchar) + N'.';

    -- Validación: criterioAplicado BETWEEN 1 AND 3
    IF @criterioAplicado NOT BETWEEN 1 AND 3
        SET @errores = @errores + CHAR(10) + N'- El criterio aplicado debe estar entre 1 y 3.';

    -- Validación: estado válido
    IF @estado NOT IN (N'Propuesta', N'Confirmada', N'Exhibida')
        SET @errores = @errores + CHAR(10) + N'- El estado debe ser ''Propuesta'', ''Confirmada'' o ''Exhibida''.';

    -- Validación: montoUSD > 0
    IF @montoUSD <= 0
        SET @errores = @errores + CHAR(10) + N'- El monto en USD debe ser mayor a cero.';

    -- Validación: no superar MAX_ESPACIOS_PARTIDO (desde Sistema.Parametro, default 4)
    SELECT @maxEspacios = TRY_CAST(valor AS int)
    FROM Sistema.Parametro
    WHERE clave = N'MAX_ESPACIOS_PARTIDO';

    SET @maxEspacios = ISNULL(@maxEspacios, 4);

    SELECT @cantActuales = COUNT(*)
    FROM Publicidad.ExhibicionPublicitaria
    WHERE idPartido = @idPartido;

    IF @cantActuales >= @maxEspacios
        SET @errores = @errores + CHAR(10) + N'- El partido ' + CAST(@idPartido AS nvarchar) + N' ya alcanzó el máximo de ' + CAST(@maxEspacios AS nvarchar) + N' espacios publicitarios permitidos.';

    -- Validación: la campaña de la pieza está vigente en la fecha del partido
    SELECT @fechaPartido = CAST(p.fechaHoraUTC AS date)
    FROM Torneo.Partido p
    WHERE p.idPartido = @idPartido;

    SELECT @fechaInicio = c.fechaInicio,
           @fechaFin    = c.fechaFin
    FROM Publicidad.PiezaContenido pc
    INNER JOIN Publicidad.Campania c ON c.idCampania = pc.idCampania
    WHERE pc.id = @idPieza;

    IF @fechaPartido IS NOT NULL AND (@fechaInicio IS NULL OR @fechaPartido NOT BETWEEN @fechaInicio AND @fechaFin)
        SET @errores = @errores + CHAR(10) + N'- La campaña de la pieza no está vigente en la fecha del partido (' + CONVERT(nvarchar, @fechaPartido, 23) + N').';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de alta la Exhibición Publicitaria:' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Publicidad.ExhibicionPublicitaria (idPartido, idUbicacion, idPieza, criterioAplicado, estado, montoUSD)
    VALUES (@idPartido, @idUbicacion, @idPieza, @criterioAplicado, @estado, @montoUSD);
END;
GO

-- ============================================================================
-- 19. Publicidad.ExhibicionPublicitaria_Baja
-- ============================================================================
CREATE OR ALTER PROCEDURE Publicidad.ExhibicionPublicitaria_Baja
    @idPartido      int,
    @idUbicacion    tinyint
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores    nvarchar(2000) = N'';
    DECLARE @estadoAct  varchar(15);

    -- Verificar existencia y obtener estado actual
    SELECT @estadoAct = estado
    FROM Publicidad.ExhibicionPublicitaria
    WHERE idPartido = @idPartido AND idUbicacion = @idUbicacion;

    -- Validación: la exhibición existe
    IF @estadoAct IS NULL
        SET @errores = @errores + CHAR(10) + N'- La exhibición publicitaria para el partido ' + CAST(@idPartido AS nvarchar) + N' y la ubicación ' + CAST(@idUbicacion AS nvarchar) + N' no existe.';

    -- Validación: el estado no es 'Exhibida' (registro histórico inamovible)
    IF @estadoAct = N'Exhibida'
        SET @errores = @errores + CHAR(10) + N'- La exhibición ya fue realizada (estado ''Exhibida'') y no puede eliminarse por ser un registro histórico.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de baja la Exhibición Publicitaria:' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Publicidad.ExhibicionPublicitaria
    WHERE idPartido = @idPartido AND idUbicacion = @idUbicacion;
END;
GO

-- ============================================================================
-- 20. Publicidad.ExhibicionPublicitaria_Modificacion
-- ============================================================================
CREATE OR ALTER PROCEDURE Publicidad.ExhibicionPublicitaria_Modificacion
    @idPartido      int,
    @idUbicacion    tinyint,
    @estado         varchar(15),
    @montoUSD       decimal(12,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores        nvarchar(2000) = N'';
    DECLARE @estadoActual   varchar(15);

    -- Obtener estado actual para validar transición
    SELECT @estadoActual = estado
    FROM Publicidad.ExhibicionPublicitaria
    WHERE idPartido = @idPartido AND idUbicacion = @idUbicacion;

    -- Validación: la exhibición existe
    IF @estadoActual IS NULL
        SET @errores = @errores + CHAR(10) + N'- La exhibición publicitaria para el partido ' + CAST(@idPartido AS nvarchar) + N' y la ubicación ' + CAST(@idUbicacion AS nvarchar) + N' no existe.';

    -- Validación: estado nuevo válido
    IF @estado NOT IN (N'Propuesta', N'Confirmada', N'Exhibida')
        SET @errores = @errores + CHAR(10) + N'- El estado debe ser ''Propuesta'', ''Confirmada'' o ''Exhibida''.';

    -- Validación: no retroceder estado (Propuesta=1 < Confirmada=2 < Exhibida=3)
    -- Solo evaluar si el estado actual y el nuevo son ambos válidos
    IF @estadoActual IS NOT NULL AND @estado IN (N'Propuesta', N'Confirmada', N'Exhibida')
    BEGIN
        IF (    @estadoActual = N'Exhibida'  AND @estado IN (N'Confirmada', N'Propuesta'))
            OR  (@estadoActual = N'Confirmada' AND @estado = N'Propuesta')
            SET @errores = @errores + CHAR(10) + N'- No se puede retroceder el estado de la exhibición (actual: ''' + @estadoActual + N''' → nuevo: ''' + @estado + N'''). El flujo es Propuesta → Confirmada → Exhibida.';
    END;

    -- Validación: si se provee @montoUSD, debe ser > 0
    IF @montoUSD IS NOT NULL AND @montoUSD <= 0
        SET @errores = @errores + CHAR(10) + N'- El monto en USD, si se indica, debe ser mayor a cero.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo modificar la Exhibición Publicitaria:' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Publicidad.ExhibicionPublicitaria
    SET estado   = @estado,
        montoUSD = CASE WHEN @montoUSD IS NOT NULL THEN @montoUSD ELSE montoUSD END
    WHERE idPartido = @idPartido AND idUbicacion = @idUbicacion;
END;
GO
