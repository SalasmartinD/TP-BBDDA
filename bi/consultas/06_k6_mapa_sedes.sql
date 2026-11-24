-- =============================================================================
-- Pregunta: K6 - Mapa Georreferenciado de Sedes
-- Tipo de visualización en Metabase: Mapa de Pines (Pin Map / Map)
-- Tipos semánticos requeridos en Metabase:
--   - latitud  -> Semántica: Latitude
--   - longitud -> Semántica: Longitude
-- Métricas: Capacidad, ciudad, país y cantidad de partidos asignados
-- Fuente: Torneo.vw_BI_Sedes
-- =============================================================================
SELECT
    idSede,
    nombreEstadio            AS [Estadio],
    ciudad                   AS [Ciudad],
    pais                     AS [País],
    capacidad                AS [Capacidad de Espectadores],
    husoHorario              AS [Huso Horario Windows],
    latitud                  AS [Latitud],
    longitud                 AS [Longitud],
    cantPartidosAsignados    AS [Partidos Asignados],
    cantPartidosDisputados   AS [Partidos Disputados]
FROM Torneo.vw_BI_Sedes
ORDER BY
    [Capacidad de Espectadores] DESC;
