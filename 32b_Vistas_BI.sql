/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 23/11/2026

 Objetivo    : Entrega 9 - Capa de datos para BI y Aplicación Blazor (Script 32b):
               1. Vistas Analíticas para Business Intelligence (Metabase):
                  - Publicidad.vw_BI_Exhibiciones:
                    Detalle granular de cada exhibición publicitaria por partido,
                    sede, fase, anunciante, país, campaña, criterio, estado e
                    ingresos en USD discriminados por estado de la exhibición:
                    facturado (Exhibida) y proyectado (Confirmada). Las
                    exhibiciones en estado Propuesta no computan como ingreso
                    (responde KPIs K1 a K5).
                  - Torneo.vw_BI_Sedes:
                    Catálogo enriquecido de sedes con geolocalización (latitud,
                    longitud), capacidad, huso horario y cantidad de partidos
                    asignados/disputados para visualización cartográfica (K6).
                  - Eventos.vw_BI_GolesPorSeleccion:
                    Goles acumulados por selección, fase y torneo sin exhibir datos
                    personales de jugadores, preservando el principio de privacidad
                    definido en el plan de seguridad de la Entrega 8 (K7).
               2. Vistas de Lectura y Catálogo para Aplicación (ABM Anunciante / Admin):
                  - Publicidad.vw_AnuncianteListado:
                    Padrón de anunciantes con país, moneda y conteo de campañas
                    (activas, vencidas y totales) para anticipar en la UI si la
                    baja resultará rechazada o permitida por el SP.
                  - Torneo.vw_PaisCatalogo:
                    Catálogo de países habilitados para combos de selección en la app.
                  - Publicidad.vw_MonedaCatalogo:
                    Catálogo de monedas disponibles para facturación (incluyendo USD
                    y las divisas con tipo de cambio registrado).
                  - Sistema.vw_ErrorImportacion:
                    Vista sanitizada de errores de importación que excluye datoOriginal
                    para no exponer datos sensibles en texto plano al rol de administración.

 Estándares aplicados:
 - Idempotencia mediante CREATE OR ALTER VIEW.
 - Consultas optimizadas con JOINs limpios y sin cursores.
 - Privacidad de datos garantizada (sin nombres ni identificadores de personas).
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- 1. VISTAS ANALÍTICAS PARA BUSINESS INTELLIGENCE (METABASE)
-- =============================================================================

/* -----------------------------------------------------------------------------
   Vista: Publicidad.vw_BI_Exhibiciones
   Detalle de exhibiciones publicitarias por partido y ubicación, vinculando
   sede, fase, anunciante, campaña y montos en USD. Fuente para KPIs K1 a K5.

   Definición de ingreso (consistente con el reporte E7):
     - montoFacturadoUSD  : monto de exhibiciones en estado 'Exhibida'.
     - montoProyectadoUSD : monto de exhibiciones en estado 'Confirmada'.
     - Estado 'Propuesta' : no cuenta como ingreso (ni facturado ni proyectado).
   montoUSD se conserva como monto bruto de la exhibición, cualquiera sea su
   estado; estadoExhibicion queda disponible para filtrar en Metabase.
----------------------------------------------------------------------------- */
CREATE OR ALTER VIEW Publicidad.vw_BI_Exhibiciones
AS
SELECT
    p.idPartido,
    p.nroPartidoOficial,
    p.fechaHoraUTC,
    p.fase                                              AS idFase,
    f.nombre                                            AS fase,
    s.idSede,
    s.nombreEstadio                                     AS sede,
    s.ciudad                                            AS ciudadSede,
    psSede.nombre                                       AS paisSede,
    CONCAT(paL.nombre, N' vs. ', paV.nombre)            AS partido,
    paL.nombre                                          AS seleccionLocal,
    paV.nombre                                          AS seleccionVisitante,
    p.estado                                            AS estadoPartido,

    u.idUbicacion,
    u.nombre                                            AS ubicacionPublicitaria,

    a.id                                                AS idAnunciante,
    a.nombre                                            AS anunciante,
    a.rubro                                             AS rubroAnunciante,
    paAnun.id                                           AS idPaisAnunciante,
    paAnun.nombre                                       AS paisAnunciante,

    c.idCampania,
    c.nombre                                            AS campania,
    pc.id                                               AS idPieza,
    pc.descripcion                                      AS piezaContenido,
    pc.idioma                                           AS idiomaPieza,

    ep.criterioAplicado,
    CASE ep.criterioAplicado
        WHEN 1 THEN N'1: Selección participante'
        WHEN 2 THEN N'2: Mayor PBI per cápita'
        WHEN 3 THEN N'3: Prime time local'
        ELSE N'No asignado'
    END                                                 AS criterioDescripcion,
    ep.estado                                           AS estadoExhibicion,
    ep.montoUSD                                         AS montoUSD,
    CASE WHEN ep.estado = N'Exhibida'
         THEN ep.montoUSD ELSE 0 END                    AS montoFacturadoUSD,
    CASE WHEN ep.estado = N'Confirmada'
         THEN ep.montoUSD ELSE 0 END                    AS montoProyectadoUSD
FROM Publicidad.ExhibicionPublicitaria ep
INNER JOIN Torneo.Partido                p      ON p.idPartido = ep.idPartido
INNER JOIN Torneo.Fase                   f      ON f.idFase = p.fase
INNER JOIN Torneo.Sede                   s      ON s.idSede = p.idSede
INNER JOIN Torneo.Pais                   psSede ON psSede.id = s.idPais
INNER JOIN Equipos.Seleccion             selL   ON selL.id = p.idSeleccionLocal
INNER JOIN Torneo.Pais                   paL    ON paL.id = selL.idPais
INNER JOIN Equipos.Seleccion             selV   ON selV.id = p.idSeleccionVisitante
INNER JOIN Torneo.Pais                   paV    ON paV.id = selV.idPais
INNER JOIN Publicidad.UbicacionPublicitaria u   ON u.idUbicacion = ep.idUbicacion
INNER JOIN Publicidad.PiezaContenido     pc     ON pc.id = ep.idPieza
INNER JOIN Publicidad.Campania           c      ON c.idCampania = pc.idCampania
INNER JOIN Publicidad.Anunciante         a      ON a.id = c.idAnunciante
INNER JOIN Torneo.Pais                   paAnun ON paAnun.id = a.idPais;
GO

/* -----------------------------------------------------------------------------
   Vista: Torneo.vw_BI_Sedes
   Sedes georreferenciadas con capacidad, huso horario y cantidad de partidos
   para alimentar el mapa de sedes (KPI K6).
----------------------------------------------------------------------------- */
CREATE OR ALTER VIEW Torneo.vw_BI_Sedes
AS
SELECT
    s.idSede,
    s.nombreEstadio,
    s.ciudad,
    p.id                                                AS idPais,
    p.nombre                                            AS pais,
    s.capacidad,
    s.husoHorario,
    s.latitud,
    s.longitud,
    COUNT(part.idPartido)                               AS cantPartidosAsignados,
    SUM(CASE WHEN part.estado = 'Finalizado' THEN 1 ELSE 0 END) AS cantPartidosDisputados
FROM Torneo.Sede s
INNER JOIN Torneo.Pais p ON p.id = s.idPais
LEFT JOIN Torneo.Partido part ON part.idSede = s.idSede
GROUP BY
    s.idSede,
    s.nombreEstadio,
    s.ciudad,
    p.id,
    p.nombre,
    s.capacidad,
    s.husoHorario,
    s.latitud,
    s.longitud;
GO

/* -----------------------------------------------------------------------------
   Vista: Eventos.vw_BI_GolesPorSeleccion
   Totales de goles por selección y fase (excluyendo definiciones por penales),
   preservando el plan de cifrado y privacidad de BI (sin nombres de jugadores).
   golesEnContraAFavor: goles en contra del rival que se acreditan a la selección
   (ya incluidos en totalGoles). Mismo nombre que Eventos.Reporte_Goleadores.
----------------------------------------------------------------------------- */
CREATE OR ALTER VIEW Eventos.vw_BI_GolesPorSeleccion
AS
WITH GolesBase AS (
    SELECT
        g.idGol,
        p.idPartido,
        p.fase                                          AS idFase,
        f.nombre                                        AS fase,
        CASE
            WHEN g.tipo = 'En contra' THEN
                CASE WHEN fp.idSeleccion = p.idSeleccionLocal
                     THEN p.idSeleccionVisitante
                     ELSE p.idSeleccionLocal END
            ELSE fp.idSeleccion
        END                                             AS idSeleccionAcreditada,
        CASE WHEN g.tipo = 'En contra' THEN 1 ELSE 0 END AS esEnContra
    FROM Eventos.Gol g
    INNER JOIN Torneo.Partido p            ON p.idPartido = g.idPartido
    INNER JOIN Torneo.Fase f               ON f.idFase = p.fase
    INNER JOIN Eventos.FormacionPartido fp ON fp.idPartido = g.idPartido
                                          AND fp.idJugador = g.idJugador
    WHERE g.minuto IS NOT NULL -- Excluye tanda de penales
)
SELECT
    gb.idSeleccionAcreditada                            AS idSeleccion,
    pa.nombre                                           AS seleccion,
    gb.idFase,
    gb.fase,
    COUNT(gb.idGol)                                     AS totalGoles,
    SUM(gb.esEnContra)                                  AS golesEnContraAFavor
FROM GolesBase gb
INNER JOIN Equipos.Seleccion sel ON sel.id = gb.idSeleccionAcreditada
INNER JOIN Torneo.Pais pa        ON pa.id = sel.idPais
GROUP BY
    gb.idSeleccionAcreditada,
    pa.nombre,
    gb.idFase,
    gb.fase;
GO

-- =============================================================================
-- 2. VISTAS DE LECTURA Y CATÁLOGOS PARA LA APLICACIÓN BLAZOR
-- =============================================================================

/* -----------------------------------------------------------------------------
   Vista: Publicidad.vw_AnuncianteListado
   Padrón de anunciantes con datos de país, moneda y cantidad de campañas activas,
   vencidas y totales para advertir en el cliente la factibilidad de la baja.
----------------------------------------------------------------------------- */
CREATE OR ALTER VIEW Publicidad.vw_AnuncianteListado
AS
SELECT
    a.id,
    a.nombre,
    a.rubro,
    a.idPais,
    p.nombre                                            AS pais,
    p.codigoISO3                                        AS paisCodigoISO3,
    a.monedaFacturacion,
    COUNT(c.idCampania)                                 AS cantCampaniasTotal,
    SUM(CASE WHEN c.fechaFin >= CAST(GETDATE() AS date) THEN 1 ELSE 0 END) AS cantCampaniasActivas,
    SUM(CASE WHEN c.fechaFin <  CAST(GETDATE() AS date) THEN 1 ELSE 0 END) AS cantCampaniasVencidas
FROM Publicidad.Anunciante a
INNER JOIN Torneo.Pais p ON p.id = a.idPais
LEFT JOIN Publicidad.Campania c ON c.idAnunciante = a.id
GROUP BY
    a.id,
    a.nombre,
    a.rubro,
    a.idPais,
    p.nombre,
    p.codigoISO3,
    a.monedaFacturacion;
GO

/* -----------------------------------------------------------------------------
   Vista: Torneo.vw_PaisCatalogo
   Catálogo de países ordenado para alimentar combos de selección en la UI.
----------------------------------------------------------------------------- */
CREATE OR ALTER VIEW Torneo.vw_PaisCatalogo
AS
SELECT
    id,
    nombre,
    codigoISO2,
    codigoISO3
FROM Torneo.Pais;
GO

/* -----------------------------------------------------------------------------
   Vista: Publicidad.vw_MonedaCatalogo
   Monedas disponibles para facturación: base USD más las monedas con cotización.
----------------------------------------------------------------------------- */
CREATE OR ALTER VIEW Publicidad.vw_MonedaCatalogo
AS
SELECT DISTINCT
    moneda
FROM (
    SELECT CAST('USD' AS char(3)) AS moneda
    UNION
    SELECT DISTINCT moneda FROM Publicidad.TipoCambio
) AS Monedas;
GO

/* -----------------------------------------------------------------------------
   Vista: Sistema.vw_ErrorImportacion
   Detalle de errores de importación para la pantalla de soporte de la app,
   omitiendo datoOriginal para respetar la política de privacidad de datos.
----------------------------------------------------------------------------- */
CREATE OR ALTER VIEW Sistema.vw_ErrorImportacion
AS
SELECT
    id,
    fechaHora,
    archivo,
    tablaDestino,
    nroFila,
    mensajeError
FROM Sistema.ErrorImportacion;
GO
