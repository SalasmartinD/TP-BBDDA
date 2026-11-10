/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 09/11/2026

 Objetivo    : SP de negocio del esquema Torneo:
               - Torneo.RegistrarResultado: cierra un partido con su resultado
                 final, controlando que coincida con los goles registrados como
                 eventos y que una eliminatoria empatada tenga ganador por
                 penales.

 Estándares aplicados:
 - Errores de datos con THROW 50001 y reglas de negocio con THROW 50002,
   cada uno con todas las líneas juntas en un único mensaje.
 - Todo corre dentro de una transacción: el partido y sus goles quedan
   bloqueados desde la validación hasta el COMMIT, así nadie carga un gol
   ni otro resultado en el medio. Ante cualquier error se hace ROLLBACK.
 - La actualización pasa por Torneo.Partido_Modificacion (10a), que suma
   sus propias validaciones (público contra capacidad, formato del esquema).
 - Un gol con minuto NULL es de la definición por penales (convención de
   Eventos.Gol en 00_InitialSchema.sql): no suma al resultado del partido.
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

/* =============================================================================
   1. REGISTRAR EL RESULTADO DE UN PARTIDO
   Pasa el partido de Programado o En juego a Finalizado.
   @cantPublico y los esquemas en NULL conservan lo que ya tenía cargado.
   ============================================================================= */
CREATE OR ALTER PROCEDURE Torneo.RegistrarResultado
    @idPartido         int,
    @golLocal          tinyint,
    @golVisitante      tinyint,
    @cantPublico       int          = NULL,
    @esquemaLocal      varchar(10)  = NULL,
    @esquemaVisitante  varchar(10)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @errores nvarchar(2000) = N'';
    DECLARE @idSede int, @idLocal int, @idVisitante int, @fase int, @fechaHoraUTC datetime2(0),
            @estado varchar(15), @nroPartidoOficial int, @publicoActual int,
            @esquemaLocalActual varchar(10), @esquemaVisitanteActual varchar(10), @esEliminatoria bit;
    DECLARE @golesEventos int, @golesEventosLocal int, @golesEventosVisitante int,
            @penalesLocal int, @penalesVisitante int;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- UPDLOCK + HOLDLOCK: el partido queda bloqueado hasta el COMMIT
        SELECT @idSede = p.idSede, @idLocal = p.idSeleccionLocal, @idVisitante = p.idSeleccionVisitante,
               @fase = p.fase, @fechaHoraUTC = p.fechaHoraUTC, @estado = p.estado,
               @nroPartidoOficial = p.nroPartidoOficial, @publicoActual = p.cantPublico,
               @esquemaLocalActual = p.esquemaLocal, @esquemaVisitanteActual = p.esquemaVisitante,
               @esEliminatoria = f.esEliminatoria
        FROM Torneo.Partido p WITH (UPDLOCK, HOLDLOCK)
        JOIN Torneo.Fase f ON f.idFase = p.fase
        WHERE p.idPartido = @idPartido;

        -- 1. Datos de entrada
        IF @estado IS NULL
            SET @errores += CHAR(10) + N'- El partido no existe.';

        IF @golLocal IS NULL OR @golVisitante IS NULL
            SET @errores += CHAR(10) + N'- El resultado debe cargarse completo: goles del local y del visitante.';

        IF @errores <> N''
        BEGIN
            SET @errores = N'No se pudo registrar el resultado:' + @errores;
            THROW 50001, @errores, 1;
        END;

        -- 2. Reglas de negocio
        IF @estado = 'Finalizado'
            SET @errores += CHAR(10) + N'- El partido ya tiene un resultado registrado; para corregirlo se usa Torneo.Partido_Modificacion.';
        ELSE IF @estado = 'Suspendido'
            SET @errores += CHAR(10) + N'- El partido está suspendido.';

        IF @fechaHoraUTC > SYSUTCDATETIME()
            SET @errores += CHAR(10) + N'- El partido todavía no empezó.';

        -- Goles registrados como eventos: un gol en contra suma para el rival.
        -- El autor se ubica en su selección a través de la formación del partido.
        SELECT @golesEventos = COUNT(*),
               @golesEventosLocal = SUM(CASE WHEN (fp.idSeleccion = @idLocal AND g.tipo <> 'En contra')
                                               OR (fp.idSeleccion = @idVisitante AND g.tipo = 'En contra')
                                             THEN 1 ELSE 0 END),
               @golesEventosVisitante = SUM(CASE WHEN (fp.idSeleccion = @idVisitante AND g.tipo <> 'En contra')
                                                   OR (fp.idSeleccion = @idLocal AND g.tipo = 'En contra')
                                                 THEN 1 ELSE 0 END)
        FROM Eventos.Gol g WITH (UPDLOCK, HOLDLOCK)
        JOIN Eventos.FormacionPartido fp ON fp.idPartido = g.idPartido AND fp.idJugador = g.idJugador
        WHERE g.idPartido = @idPartido AND g.minuto IS NOT NULL;

        IF @golesEventos > 0 AND (@golesEventosLocal <> @golLocal OR @golesEventosVisitante <> @golVisitante)
            SET @errores += CHAR(10) + N'- El resultado no coincide con los goles registrados como eventos ('
                          + CAST(@golesEventosLocal AS nvarchar(3)) + N'-'
                          + CAST(@golesEventosVisitante AS nvarchar(3)) + N').';

        -- En eliminación directa no hay empate: tiene que haber ganador por penales
        IF @esEliminatoria = 1 AND @golLocal = @golVisitante
        BEGIN
            SELECT @penalesLocal = COUNT(CASE WHEN fp.idSeleccion = @idLocal THEN 1 END),
                   @penalesVisitante = COUNT(CASE WHEN fp.idSeleccion = @idVisitante THEN 1 END)
            FROM Eventos.Gol g
            JOIN Eventos.FormacionPartido fp ON fp.idPartido = g.idPartido AND fp.idJugador = g.idJugador
            WHERE g.idPartido = @idPartido AND g.minuto IS NULL;

            IF @penalesLocal = @penalesVisitante
                SET @errores += CHAR(10) + N'- Un partido de eliminación directa empatado requiere la definición por penales registrada con un ganador.';
        END;

        IF @errores <> N''
        BEGIN
            SET @errores = N'No se pudo registrar el resultado:' + @errores;
            THROW 50002, @errores, 1;
        END;

        -- 3. Actualización a través del ABM
        SET @cantPublico      = COALESCE(@cantPublico, @publicoActual);
        SET @esquemaLocal     = COALESCE(NULLIF(LTRIM(RTRIM(@esquemaLocal)), ''), @esquemaLocalActual);
        SET @esquemaVisitante = COALESCE(NULLIF(LTRIM(RTRIM(@esquemaVisitante)), ''), @esquemaVisitanteActual);

        EXEC Torneo.Partido_Modificacion
             @idPartido = @idPartido, @idSede = @idSede, @idSeleccionLocal = @idLocal,
             @idSeleccionVisitante = @idVisitante, @fase = @fase, @fechaHoraUTC = @fechaHoraUTC,
             @estado = 'Finalizado', @nroPartidoOficial = @nroPartidoOficial, @cantPublico = @cantPublico,
             @golLocal = @golLocal, @golVisitante = @golVisitante,
             @esquemaLocal = @esquemaLocal, @esquemaVisitante = @esquemaVisitante;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END
GO
