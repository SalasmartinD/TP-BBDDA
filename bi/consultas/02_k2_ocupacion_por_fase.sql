-- =============================================================================
-- Pregunta: K2 - Ocupación e Ingresos por Fase
-- Tipo de gráfico recomendado: Gráfico de Barras Agrupadas
-- Métricas: Cantidad de espacios efectivamente exhibidos y total de ingresos facturados por fase
-- Fuente: Publicidad.vw_BI_Exhibiciones
-- =============================================================================
SELECT
    fase                     AS [Fase del Torneo],
    COUNT(idPieza)           AS [Espacios Publicitarios Ocupados],
    SUM(montoUSD)            AS [Total Ingresos (USD)]
FROM Publicidad.vw_BI_Exhibiciones
WHERE estadoExhibicion = 'Exhibida'
  [[AND idSede = {{idSede}}]]
GROUP BY
    idFase,
    fase
ORDER BY
    idFase ASC;