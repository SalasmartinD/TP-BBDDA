/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 09/11/2026

 Objetivo    : Stored Procedure de negocio para asignación automática de piezas
               publicitarias a un partido, aplicando criterios de prioridad:
               1) Países que juegan, 2) PBI per cápita, 3) Prime time local.
               Inserta en Publicidad.ExhibicionPublicitaria con estado 'Propuesta'.
               Implementado íntegramente con operaciones basadas en conjuntos
               (CTEs, ROW_NUMBER(), INSERT...SELECT). Sin cursores.
================================================================================
*/

USE MundialFutbol;
GO

/* =============================================================================
   SP: Publicidad.AsignarPiezasPartido
   
   Asigna automáticamente piezas de contenido publicitario a las ubicaciones
   disponibles de un partido dado, usando la siguiente lógica de priorización:
     - Criterio 1 (mayor prioridad): la pieza tiene mercado en alguno de los
       dos países que juegan → criterioAplicado = 1
     - Criterio 2: la pieza tiene mercados con el mayor PBI per cápita
       (dentro de este criterio se ordena por MAX(pbiPerCapita) DESC)
       → criterioAplicado = 2
     - Criterio 3: el horario del partido cae en prime time (PRIME_TIME_INICIO
       a PRIME_TIME_FIN) en algún huso horario de los países del mercado
       → criterioAplicado = 3
   
   Solo se asignan piezas de campañas vigentes en la fecha del partido y que
   no estén ya asignadas a él. Se respeta el límite MAX_ESPACIOS_PARTIDO.
   
   Parámetros:
     @idPartido int  — identificador del partido a cubrir
   
   Lanza THROW 50002 en caso de error de negocio:
     - Partido no existe
     - Partido no está en estado 'Programado' o 'En juego'
     - El partido ya alcanzó el máximo de exhibiciones asignadas
   ============================================================================= */
CREATE OR ALTER PROCEDURE Publicidad.AsignarPiezasPartido
    @idPartido int
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        /* -----------------------------------------------------------------------
           Variables de cabecera del partido y parámetros de configuración
        ----------------------------------------------------------------------- */
        DECLARE @errores        nvarchar(2000) = N'';
        DECLARE @estadoPartido  varchar(15);
        DECLARE @idFase         int;
        DECLARE @fechaHoraUTC   datetime2(0);
        DECLARE @idPaisLocal    int;
        DECLARE @idPaisVis      int;

        -- Parámetros de prime time (horas enteras, en el huso horario local del mercado)
        DECLARE @ptInicio int = ISNULL(
            (SELECT valor FROM Sistema.Parametro WHERE clave = 'PRIME_TIME_INICIO'), 19);
        DECLARE @ptFin    int = ISNULL(
            (SELECT valor FROM Sistema.Parametro WHERE clave = 'PRIME_TIME_FIN'),    23);

        -- Máximo de espacios publicitarios por partido
        DECLARE @maxEspacios int = ISNULL(
            (SELECT valor FROM Sistema.Parametro WHERE clave = 'MAX_ESPACIOS_PARTIDO'), 4);

        /* -----------------------------------------------------------------------
           VALIDACIÓN 1: Existencia y estado del partido
        ----------------------------------------------------------------------- */
        SELECT
            @estadoPartido  = p.estado,
            @idFase         = p.fase,
            @fechaHoraUTC   = p.fechaHoraUTC,
            @idPaisLocal    = sL.idPais,
            @idPaisVis      = sV.idPais
        FROM Torneo.Partido       p
        JOIN Equipos.Seleccion    sL ON sL.id = p.idSeleccionLocal
        JOIN Equipos.Seleccion    sV ON sV.id = p.idSeleccionVisitante
        WHERE p.idPartido = @idPartido;

        IF @estadoPartido IS NULL
            SET @errores = @errores
                + N' | El partido con id=' + CAST(@idPartido AS nvarchar(10))
                + N' no existe.';
        ELSE IF @estadoPartido NOT IN ('Programado', 'En juego')
            SET @errores = @errores
                + N' | El partido id=' + CAST(@idPartido AS nvarchar(10))
                + N' está en estado ''' + @estadoPartido
                + N'''. Solo se permite asignar en Programado o En juego.';

        IF @errores <> N''
        BEGIN
            SET @errores = N'No se pudo asignar piezas al partido:' + @errores;
            THROW 50002, @errores, 1;
        END;

        /* -----------------------------------------------------------------------
           VALIDACIÓN 2: Límite de exhibiciones ya asignadas
        ----------------------------------------------------------------------- */
        DECLARE @exhibicionesActuales int = (
            SELECT COUNT(*)
            FROM Publicidad.ExhibicionPublicitaria
            WHERE idPartido = @idPartido
        );

        IF @exhibicionesActuales >= @maxEspacios
        BEGIN
            SET @errores = N'No se pudo asignar piezas al partido: | El partido id='
                + CAST(@idPartido AS nvarchar(10))
                + N' ya tiene el máximo de ' + CAST(@maxEspacios AS nvarchar(10))
                + N' exhibiciones asignadas.';
            THROW 50002, @errores, 1;
        END;

        DECLARE @espaciosLibres int = @maxEspacios - @exhibicionesActuales;

        /* -----------------------------------------------------------------------
           Asignación basada en conjuntos
           
           Estrategia:
             1. CTE "UbicacionesLibres": ubicaciones con tarifa para esta fase que
                aún no tienen exhibición en el partido. Se les asigna un número de
                fila (rn) para emparejarlas con las piezas.
             
             2. CTEs de criterio: identifican qué piezas candidatas (campaña vigente,
                no asignadas todavía al partido) cumplen cada criterio.
             
             3. CTE "PiezasRankeadas": une las candidatas con sus criterios, calcula
                el criterio más favorable por pieza y asigna rn con ROW_NUMBER().
             
             4. INSERT ... SELECT: cruza las piezas (rn 1..N) con las ubicaciones
                (rn 1..N) mediante igualdad de número de fila, insertando solo
                los pares que tengan tarifa disponible.
        ----------------------------------------------------------------------- */
        ;WITH

        /* ── Ubicaciones con tarifa para la fase, aún libres en este partido ── */
        UbicacionesLibres AS (
            SELECT
                t.idUbicacion,
                t.montoUSD,
                ROW_NUMBER() OVER (ORDER BY t.idUbicacion) AS rn
            FROM Publicidad.Tarifa t
            WHERE t.idFase = @idFase
              AND NOT EXISTS (
                  SELECT 1
                  FROM Publicidad.ExhibicionPublicitaria ep
                  WHERE ep.idPartido   = @idPartido
                    AND ep.idUbicacion = t.idUbicacion
              )
        ),

        /* ── Piezas de campañas vigentes no asignadas todavía a este partido ── */
        CandidatasBase AS (
            SELECT
                pc.id        AS idPieza,
                pc.idCampania
            FROM Publicidad.PiezaContenido   pc
            JOIN Publicidad.Campania         c  ON c.idCampania = pc.idCampania
            WHERE CAST(@fechaHoraUTC AS date) BETWEEN c.fechaInicio AND c.fechaFin
              AND NOT EXISTS (
                  SELECT 1
                  FROM Publicidad.ExhibicionPublicitaria ep
                  WHERE ep.idPartido = @idPartido
                    AND ep.idPieza   = pc.id
              )
        ),

        /* ── Criterio 1: pieza con mercado en alguno de los dos países que juegan ── */
        Criterio1 AS (
            SELECT DISTINCT cb.idPieza
            FROM CandidatasBase          cb
            JOIN Publicidad.PiezaMercado pm ON pm.idPieza = cb.idPieza
            WHERE pm.idPais IN (@idPaisLocal, @idPaisVis)
        ),

        /* ── Criterio 2: máximo PBI per cápita entre los países del mercado ── */
        MaxPbiPorPieza AS (
            SELECT
                cb.idPieza,
                MAX(p.pbiPerCapita) AS maxPbi
            FROM CandidatasBase          cb
            JOIN Publicidad.PiezaMercado pm ON pm.idPieza = cb.idPieza
            JOIN Torneo.Pais             p  ON p.id       = pm.idPais
            WHERE p.pbiPerCapita IS NOT NULL
            GROUP BY cb.idPieza
        ),

        /* ── Criterio 3: horario del partido cae en prime time en algún mercado ──
           Convierte @fechaHoraUTC a datetimeoffset 'UTC' y luego al huso local
           del país de mercado usando AT TIME ZONE.
           Requiere que husoHorario sea un nombre válido de sys.time_zone_info.  */
        Criterio3 AS (
            SELECT DISTINCT cb.idPieza
            FROM CandidatasBase          cb
            JOIN Publicidad.PiezaMercado pm ON pm.idPieza = cb.idPieza
            JOIN Torneo.Pais             p  ON p.id       = pm.idPais
            WHERE p.husoHorario IS NOT NULL
              AND DATEPART(HOUR,
                      CAST(
                          CAST(@fechaHoraUTC AS datetimeoffset)
                          AT TIME ZONE 'UTC'
                          AT TIME ZONE p.husoHorario
                      AS datetimeoffset)
                  ) BETWEEN @ptInicio AND @ptFin
        ),

        /* ── Piezas con el criterio más favorable calculado y rankeadas ──
           
           Regla de asignación de criterio:
             • Si cumple criterio 1 → criterio = 1 (prioridad máxima)
             • Si NO cumple 1 pero tiene datos de PBI → criterio = 2
             • Si NO cumple 1 ni 2 pero cumple prime time → criterio = 3
             • Sin ningún criterio → el SP no las descarta, pero quedarán al final
               del ranking y solo se usan si hay ubicaciones sobrantes.
           
           Ordenamiento:
             1. criterio ASC          (1 > 2 > 3)
             2. maxPbi DESC           (dentro de criterio 2)
             3. idPieza ASC           (desempate determinístico)                  */
        PiezasRankeadas AS (
            SELECT
                cb.idPieza,
                CASE
                    WHEN c1.idPieza IS NOT NULL THEN CAST(1 AS tinyint)
                    WHEN mp.idPieza IS NOT NULL THEN CAST(2 AS tinyint)
                    WHEN c3.idPieza IS NOT NULL THEN CAST(3 AS tinyint)
                    ELSE                             CAST(3 AS tinyint)
                END                             AS criterio,
                ISNULL(mp.maxPbi, 0)            AS maxPbi,
                ROW_NUMBER() OVER (
                    ORDER BY
                        CASE
                            WHEN c1.idPieza IS NOT NULL THEN 1
                            WHEN mp.idPieza IS NOT NULL THEN 2
                            WHEN c3.idPieza IS NOT NULL THEN 3
                            ELSE                             3
                        END ASC,
                        ISNULL(mp.maxPbi, 0)    DESC,
                        cb.idPieza              ASC
                )                               AS rn
            FROM CandidatasBase  cb
            LEFT JOIN Criterio1      c1  ON c1.idPieza = cb.idPieza
            LEFT JOIN MaxPbiPorPieza mp  ON mp.idPieza = cb.idPieza
            LEFT JOIN Criterio3      c3  ON c3.idPieza = cb.idPieza
        )

        /* ── INSERT final: empareja piezas y ubicaciones por número de fila ──
           TOP (@espaciosLibres) garantiza que no se supere el límite configurado. */
        INSERT INTO Publicidad.ExhibicionPublicitaria
            (idPartido, idUbicacion, idPieza, criterioAplicado, estado, montoUSD)
        SELECT TOP (@espaciosLibres)
            @idPartido,
            u.idUbicacion,
            pr.idPieza,
            pr.criterio,
            'Propuesta',
            u.montoUSD
        FROM PiezasRankeadas    pr
        JOIN UbicacionesLibres  u   ON u.rn = pr.rn
        ORDER BY pr.rn;         -- garantiza el orden de inserción esperado

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
