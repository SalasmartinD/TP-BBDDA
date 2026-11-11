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
               Incluye las funciones que centralizan el cálculo de la hora local
               y del prime time, que también usa 32_SimulPrimeTime.sql.
================================================================================
*/

USE MundialFutbol;
GO

/* =============================================================================
   FN: Publicidad.fn_HoraLocal

   Convierte una fecha-hora UTC a la fecha-hora local de un huso horario
   (nombre válido de sys.time_zone_info) usando AT TIME ZONE.
   Devuelve NULL si el huso horario es NULL.
   ============================================================================= */
CREATE OR ALTER FUNCTION Publicidad.fn_HoraLocal
(
    @fechaHoraUTC datetime2(0),
    @husoHorario  varchar(50)
)
RETURNS datetime2(0)
AS
BEGIN
    RETURN CAST(
        CAST(@fechaHoraUTC AS datetimeoffset)
        AT TIME ZONE 'UTC'
        AT TIME ZONE @husoHorario
    AS datetime2(0));
END;
GO

/* =============================================================================
   FN: Publicidad.fn_EsPrimeTime

   Devuelve 1 si la hora local del huso horario dado cae entre
   PRIME_TIME_INICIO y PRIME_TIME_FIN (parámetros de Sistema.Parametro,
   por defecto 19 a 23, ambos inclusive) y 0 en caso contrario.
   Es el único lugar donde se leen esos parámetros y se compara la hora.
   ============================================================================= */
CREATE OR ALTER FUNCTION Publicidad.fn_EsPrimeTime
(
    @fechaHoraUTC datetime2(0),
    @husoHorario  varchar(50)
)
RETURNS bit
AS
BEGIN
    DECLARE @ptInicio int = ISNULL(
        (SELECT valor FROM Sistema.Parametro WHERE clave = 'PRIME_TIME_INICIO'), 19);
    DECLARE @ptFin    int = ISNULL(
        (SELECT valor FROM Sistema.Parametro WHERE clave = 'PRIME_TIME_FIN'),    23);

    RETURN CASE
               WHEN DATEPART(HOUR, Publicidad.fn_HoraLocal(@fechaHoraUTC, @husoHorario))
                    BETWEEN @ptInicio AND @ptFin
               THEN 1
               ELSE 0
           END;
END;
GO

/* =============================================================================
   SP: Publicidad.AsignarPiezasPartido

   Asigna automáticamente piezas de contenido publicitario a las ubicaciones
   disponibles de un partido dado, usando la siguiente lógica de priorización
   (regla definida y documentada por el grupo, el orden de la consigna es
   orientativo):
     - Criterio 1 (mayor prioridad): la pieza tiene mercado en alguno de los
       dos países que juegan → criterioAplicado = 1
     - Criterio 2: la pieza no cumple el 1 y tiene mercados con PBI per cápita
       cargado; dentro de este criterio se ordena por el mayor PBI de sus
       mercados, de mayor a menor → criterioAplicado = 2
     - Criterio 3: la pieza no cumple el 1 ni el 2 (ningún mercado con PBI
       cargado) y el horario del partido cae en prime time en algún huso
       horario de los países del mercado → criterioAplicado = 3

   criterioAplicado solo se etiqueta cuando la pieza cumple de verdad ese
   criterio: una pieza que no cumple ninguno de los tres no es candidata.
   Desempates, en este orden: mayor PBI, más mercados en prime time para este
   partido y menor idPieza. Así el prime time también influye dentro de un
   mismo criterio.

   Solo se asignan piezas de campañas vigentes en la fecha del partido y que
   no estén ya asignadas a él. Se respeta el límite MAX_ESPACIOS_PARTIDO.

   Parámetros:
     @idPartido int  — identificador del partido a cubrir

   Lanza THROW 50002 en caso de error de negocio:
     - Partido no existe
     - Partido no está en estado 'Programado' o 'En juego'
     - El partido ya alcanzó el máximo de exhibiciones asignadas
     - La fase del partido no tiene tarifas para las ubicaciones libres
     - No hay piezas candidatas que cumplan algún criterio
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
           VALIDACIÓN 3: La fase tiene tarifa para alguna ubicación libre
        ----------------------------------------------------------------------- */
        IF NOT EXISTS (
            SELECT 1
            FROM Publicidad.Tarifa t
            WHERE t.idFase = @idFase
              AND NOT EXISTS (
                  SELECT 1
                  FROM Publicidad.ExhibicionPublicitaria ep
                  WHERE ep.idPartido   = @idPartido
                    AND ep.idUbicacion = t.idUbicacion
              )
        )
        BEGIN
            SET @errores = CONCAT(
                N'No se pudo asignar piezas al partido: | La fase ''',
                (SELECT nombre FROM Torneo.Fase WHERE idFase = @idFase),
                N''' (id=', @idFase,
                N') no tiene tarifas cargadas para las ubicaciones libres del partido id=',
                @idPartido, N'.');
            THROW 50002, @errores, 1;
        END;

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

        /* ── Criterio 3: cantidad de mercados de la pieza en prime time ──
           La conversión a hora local y la comparación con PRIME_TIME_INICIO y
           PRIME_TIME_FIN las hace Publicidad.fn_EsPrimeTime (AT TIME ZONE).
           Requiere que husoHorario sea un nombre válido de sys.time_zone_info.  */
        Criterio3 AS (
            SELECT
                cb.idPieza,
                COUNT(*) AS mercadosPrimeTime
            FROM CandidatasBase          cb
            JOIN Publicidad.PiezaMercado pm ON pm.idPieza = cb.idPieza
            JOIN Torneo.Pais             p  ON p.id       = pm.idPais
            WHERE p.husoHorario IS NOT NULL
              AND Publicidad.fn_EsPrimeTime(@fechaHoraUTC, p.husoHorario) = 1
            GROUP BY cb.idPieza
        ),

        /* ── Piezas con el criterio más favorable calculado y rankeadas ──

           Regla de asignación de criterio (solo se etiqueta si se cumple):
             • Si cumple criterio 1 → criterio = 1 (prioridad máxima)
             • Si NO cumple 1 pero tiene mercados con PBI cargado → criterio = 2
             • Si NO cumple 1 ni 2 pero tiene mercados en prime time → criterio = 3
             • Si no cumple ninguno → la pieza no es candidata y no se asigna.

           Ordenamiento:
             1. criterio ASC          (1 > 2 > 3)
             2. maxPbi DESC           (mayor poder adquisitivo primero)
             3. mercadosPrimeTime DESC (más mercados en prime time primero)
             4. idPieza ASC           (desempate determinístico)                  */
        PiezasRankeadas AS (
            SELECT
                cb.idPieza,
                CASE
                    WHEN c1.idPieza IS NOT NULL THEN CAST(1 AS tinyint)
                    WHEN mp.idPieza IS NOT NULL THEN CAST(2 AS tinyint)
                    ELSE                             CAST(3 AS tinyint)
                END                             AS criterio,
                ISNULL(mp.maxPbi, 0)            AS maxPbi,
                ROW_NUMBER() OVER (
                    ORDER BY
                        CASE
                            WHEN c1.idPieza IS NOT NULL THEN 1
                            WHEN mp.idPieza IS NOT NULL THEN 2
                            ELSE                             3
                        END ASC,
                        ISNULL(mp.maxPbi, 0)    DESC,
                        ISNULL(c3.mercadosPrimeTime, 0) DESC,
                        cb.idPieza              ASC
                )                               AS rn
            FROM CandidatasBase  cb
            LEFT JOIN Criterio1      c1  ON c1.idPieza = cb.idPieza
            LEFT JOIN MaxPbiPorPieza mp  ON mp.idPieza = cb.idPieza
            LEFT JOIN Criterio3      c3  ON c3.idPieza = cb.idPieza
            WHERE c1.idPieza IS NOT NULL
               OR mp.idPieza IS NOT NULL
               OR c3.idPieza IS NOT NULL
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

        /* -----------------------------------------------------------------------
           VALIDACIÓN 4: Se asignó al menos una pieza
           Sin candidatas que cumplan algún criterio el INSERT no inserta filas;
           se informa en vez de terminar en silencio.
        ----------------------------------------------------------------------- */
        IF @@ROWCOUNT = 0
        BEGIN
            SET @errores = CONCAT(
                N'No se pudo asignar piezas al partido: | No hay piezas candidatas para el partido id=',
                @idPartido,
                N': ninguna pieza de campañas vigentes el ',
                CONVERT(nvarchar(10), CAST(@fechaHoraUTC AS date), 23),
                N' cumple algún criterio (mercado en un país que juega, PBI cargado o prime time).');
            THROW 50002, @errores, 1;
        END;

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
