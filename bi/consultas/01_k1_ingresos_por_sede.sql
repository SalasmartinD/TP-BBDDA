-- =============================================================================
-- Pregunta: K1 - Facturación por Sede
-- Tipo de gráfico recomendado: Gráfico de Barras Horizontales o Verticales
-- Métricas: Ingresos facturados por exhibiciones emitidas (estado 'Exhibida') agrupados por sede
-- Fuente: Publicidad.vw_BI_Exhibiciones
-- =============================================================================
SELECT
    sede                     AS [Estadio],
    ciudadSede               AS [Ciudad],
    paisSede                 AS [País],
    COUNT(idPieza)           AS [Exhibiciones Facturadas],
    SUM(montoUSD)            AS [Total Facturado (USD)]
FROM Publicidad.vw_BI_Exhibiciones
WHERE estadoExhibicion = 'Exhibida'
  [[AND idSede = {{idSede}}]]
  [[AND idFase = {{idFase}}]]
GROUP BY
    sede,
    ciudadSede,
    paisSede
ORDER BY
    [Total Facturado (USD)] DESC;