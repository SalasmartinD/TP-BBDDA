/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel - 45066788
               Salas, Martín Daniel - 45205702
               Zito Padró, Ezequiel Nehuén - 46097917
 Fecha       : 09/11/2026

 Objetivo    : Función y vistas de consulta de Partidos en juego y Arbitraje:
               - Eventos.fn_EquipoEnCancha      (jugadores en cancha de ambas
                                                 selecciones en un minuto dado)
               - Eventos.vw_HistorialTitularidad (titularidad, ingresos,
                                                 salidas y expulsiones de cada
                                                 jugador por partido)
               - Arbitraje.vw_HistorialArbitro  (partidos dirigidos por cada
                                                 árbitro con tarjetas, informes
                                                 y sanciones)

 Estándares aplicados:
 - Nombres en formato Esquema.fn_Nombre / Esquema.vw_Nombre.
 - CREATE OR ALTER: el script puede ejecutarse varias veces.
 - Función inline (RETURNS TABLE) para que el optimizador la expanda.
 - Agregaciones con OUTER APPLY para no multiplicar filas.
 - Parámetros en @camelCase. Cero SQL dinámico, cursores o CLR.
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

/* =============================================================================
   1. Eventos.fn_EquipoEnCancha
   Jugadores en cancha de las dos selecciones en el minuto @minuto.
   - Un evento cuenta si su minuto es <= @minuto: los minutos adicionales de
     ese minuto (ej. 45+3 al consultar el 45) se consideran ya ocurridos.
   - En cancha: (titular, o entró por una sustitución con minuto <= @minuto),
     no salió por una sustitución con minuto <= @minuto y no tiene roja con
     minuto <= @minuto.
   - Dorsal: el del convocado en Equipos.ListadoJugadores; se prefiere la fila
     activa (fechaBaja NULL) y si no la de fechaAlta más reciente.
   - Si el partido no existe, no tiene formación o @minuto es NULL, devuelve
     un conjunto vacío.
   ============================================================================= */

CREATE OR ALTER FUNCTION Eventos.fn_EquipoEnCancha
(
    @idPartido int,
    @minuto    tinyint
)
RETURNS TABLE
AS
RETURN
(
    SELECT fp.idSeleccion,
           ps.nombre            AS seleccion,
           fp.idJugador,
           j.apellido,
           j.nombre,
           fp.posicion,
           lj.dorsal,
           fp.titular           AS esTitular,
           ing.minutoIngreso
    FROM Eventos.FormacionPartido fp
    JOIN Equipos.Jugador j    ON j.id  = fp.idJugador
    JOIN Equipos.Seleccion s  ON s.id  = fp.idSeleccion
    JOIN Torneo.Pais ps       ON ps.id = s.idPais
    OUTER APPLY (SELECT MIN(su.minuto) AS minutoIngreso
                 FROM Eventos.Sustitucion su
                 WHERE su.idPartido = fp.idPartido
                   AND su.idIngresa = fp.idJugador
                   AND su.minuto   <= @minuto) ing
    OUTER APPLY (SELECT TOP (1) l.dorsal
                 FROM Equipos.ListadoJugadores l
                 WHERE l.idSeleccion = fp.idSeleccion
                   AND l.idJugador   = fp.idJugador
                 ORDER BY CASE WHEN l.fechaBaja IS NULL THEN 0 ELSE 1 END,
                          l.fechaAlta DESC,
                          l.id DESC) lj
    WHERE fp.idPartido = @idPartido
      AND @minuto IS NOT NULL
      AND (fp.titular = 1 OR ing.minutoIngreso IS NOT NULL)
      AND NOT EXISTS (SELECT 1
                      FROM Eventos.Sustitucion so
                      WHERE so.idPartido = fp.idPartido
                        AND so.idSale    = fp.idJugador
                        AND so.minuto   <= @minuto)
      AND NOT EXISTS (SELECT 1
                      FROM Eventos.Tarjeta t
                      WHERE t.idPartido = fp.idPartido
                        AND t.idJugador = fp.idJugador
                        AND t.color     = 'R'
                        AND t.minuto   <= @minuto)
);
GO

/* =============================================================================
   2. Eventos.vw_HistorialTitularidad
   Una fila por jugador y partido en que estuvo en la formación.
   - minutoIngreso: minuto en que entró por un cambio (NULL si fue titular o
     no entró).
   - minutoSalida: minuto en que salió por un cambio (NULL si no salió).
   - expulsado: 1 si recibió una roja en el partido.
   ============================================================================= */

CREATE OR ALTER VIEW Eventos.vw_HistorialTitularidad
AS
SELECT fp.idJugador,
       j.apellido,
       j.nombre,
       fp.idSeleccion,
       ps.nombre                                                AS seleccion,
       p.idPartido,
       p.fechaHoraUTC,
       f.nombre                                                 AS fase,
       pr.nombre                                                AS rival,
       fp.titular,
       CAST(CASE WHEN fp.titular = 1 THEN 'Titular' ELSE 'Suplente' END AS varchar(8)) AS condicion,
       CASE WHEN fp.titular = 0 THEN ing.minutoIngreso END      AS minutoIngreso,
       sal.minutoSalida,
       CAST(CASE WHEN EXISTS (SELECT 1
                              FROM Eventos.Tarjeta t
                              WHERE t.idPartido = fp.idPartido
                                AND t.idJugador = fp.idJugador
                                AND t.color     = 'R')
                 THEN 1 ELSE 0 END AS bit)                      AS expulsado
FROM Eventos.FormacionPartido fp
JOIN Equipos.Jugador j     ON j.id       = fp.idJugador
JOIN Torneo.Partido p      ON p.idPartido = fp.idPartido
JOIN Torneo.Fase f         ON f.idFase   = p.fase
JOIN Equipos.Seleccion s   ON s.id       = fp.idSeleccion
JOIN Torneo.Pais ps        ON ps.id      = s.idPais
JOIN Equipos.Seleccion sr  ON sr.id      = CASE WHEN p.idSeleccionLocal = fp.idSeleccion
                                                THEN p.idSeleccionVisitante
                                                ELSE p.idSeleccionLocal END
JOIN Torneo.Pais pr        ON pr.id      = sr.idPais
OUTER APPLY (SELECT MIN(su.minuto) AS minutoIngreso
             FROM Eventos.Sustitucion su
             WHERE su.idPartido = fp.idPartido
               AND su.idIngresa = fp.idJugador) ing
OUTER APPLY (SELECT MIN(su.minuto) AS minutoSalida
             FROM Eventos.Sustitucion su
             WHERE su.idPartido = fp.idPartido
               AND su.idSale    = fp.idJugador) sal;
GO

/* =============================================================================
   3. Arbitraje.vw_HistorialArbitro
   Una fila por árbitro y partido en que fue designado.
   - amarillas / rojas: tarjetas del partido (de ambas selecciones).
   - cantInformes (esSancion = 0) / cantSanciones (esSancion = 1): registros
     de Arbitraje.InformeArbitral de ese árbitro en ese partido.
   - detalleInformes: detalles de esos registros separados por ' | '.
   ============================================================================= */

CREATE OR ALTER VIEW Arbitraje.vw_HistorialArbitro
AS
SELECT a.idArbitro,
       a.apellido + N', ' + a.nombre    AS arbitro,
       pa.nombre                        AS paisArbitro,
       p.idPartido,
       p.fechaHoraUTC,
       f.nombre                         AS fase,
       pl.nombre                        AS seleccionLocal,
       pv.nombre                        AS seleccionVisitante,
       p.golLocal,
       p.golVisitante,
       p.estado,
       ca.rol,
       tj.amarillas,
       tj.rojas,
       inf.cantInformes,
       inf.cantSanciones,
       det.detalleInformes
FROM Arbitraje.cuerpoArbitral ca
JOIN Arbitraje.Arbitro a    ON a.idArbitro  = ca.idArbitro
JOIN Torneo.Pais pa         ON pa.id        = a.idPais
JOIN Torneo.Partido p       ON p.idPartido  = ca.idPartido
JOIN Torneo.Fase f          ON f.idFase     = p.fase
JOIN Equipos.Seleccion sl   ON sl.id        = p.idSeleccionLocal
JOIN Torneo.Pais pl         ON pl.id        = sl.idPais
JOIN Equipos.Seleccion sv   ON sv.id        = p.idSeleccionVisitante
JOIN Torneo.Pais pv         ON pv.id        = sv.idPais
OUTER APPLY (SELECT ISNULL(SUM(CASE WHEN t.color = 'A' THEN 1 ELSE 0 END), 0) AS amarillas,
                    ISNULL(SUM(CASE WHEN t.color = 'R' THEN 1 ELSE 0 END), 0) AS rojas
             FROM Eventos.Tarjeta t
             WHERE t.idPartido = p.idPartido) tj
OUTER APPLY (SELECT ISNULL(SUM(CASE WHEN i.esSancion = 0 THEN 1 ELSE 0 END), 0) AS cantInformes,
                    ISNULL(SUM(CASE WHEN i.esSancion = 1 THEN 1 ELSE 0 END), 0) AS cantSanciones
             FROM Arbitraje.InformeArbitral i
             WHERE i.idPartido = ca.idPartido
               AND i.idArbitro = ca.idArbitro) inf
OUTER APPLY (SELECT STRING_AGG(CAST(i.detalle AS nvarchar(max)), N' | ')
                        WITHIN GROUP (ORDER BY i.fecha, i.id)  AS detalleInformes
             FROM Arbitraje.InformeArbitral i
             WHERE i.idPartido = ca.idPartido
               AND i.idArbitro = ca.idArbitro
               AND i.detalle IS NOT NULL) det;
GO
