/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel - 45066788
               Salas, Martin Daniel - 45205702
               Zito Padró, Ezequiel Nehuén - 46097917
 Fecha       : 08/11/2026

 Objetivo    : Procedimientos almacenados para operaciones de Alta, Baja
               y Modificación (ABM) de las tablas del esquema Arbitraje:
               - Arbitraje.Arbitro
               - Arbitraje.ArbitroIdioma
               - Arbitraje.cuerpoArbitral
               - Arbitraje.InformeArbitral

 Estándares aplicados:
 - Acumulación exhaustiva de errores en @errores.
 - Un solo THROW 50001 al final de las validaciones informando todos los fallos.
 - Nombres en formato Esquema.Tabla_Accion.
 - Modificación de datos sólo tras validar con éxito todas las precondiciones.
 - Control estricto de transacciones en operaciones multi-tabla (TRY...CATCH con ROLLBACK).
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

/* =============================================================================
   1. TABLA: Arbitraje.Arbitro
   ============================================================================= */

-- 1.1 ALTA DE ÁRBITRO
CREATE OR ALTER PROCEDURE Arbitraje.Arbitro_Alta
    @idPais             int,
    @nombre             nvarchar(60),
    @apellido           nvarchar(60),
    @categoria          varchar(15),
    @genero             varchar(20) = NULL,
    @fechaInternacional date        = NULL,
    @idArbitro          int         = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @genero = NULLIF(LTRIM(RTRIM(@genero)), '');

    -- Validaciones de obligatoriedad y formato
    IF @nombre IS NULL OR LTRIM(RTRIM(@nombre)) = N''
        SET @errores += CHAR(10) + N'- El nombre del árbitro es obligatorio.';

    IF @apellido IS NULL OR LTRIM(RTRIM(@apellido)) = N''
        SET @errores += CHAR(10) + N'- El apellido del árbitro es obligatorio.';

    -- Validación de clave foránea a Torneo.Pais
    IF @idPais IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE id = @idPais)
        SET @errores += CHAR(10) + N'- El país especificado no existe.';

    -- Validación de categoría permitida
    IF @categoria IS NULL OR @categoria NOT IN ('FIFA', 'Confederacion')
        SET @errores += CHAR(10) + N'- La categoría debe ser ''FIFA'' o ''Confederacion''.';

    -- Validación de fecha internacional lógica
    IF @fechaInternacional IS NOT NULL AND @fechaInternacional > CAST(GETDATE() AS date)
        SET @errores += CHAR(10) + N'- La fecha de obtención de categoría internacional no puede ser futura.';

    -- Validación de unicidad de negocio (mismo país, nombre y apellido)
    IF @idPais IS NOT NULL AND @nombre IS NOT NULL AND @apellido IS NOT NULL
       AND EXISTS (
           SELECT 1
           FROM Arbitraje.Arbitro
           WHERE idPais = @idPais
             AND UPPER(LTRIM(RTRIM(nombre))) = UPPER(LTRIM(RTRIM(@nombre)))
             AND UPPER(LTRIM(RTRIM(apellido))) = UPPER(LTRIM(RTRIM(@apellido)))
       )
        SET @errores += CHAR(10) + N'- Ya existe un árbitro registrado con el mismo nombre y apellido para dicho país.';

    -- THROW único en caso de error
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de alta el árbitro:' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- Inserción
    INSERT INTO Arbitraje.Arbitro (idPais, nombre, apellido, categoria, genero, fechaInternacional)
    VALUES (@idPais, LTRIM(RTRIM(@nombre)), LTRIM(RTRIM(@apellido)), @categoria, @genero, @fechaInternacional);

    SET @idArbitro = SCOPE_IDENTITY();
END
GO

-- 1.2 MODIFICACIÓN DE ÁRBITRO
CREATE OR ALTER PROCEDURE Arbitraje.Arbitro_Modificacion
    @idArbitro          int,
    @idPais             int,
    @nombre             nvarchar(60),
    @apellido           nvarchar(60),
    @categoria          varchar(15),
    @genero             varchar(20) = NULL,
    @fechaInternacional date        = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @genero = NULLIF(LTRIM(RTRIM(@genero)), '');

    -- Existencia del registro a modificar
    IF @idArbitro IS NULL OR NOT EXISTS (SELECT 1 FROM Arbitraje.Arbitro WHERE idArbitro = @idArbitro)
        SET @errores += CHAR(10) + N'- El árbitro a modificar no existe.';

    -- Validaciones de campos
    IF @nombre IS NULL OR LTRIM(RTRIM(@nombre)) = N''
        SET @errores += CHAR(10) + N'- El nombre del árbitro es obligatorio.';

    IF @apellido IS NULL OR LTRIM(RTRIM(@apellido)) = N''
        SET @errores += CHAR(10) + N'- El apellido del árbitro es obligatorio.';

    IF @idPais IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE id = @idPais)
        SET @errores += CHAR(10) + N'- El país especificado no existe.';

    IF @categoria IS NULL OR @categoria NOT IN ('FIFA', 'Confederacion')
        SET @errores += CHAR(10) + N'- La categoría debe ser ''FIFA'' o ''Confederacion''.';

    IF @fechaInternacional IS NOT NULL AND @fechaInternacional > CAST(GETDATE() AS date)
        SET @errores += CHAR(10) + N'- La fecha de obtención de categoría internacional no puede ser futura.';

    -- Unicidad contra otros árbitros
    IF @idArbitro IS NOT NULL AND @idPais IS NOT NULL AND @nombre IS NOT NULL AND @apellido IS NOT NULL
       AND EXISTS (
           SELECT 1
           FROM Arbitraje.Arbitro
           WHERE idArbitro <> @idArbitro
             AND idPais = @idPais
             AND UPPER(LTRIM(RTRIM(nombre))) = UPPER(LTRIM(RTRIM(@nombre)))
             AND UPPER(LTRIM(RTRIM(apellido))) = UPPER(LTRIM(RTRIM(@apellido)))
       )
        SET @errores += CHAR(10) + N'- Ya existe otro árbitro registrado con el mismo nombre y apellido para dicho país.';

    -- Validación de conflicto si se cambia el país de un árbitro con designaciones existentes
    IF @idArbitro IS NOT NULL AND @idPais IS NOT NULL
       AND EXISTS (
           SELECT 1
           FROM Arbitraje.cuerpoArbitral ca
           JOIN Torneo.Partido p ON ca.idPartido = p.idPartido
           JOIN Equipos.Seleccion sl ON p.idSeleccionLocal = sl.id
           JOIN Equipos.Seleccion sv ON p.idSeleccionVisitante = sv.id
           WHERE ca.idArbitro = @idArbitro
             AND @idPais IN (sl.idPais, sv.idPais)
       )
        SET @errores += CHAR(10) + N'- No se puede modificar el país del árbitro al indicado porque generaría un conflicto de nacionalidad en partidos donde ya se encuentra designado.';

    -- THROW único
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo modificar el árbitro:' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- Actualización
    UPDATE Arbitraje.Arbitro
    SET idPais             = @idPais,
        nombre             = LTRIM(RTRIM(@nombre)),
        apellido           = LTRIM(RTRIM(@apellido)),
        categoria          = @categoria,
        genero             = @genero,
        fechaInternacional = @fechaInternacional
    WHERE idArbitro = @idArbitro;
END
GO

-- 1.3 BAJA DE ÁRBITRO
CREATE OR ALTER PROCEDURE Arbitraje.Arbitro_Baja
    @idArbitro int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    -- Existencia del registro a eliminar
    IF @idArbitro IS NULL OR NOT EXISTS (SELECT 1 FROM Arbitraje.Arbitro WHERE idArbitro = @idArbitro)
        SET @errores += CHAR(10) + N'- El árbitro a eliminar no existe.';

    -- Integridad referencial con designaciones
    IF EXISTS (SELECT 1 FROM Arbitraje.cuerpoArbitral WHERE idArbitro = @idArbitro)
        SET @errores += CHAR(10) + N'- No se puede eliminar el árbitro porque posee designaciones en partidos.';

    -- Integridad referencial con informes arbitrales
    IF EXISTS (SELECT 1 FROM Arbitraje.InformeArbitral WHERE idArbitro = @idArbitro)
        SET @errores += CHAR(10) + N'- No se puede eliminar el árbitro porque posee informes arbitrales registrados.';

    -- THROW único
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de baja el árbitro:' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- Eliminación en cascada manual de idiomas y árbitro bajo control transaccional
    BEGIN TRY
        BEGIN TRANSACTION;
            DELETE FROM Arbitraje.ArbitroIdioma WHERE idArbitro = @idArbitro;
            DELETE FROM Arbitraje.Arbitro WHERE idArbitro = @idArbitro;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END
GO

/* =============================================================================
   2. TABLA: Arbitraje.ArbitroIdioma
   ============================================================================= */

-- 2.1 ALTA DE IDIOMA DE ÁRBITRO
CREATE OR ALTER PROCEDURE Arbitraje.ArbitroIdioma_Alta
    @idArbitro int,
    @idioma    varchar(10)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @idioma = LOWER(LTRIM(RTRIM(@idioma)));

    -- Existencia de árbitro
    IF @idArbitro IS NULL OR NOT EXISTS (SELECT 1 FROM Arbitraje.Arbitro WHERE idArbitro = @idArbitro)
        SET @errores += CHAR(10) + N'- El árbitro especificado no existe.';

    -- Validación formato ISO 639-1 (exactamente dos letras minúsculas)
    IF @idioma IS NULL OR LEN(@idioma) <> 2 OR @idioma NOT LIKE '[a-z][a-z]'
        SET @errores += CHAR(10) + N'- El código de idioma debe componerse exactamente de dos letras minúsculas (formato ISO 639-1).';

    -- Validación de unicidad
    IF @idArbitro IS NOT NULL AND @idioma IS NOT NULL AND LEN(@idioma) = 2
       AND EXISTS (SELECT 1 FROM Arbitraje.ArbitroIdioma WHERE idArbitro = @idArbitro AND idioma = @idioma)
        SET @errores += CHAR(10) + N'- El idioma ya se encuentra registrado para este árbitro.';

    -- THROW único
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo registrar el idioma del árbitro:' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- Inserción
    INSERT INTO Arbitraje.ArbitroIdioma (idArbitro, idioma)
    VALUES (@idArbitro, CAST(@idioma AS char(2)));
END
GO

-- 2.2 MODIFICACIÓN DE IDIOMA DE ÁRBITRO
CREATE OR ALTER PROCEDURE Arbitraje.ArbitroIdioma_Modificacion
    @idArbitro     int,
    @idiomaActual  varchar(10),
    @idiomaNuevo   varchar(10)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @idiomaActual = LOWER(LTRIM(RTRIM(@idiomaActual)));
    SET @idiomaNuevo  = LOWER(LTRIM(RTRIM(@idiomaNuevo)));

    IF @idArbitro IS NULL OR NOT EXISTS (SELECT 1 FROM Arbitraje.Arbitro WHERE idArbitro = @idArbitro)
        SET @errores += CHAR(10) + N'- El árbitro especificado no existe.';

    IF @idiomaActual IS NULL OR NOT EXISTS (SELECT 1 FROM Arbitraje.ArbitroIdioma WHERE idArbitro = @idArbitro AND idioma = @idiomaActual)
        SET @errores += CHAR(10) + N'- El árbitro no posee registrado el idioma actual indicado.';

    IF @idiomaNuevo IS NULL OR LEN(@idiomaNuevo) <> 2 OR @idiomaNuevo NOT LIKE '[a-z][a-z]'
        SET @errores += CHAR(10) + N'- El nuevo código de idioma debe componerse exactamente de dos letras minúsculas (formato ISO 639-1).';

    IF @idiomaActual IS NOT NULL AND @idiomaNuevo IS NOT NULL AND @idiomaActual = @idiomaNuevo
        SET @errores += CHAR(10) + N'- El nuevo idioma no puede ser idéntico al idioma actual.';

    IF @idArbitro IS NOT NULL AND @idiomaNuevo IS NOT NULL AND LEN(@idiomaNuevo) = 2 AND @idiomaActual <> @idiomaNuevo
       AND EXISTS (SELECT 1 FROM Arbitraje.ArbitroIdioma WHERE idArbitro = @idArbitro AND idioma = @idiomaNuevo)
        SET @errores += CHAR(10) + N'- El nuevo idioma ya se encuentra registrado para este árbitro.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo modificar el idioma del árbitro:' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Arbitraje.ArbitroIdioma
    SET idioma = CAST(@idiomaNuevo AS char(2))
    WHERE idArbitro = @idArbitro AND idioma = @idiomaActual;
END
GO

-- 2.3 BAJA DE IDIOMA DE ÁRBITRO
CREATE OR ALTER PROCEDURE Arbitraje.ArbitroIdioma_Baja
    @idArbitro int,
    @idioma    varchar(10)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @idioma = LOWER(LTRIM(RTRIM(@idioma)));

    IF @idArbitro IS NULL OR NOT EXISTS (SELECT 1 FROM Arbitraje.Arbitro WHERE idArbitro = @idArbitro)
        SET @errores += CHAR(10) + N'- El árbitro especificado no existe.';
    ELSE IF NOT EXISTS (SELECT 1 FROM Arbitraje.ArbitroIdioma WHERE idArbitro = @idArbitro AND idioma = @idioma)
        SET @errores += CHAR(10) + N'- El árbitro no posee registrado el idioma indicado.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de baja el idioma del árbitro:' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Arbitraje.ArbitroIdioma
    WHERE idArbitro = @idArbitro AND idioma = @idioma;
END
GO

/* =============================================================================
   3. TABLA: Arbitraje.cuerpoArbitral
   ============================================================================= */

-- 3.1 ALTA DE DESIGNACIÓN ARBITRAL
CREATE OR ALTER PROCEDURE Arbitraje.cuerpoArbitral_Alta
    @idPartido  int,
    @idArbitro  int,
    @rol        varchar(15),
    @id         int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    -- Existencia del partido
    IF @idPartido IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido)
        SET @errores += CHAR(10) + N'- El partido especificado no existe.';

    -- Existencia y estado del árbitro
    IF @idArbitro IS NULL OR NOT EXISTS (SELECT 1 FROM Arbitraje.Arbitro WHERE idArbitro = @idArbitro)
        SET @errores += CHAR(10) + N'- El árbitro especificado no existe.';

    -- Validación del rol
    IF @rol IS NULL OR @rol NOT IN ('Principal', 'Asistente 1', 'Asistente 2', 'Cuarto Arbitro', 'VAR')
        SET @errores += CHAR(10) + N'- El rol arbitral debe ser Principal, Asistente 1, Asistente 2, Cuarto Arbitro o VAR.';

    -- Estado del partido (no permitir si ya finalizó o está en juego)
    IF EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido AND estado IN ('Finalizado', 'En juego'))
        SET @errores += CHAR(10) + N'- No se pueden asignar árbitros a un partido ya finalizado o que se encuentra en juego.';

    -- Un árbitro por rol en el partido
    IF @idPartido IS NOT NULL AND @rol IS NOT NULL
       AND EXISTS (SELECT 1 FROM Arbitraje.cuerpoArbitral WHERE idPartido = @idPartido AND rol = @rol)
        SET @errores += CHAR(10) + N'- El rol ya se encuentra cubierto por otro árbitro en este partido.';

    -- Un rol por árbitro en el partido
    IF @idPartido IS NOT NULL AND @idArbitro IS NOT NULL
       AND EXISTS (SELECT 1 FROM Arbitraje.cuerpoArbitral WHERE idPartido = @idPartido AND idArbitro = @idArbitro)
        SET @errores += CHAR(10) + N'- El árbitro ya posee otro rol asignado en este mismo partido.';

    -- Regla de negocio: Conflicto de nacionalidad con selecciones que disputan el encuentro
    IF @idPartido IS NOT NULL AND @idArbitro IS NOT NULL
       AND EXISTS (
           SELECT 1
           FROM Arbitraje.Arbitro a
           JOIN Torneo.Partido p ON p.idPartido = @idPartido
           JOIN Equipos.Seleccion sl ON p.idSeleccionLocal = sl.id
           JOIN Equipos.Seleccion sv ON p.idSeleccionVisitante = sv.id
           WHERE a.idArbitro = @idArbitro
             AND (a.idPais = sl.idPais OR a.idPais = sv.idPais)
       )
        SET @errores += CHAR(10) + N'- Conflicto de nacionalidad: el árbitro es de la misma nacionalidad que una de las selecciones del partido.';

    -- THROW único
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo designar el árbitro en el partido:' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- Inserción
    INSERT INTO Arbitraje.cuerpoArbitral (idPartido, idArbitro, rol)
    VALUES (@idPartido, @idArbitro, @rol);

    SET @id = SCOPE_IDENTITY();
END
GO

-- 3.2 MODIFICACIÓN DE DESIGNACIÓN ARBITRAL
CREATE OR ALTER PROCEDURE Arbitraje.cuerpoArbitral_Modificacion
    @id         int,
    @idPartido  int,
    @idArbitro  int,
    @rol        varchar(15)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    -- Existencia del registro a modificar
    IF @id IS NULL OR NOT EXISTS (SELECT 1 FROM Arbitraje.cuerpoArbitral WHERE id = @id)
        SET @errores += CHAR(10) + N'- La designación arbitral a modificar no existe.';

    -- Existencia del partido y árbitro
    IF @idPartido IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido)
        SET @errores += CHAR(10) + N'- El partido especificado no existe.';

    IF @idArbitro IS NULL OR NOT EXISTS (SELECT 1 FROM Arbitraje.Arbitro WHERE idArbitro = @idArbitro)
        SET @errores += CHAR(10) + N'- El árbitro especificado no existe.';

    -- Rol válido
    IF @rol IS NULL OR @rol NOT IN ('Principal', 'Asistente 1', 'Asistente 2', 'Cuarto Arbitro', 'VAR')
        SET @errores += CHAR(10) + N'- El rol arbitral debe ser Principal, Asistente 1, Asistente 2, Cuarto Arbitro o VAR.';

    -- No permitir modificar designaciones de un partido ya finalizado o en juego (tanto el original como el nuevo)
    IF EXISTS (
        SELECT 1
        FROM Arbitraje.cuerpoArbitral ca
        JOIN Torneo.Partido pOriginal ON ca.idPartido = pOriginal.idPartido
        WHERE ca.id = @id AND pOriginal.estado IN ('Finalizado', 'En juego')
    )
        SET @errores += CHAR(10) + N'- No se pueden modificar designaciones de un partido ya finalizado o en juego.';
    ELSE IF EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido AND estado IN ('Finalizado', 'En juego'))
        SET @errores += CHAR(10) + N'- No se puede trasladar la designación a un partido ya finalizado o en juego.';

    -- No permitir modificar árbitro o partido si ya posee informes arbitrales registrados
    IF EXISTS (
        SELECT 1
        FROM Arbitraje.cuerpoArbitral ca
        JOIN Arbitraje.InformeArbitral ia ON ca.idPartido = ia.idPartido AND ca.idArbitro = ia.idArbitro
        WHERE ca.id = @id AND (ca.idArbitro <> @idArbitro OR ca.idPartido <> @idPartido)
    )
        SET @errores += CHAR(10) + N'- No se puede modificar el árbitro o partido de la designación porque ya posee informes arbitrales registrados.';

    -- Unicidad de rol en el partido (excluyendo el registro actual)
    IF @id IS NOT NULL AND @idPartido IS NOT NULL AND @rol IS NOT NULL
       AND EXISTS (SELECT 1 FROM Arbitraje.cuerpoArbitral WHERE idPartido = @idPartido AND rol = @rol AND id <> @id)
        SET @errores += CHAR(10) + N'- El rol ya se encuentra cubierto por otro árbitro en este partido.';

    -- Unicidad de árbitro en el partido (excluyendo el registro actual)
    IF @id IS NOT NULL AND @idPartido IS NOT NULL AND @idArbitro IS NOT NULL
       AND EXISTS (SELECT 1 FROM Arbitraje.cuerpoArbitral WHERE idPartido = @idPartido AND idArbitro = @idArbitro AND id <> @id)
        SET @errores += CHAR(10) + N'- El árbitro ya posee otro rol asignado en este mismo partido.';

    -- Conflicto de nacionalidad
    IF @idPartido IS NOT NULL AND @idArbitro IS NOT NULL
       AND EXISTS (
           SELECT 1
           FROM Arbitraje.Arbitro a
           JOIN Torneo.Partido p ON p.idPartido = @idPartido
           JOIN Equipos.Seleccion sl ON p.idSeleccionLocal = sl.id
           JOIN Equipos.Seleccion sv ON p.idSeleccionVisitante = sv.id
           WHERE a.idArbitro = @idArbitro
             AND (a.idPais = sl.idPais OR a.idPais = sv.idPais)
       )
        SET @errores += CHAR(10) + N'- Conflicto de nacionalidad: el árbitro es de la misma nacionalidad que una de las selecciones del partido.';

    -- THROW único
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo modificar la designación arbitral:' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- Actualización
    UPDATE Arbitraje.cuerpoArbitral
    SET idPartido = @idPartido,
        idArbitro = @idArbitro,
        rol       = @rol
    WHERE id = @id;
END
GO

-- 3.3 BAJA DE DESIGNACIÓN ARBITRAL
CREATE OR ALTER PROCEDURE Arbitraje.cuerpoArbitral_Baja
    @id int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    -- Existencia de la designación
    IF @id IS NULL OR NOT EXISTS (SELECT 1 FROM Arbitraje.cuerpoArbitral WHERE id = @id)
        SET @errores += CHAR(10) + N'- La designación arbitral a eliminar no existe.';

    -- No eliminar si el partido ya finalizó o está en juego
    IF EXISTS (
        SELECT 1
        FROM Arbitraje.cuerpoArbitral ca
        JOIN Torneo.Partido p ON ca.idPartido = p.idPartido
        WHERE ca.id = @id AND p.estado IN ('Finalizado', 'En juego')
    )
        SET @errores += CHAR(10) + N'- No se puede eliminar la designación arbitral de un partido ya finalizado o en juego.';

    -- No eliminar si el árbitro emitió informes sobre ese partido
    IF EXISTS (
        SELECT 1
        FROM Arbitraje.cuerpoArbitral ca
        JOIN Arbitraje.InformeArbitral ia ON ca.idPartido = ia.idPartido AND ca.idArbitro = ia.idArbitro
        WHERE ca.id = @id
    )
        SET @errores += CHAR(10) + N'- No se puede eliminar la designación porque el árbitro posee informes arbitrales registrados para este partido.';

    -- THROW único
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de baja la designación arbitral:' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Arbitraje.cuerpoArbitral
    WHERE id = @id;
END
GO

/* =============================================================================
   4. TABLA: Arbitraje.InformeArbitral
   ============================================================================= */

-- 4.1 ALTA DE INFORME ARBITRAL
CREATE OR ALTER PROCEDURE Arbitraje.InformeArbitral_Alta
    @idPartido  int,
    @idArbitro  int,
    @fecha      date,
    @esSancion  bit,
    @detalle    nvarchar(500) = NULL,
    @id         int           = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    -- Existencia del partido y árbitro
    IF @idPartido IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido)
        SET @errores += CHAR(10) + N'- El partido especificado no existe.';

    IF @idArbitro IS NULL OR NOT EXISTS (SELECT 1 FROM Arbitraje.Arbitro WHERE idArbitro = @idArbitro)
        SET @errores += CHAR(10) + N'- El árbitro especificado no existe.';

    -- El árbitro debe haber formado parte del cuerpo arbitral del partido
    IF @idPartido IS NOT NULL AND @idArbitro IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM Arbitraje.cuerpoArbitral WHERE idPartido = @idPartido AND idArbitro = @idArbitro)
        SET @errores += CHAR(10) + N'- El árbitro no formó parte del cuerpo arbitral designado para este partido.';

    -- El partido no puede estar en estado 'Programado' para recibir informes post-partido
    IF EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido AND estado = 'Programado')
        SET @errores += CHAR(10) + N'- No se pueden registrar informes post-partido para un encuentro que todavía se encuentra programado.';

    -- Fecha obligatoria y no anterior a la disputa del partido
    IF @fecha IS NULL
        SET @errores += CHAR(10) + N'- La fecha del informe es obligatoria.';
    ELSE IF @idPartido IS NOT NULL AND @fecha < CAST((SELECT fechaHoraUTC FROM Torneo.Partido WHERE idPartido = @idPartido) AS date)
        SET @errores += CHAR(10) + N'- La fecha del informe no puede ser anterior a la fecha de disputa del partido.';

    -- Validación de bandera esSancion
    IF @esSancion IS NULL
        SET @errores += CHAR(10) + N'- Debe indicar si el informe corresponde a una sanción (1) o informe general (0).';

    -- Si es sanción, el detalle es obligatorio
    IF @esSancion = 1 AND (LTRIM(RTRIM(ISNULL(@detalle, N''))) = N'')
        SET @errores += CHAR(10) + N'- Las sanciones arbitrales requieren consignar el detalle de la sanción.';

    -- THROW único
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo registrar el informe arbitral:' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- Inserción
    INSERT INTO Arbitraje.InformeArbitral (idPartido, idArbitro, fecha, esSancion, detalle)
    VALUES (@idPartido, @idArbitro, @fecha, @esSancion, NULLIF(LTRIM(RTRIM(@detalle)), N''));

    SET @id = SCOPE_IDENTITY();
END
GO

-- 4.2 MODIFICACIÓN DE INFORME ARBITRAL
CREATE OR ALTER PROCEDURE Arbitraje.InformeArbitral_Modificacion
    @id         int,
    @idPartido  int,
    @idArbitro  int,
    @fecha      date,
    @esSancion  bit,
    @detalle    nvarchar(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    -- Existencia del informe
    IF @id IS NULL OR NOT EXISTS (SELECT 1 FROM Arbitraje.InformeArbitral WHERE id = @id)
        SET @errores += CHAR(10) + N'- El informe arbitral a modificar no existe.';

    -- Existencia del partido y árbitro
    IF @idPartido IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido)
        SET @errores += CHAR(10) + N'- El partido especificado no existe.';

    IF @idArbitro IS NULL OR NOT EXISTS (SELECT 1 FROM Arbitraje.Arbitro WHERE idArbitro = @idArbitro)
        SET @errores += CHAR(10) + N'- El árbitro especificado no existe.';

    -- Pertenencia al cuerpo arbitral
    IF @idPartido IS NOT NULL AND @idArbitro IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM Arbitraje.cuerpoArbitral WHERE idPartido = @idPartido AND idArbitro = @idArbitro)
        SET @errores += CHAR(10) + N'- El árbitro no formó parte del cuerpo arbitral designado para este partido.';

    -- Estado del encuentro
    IF EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido AND estado = 'Programado')
        SET @errores += CHAR(10) + N'- No se pueden registrar informes post-partido para un encuentro que todavía se encuentra programado.';

    -- Validación de fecha
    IF @fecha IS NULL
        SET @errores += CHAR(10) + N'- La fecha del informe es obligatoria.';
    ELSE IF @idPartido IS NOT NULL AND @fecha < CAST((SELECT fechaHoraUTC FROM Torneo.Partido WHERE idPartido = @idPartido) AS date)
        SET @errores += CHAR(10) + N'- La fecha del informe no puede ser anterior a la fecha de disputa del partido.';

    IF @esSancion IS NULL
        SET @errores += CHAR(10) + N'- Debe indicar si el informe corresponde a una sanción (1) o informe general (0).';

    IF @esSancion = 1 AND (LTRIM(RTRIM(ISNULL(@detalle, N''))) = N'')
        SET @errores += CHAR(10) + N'- Las sanciones arbitrales requieren consignar el detalle de la sanción.';

    -- THROW único
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo modificar el informe arbitral:' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- Actualización
    UPDATE Arbitraje.InformeArbitral
    SET idPartido = @idPartido,
        idArbitro = @idArbitro,
        fecha     = @fecha,
        esSancion = @esSancion,
        detalle   = NULLIF(LTRIM(RTRIM(@detalle)), N'')
    WHERE id = @id;
END
GO

-- 4.3 BAJA DE INFORME ARBITRAL
CREATE OR ALTER PROCEDURE Arbitraje.InformeArbitral_Baja
    @id int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    IF @id IS NULL OR NOT EXISTS (SELECT 1 FROM Arbitraje.InformeArbitral WHERE id = @id)
        SET @errores += CHAR(10) + N'- El informe arbitral a eliminar no existe.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo eliminar el informe arbitral:' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Arbitraje.InformeArbitral
    WHERE id = @id;
END
GO
