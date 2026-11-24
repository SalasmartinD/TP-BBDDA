-- =============================================================================
-- Pregunta: K5 - Ranking de Anunciantes por Inversión y País de Origen
-- Tipo de gráfico recomendado: Gráfico de Barras Horizontales o Tabla Dinámica
-- Métricas: Monto facturado (estado 'Exhibida') y cantidad de exhibiciones por anunciante
-- Fuente: Publicidad.vw_BI_Exhibiciones
-- =============================================================================
SELECT
    anunciante               AS [Anunciante],
    paisAnunciante           AS [País del Anunciante],
    rubroAnunciante          AS [Rubro],
    COUNT(idPieza)           AS [Exhibiciones Totales],
    SUM(montoUSD)            AS [Total Invertido (USD)]
FROM Publicidad.vw_BI_Exhibiciones
WHERE estadoExhibicion = 'Exhibida'
  [[AND idSede = {{idSede}}]]
  [[AND idFase = {{idFase}}]]
GROUP BY
    idAnunciante,
    anunciante,
    paisAnunciante,
    rubroAnunciante
ORDER BY
    [Total Invertido (USD)] DESC;