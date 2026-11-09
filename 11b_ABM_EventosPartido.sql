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
               y Modificación (ABM) de las 5 tablas del esquema Eventos:
               - Eventos.FormacionPartido
               - Eventos.Gol
               - Eventos.Tarjeta
               - Eventos.Sustitucion
               - Eventos.Suspension

 Estándares aplicados:
 - Acumulación exhaustiva de errores en @errores nvarchar(2000).
 - Un solo THROW 50001 al final de las validaciones informando todos los fallos.
 - Nombres en formato Esquema.Tabla_Accion.
 - Modificación de datos sólo tras validar con éxito todas las precondiciones.
 - Parámetros y variables locales estrictamente en @camelCase.
 - Cero uso de SQL dinámico o CLR.
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

/* =============================================================================
   1. TABLA: Eventos.FormacionPartido
   ============================================================================= */

-- 1.1 ALTA DE FORMACIÓN
CREATE OR ALTER PROCEDURE Eventos.FormacionPartido_Alta
    @idPartido   int,
    @idSeleccion int,
    @idJugador   int,
    @titular     bit,
    @posicion    varchar(15) = NULL,
    @id          int         = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @posicion = NULLIF(LTRIM(RTRIM(@posicion)), '');

    -- Existencia de partido
    IF @idPartido IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido)
        SET @errores += CHAR(10) + N'- El partido especificado no existe.';

    -- Existencia de selección
    IF @idSeleccion IS NULL OR NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE id = @idSeleccion)
        SET @errores += CHAR(10) + N'- La selección especificada no existe.';

    -- Existencia de jugador
    IF @idJugador IS NULL OR NOT EXISTS (SELECT 1 FROM Equipos.Jugador WHERE id = @idJugador)
        SET @errores += CHAR(10) + N'- El jugador especificado no existe.';

    -- Validación de titularidad obligatoria
    IF @titular IS NULL
        SET @errores += CHAR(10) + N'- Debe indicar si el jugador es titular (1) o suplente (0).';

    -- Posición válida
    IF @posicion IS NOT NULL AND @posicion NOT IN ('Arquero', 'Defensor', 'Mediocampista', 'Delantero')
        SET @errores += CHAR(10) + N'- La posición táctica debe ser Arquero, Defensor, Mediocampista o Delantero.';

    -- Coherencia: la selección debe ser una de las dos que disputan el encuentro
    IF @idPartido IS NOT NULL AND @idSeleccion IS NOT NULL
       AND NOT EXISTS (
           SELECT 1
           FROM Torneo.Partido
           WHERE idPartido = @idPartido
             AND (idSeleccionLocal = @idSeleccion OR idSeleccionVisitante = @idSeleccion)
       )
        SET @errores += CHAR(10) + N'- La selección especificada no disputa el partido indicado.';

    -- Unicidad de jugador en el partido (UQ_FormacionPartido_PartidoJugador)
    IF @idPartido IS NOT NULL AND @idJugador IS NOT NULL
       AND EXISTS (SELECT 1 FROM Eventos.FormacionPartido WHERE idPartido = @idPartido AND idJugador = @idJugador)
        SET @errores += CHAR(10) + N'- El jugador ya se encuentra registrado en la formación de este partido.';

    -- Estado del partido (no permitir si ya finalizó o está en juego)
    IF EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido AND estado IN ('Finalizado', 'En juego'))
        SET @errores += CHAR(10) + N'- No se pueden agregar jugadores a la formación de un partido ya finalizado o que se encuentra en juego.';

    -- THROW único
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo registrar la formación del partido:' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Eventos.FormacionPartido (idPartido, idSeleccion, idJugador, titular, posicion)
    VALUES (@idPartido, @idSeleccion, @idJugador, @titular, @posicion);

    SET @id = SCOPE_IDENTITY();
END
GO

-- 1.2 MODIFICACIÓN DE FORMACIÓN
CREATE OR ALTER PROCEDURE Eventos.FormacionPartido_Modificacion
    @id          int,
    @idPartido   int,
    @idSeleccion int,
    @idJugador   int,
    @titular     bit,
    @posicion    varchar(15) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @posicion = NULLIF(LTRIM(RTRIM(@posicion)), '');

    -- Existencia del registro a modificar
    IF @id IS NULL OR NOT EXISTS (SELECT 1 FROM Eventos.FormacionPartido WHERE id = @id)
        SET @errores += CHAR(10) + N'- El registro de formación a modificar no existe.';

    -- Existencia de claves foráneas
    IF @idPartido IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido)
        SET @errores += CHAR(10) + N'- El partido especificado no existe.';

    IF @idSeleccion IS NULL OR NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE id = @idSeleccion)
        SET @errores += CHAR(10) + N'- La selección especificada no existe.';

    IF @idJugador IS NULL OR NOT EXISTS (SELECT 1 FROM Equipos.Jugador WHERE id = @idJugador)
        SET @errores += CHAR(10) + N'- El jugador especificado no existe.';

    IF @titular IS NULL
        SET @errores += CHAR(10) + N'- Debe indicar si el jugador es titular (1) o suplente (0).';

    IF @posicion IS NOT NULL AND @posicion NOT IN ('Arquero', 'Defensor', 'Mediocampista', 'Delantero')
        SET @errores += CHAR(10) + N'- La posición táctica debe ser Arquero, Defensor, Mediocampista o Delantero.';

    -- Coherencia selección - partido
    IF @idPartido IS NOT NULL AND @idSeleccion IS NOT NULL
       AND NOT EXISTS (
           SELECT 1
           FROM Torneo.Partido
           WHERE idPartido = @idPartido
             AND (idSeleccionLocal = @idSeleccion OR idSeleccionVisitante = @idSeleccion)
       )
        SET @errores += CHAR(10) + N'- La selección especificada no disputa el partido indicado.';

    -- Unicidad contra otros registros
    IF @id IS NOT NULL AND @idPartido IS NOT NULL AND @idJugador IS NOT NULL
       AND EXISTS (
           SELECT 1
           FROM Eventos.FormacionPartido
           WHERE idPartido = @idPartido
             AND idJugador = @idJugador
             AND id <> @id
       )
        SET @errores += CHAR(10) + N'- El jugador ya se encuentra registrado en la formación de este partido.';

    -- Estado del partido original y nuevo
    IF EXISTS (
        SELECT 1
        FROM Eventos.FormacionPartido fp
        JOIN Torneo.Partido p ON fp.idPartido = p.idPartido
        WHERE fp.id = @id AND p.estado IN ('Finalizado', 'En juego')
    )
        SET @errores += CHAR(10) + N'- No se puede modificar la formación de un partido ya finalizado o que se encuentra en juego.';
    ELSE IF EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido AND estado IN ('Finalizado', 'En juego'))
        SET @errores += CHAR(10) + N'- No se puede trasladar la formación a un partido ya finalizado o en juego.';

    -- Bloqueo si el jugador original registra incidencias y se intenta cambiar de jugador, selección o partido
    IF EXISTS (
        SELECT 1
        FROM Eventos.FormacionPartido fp
        WHERE fp.id = @id
          AND (fp.idPartido <> @idPartido OR fp.idJugador <> @idJugador OR fp.idSeleccion <> @idSeleccion)
          AND (
              EXISTS (SELECT 1 FROM Eventos.Gol g WHERE g.idPartido = fp.idPartido AND (g.idJugador = fp.idJugador OR g.idAsistidor = fp.idJugador))
              OR EXISTS (SELECT 1 FROM Eventos.Tarjeta t WHERE t.idPartido = fp.idPartido AND t.idJugador = fp.idJugador)
              OR EXISTS (SELECT 1 FROM Eventos.Sustitucion s WHERE s.idPartido = fp.idPartido AND (s.idIngresa = fp.idJugador OR s.idSale = fp.idJugador))
          )
    )
        SET @errores += CHAR(10) + N'- No se puede modificar el jugador, la selección o el partido porque registra incidencias (goles, tarjetas o sustituciones) asociadas en este encuentro.';

    -- THROW único
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo modificar la formación del partido:' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Eventos.FormacionPartido
    SET idPartido   = @idPartido,
        idSeleccion = @idSeleccion,
        idJugador   = @idJugador,
        titular     = @titular,
        posicion    = @posicion
    WHERE id = @id;
END
GO

-- 1.3 BAJA DE FORMACIÓN
CREATE OR ALTER PROCEDURE Eventos.FormacionPartido_Baja
    @id int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    -- Existencia del registro
    IF @id IS NULL OR NOT EXISTS (SELECT 1 FROM Eventos.FormacionPartido WHERE id = @id)
        SET @errores += CHAR(10) + N'- El registro de formación a eliminar no existe.';

    -- Estado del partido
    IF EXISTS (
        SELECT 1
        FROM Eventos.FormacionPartido fp
        JOIN Torneo.Partido p ON fp.idPartido = p.idPartido
        WHERE fp.id = @id AND p.estado IN ('Finalizado', 'En juego')
    )
        SET @errores += CHAR(10) + N'- No se puede eliminar a un jugador de la formación de un partido ya finalizado o en juego.';

    -- Integridad referencial: goles / asistencias
    IF EXISTS (
        SELECT 1
        FROM Eventos.FormacionPartido fp
        JOIN Eventos.Gol g ON fp.idPartido = g.idPartido AND (fp.idJugador = g.idJugador OR fp.idJugador = g.idAsistidor)
        WHERE fp.id = @id
    )
        SET @errores += CHAR(10) + N'- No se puede eliminar al jugador de la formación porque registra goles o asistencias en este partido.';

    -- Integridad referencial: tarjetas
    IF EXISTS (
        SELECT 1
        FROM Eventos.FormacionPartido fp
        JOIN Eventos.Tarjeta t ON fp.idPartido = t.idPartido AND fp.idJugador = t.idJugador
        WHERE fp.id = @id
    )
        SET @errores += CHAR(10) + N'- No se puede eliminar al jugador de la formación porque registra tarjetas en este partido.';

    -- Integridad referencial: sustituciones
    IF EXISTS (
        SELECT 1
        FROM Eventos.FormacionPartido fp
        JOIN Eventos.Sustitucion s ON fp.idPartido = s.idPartido AND (fp.idJugador = s.idIngresa OR fp.idJugador = s.idSale)
        WHERE fp.id = @id
    )
        SET @errores += CHAR(10) + N'- No se puede eliminar al jugador de la formación porque registra sustituciones en este partido.';

    -- THROW único
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de baja la formación del partido:' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Eventos.FormacionPartido
    WHERE id = @id;
END
GO

/* =============================================================================
   2. TABLA: Eventos.Gol
   ============================================================================= */

-- 2.1 ALTA DE GOL
CREATE OR ALTER PROCEDURE Eventos.Gol_Alta
    @idPartido       int,
    @idJugador       int,
    @idAsistidor     int         = NULL,
    @minuto          tinyint     = NULL,
    @minutoAdicional tinyint     = NULL,
    @tipo            varchar(20),
    @idPeriodo       tinyint,
    @idGol           int         = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @tipo = LTRIM(RTRIM(@tipo));

    -- Existencia de claves foráneas
    IF @idPartido IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido)
        SET @errores += CHAR(10) + N'- El partido especificado no existe.';

    IF @idJugador IS NULL OR NOT EXISTS (SELECT 1 FROM Equipos.Jugador WHERE id = @idJugador)
        SET @errores += CHAR(10) + N'- El jugador autor del gol no existe.';

    IF @idPeriodo IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Periodo WHERE idPeriodo = @idPeriodo)
        SET @errores += CHAR(10) + N'- El período de juego especificado no existe.';

    -- Validación de asistidor (si se indica)
    IF @idAsistidor IS NOT NULL
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM Equipos.Jugador WHERE id = @idAsistidor)
            SET @errores += CHAR(10) + N'- El jugador asistidor especificado no existe.';
        ELSE IF @idAsistidor = @idJugador
            SET @errores += CHAR(10) + N'- El asistidor no puede ser el mismo jugador que convirtió el gol.';
    END;

    -- Tipo de gol obligatorio y dentro del dominio permitido
    IF @tipo IS NULL OR @tipo = ''
        SET @errores += CHAR(10) + N'- El tipo de gol es obligatorio.';
    ELSE IF @tipo NOT IN ('Jugada', 'Penal', 'Tiro libre', 'En contra', 'Cabeza')
        SET @errores += CHAR(10) + N'- El tipo de gol debe ser Jugada, Penal, Tiro libre, En contra o Cabeza.';

    -- Rango de minuto (0 a 120 o NULL si es definición por penales)
    IF @minuto IS NOT NULL AND @minuto > 120
        SET @errores += CHAR(10) + N'- El minuto del gol debe estar comprendido entre 0 y 120.';

    -- Minuto adicional solo permitido en 45, 90, 105 o 120
    IF @minutoAdicional IS NOT NULL AND (@minuto IS NULL OR @minuto NOT IN (45, 90, 105, 120))
        SET @errores += CHAR(10) + N'- El minuto adicional solo es válido en los minutos de cierre reglamentario (45, 90, 105 o 120).';

    -- Estado del partido (no permitir registrar goles en partidos programados)
    IF EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido AND estado = 'Programado')
        SET @errores += CHAR(10) + N'- No se pueden registrar goles en un partido que todavía se encuentra en estado programado.';

    -- El autor del gol debe figurar en la formación del partido
    IF @idPartido IS NOT NULL AND @idJugador IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM Eventos.FormacionPartido WHERE idPartido = @idPartido AND idJugador = @idJugador)
        SET @errores += CHAR(10) + N'- El autor del gol debe estar registrado en la formación del partido.';

    -- El asistidor debe figurar en la formación del partido y pertenecer a la misma selección
    IF @idPartido IS NOT NULL AND @idJugador IS NOT NULL AND @idAsistidor IS NOT NULL AND @idAsistidor <> @idJugador
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM Eventos.FormacionPartido WHERE idPartido = @idPartido AND idJugador = @idAsistidor)
            SET @errores += CHAR(10) + N'- El jugador asistidor debe estar registrado en la formación del partido.';
        ELSE IF (
            SELECT idSeleccion FROM Eventos.FormacionPartido WHERE idPartido = @idPartido AND idJugador = @idJugador
        ) <> (
            SELECT idSeleccion FROM Eventos.FormacionPartido WHERE idPartido = @idPartido AND idJugador = @idAsistidor
        )
            SET @errores += CHAR(10) + N'- El asistidor debe pertenecer a la misma selección que el autor del gol.';
    END;

    -- THROW único
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo registrar el gol:' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Eventos.Gol (idPartido, idJugador, idAsistidor, minuto, minutoAdicional, tipo, idPeriodo)
    VALUES (@idPartido, @idJugador, @idAsistidor, @minuto, @minutoAdicional, @tipo, @idPeriodo);

    SET @idGol = SCOPE_IDENTITY();
END
GO

-- 2.2 MODIFICACIÓN DE GOL
CREATE OR ALTER PROCEDURE Eventos.Gol_Modificacion
    @idGol           int,
    @idPartido       int,
    @idJugador       int,
    @idAsistidor     int         = NULL,
    @minuto          tinyint     = NULL,
    @minutoAdicional tinyint     = NULL,
    @tipo            varchar(20),
    @idPeriodo       tinyint
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @tipo = LTRIM(RTRIM(@tipo));

    -- Existencia del registro a modificar
    IF @idGol IS NULL OR NOT EXISTS (SELECT 1 FROM Eventos.Gol WHERE idGol = @idGol)
        SET @errores += CHAR(10) + N'- El registro del gol a modificar no existe.';

    -- Existencia de claves foráneas
    IF @idPartido IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido)
        SET @errores += CHAR(10) + N'- El partido especificado no existe.';

    IF @idJugador IS NULL OR NOT EXISTS (SELECT 1 FROM Equipos.Jugador WHERE id = @idJugador)
        SET @errores += CHAR(10) + N'- El jugador autor del gol no existe.';

    IF @idPeriodo IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Periodo WHERE idPeriodo = @idPeriodo)
        SET @errores += CHAR(10) + N'- El período de juego especificado no existe.';

    -- Validación de asistidor
    IF @idAsistidor IS NOT NULL
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM Equipos.Jugador WHERE id = @idAsistidor)
            SET @errores += CHAR(10) + N'- El jugador asistidor especificado no existe.';
        ELSE IF @idAsistidor = @idJugador
            SET @errores += CHAR(10) + N'- El asistidor no puede ser el mismo jugador que convirtió el gol.';
    END;

    IF @tipo IS NULL OR @tipo = ''
        SET @errores += CHAR(10) + N'- El tipo de gol es obligatorio.';
    ELSE IF @tipo NOT IN ('Jugada', 'Penal', 'Tiro libre', 'En contra', 'Cabeza')
        SET @errores += CHAR(10) + N'- El tipo de gol debe ser Jugada, Penal, Tiro libre, En contra o Cabeza.';

    IF @minuto IS NOT NULL AND @minuto > 120
        SET @errores += CHAR(10) + N'- El minuto del gol debe estar comprendido entre 0 y 120.';

    IF @minutoAdicional IS NOT NULL AND (@minuto IS NULL OR @minuto NOT IN (45, 90, 105, 120))
        SET @errores += CHAR(10) + N'- El minuto adicional solo es válido en los minutos de cierre reglamentario (45, 90, 105 o 120).';

    IF EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido AND estado = 'Programado')
        SET @errores += CHAR(10) + N'- No se pueden registrar goles en un partido que todavía se encuentra en estado programado.';

    IF @idPartido IS NOT NULL AND @idJugador IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM Eventos.FormacionPartido WHERE idPartido = @idPartido AND idJugador = @idJugador)
        SET @errores += CHAR(10) + N'- El autor del gol debe estar registrado en la formación del partido.';

    IF @idPartido IS NOT NULL AND @idJugador IS NOT NULL AND @idAsistidor IS NOT NULL AND @idAsistidor <> @idJugador
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM Eventos.FormacionPartido WHERE idPartido = @idPartido AND idJugador = @idAsistidor)
            SET @errores += CHAR(10) + N'- El jugador asistidor debe estar registrado en la formación del partido.';
        ELSE IF (
            SELECT idSeleccion FROM Eventos.FormacionPartido WHERE idPartido = @idPartido AND idJugador = @idJugador
        ) <> (
            SELECT idSeleccion FROM Eventos.FormacionPartido WHERE idPartido = @idPartido AND idJugador = @idAsistidor
        )
            SET @errores += CHAR(10) + N'- El asistidor debe pertenecer a la misma selección que el autor del gol.';
    END;

    -- THROW único
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo modificar el gol:' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Eventos.Gol
    SET idPartido       = @idPartido,
        idJugador       = @idJugador,
        idAsistidor     = @idAsistidor,
        minuto          = @minuto,
        minutoAdicional = @minutoAdicional,
        tipo            = @tipo,
        idPeriodo       = @idPeriodo
    WHERE idGol = @idGol;
END
GO

-- 2.3 BAJA DE GOL
CREATE OR ALTER PROCEDURE Eventos.Gol_Baja
    @idGol int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    IF @idGol IS NULL OR NOT EXISTS (SELECT 1 FROM Eventos.Gol WHERE idGol = @idGol)
        SET @errores += CHAR(10) + N'- El registro de gol a eliminar no existe.';

    -- THROW único
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de baja el gol:' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Eventos.Gol
    WHERE idGol = @idGol;
END
GO

/* =============================================================================
   3. TABLA: Eventos.Tarjeta
   ============================================================================= */

-- 3.1 ALTA DE TARJETA
CREATE OR ALTER PROCEDURE Eventos.Tarjeta_Alta
    @idPartido       int,
    @idJugador       int         = NULL,
    @idStaff         int         = NULL,
    @idPeriodo       tinyint,
    @color           char(1),
    @minuto          tinyint,
    @minutoAdicional tinyint     = NULL,
    @motivo          varchar(80) = NULL,
    @tipoRoja        varchar(15) = NULL,
    @idTarjeta       int         = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @color    = UPPER(LTRIM(RTRIM(@color)));
    SET @motivo   = NULLIF(LTRIM(RTRIM(@motivo)), '');
    SET @tipoRoja = NULLIF(LTRIM(RTRIM(@tipoRoja)), '');

    -- Existencia de partido y período
    IF @idPartido IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido)
        SET @errores += CHAR(10) + N'- El partido especificado no existe.';

    IF @idPeriodo IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Periodo WHERE idPeriodo = @idPeriodo)
        SET @errores += CHAR(10) + N'- El período de juego especificado no existe.';

    -- Exactamente uno de los dos: Jugador o Staff (CK_Tarjeta_JugadorOStaff)
    IF (@idJugador IS NULL AND @idStaff IS NULL) OR (@idJugador IS NOT NULL AND @idStaff IS NOT NULL)
        SET @errores += CHAR(10) + N'- Debe especificar exactamente a un jugador o a un integrante del cuerpo técnico, no ambos ni ninguno.';

    -- Validación de Jugador
    IF @idJugador IS NOT NULL
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM Equipos.Jugador WHERE id = @idJugador)
            SET @errores += CHAR(10) + N'- El jugador especificado no existe.';
        ELSE IF @idPartido IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM Eventos.FormacionPartido WHERE idPartido = @idPartido AND idJugador = @idJugador)
            SET @errores += CHAR(10) + N'- El jugador amonestado/expulsado debe estar registrado en la formación del partido.';
    END;

    -- Validación de Staff
    IF @idStaff IS NOT NULL
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM Equipos.Staff WHERE id = @idStaff)
            SET @errores += CHAR(10) + N'- El integrante del cuerpo técnico especificado no existe.';
        ELSE IF @idPartido IS NOT NULL
           AND NOT EXISTS (
               SELECT 1
               FROM Equipos.Staff st
               JOIN Torneo.Partido p ON p.idPartido = @idPartido
               WHERE st.id = @idStaff
                 AND (st.idSeleccion = p.idSeleccionLocal OR st.idSeleccion = p.idSeleccionVisitante)
           )
            SET @errores += CHAR(10) + N'- El integrante del cuerpo técnico no pertenece a ninguna de las selecciones que disputan el partido.';
    END;

    -- Validación del color ('A' o 'R')
    IF @color IS NULL OR @color NOT IN ('A', 'R')
        SET @errores += CHAR(10) + N'- El color de la tarjeta debe ser ''A'' (amarilla) o ''R'' (roja).';

    -- Validación de consistencia de tipoRoja (CK_Tarjeta_TipoRoja)
    IF @color = 'A' AND @tipoRoja IS NOT NULL
        SET @errores += CHAR(10) + N'- Las tarjetas amarillas no deben indicar tipo de expulsión.';
    ELSE IF @color = 'R' AND (@tipoRoja IS NULL OR @tipoRoja NOT IN ('Directa', 'Doble amarilla'))
        SET @errores += CHAR(10) + N'- Para tarjetas rojas, el tipo debe ser ''Directa'' o ''Doble amarilla''.';

    -- Minuto obligatorio entre 0 y 120
    IF @minuto IS NULL OR @minuto > 120
        SET @errores += CHAR(10) + N'- El minuto de la tarjeta es obligatorio y debe encontrarse entre 0 y 120.';

    -- Minuto adicional
    IF @minutoAdicional IS NOT NULL AND (@minuto IS NULL OR @minuto NOT IN (45, 90, 105, 120))
        SET @errores += CHAR(10) + N'- El minuto adicional solo es válido en los minutos de cierre reglamentario (45, 90, 105 o 120).';

    -- Estado del partido
    IF EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido AND estado = 'Programado')
        SET @errores += CHAR(10) + N'- No se pueden registrar tarjetas en un partido que todavía se encuentra en estado programado.';

    -- THROW único
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo registrar la tarjeta:' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Eventos.Tarjeta (idPartido, idJugador, idStaff, idPeriodo, color, minuto, minutoAdicional, motivo, tipoRoja)
    VALUES (@idPartido, @idJugador, @idStaff, @idPeriodo, @color, @minuto, @minutoAdicional, @motivo, @tipoRoja);

    SET @idTarjeta = SCOPE_IDENTITY();
END
GO

-- 3.2 MODIFICACIÓN DE TARJETA
CREATE OR ALTER PROCEDURE Eventos.Tarjeta_Modificacion
    @idTarjeta       int,
    @idPartido       int,
    @idJugador       int         = NULL,
    @idStaff         int         = NULL,
    @idPeriodo       tinyint,
    @color           char(1),
    @minuto          tinyint,
    @minutoAdicional tinyint     = NULL,
    @motivo          varchar(80) = NULL,
    @tipoRoja        varchar(15) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @color    = UPPER(LTRIM(RTRIM(@color)));
    SET @motivo   = NULLIF(LTRIM(RTRIM(@motivo)), '');
    SET @tipoRoja = NULLIF(LTRIM(RTRIM(@tipoRoja)), '');

    -- Existencia de la tarjeta
    IF @idTarjeta IS NULL OR NOT EXISTS (SELECT 1 FROM Eventos.Tarjeta WHERE idTarjeta = @idTarjeta)
        SET @errores += CHAR(10) + N'- El registro de la tarjeta a modificar no existe.';

    -- Existencia de claves foráneas
    IF @idPartido IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido)
        SET @errores += CHAR(10) + N'- El partido especificado no existe.';

    IF @idPeriodo IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Periodo WHERE idPeriodo = @idPeriodo)
        SET @errores += CHAR(10) + N'- El período de juego especificado no existe.';

    -- Exactamente uno de los dos
    IF (@idJugador IS NULL AND @idStaff IS NULL) OR (@idJugador IS NOT NULL AND @idStaff IS NOT NULL)
        SET @errores += CHAR(10) + N'- Debe especificar exactamente a un jugador o a un integrante del cuerpo técnico, no ambos ni ninguno.';

    -- Validación de Jugador
    IF @idJugador IS NOT NULL
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM Equipos.Jugador WHERE id = @idJugador)
            SET @errores += CHAR(10) + N'- El jugador especificado no existe.';
        ELSE IF @idPartido IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM Eventos.FormacionPartido WHERE idPartido = @idPartido AND idJugador = @idJugador)
            SET @errores += CHAR(10) + N'- El jugador amonestado/expulsado debe estar registrado en la formación del partido.';
    END;

    -- Validación de Staff
    IF @idStaff IS NOT NULL
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM Equipos.Staff WHERE id = @idStaff)
            SET @errores += CHAR(10) + N'- El integrante del cuerpo técnico especificado no existe.';
        ELSE IF @idPartido IS NOT NULL
           AND NOT EXISTS (
               SELECT 1
               FROM Equipos.Staff st
               JOIN Torneo.Partido p ON p.idPartido = @idPartido
               WHERE st.id = @idStaff
                 AND (st.idSeleccion = p.idSeleccionLocal OR st.idSeleccion = p.idSeleccionVisitante)
           )
            SET @errores += CHAR(10) + N'- El integrante del cuerpo técnico no pertenece a ninguna de las selecciones que disputan el partido.';
    END;

    -- Validación del color
    IF @color IS NULL OR @color NOT IN ('A', 'R')
        SET @errores += CHAR(10) + N'- El color de la tarjeta debe ser ''A'' (amarilla) o ''R'' (roja).';

    -- Consistencia tipoRoja
    IF @color = 'A' AND @tipoRoja IS NOT NULL
        SET @errores += CHAR(10) + N'- Las tarjetas amarillas no deben indicar tipo de expulsión.';
    ELSE IF @color = 'R' AND (@tipoRoja IS NULL OR @tipoRoja NOT IN ('Directa', 'Doble amarilla'))
        SET @errores += CHAR(10) + N'- Para tarjetas rojas, el tipo debe ser ''Directa'' o ''Doble amarilla''.';

    -- Minuto
    IF @minuto IS NULL OR @minuto > 120
        SET @errores += CHAR(10) + N'- El minuto de la tarjeta es obligatorio y debe encontrarse entre 0 y 120.';

    IF @minutoAdicional IS NOT NULL AND (@minuto IS NULL OR @minuto NOT IN (45, 90, 105, 120))
        SET @errores += CHAR(10) + N'- El minuto adicional solo es válido en los minutos de cierre reglamentario (45, 90, 105 o 120).';

    IF EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido AND estado = 'Programado')
        SET @errores += CHAR(10) + N'- No se pueden registrar tarjetas en un partido que todavía se encuentra en estado programado.';

    -- THROW único
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo modificar la tarjeta:' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Eventos.Tarjeta
    SET idPartido       = @idPartido,
        idJugador       = @idJugador,
        idStaff         = @idStaff,
        idPeriodo       = @idPeriodo,
        color           = @color,
        minuto          = @minuto,
        minutoAdicional = @minutoAdicional,
        motivo          = @motivo,
        tipoRoja        = @tipoRoja
    WHERE idTarjeta = @idTarjeta;
END
GO

-- 3.3 BAJA DE TARJETA
CREATE OR ALTER PROCEDURE Eventos.Tarjeta_Baja
    @idTarjeta int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    IF @idTarjeta IS NULL OR NOT EXISTS (SELECT 1 FROM Eventos.Tarjeta WHERE idTarjeta = @idTarjeta)
        SET @errores += CHAR(10) + N'- El registro de la tarjeta a eliminar no existe.';

    -- THROW único
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de baja la tarjeta:' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Eventos.Tarjeta
    WHERE idTarjeta = @idTarjeta;
END
GO

/* =============================================================================
   4. TABLA: Eventos.Sustitucion
   ============================================================================= */

-- 4.1 ALTA DE SUSTITUCIÓN
CREATE OR ALTER PROCEDURE Eventos.Sustitucion_Alta
    @idPartido       int,
    @idIngresa       int,
    @idSale          int,
    @idPeriodo       tinyint,
    @minuto          tinyint,
    @minutoAdicional tinyint     = NULL,
    @motivo          varchar(15),
    @id              int         = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @motivo = LTRIM(RTRIM(@motivo));

    -- Existencia de claves foráneas
    IF @idPartido IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido)
        SET @errores += CHAR(10) + N'- El partido especificado no existe.';

    IF @idIngresa IS NULL OR NOT EXISTS (SELECT 1 FROM Equipos.Jugador WHERE id = @idIngresa)
        SET @errores += CHAR(10) + N'- El jugador que ingresa no existe.';

    IF @idSale IS NULL OR NOT EXISTS (SELECT 1 FROM Equipos.Jugador WHERE id = @idSale)
        SET @errores += CHAR(10) + N'- El jugador que sale no existe.';

    IF @idPeriodo IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Periodo WHERE idPeriodo = @idPeriodo)
        SET @errores += CHAR(10) + N'- El período de juego especificado no existe.';

    -- Jugadores distintos (CK_Sustitucion_JugadoresDistintos)
    IF @idIngresa IS NOT NULL AND @idSale IS NOT NULL AND @idIngresa = @idSale
        SET @errores += CHAR(10) + N'- El jugador que ingresa y el que sale deben ser distintos.';

    -- Motivo válido (CK_Sustitucion_Motivo)
    IF @motivo IS NULL OR @motivo NOT IN ('Tactico', 'Lesion', 'Precaucion')
        SET @errores += CHAR(10) + N'- El motivo de la sustitución debe ser Tactico, Lesion o Precaucion.';

    -- Minuto válido (0 a 120)
    IF @minuto IS NULL OR @minuto > 120
        SET @errores += CHAR(10) + N'- El minuto de la sustitución es obligatorio y debe encontrarse entre 0 y 120.';

    -- Minuto adicional
    IF @minutoAdicional IS NOT NULL AND (@minuto IS NULL OR @minuto NOT IN (45, 90, 105, 120))
        SET @errores += CHAR(10) + N'- El minuto adicional solo es válido en los minutos de cierre reglamentario (45, 90, 105 o 120).';

    -- Estado del partido
    IF EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido AND estado = 'Programado')
        SET @errores += CHAR(10) + N'- No se pueden registrar sustituciones en un partido que todavía se encuentra en estado programado.';

    -- Validación de pertenencia y equipo en la formación
    IF @idPartido IS NOT NULL AND @idIngresa IS NOT NULL AND @idSale IS NOT NULL AND @idIngresa <> @idSale
    BEGIN
        DECLARE @selIngresa int = (SELECT idSeleccion FROM Eventos.FormacionPartido WHERE idPartido = @idPartido AND idJugador = @idIngresa);
        DECLARE @selSale int    = (SELECT idSeleccion FROM Eventos.FormacionPartido WHERE idPartido = @idPartido AND idJugador = @idSale);

        IF @selSale IS NULL
            SET @errores += CHAR(10) + N'- El jugador que sale debe estar registrado en la formación del partido.';

        IF @selIngresa IS NULL
            SET @errores += CHAR(10) + N'- El jugador que ingresa debe estar registrado en la formación del partido.';

        IF @selSale IS NOT NULL AND @selIngresa IS NOT NULL AND @selSale <> @selIngresa
            SET @errores += CHAR(10) + N'- Ambos jugadores deben pertenecer a la misma selección en el partido.';
    END;

    -- THROW único
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo registrar la sustitución:' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Eventos.Sustitucion (idPartido, idIngresa, idSale, idPeriodo, minuto, minutoAdicional, motivo)
    VALUES (@idPartido, @idIngresa, @idSale, @idPeriodo, @minuto, @minutoAdicional, @motivo);

    SET @id = SCOPE_IDENTITY();
END
GO

-- 4.2 MODIFICACIÓN DE SUSTITUCIÓN
CREATE OR ALTER PROCEDURE Eventos.Sustitucion_Modificacion
    @id              int,
    @idPartido       int,
    @idIngresa       int,
    @idSale          int,
    @idPeriodo       tinyint,
    @minuto          tinyint,
    @minutoAdicional tinyint     = NULL,
    @motivo          varchar(15)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @motivo = LTRIM(RTRIM(@motivo));

    -- Existencia del registro a modificar
    IF @id IS NULL OR NOT EXISTS (SELECT 1 FROM Eventos.Sustitucion WHERE id = @id)
        SET @errores += CHAR(10) + N'- El registro de la sustitución a modificar no existe.';

    -- Existencia de claves foráneas
    IF @idPartido IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido)
        SET @errores += CHAR(10) + N'- El partido especificado no existe.';

    IF @idIngresa IS NULL OR NOT EXISTS (SELECT 1 FROM Equipos.Jugador WHERE id = @idIngresa)
        SET @errores += CHAR(10) + N'- El jugador que ingresa no existe.';

    IF @idSale IS NULL OR NOT EXISTS (SELECT 1 FROM Equipos.Jugador WHERE id = @idSale)
        SET @errores += CHAR(10) + N'- El jugador que sale no existe.';

    IF @idPeriodo IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Periodo WHERE idPeriodo = @idPeriodo)
        SET @errores += CHAR(10) + N'- El período de juego especificado no existe.';

    IF @idIngresa IS NOT NULL AND @idSale IS NOT NULL AND @idIngresa = @idSale
        SET @errores += CHAR(10) + N'- El jugador que ingresa y el que sale deben ser distintos.';

    IF @motivo IS NULL OR @motivo NOT IN ('Tactico', 'Lesion', 'Precaucion')
        SET @errores += CHAR(10) + N'- El motivo de la sustitución debe ser Tactico, Lesion o Precaucion.';

    IF @minuto IS NULL OR @minuto > 120
        SET @errores += CHAR(10) + N'- El minuto de la sustitución es obligatorio y debe encontrarse entre 0 y 120.';

    IF @minutoAdicional IS NOT NULL AND (@minuto IS NULL OR @minuto NOT IN (45, 90, 105, 120))
        SET @errores += CHAR(10) + N'- El minuto adicional solo es válido en los minutos de cierre reglamentario (45, 90, 105 o 120).';

    IF EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido AND estado = 'Programado')
        SET @errores += CHAR(10) + N'- No se pueden registrar sustituciones en un partido que todavía se encuentra en estado programado.';

    IF @idPartido IS NOT NULL AND @idIngresa IS NOT NULL AND @idSale IS NOT NULL AND @idIngresa <> @idSale
    BEGIN
        DECLARE @selIngresaMod int = (SELECT idSeleccion FROM Eventos.FormacionPartido WHERE idPartido = @idPartido AND idJugador = @idIngresa);
        DECLARE @selSaleMod int    = (SELECT idSeleccion FROM Eventos.FormacionPartido WHERE idPartido = @idPartido AND idJugador = @idSale);

        IF @selSaleMod IS NULL
            SET @errores += CHAR(10) + N'- El jugador que sale debe estar registrado en la formación del partido.';

        IF @selIngresaMod IS NULL
            SET @errores += CHAR(10) + N'- El jugador que ingresa debe estar registrado en la formación del partido.';

        IF @selSaleMod IS NOT NULL AND @selIngresaMod IS NOT NULL AND @selSaleMod <> @selIngresaMod
            SET @errores += CHAR(10) + N'- Ambos jugadores deben pertenecer a la misma selección en el partido.';
    END;

    -- THROW único
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo modificar la sustitución:' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Eventos.Sustitucion
    SET idPartido       = @idPartido,
        idIngresa       = @idIngresa,
        idSale          = @idSale,
        idPeriodo       = @idPeriodo,
        minuto          = @minuto,
        minutoAdicional = @minutoAdicional,
        motivo          = @motivo
    WHERE id = @id;
END
GO

-- 4.3 BAJA DE SUSTITUCIÓN
CREATE OR ALTER PROCEDURE Eventos.Sustitucion_Baja
    @id int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    IF @id IS NULL OR NOT EXISTS (SELECT 1 FROM Eventos.Sustitucion WHERE id = @id)
        SET @errores += CHAR(10) + N'- El registro de la sustitución a eliminar no existe.';

    -- THROW único
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de baja la sustitución:' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Eventos.Sustitucion
    WHERE id = @id;
END
GO

/* =============================================================================
   5. TABLA: Eventos.Suspension
   ============================================================================= */

-- 5.1 ALTA DE SUSPENSIÓN
CREATE OR ALTER PROCEDURE Eventos.Suspension_Alta
    @idPartido         int,
    @idJugador         int     = NULL,
    @idStaff           int     = NULL,
    @cantPartidos      tinyint,
    @partidosRestantes tinyint,
    @id                int     = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    -- Existencia de partido
    IF @idPartido IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido)
        SET @errores += CHAR(10) + N'- El partido especificado no existe.';

    -- Exactamente uno de los dos: Jugador o Staff (CK_Suspension_JugadorOStaff)
    IF (@idJugador IS NULL AND @idStaff IS NULL) OR (@idJugador IS NOT NULL AND @idStaff IS NOT NULL)
        SET @errores += CHAR(10) + N'- Debe especificar exactamente a un jugador o a un integrante del cuerpo técnico, no ambos ni ninguno.';

    -- Existencia de jugador si se indicó
    IF @idJugador IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Equipos.Jugador WHERE id = @idJugador)
        SET @errores += CHAR(10) + N'- El jugador especificado no existe.';

    -- Existencia de staff si se indicó
    IF @idStaff IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Equipos.Staff WHERE id = @idStaff)
        SET @errores += CHAR(10) + N'- El integrante del cuerpo técnico especificado no existe.';

    -- Cantidad de partidos > 0 (CK_Suspension_CantPartidos)
    IF @cantPartidos IS NULL OR @cantPartidos = 0
        SET @errores += CHAR(10) + N'- La cantidad total de partidos sancionados debe ser mayor a cero.';

    -- Partidos restantes <= cantPartidos (CK_Suspension_Restantes)
    IF @partidosRestantes IS NULL OR (@cantPartidos IS NOT NULL AND @partidosRestantes > @cantPartidos)
        SET @errores += CHAR(10) + N'- La cantidad de partidos restantes no puede superar el total de partidos de la sanción.';

    -- THROW único
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo registrar la suspensión:' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Eventos.Suspension (idPartido, idJugador, idStaff, cantPartidos, partidosRestantes)
    VALUES (@idPartido, @idJugador, @idStaff, @cantPartidos, @partidosRestantes);

    SET @id = SCOPE_IDENTITY();
END
GO

-- 5.2 MODIFICACIÓN DE SUSPENSIÓN
CREATE OR ALTER PROCEDURE Eventos.Suspension_Modificacion
    @id                int,
    @idPartido         int,
    @idJugador         int     = NULL,
    @idStaff           int     = NULL,
    @cantPartidos      tinyint,
    @partidosRestantes tinyint
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    -- Existencia de la suspensión
    IF @id IS NULL OR NOT EXISTS (SELECT 1 FROM Eventos.Suspension WHERE id = @id)
        SET @errores += CHAR(10) + N'- El registro de suspensión a modificar no existe.';

    -- Existencia de partido
    IF @idPartido IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido)
        SET @errores += CHAR(10) + N'- El partido especificado no existe.';

    -- Exactamente uno de los dos
    IF (@idJugador IS NULL AND @idStaff IS NULL) OR (@idJugador IS NOT NULL AND @idStaff IS NOT NULL)
        SET @errores += CHAR(10) + N'- Debe especificar exactamente a un jugador o a un integrante del cuerpo técnico, no ambos ni ninguno.';

    IF @idJugador IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Equipos.Jugador WHERE id = @idJugador)
        SET @errores += CHAR(10) + N'- El jugador especificado no existe.';

    IF @idStaff IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Equipos.Staff WHERE id = @idStaff)
        SET @errores += CHAR(10) + N'- El integrante del cuerpo técnico especificado no existe.';

    IF @cantPartidos IS NULL OR @cantPartidos = 0
        SET @errores += CHAR(10) + N'- La cantidad total de partidos sancionados debe ser mayor a cero.';

    IF @partidosRestantes IS NULL OR (@cantPartidos IS NOT NULL AND @partidosRestantes > @cantPartidos)
        SET @errores += CHAR(10) + N'- La cantidad de partidos restantes no puede superar el total de partidos de la sanción.';

    -- THROW único
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo modificar la suspensión:' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Eventos.Suspension
    SET idPartido         = @idPartido,
        idJugador         = @idJugador,
        idStaff           = @idStaff,
        cantPartidos      = @cantPartidos,
        partidosRestantes = @partidosRestantes
    WHERE id = @id;
END
GO

-- 5.3 BAJA DE SUSPENSIÓN
CREATE OR ALTER PROCEDURE Eventos.Suspension_Baja
    @id int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    IF @id IS NULL OR NOT EXISTS (SELECT 1 FROM Eventos.Suspension WHERE id = @id)
        SET @errores += CHAR(10) + N'- El registro de suspensión a eliminar no existe.';

    -- THROW único
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de baja la suspensión:' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Eventos.Suspension
    WHERE id = @id;
END
GO
