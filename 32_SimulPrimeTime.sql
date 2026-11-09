/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 09/11/2026

 Objetivo    : SPs de simulación de prime time para un partido:
               1) Publicidad.SimularPrimeTimePartido  — países con piezas
                  de mercado candidatas para ese partido, mostrando hora local
                  y si el partido cae en prime time.
               2) Publicidad.SimularPrimeTimePorPais  — todos los países de
                  Torneo.Pais con husoHorario definido, con hora local del
                  partido y si es prime time. Versión más simple/global.
               Implementados con SELECT y AT TIME ZONE (sin cursores).
================================================================================
*/

USE MundialFutbol;
GO

/* =============================================================================
   SP: Publicidad.SimularPrimeTimePartido
   
   Para un partido dado, devuelve el result set de los países que poseen al
   menos una pieza de mercado candidata (campaña vigente en la fecha del
   partido), mostrando:
     - idPais, nombrePais, husoHorario
     - horaLocalPartido (time): hora local calculada con AT TIME ZONE
     - esPrimeTime (bit): 1 si la hora local cae entre PRIME_TIME_INICIO
       y PRIME_TIME_FIN (parámetros en Sistema.Parametro, default 19–23)
   
   Parámetros:
     @idPartido int  — identificador del partido a simular
   
   Lanza THROW 50001 si el partido no existe.
   ============================================================================= */
CREATE OR ALTER PROCEDURE Publicidad.SimularPrimeTimePartido
    @idPartido int
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY

        DECLARE @errores      nvarchar(2000) = N'';
        DECLARE @fechaHoraUTC datetime2(0);
        DECLARE @fechaPartido date;

        /* -----------------------------------------------------------------------
           VALIDACIÓN: Existencia del partido
        ----------------------------------------------------------------------- */
        SELECT @fechaHoraUTC = fechaHoraUTC
        FROM Torneo.Partido
        WHERE idPartido = @idPartido;

        IF @fechaHoraUTC IS NULL
            SET @errores = @errores
                + N' | El partido con id=' + CAST(@idPartido AS nvarchar(10))
                + N' no existe.';

        IF @errores <> N''
        BEGIN
            SET @errores = N'SimularPrimeTimePartido:' + @errores;
            THROW 50001, @errores, 1;
        END;

        SET @fechaPartido = CAST(@fechaHoraUTC AS date);

        /* -----------------------------------------------------------------------
           Parámetros de prime time
        ----------------------------------------------------------------------- */
        DECLARE @ptInicio int = ISNULL(
            (SELECT valor FROM Sistema.Parametro WHERE clave = 'PRIME_TIME_INICIO'), 19);
        DECLARE @ptFin    int = ISNULL(
            (SELECT valor FROM Sistema.Parametro WHERE clave = 'PRIME_TIME_FIN'),    23);

        /* -----------------------------------------------------------------------
           Result set:
           Países que tienen al menos una pieza de mercado candidata para este
           partido (campaña vigente, independientemente de si ya está asignada).
           
           Para la conversión de huso horario:
             CAST(@fechaHoraUTC AS datetimeoffset) → produce datetimeoffset con
             offset +00:00 (interpretado luego como UTC con AT TIME ZONE 'UTC').
             AT TIME ZONE p.husoHorario → convierte al huso local del país.
             DATEPART(HOUR, ...) → extrae la hora local.
           
           Los países sin husoHorario se excluyen (no se puede calcular hora local).
        ----------------------------------------------------------------------- */
        ;WITH
        PaisesCandidatos AS (
            SELECT DISTINCT pm.idPais
            FROM Publicidad.PiezaMercado     pm
            JOIN Publicidad.PiezaContenido   pc ON pc.id          = pm.idPieza
            JOIN Publicidad.Campania          c  ON c.idCampania   = pc.idCampania
            WHERE @fechaPartido BETWEEN c.fechaInicio AND c.fechaFin
        ),
        Resultado AS (
            SELECT
                p.id                                        AS idPais,
                p.nombre                                    AS nombrePais,
                p.husoHorario,
                /* Hora local del partido en el huso de este país */
                CAST(
                    CAST(
                        CAST(@fechaHoraUTC AS datetimeoffset)
                        AT TIME ZONE 'UTC'
                        AT TIME ZONE p.husoHorario
                    AS datetimeoffset)
                AS time(0))                                 AS horaLocalPartido,
                /* Hora entera para comparar con prime time */
                DATEPART(HOUR,
                    CAST(
                        CAST(@fechaHoraUTC AS datetimeoffset)
                        AT TIME ZONE 'UTC'
                        AT TIME ZONE p.husoHorario
                    AS datetimeoffset)
                )                                           AS horaEntera
            FROM PaisesCandidatos        pc
            JOIN Torneo.Pais              p  ON p.id = pc.idPais
            WHERE p.husoHorario IS NOT NULL
        )
        SELECT
            r.idPais,
            r.nombrePais,
            r.husoHorario,
            r.horaLocalPartido,
            CAST(
                CASE WHEN r.horaEntera BETWEEN @ptInicio AND @ptFin
                     THEN 1 ELSE 0
                END
            AS bit)                                         AS esPrimeTime
        FROM Resultado r
        ORDER BY
            r.nombrePais;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO

/* =============================================================================
   SP: Publicidad.SimularPrimeTimePorPais
   
   Versión global / simplificada: devuelve TODOS los países de Torneo.Pais
   que tengan husoHorario no nulo, con la hora local del partido especificado
   y si esa hora cae en prime time.
   Útil para ver el impacto horario del partido en todo el mundo sin filtrar
   por piezas de mercado existentes.
   
   Parámetros:
     @idPartido int  — identificador del partido a simular
   
   Columnas devueltas:
     idPais, nombrePais, husoHorario, horaLocalPartido (time), esPrimeTime (bit)
   
   Lanza THROW 50001 si el partido no existe.
   ============================================================================= */
CREATE OR ALTER PROCEDURE Publicidad.SimularPrimeTimePorPais
    @idPartido int
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY

        DECLARE @errores      nvarchar(2000) = N'';
        DECLARE @fechaHoraUTC datetime2(0);

        /* -----------------------------------------------------------------------
           VALIDACIÓN: Existencia del partido
        ----------------------------------------------------------------------- */
        SELECT @fechaHoraUTC = fechaHoraUTC
        FROM Torneo.Partido
        WHERE idPartido = @idPartido;

        IF @fechaHoraUTC IS NULL
            SET @errores = @errores
                + N' | El partido con id=' + CAST(@idPartido AS nvarchar(10))
                + N' no existe.';

        IF @errores <> N''
        BEGIN
            SET @errores = N'SimularPrimeTimePorPais:' + @errores;
            THROW 50001, @errores, 1;
        END;

        /* -----------------------------------------------------------------------
           Parámetros de prime time
        ----------------------------------------------------------------------- */
        DECLARE @ptInicio int = ISNULL(
            (SELECT valor FROM Sistema.Parametro WHERE clave = 'PRIME_TIME_INICIO'), 19);
        DECLARE @ptFin    int = ISNULL(
            (SELECT valor FROM Sistema.Parametro WHERE clave = 'PRIME_TIME_FIN'),    23);

        /* -----------------------------------------------------------------------
           Result set: todos los países con husoHorario, calculando hora local.
           
           Misma lógica de conversión AT TIME ZONE que en SimularPrimeTimePartido.
           Los países con husoHorario NULL se excluyen porque no es posible
           convertir la hora UTC sin una zona válida de sys.time_zone_info.
        ----------------------------------------------------------------------- */
        SELECT
            p.id                                AS idPais,
            p.nombre                            AS nombrePais,
            p.husoHorario,
            /* Hora local del partido (sin fecha ni offset) */
            CAST(
                CAST(
                    CAST(@fechaHoraUTC AS datetimeoffset)
                    AT TIME ZONE 'UTC'
                    AT TIME ZONE p.husoHorario
                AS datetimeoffset)
            AS time(0))                         AS horaLocalPartido,
            /* ¿Cae en la franja de prime time? */
            CAST(
                CASE
                    WHEN DATEPART(HOUR,
                             CAST(
                                 CAST(@fechaHoraUTC AS datetimeoffset)
                                 AT TIME ZONE 'UTC'
                                 AT TIME ZONE p.husoHorario
                             AS datetimeoffset)
                         ) BETWEEN @ptInicio AND @ptFin
                    THEN 1
                    ELSE 0
                END
            AS bit)                             AS esPrimeTime
        FROM Torneo.Pais p
        WHERE p.husoHorario IS NOT NULL
        ORDER BY
            p.nombre;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO
