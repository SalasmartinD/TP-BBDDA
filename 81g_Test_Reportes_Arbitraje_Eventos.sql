/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 17/11/2026

 Objetivo    : Suite de pruebas unitarias para 61_Reportes_Arbitraje_Eventos.sql.
               Cubre los 3 reportes (solo lectura):
               - Eventos.Reporte_Goleadores
               - Eventos.Reporte_Tarjetas
               - Arbitraje.Reporte_DesignacionesArbitrales

 PRECONDICIÓN: la base debe tener la carga de datos de los scripts 50*, 51* y
 53* (partidos finalizados con goles, tarjetas, suspensiones y árbitros
 designados). Se ejecuta recreando la base y corriendo en orden numérico los
 scripts 00_* a 61_* (incluido el 53, que cierra los partidos) y luego este
 script.
 Los valores esperados NO están fijos en el test: se calculan en el momento con
 consultas independientes sobre las tablas (marcador de Torneo.Partido,
 Eventos.Gol, Eventos.Tarjeta, Eventos.Suspension, Arbitraje.cuerpoArbitral);
 el script avisa con una PRECONDICIÓN si la base no está cargada.

 Estándares aplicados:
 - Relación 1:1 con 61_Reportes_Arbitraje_Eventos.sql.
 - Una prueba negativa por cada mensaje de validación (código 50001 y texto
   exacto). Eventos.Reporte_Goleadores valida dos cosas y tiene su prueba de
   acumulación; Reporte_Tarjetas y Reporte_DesignacionesArbitrales validan una
   sola, por lo que no admiten acumulación.
 - Un caso exitoso por reporte, con evidencia (SELECT), más los casos propios de
   cada reporte (filtros, tanda de penales, suspensión activa, árbitro sin
   designaciones).
 - Cómo se verifican los reportes:
   * Reporte_Tarjetas y Reporte_DesignacionesArbitrales devuelven UN result set:
     se capturan con INSERT ... EXEC y se comparan contra consultas
     independientes sobre las tablas.
   * Reporte_Goleadores devuelve TRES result sets de distinta forma y no se
     puede capturar completo con INSERT ... EXEC. Se verifica automáticamente la
     cantidad de filas del ÚLTIMO result set (los totales con ROLLUP), que es lo
     que devuelve @@ROWCOUNT inmediatamente después del EXEC, contra la cantidad
     esperada calculada en el test desde el marcador de Torneo.Partido (que es
     independiente de Eventos.Gol). Ese número cambia si el reporte cuenta un
     gol de más o de menos o lo acredita a otra selección, por eso sirve para
     las pruebas de la tanda de penales y del gol en contra. Los valores
     (goles por selección, ranking) se verifican a ojo contra el SELECT
     'ESPERADO' que se muestra antes del reporte. El SP queda ejecutado en el
     log como evidencia visible.
 - Idempotencia: limpieza preventiva al inicio y al final. Todo dato de prueba
   se crea y se borra con los SP de ABM (Gol_Alta/Gol_Baja,
   Suspension_Alta/Suspension_Baja, Arbitro_Alta/Arbitro_Baja); nunca con
   INSERT o DELETE directo a las tablas de negocio. Al terminar se verifica que
   las tablas tocadas vuelvan a la cantidad de filas inicial.
 - Todo set-based, sin SQL dinámico.
================================================================================
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

PRINT '================================================================================';
PRINT ' INICIANDO BATERÍA DE PRUEBAS: 61_Reportes_Arbitraje_Eventos.sql';
PRINT '================================================================================';
GO

/* =============================================================================
   OBJETOS TEMPORALES DE LA SESIÓN (no dejan nada en la base)
   #res        : resultado de cada prueba, para el resumen final.
   #Resultado  : imprime [OK] / [FALLO] y registra el resultado.
   ============================================================================= */
IF OBJECT_ID('tempdb..#res') IS NOT NULL DROP TABLE #res;
CREATE TABLE #res (titulo varchar(30) NOT NULL, ok bit NOT NULL);

IF OBJECT_ID('tempdb..#Resultado') IS NOT NULL DROP PROCEDURE #Resultado;
GO

CREATE PROCEDURE #Resultado
    @titulo      varchar(30),
    @ok          bit,
    @textoOk     nvarchar(400),
    @textoFallo  nvarchar(2200)
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO #res (titulo, ok) VALUES (@titulo, @ok);
    IF @ok = 1
        PRINT '[OK] ' + @titulo + N': ' + @textoOk;
    ELSE
        PRINT '[FALLO] ' + @titulo + N': ' + @textoFallo;
END;
GO

/* =============================================================================
   PREPARACIÓN DEL ENTORNO DE PRUEBAS
   No se crean datos de negocio de base: se eligen, dentro del seed, los
   registros con los que se arman las pruebas.
   - #fx / #fxJug : fixture de goleadores. Se elige una selección S y una fase F
       en las que S jugó partidos finalizados pero convirtió 0 goles según el
       marcador (así, cualquier gol que el reporte le acredite se nota en la
       cantidad de filas), un partido de esa fase, el rival R y jugadores de
       ambas selecciones (de la formación de ese partido).
   - #fxT         : jugador del seed con más tarjetas y uno de sus partidos.
   - Árbitro de prueba: apellido 'QRep Arbitro Sin Partidos'.
   ============================================================================= */
PRINT '--- Preparación: selección del fixture y limpieza preventiva ---';

IF OBJECT_ID('tempdb..#fx')        IS NOT NULL DROP TABLE #fx;
IF OBJECT_ID('tempdb..#fxJug')     IS NOT NULL DROP TABLE #fxJug;
IF OBJECT_ID('tempdb..#fxT')       IS NOT NULL DROP TABLE #fxT;
IF OBJECT_ID('tempdb..#esp')       IS NOT NULL DROP TABLE #esp;
IF OBJECT_ID('tempdb..#cred')      IS NOT NULL DROP TABLE #cred;
IF OBJECT_ID('tempdb..#expFilas')  IS NOT NULL DROP TABLE #expFilas;
IF OBJECT_ID('tempdb..#base')      IS NOT NULL DROP TABLE #base;
IF OBJECT_ID('tempdb..#LimpiarFixture') IS NOT NULL DROP PROCEDURE #LimpiarFixture;

-- Cada partido finalizado visto desde cada selección (sel, rival, goles a favor)
WITH t AS (
    SELECT p.idPartido, p.fase, p.idSeleccionLocal AS sel, p.idSeleccionVisitante AS riv, p.golLocal AS g
    FROM Torneo.Partido p WHERE p.estado = 'Finalizado'
    UNION ALL
    SELECT p.idPartido, p.fase, p.idSeleccionVisitante, p.idSeleccionLocal, p.golVisitante
    FROM Torneo.Partido p WHERE p.estado = 'Finalizado'
),
z AS (
    SELECT fase, sel FROM t GROUP BY fase, sel HAVING SUM(g) = 0
)
SELECT TOP 1 z.fase AS idFase, z.sel AS idSelS, t.riv AS idSelR, t.idPartido
INTO #fx
FROM z
JOIN t ON t.fase = z.fase AND t.sel = z.sel
ORDER BY z.fase, z.sel, t.idPartido;

SELECT fp.idJugador,
       CASE WHEN fp.idSeleccion = f.idSelS THEN 'S' ELSE 'R' END AS lado,
       ROW_NUMBER() OVER (PARTITION BY fp.idSeleccion ORDER BY fp.idJugador) AS n
INTO #fxJug
FROM Eventos.FormacionPartido fp
JOIN #fx f ON f.idPartido = fp.idPartido AND fp.idSeleccion IN (f.idSelS, f.idSelR);

SELECT TOP 1 t.idJugador, MIN(t.idPartido) AS idPartido
INTO #fxT
FROM Eventos.Tarjeta t
WHERE t.idJugador IS NOT NULL
GROUP BY t.idJugador
ORDER BY COUNT(*) DESC, t.idJugador;
GO

-- Limpieza del fixture (se usa al inicio y al final): da de baja, con los SP de
-- ABM, lo que pudo quedar de una corrida interrumpida.
--   Goles: los que se le acreditarían a S en el partido elegido (S no tiene ninguno
--          en el seed) y cualquier gol de tanda (minuto NULL) de ese partido.
--   Suspensión manual de prueba del jugador de #fxT (3 partidos, restan 2).
--   Árbitro de prueba sin designaciones.
CREATE PROCEDURE #LimpiarFixture
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id int;

    WHILE 1 = 1
    BEGIN
        SET @id = NULL;
        SELECT @id = MIN(g.idGol)
        FROM Eventos.Gol g
        JOIN #fx f ON f.idPartido = g.idPartido
        JOIN Eventos.FormacionPartido fp ON fp.idPartido = g.idPartido AND fp.idJugador = g.idJugador
        WHERE g.minuto IS NULL
           OR (g.tipo =  'En contra' AND fp.idSeleccion = f.idSelR)
           OR (g.tipo <> 'En contra' AND fp.idSeleccion = f.idSelS);
        IF @id IS NULL BREAK;
        EXEC Eventos.Gol_Baja @idGol = @id;
    END;

    WHILE 1 = 1
    BEGIN
        SET @id = NULL;
        SELECT @id = MIN(s.id)
        FROM Eventos.Suspension s
        JOIN #fxT t ON t.idJugador = s.idJugador
        WHERE s.idTarjeta IS NULL AND s.cantPartidos = 3 AND s.partidosRestantes = 2;
        IF @id IS NULL BREAK;
        EXEC Eventos.Suspension_Baja @id = @id;
    END;

    WHILE 1 = 1
    BEGIN
        SET @id = NULL;
        SELECT @id = MIN(idArbitro) FROM Arbitraje.Arbitro WHERE apellido = N'QRep Arbitro Sin Partidos';
        IF @id IS NULL BREAK;
        EXEC Arbitraje.Arbitro_Baja @idArbitro = @id;
    END;
END;
GO

EXEC #LimpiarFixture;
GO

-- Valores esperados, calculados con consultas independientes del reporte.
-- #esp  : goles por (fase, selección) según el MARCADOR de Torneo.Partido.
-- #cred : goles con minuto según Eventos.Gol y la formación del autor, ya
--         acreditados a la selección que corresponde (el gol 'En contra' va al rival).
SELECT x.idFase, x.idSeleccion, SUM(x.goles) AS goles
INTO #esp
FROM (SELECT p.fase AS idFase, p.idSeleccionLocal AS idSeleccion, p.golLocal AS goles
      FROM Torneo.Partido p WHERE p.estado = 'Finalizado'
      UNION ALL
      SELECT p.fase, p.idSeleccionVisitante, p.golVisitante
      FROM Torneo.Partido p WHERE p.estado = 'Finalizado') x
GROUP BY x.idFase, x.idSeleccion;

SELECT g.idGol,
       p.fase AS idFase,
       CASE WHEN g.tipo = 'En contra'
            THEN CASE WHEN fp.idSeleccion = p.idSeleccionLocal THEN p.idSeleccionVisitante ELSE p.idSeleccionLocal END
            ELSE fp.idSeleccion END AS idSeleccion,
       CASE WHEN g.tipo = 'En contra' THEN 1 ELSE 0 END AS enContra
INTO #cred
FROM Eventos.Gol g
JOIN Torneo.Partido p            ON p.idPartido  = g.idPartido
JOIN Eventos.FormacionPartido fp ON fp.idPartido = g.idPartido AND fp.idJugador = g.idJugador
WHERE g.minuto IS NOT NULL;

-- Cantidad de filas esperada en el último result set de Reporte_Goleadores
-- (ROLLUP: una fila por selección-fase con goles + un subtotal por selección + el
-- total del torneo; 0 filas si no hay goles en el filtro).
--   todo / sel / fase / ambos : sin filtro, solo selección, solo fase, ambos.
--   sinGoles                  : la selección S y la fase F del fixture (0 goles).
CREATE TABLE #expFilas (caso varchar(10) PRIMARY KEY, idSel int NULL, idFase int NULL, filas int NOT NULL);

DECLARE @faseF int = (SELECT MAX(idFase) FROM #esp WHERE goles > 0);
DECLARE @selF  int = (SELECT MIN(idSeleccion) FROM #esp WHERE goles > 0 AND idFase = @faseF);
DECLARE @selS  int = (SELECT idSelS FROM #fx);
DECLARE @faseS int = (SELECT idFase FROM #fx);

INSERT INTO #expFilas (caso, idSel, idFase, filas)
SELECT c.caso, c.s, c.f, CASE WHEN x.n = 0 THEN 0 ELSE x.n + x.s + 1 END
FROM (VALUES ('todo',     CAST(NULL AS int), CAST(NULL AS int)),
             ('sel',      @selF,             CAST(NULL AS int)),
             ('fase',     CAST(NULL AS int), @faseF),
             ('ambos',    @selF,             @faseF),
             ('sinGoles', @selS,             @faseS)) c (caso, s, f)
CROSS APPLY (SELECT COUNT(*) AS n, COUNT(DISTINCT e.idSeleccion) AS s
             FROM #esp e
             WHERE e.goles > 0
               AND (c.s IS NULL OR e.idSeleccion = c.s)
               AND (c.f IS NULL OR e.idFase = c.f)) x;

-- Cantidad de filas de las tablas que tocan las pruebas, para verificar al final que no quedó nada
SELECT v.tabla, v.n
INTO #base
FROM (SELECT 'Gol' AS tabla, COUNT(*) AS n FROM Eventos.Gol
      UNION ALL SELECT 'Suspension', COUNT(*) FROM Eventos.Suspension
      UNION ALL SELECT 'Arbitro',    COUNT(*) FROM Arbitraje.Arbitro
      UNION ALL SELECT 'Tarjeta',    COUNT(*) FROM Eventos.Tarjeta
      UNION ALL SELECT 'cuerpoArbitral', COUNT(*) FROM Arbitraje.cuerpoArbitral) v;

-- PRECONDICIÓN: la base tiene la carga de datos (50*, 51*, 53*) y hay fixture disponible
DECLARE @ok bit = CASE WHEN
        EXISTS (SELECT 1 FROM Torneo.Partido WHERE estado = 'Finalizado' AND golLocal + golVisitante > 0)
    AND EXISTS (SELECT 1 FROM Eventos.Tarjeta WHERE idJugador IS NOT NULL)
    AND EXISTS (SELECT 1 FROM Eventos.Tarjeta WHERE idStaff IS NOT NULL)
    AND EXISTS (SELECT 1 FROM Eventos.Suspension)
    AND EXISTS (SELECT 1 FROM Arbitraje.cuerpoArbitral)
    AND (SELECT COUNT(*) FROM Torneo.Periodo WHERE idPeriodo IN (1, 2, 5)) = 3
    AND EXISTS (SELECT 1 FROM #fx)
    AND (SELECT COUNT(*) FROM #fxJug WHERE lado = 'S' AND n <= 3) = 3
    AND EXISTS (SELECT 1 FROM #fxJug WHERE lado = 'R' AND n = 1)
    AND EXISTS (SELECT 1 FROM #fxT)
    THEN 1 ELSE 0 END;
EXEC #Resultado 'PRECONDICION', @ok,
     N'Base cargada (partidos finalizados con goles, tarjetas, suspensiones y árbitros designados) y fixture disponible.',
     N'La base no tiene la carga de datos esperada. Ejecutar en orden numérico los scripts 00_* a 61_* y luego este script.';

SELECT 'FIXTURE GOLEADORES' AS momento, f.idPartido, pa.nroPartidoOficial AS nroPartido,
       fa.nombre AS fase, ps.nombre AS seleccionS_sin_goles, pr.nombre AS rival
FROM #fx f
JOIN Torneo.Partido pa ON pa.idPartido = f.idPartido
JOIN Torneo.Fase fa ON fa.idFase = f.idFase
JOIN Equipos.Seleccion ss ON ss.id = f.idSelS JOIN Torneo.Pais ps ON ps.id = ss.idPais
JOIN Equipos.Seleccion sr ON sr.id = f.idSelR JOIN Torneo.Pais pr ON pr.id = sr.idPais;
PRINT '';
GO

/* =============================================================================
   SECCIÓN 1: Eventos.Reporte_Goleadores
   Se verifica con la cantidad de filas del último result set (ver encabezado).
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 1. PRUEBAS: Eventos.Reporte_Goleadores';
PRINT '--------------------------------------------------------------------------------';

DECLARE @idSelS int, @idSelR int, @idFase int, @idPartido int, @selF int, @faseF int;
SELECT @idSelS = idSelS, @idSelR = idSelR, @idFase = idFase, @idPartido = idPartido FROM #fx;
SELECT @selF = idSel, @faseF = idFase FROM #expFilas WHERE caso = 'ambos';

DECLARE @j1 int, @j2 int, @j3 int, @jR int;
SELECT @j1 = MAX(CASE WHEN lado = 'S' AND n = 1 THEN idJugador ELSE 0 END),
       @j2 = MAX(CASE WHEN lado = 'S' AND n = 2 THEN idJugador ELSE 0 END),
       @j3 = MAX(CASE WHEN lado = 'S' AND n = 3 THEN idJugador ELSE 0 END),
       @jR = MAX(CASE WHEN lado = 'R' AND n = 1 THEN idJugador ELSE 0 END)
FROM #fxJug;

DECLARE @ok bit, @txt nvarchar(2200), @esperado nvarchar(2000);
DECLARE @rc int, @rcAntes int, @rcTanda int, @rcTodo int, @rcControl int, @rcSel int, @rcFase int, @rcAmbos int;
DECLARE @g1 int, @g2 int, @g3 int, @gC int, @golesAntes int;

-- PRUEBA 1.1: Reporte exitoso sin filtros
-- Resultado esperado: 3 result sets (goleadores por selección y fase, tabla de goleadores
--   con ranking y totales con ROLLUP hasta 'TOTAL DEL TORNEO'). Automático: el último result
--   set tiene la cantidad de filas esperada según el marcador (selecciones-fase con goles +
--   subtotales + total); la suma de los marcadores de los partidos finalizados es igual a la
--   cantidad de goles con minuto de Eventos.Gol; y los goles acreditados según Eventos.Gol
--   (el 'En contra' suma al rival) coinciden selección por selección y fase por fase con el
--   marcador. A ojo: comparar los totales del reporte con el SELECT 'ESPERADO' (los
--   'En contra' no figuran a nombre del autor en los listados y suman al rival).
BEGIN TRY
    SELECT N'GOLES EN CONTRA DEL SEED' AS momento, p.nroPartidoOficial AS nroPartido,
           j.apellido + N', ' + j.nombre AS autor, pa.nombre AS seleccionDelAutor, pc.nombre AS seleccionAcreditada
    FROM #cred c
    JOIN Eventos.Gol g               ON g.idGol      = c.idGol
    JOIN Torneo.Partido p            ON p.idPartido  = g.idPartido
    JOIN Eventos.FormacionPartido fp ON fp.idPartido = g.idPartido AND fp.idJugador = g.idJugador
    JOIN Equipos.Jugador j           ON j.id         = g.idJugador
    JOIN Equipos.Seleccion sa        ON sa.id        = fp.idSeleccion
    JOIN Torneo.Pais pa              ON pa.id        = sa.idPais
    JOIN Equipos.Seleccion sc        ON sc.id        = c.idSeleccion
    JOIN Torneo.Pais pc              ON pc.id        = sc.idPais
    WHERE c.enContra = 1
    ORDER BY p.nroPartidoOficial;

    SELECT N'ESPERADO 1.1 (totales)' AS momento,
           CASE WHEN GROUPING(s.id) = 1 THEN N'TOTAL DEL TORNEO' ELSE ps.nombre END AS seleccion,
           CASE WHEN GROUPING(f.idFase) = 0 THEN f.nombre
                WHEN GROUPING(s.id) = 1     THEN N'Todas las fases'
                ELSE N'Total de la selección' END AS fase,
           SUM(CASE WHEN c.enContra = 0 THEN 1 ELSE 0 END) AS goles,
           SUM(CASE WHEN c.enContra = 1 THEN 1 ELSE 0 END) AS golesEnContraAFavor,
           COUNT(*) AS golesTotales
    FROM #cred c
    JOIN Equipos.Seleccion s ON s.id  = c.idSeleccion
    JOIN Torneo.Pais ps      ON ps.id = s.idPais
    JOIN Torneo.Fase f       ON f.idFase = c.idFase
    GROUP BY ROLLUP ((s.id, ps.nombre), (f.idFase, f.nombre, f.orden))
    ORDER BY GROUPING(s.id), ps.nombre, GROUPING(f.idFase), f.orden;

    EXEC Eventos.Reporte_Goleadores;
    SET @rc = @@ROWCOUNT;

    SET @ok = CASE WHEN @rc = (SELECT filas FROM #expFilas WHERE caso = 'todo')
                    AND (SELECT SUM(goles) FROM #esp) = (SELECT COUNT(*) FROM Eventos.Gol WHERE minuto IS NOT NULL)
                    AND NOT EXISTS (SELECT 1
                                    FROM (SELECT idFase, idSeleccion, COUNT(*) AS goles FROM #cred GROUP BY idFase, idSeleccion) c
                                    FULL JOIN (SELECT idFase, idSeleccion, goles FROM #esp WHERE goles > 0) e
                                           ON e.idFase = c.idFase AND e.idSeleccion = c.idSeleccion
                                    WHERE ISNULL(c.goles, 0) <> ISNULL(e.goles, 0))
                   THEN 1 ELSE 0 END;
    SET @txt = N'Último result set con ' + CAST(@rc AS nvarchar(10)) + N' filas; esperadas '
             + CAST((SELECT filas FROM #expFilas WHERE caso = 'todo') AS nvarchar(10)) + N' (o los goles acreditados no coinciden con el marcador).';
    EXEC #Resultado 'PRUEBA 1.1', @ok,
         N'Reporte completo: totales con la cantidad de filas esperada y goles acreditados coherentes con el marcador.', @txt;
END TRY
BEGIN CATCH
    SET @txt = N'Error inesperado ' + CAST(ERROR_NUMBER() AS nvarchar(10)) + N': ' + ERROR_MESSAGE();
    EXEC #Resultado 'PRUEBA 1.1', 0, N'', @txt;
END CATCH;

-- PRUEBA 1.2: Reporte exitoso con filtros (solo selección, solo fase y ambos)
-- Resultado esperado: cada filtro reduce el resultado; la cantidad de filas del último result set
--   coincide con la esperada para el filtro (el filtro de selección usa los goles que se le
--   acreditan; el de fase, solo los goles de esa fase), y 'solo selección' y 'solo fase' tienen
--   menos filas que el reporte completo. A ojo: los tres reportes quedan en el log.
BEGIN TRY
    EXEC Eventos.Reporte_Goleadores @idSeleccion = @selF;
    SET @rcSel = @@ROWCOUNT;
    EXEC Eventos.Reporte_Goleadores @idFase = @faseF;
    SET @rcFase = @@ROWCOUNT;
    EXEC Eventos.Reporte_Goleadores @idSeleccion = @selF, @idFase = @faseF;
    SET @rcAmbos = @@ROWCOUNT;

    SET @ok = CASE WHEN @rcSel   = (SELECT filas FROM #expFilas WHERE caso = 'sel')
                    AND @rcFase  = (SELECT filas FROM #expFilas WHERE caso = 'fase')
                    AND @rcAmbos = (SELECT filas FROM #expFilas WHERE caso = 'ambos')
                    AND @rcSel  < (SELECT filas FROM #expFilas WHERE caso = 'todo')
                    AND @rcFase < (SELECT filas FROM #expFilas WHERE caso = 'todo')
                   THEN 1 ELSE 0 END;
    SET @txt = N'Filas de totales: selección=' + CAST(@rcSel AS nvarchar(10)) + N', fase=' + CAST(@rcFase AS nvarchar(10))
             + N', ambos=' + CAST(@rcAmbos AS nvarchar(10)) + N' (no coinciden con lo esperado o no reducen el reporte completo).';
    EXEC #Resultado 'PRUEBA 1.2', @ok, N'Los filtros por selección, por fase y por ambos devuelven lo esperado y reducen el resultado.', @txt;
END TRY
BEGIN CATCH
    SET @txt = N'Error inesperado ' + CAST(ERROR_NUMBER() AS nvarchar(10)) + N': ' + ERROR_MESSAGE();
    EXEC #Resultado 'PRUEBA 1.2', 0, N'', @txt;
END CATCH;

-- PRUEBA 1.3: CASO CLAVE - los goles de la definición por penales (minuto NULL) no cuentan
--   La selección S (0 goles en la fase F según el marcador) tiene 3 goles de tanda cargados con
--   Eventos.Gol_Alta (minuto NULL, período 5, tipo 'Penal') por jugadores de la formación del
--   partido. Como control, un penal convertido durante el juego (tipo 'Penal' con minuto) SÍ debe contar:
--   el filtro es el minuto, no el tipo. Los goles se dan de baja con Gol_Baja.
-- Resultado esperado: con el filtro (S, F) el último result set tiene 0 filas antes, 0 filas con
--   los 3 goles de tanda cargados (los totales no cambian) y 3 filas (selección-fase, subtotal y
--   total) con el penal en juego; sin filtro sigue teniendo la cantidad esperada de filas con los
--   goles de tanda cargados; al final Eventos.Gol tiene la misma cantidad de filas que al inicio.
BEGIN TRY
    SELECT @golesAntes = COUNT(*) FROM Eventos.Gol;

    EXEC Eventos.Reporte_Goleadores @idSeleccion = @idSelS, @idFase = @idFase;
    SET @rcAntes = @@ROWCOUNT;

    EXEC Eventos.Gol_Alta @idPartido = @idPartido, @idJugador = @j1, @minuto = NULL, @tipo = 'Penal', @idPeriodo = 5, @idGol = @g1 OUTPUT;
    EXEC Eventos.Gol_Alta @idPartido = @idPartido, @idJugador = @j2, @minuto = NULL, @tipo = 'Penal', @idPeriodo = 5, @idGol = @g2 OUTPUT;
    EXEC Eventos.Gol_Alta @idPartido = @idPartido, @idJugador = @j3, @minuto = NULL, @tipo = 'Penal', @idPeriodo = 5, @idGol = @g3 OUTPUT;
    SELECT N'TANDA CARGADA 1.3' AS momento, g.idGol, g.idPartido, g.idJugador, g.minuto, g.tipo, g.idPeriodo
    FROM Eventos.Gol g WHERE g.idGol IN (@g1, @g2, @g3) ORDER BY g.idGol;

    EXEC Eventos.Reporte_Goleadores @idSeleccion = @idSelS, @idFase = @idFase;   -- con la tanda: no debe cambiar
    SET @rcTanda = @@ROWCOUNT;
    EXEC Eventos.Reporte_Goleadores;                                             -- sin filtro: el total del torneo no cambia
    SET @rcTodo = @@ROWCOUNT;

    EXEC Eventos.Gol_Alta @idPartido = @idPartido, @idJugador = @j1, @minuto = 80, @tipo = 'Penal', @idPeriodo = 2, @idGol = @gC OUTPUT;
    EXEC Eventos.Reporte_Goleadores @idSeleccion = @idSelS, @idFase = @idFase;   -- control: el penal en juego sí cuenta
    SET @rcControl = @@ROWCOUNT;

    EXEC Eventos.Gol_Baja @idGol = @g1;
    EXEC Eventos.Gol_Baja @idGol = @g2;
    EXEC Eventos.Gol_Baja @idGol = @g3;
    EXEC Eventos.Gol_Baja @idGol = @gC;

    SELECT N'FILAS DE TOTALES 1.3' AS momento, @rcAntes AS antes, @rcTanda AS conTanda,
           @rcTodo AS sinFiltroConTanda, @rcControl AS conPenalEnJuego,
           (SELECT COUNT(*) FROM Eventos.Gol) - @golesAntes AS golesDeMasAlFinal;

    SET @ok = CASE WHEN @rcAntes   = (SELECT filas FROM #expFilas WHERE caso = 'sinGoles')
                    AND @rcTanda   = @rcAntes
                    AND @rcTodo    = (SELECT filas FROM #expFilas WHERE caso = 'todo')
                    AND @rcControl = 3
                    AND (SELECT COUNT(*) FROM Eventos.Gol) = @golesAntes
                   THEN 1 ELSE 0 END;
    SET @txt = N'Filas de totales: antes=' + CAST(@rcAntes AS nvarchar(10)) + N', con tanda=' + CAST(@rcTanda AS nvarchar(10))
             + N', sin filtro=' + CAST(@rcTodo AS nvarchar(10)) + N', con penal en juego=' + CAST(@rcControl AS nvarchar(10))
             + N' (esperado 0, 0, ' + CAST((SELECT filas FROM #expFilas WHERE caso = 'todo') AS nvarchar(10)) + N' y 3) o quedaron goles de prueba.';
    EXEC #Resultado 'PRUEBA 1.3', @ok, N'Los goles de la tanda de penales (minuto NULL) no cuentan; el penal convertido en juego sí.', @txt;
END TRY
BEGIN CATCH
    SET @txt = N'Error inesperado ' + CAST(ERROR_NUMBER() AS nvarchar(10)) + N': ' + ERROR_MESSAGE();
    EXEC #Resultado 'PRUEBA 1.3', 0, N'', @txt;
    EXEC #LimpiarFixture;
END CATCH;

-- PRUEBA 1.4: Un gol 'En contra' se acredita a la selección rival
--   Un jugador de R convierte un gol 'En contra' (Gol_Alta) en el partido contra S; se da de baja con Gol_Baja.
-- Resultado esperado: con el filtro (S, F) el último result set pasa de 0 a 3 filas (el gol se
--   acredita a S, la selección rival del autor); al final Eventos.Gol queda con las filas iniciales.
--   A ojo: en los listados de goleadores ese gol no figura a nombre del autor.
BEGIN TRY
    SELECT @golesAntes = COUNT(*) FROM Eventos.Gol;
    EXEC Eventos.Gol_Alta @idPartido = @idPartido, @idJugador = @jR, @minuto = 30, @tipo = 'En contra', @idPeriodo = 1, @idGol = @gC OUTPUT;
    SELECT N'GOL EN CONTRA CARGADO 1.4' AS momento, g.idGol, g.idPartido, g.idJugador AS idAutor_de_R, g.minuto, g.tipo
    FROM Eventos.Gol g WHERE g.idGol = @gC;

    EXEC Eventos.Reporte_Goleadores @idSeleccion = @idSelS, @idFase = @idFase;
    SET @rc = @@ROWCOUNT;
    EXEC Eventos.Gol_Baja @idGol = @gC;

    SET @ok = CASE WHEN @rc = 3 AND (SELECT COUNT(*) FROM Eventos.Gol) = @golesAntes THEN 1 ELSE 0 END;
    SET @txt = N'El reporte de S devolvió ' + CAST(@rc AS nvarchar(10)) + N' filas de totales (esperadas 3) o quedó el gol de prueba.';
    EXEC #Resultado 'PRUEBA 1.4', @ok, N'El gol en contra del jugador de R se acredita a la selección rival S.', @txt;
END TRY
BEGIN CATCH
    SET @txt = N'Error inesperado ' + CAST(ERROR_NUMBER() AS nvarchar(10)) + N': ' + ERROR_MESSAGE();
    EXEC #Resultado 'PRUEBA 1.4', 0, N'', @txt;
    EXEC #LimpiarFixture;
END CATCH;

-- PRUEBA 1.5: Selección inexistente
-- Resultado esperado: THROW 50001 "No se pudo generar el reporte de goleadores:" + "- La selección no existe."
SET @esperado = N'No se pudo generar el reporte de goleadores:' + CHAR(10) + N'- La selección no existe.';
BEGIN TRY
    EXEC Eventos.Reporte_Goleadores @idSeleccion = -999;
    EXEC #Resultado 'PRUEBA 1.5', 0, N'', N'No detectó la selección inexistente.';
END TRY
BEGIN CATCH
    SET @ok = CASE WHEN ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() = @esperado THEN 1 ELSE 0 END;
    SET @txt = N'Código o mensaje inesperado: ' + CAST(ERROR_NUMBER() AS nvarchar(10)) + N' - ' + ERROR_MESSAGE();
    EXEC #Resultado 'PRUEBA 1.5', @ok, N'Selección inexistente rechazada (50001).', @txt;
END CATCH;

-- PRUEBA 1.6: Fase inexistente
-- Resultado esperado: THROW 50001 "No se pudo generar el reporte de goleadores:" + "- La fase no existe."
SET @esperado = N'No se pudo generar el reporte de goleadores:' + CHAR(10) + N'- La fase no existe.';
BEGIN TRY
    EXEC Eventos.Reporte_Goleadores @idFase = -999;
    EXEC #Resultado 'PRUEBA 1.6', 0, N'', N'No detectó la fase inexistente.';
END TRY
BEGIN CATCH
    SET @ok = CASE WHEN ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() = @esperado THEN 1 ELSE 0 END;
    SET @txt = N'Código o mensaje inesperado: ' + CAST(ERROR_NUMBER() AS nvarchar(10)) + N' - ' + ERROR_MESSAGE();
    EXEC #Resultado 'PRUEBA 1.6', @ok, N'Fase inexistente rechazada (50001).', @txt;
END CATCH;

-- PRUEBA 1.7: Acumulación de errores (selección y fase inexistentes a la vez)
-- Resultado esperado: un único THROW 50001 con el prefijo y los dos mensajes juntos.
SET @esperado = N'No se pudo generar el reporte de goleadores:' + CHAR(10) + N'- La selección no existe.' + CHAR(10) + N'- La fase no existe.';
BEGIN TRY
    EXEC Eventos.Reporte_Goleadores @idSeleccion = -999, @idFase = -999;
    EXEC #Resultado 'PRUEBA 1.7', 0, N'', N'No detectó los errores acumulados.';
END TRY
BEGIN CATCH
    SET @ok = CASE WHEN ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() = @esperado THEN 1 ELSE 0 END;
    SET @txt = N'Código o mensaje inesperado: ' + CAST(ERROR_NUMBER() AS nvarchar(10)) + N' - ' + ERROR_MESSAGE();
    EXEC #Resultado 'PRUEBA 1.7', @ok, N'Acumulación de los 2 errores verificada en un único THROW 50001.', @txt;
END CATCH;
GO

/* =============================================================================
   SECCIÓN 2: Eventos.Reporte_Tarjetas
   Un solo result set: se captura con INSERT ... EXEC en #repT.
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 2. PRUEBAS: Eventos.Reporte_Tarjetas';
PRINT '--------------------------------------------------------------------------------';

IF OBJECT_ID('tempdb..#repT') IS NOT NULL DROP TABLE #repT;
CREATE TABLE #repT (
    idSeleccion         int            NULL,
    seleccion           nvarchar(200)  NULL,
    tipoPersona         varchar(20)    NULL,
    persona             nvarchar(300)  NULL,
    posicionORol        varchar(40)    NULL,
    amarillas           int            NULL,
    rojas               int            NULL,
    rojasDirectas       int            NULL,
    rojasDobleAmarilla  int            NULL,
    suspensionesActivas int            NULL,
    partidosPorCumplir  int            NULL,
    suspensionesTotales int            NULL,
    detalleSuspensiones nvarchar(max)  NULL
);

DECLARE @ok bit, @txt nvarchar(2200), @esperado nvarchar(2000);
DECLARE @nTarj int, @nTarjJug int, @nTarjStaff int, @nAm int, @nRo int, @nPers int, @nSusp int, @nSuspAct int,
        @nPorCumplir int, @nCumplidas int, @nPersAct int, @nFilas int;

SELECT @nTarj      = COUNT(*),
       @nTarjJug   = SUM(CASE WHEN idJugador IS NOT NULL THEN 1 ELSE 0 END),
       @nTarjStaff = SUM(CASE WHEN idStaff   IS NOT NULL THEN 1 ELSE 0 END),
       @nAm        = SUM(CASE WHEN color = 'A' THEN 1 ELSE 0 END),
       @nRo        = SUM(CASE WHEN color = 'R' THEN 1 ELSE 0 END)
FROM Eventos.Tarjeta;

SELECT @nSusp       = COUNT(*),
       @nSuspAct    = SUM(CASE WHEN partidosRestantes > 0 THEN 1 ELSE 0 END),
       @nPorCumplir = SUM(CAST(partidosRestantes AS int)),
       @nCumplidas  = SUM(CASE WHEN partidosRestantes = 0 THEN 1 ELSE 0 END)
FROM Eventos.Suspension;

SELECT @nPers = COUNT(*)
FROM (SELECT 'J' AS t, idJugador AS id FROM Eventos.Tarjeta   WHERE idJugador IS NOT NULL
      UNION SELECT 'S', idStaff   FROM Eventos.Tarjeta   WHERE idStaff   IS NOT NULL
      UNION SELECT 'J', idJugador FROM Eventos.Suspension WHERE idJugador IS NOT NULL
      UNION SELECT 'S', idStaff   FROM Eventos.Suspension WHERE idStaff   IS NOT NULL) x;

SELECT @nPersAct = COUNT(*)
FROM (SELECT 'J' AS t, idJugador AS id FROM Eventos.Suspension WHERE idJugador IS NOT NULL AND partidosRestantes > 0
      UNION SELECT 'S', idStaff FROM Eventos.Suspension WHERE idStaff IS NOT NULL AND partidosRestantes > 0) x;

-- PRUEBA 2.1: Reporte exitoso sin filtros
-- Resultado esperado: una fila por persona con tarjeta o suspensión; la suma de amarillas y rojas
--   es igual a la cantidad de filas de Eventos.Tarjeta (también por color y por tipo de persona:
--   jugadores y cuerpo técnico); las suspensiones del reporte coinciden con Eventos.Suspension
--   (totales, activas, partidos por cumplir y las que figuran como 'Cumplida'). Con el seed:
--   71 tarjetas (68 a jugadores y 3 a cuerpo técnico) y 5 suspensiones, todas 'Cumplida'.
BEGIN TRY
    DELETE FROM #repT;
    INSERT INTO #repT EXEC Eventos.Reporte_Tarjetas;

    SELECT N'RESUMEN 2.1' AS momento, COUNT(*) AS personas, SUM(amarillas) AS amarillas, SUM(rojas) AS rojas,
           SUM(amarillas) + SUM(rojas) AS tarjetas, @nTarj AS tarjetasEnLaTabla,
           SUM(suspensionesTotales) AS suspensiones, SUM(suspensionesActivas) AS suspensionesActivas
    FROM #repT;
    SELECT N'CUERPO TECNICO Y SUSPENDIDOS 2.1' AS momento, seleccion, tipoPersona, persona, posicionORol, amarillas, rojas,
           suspensionesActivas, partidosPorCumplir, suspensionesTotales, detalleSuspensiones
    FROM #repT
    WHERE tipoPersona <> 'Jugador' OR suspensionesTotales > 0
    ORDER BY tipoPersona, seleccion, persona;

    SET @ok = CASE WHEN (SELECT COUNT(*) FROM #repT) = @nPers
                    AND @nTarjJug > 0 AND @nTarjStaff > 0
                    AND (SELECT SUM(amarillas) + SUM(rojas) FROM #repT) = @nTarj
                    AND (SELECT SUM(amarillas) FROM #repT) = @nAm
                    AND (SELECT SUM(rojas) FROM #repT) = @nRo
                    AND (SELECT SUM(amarillas + rojas) FROM #repT WHERE tipoPersona = 'Jugador') = @nTarjJug
                    AND (SELECT SUM(amarillas + rojas) FROM #repT WHERE tipoPersona = 'Cuerpo tecnico') = @nTarjStaff
                    AND (SELECT SUM(suspensionesTotales) FROM #repT) = @nSusp
                    AND (SELECT SUM(suspensionesActivas) FROM #repT) = @nSuspAct
                    AND (SELECT SUM(partidosPorCumplir) FROM #repT) = @nPorCumplir
                    AND (SELECT ISNULL(SUM((LEN(detalleSuspensiones) - LEN(REPLACE(detalleSuspensiones, N'Cumplida', N''))) / LEN(N'Cumplida')), 0)
                         FROM #repT) = @nCumplidas
                   THEN 1 ELSE 0 END;
    EXEC #Resultado 'PRUEBA 2.1', @ok,
         N'Tarjetas de jugadores y cuerpo técnico y suspensiones coinciden con las tablas.',
         N'Los totales del reporte no coinciden con Eventos.Tarjeta y Eventos.Suspension (ver el SELECT de resumen).';
END TRY
BEGIN CATCH
    SET @txt = N'Error inesperado ' + CAST(ERROR_NUMBER() AS nvarchar(10)) + N': ' + ERROR_MESSAGE();
    EXEC #Resultado 'PRUEBA 2.1', 0, N'', @txt;
END CATCH;

-- PRUEBA 2.2: Filtro por selección (la selección con más tarjetas)
-- Resultado esperado: solo filas de esa selección, menos que en el reporte completo, y la suma de
--   amarillas y rojas es igual a las tarjetas de sus jugadores (formación del partido) y de su
--   cuerpo técnico.
DECLARE @selT int, @nTarjSel int;
SELECT TOP 1 @selT = x.idSel
FROM (SELECT COALESCE(fp.idSeleccion, st.idSeleccion) AS idSel
      FROM Eventos.Tarjeta t
      LEFT JOIN Eventos.FormacionPartido fp ON fp.idPartido = t.idPartido AND fp.idJugador = t.idJugador
      LEFT JOIN Equipos.Staff st            ON st.id = t.idStaff) x
WHERE x.idSel IS NOT NULL
GROUP BY x.idSel
ORDER BY COUNT(*) DESC, x.idSel;

SELECT @nTarjSel = COUNT(*)
FROM Eventos.Tarjeta t
LEFT JOIN Eventos.FormacionPartido fp ON fp.idPartido = t.idPartido AND fp.idJugador = t.idJugador
LEFT JOIN Equipos.Staff st            ON st.id = t.idStaff
WHERE COALESCE(fp.idSeleccion, st.idSeleccion) = @selT;

BEGIN TRY
    DELETE FROM #repT;
    INSERT INTO #repT EXEC Eventos.Reporte_Tarjetas @idSeleccion = @selT;

    SELECT N'FILTRO SELECCION 2.2' AS momento, seleccion, tipoPersona, persona, posicionORol, amarillas, rojas, suspensionesTotales
    FROM #repT ORDER BY tipoPersona, rojas DESC, amarillas DESC, persona;

    SET @ok = CASE WHEN (SELECT COUNT(*) FROM #repT) > 0
                    AND (SELECT COUNT(*) FROM #repT) < @nPers
                    AND NOT EXISTS (SELECT 1 FROM #repT WHERE idSeleccion IS NULL OR idSeleccion <> @selT)
                    AND (SELECT SUM(amarillas + rojas) FROM #repT) = @nTarjSel
                   THEN 1 ELSE 0 END;
    EXEC #Resultado 'PRUEBA 2.2', @ok, N'El filtro por selección devuelve solo personas de esa selección con sus tarjetas.',
         N'El filtro por selección no devolvió solo las personas y tarjetas de la selección indicada.';
END TRY
BEGIN CATCH
    SET @txt = N'Error inesperado ' + CAST(ERROR_NUMBER() AS nvarchar(10)) + N': ' + ERROR_MESSAGE();
    EXEC #Resultado 'PRUEBA 2.2', 0, N'', @txt;
END CATCH;

-- PRUEBA 2.3: @soloActivas = 1 con el seed (todas las suspensiones están cumplidas)
-- Resultado esperado: 0 filas (cantidad de personas con alguna suspensión con partidos restantes; 0 con el seed).
BEGIN TRY
    DELETE FROM #repT;
    INSERT INTO #repT EXEC Eventos.Reporte_Tarjetas @soloActivas = 1;
    SELECT N'SOLO ACTIVAS 2.3' AS momento, COUNT(*) AS filas, @nPersAct AS personasConSuspensionActiva FROM #repT;

    SET @ok = CASE WHEN (SELECT COUNT(*) FROM #repT) = @nPersAct THEN 1 ELSE 0 END;
    EXEC #Resultado 'PRUEBA 2.3', @ok, N'Sin suspensiones activas el reporte devuelve 0 filas.',
         N'El reporte con @soloActivas = 1 no devolvió la cantidad esperada de personas con suspensión activa.';
END TRY
BEGIN CATCH
    SET @txt = N'Error inesperado ' + CAST(ERROR_NUMBER() AS nvarchar(10)) + N': ' + ERROR_MESSAGE();
    EXEC #Resultado 'PRUEBA 2.3', 0, N'', @txt;
END CATCH;

-- PRUEBA 2.4: @soloActivas = 1 con una suspensión activa creada con Suspension_Alta
--   Al jugador del seed con más tarjetas se le carga una suspensión manual de 3 partidos con 2
--   restantes y se da de baja con Suspension_Baja.
-- Resultado esperado: 1 fila, la del jugador, con suspensionesActivas = 1, partidosPorCumplir = 2,
--   suspensionesTotales = sus suspensiones reales (las cumplidas del seed + la nueva), el detalle
--   solo con la activa ('manual') y amarillas/rojas iguales a sus tarjetas reales (la suspensión no
--   multiplica las tarjetas). Al final Eventos.Suspension queda con las filas iniciales.
DECLARE @jugT int, @partT int, @idSusp int, @amJug int, @roJug int;
SELECT @jugT = idJugador, @partT = idPartido FROM #fxT;
SELECT @amJug = SUM(CASE WHEN color = 'A' THEN 1 ELSE 0 END), @roJug = SUM(CASE WHEN color = 'R' THEN 1 ELSE 0 END)
FROM Eventos.Tarjeta WHERE idJugador = @jugT;

BEGIN TRY
    SELECT N'ANTES 2.4' AS momento, @jugT AS idJugador, @amJug AS amarillas, @roJug AS rojas,
           (SELECT COUNT(*) FROM Eventos.Suspension WHERE idJugador = @jugT) AS suspensionesDelJugador;

    EXEC Eventos.Suspension_Alta @idPartido = @partT, @idJugador = @jugT, @cantPartidos = 3, @partidosRestantes = 2, @id = @idSusp OUTPUT;

    DELETE FROM #repT;
    INSERT INTO #repT EXEC Eventos.Reporte_Tarjetas @soloActivas = 1;
    SELECT N'REPORTE 2.4 (soloActivas = 1)' AS momento, seleccion, tipoPersona, persona, amarillas, rojas,
           suspensionesActivas, partidosPorCumplir, suspensionesTotales, detalleSuspensiones
    FROM #repT;

    SET @ok = CASE WHEN (SELECT COUNT(*) FROM #repT) = @nPersAct + 1
                    AND EXISTS (SELECT 1 FROM #repT
                                WHERE tipoPersona = 'Jugador'
                                  AND persona = (SELECT apellido + N', ' + nombre FROM Equipos.Jugador WHERE id = @jugT)
                                  AND suspensionesActivas = 1 AND partidosPorCumplir = 2
                                  AND suspensionesTotales = (SELECT COUNT(*) FROM Eventos.Suspension WHERE idJugador = @jugT)
                                  AND amarillas = ISNULL(@amJug, 0) AND rojas = ISNULL(@roJug, 0)
                                  AND detalleSuspensiones LIKE N'%Activa%manual%'
                                  AND detalleSuspensiones NOT LIKE N'%Cumplida%')
                   THEN 1 ELSE 0 END;
    SET @txt = N'El reporte con la suspensión activa no tiene la fila esperada del jugador (ver el SELECT del reporte).';

    EXEC Eventos.Suspension_Baja @id = @idSusp;
    SET @ok = CASE WHEN @ok = 1 AND (SELECT COUNT(*) FROM Eventos.Suspension) = @nSusp THEN 1 ELSE 0 END;
    EXEC #Resultado 'PRUEBA 2.4', @ok, N'Suspensión activa informada (1 activa, 2 partidos por cumplir) sin multiplicar las tarjetas.', @txt;
END TRY
BEGIN CATCH
    SET @txt = N'Error inesperado ' + CAST(ERROR_NUMBER() AS nvarchar(10)) + N': ' + ERROR_MESSAGE();
    EXEC #Resultado 'PRUEBA 2.4', 0, N'', @txt;
    EXEC #LimpiarFixture;
END CATCH;

-- PRUEBA 2.5: Selección inexistente
-- Resultado esperado: THROW 50001 "No se pudo generar el reporte de tarjetas:" + "- La selección no existe."
SET @esperado = N'No se pudo generar el reporte de tarjetas:' + CHAR(10) + N'- La selección no existe.';
BEGIN TRY
    DELETE FROM #repT;
    INSERT INTO #repT EXEC Eventos.Reporte_Tarjetas @idSeleccion = -999;
    EXEC #Resultado 'PRUEBA 2.5', 0, N'', N'No detectó la selección inexistente.';
END TRY
BEGIN CATCH
    SET @ok = CASE WHEN ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() = @esperado THEN 1 ELSE 0 END;
    SET @txt = N'Código o mensaje inesperado: ' + CAST(ERROR_NUMBER() AS nvarchar(10)) + N' - ' + ERROR_MESSAGE();
    EXEC #Resultado 'PRUEBA 2.5', @ok, N'Selección inexistente rechazada (50001).', @txt;
END CATCH;

DROP TABLE #repT;
GO

/* =============================================================================
   SECCIÓN 3: Arbitraje.Reporte_DesignacionesArbitrales
   Un result set de una fila y una columna xml: se captura con INSERT ... EXEC.
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 3. PRUEBAS: Arbitraje.Reporte_DesignacionesArbitrales';
PRINT '--------------------------------------------------------------------------------';

IF OBJECT_ID('tempdb..#repD') IS NOT NULL DROP TABLE #repD;
CREATE TABLE #repD (reporteXML xml NULL);

DECLARE @ok bit, @txt nvarchar(2200), @esperado nvarchar(2000), @x xml;
DECLARE @nArb int, @nPart int, @nTarjNodos int;

SELECT @nArb = COUNT(DISTINCT idArbitro), @nPart = COUNT(*) FROM Arbitraje.cuerpoArbitral;
SELECT @nTarjNodos = ISNULL(SUM(t.n), 0)
FROM Arbitraje.cuerpoArbitral ca
JOIN (SELECT idPartido, COUNT(*) AS n FROM Eventos.Tarjeta GROUP BY idPartido) t ON t.idPartido = ca.idPartido;

-- PRUEBA 3.1: Reporte exitoso sin filtro
-- Resultado esperado: una fila y una columna 'reporteXML' de tipo xml, con raíz DesignacionesArbitrales,
--   un nodo <Arbitro> por árbitro designado, un <Partido> por designación y un <Tarjeta> por cada
--   tarjeta de cada partido de cada árbitro (cada tarjeta se repite en los árbitros del partido).
--   Con el seed: 20 árbitros, 155 partidos y 355 tarjetas (5 árbitros por partido x 71 tarjetas).
--   A ojo: el primer partido del primer árbitro queda en el log; el XML completo se ve en
--   la columna reporteXML (en SSMS, clic sobre el valor).
BEGIN TRY
    DELETE FROM #repD;
    INSERT INTO #repD EXEC Arbitraje.Reporte_DesignacionesArbitrales;
    SELECT @x = reporteXML FROM #repD;

    SELECT N'EVIDENCIA 3.1' AS momento,
           @x.value('count(/DesignacionesArbitrales/Arbitro)', 'int') AS arbitros,
           @x.value('count(/DesignacionesArbitrales/Arbitro/Partido)', 'int') AS partidos,
           @x.value('count(/DesignacionesArbitrales/Arbitro/Partido/Tarjetas/Tarjeta)', 'int') AS tarjetas,
           @nArb AS arbitrosEsperados, @nPart AS partidosEsperados, @nTarjNodos AS tarjetasEsperadas;
    SELECT N'MUESTRA 3.1 (primer partido del primer árbitro)' AS momento,
           @x.query('/DesignacionesArbitrales/Arbitro[1]/Partido[1]') AS muestra;

    SET @ok = CASE WHEN (SELECT COUNT(*) FROM #repD) = 1
                    AND (SELECT COUNT(*) FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID(N'Arbitraje.Reporte_DesignacionesArbitrales'), 0)) = 1
                    AND EXISTS (SELECT 1 FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID(N'Arbitraje.Reporte_DesignacionesArbitrales'), 0)
                                WHERE name = 'reporteXML' AND system_type_name = 'xml')
                    AND @x.exist('/DesignacionesArbitrales') = 1
                    AND @x.value('count(/DesignacionesArbitrales/Arbitro)', 'int') = @nArb
                    AND @x.value('count(/DesignacionesArbitrales/Arbitro/Partido)', 'int') = @nPart
                    AND @x.value('count(/DesignacionesArbitrales/Arbitro/Partido/Tarjetas/Tarjeta)', 'int') = @nTarjNodos
                   THEN 1 ELSE 0 END;
    EXEC #Resultado 'PRUEBA 3.1', @ok, N'XML válido con todos los árbitros, sus partidos y las tarjetas de cada partido.',
         N'El XML (una fila, columna reporteXML) no tiene la cantidad esperada de árbitros, partidos o tarjetas (ver el SELECT de evidencia).';
END TRY
BEGIN CATCH
    SET @txt = N'Error inesperado ' + CAST(ERROR_NUMBER() AS nvarchar(10)) + N': ' + ERROR_MESSAGE();
    EXEC #Resultado 'PRUEBA 3.1', 0, N'', @txt;
END CATCH;

-- PRUEBA 3.2: Filtro por árbitro (el árbitro del seed con más designaciones)
-- Resultado esperado: el XML contiene un solo <Arbitro> (el indicado) con exactamente sus partidos y
--   roles (los de Arbitraje.cuerpoArbitral) y las tarjetas de esos partidos. A ojo: el XML y el
--   detalle de partidos del árbitro quedan en el log.
DECLARE @arbT int, @nPartArb int, @nTarjArb int;
SELECT TOP 1 @arbT = idArbitro, @nPartArb = COUNT(*)
FROM Arbitraje.cuerpoArbitral
GROUP BY idArbitro
ORDER BY COUNT(*) DESC, idArbitro;

SELECT @nTarjArb = ISNULL(SUM(t.n), 0)
FROM Arbitraje.cuerpoArbitral ca
JOIN (SELECT idPartido, COUNT(*) AS n FROM Eventos.Tarjeta GROUP BY idPartido) t ON t.idPartido = ca.idPartido
WHERE ca.idArbitro = @arbT;

DECLARE @nodos TABLE (nroPartido int NULL, rol varchar(20) NULL);
BEGIN TRY
    DELETE FROM #repD;
    INSERT INTO #repD EXEC Arbitraje.Reporte_DesignacionesArbitrales @idArbitro = @arbT;
    SELECT @x = reporteXML FROM #repD;

    INSERT INTO @nodos (nroPartido, rol)
    SELECT n.p.value('@nroPartido', 'int'), n.p.value('@rol', 'varchar(20)')
    FROM @x.nodes('/DesignacionesArbitrales/Arbitro/Partido') n (p);

    SELECT N'XML 3.2' AS momento, @x AS reporteXML;
    SELECT N'PARTIDOS DEL ARBITRO 3.2' AS momento, nroPartido, rol FROM @nodos ORDER BY nroPartido;

    SET @ok = CASE WHEN (SELECT COUNT(*) FROM #repD) = 1
                    AND @x.value('count(/DesignacionesArbitrales/Arbitro)', 'int') = 1
                    AND @x.value('(/DesignacionesArbitrales/Arbitro/@idArbitro)[1]', 'int') = @arbT
                    AND (SELECT COUNT(*) FROM @nodos) = @nPartArb
                    AND NOT EXISTS (SELECT nroPartido, rol FROM @nodos
                                    EXCEPT
                                    SELECT p.nroPartidoOficial, ca.rol
                                    FROM Arbitraje.cuerpoArbitral ca JOIN Torneo.Partido p ON p.idPartido = ca.idPartido
                                    WHERE ca.idArbitro = @arbT)
                    AND NOT EXISTS (SELECT p.nroPartidoOficial, ca.rol
                                    FROM Arbitraje.cuerpoArbitral ca JOIN Torneo.Partido p ON p.idPartido = ca.idPartido
                                    WHERE ca.idArbitro = @arbT
                                    EXCEPT
                                    SELECT nroPartido, rol FROM @nodos)
                    AND @x.value('count(/DesignacionesArbitrales/Arbitro/Partido/Tarjetas/Tarjeta)', 'int') = @nTarjArb
                   THEN 1 ELSE 0 END;
    EXEC #Resultado 'PRUEBA 3.2', @ok, N'Solo el árbitro indicado, con sus partidos, roles y tarjetas.',
         N'El XML filtrado no contiene exactamente al árbitro indicado con sus partidos, roles y tarjetas.';
END TRY
BEGIN CATCH
    SET @txt = N'Error inesperado ' + CAST(ERROR_NUMBER() AS nvarchar(10)) + N': ' + ERROR_MESSAGE();
    EXEC #Resultado 'PRUEBA 3.2', 0, N'', @txt;
END CATCH;

-- PRUEBA 3.3: Árbitro sin designaciones (alta con Arbitro_Alta, baja al terminar con Arbitro_Baja)
-- Resultado esperado: una fila con la raíz vacía <DesignacionesArbitrales /> (sin ningún nodo hijo).
DECLARE @idArbNuevo int, @arbitrosAntes int, @idPaisArb int = (SELECT MIN(id) FROM Torneo.Pais);
SELECT @arbitrosAntes = COUNT(*) FROM Arbitraje.Arbitro;
BEGIN TRY
    EXEC Arbitraje.Arbitro_Alta @idPais = @idPaisArb, @nombre = N'Test', @apellido = N'QRep Arbitro Sin Partidos',
         @categoria = 'FIFA', @idArbitro = @idArbNuevo OUTPUT;

    DELETE FROM #repD;
    INSERT INTO #repD EXEC Arbitraje.Reporte_DesignacionesArbitrales @idArbitro = @idArbNuevo;
    SELECT @x = reporteXML FROM #repD;
    SELECT N'ARBITRO SIN DESIGNACIONES 3.3' AS momento, @idArbNuevo AS idArbitro, CAST(@x AS nvarchar(200)) AS reporteXML;

    SET @ok = CASE WHEN (SELECT COUNT(*) FROM #repD) = 1
                    AND @x IS NOT NULL
                    AND @x.exist('/DesignacionesArbitrales') = 1
                    AND @x.value('count(/DesignacionesArbitrales/*)', 'int') = 0
                   THEN 1 ELSE 0 END;

    EXEC Arbitraje.Arbitro_Baja @idArbitro = @idArbNuevo;
    SET @ok = CASE WHEN @ok = 1 AND (SELECT COUNT(*) FROM Arbitraje.Arbitro) = @arbitrosAntes THEN 1 ELSE 0 END;
    EXEC #Resultado 'PRUEBA 3.3', @ok, N'Árbitro sin designaciones: raíz vacía <DesignacionesArbitrales />.',
         N'El reporte de un árbitro sin designaciones no devolvió la raíz vacía.';
END TRY
BEGIN CATCH
    SET @txt = N'Error inesperado ' + CAST(ERROR_NUMBER() AS nvarchar(10)) + N': ' + ERROR_MESSAGE();
    EXEC #Resultado 'PRUEBA 3.3', 0, N'', @txt;
    EXEC #LimpiarFixture;
END CATCH;

-- PRUEBA 3.4: Árbitro inexistente
-- Resultado esperado: THROW 50001 "No se pudo generar el reporte de designaciones arbitrales:" + "- El árbitro no existe."
SET @esperado = N'No se pudo generar el reporte de designaciones arbitrales:' + CHAR(10) + N'- El árbitro no existe.';
BEGIN TRY
    DELETE FROM #repD;
    INSERT INTO #repD EXEC Arbitraje.Reporte_DesignacionesArbitrales @idArbitro = -999;
    EXEC #Resultado 'PRUEBA 3.4', 0, N'', N'No detectó el árbitro inexistente.';
END TRY
BEGIN CATCH
    SET @ok = CASE WHEN ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() = @esperado THEN 1 ELSE 0 END;
    SET @txt = N'Código o mensaje inesperado: ' + CAST(ERROR_NUMBER() AS nvarchar(10)) + N' - ' + ERROR_MESSAGE();
    EXEC #Resultado 'PRUEBA 3.4', @ok, N'Árbitro inexistente rechazado (50001).', @txt;
END CATCH;

DROP TABLE #repD;
GO

/* =============================================================================
   LIMPIEZA FINAL DEL ENTORNO DE PRUEBAS Y RESUMEN
   ============================================================================= */
PRINT '--- Limpiando fixture auxiliar de pruebas ---';

EXEC #LimpiarFixture;

-- PRUEBA 4.1: Limpieza final sin residuos
-- Resultado esperado: Eventos.Gol, Eventos.Suspension y Arbitraje.Arbitro (más Eventos.Tarjeta y
--   Arbitraje.cuerpoArbitral, que las pruebas no tocan) tienen las mismas filas que al inicio.
DECLARE @ok bit;
SET @ok = CASE WHEN NOT EXISTS (SELECT 1
                                FROM #base b
                                JOIN (SELECT 'Gol' AS tabla, COUNT(*) AS n FROM Eventos.Gol
                                      UNION ALL SELECT 'Suspension', COUNT(*) FROM Eventos.Suspension
                                      UNION ALL SELECT 'Arbitro',    COUNT(*) FROM Arbitraje.Arbitro
                                      UNION ALL SELECT 'Tarjeta',    COUNT(*) FROM Eventos.Tarjeta
                                      UNION ALL SELECT 'cuerpoArbitral', COUNT(*) FROM Arbitraje.cuerpoArbitral) a ON a.tabla = b.tabla
                                WHERE a.n <> b.n)
               THEN 1 ELSE 0 END;
EXEC #Resultado 'PRUEBA 4.1', @ok, N'Sin residuos: las tablas tocadas volvieron a la cantidad de filas inicial.',
     N'Quedaron filas de prueba en Eventos.Gol, Eventos.Suspension o Arbitraje.Arbitro.';

DECLARE @total int, @nOk int, @nFallo int, @precond varchar(20);
SELECT @total = COUNT(*), @nOk = ISNULL(SUM(CAST(ok AS int)), 0) FROM #res WHERE titulo LIKE 'PRUEBA%';
SET @nFallo = @total - @nOk;
SELECT @precond = CASE WHEN ok = 1 THEN 'cumplida' ELSE 'NO cumplida' END FROM #res WHERE titulo = 'PRECONDICION';

IF OBJECT_ID('tempdb..#fx')       IS NOT NULL DROP TABLE #fx;
IF OBJECT_ID('tempdb..#fxJug')    IS NOT NULL DROP TABLE #fxJug;
IF OBJECT_ID('tempdb..#fxT')      IS NOT NULL DROP TABLE #fxT;
IF OBJECT_ID('tempdb..#esp')      IS NOT NULL DROP TABLE #esp;
IF OBJECT_ID('tempdb..#cred')     IS NOT NULL DROP TABLE #cred;
IF OBJECT_ID('tempdb..#expFilas') IS NOT NULL DROP TABLE #expFilas;
IF OBJECT_ID('tempdb..#base')     IS NOT NULL DROP TABLE #base;
IF OBJECT_ID('tempdb..#LimpiarFixture') IS NOT NULL DROP PROCEDURE #LimpiarFixture;
IF OBJECT_ID('tempdb..#Resultado') IS NOT NULL DROP PROCEDURE #Resultado;
IF OBJECT_ID('tempdb..#res')      IS NOT NULL DROP TABLE #res;

PRINT 'Fixture de pruebas limpiado con éxito.';
PRINT '================================================================================';
PRINT ' BATERÍA DE PRUEBAS DE REPORTES FINALIZADA: ' + CAST(@total AS varchar(10)) + ' pruebas (precondición ' + @precond + ')';
PRINT '   1. Reporte_Goleadores: 7 | 2. Reporte_Tarjetas: 5 | 3. Reporte_DesignacionesArbitrales: 4 | 4. Limpieza: 1';
PRINT '   Resultado: OK = ' + CAST(@nOk AS varchar(10)) + ' | FALLO = ' + CAST(@nFallo AS varchar(10));
PRINT '================================================================================';
GO
