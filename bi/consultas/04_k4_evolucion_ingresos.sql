-- =============================================================================
-- Pregunta: K4 - Evolución Cronológica del Ingreso Publicitario
-- Tipo de gráfico recomendado: Gráfico de Líneas / Área Acumulada
-- Métricas: Ingreso diario facturado (estado 'Exhibida') y evolución acumulada en el torneo
-- Fuente: Publicidad.vw_BI_Exhibiciones
-- =============================================================================
WITH Diario AS (
    SELECT
        CAST(fechaHoraUTC AS date) AS [Fecha],
        SUM(montoUSD)              AS [Ingreso Diario (USD)]
    FROM Publicidad.vw_BI_Exhibiciones
    WHERE estadoExhibicion = 'Exhibida'
      [[AND idSede = {{idSede}}]]
      [[AND idFase = {{idFase}}]]
    GROUP BY
        CAST(fechaHoraUTC AS date)
)
SELECT
    [Fecha],
    [Ingreso Diario (USD)],
    SUM([Ingreso Diario (USD)]) OVER (ORDER BY [Fecha] ROWS UNBOUNDED PRECEDING) AS [Ingreso Acumulado (USD)]
FROM Diario
ORDER BY
    [Fecha] ASC;