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
               de las tablas del esquema Equipos:
               - Equipos.Seleccion
               - Equipos.Jugador
               - Equipos.Staff
               - Equipos.ListadoJugadores

 Estándares aplicados:
 - Cada SP revisa todas las condiciones, acumula las que fallan en @errores
   y, si hay alguna, corta con un único THROW 50001 que las informa juntas.
 - La tabla se modifica solo después de validar con éxito.
 - La baja de un convocado es lógica (fechaBaja + motivoBaja), porque la
   consigna pide registrar el motivo y la fecha de las bajas de último momento.
 - El mínimo y máximo de convocados contra Sistema.Parametro se controla en
   los SP de negocio (script 20), no en el ABM.
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

/* =============================================================================
   1. TABLA: Equipos.Seleccion
   ============================================================================= */

-- 1.1 ALTA DE SELECCIÓN
CREATE OR ALTER PROCEDURE Equipos.Seleccion_Alta
    @idPais            int,
    @confederacion     varchar(10),
    @abreviacion       varchar(10),
    @nombreAsociacion  nvarchar(100) = NULL,
    @grupo             varchar(5)    = NULL,
    @id                int           = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @confederacion    = UPPER(LTRIM(RTRIM(@confederacion)));
    SET @abreviacion      = UPPER(LTRIM(RTRIM(@abreviacion)));
    SET @nombreAsociacion = NULLIF(LTRIM(RTRIM(@nombreAsociacion)), N'');
    SET @grupo            = NULLIF(UPPER(LTRIM(RTRIM(@grupo))), '');

    IF @idPais IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE id = @idPais)
        SET @errores += CHAR(10) + N'- El país de la selección no existe.';
    ELSE IF EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE idPais = @idPais)
        SET @errores += CHAR(10) + N'- El país ya tiene una selección registrada.';

    IF @confederacion IS NULL OR @confederacion NOT IN ('AFC', 'CAF', 'CONCACAF', 'CONMEBOL', 'OFC', 'UEFA')
        SET @errores += CHAR(10) + N'- La confederación debe ser AFC, CAF, CONCACAF, CONMEBOL, OFC o UEFA.';

    IF @abreviacion IS NULL OR @abreviacion COLLATE Latin1_General_BIN NOT LIKE '[A-Z][A-Z][A-Z]'
        SET @errores += CHAR(10) + N'- La abreviación FIFA debe tener exactamente 3 letras.';
    ELSE IF EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE abreviacion = @abreviacion)
        SET @errores += CHAR(10) + N'- La abreviación FIFA ya la usa otra selección.';

    IF @grupo IS NOT NULL AND @grupo COLLATE Latin1_General_BIN NOT LIKE '[A-L]'
        SET @errores += CHAR(10) + N'- El grupo debe ser una letra de la A a la L.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de alta la selección:' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Equipos.Seleccion (idPais, confederacion, nombreAsociacion, abreviacion, grupo)
    VALUES (@idPais, @confederacion, @nombreAsociacion, @abreviacion, @grupo);

    SET @id = SCOPE_IDENTITY();
END
GO

-- 1.2 MODIFICACIÓN DE SELECCIÓN
-- El país no se puede cambiar si la selección ya juega partidos: cambiaría la
-- nacionalidad contra la que se validaron las designaciones arbitrales.
CREATE OR ALTER PROCEDURE Equipos.Seleccion_Modificacion
    @id                int,
    @idPais            int,
    @confederacion     varchar(10),
    @abreviacion       varchar(10),
    @nombreAsociacion  nvarchar(100) = NULL,
    @grupo             varchar(5)    = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @confederacion    = UPPER(LTRIM(RTRIM(@confederacion)));
    SET @abreviacion      = UPPER(LTRIM(RTRIM(@abreviacion)));
    SET @nombreAsociacion = NULLIF(LTRIM(RTRIM(@nombreAsociacion)), N'');
    SET @grupo            = NULLIF(UPPER(LTRIM(RTRIM(@grupo))), '');

    IF @id IS NULL OR NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE id = @id)
        SET @errores += CHAR(10) + N'- La selección a modificar no existe.';

    IF @idPais IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE id = @idPais)
        SET @errores += CHAR(10) + N'- El país de la selección no existe.';
    ELSE IF EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE idPais = @idPais AND id <> @id)
        SET @errores += CHAR(10) + N'- El país ya tiene otra selección registrada.';
    ELSE IF EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE id = @id AND idPais <> @idPais)
            AND EXISTS (SELECT 1 FROM Torneo.Partido
                        WHERE idSeleccionLocal = @id OR idSeleccionVisitante = @id)
        SET @errores += CHAR(10) + N'- No se puede cambiar el país porque la selección ya tiene partidos asignados.';

    IF @confederacion IS NULL OR @confederacion NOT IN ('AFC', 'CAF', 'CONCACAF', 'CONMEBOL', 'OFC', 'UEFA')
        SET @errores += CHAR(10) + N'- La confederación debe ser AFC, CAF, CONCACAF, CONMEBOL, OFC o UEFA.';

    IF @abreviacion IS NULL OR @abreviacion COLLATE Latin1_General_BIN NOT LIKE '[A-Z][A-Z][A-Z]'
        SET @errores += CHAR(10) + N'- La abreviación FIFA debe tener exactamente 3 letras.';
    ELSE IF EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE abreviacion = @abreviacion AND id <> @id)
        SET @errores += CHAR(10) + N'- La abreviación FIFA ya la usa otra selección.';

    IF @grupo IS NOT NULL AND @grupo COLLATE Latin1_General_BIN NOT LIKE '[A-L]'
        SET @errores += CHAR(10) + N'- El grupo debe ser una letra de la A a la L.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo modificar la selección:' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Equipos.Seleccion
    SET idPais           = @idPais,
        confederacion    = @confederacion,
        nombreAsociacion = @nombreAsociacion,
        abreviacion      = @abreviacion,
        grupo            = @grupo
    WHERE id = @id;
END
GO

-- 1.3 BAJA DE SELECCIÓN
CREATE OR ALTER PROCEDURE Equipos.Seleccion_Baja
    @id int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    IF @id IS NULL OR NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE id = @id)
        SET @errores += CHAR(10) + N'- La selección a eliminar no existe.';

    IF EXISTS (SELECT 1 FROM Torneo.Partido WHERE idSeleccionLocal = @id OR idSeleccionVisitante = @id)
        SET @errores += CHAR(10) + N'- La selección tiene partidos asignados.';

    IF EXISTS (SELECT 1 FROM Equipos.ListadoJugadores WHERE idSeleccion = @id)
        SET @errores += CHAR(10) + N'- La selección tiene jugadores convocados.';

    IF EXISTS (SELECT 1 FROM Equipos.Staff WHERE idSeleccion = @id)
        SET @errores += CHAR(10) + N'- La selección tiene cuerpo técnico registrado.';

    IF EXISTS (SELECT 1 FROM Eventos.FormacionPartido WHERE idSeleccion = @id)
        SET @errores += CHAR(10) + N'- La selección tiene formaciones cargadas.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de baja la selección:' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Equipos.Seleccion WHERE id = @id;
END
GO

/* =============================================================================
   2. TABLA: Equipos.Jugador
   ============================================================================= */

-- 2.1 ALTA DE JUGADOR
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
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @nombre      = LTRIM(RTRIM(@nombre));
    SET @apellido    = LTRIM(RTRIM(@apellido));
    SET @piernaHabil = NULLIF(LTRIM(RTRIM(@piernaHabil)), '');
    SET @club        = NULLIF(LTRIM(RTRIM(@club)), N'');
    SET @posicion    = NULLIF(LTRIM(RTRIM(@posicion)), '');

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

    IF @fechaNacimiento IS NOT NULL
       AND EXISTS (SELECT 1 FROM Equipos.Jugador
                   WHERE nombre = @nombre AND apellido = @apellido AND fechaNacimiento = @fechaNacimiento)
        SET @errores += CHAR(10) + N'- Ya existe un jugador con el mismo nombre, apellido y fecha de nacimiento.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de alta el jugador:' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Equipos.Jugador (nombre, apellido, fechaNacimiento, altura, peso, piernaHabil, club, posicion)
    VALUES (@nombre, @apellido, @fechaNacimiento, @altura, @peso, @piernaHabil, @club, @posicion);

    SET @id = SCOPE_IDENTITY();
END
GO

-- 2.2 MODIFICACIÓN DE JUGADOR
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
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @nombre      = LTRIM(RTRIM(@nombre));
    SET @apellido    = LTRIM(RTRIM(@apellido));
    SET @piernaHabil = NULLIF(LTRIM(RTRIM(@piernaHabil)), '');
    SET @club        = NULLIF(LTRIM(RTRIM(@club)), N'');
    SET @posicion    = NULLIF(LTRIM(RTRIM(@posicion)), '');

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

    IF @fechaNacimiento IS NOT NULL
       AND EXISTS (SELECT 1 FROM Equipos.Jugador
                   WHERE nombre = @nombre AND apellido = @apellido
                     AND fechaNacimiento = @fechaNacimiento AND id <> @id)
        SET @errores += CHAR(10) + N'- Ya existe otro jugador con el mismo nombre, apellido y fecha de nacimiento.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo modificar el jugador:' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Equipos.Jugador
    SET nombre          = @nombre,
        apellido        = @apellido,
        fechaNacimiento = @fechaNacimiento,
        altura          = @altura,
        peso            = @peso,
        piernaHabil     = @piernaHabil,
        club            = @club,
        posicion        = @posicion
    WHERE id = @id;
END
GO

-- 2.3 BAJA DE JUGADOR
CREATE OR ALTER PROCEDURE Equipos.Jugador_Baja
    @id int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    IF @id IS NULL OR NOT EXISTS (SELECT 1 FROM Equipos.Jugador WHERE id = @id)
        SET @errores += CHAR(10) + N'- El jugador a eliminar no existe.';

    IF EXISTS (SELECT 1 FROM Equipos.ListadoJugadores WHERE idJugador = @id)
        SET @errores += CHAR(10) + N'- El jugador figura en convocatorias.';

    IF EXISTS (SELECT 1 FROM Eventos.FormacionPartido WHERE idJugador = @id)
        SET @errores += CHAR(10) + N'- El jugador figura en formaciones de partidos.';

    IF EXISTS (SELECT 1 FROM Eventos.Gol WHERE idJugador = @id OR idAsistidor = @id)
       OR EXISTS (SELECT 1 FROM Eventos.Tarjeta WHERE idJugador = @id)
       OR EXISTS (SELECT 1 FROM Eventos.Sustitucion WHERE idIngresa = @id OR idSale = @id)
       OR EXISTS (SELECT 1 FROM Eventos.Suspension WHERE idJugador = @id)
        SET @errores += CHAR(10) + N'- El jugador tiene goles, tarjetas, sustituciones o suspensiones registrados.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de baja el jugador:' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Equipos.Jugador WHERE id = @id;
END
GO

/* =============================================================================
   3. TABLA: Equipos.Staff
   ============================================================================= */

-- 3.1 ALTA DE INTEGRANTE DEL CUERPO TÉCNICO
CREATE OR ALTER PROCEDURE Equipos.Staff_Alta
    @idSeleccion      int,
    @nombre           nvarchar(60),
    @apellido         nvarchar(60),
    @rol              varchar(20),
    @fechaNacimiento  date = NULL,
    @id               int  = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
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

    INSERT INTO Equipos.Staff (idSeleccion, nombre, apellido, fechaNacimiento, rol)
    VALUES (@idSeleccion, @nombre, @apellido, @fechaNacimiento, @rol);

    SET @id = SCOPE_IDENTITY();
END
GO

-- 3.2 MODIFICACIÓN DE INTEGRANTE DEL CUERPO TÉCNICO
CREATE OR ALTER PROCEDURE Equipos.Staff_Modificacion
    @id               int,
    @idSeleccion      int,
    @nombre           nvarchar(60),
    @apellido         nvarchar(60),
    @rol              varchar(20),
    @fechaNacimiento  date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
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

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo modificar el integrante del cuerpo técnico:' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Equipos.Staff
    SET idSeleccion     = @idSeleccion,
        nombre          = @nombre,
        apellido        = @apellido,
        fechaNacimiento = @fechaNacimiento,
        rol             = @rol
    WHERE id = @id;
END
GO

-- 3.3 BAJA DE INTEGRANTE DEL CUERPO TÉCNICO
CREATE OR ALTER PROCEDURE Equipos.Staff_Baja
    @id int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    IF @id IS NULL OR NOT EXISTS (SELECT 1 FROM Equipos.Staff WHERE id = @id)
        SET @errores += CHAR(10) + N'- El integrante del cuerpo técnico a eliminar no existe.';

    IF EXISTS (SELECT 1 FROM Eventos.Tarjeta WHERE idStaff = @id)
       OR EXISTS (SELECT 1 FROM Eventos.Suspension WHERE idStaff = @id)
        SET @errores += CHAR(10) + N'- El integrante tiene tarjetas o suspensiones registradas.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de baja el integrante del cuerpo técnico:' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Equipos.Staff WHERE id = @id;
END
GO

/* =============================================================================
   4. TABLA: Equipos.ListadoJugadores (convocatoria)
   El dorsal se recibe como int para poder informar el rango en lugar de
   fallar en la conversión a tinyint.
   ============================================================================= */

-- 4.1 ALTA DE CONVOCADO
-- Si el convocado reemplaza a otro, el reemplazado tiene que ser de la misma
-- selección, ya estar dado de baja (antes o el mismo día) y no tener otro
-- reemplazo registrado.
CREATE OR ALTER PROCEDURE Equipos.ListadoJugadores_Alta
    @idSeleccion   int,
    @idJugador     int,
    @dorsal        int,
    @fechaAlta     date,
    @idReemplazaA  int = NULL,
    @id            int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    IF @idSeleccion IS NULL OR NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE id = @idSeleccion)
        SET @errores += CHAR(10) + N'- La selección no existe.';

    IF @idJugador IS NULL OR NOT EXISTS (SELECT 1 FROM Equipos.Jugador WHERE id = @idJugador)
        SET @errores += CHAR(10) + N'- El jugador no existe.';
    ELSE IF EXISTS (SELECT 1 FROM Equipos.ListadoJugadores WHERE idJugador = @idJugador AND fechaBaja IS NULL)
        SET @errores += CHAR(10) + N'- El jugador ya está convocado activo en una selección.';

    IF @fechaAlta IS NULL
        SET @errores += CHAR(10) + N'- La fecha de alta es obligatoria.';

    IF @dorsal IS NULL OR @dorsal NOT BETWEEN 1 AND 99
        SET @errores += CHAR(10) + N'- El dorsal es obligatorio y debe estar entre 1 y 99.';
    ELSE IF EXISTS (SELECT 1 FROM Equipos.ListadoJugadores
                    WHERE idSeleccion = @idSeleccion AND dorsal = @dorsal AND fechaBaja IS NULL)
        SET @errores += CHAR(10) + N'- El dorsal ya lo usa otro convocado activo.';

    IF @idReemplazaA IS NOT NULL
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM Equipos.ListadoJugadores WHERE id = @idReemplazaA)
            SET @errores += CHAR(10) + N'- El convocado reemplazado no existe.';
        ELSE
        BEGIN
            IF EXISTS (SELECT 1 FROM Equipos.ListadoJugadores WHERE id = @idReemplazaA AND idSeleccion <> @idSeleccion)
                SET @errores += CHAR(10) + N'- El convocado reemplazado pertenece a otra selección.';

            IF EXISTS (SELECT 1 FROM Equipos.ListadoJugadores WHERE id = @idReemplazaA AND fechaBaja IS NULL)
                SET @errores += CHAR(10) + N'- El convocado reemplazado todavía no fue dado de baja.';
            ELSE IF EXISTS (SELECT 1 FROM Equipos.ListadoJugadores WHERE id = @idReemplazaA AND fechaBaja > @fechaAlta)
                SET @errores += CHAR(10) + N'- La fecha de alta del reemplazo es anterior a la baja del reemplazado.';

            IF EXISTS (SELECT 1 FROM Equipos.ListadoJugadores WHERE idReemplazaA = @idReemplazaA)
                SET @errores += CHAR(10) + N'- El convocado reemplazado ya tiene otro reemplazo registrado.';
        END;
    END;

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de alta el convocado:' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Equipos.ListadoJugadores (idSeleccion, idJugador, fechaAlta, dorsal, idReemplazaA)
    VALUES (@idSeleccion, @idJugador, @fechaAlta, @dorsal, @idReemplazaA);

    SET @id = SCOPE_IDENTITY();
END
GO

-- 4.2 MODIFICACIÓN DE CONVOCADO
-- Solo se modifican el dorsal y la fecha de alta: cambiar la selección o el
-- jugador equivale a una baja y un alta nuevas.
CREATE OR ALTER PROCEDURE Equipos.ListadoJugadores_Modificacion
    @id         int,
    @dorsal     int,
    @fechaAlta  date
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    IF @id IS NULL OR NOT EXISTS (SELECT 1 FROM Equipos.ListadoJugadores WHERE id = @id)
        SET @errores += CHAR(10) + N'- El convocado a modificar no existe.';

    IF @fechaAlta IS NULL
        SET @errores += CHAR(10) + N'- La fecha de alta es obligatoria.';
    ELSE IF EXISTS (SELECT 1 FROM Equipos.ListadoJugadores WHERE id = @id AND fechaBaja < @fechaAlta)
        SET @errores += CHAR(10) + N'- La fecha de alta no puede ser posterior a la fecha de baja.';

    IF @dorsal IS NULL OR @dorsal NOT BETWEEN 1 AND 99
        SET @errores += CHAR(10) + N'- El dorsal es obligatorio y debe estar entre 1 y 99.';
    ELSE IF EXISTS (SELECT 1
                    FROM Equipos.ListadoJugadores actual
                    JOIN Equipos.ListadoJugadores otro
                      ON otro.idSeleccion = actual.idSeleccion AND otro.id <> actual.id
                    WHERE actual.id = @id AND actual.fechaBaja IS NULL
                      AND otro.fechaBaja IS NULL AND otro.dorsal = @dorsal)
        SET @errores += CHAR(10) + N'- El dorsal ya lo usa otro convocado activo.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo modificar el convocado:' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Equipos.ListadoJugadores
    SET dorsal    = @dorsal,
        fechaAlta = @fechaAlta
    WHERE id = @id;
END
GO

-- 4.3 BAJA DE CONVOCADO (lógica)
CREATE OR ALTER PROCEDURE Equipos.ListadoJugadores_Baja
    @id          int,
    @fechaBaja   date,
    @motivoBaja  varchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @motivoBaja = LTRIM(RTRIM(@motivoBaja));

    IF @id IS NULL OR NOT EXISTS (SELECT 1 FROM Equipos.ListadoJugadores WHERE id = @id)
        SET @errores += CHAR(10) + N'- El convocado a dar de baja no existe.';
    ELSE IF EXISTS (SELECT 1 FROM Equipos.ListadoJugadores WHERE id = @id AND fechaBaja IS NOT NULL)
        SET @errores += CHAR(10) + N'- El convocado ya fue dado de baja.';

    IF @fechaBaja IS NULL
        SET @errores += CHAR(10) + N'- La fecha de baja es obligatoria.';
    ELSE IF EXISTS (SELECT 1 FROM Equipos.ListadoJugadores WHERE id = @id AND fechaAlta > @fechaBaja)
        SET @errores += CHAR(10) + N'- La fecha de baja no puede ser anterior a la fecha de alta.';

    IF @motivoBaja IS NULL OR @motivoBaja = ''
        SET @errores += CHAR(10) + N'- El motivo de la baja es obligatorio.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de baja el convocado:' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Equipos.ListadoJugadores
    SET fechaBaja  = @fechaBaja,
        motivoBaja = @motivoBaja
    WHERE id = @id;
END
GO
