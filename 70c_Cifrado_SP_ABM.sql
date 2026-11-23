/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 23/11/2026

 Objetivo    : Entrega 8 (cifrado) - SP de alta y modificación que escriben datos
               personales, ahora cifrándolos:
               - Equipos.Jugador_Alta / Equipos.Jugador_Modificacion   (script 10b)
               - Equipos.Staff_Alta / Equipos.Staff_Modificacion       (script 10b)
               - Arbitraje.Arbitro_Alta / Arbitraje.Arbitro_Modificacion (script 11a)
               - Arbitraje.Arbitro_Buscar (nuevo): busca un árbitro por país,
                 nombre y apellido sin descifrar nada, para el importador XML.
               Se redefinen con CREATE OR ALTER: los scripts 10b y 11a no se modifican.
               Las bajas no leen columnas cifradas y no cambian.

 Qué se mantiene igual que en los originales:
 - La firma de cada SP (mismos parámetros, mismos nombres y mismos valores por
   defecto), así que los GRANT EXECUTE y las llamadas existentes siguen valiendo.
 - Todas las validaciones y sus mensajes, con el patrón de la entrega 5: acumulan
   los errores y cortan con un único THROW 50001.

 Qué cambia:
 - Se declaran WITH EXECUTE AS OWNER: los permisos sobre certificados y claves no
   se heredan por encadenamiento de propiedad, y esta es la forma de que ningún rol
   necesite permisos sobre CertDatosPersonales ni ClaveDatosPersonales.
 - Cifran con EncryptByKey y guardan en las columnas con sufijo Cif (70b).
 - La regla de "no repetir nombre + apellido + fecha de nacimiento" (jugador) y la
   de "mismo país + nombre + apellido" (árbitro) comparan por huella (columna
   huella, Seguridad.fn_Huella) porque no se pueden comparar textos cifrados.
 - La clave se abre y se cierra dentro del propio SP, también si algo falla.
   Solo se cierra si la abrió este SP (Seguridad.AbrirClave / CerrarClave), para no
   dejar sin clave a un SP que lo llamó. Sin autenticador (add_authenticator): la
   amenaza de copiar un valor cifrado de una fila a otra con permiso de escritura
   queda fuera del alcance del trabajo.
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

/* =============================================================================
   1. TABLA: Equipos.Jugador
   ============================================================================= */

-- 1.1 ALTA DE JUGADOR
CREATE OR ALTER PROCEDURE Equipos.Jugador_Alta
    @nombre           nvarchar(60),
    @apellido         nvarchar(60),
    @fechaNacimiento  date         = NULL,
    @altura           decimal(5,2) = NULL,
    @peso             decimal(5,2) = NULL,
    @piernaHabil      varchar(15)  = NULL,
    @club             nvarchar(80) = NULL,
    @posicion         varchar(15)  = NULL,
    @id               int          = NULL OUTPUT
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    DECLARE @abrio bit = 0, @pimienta nvarchar(100), @huella varbinary(32);
    SET @nombre      = LTRIM(RTRIM(@nombre));
    SET @apellido    = LTRIM(RTRIM(@apellido));
    SET @piernaHabil = NULLIF(LTRIM(RTRIM(@piernaHabil)), '');
    SET @club        = NULLIF(LTRIM(RTRIM(@club)), N'');
    SET @posicion    = NULLIF(LTRIM(RTRIM(@posicion)), '');

    -- Huella para la regla de duplicados (la pimienta está cifrada: hay que abrir la clave)
    BEGIN TRY
        EXEC Seguridad.AbrirClave @abrio = @abrio OUTPUT;
        EXEC Seguridad.ObtenerPimienta @pimienta = @pimienta OUTPUT;
        SET @huella = CASE WHEN @fechaNacimiento IS NULL THEN NULL
                           ELSE Seguridad.fn_Huella(@pimienta, @nombre, @apellido, @fechaNacimiento) END;
        EXEC Seguridad.CerrarClave @abrio = @abrio;
    END TRY
    BEGIN CATCH
        EXEC Seguridad.CerrarClave @abrio = @abrio;
        THROW;
    END CATCH;

    IF @nombre IS NULL OR @nombre = N''
        SET @errores += CHAR(10) + N'- El nombre del jugador es obligatorio.';

    IF @apellido IS NULL OR @apellido = N''
        SET @errores += CHAR(10) + N'- El apellido del jugador es obligatorio.';

    IF @fechaNacimiento > DATEADD(YEAR, -15, CAST(GETDATE() AS date))
        SET @errores += CHAR(10) + N'- El jugador debe tener al menos 15 años.';

    IF @altura NOT BETWEEN 1.40 AND 2.20
        SET @errores += CHAR(10) + N'- La altura debe estar entre 1,40 y 2,20 metros.';

    IF @peso NOT BETWEEN 40 AND 130
        SET @errores += CHAR(10) + N'- El peso debe estar entre 40 y 130 kg.';

    IF @piernaHabil NOT IN ('Izquierda', 'Derecha', 'Ambidiestro')
        SET @errores += CHAR(10) + N'- La pierna hábil debe ser Izquierda, Derecha o Ambidiestro.';

    IF @posicion NOT IN ('Arquero', 'Defensor', 'Mediocampista', 'Delantero')
        SET @errores += CHAR(10) + N'- La posición debe ser Arquero, Defensor, Mediocampista o Delantero.';

    IF @fechaNacimiento IS NOT NULL AND @nombre <> N'' AND @apellido <> N''
       AND EXISTS (SELECT 1 FROM Equipos.Jugador WHERE huella = @huella)
        SET @errores += CHAR(10) + N'- Ya existe un jugador con el mismo nombre, apellido y fecha de nacimiento.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de alta el jugador:' + @errores;
        THROW 50001, @errores, 1;
    END;

    BEGIN TRY
        EXEC Seguridad.AbrirClave @abrio = @abrio OUTPUT;

        INSERT INTO Equipos.Jugador (nombreCif, apellidoCif, fechaNacimientoCif, alturaCif, pesoCif,
                                     huella, piernaHabil, club, posicion)
        VALUES (EncryptByKey(Key_GUID(N'ClaveDatosPersonales'), @nombre),
                EncryptByKey(Key_GUID(N'ClaveDatosPersonales'), @apellido),
                EncryptByKey(Key_GUID(N'ClaveDatosPersonales'), CONVERT(varchar(10), @fechaNacimiento, 23)),
                EncryptByKey(Key_GUID(N'ClaveDatosPersonales'), CONVERT(varchar(10), @altura)),
                EncryptByKey(Key_GUID(N'ClaveDatosPersonales'), CONVERT(varchar(10), @peso)),
                @huella, @piernaHabil, @club, @posicion);

        SET @id = SCOPE_IDENTITY();
        EXEC Seguridad.CerrarClave @abrio = @abrio;
    END TRY
    BEGIN CATCH
        EXEC Seguridad.CerrarClave @abrio = @abrio;
        THROW;
    END CATCH;
END
GO

-- 1.2 MODIFICACIÓN DE JUGADOR
CREATE OR ALTER PROCEDURE Equipos.Jugador_Modificacion
    @id               int,
    @nombre           nvarchar(60),
    @apellido         nvarchar(60),
    @fechaNacimiento  date         = NULL,
    @altura           decimal(5,2) = NULL,
    @peso             decimal(5,2) = NULL,
    @piernaHabil      varchar(15)  = NULL,
    @club             nvarchar(80) = NULL,
    @posicion         varchar(15)  = NULL
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    DECLARE @abrio bit = 0, @pimienta nvarchar(100), @huella varbinary(32);
    SET @nombre      = LTRIM(RTRIM(@nombre));
    SET @apellido    = LTRIM(RTRIM(@apellido));
    SET @piernaHabil = NULLIF(LTRIM(RTRIM(@piernaHabil)), '');
    SET @club        = NULLIF(LTRIM(RTRIM(@club)), N'');
    SET @posicion    = NULLIF(LTRIM(RTRIM(@posicion)), '');

    -- Huella para la regla de duplicados (la pimienta está cifrada: hay que abrir la clave)
    BEGIN TRY
        EXEC Seguridad.AbrirClave @abrio = @abrio OUTPUT;
        EXEC Seguridad.ObtenerPimienta @pimienta = @pimienta OUTPUT;
        SET @huella = CASE WHEN @fechaNacimiento IS NULL THEN NULL
                           ELSE Seguridad.fn_Huella(@pimienta, @nombre, @apellido, @fechaNacimiento) END;
        EXEC Seguridad.CerrarClave @abrio = @abrio;
    END TRY
    BEGIN CATCH
        EXEC Seguridad.CerrarClave @abrio = @abrio;
        THROW;
    END CATCH;

    IF @id IS NULL OR NOT EXISTS (SELECT 1 FROM Equipos.Jugador WHERE id = @id)
        SET @errores += CHAR(10) + N'- El jugador a modificar no existe.';

    IF @nombre IS NULL OR @nombre = N''
        SET @errores += CHAR(10) + N'- El nombre del jugador es obligatorio.';

    IF @apellido IS NULL OR @apellido = N''
        SET @errores += CHAR(10) + N'- El apellido del jugador es obligatorio.';

    IF @fechaNacimiento > DATEADD(YEAR, -15, CAST(GETDATE() AS date))
        SET @errores += CHAR(10) + N'- El jugador debe tener al menos 15 años.';

    IF @altura NOT BETWEEN 1.40 AND 2.20
        SET @errores += CHAR(10) + N'- La altura debe estar entre 1,40 y 2,20 metros.';

    IF @peso NOT BETWEEN 40 AND 130
        SET @errores += CHAR(10) + N'- El peso debe estar entre 40 y 130 kg.';

    IF @piernaHabil NOT IN ('Izquierda', 'Derecha', 'Ambidiestro')
        SET @errores += CHAR(10) + N'- La pierna hábil debe ser Izquierda, Derecha o Ambidiestro.';

    IF @posicion NOT IN ('Arquero', 'Defensor', 'Mediocampista', 'Delantero')
        SET @errores += CHAR(10) + N'- La posición debe ser Arquero, Defensor, Mediocampista o Delantero.';

    IF @fechaNacimiento IS NOT NULL AND @nombre <> N'' AND @apellido <> N''
       AND EXISTS (SELECT 1 FROM Equipos.Jugador WHERE huella = @huella AND id <> @id)
        SET @errores += CHAR(10) + N'- Ya existe otro jugador con el mismo nombre, apellido y fecha de nacimiento.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo modificar el jugador:' + @errores;
        THROW 50001, @errores, 1;
    END;

    BEGIN TRY
        EXEC Seguridad.AbrirClave @abrio = @abrio OUTPUT;

        UPDATE Equipos.Jugador
        SET nombreCif          = EncryptByKey(Key_GUID(N'ClaveDatosPersonales'), @nombre),
            apellidoCif        = EncryptByKey(Key_GUID(N'ClaveDatosPersonales'), @apellido),
            fechaNacimientoCif = EncryptByKey(Key_GUID(N'ClaveDatosPersonales'), CONVERT(varchar(10), @fechaNacimiento, 23)),
            alturaCif          = EncryptByKey(Key_GUID(N'ClaveDatosPersonales'), CONVERT(varchar(10), @altura)),
            pesoCif            = EncryptByKey(Key_GUID(N'ClaveDatosPersonales'), CONVERT(varchar(10), @peso)),
            huella             = @huella,
            piernaHabil        = @piernaHabil,
            club               = @club,
            posicion           = @posicion
        WHERE id = @id;

        EXEC Seguridad.CerrarClave @abrio = @abrio;
    END TRY
    BEGIN CATCH
        EXEC Seguridad.CerrarClave @abrio = @abrio;
        THROW;
    END CATCH;
END
GO

/* =============================================================================
   2. TABLA: Equipos.Staff
   No tiene regla de duplicados por valor: no lleva huella.
   ============================================================================= */

-- 2.1 ALTA DE INTEGRANTE DEL CUERPO TÉCNICO
CREATE OR ALTER PROCEDURE Equipos.Staff_Alta
    @idSeleccion      int,
    @nombre           nvarchar(60),
    @apellido         nvarchar(60),
    @rol              varchar(20),
    @fechaNacimiento  date = NULL,
    @id               int  = NULL OUTPUT
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    DECLARE @abrio bit = 0;
    SET @nombre   = LTRIM(RTRIM(@nombre));
    SET @apellido = LTRIM(RTRIM(@apellido));
    SET @rol      = LTRIM(RTRIM(@rol));

    IF @idSeleccion IS NULL OR NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE id = @idSeleccion)
        SET @errores += CHAR(10) + N'- La selección no existe.';

    IF @nombre IS NULL OR @nombre = N''
        SET @errores += CHAR(10) + N'- El nombre es obligatorio.';

    IF @apellido IS NULL OR @apellido = N''
        SET @errores += CHAR(10) + N'- El apellido es obligatorio.';

    IF @rol IS NULL OR @rol NOT IN ('Director Principal', 'Ayudante', 'Preparador Fisico', 'Medico')
        SET @errores += CHAR(10) + N'- El rol debe ser Director Principal, Ayudante, Preparador Fisico o Medico.';
    ELSE IF @rol = 'Director Principal'
            AND EXISTS (SELECT 1 FROM Equipos.Staff WHERE idSeleccion = @idSeleccion AND rol = 'Director Principal')
        SET @errores += CHAR(10) + N'- La selección ya tiene un director principal.';

    IF @fechaNacimiento > CAST(GETDATE() AS date)
        SET @errores += CHAR(10) + N'- La fecha de nacimiento no puede ser futura.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de alta el integrante del cuerpo técnico:' + @errores;
        THROW 50001, @errores, 1;
    END;

    BEGIN TRY
        EXEC Seguridad.AbrirClave @abrio = @abrio OUTPUT;

        INSERT INTO Equipos.Staff (idSeleccion, nombreCif, apellidoCif, fechaNacimientoCif, rol)
        VALUES (@idSeleccion,
                EncryptByKey(Key_GUID(N'ClaveDatosPersonales'), @nombre),
                EncryptByKey(Key_GUID(N'ClaveDatosPersonales'), @apellido),
                EncryptByKey(Key_GUID(N'ClaveDatosPersonales'), CONVERT(varchar(10), @fechaNacimiento, 23)),
                @rol);

        SET @id = SCOPE_IDENTITY();
        EXEC Seguridad.CerrarClave @abrio = @abrio;
    END TRY
    BEGIN CATCH
        EXEC Seguridad.CerrarClave @abrio = @abrio;
        THROW;
    END CATCH;
END
GO

-- 2.2 MODIFICACIÓN DE INTEGRANTE DEL CUERPO TÉCNICO
CREATE OR ALTER PROCEDURE Equipos.Staff_Modificacion
    @id               int,
    @idSeleccion      int,
    @nombre           nvarchar(60),
    @apellido         nvarchar(60),
    @rol              varchar(20),
    @fechaNacimiento  date = NULL
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    DECLARE @abrio bit = 0;
    SET @nombre   = LTRIM(RTRIM(@nombre));
    SET @apellido = LTRIM(RTRIM(@apellido));
    SET @rol      = LTRIM(RTRIM(@rol));

    IF @id IS NULL OR NOT EXISTS (SELECT 1 FROM Equipos.Staff WHERE id = @id)
        SET @errores += CHAR(10) + N'- El integrante del cuerpo técnico a modificar no existe.';

    IF @idSeleccion IS NULL OR NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE id = @idSeleccion)
        SET @errores += CHAR(10) + N'- La selección no existe.';

    IF @nombre IS NULL OR @nombre = N''
        SET @errores += CHAR(10) + N'- El nombre es obligatorio.';

    IF @apellido IS NULL OR @apellido = N''
        SET @errores += CHAR(10) + N'- El apellido es obligatorio.';

    IF @rol IS NULL OR @rol NOT IN ('Director Principal', 'Ayudante', 'Preparador Fisico', 'Medico')
        SET @errores += CHAR(10) + N'- El rol debe ser Director Principal, Ayudante, Preparador Fisico o Medico.';
    ELSE IF @rol = 'Director Principal'
            AND EXISTS (SELECT 1 FROM Equipos.Staff
                        WHERE idSeleccion = @idSeleccion AND rol = 'Director Principal' AND id <> @id)
        SET @errores += CHAR(10) + N'- La selección ya tiene otro director principal.';

    IF @fechaNacimiento > CAST(GETDATE() AS date)
        SET @errores += CHAR(10) + N'- La fecha de nacimiento no puede ser futura.';

    -- Las tarjetas y suspensiones del integrante se validaron contra su selección
    IF EXISTS (SELECT 1 FROM Equipos.Staff WHERE id = @id AND idSeleccion <> @idSeleccion)
       AND (EXISTS (SELECT 1 FROM Eventos.Tarjeta WHERE idStaff = @id)
            OR EXISTS (SELECT 1 FROM Eventos.Suspension WHERE idStaff = @id))
        SET @errores += CHAR(10) + N'- No se puede cambiar la selección porque el integrante tiene tarjetas o suspensiones.';

    -- El cuerpo técnico de cada partido se armó con la selección del integrante
    IF EXISTS (SELECT 1 FROM Equipos.Staff WHERE id = @id AND idSeleccion <> @idSeleccion)
       AND EXISTS (SELECT 1 FROM Eventos.CuerpoTecnicoPartido WHERE idStaff = @id)
        SET @errores += CHAR(10) + N'- No se puede cambiar la selección porque el integrante figura en el cuerpo técnico de algún partido.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo modificar el integrante del cuerpo técnico:' + @errores;
        THROW 50001, @errores, 1;
    END;

    BEGIN TRY
        EXEC Seguridad.AbrirClave @abrio = @abrio OUTPUT;

        UPDATE Equipos.Staff
        SET idSeleccion        = @idSeleccion,
            nombreCif          = EncryptByKey(Key_GUID(N'ClaveDatosPersonales'), @nombre),
            apellidoCif        = EncryptByKey(Key_GUID(N'ClaveDatosPersonales'), @apellido),
            fechaNacimientoCif = EncryptByKey(Key_GUID(N'ClaveDatosPersonales'), CONVERT(varchar(10), @fechaNacimiento, 23)),
            rol                = @rol
        WHERE id = @id;

        EXEC Seguridad.CerrarClave @abrio = @abrio;
    END TRY
    BEGIN CATCH
        EXEC Seguridad.CerrarClave @abrio = @abrio;
        THROW;
    END CATCH;
END
GO

/* =============================================================================
   3. TABLA: Arbitraje.Arbitro
   ============================================================================= */

-- 3.1 ALTA DE ÁRBITRO
CREATE OR ALTER PROCEDURE Arbitraje.Arbitro_Alta
    @idPais             int,
    @nombre             nvarchar(60),
    @apellido           nvarchar(60),
    @categoria          varchar(15),
    @genero             varchar(20) = NULL,
    @fechaInternacional date        = NULL,
    @idArbitro          int         = NULL OUTPUT
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    DECLARE @abrio bit = 0, @pimienta nvarchar(100), @huella varbinary(32);
    SET @genero = NULLIF(LTRIM(RTRIM(@genero)), '');

    -- Huella para la regla de duplicados (la pimienta está cifrada: hay que abrir la clave)
    BEGIN TRY
        EXEC Seguridad.AbrirClave @abrio = @abrio OUTPUT;
        EXEC Seguridad.ObtenerPimienta @pimienta = @pimienta OUTPUT;
        SET @huella = Seguridad.fn_Huella(@pimienta, @nombre, @apellido, NULL);
        EXEC Seguridad.CerrarClave @abrio = @abrio;
    END TRY
    BEGIN CATCH
        EXEC Seguridad.CerrarClave @abrio = @abrio;
        THROW;
    END CATCH;

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

    -- Validación de unicidad de negocio (mismo país, nombre y apellido), por huella
    IF @idPais IS NOT NULL AND @nombre IS NOT NULL AND @apellido IS NOT NULL
       AND EXISTS (
           SELECT 1
           FROM Arbitraje.Arbitro
           WHERE idPais = @idPais
             AND huella = @huella
       )
        SET @errores += CHAR(10) + N'- Ya existe un árbitro registrado con el mismo nombre y apellido para dicho país.';

    -- THROW único en caso de error
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de alta el árbitro:' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- Inserción
    BEGIN TRY
        EXEC Seguridad.AbrirClave @abrio = @abrio OUTPUT;

        INSERT INTO Arbitraje.Arbitro (idPais, nombreCif, apellidoCif, categoria, generoCif, huella, fechaInternacional)
        VALUES (@idPais,
                EncryptByKey(Key_GUID(N'ClaveDatosPersonales'), LTRIM(RTRIM(@nombre))),
                EncryptByKey(Key_GUID(N'ClaveDatosPersonales'), LTRIM(RTRIM(@apellido))),
                @categoria,
                EncryptByKey(Key_GUID(N'ClaveDatosPersonales'), @genero),
                @huella,
                @fechaInternacional);

        SET @idArbitro = SCOPE_IDENTITY();
        EXEC Seguridad.CerrarClave @abrio = @abrio;
    END TRY
    BEGIN CATCH
        EXEC Seguridad.CerrarClave @abrio = @abrio;
        THROW;
    END CATCH;
END
GO

-- 3.2 MODIFICACIÓN DE ÁRBITRO
CREATE OR ALTER PROCEDURE Arbitraje.Arbitro_Modificacion
    @idArbitro          int,
    @idPais             int,
    @nombre             nvarchar(60),
    @apellido           nvarchar(60),
    @categoria          varchar(15),
    @genero             varchar(20) = NULL,
    @fechaInternacional date        = NULL
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    DECLARE @abrio bit = 0, @pimienta nvarchar(100), @huella varbinary(32);
    SET @genero = NULLIF(LTRIM(RTRIM(@genero)), '');

    -- Huella para la regla de duplicados (la pimienta está cifrada: hay que abrir la clave)
    BEGIN TRY
        EXEC Seguridad.AbrirClave @abrio = @abrio OUTPUT;
        EXEC Seguridad.ObtenerPimienta @pimienta = @pimienta OUTPUT;
        SET @huella = Seguridad.fn_Huella(@pimienta, @nombre, @apellido, NULL);
        EXEC Seguridad.CerrarClave @abrio = @abrio;
    END TRY
    BEGIN CATCH
        EXEC Seguridad.CerrarClave @abrio = @abrio;
        THROW;
    END CATCH;

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

    -- Unicidad contra otros árbitros, por huella
    IF @idArbitro IS NOT NULL AND @idPais IS NOT NULL AND @nombre IS NOT NULL AND @apellido IS NOT NULL
       AND EXISTS (
           SELECT 1
           FROM Arbitraje.Arbitro
           WHERE idArbitro <> @idArbitro
             AND idPais = @idPais
             AND huella = @huella
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
    BEGIN TRY
        EXEC Seguridad.AbrirClave @abrio = @abrio OUTPUT;

        UPDATE Arbitraje.Arbitro
        SET idPais             = @idPais,
            nombreCif          = EncryptByKey(Key_GUID(N'ClaveDatosPersonales'), LTRIM(RTRIM(@nombre))),
            apellidoCif        = EncryptByKey(Key_GUID(N'ClaveDatosPersonales'), LTRIM(RTRIM(@apellido))),
            categoria          = @categoria,
            generoCif          = EncryptByKey(Key_GUID(N'ClaveDatosPersonales'), @genero),
            huella             = @huella,
            fechaInternacional = @fechaInternacional
        WHERE idArbitro = @idArbitro;

        EXEC Seguridad.CerrarClave @abrio = @abrio;
    END TRY
    BEGIN CATCH
        EXEC Seguridad.CerrarClave @abrio = @abrio;
        THROW;
    END CATCH;
END
GO

-- 3.3 BÚSQUEDA DE ÁRBITRO POR PAÍS, NOMBRE Y APELLIDO (nuevo)
-- Devuelve el id más bajo que coincide, o NULL. Mismo criterio de coincidencia que
-- la regla de unicidad de Arbitro_Alta (sin distinguir mayúsculas ni espacios de
-- los extremos). Lo usa el importador XML (70e) en lugar de comparar nombre y
-- apellido en la tabla, que ahora están cifrados.
CREATE OR ALTER PROCEDURE Arbitraje.Arbitro_Buscar
    @idPais     int,
    @nombre     nvarchar(200),
    @apellido   nvarchar(200),
    @idArbitro  int = NULL OUTPUT
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @abrio bit = 0, @pimienta nvarchar(100);
    SET @idArbitro = NULL;

    BEGIN TRY
        EXEC Seguridad.AbrirClave @abrio = @abrio OUTPUT;
        EXEC Seguridad.ObtenerPimienta @pimienta = @pimienta OUTPUT;

        SELECT TOP (1) @idArbitro = idArbitro
        FROM Arbitraje.Arbitro
        WHERE idPais = @idPais
          AND huella = Seguridad.fn_Huella(@pimienta, @nombre, @apellido, NULL)
        ORDER BY idArbitro;

        EXEC Seguridad.CerrarClave @abrio = @abrio;
    END TRY
    BEGIN CATCH
        EXEC Seguridad.CerrarClave @abrio = @abrio;
        THROW;
    END CATCH;
END
GO
