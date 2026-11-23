/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 22/11/2026

 Objetivo    : Ejecutar manualmente los 9 reportes de la Entrega 7 (scripts 60,
               61 y 62) con todas las variantes de sus parámetros:
               60 - Torneo.Reporte_Resultados
                    Equipos.Reporte_SeleccionesPlantillas      (XML)
               61 - Eventos.Reporte_Goleadores
                    Eventos.Reporte_Tarjetas
                    Arbitraje.Reporte_DesignacionesArbitrales  (XML)
               62 - Publicidad.Reporte_OcupacionPublicitaria
                    Publicidad.Reporte_MatrizPrimeTime
                    Publicidad.Reporte_IngresosPorMoneda
               Cada reporte tiene una ejecución sin parámetros (activa) y debajo
               sus variantes, comentadas: seleccionar la línea y ejecutar (F5).
               Al final hay una sección con los errores de validación de los
               parámetros, que sí se ejecuta (cada error se captura y se muestra).

 Requisitos  : Base MundialFutbol creada y cargada (91_Crear_Base_Completa.sql).
               Los reportes XML devuelven 1 fila / 1 columna: en SSMS, clic sobre
               el valor para abrir el XML completo.

 Referencias de los datos de carga (ver 50a a 54):
   - Selección 9 = Argentina   - Fases 1 a 7 (1 = Fase de grupos, 7 = Final)
   - Sedes 1 a 16              - Partidos 1 a 31 (todos Finalizados)
   - Árbitro 1                 - Monedas con cotización: EUR, ARS, JPY, USD, etc.
================================================================================
*/

USE MundialFutbol;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* =============================================================================
   60 - REPORTES DE TORNEO Y EQUIPOS
   ============================================================================= */

/* ---------------------------------------------------------------------------
   1. Torneo.Reporte_Resultados
      Parámetros (todos opcionales): @idSede, @idFase, @idSeleccion,
      @fechaDesde, @fechaHasta (fecha local de la sede), @soloFinalizados
      (1 por defecto; 0 incluye los partidos sin resultado).
   --------------------------------------------------------------------------- */
EXEC Torneo.Reporte_Resultados;

-- Un filtro por vez:
-- EXEC Torneo.Reporte_Resultados @idSede = 2;
-- EXEC Torneo.Reporte_Resultados @idFase = 7;
-- EXEC Torneo.Reporte_Resultados @idSeleccion = 9;
-- EXEC Torneo.Reporte_Resultados @fechaDesde = '2026-06-20';
-- EXEC Torneo.Reporte_Resultados @fechaHasta = '2026-06-30';
-- EXEC Torneo.Reporte_Resultados @soloFinalizados = 0;

-- Rango de fechas (desde y hasta):
-- EXEC Torneo.Reporte_Resultados @fechaDesde = '2026-06-20', @fechaHasta = '2026-06-30';

-- Combinaciones:
-- EXEC Torneo.Reporte_Resultados @idSede = 2, @soloFinalizados = 1;
-- EXEC Torneo.Reporte_Resultados @idSeleccion = 9, @idFase = 7;
-- EXEC Torneo.Reporte_Resultados @idFase = 1, @fechaDesde = '2026-06-15', @fechaHasta = '2026-06-20', @soloFinalizados = 0;                            

/* ---------------------------------------------------------------------------
   2. Equipos.Reporte_SeleccionesPlantillas (XML)
      Parámetros: @idSeleccion (opcional), @soloActivos (1 por defecto; 0 suma
      las bajas con fechaBaja y motivoBaja).
   --------------------------------------------------------------------------- */
EXEC Equipos.Reporte_SeleccionesPlantillas;

-- Variantes:
-- EXEC Equipos.Reporte_SeleccionesPlantillas @idSeleccion = 9;
-- EXEC Equipos.Reporte_SeleccionesPlantillas @soloActivos = 0;
-- EXEC Equipos.Reporte_SeleccionesPlantillas @idSeleccion = 9, @soloActivos = 0;

/* =============================================================================
   61 - REPORTES DE PARTIDOS EN JUEGO Y ARBITRAJE
   ============================================================================= */

/* ---------------------------------------------------------------------------
   3. Eventos.Reporte_Goleadores (3 tablas de resultado)
      a) goleadores por selección, fase y jugador
      b) tabla de goleadores del torneo (ranking)
      c) totales por selección y fase, con el total del torneo
      Parámetros (opcionales): @idSeleccion, @idFase.
   --------------------------------------------------------------------------- */
EXEC Eventos.Reporte_Goleadores;

-- Variantes:
-- EXEC Eventos.Reporte_Goleadores @idSeleccion = 9;
-- EXEC Eventos.Reporte_Goleadores @idFase = 7;
-- EXEC Eventos.Reporte_Goleadores @idSeleccion = 9, @idFase = 5;

/* ---------------------------------------------------------------------------
   4. Eventos.Reporte_Tarjetas (jugadores y cuerpo técnico, con suspensiones)
      Parámetros: @idSeleccion (opcional), @soloActivas (0 por defecto; 1 deja
      solo quienes tienen una suspensión activa).
   --------------------------------------------------------------------------- */
EXEC Eventos.Reporte_Tarjetas;

-- Variantes:
-- EXEC Eventos.Reporte_Tarjetas @idSeleccion = 9;
-- EXEC Eventos.Reporte_Tarjetas @soloActivas = 1;                      -- con los datos cargados puede dar 0 filas
-- EXEC Eventos.Reporte_Tarjetas @idSeleccion = 9, @soloActivas = 0;

/* ---------------------------------------------------------------------------
   5. Arbitraje.Reporte_DesignacionesArbitrales (XML)
      árbitro -> partidos que dirigió -> tarjetas del partido.
      Parámetro: @idArbitro (opcional).
   --------------------------------------------------------------------------- */
EXEC Arbitraje.Reporte_DesignacionesArbitrales;

-- Variante (un solo árbitro; si no dirigió partidos devuelve la raíz vacía):
-- EXEC Arbitraje.Reporte_DesignacionesArbitrales @idArbitro = 1;

/* =============================================================================
   62 - REPORTES DE PUBLICIDAD
   ============================================================================= */

/* ---------------------------------------------------------------------------
   6. Publicidad.Reporte_OcupacionPublicitaria
      Parámetros (opcionales): @idSede, @idFase, @idPartido.
   --------------------------------------------------------------------------- */
EXEC Publicidad.Reporte_OcupacionPublicitaria;

-- Un filtro por vez:
-- EXEC Publicidad.Reporte_OcupacionPublicitaria @idSede = 2;
-- EXEC Publicidad.Reporte_OcupacionPublicitaria @idFase = 1;
-- EXEC Publicidad.Reporte_OcupacionPublicitaria @idPartido = 1;

-- Combinaciones:
-- EXEC Publicidad.Reporte_OcupacionPublicitaria @idSede = 2, @idFase = 1;
-- EXEC Publicidad.Reporte_OcupacionPublicitaria @idFase = 1, @idPartido = 1;

/* ---------------------------------------------------------------------------
   7. Publicidad.Reporte_MatrizPrimeTime (tabla cruzada con PIVOT)
      Parámetros (opcionales): @idFase, @idPartido.
   --------------------------------------------------------------------------- */
EXEC Publicidad.Reporte_MatrizPrimeTime;

-- Variantes:
-- EXEC Publicidad.Reporte_MatrizPrimeTime @idFase = 7;
-- EXEC Publicidad.Reporte_MatrizPrimeTime @idPartido = 1;
-- EXEC Publicidad.Reporte_MatrizPrimeTime @idFase = 1, @idPartido = 1;

/* ---------------------------------------------------------------------------
   8. Publicidad.Reporte_IngresosPorMoneda
      Parámetro: @monedaDestino (opcional). Sin moneda, cada anunciante se
      liquida en su moneda de facturación; con moneda, todo se convierte a ella.
   --------------------------------------------------------------------------- */
EXEC Publicidad.Reporte_IngresosPorMoneda;

-- Variantes (cualquier moneda de Publicidad.TipoCambio, o USD):
-- EXEC Publicidad.Reporte_IngresosPorMoneda @monedaDestino = 'USD';
-- EXEC Publicidad.Reporte_IngresosPorMoneda @monedaDestino = 'EUR';
-- EXEC Publicidad.Reporte_IngresosPorMoneda @monedaDestino = 'ARS';
-- EXEC Publicidad.Reporte_IngresosPorMoneda @monedaDestino = 'JPY';