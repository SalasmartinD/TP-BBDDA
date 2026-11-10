/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 09/11/2026

 Objetivo    : Cierre de los 31 partidos cargados por 50c: registra el
               resultado final y la asistencia de cada uno con
               Torneo.RegistrarResultado (20a).

 Orden       : Corre al final, después de 50c y de las cargas de Persona 2 y 3
               (51, 52), y por eso lleva el número 53: en orden numérico los
               partidos se cierran recién cuando ya tienen formaciones y goles.
               50c crea los partidos Programados porque
               Eventos.FormacionPartido_Alta no acepta formaciones en partidos
               finalizados; recién con las formaciones y los goles cargados se
               cierran. Si los goles de 51 no coinciden con estos resultados,
               RegistrarResultado rechaza el cierre y lo informa. Sin goles
               cargados, el script también funciona.

 Fuente      : Copa Mundial de la FIFA 2026 (datos reales). Wikipedia en inglés,
               artículos de los grupos H, I, J y L y de la fase eliminatoria,
               consultados el 09/11/2026. Cada partido se identifica por su
               nroPartidoOficial.

 Uso         : Cada cierre verifica antes si el partido ya está Finalizado, así
               que el script se puede ejecutar varias veces.
================================================================================
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

DROP TABLE IF EXISTS #resultados;
CREATE TABLE #resultados (n int IDENTITY(1,1) PRIMARY KEY, nroPartidoOficial int, golLocal tinyint,
                          golVisitante tinyint, cantPublico int);
INSERT INTO #resultados (nroPartidoOficial, golLocal, golVisitante, cantPublico) VALUES
    (13, 1, 1, 62764),
    (14, 0, 0, 67640),
    (17, 3, 1, 80545),
    (18, 1, 4, 63106),
    (19, 3, 0, 69045),
    (20, 3, 1, 68527),
    (21, 1, 0, 42942),
    (22, 4, 2, 70389),
    (37, 2, 2, 64003),
    (38, 4, 0, 68239),
    (41, 3, 2, 80663),
    (42, 3, 0, 68324),
    (43, 2, 0, 70649),
    (44, 1, 2, 68371),
    (45, 0, 0, 63983),
    (46, 0, 1, 43036),
    (61, 1, 4, 64146),
    (62, 5, 0, 43036),
    (65, 0, 0, 68278),
    (66, 0, 1, 45065),
    (67, 0, 2, 80663),
    (68, 2, 1, 68324),
    (69, 3, 3, 69045),
    (70, 1, 3, 70649),
    (84, 3, 0, 70492),
    (86, 3, 2, 64478),
    (99, 1, 2, 64478),
    (101, 0, 2, 70176),
    (102, 1, 2, 68239),
    (103, 4, 6, 64478),
    (104, 1, 0, 80663);

DECLARE @idPartido int, @golLocal tinyint, @golVisit tinyint, @publico int;
DECLARE @n int = 1, @max int = (SELECT MAX(n) FROM #resultados);
WHILE @n <= @max
BEGIN
    SELECT @idPartido = p.idPartido, @golLocal = r.golLocal, @golVisit = r.golVisitante, @publico = r.cantPublico
    FROM #resultados r
    JOIN Torneo.Partido p ON p.nroPartidoOficial = r.nroPartidoOficial
    WHERE r.n = @n;
    BEGIN TRY
        IF @idPartido IS NOT NULL AND EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido AND estado <> 'Finalizado')
            EXEC Torneo.RegistrarResultado @idPartido = @idPartido, @golLocal = @golLocal,
                 @golVisitante = @golVisit, @cantPublico = @publico;
    END TRY
    BEGIN CATCH
        PRINT 'Error al cerrar el partido de la fila ' + CAST(@n AS varchar(10)) + ' de #resultados.';
        THROW;
    END CATCH;
    SET @idPartido = NULL;
    SET @n += 1;
END;
GO

-- Resumen de la carga
SELECT estado, COUNT(*) AS partidos, SUM(golLocal + golVisitante) AS goles, SUM(cantPublico) AS publico
FROM Torneo.Partido GROUP BY estado;
GO
