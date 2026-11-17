/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 17/11/2026

 Objetivo    : Reportes de Torneo y Equipos (Entrega 7):
               - Torneo.Reporte_Resultados: resultados de los encuentros, con
                 el marcador, la definición por penales y el ganador.
               - Equipos.Reporte_SeleccionesPlantillas: selecciones con un
                 vector anidado de convocados (nombre, posición, club,
                 dorsal), devuelto en XML.

 Criterios:
 - Reporte_Resultados parte de Torneo.vw_Fixture (30a), así que la fecha y la
   hora son las locales de la sede. El filtro por fecha es por la fecha local.
   Por defecto muestra solo los partidos Finalizados; con @soloFinalizados = 0
   muestra también los que todavía no tienen resultado.
 - Los goles de la definición por penales (Eventos.Gol con minuto NULL) no
   forman parte del marcador: se informan aparte en penalesLocal y
   penalesVisitante. El autor del gol se ubica en su selección a través de la
   formación del partido (Eventos.FormacionPartido), igual que en
   Torneo.RegistrarResultado (20a).
 - Ganador: el de mayor cantidad de goles; si hay empate, el de los penales; si
   tampoco hay ganador por penales, 'Empate'. Un partido sin resultado no
   tiene ganador (NULL).
 - Reporte_SeleccionesPlantillas devuelve una sola fila con una sola columna
   de tipo xml. Por defecto lista los convocados activos (sin fecha de baja);
   con @soloActivos = 0 lista también las bajas y agrega los atributos
   fechaBaja y motivoBaja. Una selección sin convocados sale sin el nodo
   <convocados>. Los datos en NULL no generan atributos ni elementos.
 - Los filtros se validan con el patrón de los SP: todos los errores juntos en
   un único THROW 50001. Un filtro que no encuentra datos devuelve cero filas
   (o un XML sin selecciones), no un error.
 - Los reportes solo leen: no modifican ninguna tabla.
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

/* =============================================================================
   1. SP: Torneo.Reporte_Resultados
   Todos los filtros en NULL no filtran.
   ============================================================================= */
CREATE OR ALTER PROCEDURE Torneo.Reporte_Resultados
    @idSede           int  = NULL,
    @idFase           int  = NULL,
    @idSeleccion      int  = NULL,
    @fechaDesde       date = NULL,
    @fechaHasta       date = NULL,
    @soloFinalizados  bit  = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    SET @soloFinalizados = ISNULL(@soloFinalizados, 1);

    IF @idSede IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Torneo.Sede WHERE idSede = @idSede)
        SET @errores += CHAR(10) + N'- La sede no existe.';

    IF @idFase IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = @idFase)
        SET @errores += CHAR(10) + N'- La fase no existe.';

    IF @idSeleccion IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE id = @idSeleccion)
        SET @errores += CHAR(10) + N'- La selección no existe.';

    IF @fechaDesde > @fechaHasta
        SET @errores += CHAR(10) + N'- La fecha desde no puede ser posterior a la fecha hasta.';

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo generar el reporte de resultados:' + @errores;
        THROW 50001, @errores, 1;
    END;

    SELECT v.nroPartidoOficial                AS nroPartido,
           v.fase,
           CASE WHEN f.esEliminatoria = 0 THEN sl.grupo END AS grupo,
           v.estado,
           v.fechaLocal,
           v.horaLocal,
           v.sede,
           v.ciudad,
           v.seleccionLocal,
           v.golLocal,
           v.golVisitante,
           v.seleccionVisitante,
           CASE WHEN v.golLocal IS NULL OR v.golVisitante IS NULL THEN NULL
                ELSE COALESCE(v.abreviacionLocal, v.seleccionLocal) + N' '
                     + CAST(v.golLocal AS nvarchar(3)) + N' - ' + CAST(v.golVisitante AS nvarchar(3)) + N' '
                     + COALESCE(v.abreviacionVisitante, v.seleccionVisitante)
                     + CASE WHEN pen.penalesLocal IS NULL THEN N''
                            ELSE N' (' + CAST(pen.penalesLocal AS nvarchar(3)) + N'-'
                                 + CAST(pen.penalesVisitante AS nvarchar(3)) + N' pen.)' END
           END                                AS marcador,
           pen.penalesLocal,
           pen.penalesVisitante,
           CASE WHEN v.golLocal IS NULL OR v.golVisitante IS NULL THEN NULL
                WHEN v.golLocal > v.golVisitante THEN v.seleccionLocal
                WHEN v.golLocal < v.golVisitante THEN v.seleccionVisitante
                WHEN pen.penalesLocal > pen.penalesVisitante THEN v.seleccionLocal
                WHEN pen.penalesLocal < pen.penalesVisitante THEN v.seleccionVisitante
                ELSE N'Empate'
           END                                AS ganador,
           v.cantPublico
    FROM Torneo.vw_Fixture v
    JOIN Torneo.Fase f        ON f.idFase = v.idFase
    JOIN Equipos.Seleccion sl ON sl.id = v.idSeleccionLocal
    -- Penales: NULL si el partido no tuvo definición por penales
    OUTER APPLY (SELECT SUM(CASE WHEN fp.idSeleccion = v.idSeleccionLocal THEN 1 ELSE 0 END)      AS penalesLocal,
                        SUM(CASE WHEN fp.idSeleccion = v.idSeleccionVisitante THEN 1 ELSE 0 END)  AS penalesVisitante
                 FROM Eventos.Gol g
                 JOIN Eventos.FormacionPartido fp ON fp.idPartido = g.idPartido AND fp.idJugador = g.idJugador
                 WHERE g.idPartido = v.idPartido AND g.minuto IS NULL) pen
    WHERE (@idSede IS NULL OR v.idSede = @idSede)
      AND (@idFase IS NULL OR v.idFase = @idFase)
      AND (@idSeleccion IS NULL OR @idSeleccion IN (v.idSeleccionLocal, v.idSeleccionVisitante))
      AND (@fechaDesde IS NULL OR v.fechaLocal >= @fechaDesde)
      AND (@fechaHasta IS NULL OR v.fechaLocal <= @fechaHasta)
      AND (@soloFinalizados = 0 OR v.estado = 'Finalizado')
    ORDER BY v.fechaHoraUTC, v.idPartido;
END
GO

/* =============================================================================
   2. SP: Equipos.Reporte_SeleccionesPlantillas (XML)
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
                JOIN Equipos.Jugador j ON j.id = lj.idJugador
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
