-- =============================================================================
-- Pregunta: K3 - Distribución de Exhibiciones por Criterio Aplicado
-- Tipo de gráfico recomendado: Gráfico Circular / Torta o Anillo (Donut)
-- Métricas: Participación porcentual de los criterios del algoritmo de asignación:
--   1: Selección participante
--   2: Mayor PBI per cápita
--   3: Prime time local
-- Fuente: Publicidad.vw_BI_Exhibiciones
-- =============================================================================
SELECT
    criterioDescripcion      AS [Criterio de Priorización],
    COUNT(idPieza)           AS [Cantidad de Exhibiciones],
    SUM(montoUSD)            AS [Monto Total (USD)]
FROM Publicidad.vw_BI_Exhibiciones
WHERE 1 = 1
  [[AND idSede = {{idSede}}]]
  [[AND idFase = {{idFase}}]]
GROUP BY
    criterioAplicado,
    criterioDescripcion
ORDER BY
    criterioAplicado ASC;
