/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 09/11/2026

 Objetivo    : Carga base de partidos: los 31 partidos del Mundial 2026 jugados
               entre las 16 selecciones cargadas (24 de fase de grupos y 7 de
               eliminación directa), con resultado final y asistencia.
               La hora se guarda en UTC: hora local de la sede menos su
               desfasaje UTC de ese día (horario de verano incluido); el
               comentario de cada fila muestra la hora local original.

 Fuente      : Copa Mundial de la FIFA 2026 (datos reales). Wikipedia en inglés,
               artículos del torneo, de los grupos H, I, J y L, de la fase
               eliminatoria, de los planteles y de cada selección (versión al
               15/06/2026 para los cuerpos técnicos), consultados el 09/11/2026.

 Uso         : Todas las altas pasan por los SP del ABM (10a/10b). Cada alta
               verifica antes si el registro ya existe, así que el script se
               puede ejecutar varias veces sin duplicar datos.
================================================================================
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

DROP TABLE IF EXISTS #partidos;
CREATE TABLE #partidos (n int IDENTITY(1,1) PRIMARY KEY, nroPartidoOficial int, fase int,
                        seleccionLocal char(3), seleccionVisitante char(3), nombreEstadio nvarchar(80),
                        ciudad nvarchar(60), fechaHoraUTC datetime2(0), cantPublico int,
                        golLocal tinyint, golVisitante tinyint);
INSERT INTO #partidos (nroPartidoOficial, fase, seleccionLocal, seleccionVisitante, nombreEstadio, ciudad, fechaHoraUTC, cantPublico, golLocal, golVisitante) VALUES
    (13, 1, N'KSA', N'URU', N'Hard Rock Stadium', N'Miami Gardens', N'2026-06-15 22:00', 62764, 1, 1),  -- 18:00 local (UTC-4)
    (14, 1, N'ESP', N'CPV', N'Mercedes-Benz Stadium', N'Atlanta', N'2026-06-15 16:00', 67640, 0, 0),  -- 12:00 local (UTC-4)
    (17, 1, N'FRA', N'SEN', N'MetLife Stadium', N'East Rutherford', N'2026-06-16 19:00', 80545, 3, 1),  -- 15:00 local (UTC-4)
    (18, 1, N'IRQ', N'NOR', N'Gillette Stadium', N'Foxborough', N'2026-06-16 22:00', 63106, 1, 4),  -- 18:00 local (UTC-4)
    (19, 1, N'ARG', N'ALG', N'Arrowhead Stadium', N'Kansas City', N'2026-06-17 01:00', 69045, 3, 0),  -- 20:00 local (UTC-5)
    (20, 1, N'AUT', N'JOR', N'Levi''s Stadium', N'Santa Clara', N'2026-06-17 04:00', 68527, 3, 1),  -- 21:00 local (UTC-7)
    (21, 1, N'GHA', N'PAN', N'BMO Field', N'Toronto', N'2026-06-17 23:00', 42942, 1, 0),  -- 19:00 local (UTC-4)
    (22, 1, N'ENG', N'CRO', N'AT&T Stadium', N'Arlington', N'2026-06-17 20:00', 70389, 4, 2),  -- 15:00 local (UTC-5)
    (37, 1, N'URU', N'CPV', N'Hard Rock Stadium', N'Miami Gardens', N'2026-06-21 22:00', 64003, 2, 2),  -- 18:00 local (UTC-4)
    (38, 1, N'ESP', N'KSA', N'Mercedes-Benz Stadium', N'Atlanta', N'2026-06-21 16:00', 68239, 4, 0),  -- 12:00 local (UTC-4)
    (41, 1, N'NOR', N'SEN', N'MetLife Stadium', N'East Rutherford', N'2026-06-23 00:00', 80663, 3, 2),  -- 20:00 local (UTC-4)
    (42, 1, N'FRA', N'IRQ', N'Lincoln Financial Field', N'Philadelphia', N'2026-06-22 21:00', 68324, 3, 0),  -- 17:00 local (UTC-4)
    (43, 1, N'ARG', N'AUT', N'AT&T Stadium', N'Arlington', N'2026-06-22 17:00', 70649, 2, 0),  -- 12:00 local (UTC-5)
    (44, 1, N'JOR', N'ALG', N'Levi''s Stadium', N'Santa Clara', N'2026-06-23 03:00', 68371, 1, 2),  -- 20:00 local (UTC-7)
    (45, 1, N'ENG', N'GHA', N'Gillette Stadium', N'Foxborough', N'2026-06-23 20:00', 63983, 0, 0),  -- 16:00 local (UTC-4)
    (46, 1, N'PAN', N'CRO', N'BMO Field', N'Toronto', N'2026-06-23 23:00', 43036, 0, 1),  -- 19:00 local (UTC-4)
    (61, 1, N'NOR', N'FRA', N'Gillette Stadium', N'Foxborough', N'2026-06-26 19:00', 64146, 1, 4),  -- 15:00 local (UTC-4)
    (62, 1, N'SEN', N'IRQ', N'BMO Field', N'Toronto', N'2026-06-26 19:00', 43036, 5, 0),  -- 15:00 local (UTC-4)
    (65, 1, N'CPV', N'KSA', N'NRG Stadium', N'Houston', N'2026-06-27 00:00', 68278, 0, 0),  -- 19:00 local (UTC-5)
    (66, 1, N'URU', N'ESP', N'Estadio Akron', N'Zapopan', N'2026-06-27 00:00', 45065, 0, 1),  -- 18:00 local (UTC-6)
    (67, 1, N'PAN', N'ENG', N'MetLife Stadium', N'East Rutherford', N'2026-06-27 21:00', 80663, 0, 2),  -- 17:00 local (UTC-4)
    (68, 1, N'CRO', N'GHA', N'Lincoln Financial Field', N'Philadelphia', N'2026-06-27 21:00', 68324, 2, 1),  -- 17:00 local (UTC-4)
    (69, 1, N'ALG', N'AUT', N'Arrowhead Stadium', N'Kansas City', N'2026-06-28 02:00', 69045, 3, 3),  -- 21:00 local (UTC-5)
    (70, 1, N'JOR', N'ARG', N'AT&T Stadium', N'Arlington', N'2026-06-28 02:00', 70649, 1, 3),  -- 21:00 local (UTC-5)
    (84, 2, N'ESP', N'AUT', N'SoFi Stadium', N'Inglewood', N'2026-07-02 19:00', 70492, 3, 0),  -- 12:00 local (UTC-7)
    (86, 2, N'ARG', N'CPV', N'Hard Rock Stadium', N'Miami Gardens', N'2026-07-03 22:00', 64478, 3, 2),  -- 18:00 local (UTC-4), con alargue
    (99, 4, N'NOR', N'ENG', N'Hard Rock Stadium', N'Miami Gardens', N'2026-07-11 21:00', 64478, 1, 2),  -- 17:00 local (UTC-4), con alargue
    (101, 5, N'FRA', N'ESP', N'AT&T Stadium', N'Arlington', N'2026-07-14 19:00', 70176, 0, 2),  -- 14:00 local (UTC-5)
    (102, 5, N'ENG', N'ARG', N'Mercedes-Benz Stadium', N'Atlanta', N'2026-07-15 19:00', 68239, 1, 2),  -- 15:00 local (UTC-4)
    (103, 6, N'FRA', N'ENG', N'Hard Rock Stadium', N'Miami Gardens', N'2026-07-18 21:00', 64478, 4, 6),  -- 17:00 local (UTC-4)
    (104, 7, N'ESP', N'ARG', N'MetLife Stadium', N'East Rutherford', N'2026-07-19 19:00', 80663, 1, 0);  -- 15:00 local (UTC-4), con alargue

DECLARE @nro int, @fase int, @local int, @visit int, @sede int, @fecha datetime2(0),
        @publico int, @golLocal tinyint, @golVisit tinyint;
DECLARE @n int = 1, @max int = (SELECT MAX(n) FROM #partidos);
WHILE @n <= @max
BEGIN
    SELECT @nro = p.nroPartidoOficial, @fase = p.fase, @local = sl.id, @visit = sv.id, @sede = s.idSede,
           @fecha = p.fechaHoraUTC, @publico = p.cantPublico, @golLocal = p.golLocal, @golVisit = p.golVisitante
    FROM #partidos p
    JOIN Equipos.Seleccion sl ON sl.abreviacion = p.seleccionLocal
    JOIN Equipos.Seleccion sv ON sv.abreviacion = p.seleccionVisitante
    JOIN Torneo.Sede s ON s.nombreEstadio = p.nombreEstadio AND s.ciudad = p.ciudad
    WHERE p.n = @n;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM Torneo.Partido WHERE nroPartidoOficial = @nro)
            EXEC Torneo.Partido_Alta @idSede = @sede, @idSeleccionLocal = @local, @idSeleccionVisitante = @visit,
                 @fase = @fase, @fechaHoraUTC = @fecha, @estado = 'Finalizado', @nroPartidoOficial = @nro,
                 @cantPublico = @publico, @golLocal = @golLocal, @golVisitante = @golVisit;
    END TRY
    BEGIN CATCH
        PRINT 'Error al cargar el partido de la fila ' + CAST(@n AS varchar(10)) + ' de #partidos.';
        THROW;
    END CATCH;
    SET @n += 1;
END;
GO

-- Resumen de la carga
SELECT (SELECT COUNT(*) FROM Torneo.Partido) AS partidos;
GO
