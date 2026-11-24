-- =============================================================================
-- Pregunta: K7 - Total de Goles por Selección (Privacidad de Datos)
-- Tipo de gráfico recomendado: Gráfico de Barras Verticales
-- Principio de seguridad: Cumplimiento del Plan de Cifrado de la Entrega 8;
--   el analista de BI observa totales por selección y fase SIN nombres de jugadores.
-- Fuente: Eventos.vw_BI_GolesPorSeleccion
-- =============================================================================
SELECT
    seleccion                   AS [Selección Nacional],
    SUM(totalGoles)             AS [Total de Goles Marcados],
    SUM(golesEnContraAFavor)    AS [Goles en Contra Favorecidos]
FROM Eventos.vw_BI_GolesPorSeleccion
WHERE 1 = 1
  [[AND idFase = {{idFase}}]]
GROUP BY
    idSeleccion,
    seleccion
ORDER BY
    [Total de Goles Marcados] DESC;