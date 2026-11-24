/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 23/11/2026

 Objetivo    : Entrega 8 (cifrado) - Reportes que muestran nombres de jugadores,
               cuerpo técnico y árbitros, ahora leyendo de las vistas de descifrado:
               - Equipos.Reporte_SeleccionesPlantillas   (script 60)
               - Eventos.Reporte_Goleadores              (script 61)
               - Eventos.Reporte_Tarjetas                (script 61)
               - Arbitraje.Reporte_DesignacionesArbitrales (script 61)
               Decisión: los 4 reportes siguen devolviendo los nombres en claro
               (la entrega 7 los pide) y el acceso se controla con GRANT EXECUTE.
               Cada uno se declara WITH EXECUTE AS OWNER para poder descifrar sin
               darle permisos sobre el certificado ni la clave a ningún rol.
               Mismas firmas y mismo resultado; los GROUP BY y ORDER BY por nombre
               se calculan sobre el valor descifrado. Se redefinen con CREATE OR
               ALTER: los scripts 60 y 61 no se modifican.
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

/* =============================================================================
   1. SP: Equipos.Reporte_SeleccionesPlantillas (XML)
   Estructura:
     <selecciones>
       <seleccion id pais abreviacion confederacion grupo cantidadConvocados>
         <convocados>
           <jugador dorsal [fechaBaja] [motivoBaja]>
             <nombre/> <posicion/> <club/>
           </jugador>
         </convocados>
       </seleccion>
     </selecciones>
   ============================================================================= */
CREATE OR ALTER PROCEDURE Equipos.Reporte_SeleccionesPlantillas
    @idSeleccion  int = NULL,
    @soloActivos  bit = 1
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @soloActivos = ISNULL(@soloActivos, 1);

    IF @idSeleccion IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE id = @idSeleccion)
        SET @errores += CHAR(10) + N'- La selección no existe.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo generar el reporte de selecciones y plantillas:' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- Los atributos tienen que ir antes que los elementos hijos en cada SELECT
    SELECT (
        SELECT s.id                AS '@id',
               p.nombre            AS '@pais',
               s.abreviacion       AS '@abreviacion',
               s.confederacion     AS '@confederacion',
               s.grupo             AS '@grupo',
               (SELECT COUNT(*)
                FROM Equipos.ListadoJugadores c
                WHERE c.idSeleccion = s.id AND (@soloActivos = 0 OR c.fechaBaja IS NULL)) AS '@cantidadConvocados',
               (SELECT lj.dorsal                AS '@dorsal',
                       lj.fechaBaja             AS '@fechaBaja',
                       lj.motivoBaja            AS '@motivoBaja',
                       j.nombre + N' ' + j.apellido AS 'nombre',
                       j.posicion               AS 'posicion',
                       j.club                   AS 'club'
                FROM Equipos.ListadoJugadores lj
                JOIN Equipos.vw_Jugador j ON j.id = lj.idJugador
                WHERE lj.idSeleccion = s.id AND (@soloActivos = 0 OR lj.fechaBaja IS NULL)
                ORDER BY lj.dorsal, lj.id
                FOR XML PATH('jugador'), ROOT('convocados'), TYPE)
        FROM Equipos.Seleccion s
        JOIN Torneo.Pais p ON p.id = s.idPais
        WHERE (@idSeleccion IS NULL OR s.id = @idSeleccion)
        ORDER BY p.nombre
        FOR XML PATH('seleccion'), ROOT('selecciones'), TYPE
    ) AS plantillas;
END
GO

/* =============================================================================
   2. Eventos.Reporte_Goleadores
   Parámetros (ambos opcionales):
   - @idSeleccion : solo goles de esa selección (en (a) y (b) los que convirtieron
                    sus jugadores; en (c) los que se le acreditan, incluidos los
                    'En contra' del rival).
   - @idFase      : solo goles de partidos de esa fase.
   Devuelve 3 result sets:
   (a) Goleadores por selección y fase (jugador, goles), sin 'En contra'.
   (b) Tabla de goleadores del torneo: acumulado por jugador con RANK. El puesto
       se calcula sobre todas las selecciones (y las fases consideradas por
       @idFase), antes de aplicar @idSeleccion: con ese filtro se ve el puesto
       real del jugador, no el puesto dentro de su selección.
   (c) Totales por selección y fase con ROLLUP: subtotal por selección y fila
       final. Sin filtros la fila final es 'TOTAL DEL TORNEO' / 'Todas las
       fases'; con @idSeleccion o @idFase suma solo lo filtrado y se rotula
       'TOTAL (filtrado)' (con @idFase, la fase muestra su nombre).
       goles = convertidos por sus jugadores;
       golesEnContraAFavor = 'En contra' que le suma el rival; golesTotales = suma.
   ============================================================================= */

CREATE OR ALTER PROCEDURE Eventos.Reporte_Goleadores
    @idSeleccion int = NULL,
    @idFase      int = NULL
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    -- 1. Validaciones acumulativas
    IF @idSeleccion IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE id = @idSeleccion)
        SET @errores += CHAR(10) + N'- La selección no existe.';

    IF @idFase IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = @idFase)
        SET @errores += CHAR(10) + N'- La fase no existe.';

    -- 2. Corte único con THROW
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo generar el reporte de goleadores:' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- Rótulo de la fase en la fila final de (c): el nombre de la fase filtrada o
    -- 'Todas las fases' si no se filtra por fase.
    DECLARE @nombreFase nvarchar(60) = ISNULL((SELECT nombre FROM Torneo.Fase WHERE idFase = @idFase),
                                              N'Todas las fases');

    -- 3. Goles del reporte (sin la definición por penales), una sola vez para
    --    los tres resultados. Variable de tabla: no deja objetos persistentes.
    DECLARE @goles TABLE (
        idGol               int PRIMARY KEY,
        idJugador           int NOT NULL,
        idSeleccionAutor    int NOT NULL,
        idSeleccionAcredita int NOT NULL,
        idFase              int NOT NULL,
        esEnContra          bit NOT NULL
    );

    INSERT INTO @goles (idGol, idJugador, idSeleccionAutor, idSeleccionAcredita, idFase, esEnContra)
    SELECT g.idGol,
           g.idJugador,
           fp.idSeleccion,
           CASE WHEN g.tipo = 'En contra'
                THEN CASE WHEN fp.idSeleccion = p.idSeleccionLocal
                          THEN p.idSeleccionVisitante
                          ELSE p.idSeleccionLocal END
                ELSE fp.idSeleccion END,
           p.fase,
           CASE WHEN g.tipo = 'En contra' THEN 1 ELSE 0 END
    FROM Eventos.Gol g
    JOIN Torneo.Partido p            ON p.idPartido  = g.idPartido
    JOIN Eventos.FormacionPartido fp ON fp.idPartido = g.idPartido
                                    AND fp.idJugador = g.idJugador
    WHERE g.minuto IS NOT NULL
      AND (@idFase IS NULL OR p.fase = @idFase);

    -- (a) Goleadores por selección y fase
    SELECT s.id                                 AS idSeleccion,
           ps.nombre                            AS seleccion,
           f.idFase,
           f.nombre                             AS fase,
           f.orden                              AS ordenFase,
           j.id                                 AS idJugador,
           j.apellido + N', ' + j.nombre        AS jugador,
           COUNT(*)                             AS goles
    FROM @goles gl
    JOIN Equipos.Seleccion s ON s.id  = gl.idSeleccionAutor
    JOIN Torneo.Pais ps      ON ps.id = s.idPais
    JOIN Torneo.Fase f       ON f.idFase = gl.idFase
    JOIN Equipos.vw_Jugador j   ON j.id  = gl.idJugador
    WHERE gl.esEnContra = 0
      AND (@idSeleccion IS NULL OR gl.idSeleccionAutor = @idSeleccion)
    GROUP BY s.id, ps.nombre, f.idFase, f.nombre, f.orden, j.id, j.apellido, j.nombre
    ORDER BY ps.nombre, f.orden, COUNT(*) DESC, j.apellido, j.nombre, j.id;

    -- (b) Tabla de goleadores del torneo (acumulado de las fases consideradas).
    --     El RANK se calcula sobre todas las selecciones y recién después se filtra
    --     por @idSeleccion, así el puesto es el del torneo y no el de la selección.
    WITH acumulado AS (
        SELECT RANK() OVER (ORDER BY COUNT(*) DESC)  AS ranking,
               s.id                                  AS idSeleccion,
               ps.nombre                             AS seleccion,
               j.id                                  AS idJugador,
               j.apellido + N', ' + j.nombre         AS jugador,
               COUNT(*)                              AS goles
        FROM @goles gl
        JOIN Equipos.Seleccion s ON s.id  = gl.idSeleccionAutor
        JOIN Torneo.Pais ps      ON ps.id = s.idPais
        JOIN Equipos.vw_Jugador j   ON j.id  = gl.idJugador
        WHERE gl.esEnContra = 0
        GROUP BY s.id, ps.nombre, j.id, j.apellido, j.nombre
    )
    SELECT ranking, idSeleccion, seleccion, idJugador, jugador, goles
    FROM acumulado
    WHERE @idSeleccion IS NULL OR idSeleccion = @idSeleccion
    ORDER BY ranking, seleccion, jugador, idJugador;

    -- (c) Totales por selección y fase, con subtotal por selección y total final.
    --     La fila final se rotula 'TOTAL DEL TORNEO' solo si no hay filtros: con
    --     @idSeleccion o @idFase suma únicamente lo filtrado ('TOTAL (filtrado)').
    SELECT CASE WHEN GROUPING(s.id) = 1 THEN NULL ELSE s.id END AS idSeleccion,
           CASE WHEN GROUPING(s.id) = 1
                THEN CASE WHEN @idSeleccion IS NULL AND @idFase IS NULL
                          THEN N'TOTAL DEL TORNEO' ELSE N'TOTAL (filtrado)' END
                ELSE ps.nombre END                            AS seleccion,
           CASE WHEN GROUPING(f.idFase) = 1 THEN NULL ELSE f.idFase END AS idFase,
           CASE WHEN GROUPING(f.idFase) = 0 THEN f.nombre
                WHEN GROUPING(s.id) = 1     THEN @nombreFase
                ELSE N'Total de la selección' END             AS fase,
           SUM(CASE WHEN gl.esEnContra = 0 THEN 1 ELSE 0 END) AS goles,
           SUM(CASE WHEN gl.esEnContra = 1 THEN 1 ELSE 0 END) AS golesEnContraAFavor,
           COUNT(*)                                           AS golesTotales
    FROM @goles gl
    JOIN Equipos.Seleccion s ON s.id  = gl.idSeleccionAcredita
    JOIN Torneo.Pais ps      ON ps.id = s.idPais
    JOIN Torneo.Fase f       ON f.idFase = gl.idFase
    WHERE @idSeleccion IS NULL OR gl.idSeleccionAcredita = @idSeleccion
    GROUP BY ROLLUP ((s.id, ps.nombre), (f.idFase, f.nombre, f.orden))
    ORDER BY GROUPING(s.id), ps.nombre, GROUPING(f.idFase), f.orden;
END;
GO

/* =============================================================================
   3. Eventos.Reporte_Tarjetas
   Un solo listado: una fila por persona (jugador o integrante del cuerpo
   técnico) con alguna tarjeta o alguna suspensión.
   - @idSeleccion : solo personas de esa selección (opcional).
   - @soloActivas : 1 = solo personas con al menos una suspensión activa
                    (partidosRestantes > 0) y detalleSuspensiones con las
                    activas; 0 = todas. Los contadores son siempre los reales.
   - Selección: la del jugador es la de su Eventos.FormacionPartido; la del
     staff, Equipos.Staff.idSeleccion.
   - Tarjetas y suspensiones se agregan en OUTER APPLY separados: las
     suspensiones no multiplican las filas de tarjetas ni al revés.
   - detalleSuspensiones: una frase por suspensión (partido nro oficial donde se
     generó, cantidad, restantes, estado y tarjeta de origen o 'manual').
   ============================================================================= */

CREATE OR ALTER PROCEDURE Eventos.Reporte_Tarjetas
    @idSeleccion int = NULL,
    @soloActivas bit = 0
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    -- 1. Validaciones acumulativas
    IF @idSeleccion IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE id = @idSeleccion)
        SET @errores += CHAR(10) + N'- La selección no existe.';

    -- 2. Corte único con THROW
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo generar el reporte de tarjetas:' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- 3. Listado. tarj/susp normalizan a la persona: (tipoPersona, idPersona).
    WITH tarj AS (
        SELECT CASE WHEN t.idJugador IS NOT NULL THEN 'Jugador' ELSE 'Cuerpo tecnico' END AS tipoPersona,
               COALESCE(t.idJugador, t.idStaff) AS idPersona,
               t.color,
               t.tipoRoja
        FROM Eventos.Tarjeta t
    ),
    susp AS (
        SELECT CASE WHEN s.idJugador IS NOT NULL THEN 'Jugador' ELSE 'Cuerpo tecnico' END AS tipoPersona,
               COALESCE(s.idJugador, s.idStaff) AS idPersona,
               s.id,
               s.idPartido,
               s.cantPartidos,
               s.partidosRestantes,
               s.idTarjeta
        FROM Eventos.Suspension s
    ),
    personas AS (
        SELECT tipoPersona, idPersona FROM tarj
        UNION
        SELECT tipoPersona, idPersona FROM susp
    ),
    datos AS (
        SELECT pe.tipoPersona,
               pe.idPersona,
               CASE WHEN pe.tipoPersona = 'Jugador' THEN fpj.idSeleccion ELSE st.idSeleccion END AS idSeleccion,
               CASE WHEN pe.tipoPersona = 'Jugador' THEN j.apellido ELSE st.apellido END         AS apellido,
               CASE WHEN pe.tipoPersona = 'Jugador' THEN j.nombre   ELSE st.nombre   END         AS nombre,
               CASE WHEN pe.tipoPersona = 'Jugador' THEN j.posicion ELSE st.rol      END         AS posicionORol
        FROM personas pe
        LEFT JOIN Equipos.vw_Jugador j ON pe.tipoPersona = 'Jugador'        AND j.id  = pe.idPersona
        LEFT JOIN Equipos.vw_Staff st  ON pe.tipoPersona = 'Cuerpo tecnico' AND st.id = pe.idPersona
        OUTER APPLY (SELECT MIN(fp.idSeleccion) AS idSeleccion
                     FROM Eventos.FormacionPartido fp
                     WHERE pe.tipoPersona = 'Jugador'
                       AND fp.idJugador   = pe.idPersona) fpj
    )
    SELECT d.idSeleccion,
           ps.nombre                                   AS seleccion,
           d.tipoPersona,
           d.apellido + N', ' + d.nombre               AS persona,
           d.posicionORol,
           tj.amarillas,
           tj.rojas,
           tj.rojasDirectas,
           tj.rojasDobleAmarilla,
           sp.suspensionesActivas,
           sp.partidosPorCumplir,
           sp.suspensionesTotales,
           sp.detalleSuspensiones
    FROM datos d
    LEFT JOIN Equipos.Seleccion s ON s.id  = d.idSeleccion
    LEFT JOIN Torneo.Pais ps      ON ps.id = s.idPais
    OUTER APPLY (SELECT ISNULL(SUM(CASE WHEN t.color = 'A' THEN 1 ELSE 0 END), 0) AS amarillas,
                        ISNULL(SUM(CASE WHEN t.color = 'R' THEN 1 ELSE 0 END), 0) AS rojas,
                        ISNULL(SUM(CASE WHEN t.tipoRoja = 'Directa' THEN 1 ELSE 0 END), 0)        AS rojasDirectas,
                        ISNULL(SUM(CASE WHEN t.tipoRoja = 'Doble amarilla' THEN 1 ELSE 0 END), 0) AS rojasDobleAmarilla
                 FROM tarj t
                 WHERE t.tipoPersona = d.tipoPersona
                   AND t.idPersona   = d.idPersona) tj
    OUTER APPLY (SELECT ISNULL(SUM(CASE WHEN su.partidosRestantes > 0 THEN 1 ELSE 0 END), 0)                 AS suspensionesActivas,
                        ISNULL(SUM(CASE WHEN su.partidosRestantes > 0 THEN su.partidosRestantes ELSE 0 END), 0) AS partidosPorCumplir,
                        COUNT(su.id)                                                                         AS suspensionesTotales,
                        STRING_AGG(
                            CASE WHEN @soloActivas = 1 AND su.partidosRestantes = 0 THEN NULL
                                 ELSE CONCAT(N'Partido ',
                                             ISNULL(CAST(pa.nroPartidoOficial AS nvarchar(10)),
                                                    N'id ' + CAST(pa.idPartido AS nvarchar(10))),
                                             N': ', su.cantPartidos, N' partido(s), restan ', su.partidosRestantes,
                                             N' (', CASE WHEN su.partidosRestantes > 0 THEN N'Activa' ELSE N'Cumplida' END,
                                             N'), origen: ',
                                             CASE WHEN su.idTarjeta IS NULL THEN N'manual'
                                                  ELSE CONCAT(CASE WHEN tt.color = 'R' THEN N'roja' ELSE N'amarilla' END,
                                                              N' min ', tt.minuto,
                                                              CASE WHEN tt.minutoAdicional IS NULL THEN N''
                                                                   ELSE CONCAT(N'+', tt.minutoAdicional) END)
                                             END) END,
                            N' | ') WITHIN GROUP (ORDER BY pa.fechaHoraUTC, su.id)                           AS detalleSuspensiones
                 FROM susp su
                 JOIN Torneo.Partido pa     ON pa.idPartido = su.idPartido
                 LEFT JOIN Eventos.Tarjeta tt ON tt.idTarjeta = su.idTarjeta
                 WHERE su.tipoPersona = d.tipoPersona
                   AND su.idPersona   = d.idPersona) sp
    WHERE (@idSeleccion IS NULL OR d.idSeleccion = @idSeleccion)
      AND (ISNULL(@soloActivas, 0) = 0 OR sp.suspensionesActivas > 0)
    ORDER BY ps.nombre, d.tipoPersona, tj.rojas DESC, tj.amarillas DESC, d.apellido, d.nombre, d.idPersona;
END;
GO

/* =============================================================================
   4. Arbitraje.Reporte_DesignacionesArbitrales
   Un result set de una fila y una columna (reporteXML, tipo xml):
     <DesignacionesArbitrales>
       <Arbitro idArbitro nombre pais categoria>
         <Partido nroPartido fechaHoraUTC fase local visitante marcador estado rol>
           <Tarjetas total amarillas rojas>
             <Tarjeta color minuto minutoAdicional tipoRoja motivo tipoPersona
                      persona seleccion/>
   - Un <Partido> por cada designación del árbitro (en cualquier rol; el rol va
     como atributo), ordenados por fecha. Árbitros ordenados por apellido.
   - <Tarjetas> reúne las tarjetas del partido de ambas selecciones (jugadores y
     cuerpo técnico).
   - Un árbitro sin designaciones no aparece; con @idArbitro de un árbitro sin
     partidos devuelve la raíz vacía.
   - Los atributos NULL (marcador sin resultado, tipoRoja de una amarilla...)
     se omiten del XML.
   ============================================================================= */

CREATE OR ALTER PROCEDURE Arbitraje.Reporte_DesignacionesArbitrales
    @idArbitro int = NULL
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    -- 1. Validaciones acumulativas
    IF @idArbitro IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM Arbitraje.Arbitro WHERE idArbitro = @idArbitro)
        SET @errores += CHAR(10) + N'- El árbitro no existe.';

    -- 2. Corte único con THROW
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo generar el reporte de designaciones arbitrales:' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- 3. XML anidado con subconsultas correlacionadas (FOR XML PATH ... TYPE).
    --    ISNULL: si no hay árbitros, la raíz vacía en vez de NULL.
    SELECT ISNULL(
           (SELECT a.idArbitro                      AS '@idArbitro',
                   a.apellido + N', ' + a.nombre    AS '@nombre',
                   pa.nombre                        AS '@pais',
                   a.categoria                      AS '@categoria',
                   (SELECT p.nroPartidoOficial      AS '@nroPartido',
                           p.fechaHoraUTC           AS '@fechaHoraUTC',
                           f.nombre                 AS '@fase',
                           pl.nombre                AS '@local',
                           pv.nombre                AS '@visitante',
                           CASE WHEN p.golLocal IS NOT NULL AND p.golVisitante IS NOT NULL
                                THEN CONCAT(p.golLocal, N'-', p.golVisitante) END AS '@marcador',
                           p.estado                 AS '@estado',
                           ca.rol                   AS '@rol',
                           (SELECT tt.total         AS '@total',
                                   tt.amarillas     AS '@amarillas',
                                   tt.rojas         AS '@rojas',
                                   (SELECT t.color           AS '@color',
                                           t.minuto          AS '@minuto',
                                           t.minutoAdicional AS '@minutoAdicional',
                                           t.tipoRoja        AS '@tipoRoja',
                                           t.motivo          AS '@motivo',
                                           CASE WHEN t.idJugador IS NOT NULL THEN N'Jugador'
                                                ELSE N'Cuerpo tecnico' END AS '@tipoPersona',
                                           COALESCE(j.apellido + N', ' + j.nombre,
                                                    st.apellido + N', ' + st.nombre) AS '@persona',
                                           pt.nombre         AS '@seleccion'
                                    FROM Eventos.Tarjeta t
                                    LEFT JOIN Equipos.vw_Jugador j ON j.id = t.idJugador
                                    LEFT JOIN Eventos.FormacionPartido fp
                                           ON fp.idPartido = t.idPartido AND fp.idJugador = t.idJugador
                                    LEFT JOIN Equipos.vw_Staff st  ON st.id = t.idStaff
                                    LEFT JOIN Equipos.Seleccion se ON se.id = COALESCE(fp.idSeleccion, st.idSeleccion)
                                    LEFT JOIN Torneo.Pais pt    ON pt.id = se.idPais
                                    WHERE t.idPartido = p.idPartido
                                    ORDER BY t.minuto, t.minutoAdicional, t.idTarjeta
                                    FOR XML PATH('Tarjeta'), TYPE)
                            FROM (SELECT COUNT(*)                                          AS total,
                                         ISNULL(SUM(CASE WHEN x.color = 'A' THEN 1 ELSE 0 END), 0) AS amarillas,
                                         ISNULL(SUM(CASE WHEN x.color = 'R' THEN 1 ELSE 0 END), 0) AS rojas
                                  FROM Eventos.Tarjeta x
                                  WHERE x.idPartido = p.idPartido) tt
                            FOR XML PATH('Tarjetas'), TYPE)
                    FROM Arbitraje.cuerpoArbitral ca
                    JOIN Torneo.Partido p       ON p.idPartido = ca.idPartido
                    JOIN Torneo.Fase f          ON f.idFase    = p.fase
                    JOIN Equipos.Seleccion sl   ON sl.id       = p.idSeleccionLocal
                    JOIN Torneo.Pais pl         ON pl.id       = sl.idPais
                    JOIN Equipos.Seleccion sv   ON sv.id       = p.idSeleccionVisitante
                    JOIN Torneo.Pais pv         ON pv.id       = sv.idPais
                    WHERE ca.idArbitro = a.idArbitro
                    ORDER BY p.fechaHoraUTC, p.idPartido
                    FOR XML PATH('Partido'), TYPE)
            FROM Arbitraje.vw_Arbitro a
            JOIN Torneo.Pais pa ON pa.id = a.idPais
            WHERE EXISTS (SELECT 1 FROM Arbitraje.cuerpoArbitral c WHERE c.idArbitro = a.idArbitro)
              AND (@idArbitro IS NULL OR a.idArbitro = @idArbitro)
            ORDER BY a.apellido, a.nombre, a.idArbitro
            FOR XML PATH('Arbitro'), ROOT('DesignacionesArbitrales'), TYPE),
           CAST(N'<DesignacionesArbitrales />' AS xml)) AS reporteXML;
END;
GO
