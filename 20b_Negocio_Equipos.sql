/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 09/11/2026

 Objetivo    : SP de negocio del esquema Equipos:
               - Equipos.RegistrarConvocatoria: da de alta una lista de
                 convocados de una selección en una sola operación, validando
                 el mínimo y el máximo de convocados contra Sistema.Parametro.
               - Equipos.ReemplazarConvocado: da de baja un convocado y da de
                 alta a su reemplazo en la misma operación (baja de último
                 momento, por ejemplo por lesión).

 Estándares aplicados:
 - Errores de datos con THROW 50001 y reglas de negocio con THROW 50002,
   cada uno con todas las líneas juntas en un único mensaje.
 - Cada SP corre dentro de una transacción: si falla cualquier alta o baja,
   se hace ROLLBACK y no queda ningún cambio a medias.
 - Las altas y bajas pasan por los SP del ABM (10b), que suman sus propias
   validaciones (dorsal repetido, jugador ya convocado, fechas).

 Parámetros que usa (Sistema.Parametro, se cargan en 50d):
   MIN_CONVOCADOS          mínimo de convocados activos por selección
   MAX_CONVOCADOS          máximo de convocados activos por selección
   HORAS_LIMITE_REEMPLAZO  horas antes del primer partido de la selección
                           hasta las que se puede reemplazar a un jugador de
                           campo (a un arquero se lo puede reemplazar siempre)
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

/* =============================================================================
   1. REGISTRAR LA CONVOCATORIA DE UNA SELECCIÓN
   @convocados es un arreglo JSON con un objeto por jugador:
     [{"idJugador": 12, "dorsal": 1}, {"idJugador": 13, "dorsal": 2}, ...]
   La selección puede tener convocados activos de antes: el control de mínimo
   y máximo se hace sobre el total que queda después de la operación.
   ============================================================================= */
CREATE OR ALTER PROCEDURE Equipos.RegistrarConvocatoria
    @idSeleccion  int,
    @fechaAlta    date,
    @convocados   nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @errores nvarchar(2000) = N'';
    DECLARE @minimo int = (SELECT valor FROM Sistema.Parametro WHERE clave = 'MIN_CONVOCADOS');
    DECLARE @maximo int = (SELECT valor FROM Sistema.Parametro WHERE clave = 'MAX_CONVOCADOS');
    DECLARE @activos int, @nuevos int, @total int, @mensaje nvarchar(2048);
    DECLARE @n int, @idJugador int, @dorsal int;
    DECLARE @lista TABLE (n int PRIMARY KEY, idJugador int, dorsal int);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. Datos de entrada
        IF @idSeleccion IS NULL OR NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE id = @idSeleccion)
            SET @errores += CHAR(10) + N'- La selección no existe.';

        IF @fechaAlta IS NULL
            SET @errores += CHAR(10) + N'- La fecha de alta es obligatoria.';

        IF @minimo IS NULL OR @maximo IS NULL
            SET @errores += CHAR(10) + N'- Faltan los parámetros MIN_CONVOCADOS y MAX_CONVOCADOS en Sistema.Parametro.';

        IF @convocados IS NULL OR ISJSON(@convocados) = 0 OR LEFT(LTRIM(@convocados), 1) <> '['
            SET @errores += CHAR(10) + N'- La lista de convocados debe ser un arreglo JSON.';
        ELSE
        BEGIN
            -- [key] es la posición de cada objeto en el arreglo (0, 1, 2...)
            INSERT INTO @lista (n, idJugador, dorsal)
            SELECT CAST(arr.[key] AS int) + 1, TRY_CAST(JSON_VALUE(arr.value, '$.idJugador') AS int),
                   TRY_CAST(JSON_VALUE(arr.value, '$.dorsal') AS int)
            FROM OPENJSON(@convocados) arr;

            IF NOT EXISTS (SELECT 1 FROM @lista)
                SET @errores += CHAR(10) + N'- La lista de convocados está vacía.';

            IF EXISTS (SELECT 1 FROM @lista WHERE idJugador IS NULL OR dorsal IS NULL)
                SET @errores += CHAR(10) + N'- Cada convocado de la lista debe tener idJugador y dorsal numéricos.';

            IF EXISTS (SELECT idJugador FROM @lista WHERE idJugador IS NOT NULL GROUP BY idJugador HAVING COUNT(*) > 1)
                SET @errores += CHAR(10) + N'- Un jugador figura más de una vez en la lista.';

            IF EXISTS (SELECT dorsal FROM @lista WHERE dorsal IS NOT NULL GROUP BY dorsal HAVING COUNT(*) > 1)
                SET @errores += CHAR(10) + N'- Un dorsal figura más de una vez en la lista.';
        END;

        IF @errores <> N''
        BEGIN
            SET @errores = N'No se pudo registrar la convocatoria:' + @errores;
            THROW 50001, @errores, 1;
        END;

        -- 2. Reglas de negocio: mínimo y máximo sobre el total que va a quedar.
        -- UPDLOCK + HOLDLOCK: nadie suma ni da de baja convocados de la
        -- selección hasta el COMMIT.
        SET @activos = (SELECT COUNT(*) FROM Equipos.ListadoJugadores WITH (UPDLOCK, HOLDLOCK)
                        WHERE idSeleccion = @idSeleccion AND fechaBaja IS NULL);
        SET @nuevos = (SELECT COUNT(*) FROM @lista);
        SET @total = @activos + @nuevos;

        IF @total < @minimo
            SET @errores += CHAR(10) + N'- La selección quedaría con ' + CAST(@total AS nvarchar(10))
                          + N' convocados y el mínimo es ' + CAST(@minimo AS nvarchar(10)) + N'.';

        IF @total > @maximo
            SET @errores += CHAR(10) + N'- La selección quedaría con ' + CAST(@total AS nvarchar(10))
                          + N' convocados y el máximo es ' + CAST(@maximo AS nvarchar(10)) + N'.';

        IF @errores <> N''
        BEGIN
            SET @errores = N'No se pudo registrar la convocatoria:' + @errores;
            THROW 50002, @errores, 1;
        END;

        -- 3. Altas a través del ABM. Si una falla, se avisa qué fila de la
        -- lista fue y se deshacen todas las anteriores.
        SET @n = 1;
        WHILE @n <= @nuevos
        BEGIN
            SELECT @idJugador = idJugador, @dorsal = dorsal FROM @lista WHERE n = @n;
            BEGIN TRY
                EXEC Equipos.ListadoJugadores_Alta @idSeleccion = @idSeleccion, @idJugador = @idJugador,
                     @dorsal = @dorsal, @fechaAlta = @fechaAlta;
            END TRY
            BEGIN CATCH
                IF ERROR_NUMBER() < 50000 THROW;   -- error del motor: se propaga tal cual
                SET @mensaje = N'Convocado ' + CAST(@n AS nvarchar(10)) + N' de la lista (idJugador '
                             + CAST(@idJugador AS nvarchar(10)) + N'). ' + ERROR_MESSAGE();
                THROW 50001, @mensaje, 1;
            END CATCH;
            SET @n += 1;
        END;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END
GO

/* =============================================================================
   2. REEMPLAZAR UN CONVOCADO
   Baja lógica del convocado y alta del reemplazante en la misma selección,
   con idReemplazaA apuntando al reemplazado. @dorsal en NULL hereda el
   dorsal del reemplazado. Devuelve el id del nuevo convocado en @idNuevo.
   ============================================================================= */
CREATE OR ALTER PROCEDURE Equipos.ReemplazarConvocado
    @idConvocado         int,
    @idJugadorReemplazo  int,
    @fechaCambio         date,
    @motivoBaja          varchar(100),
    @dorsal              int  = NULL,
    @idNuevo             int  = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @errores nvarchar(2000) = N'';
    DECLARE @horasLimite int = (SELECT valor FROM Sistema.Parametro WHERE clave = 'HORAS_LIMITE_REEMPLAZO');
    DECLARE @idSeleccion int, @idJugadorActual int, @dorsalActual int, @fechaBajaActual date,
            @posicion varchar(15), @primerPartido datetime2(0);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- UPDLOCK + HOLDLOCK: el convocado queda bloqueado hasta el COMMIT
        SELECT @idSeleccion = lj.idSeleccion, @idJugadorActual = lj.idJugador, @dorsalActual = lj.dorsal,
               @fechaBajaActual = lj.fechaBaja, @posicion = j.posicion
        FROM Equipos.ListadoJugadores lj WITH (UPDLOCK, HOLDLOCK)
        JOIN Equipos.Jugador j ON j.id = lj.idJugador
        WHERE lj.id = @idConvocado;

        -- 1. Datos de entrada
        IF @idSeleccion IS NULL
            SET @errores += CHAR(10) + N'- El convocado a reemplazar no existe.';
        ELSE IF @fechaBajaActual IS NOT NULL
            SET @errores += CHAR(10) + N'- El convocado a reemplazar ya fue dado de baja.';

        IF @idJugadorReemplazo IS NULL OR NOT EXISTS (SELECT 1 FROM Equipos.Jugador WHERE id = @idJugadorReemplazo)
            SET @errores += CHAR(10) + N'- El jugador reemplazante no existe.';
        ELSE IF @idJugadorReemplazo = @idJugadorActual
            SET @errores += CHAR(10) + N'- El reemplazante no puede ser el mismo jugador que se da de baja.';

        IF @fechaCambio IS NULL
            SET @errores += CHAR(10) + N'- La fecha del cambio es obligatoria.';

        IF @horasLimite IS NULL
            SET @errores += CHAR(10) + N'- Falta el parámetro HORAS_LIMITE_REEMPLAZO en Sistema.Parametro.';

        IF @errores <> N''
        BEGIN
            SET @errores = N'No se pudo reemplazar el convocado:' + @errores;
            THROW 50001, @errores, 1;
        END;

        -- 2. Regla de negocio: a un jugador de campo se lo reemplaza hasta
        -- HORAS_LIMITE_REEMPLAZO horas antes del primer partido de su selección.
        -- La fecha del cambio se toma desde las 00:00 UTC de ese día.
        SET @primerPartido = (SELECT MIN(fechaHoraUTC) FROM Torneo.Partido
                              WHERE @idSeleccion IN (idSeleccionLocal, idSeleccionVisitante));

        IF (@posicion IS NULL OR @posicion <> 'Arquero')
           AND @primerPartido IS NOT NULL
           AND DATEDIFF(HOUR, CAST(@fechaCambio AS datetime2(0)), @primerPartido) < @horasLimite
            SET @errores += CHAR(10) + N'- Fuera de término: a un jugador de campo solo se lo puede reemplazar hasta '
                          + CAST(@horasLimite AS nvarchar(10)) + N' horas antes del primer partido de su selección.';

        IF @errores <> N''
        BEGIN
            SET @errores = N'No se pudo reemplazar el convocado:' + @errores;
            THROW 50002, @errores, 1;
        END;

        -- 3. Baja y alta a través del ABM, en ese orden: la baja libera el dorsal
        EXEC Equipos.ListadoJugadores_Baja @id = @idConvocado, @fechaBaja = @fechaCambio, @motivoBaja = @motivoBaja;

        SET @dorsal = COALESCE(@dorsal, @dorsalActual);
        EXEC Equipos.ListadoJugadores_Alta @idSeleccion = @idSeleccion, @idJugador = @idJugadorReemplazo,
             @dorsal = @dorsal, @fechaAlta = @fechaCambio, @idReemplazaA = @idConvocado, @id = @idNuevo OUTPUT;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END
GO
