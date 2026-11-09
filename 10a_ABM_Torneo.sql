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
               de las tablas del esquema Torneo:
               - Torneo.Pais
               - Torneo.Fase
               - Torneo.Periodo
               - Torneo.Sede
               - Torneo.Partido

 Estándares aplicados:
 - Cada SP revisa todas las condiciones, acumula las que fallan en @errores
   y, si hay alguna, corta con un único THROW 50001 que las informa juntas.
 - La tabla se modifica solo después de validar con éxito.
 - Los códigos (ISO, moneda) se normalizan a mayúsculas y se comparan con
   intercalación binaria para que '[A-Z]' no acepte minúsculas ni tildes.
 - Los husos horarios se validan contra sys.time_zone_info, porque el
   fixture convierte la hora con AT TIME ZONE.
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

/* =============================================================================
   1. TABLA: Torneo.Pais
   ============================================================================= */

-- 1.1 ALTA DE PAÍS
CREATE OR ALTER PROCEDURE Torneo.Pais_Alta
    @nombre        nvarchar(60),
    @codigoISO2    varchar(10),
    @codigoISO3    varchar(10),
    @husoHorario   varchar(50)   = NULL,
    @moneda        varchar(10)   = NULL,
    @pbiPerCapita  decimal(12,2) = NULL,
    @poblacion     bigint        = NULL,
    @id            int           = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @nombre      = LTRIM(RTRIM(@nombre));
    SET @codigoISO2  = UPPER(LTRIM(RTRIM(@codigoISO2)));
    SET @codigoISO3  = UPPER(LTRIM(RTRIM(@codigoISO3)));
    SET @husoHorario = NULLIF(LTRIM(RTRIM(@husoHorario)), '');
    SET @moneda      = NULLIF(UPPER(LTRIM(RTRIM(@moneda))), '');

    IF @nombre IS NULL OR @nombre = N''
        SET @errores += CHAR(10) + N'- El nombre del país es obligatorio.';
    ELSE IF EXISTS (SELECT 1 FROM Torneo.Pais WHERE nombre = @nombre)
        SET @errores += CHAR(10) + N'- Ya existe un país con ese nombre.';

    IF @codigoISO2 IS NULL OR @codigoISO2 COLLATE Latin1_General_BIN NOT LIKE '[A-Z][A-Z]'
        SET @errores += CHAR(10) + N'- El código ISO alfa-2 debe tener exactamente 2 letras.';
    ELSE IF EXISTS (SELECT 1 FROM Torneo.Pais WHERE codigoISO2 = @codigoISO2)
        SET @errores += CHAR(10) + N'- El código ISO alfa-2 ya está registrado.';

    IF @codigoISO3 IS NULL OR @codigoISO3 COLLATE Latin1_General_BIN NOT LIKE '[A-Z][A-Z][A-Z]'
        SET @errores += CHAR(10) + N'- El código ISO alfa-3 debe tener exactamente 3 letras.';
    ELSE IF EXISTS (SELECT 1 FROM Torneo.Pais WHERE codigoISO3 = @codigoISO3)
        SET @errores += CHAR(10) + N'- El código ISO alfa-3 ya está registrado.';

    IF @husoHorario IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.time_zone_info WHERE name = @husoHorario)
        SET @errores += CHAR(10) + N'- El huso horario no es un nombre válido de sys.time_zone_info.';

    IF @moneda IS NOT NULL AND @moneda COLLATE Latin1_General_BIN NOT LIKE '[A-Z][A-Z][A-Z]'
        SET @errores += CHAR(10) + N'- La moneda debe ser un código ISO 4217 de 3 letras.';

    IF @pbiPerCapita < 0
        SET @errores += CHAR(10) + N'- El PBI per cápita no puede ser negativo.';

    IF @poblacion < 0
        SET @errores += CHAR(10) + N'- La población no puede ser negativa.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de alta el país:' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3, husoHorario, moneda, pbiPerCapita, poblacion)
    VALUES (@nombre, @codigoISO2, @codigoISO3, @husoHorario, @moneda, @pbiPerCapita, @poblacion);

    SET @id = SCOPE_IDENTITY();
END
GO

-- 1.2 MODIFICACIÓN DE PAÍS
CREATE OR ALTER PROCEDURE Torneo.Pais_Modificacion
    @id            int,
    @nombre        nvarchar(60),
    @codigoISO2    varchar(10),
    @codigoISO3    varchar(10),
    @husoHorario   varchar(50)   = NULL,
    @moneda        varchar(10)   = NULL,
    @pbiPerCapita  decimal(12,2) = NULL,
    @poblacion     bigint        = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @nombre      = LTRIM(RTRIM(@nombre));
    SET @codigoISO2  = UPPER(LTRIM(RTRIM(@codigoISO2)));
    SET @codigoISO3  = UPPER(LTRIM(RTRIM(@codigoISO3)));
    SET @husoHorario = NULLIF(LTRIM(RTRIM(@husoHorario)), '');
    SET @moneda      = NULLIF(UPPER(LTRIM(RTRIM(@moneda))), '');

    IF @id IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE id = @id)
        SET @errores += CHAR(10) + N'- El país a modificar no existe.';

    IF @nombre IS NULL OR @nombre = N''
        SET @errores += CHAR(10) + N'- El nombre del país es obligatorio.';
    ELSE IF EXISTS (SELECT 1 FROM Torneo.Pais WHERE nombre = @nombre AND id <> @id)
        SET @errores += CHAR(10) + N'- Ya existe otro país con ese nombre.';

    IF @codigoISO2 IS NULL OR @codigoISO2 COLLATE Latin1_General_BIN NOT LIKE '[A-Z][A-Z]'
        SET @errores += CHAR(10) + N'- El código ISO alfa-2 debe tener exactamente 2 letras.';
    ELSE IF EXISTS (SELECT 1 FROM Torneo.Pais WHERE codigoISO2 = @codigoISO2 AND id <> @id)
        SET @errores += CHAR(10) + N'- El código ISO alfa-2 ya lo usa otro país.';

    IF @codigoISO3 IS NULL OR @codigoISO3 COLLATE Latin1_General_BIN NOT LIKE '[A-Z][A-Z][A-Z]'
        SET @errores += CHAR(10) + N'- El código ISO alfa-3 debe tener exactamente 3 letras.';
    ELSE IF EXISTS (SELECT 1 FROM Torneo.Pais WHERE codigoISO3 = @codigoISO3 AND id <> @id)
        SET @errores += CHAR(10) + N'- El código ISO alfa-3 ya lo usa otro país.';

    IF @husoHorario IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sys.time_zone_info WHERE name = @husoHorario)
        SET @errores += CHAR(10) + N'- El huso horario no es un nombre válido de sys.time_zone_info.';

    IF @moneda IS NOT NULL AND @moneda COLLATE Latin1_General_BIN NOT LIKE '[A-Z][A-Z][A-Z]'
        SET @errores += CHAR(10) + N'- La moneda debe ser un código ISO 4217 de 3 letras.';

    IF @pbiPerCapita < 0
        SET @errores += CHAR(10) + N'- El PBI per cápita no puede ser negativo.';

    IF @poblacion < 0
        SET @errores += CHAR(10) + N'- La población no puede ser negativa.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo modificar el país:' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Torneo.Pais
    SET nombre       = @nombre,
        codigoISO2   = @codigoISO2,
        codigoISO3   = @codigoISO3,
        husoHorario  = @husoHorario,
        moneda       = @moneda,
        pbiPerCapita = @pbiPerCapita,
        poblacion    = @poblacion
    WHERE id = @id;
END
GO

-- 1.3 BAJA DE PAÍS
CREATE OR ALTER PROCEDURE Torneo.Pais_Baja
    @id int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    IF @id IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE id = @id)
        SET @errores += CHAR(10) + N'- El país a eliminar no existe.';

    IF EXISTS (SELECT 1 FROM Torneo.Sede WHERE idPais = @id)
        SET @errores += CHAR(10) + N'- El país tiene sedes registradas.';

    IF EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE idPais = @id)
        SET @errores += CHAR(10) + N'- El país tiene una selección registrada.';

    IF EXISTS (SELECT 1 FROM Arbitraje.Arbitro WHERE idPais = @id)
        SET @errores += CHAR(10) + N'- El país tiene árbitros registrados.';

    IF EXISTS (SELECT 1 FROM Publicidad.Anunciante WHERE idPais = @id)
        SET @errores += CHAR(10) + N'- El país tiene anunciantes registrados.';

    IF EXISTS (SELECT 1 FROM Publicidad.PiezaMercado WHERE idPais = @id)
        SET @errores += CHAR(10) + N'- El país es mercado de piezas publicitarias.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de baja el país:' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Torneo.Pais WHERE id = @id;
END
GO

/* =============================================================================
   2. TABLA: Torneo.Fase (catálogo con ids controlados a mano)
   ============================================================================= */

-- 2.1 ALTA DE FASE
CREATE OR ALTER PROCEDURE Torneo.Fase_Alta
    @idFase          int,
    @nombre          varchar(60),
    @esEliminatoria  bit,
    @orden           int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @nombre = LTRIM(RTRIM(@nombre));

    IF @idFase IS NULL OR @idFase <= 0
        SET @errores += CHAR(10) + N'- El id de la fase es obligatorio y debe ser mayor a cero.';
    ELSE IF EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = @idFase)
        SET @errores += CHAR(10) + N'- Ya existe una fase con ese id.';

    IF @nombre IS NULL OR @nombre = ''
        SET @errores += CHAR(10) + N'- El nombre de la fase es obligatorio.';
    ELSE IF EXISTS (SELECT 1 FROM Torneo.Fase WHERE nombre = @nombre)
        SET @errores += CHAR(10) + N'- Ya existe una fase con ese nombre.';

    IF @esEliminatoria IS NULL
        SET @errores += CHAR(10) + N'- Debe indicar si la fase es eliminatoria (1) o no (0).';

    IF @orden IS NULL OR @orden <= 0
        SET @errores += CHAR(10) + N'- El orden de la fase es obligatorio y debe ser mayor a cero.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de alta la fase:' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Torneo.Fase (idFase, nombre, esEliminatoria, orden)
    VALUES (@idFase, @nombre, @esEliminatoria, @orden);
END
GO

-- 2.2 MODIFICACIÓN DE FASE
CREATE OR ALTER PROCEDURE Torneo.Fase_Modificacion
    @idFase          int,
    @nombre          varchar(60),
    @esEliminatoria  bit,
    @orden           int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @nombre = LTRIM(RTRIM(@nombre));

    IF @idFase IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = @idFase)
        SET @errores += CHAR(10) + N'- La fase a modificar no existe.';

    IF @nombre IS NULL OR @nombre = ''
        SET @errores += CHAR(10) + N'- El nombre de la fase es obligatorio.';
    ELSE IF EXISTS (SELECT 1 FROM Torneo.Fase WHERE nombre = @nombre AND idFase <> @idFase)
        SET @errores += CHAR(10) + N'- Ya existe otra fase con ese nombre.';

    IF @esEliminatoria IS NULL
        SET @errores += CHAR(10) + N'- Debe indicar si la fase es eliminatoria (1) o no (0).';

    IF @orden IS NULL OR @orden <= 0
        SET @errores += CHAR(10) + N'- El orden de la fase es obligatorio y debe ser mayor a cero.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo modificar la fase:' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Torneo.Fase
    SET nombre         = @nombre,
        esEliminatoria = @esEliminatoria,
        orden          = @orden
    WHERE idFase = @idFase;
END
GO

-- 2.3 BAJA DE FASE
CREATE OR ALTER PROCEDURE Torneo.Fase_Baja
    @idFase int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    IF @idFase IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = @idFase)
        SET @errores += CHAR(10) + N'- La fase a eliminar no existe.';

    IF EXISTS (SELECT 1 FROM Torneo.Partido WHERE fase = @idFase)
        SET @errores += CHAR(10) + N'- La fase tiene partidos asignados.';

    IF EXISTS (SELECT 1 FROM Publicidad.Tarifa WHERE idFase = @idFase)
        SET @errores += CHAR(10) + N'- La fase tiene tarifas publicitarias asociadas.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de baja la fase:' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Torneo.Fase WHERE idFase = @idFase;
END
GO

/* =============================================================================
   3. TABLA: Torneo.Periodo (catálogo con ids controlados a mano)
   Los parámetros numéricos se reciben como int para poder informar el rango
   en lugar de fallar en la conversión a tinyint.
   ============================================================================= */

-- 3.1 ALTA DE PERÍODO
CREATE OR ALTER PROCEDURE Torneo.Periodo_Alta
    @idPeriodo  int,
    @nombre     varchar(30),
    @orden      int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @nombre = LTRIM(RTRIM(@nombre));

    IF @idPeriodo IS NULL OR @idPeriodo NOT BETWEEN 1 AND 255
        SET @errores += CHAR(10) + N'- El id del período es obligatorio y debe estar entre 1 y 255.';
    ELSE IF EXISTS (SELECT 1 FROM Torneo.Periodo WHERE idPeriodo = @idPeriodo)
        SET @errores += CHAR(10) + N'- Ya existe un período con ese id.';

    IF @nombre IS NULL OR @nombre = ''
        SET @errores += CHAR(10) + N'- El nombre del período es obligatorio.';
    ELSE IF EXISTS (SELECT 1 FROM Torneo.Periodo WHERE nombre = @nombre)
        SET @errores += CHAR(10) + N'- Ya existe un período con ese nombre.';

    IF @orden IS NULL OR @orden NOT BETWEEN 1 AND 255
        SET @errores += CHAR(10) + N'- El orden del período es obligatorio y debe estar entre 1 y 255.';
    ELSE IF EXISTS (SELECT 1 FROM Torneo.Periodo WHERE orden = @orden)
        SET @errores += CHAR(10) + N'- Ya existe un período con ese orden.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de alta el período:' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Torneo.Periodo (idPeriodo, nombre, orden)
    VALUES (@idPeriodo, @nombre, @orden);
END
GO

-- 3.2 MODIFICACIÓN DE PERÍODO
CREATE OR ALTER PROCEDURE Torneo.Periodo_Modificacion
    @idPeriodo  int,
    @nombre     varchar(30),
    @orden      int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @nombre = LTRIM(RTRIM(@nombre));

    IF @idPeriodo IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Periodo WHERE idPeriodo = @idPeriodo)
        SET @errores += CHAR(10) + N'- El período a modificar no existe.';

    IF @nombre IS NULL OR @nombre = ''
        SET @errores += CHAR(10) + N'- El nombre del período es obligatorio.';
    ELSE IF EXISTS (SELECT 1 FROM Torneo.Periodo WHERE nombre = @nombre AND idPeriodo <> @idPeriodo)
        SET @errores += CHAR(10) + N'- Ya existe otro período con ese nombre.';

    IF @orden IS NULL OR @orden NOT BETWEEN 1 AND 255
        SET @errores += CHAR(10) + N'- El orden del período es obligatorio y debe estar entre 1 y 255.';
    ELSE IF EXISTS (SELECT 1 FROM Torneo.Periodo WHERE orden = @orden AND idPeriodo <> @idPeriodo)
        SET @errores += CHAR(10) + N'- Ya existe otro período con ese orden.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo modificar el período:' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Torneo.Periodo
    SET nombre = @nombre,
        orden  = @orden
    WHERE idPeriodo = @idPeriodo;
END
GO

-- 3.3 BAJA DE PERÍODO
CREATE OR ALTER PROCEDURE Torneo.Periodo_Baja
    @idPeriodo int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    IF @idPeriodo IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Periodo WHERE idPeriodo = @idPeriodo)
        SET @errores += CHAR(10) + N'- El período a eliminar no existe.';

    IF EXISTS (SELECT 1 FROM Eventos.Gol WHERE idPeriodo = @idPeriodo)
       OR EXISTS (SELECT 1 FROM Eventos.Tarjeta WHERE idPeriodo = @idPeriodo)
       OR EXISTS (SELECT 1 FROM Eventos.Sustitucion WHERE idPeriodo = @idPeriodo)
        SET @errores += CHAR(10) + N'- El período tiene goles, tarjetas o sustituciones registrados.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de baja el período:' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Torneo.Periodo WHERE idPeriodo = @idPeriodo;
END
GO

/* =============================================================================
   4. TABLA: Torneo.Sede
   ============================================================================= */

-- 4.1 ALTA DE SEDE
CREATE OR ALTER PROCEDURE Torneo.Sede_Alta
    @nombreEstadio  nvarchar(80),
    @ciudad         nvarchar(60),
    @idPais         int,
    @husoHorario    varchar(50),
    @capacidad      int          = NULL,
    @latitud        decimal(9,6) = NULL,
    @longitud       decimal(9,6) = NULL,
    @idSede         int          = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @nombreEstadio = LTRIM(RTRIM(@nombreEstadio));
    SET @ciudad        = LTRIM(RTRIM(@ciudad));
    SET @husoHorario   = LTRIM(RTRIM(@husoHorario));

    IF @nombreEstadio IS NULL OR @nombreEstadio = N''
        SET @errores += CHAR(10) + N'- El nombre del estadio es obligatorio.';

    IF @ciudad IS NULL OR @ciudad = N''
        SET @errores += CHAR(10) + N'- La ciudad es obligatoria.';

    IF @idPais IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE id = @idPais)
        SET @errores += CHAR(10) + N'- El país de la sede no existe.';

    IF @husoHorario IS NULL OR NOT EXISTS (SELECT 1 FROM sys.time_zone_info WHERE name = @husoHorario)
        SET @errores += CHAR(10) + N'- El huso horario es obligatorio y debe ser un nombre válido de sys.time_zone_info.';

    IF @capacidad <= 0
        SET @errores += CHAR(10) + N'- La capacidad del estadio debe ser mayor a cero.';

    IF @latitud NOT BETWEEN -90 AND 90
        SET @errores += CHAR(10) + N'- La latitud debe estar entre -90 y 90.';

    IF @longitud NOT BETWEEN -180 AND 180
        SET @errores += CHAR(10) + N'- La longitud debe estar entre -180 y 180.';

    IF EXISTS (SELECT 1 FROM Torneo.Sede WHERE nombreEstadio = @nombreEstadio AND ciudad = @ciudad)
        SET @errores += CHAR(10) + N'- Ya existe una sede con ese estadio en esa ciudad.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de alta la sede:' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Torneo.Sede (nombreEstadio, ciudad, idPais, capacidad, husoHorario, latitud, longitud)
    VALUES (@nombreEstadio, @ciudad, @idPais, @capacidad, @husoHorario, @latitud, @longitud);

    SET @idSede = SCOPE_IDENTITY();
END
GO

-- 4.2 MODIFICACIÓN DE SEDE
CREATE OR ALTER PROCEDURE Torneo.Sede_Modificacion
    @idSede         int,
    @nombreEstadio  nvarchar(80),
    @ciudad         nvarchar(60),
    @idPais         int,
    @husoHorario    varchar(50),
    @capacidad      int          = NULL,
    @latitud        decimal(9,6) = NULL,
    @longitud       decimal(9,6) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @nombreEstadio = LTRIM(RTRIM(@nombreEstadio));
    SET @ciudad        = LTRIM(RTRIM(@ciudad));
    SET @husoHorario   = LTRIM(RTRIM(@husoHorario));

    IF @idSede IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Sede WHERE idSede = @idSede)
        SET @errores += CHAR(10) + N'- La sede a modificar no existe.';

    IF @nombreEstadio IS NULL OR @nombreEstadio = N''
        SET @errores += CHAR(10) + N'- El nombre del estadio es obligatorio.';

    IF @ciudad IS NULL OR @ciudad = N''
        SET @errores += CHAR(10) + N'- La ciudad es obligatoria.';

    IF @idPais IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE id = @idPais)
        SET @errores += CHAR(10) + N'- El país de la sede no existe.';

    IF @husoHorario IS NULL OR NOT EXISTS (SELECT 1 FROM sys.time_zone_info WHERE name = @husoHorario)
        SET @errores += CHAR(10) + N'- El huso horario es obligatorio y debe ser un nombre válido de sys.time_zone_info.';

    IF @capacidad <= 0
        SET @errores += CHAR(10) + N'- La capacidad del estadio debe ser mayor a cero.';
    ELSE IF EXISTS (SELECT 1 FROM Torneo.Partido WHERE idSede = @idSede AND cantPublico > @capacidad)
        SET @errores += CHAR(10) + N'- La nueva capacidad es menor que el público registrado en partidos de la sede.';

    IF @latitud NOT BETWEEN -90 AND 90
        SET @errores += CHAR(10) + N'- La latitud debe estar entre -90 y 90.';

    IF @longitud NOT BETWEEN -180 AND 180
        SET @errores += CHAR(10) + N'- La longitud debe estar entre -180 y 180.';

    IF EXISTS (SELECT 1 FROM Torneo.Sede
               WHERE nombreEstadio = @nombreEstadio AND ciudad = @ciudad AND idSede <> @idSede)
        SET @errores += CHAR(10) + N'- Ya existe otra sede con ese estadio en esa ciudad.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo modificar la sede:' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Torneo.Sede
    SET nombreEstadio = @nombreEstadio,
        ciudad        = @ciudad,
        idPais        = @idPais,
        capacidad     = @capacidad,
        husoHorario   = @husoHorario,
        latitud       = @latitud,
        longitud      = @longitud
    WHERE idSede = @idSede;
END
GO

-- 4.3 BAJA DE SEDE
CREATE OR ALTER PROCEDURE Torneo.Sede_Baja
    @idSede int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    IF @idSede IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Sede WHERE idSede = @idSede)
        SET @errores += CHAR(10) + N'- La sede a eliminar no existe.';

    IF EXISTS (SELECT 1 FROM Torneo.Partido WHERE idSede = @idSede)
        SET @errores += CHAR(10) + N'- La sede tiene partidos asignados.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de baja la sede:' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Torneo.Sede WHERE idSede = @idSede;
END
GO

/* =============================================================================
   5. TABLA: Torneo.Partido
   Reglas propias además de las restricciones de la tabla:
   - Un partido Programado no lleva resultado; uno Finalizado lo exige.
   - El resultado se carga completo (los dos goles) o no se carga.
   - El público no puede superar la capacidad de la sede.
   - Ni la sede ni las selecciones pueden tener otro partido a menos de 24 h.
   - El esquema táctico son números de 1 a 9 separados por guiones que suman
     10 jugadores de campo (por ejemplo 4-3-3 o 4-2-3-1).
   ============================================================================= */

-- 5.1 ALTA DE PARTIDO
CREATE OR ALTER PROCEDURE Torneo.Partido_Alta
    @idSede                int,
    @idSeleccionLocal      int,
    @idSeleccionVisitante  int,
    @fase                  int,
    @fechaHoraUTC          datetime2(0),
    @estado                varchar(15)  = 'Programado',
    @nroPartidoOficial     int          = NULL,
    @cantPublico           int          = NULL,
    @golLocal              tinyint      = NULL,
    @golVisitante          tinyint      = NULL,
    @esquemaLocal          varchar(10)  = NULL,
    @esquemaVisitante      varchar(10)  = NULL,
    @idPartido             int          = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @estado           = LTRIM(RTRIM(@estado));
    SET @esquemaLocal     = NULLIF(LTRIM(RTRIM(@esquemaLocal)), '');
    SET @esquemaVisitante = NULLIF(LTRIM(RTRIM(@esquemaVisitante)), '');

    IF @idSede IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Sede WHERE idSede = @idSede)
        SET @errores += CHAR(10) + N'- La sede no existe.';

    IF @idSeleccionLocal IS NULL OR NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE id = @idSeleccionLocal)
        SET @errores += CHAR(10) + N'- La selección local no existe.';

    IF @idSeleccionVisitante IS NULL OR NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE id = @idSeleccionVisitante)
        SET @errores += CHAR(10) + N'- La selección visitante no existe.';

    IF @idSeleccionLocal = @idSeleccionVisitante
        SET @errores += CHAR(10) + N'- La selección local y la visitante deben ser distintas.';

    IF @fase IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = @fase)
        SET @errores += CHAR(10) + N'- La fase no existe.';

    IF @fechaHoraUTC IS NULL
        SET @errores += CHAR(10) + N'- La fecha y hora UTC del partido es obligatoria.';

    IF @estado IS NULL OR @estado NOT IN ('Programado', 'En juego', 'Finalizado', 'Suspendido')
        SET @errores += CHAR(10) + N'- El estado debe ser Programado, En juego, Finalizado o Suspendido.';
    ELSE IF @estado = 'Programado' AND (@golLocal IS NOT NULL OR @golVisitante IS NOT NULL)
        SET @errores += CHAR(10) + N'- Un partido programado no puede tener resultado cargado.';
    ELSE IF @estado = 'Finalizado' AND (@golLocal IS NULL OR @golVisitante IS NULL)
        SET @errores += CHAR(10) + N'- Un partido finalizado requiere el resultado completo.';

    IF (@golLocal IS NULL AND @golVisitante IS NOT NULL) OR (@golLocal IS NOT NULL AND @golVisitante IS NULL)
        SET @errores += CHAR(10) + N'- El resultado debe cargarse completo: goles del local y del visitante.';

    IF @nroPartidoOficial <= 0
        SET @errores += CHAR(10) + N'- El número de partido oficial debe ser mayor a cero.';
    ELSE IF EXISTS (SELECT 1 FROM Torneo.Partido WHERE nroPartidoOficial = @nroPartidoOficial)
        SET @errores += CHAR(10) + N'- El número de partido oficial ya está registrado.';

    IF @cantPublico < 0
        SET @errores += CHAR(10) + N'- La cantidad de público no puede ser negativa.';
    ELSE IF EXISTS (SELECT 1 FROM Torneo.Sede WHERE idSede = @idSede AND @cantPublico > capacidad)
        SET @errores += CHAR(10) + N'- La cantidad de público supera la capacidad de la sede.';

    IF @esquemaLocal IS NOT NULL
       AND (@esquemaLocal NOT LIKE '[1-9]-%[1-9]' OR @esquemaLocal LIKE '%[^1-9-]%'
            OR @esquemaLocal LIKE '%--%' OR @esquemaLocal LIKE '%[0-9][0-9]%'
            OR (SELECT SUM(TRY_CAST(value AS int)) FROM STRING_SPLIT(@esquemaLocal, '-')) <> 10)
        SET @errores += CHAR(10) + N'- El esquema local debe tener números de 1 a 9 separados por guiones que sumen 10 (ej. 4-3-3).';

    IF @esquemaVisitante IS NOT NULL
       AND (@esquemaVisitante NOT LIKE '[1-9]-%[1-9]' OR @esquemaVisitante LIKE '%[^1-9-]%'
            OR @esquemaVisitante LIKE '%--%' OR @esquemaVisitante LIKE '%[0-9][0-9]%'
            OR (SELECT SUM(TRY_CAST(value AS int)) FROM STRING_SPLIT(@esquemaVisitante, '-')) <> 10)
        SET @errores += CHAR(10) + N'- El esquema visitante debe tener números de 1 a 9 separados por guiones que sumen 10 (ej. 4-3-3).';

    IF @fechaHoraUTC IS NOT NULL
       AND EXISTS (SELECT 1 FROM Torneo.Partido
                   WHERE idSede = @idSede
                     AND ABS(DATEDIFF(MINUTE, fechaHoraUTC, @fechaHoraUTC)) < 1440)
        SET @errores += CHAR(10) + N'- La sede ya tiene otro partido a menos de 24 horas.';

    IF @fechaHoraUTC IS NOT NULL
       AND EXISTS (SELECT 1 FROM Torneo.Partido
                   WHERE (idSeleccionLocal IN (@idSeleccionLocal, @idSeleccionVisitante)
                          OR idSeleccionVisitante IN (@idSeleccionLocal, @idSeleccionVisitante))
                     AND ABS(DATEDIFF(MINUTE, fechaHoraUTC, @fechaHoraUTC)) < 1440)
        SET @errores += CHAR(10) + N'- Alguna de las selecciones ya tiene otro partido a menos de 24 horas.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de alta el partido:' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Torneo.Partido (nroPartidoOficial, idSede, idSeleccionLocal, idSeleccionVisitante, fase,
                                fechaHoraUTC, estado, cantPublico, golLocal, golVisitante,
                                esquemaLocal, esquemaVisitante)
    VALUES (@nroPartidoOficial, @idSede, @idSeleccionLocal, @idSeleccionVisitante, @fase,
            @fechaHoraUTC, @estado, @cantPublico, @golLocal, @golVisitante,
            @esquemaLocal, @esquemaVisitante);

    SET @idPartido = SCOPE_IDENTITY();
END
GO

-- 5.2 MODIFICACIÓN DE PARTIDO
-- Además de las reglas del alta: no se cambian las selecciones si ya hay
-- formaciones cargadas, ni se vuelve a Programado si hay eventos registrados.
CREATE OR ALTER PROCEDURE Torneo.Partido_Modificacion
    @idPartido             int,
    @idSede                int,
    @idSeleccionLocal      int,
    @idSeleccionVisitante  int,
    @fase                  int,
    @fechaHoraUTC          datetime2(0),
    @estado                varchar(15),
    @nroPartidoOficial     int          = NULL,
    @cantPublico           int          = NULL,
    @golLocal              tinyint      = NULL,
    @golVisitante          tinyint      = NULL,
    @esquemaLocal          varchar(10)  = NULL,
    @esquemaVisitante      varchar(10)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @estado           = LTRIM(RTRIM(@estado));
    SET @esquemaLocal     = NULLIF(LTRIM(RTRIM(@esquemaLocal)), '');
    SET @esquemaVisitante = NULLIF(LTRIM(RTRIM(@esquemaVisitante)), '');

    IF @idPartido IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido)
        SET @errores += CHAR(10) + N'- El partido a modificar no existe.';

    IF @idSede IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Sede WHERE idSede = @idSede)
        SET @errores += CHAR(10) + N'- La sede no existe.';

    IF @idSeleccionLocal IS NULL OR NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE id = @idSeleccionLocal)
        SET @errores += CHAR(10) + N'- La selección local no existe.';

    IF @idSeleccionVisitante IS NULL OR NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE id = @idSeleccionVisitante)
        SET @errores += CHAR(10) + N'- La selección visitante no existe.';

    IF @idSeleccionLocal = @idSeleccionVisitante
        SET @errores += CHAR(10) + N'- La selección local y la visitante deben ser distintas.';

    IF @fase IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = @fase)
        SET @errores += CHAR(10) + N'- La fase no existe.';

    IF @fechaHoraUTC IS NULL
        SET @errores += CHAR(10) + N'- La fecha y hora UTC del partido es obligatoria.';

    IF @estado IS NULL OR @estado NOT IN ('Programado', 'En juego', 'Finalizado', 'Suspendido')
        SET @errores += CHAR(10) + N'- El estado debe ser Programado, En juego, Finalizado o Suspendido.';
    ELSE IF @estado = 'Programado' AND (@golLocal IS NOT NULL OR @golVisitante IS NOT NULL)
        SET @errores += CHAR(10) + N'- Un partido programado no puede tener resultado cargado.';
    ELSE IF @estado = 'Finalizado' AND (@golLocal IS NULL OR @golVisitante IS NULL)
        SET @errores += CHAR(10) + N'- Un partido finalizado requiere el resultado completo.';

    IF (@golLocal IS NULL AND @golVisitante IS NOT NULL) OR (@golLocal IS NOT NULL AND @golVisitante IS NULL)
        SET @errores += CHAR(10) + N'- El resultado debe cargarse completo: goles del local y del visitante.';

    IF @nroPartidoOficial <= 0
        SET @errores += CHAR(10) + N'- El número de partido oficial debe ser mayor a cero.';
    ELSE IF EXISTS (SELECT 1 FROM Torneo.Partido
                    WHERE nroPartidoOficial = @nroPartidoOficial AND idPartido <> @idPartido)
        SET @errores += CHAR(10) + N'- El número de partido oficial ya lo usa otro partido.';

    IF @cantPublico < 0
        SET @errores += CHAR(10) + N'- La cantidad de público no puede ser negativa.';
    ELSE IF EXISTS (SELECT 1 FROM Torneo.Sede WHERE idSede = @idSede AND @cantPublico > capacidad)
        SET @errores += CHAR(10) + N'- La cantidad de público supera la capacidad de la sede.';

    IF @esquemaLocal IS NOT NULL
       AND (@esquemaLocal NOT LIKE '[1-9]-%[1-9]' OR @esquemaLocal LIKE '%[^1-9-]%'
            OR @esquemaLocal LIKE '%--%' OR @esquemaLocal LIKE '%[0-9][0-9]%'
            OR (SELECT SUM(TRY_CAST(value AS int)) FROM STRING_SPLIT(@esquemaLocal, '-')) <> 10)
        SET @errores += CHAR(10) + N'- El esquema local debe tener números de 1 a 9 separados por guiones que sumen 10 (ej. 4-3-3).';

    IF @esquemaVisitante IS NOT NULL
       AND (@esquemaVisitante NOT LIKE '[1-9]-%[1-9]' OR @esquemaVisitante LIKE '%[^1-9-]%'
            OR @esquemaVisitante LIKE '%--%' OR @esquemaVisitante LIKE '%[0-9][0-9]%'
            OR (SELECT SUM(TRY_CAST(value AS int)) FROM STRING_SPLIT(@esquemaVisitante, '-')) <> 10)
        SET @errores += CHAR(10) + N'- El esquema visitante debe tener números de 1 a 9 separados por guiones que sumen 10 (ej. 4-3-3).';

    IF @fechaHoraUTC IS NOT NULL
       AND EXISTS (SELECT 1 FROM Torneo.Partido
                   WHERE idSede = @idSede AND idPartido <> @idPartido
                     AND ABS(DATEDIFF(MINUTE, fechaHoraUTC, @fechaHoraUTC)) < 1440)
        SET @errores += CHAR(10) + N'- La sede ya tiene otro partido a menos de 24 horas.';

    IF @fechaHoraUTC IS NOT NULL
       AND EXISTS (SELECT 1 FROM Torneo.Partido
                   WHERE idPartido <> @idPartido
                     AND (idSeleccionLocal IN (@idSeleccionLocal, @idSeleccionVisitante)
                          OR idSeleccionVisitante IN (@idSeleccionLocal, @idSeleccionVisitante))
                     AND ABS(DATEDIFF(MINUTE, fechaHoraUTC, @fechaHoraUTC)) < 1440)
        SET @errores += CHAR(10) + N'- Alguna de las selecciones ya tiene otro partido a menos de 24 horas.';

    -- Las formaciones guardan la selección: cambiarla las dejaría inconsistentes
    IF EXISTS (SELECT 1 FROM Torneo.Partido
               WHERE idPartido = @idPartido
                 AND (idSeleccionLocal <> @idSeleccionLocal OR idSeleccionVisitante <> @idSeleccionVisitante))
       AND EXISTS (SELECT 1 FROM Eventos.FormacionPartido WHERE idPartido = @idPartido)
        SET @errores += CHAR(10) + N'- No se pueden cambiar las selecciones porque el partido ya tiene formaciones cargadas.';

    IF @estado = 'Programado'
       AND (EXISTS (SELECT 1 FROM Eventos.Gol WHERE idPartido = @idPartido)
            OR EXISTS (SELECT 1 FROM Eventos.Tarjeta WHERE idPartido = @idPartido)
            OR EXISTS (SELECT 1 FROM Eventos.Sustitucion WHERE idPartido = @idPartido))
        SET @errores += CHAR(10) + N'- No se puede volver a Programado porque el partido tiene eventos registrados.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo modificar el partido:' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Torneo.Partido
    SET nroPartidoOficial    = @nroPartidoOficial,
        idSede               = @idSede,
        idSeleccionLocal     = @idSeleccionLocal,
        idSeleccionVisitante = @idSeleccionVisitante,
        fase                 = @fase,
        fechaHoraUTC         = @fechaHoraUTC,
        estado               = @estado,
        cantPublico          = @cantPublico,
        golLocal             = @golLocal,
        golVisitante         = @golVisitante,
        esquemaLocal         = @esquemaLocal,
        esquemaVisitante     = @esquemaVisitante
    WHERE idPartido = @idPartido;
END
GO

-- 5.3 BAJA DE PARTIDO
CREATE OR ALTER PROCEDURE Torneo.Partido_Baja
    @idPartido int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    IF @idPartido IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido)
        SET @errores += CHAR(10) + N'- El partido a eliminar no existe.';

    IF EXISTS (SELECT 1 FROM Eventos.FormacionPartido WHERE idPartido = @idPartido)
        SET @errores += CHAR(10) + N'- El partido tiene formaciones cargadas.';

    IF EXISTS (SELECT 1 FROM Eventos.Gol WHERE idPartido = @idPartido)
       OR EXISTS (SELECT 1 FROM Eventos.Tarjeta WHERE idPartido = @idPartido)
       OR EXISTS (SELECT 1 FROM Eventos.Sustitucion WHERE idPartido = @idPartido)
       OR EXISTS (SELECT 1 FROM Eventos.Suspension WHERE idPartido = @idPartido)
        SET @errores += CHAR(10) + N'- El partido tiene goles, tarjetas, sustituciones o suspensiones registrados.';

    IF EXISTS (SELECT 1 FROM Arbitraje.cuerpoArbitral WHERE idPartido = @idPartido)
       OR EXISTS (SELECT 1 FROM Arbitraje.InformeArbitral WHERE idPartido = @idPartido)
        SET @errores += CHAR(10) + N'- El partido tiene designaciones o informes arbitrales.';

    IF EXISTS (SELECT 1 FROM Publicidad.ExhibicionPublicitaria WHERE idPartido = @idPartido)
        SET @errores += CHAR(10) + N'- El partido tiene exhibiciones publicitarias asignadas.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de baja el partido:' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Torneo.Partido WHERE idPartido = @idPartido;
END
GO
