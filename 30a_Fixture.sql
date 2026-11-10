/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 09/11/2026

 Objetivo    : Consulta del fixture del torneo:
               - Torneo.vw_Fixture: todos los partidos con la fase, la sede,
                 las selecciones, el resultado, la hora en UTC y la hora local
                 de la sede.
               - Torneo.ConsultarFixture: la misma consulta con filtros
                 opcionales por sede, fase, selección y fecha, y una columna
                 extra con la hora en el huso horario que elija quien consulta.

 Criterios:
 - La hora local sale de la hora UTC guardada en Torneo.Partido con
   AT TIME ZONE, usando el huso de la sede (nombre de zona de Windows). Así
   se aplica el horario de verano que corresponde a la fecha de cada partido.
 - El filtro por fecha es por la fecha local de la sede: un partido jugado a
   las 22:00 en Los Ángeles el 15/06 es del 15/06 aunque en UTC ya sea el 16.
 - El filtro por selección incluye los partidos en que juega de local o de
   visitante.
 - Los filtros en NULL no filtran. Un filtro que no encuentra partidos
   devuelve cero filas, no un error.
 - Los datos de entrada se validan con el patrón de los SP (todos los errores
   juntos en un único THROW 50001).
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

/* =============================================================================
   1. VISTA: Torneo.vw_Fixture
   ============================================================================= */
CREATE OR ALTER VIEW Torneo.vw_Fixture
AS
SELECT p.idPartido,
       p.nroPartidoOficial,
       f.idFase,
       f.nombre                 AS fase,
       f.orden                  AS ordenFase,
       p.estado,
       s.idSede,
       s.nombreEstadio          AS sede,
       s.ciudad,
       ps.nombre                AS paisSede,
       s.husoHorario            AS husoHorarioSede,
       p.fechaHoraUTC,
       loc.fechaHoraLocal,
       CAST(loc.fechaHoraLocal AS date)     AS fechaLocal,
       CAST(loc.fechaHoraLocal AS time(0))  AS horaLocal,
       p.idSeleccionLocal,
       pl.nombre                AS seleccionLocal,
       sl.abreviacion           AS abreviacionLocal,
       p.idSeleccionVisitante,
       pv.nombre                AS seleccionVisitante,
       sv.abreviacion           AS abreviacionVisitante,
       p.golLocal,
       p.golVisitante,
       p.cantPublico
FROM Torneo.Partido p
JOIN Torneo.Fase f        ON f.idFase = p.fase
JOIN Torneo.Sede s        ON s.idSede = p.idSede
JOIN Torneo.Pais ps       ON ps.id = s.idPais
JOIN Equipos.Seleccion sl ON sl.id = p.idSeleccionLocal
JOIN Torneo.Pais pl       ON pl.id = sl.idPais
JOIN Equipos.Seleccion sv ON sv.id = p.idSeleccionVisitante
JOIN Torneo.Pais pv       ON pv.id = sv.idPais
-- La hora UTC se marca como UTC (offset 0) y se convierte al huso de la sede
CROSS APPLY (SELECT p.fechaHoraUTC AT TIME ZONE 'UTC' AT TIME ZONE s.husoHorario AS fechaHoraLocal) loc;
GO

/* =============================================================================
   2. SP: Torneo.ConsultarFixture
   Devuelve las columnas de la vista más fechaHoraConsulta: la hora del
   partido en @husoHorarioConsulta (NULL si no se indica un huso). Las columnas
   se listan a mano, así una columna nueva en la vista no cambia lo que
   devuelve el SP.
   ============================================================================= */
CREATE OR ALTER PROCEDURE Torneo.ConsultarFixture
    @idSede               int         = NULL,
    @idFase               int         = NULL,
    @idSeleccion          int         = NULL,
    @fechaDesde           date        = NULL,
    @fechaHasta           date        = NULL,
    @husoHorarioConsulta  varchar(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @husoHorarioConsulta = NULLIF(LTRIM(RTRIM(@husoHorarioConsulta)), '');

    IF @idSede IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Torneo.Sede WHERE idSede = @idSede)
        SET @errores += CHAR(10) + N'- La sede no existe.';

    IF @idFase IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = @idFase)
        SET @errores += CHAR(10) + N'- La fase no existe.';

    IF @idSeleccion IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE id = @idSeleccion)
        SET @errores += CHAR(10) + N'- La selección no existe.';

    IF @fechaDesde > @fechaHasta
        SET @errores += CHAR(10) + N'- La fecha desde no puede ser posterior a la fecha hasta.';

    IF @husoHorarioConsulta IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM sys.time_zone_info WHERE name = @husoHorarioConsulta)
        SET @errores += CHAR(10) + N'- El huso horario de consulta no es un nombre válido de sys.time_zone_info.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo consultar el fixture:' + @errores;
        THROW 50001, @errores, 1;
    END;

    SELECT v.idPartido, v.nroPartidoOficial, v.idFase, v.fase, v.ordenFase,
           v.estado, v.idSede, v.sede, v.ciudad, v.paisSede, v.husoHorarioSede,
           v.fechaHoraUTC, v.fechaHoraLocal, v.fechaLocal, v.horaLocal,
           v.idSeleccionLocal, v.seleccionLocal, v.abreviacionLocal, v.idSeleccionVisitante,
           v.seleccionVisitante, v.abreviacionVisitante, v.golLocal, v.golVisitante,
           v.cantPublico,
           CASE WHEN @husoHorarioConsulta IS NULL THEN NULL
                ELSE v.fechaHoraUTC AT TIME ZONE 'UTC' AT TIME ZONE @husoHorarioConsulta
           END AS fechaHoraConsulta
    FROM Torneo.vw_Fixture v
    WHERE (@idSede IS NULL OR v.idSede = @idSede)
      AND (@idFase IS NULL OR v.idFase = @idFase)
      AND (@idSeleccion IS NULL OR @idSeleccion IN (v.idSeleccionLocal, v.idSeleccionVisitante))
      AND (@fechaDesde IS NULL OR v.fechaLocal >= @fechaDesde)
      AND (@fechaHasta IS NULL OR v.fechaLocal <= @fechaHasta)
    ORDER BY v.fechaHoraUTC, v.idPartido;
END
GO
