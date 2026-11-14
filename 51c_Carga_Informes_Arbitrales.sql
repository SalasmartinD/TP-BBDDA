/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel - 45066788
               Salas, Martín Daniel - 45205702
               Zito Padró, Ezequiel Nehuén - 46097917
 Fecha       : 11/11/2026

 Objetivo    : Carga de datos de Persona 2 (parte 3 de 3): informes arbitrales
               de los 31 partidos.
               - Un informe general (esSancion = 0) por partido, a nombre del
                 árbitro Principal designado, con la fecha UTC del partido.
               - Una sanción (esSancion = 1, con detalle) por cada partido en
                 que hubo una expulsión, a nombre del Principal.

 Orden       : Corre después de 51b (necesita el cuerpo arbitral y las
               tarjetas) y antes de 53.

 Uso         : Todas las altas pasan por Arbitraje.InformeArbitral_Alta (11a).
               Cada alta verifica antes si ya existe un informe del mismo tipo
               para ese partido y árbitro: el script se puede ejecutar varias
               veces, incluso después de que 53 cerró los partidos, sin
               duplicar datos.
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

SET NOCOUNT ON;
GO

DROP TABLE IF EXISTS #informes;
CREATE TABLE #informes (n int IDENTITY(1,1) PRIMARY KEY, idPartido int NOT NULL, idArbitro int NOT NULL,
                        fecha date NOT NULL, esSancion bit NOT NULL, detalle nvarchar(500) NULL);

-- Informe general de cada partido que todavía no lo tiene (el SP no admite partidos Programados)
INSERT INTO #informes (idPartido, idArbitro, fecha, esSancion, detalle)
SELECT p.idPartido, ca.idArbitro, CAST(p.fechaHoraUTC AS date), 0,
       N'Informe general del partido nro ' + CAST(p.nroPartidoOficial AS nvarchar(10)) + N' ('
       + sl.abreviacion + N'-' + sv.abreviacion + N'): '
       + CAST((SELECT COUNT(*) FROM Eventos.Gol g WHERE g.idPartido = p.idPartido) AS nvarchar(10)) + N' goles y '
       + CAST((SELECT COUNT(*) FROM Eventos.Tarjeta t WHERE t.idPartido = p.idPartido) AS nvarchar(10))
       + N' tarjetas; sin incidentes de orden en el estadio.'
FROM Torneo.Partido p
JOIN Arbitraje.cuerpoArbitral ca ON ca.idPartido = p.idPartido AND ca.rol = 'Principal'
JOIN Equipos.Seleccion sl        ON sl.id = p.idSeleccionLocal
JOIN Equipos.Seleccion sv        ON sv.id = p.idSeleccionVisitante
WHERE p.estado <> 'Programado'
  AND NOT EXISTS (SELECT 1 FROM Arbitraje.InformeArbitral i
                  WHERE i.idPartido = p.idPartido AND i.idArbitro = ca.idArbitro AND i.esSancion = 0)
ORDER BY p.fechaHoraUTC, p.idPartido;

-- Sanción por cada partido con expulsión que todavía no la tiene; el detalle nombra a los expulsados
INSERT INTO #informes (idPartido, idArbitro, fecha, esSancion, detalle)
SELECT p.idPartido, ca.idArbitro, CAST(p.fechaHoraUTC AS date), 1,
       N'Expulsión informada en el partido nro ' + CAST(p.nroPartidoOficial AS nvarchar(10)) + N': ' + exp.detalle
FROM Torneo.Partido p
JOIN Arbitraje.cuerpoArbitral ca ON ca.idPartido = p.idPartido AND ca.rol = 'Principal'
CROSS APPLY (SELECT STRING_AGG(CAST(j.apellido + N' (' + s.abreviacion + N'), minuto ' + CAST(t.minuto AS nvarchar(10))
                                + N', ' + LOWER(t.tipoRoja) AS nvarchar(max)), N'; ')
                    WITHIN GROUP (ORDER BY t.idTarjeta) AS detalle
             FROM Eventos.Tarjeta t
             JOIN Equipos.Jugador j            ON j.id = t.idJugador
             JOIN Eventos.FormacionPartido fp  ON fp.idPartido = t.idPartido AND fp.idJugador = t.idJugador
             JOIN Equipos.Seleccion s          ON s.id = fp.idSeleccion
             WHERE t.idPartido = p.idPartido AND t.color = 'R') exp
WHERE p.estado <> 'Programado'
  AND exp.detalle IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM Arbitraje.InformeArbitral i
                  WHERE i.idPartido = p.idPartido AND i.idArbitro = ca.idArbitro AND i.esSancion = 1)
ORDER BY p.fechaHoraUTC, p.idPartido;

DECLARE @idPartido int, @idArbitro int, @fecha date, @esSancion bit, @detalle nvarchar(500);
DECLARE @n int = 1, @max int = (SELECT ISNULL(MAX(n), 0) FROM #informes);
WHILE @n <= @max
BEGIN
    SELECT @idPartido = idPartido, @idArbitro = idArbitro, @fecha = fecha, @esSancion = esSancion, @detalle = detalle
    FROM #informes
    WHERE n = @n;
    BEGIN TRY
        EXEC Arbitraje.InformeArbitral_Alta @idPartido = @idPartido, @idArbitro = @idArbitro, @fecha = @fecha,
             @esSancion = @esSancion, @detalle = @detalle;
    END TRY
    BEGIN CATCH
        PRINT 'Error al cargar el informe de la fila ' + CAST(@n AS varchar(10)) + ' de #informes.';
        THROW;
    END CATCH;
    SET @n += 1;
END;
GO

/* =============================================================================
   RESUMEN DE LA CARGA
   ============================================================================= */
SELECT COUNT(*) AS informes,
       SUM(CASE WHEN esSancion = 0 THEN 1 ELSE 0 END) AS generales,
       SUM(CASE WHEN esSancion = 1 THEN 1 ELSE 0 END) AS sanciones,
       COUNT(DISTINCT idPartido) AS partidosConInforme
FROM Arbitraje.InformeArbitral;

-- Muestra de Arbitraje.vw_HistorialArbitro (31): los partidos con sanción y los primeros partidos del torneo
SELECT arbitro, paisArbitro, idPartido, fase, seleccionLocal, seleccionVisitante, rol,
       amarillas, rojas, cantInformes, cantSanciones, detalleInformes
FROM Arbitraje.vw_HistorialArbitro
WHERE rol = 'Principal' AND (cantSanciones > 0 OR idPartido <= 4)
ORDER BY fechaHoraUTC, idPartido;
GO
