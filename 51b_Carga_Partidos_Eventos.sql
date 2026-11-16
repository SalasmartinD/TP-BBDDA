/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel - 45066788
               Salas, Martín Daniel - 45205702
               Zito Padró, Ezequiel Nehuén - 46097917
 Fecha       : 15/11/2026

 Objetivo    : Carga de datos de Persona 2 (parte 2 de 3): cuerpo arbitral,
               formaciones y eventos (cambios, tarjetas y goles) de los 31
               partidos de 50c, y casos de rechazo de los SP de 21.
               Los partidos quedan 'En juego': 53_Cierre_Partidos.sql los cierra
               con Torneo.RegistrarResultado, que exige que los goles de los
               eventos den el marcador de su tabla #resultados.

 Orden       : Corre después de 50 y 51a, y antes de 51c y 53. Los partidos se
               procesan en orden cronológico (fechaHoraUTC, idPartido): una
               suspensión generada en un partido tiene que existir antes de
               armar la formación del partido siguiente de esa selección.
               Todo el recorrido es un WHILE sobre la tabla temporal #orden.

 Etapas por partido (cada una se saltea si ya se hizo, así el script se puede
 ejecutar varias veces, incluso después de que 53 cerró los partidos):
   a) Cuerpo arbitral con Arbitraje.DesignarCuerpoArbitral: se eligen los 5
      árbitros menos cargados que no sean de ninguna de las dos selecciones ni
      estén en otro partido a menos de 3 horas.
   b) Formación de las dos selecciones con Eventos.RegistrarFormacion, armada
      con los convocados activos: 11 titulares (1 arquero y el resto según el
      esquema, por orden de dorsal) y el resto al banco. El esquema rota entre
      4-3-3, 4-4-2, 3-5-2, 3-4-3, 5-3-2 y 5-4-1 según el partido y la
      selección; si por las suspensiones no alcanzan jugadores de una posición,
      se usa el siguiente esquema posible, así siempre hay 11 titulares. Los
      jugadores con suspensión activa no se incluyen. El cuerpo técnico es todo
      el Equipos.Staff de la selección menos los integrantes con suspensión
      activa (un cuerpo técnico sin Director Principal es válido).
   c) Pase a 'En juego' con Torneo.Partido_Modificacion (con los valores
      actuales: no pisa los esquemas guardados por la formación).
   d) Cambios, tarjetas y goles (reanudable por fila: cada uno se carga solo
      si todavía no está), definidos como datos por abreviación de
      selección y dorsal (se resuelven a id con joins), en ese orden. Las
      tarjetas al cuerpo técnico se definen por abreviación, rol y ordinal del
      integrante dentro de su rol, y se cargan después de las de los jugadores
      del mismo partido.

 Casos de la consigna (todos se muestran con PRINT; un rechazo esperado se
 captura con TRY/CATCH, y si el SP no rechaza el script avisa y falla):
   CASO OBLIGATORIO 1 - Expulsiones: doble amarilla en el partido 18 (IRQ-NOR)
                        y roja directa en el 44 (JOR-ALG).
   CASO OBLIGATORIO 2 - Suspensión por acumulación: URU 6 con amarilla en los
                        partidos 13 y 37; en el 66 (URU-ESP) se rechaza su
                        inclusión y se registra la formación sin él.
   CASO OBLIGATORIO 3 - Roja a un integrante del cuerpo técnico: roja directa
                        al Director Principal de NOR en el partido 41 (NOR-SEN);
                        en el 61 (NOR-FRA) se rechaza su inclusión en el cuerpo
                        técnico y se registra la formación sin él.
   CASO OBLIGATORIO 4 - Cambio por lesión en el minuto 17 del partido 17.
   CASO OBLIGATORIO 5 - Designación rechazada por conflicto de nacionalidad
                        (partido 19, ARG-ALG) y designación válida.
   EXTRA E1 - Designación con dos conflictos de nacionalidad (partido 20).
   EXTRA E2 - Sexto cambio rechazado por MAX_CAMBIOS (partido 22).
   EXTRA E3 - Tarjeta a un jugador ya expulsado, rechazada (partido 18).
   EXTRA E4 - Formación con un suspendido por expulsión, rechazada (IRQ en el
              partido 42 y JOR en el 70; la de URU en el 66 es el caso 2).
   EXTRA E5 - Acumulación de amarillas del cuerpo técnico (parámetro
              AMARILLAS_SUSPENSION_STAFF = 2): amarilla al Ayudante nro 1 de ESP
              en los partidos 14 y 38; la 2ª genera la suspensión. En el 66
              (URU-ESP) se rechaza su inclusión en el cuerpo técnico y se
              registra la formación sin él.
   Además, los partidos eliminatorios muestran la advertencia de cruce.

 Uso         : Todas las altas pasan por los SP de 10a, 11 y 21.

 Cambio cuerpo técnico (Fase 2): Eventos.RegistrarFormacion ahora exige el
               cuerpo técnico, así que cada llamada (la del rechazo esperado del
               suspendido y la válida) se arma con todo el Equipos.Staff de la
               selección y lo pasa en @cuerpoTecnico.

 Cambio cuerpo técnico (Fase 3): se cargan tarjetas al cuerpo técnico con
               Eventos.RegistrarTarjeta @idStaff (caso 3 y extra E5), la
               formación excluye al staff con suspensión activa y se agrega el
               rechazo esperado del staff suspendido (F19). Los casos
               obligatorios pasan a numerarse según la consigna vigente (5).
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

SET NOCOUNT ON;
GO

/* =============================================================================
   1. DATOS
   ============================================================================= */

-- Marcador que debe dar la suma de goles de cada partido (el mismo que cierra 53).
-- Un gol 'En contra' suma al rival del autor.
DROP TABLE IF EXISTS #marcadores;
CREATE TABLE #marcadores (nro int PRIMARY KEY, golLocal tinyint NOT NULL, golVisitante tinyint NOT NULL);
INSERT INTO #marcadores (nro, golLocal, golVisitante) VALUES
    (13, 1, 1), (14, 0, 0), (17, 3, 1), (18, 1, 4), (19, 3, 0), (20, 3, 1), (21, 1, 0), (22, 4, 2),
    (37, 2, 2), (38, 4, 0), (41, 3, 2), (42, 3, 0), (43, 2, 0), (44, 1, 2), (45, 0, 0), (46, 0, 1),
    (61, 1, 4), (62, 5, 0), (65, 0, 0), (66, 0, 1), (67, 0, 2), (68, 2, 1), (69, 3, 3), (70, 1, 3),
    (84, 3, 0), (86, 3, 2), (99, 1, 2), (101, 0, 2), (102, 1, 2), (103, 4, 6), (104, 1, 0);

-- Esquemas tácticos que rotan: defensores, mediocampistas y delanteros (más 1 arquero)
DROP TABLE IF EXISTS #esquemas;
CREATE TABLE #esquemas (idx int PRIMARY KEY, esquema varchar(10) NOT NULL, d int NOT NULL, m int NOT NULL, f int NOT NULL);
INSERT INTO #esquemas (idx, esquema, d, m, f) VALUES
    (0, '4-3-3', 4, 3, 3), (1, '4-4-2', 4, 4, 2), (2, '3-5-2', 3, 5, 2),
    (3, '3-4-3', 3, 4, 3), (4, '5-3-2', 5, 3, 2), (5, '5-4-1', 5, 4, 1);

-- Cambios: (partido, selección que cambia, minuto, adicional, dorsal que sale, dorsal que entra, motivo).
-- Cada selección: 2 a 5 cambios en máximo 3 ventanas (instantes distintos). En los partidos 86, 99 y 104
-- (con alargue) hay un cambio en el minuto 95 o 100 y una selección usa el cambio y la ventana extra.
DROP TABLE IF EXISTS #cambios;
CREATE TABLE #cambios (n int IDENTITY(1,1) PRIMARY KEY, nro int NOT NULL, sel char(3) NOT NULL,
                       minuto tinyint NOT NULL, minutoAdicional tinyint NULL,
                       dorsalSale int NOT NULL, dorsalEntra int NOT NULL, motivo varchar(15) NOT NULL);
INSERT INTO #cambios (nro, sel, minuto, minutoAdicional, dorsalSale, dorsalEntra, motivo) VALUES
    (14, 'ESP', 60, NULL, 7, 17, 'Tactico'), (14, 'ESP', 75, NULL, 9, 15, 'Tactico'), (14, 'ESP', 85, NULL, 3, 12, 'Precaucion'),
    (14, 'CPV', 55, NULL, 9, 20, 'Tactico'), (14, 'CPV', 78, NULL, 7, 10, 'Tactico'),
    (13, 'KSA', 46, NULL, 18, 10, 'Tactico'), (13, 'KSA', 70, NULL, 16, 17, 'Tactico'), (13, 'KSA', 82, NULL, 9, 19, 'Tactico'),
    (13, 'URU', 62, NULL, 9, 18, 'Tactico'), (13, 'URU', 75, NULL, 5, 8, 'Tactico'),
    (17, 'FRA', 60, NULL, 9, 10, 'Tactico'), (17, 'FRA', 72, NULL, 18, 24, 'Tactico'), (17, 'FRA', 80, NULL, 13, 25, 'Tactico'),
    (17, 'SEN', 17, NULL, 4, 15, 'Lesion'), (17, 'SEN', 55, NULL, 8, 21, 'Tactico'), (17, 'SEN', 55, NULL, 17, 22, 'Tactico'),
    (17, 'SEN', 78, NULL, 7, 10, 'Tactico'),
    (18, 'IRQ', 46, NULL, 14, 16, 'Tactico'), (18, 'IRQ', 60, NULL, 9, 17, 'Tactico'), (18, 'IRQ', 78, NULL, 7, 19, 'Tactico'),
    (18, 'NOR', 65, NULL, 2, 14, 'Tactico'), (18, 'NOR', 80, NULL, 16, 17, 'Precaucion'), (18, 'NOR', 80, NULL, 7, 9, 'Tactico'),
    (19, 'ARG', 70, NULL, 8, 11, 'Tactico'), (19, 'ARG', 70, NULL, 5, 14, 'Tactico'), (19, 'ARG', 82, NULL, 9, 17, 'Tactico'),
    (19, 'ALG', 46, NULL, 14, 19, 'Tactico'), (19, 'ALG', 65, NULL, 11, 12, 'Precaucion'), (19, 'ALG', 65, NULL, 7, 18, 'Tactico'),
    (19, 'ALG', 80, NULL, 8, 22, 'Tactico'),
    (20, 'AUT', 60, NULL, 7, 14, 'Tactico'), (20, 'AUT', 60, NULL, 8, 16, 'Tactico'), (20, 'AUT', 75, NULL, 15, 10, 'Tactico'),
    (20, 'JOR', 55, NULL, 10, 11, 'Tactico'), (20, 'JOR', 70, NULL, 14, 18, 'Tactico'), (20, 'JOR', 70, NULL, 7, 13, 'Tactico'),
    (22, 'ENG', 46, NULL, 7, 18, 'Tactico'), (22, 'ENG', 46, NULL, 10, 14, 'Tactico'), (22, 'ENG', 65, NULL, 4, 16, 'Tactico'),
    (22, 'ENG', 65, NULL, 8, 17, 'Precaucion'), (22, 'ENG', 80, NULL, 3, 24, 'Tactico'),
    (22, 'CRO', 60, NULL, 11, 14, 'Tactico'), (22, 'CRO', 75, NULL, 8, 15, 'Lesion'),
    (21, 'GHA', 60, NULL, 9, 10, 'Tactico'), (21, 'GHA', 78, NULL, 5, 15, 'Tactico'),
    (21, 'PAN', 55, NULL, 9, 17, 'Tactico'), (21, 'PAN', 70, NULL, 6, 19, 'Tactico'), (21, 'PAN', 70, NULL, 7, 20, 'Precaucion'),
    (21, 'PAN', 85, NULL, 13, 14, 'Tactico'),
    (38, 'ESP', 55, NULL, 7, 11, 'Tactico'), (38, 'ESP', 70, NULL, 10, 19, 'Tactico'), (38, 'ESP', 70, NULL, 9, 15, 'Tactico'),
    (38, 'ESP', 85, NULL, 2, 14, 'Tactico'),
    (38, 'KSA', 46, NULL, 12, 13, 'Tactico'), (38, 'KSA', 60, NULL, 9, 11, 'Tactico'), (38, 'KSA', 75, NULL, 6, 16, 'Tactico'),
    (37, 'URU', 60, NULL, 9, 11, 'Tactico'), (37, 'URU', 75, NULL, 8, 10, 'Tactico'), (37, 'URU', 85, NULL, 16, 17, 'Tactico'),
    (37, 'CPV', 55, NULL, 7, 11, 'Tactico'), (37, 'CPV', 70, NULL, 19, 20, 'Tactico'),
    (43, 'ARG', 60, NULL, 5, 15, 'Tactico'), (43, 'ARG', 60, NULL, 7, 11, 'Tactico'), (43, 'ARG', 75, NULL, 13, 19, 'Precaucion'),
    (43, 'ARG', 85, NULL, 9, 17, 'Tactico'),
    (43, 'AUT', 46, NULL, 17, 18, 'Tactico'), (43, 'AUT', 70, NULL, 7, 14, 'Lesion'),
    (42, 'FRA', 46, NULL, 7, 9, 'Tactico'), (42, 'FRA', 70, NULL, 13, 10, 'Tactico'), (42, 'FRA', 70, NULL, 14, 18, 'Tactico'),
    (42, 'FRA', 82, NULL, 2, 19, 'Precaucion'),
    (42, 'IRQ', 60, NULL, 9, 10, 'Tactico'), (42, 'IRQ', 75, NULL, 8, 19, 'Tactico'),
    (41, 'NOR', 46, NULL, 7, 9, 'Tactico'), (41, 'NOR', 70, NULL, 16, 17, 'Tactico'), (41, 'NOR', 70, NULL, 5, 24, 'Tactico'),
    (41, 'NOR', 80, NULL, 2, 14, 'Tactico'),
    (41, 'SEN', 60, NULL, 10, 11, 'Tactico'), (41, 'SEN', 75, NULL, 17, 21, 'Tactico'),
    (44, 'JOR', 46, NULL, 14, 15, 'Tactico'), (44, 'JOR', 78, NULL, 7, 11, 'Tactico'),
    (44, 'ALG', 55, NULL, 9, 12, 'Tactico'), (44, 'ALG', 70, NULL, 6, 14, 'Tactico'), (44, 'ALG', 70, NULL, 8, 19, 'Tactico'),
    (45, 'ENG', 60, NULL, 7, 11, 'Tactico'), (45, 'ENG', 75, NULL, 9, 18, 'Tactico'),
    (45, 'GHA', 46, NULL, 8, 15, 'Tactico'), (45, 'GHA', 70, NULL, 10, 13, 'Tactico'), (45, 'GHA', 85, NULL, 5, 20, 'Precaucion'),
    (46, 'PAN', 60, NULL, 9, 24, 'Tactico'), (46, 'PAN', 70, NULL, 7, 19, 'Tactico'), (46, 'PAN', 70, NULL, 8, 20, 'Tactico'),
    (46, 'PAN', 85, NULL, 2, 13, 'Lesion'),
    (46, 'CRO', 65, NULL, 9, 14, 'Tactico'), (46, 'CRO', 80, NULL, 11, 20, 'Tactico'),
    (61, 'NOR', 46, NULL, 2, 14, 'Tactico'), (61, 'NOR', 60, NULL, 7, 11, 'Tactico'), (61, 'NOR', 75, NULL, 6, 18, 'Tactico'),
    (61, 'FRA', 75, NULL, 9, 11, 'Tactico'), (61, 'FRA', 75, NULL, 7, 20, 'Tactico'), (61, 'FRA', 85, NULL, 3, 15, 'Precaucion'),
    (62, 'SEN', 46, NULL, 9, 10, 'Tactico'), (62, 'SEN', 70, NULL, 7, 12, 'Tactico'), (62, 'SEN', 70, NULL, 17, 21, 'Tactico'),
    (62, 'IRQ', 46, NULL, 14, 19, 'Tactico'), (62, 'IRQ', 65, NULL, 9, 10, 'Precaucion'), (62, 'IRQ', 80, NULL, 7, 20, 'Tactico'),
    (65, 'CPV', 60, NULL, 9, 20, 'Tactico'), (65, 'CPV', 70, NULL, 7, 11, 'Tactico'), (65, 'CPV', 85, NULL, 10, 14, 'Tactico'),
    (65, 'KSA', 55, NULL, 8, 11, 'Tactico'), (65, 'KSA', 70, NULL, 10, 17, 'Tactico'),
    (66, 'URU', 60, NULL, 9, 18, 'Tactico'), (66, 'URU', 70, NULL, 11, 19, 'Tactico'), (66, 'URU', 85, NULL, 8, 14, 'Tactico'),
    (66, 'ESP', 46, NULL, 7, 11, 'Tactico'), (66, 'ESP', 70, NULL, 9, 18, 'Tactico'), (66, 'ESP', 70, NULL, 15, 20, 'Tactico'),
    (67, 'ENG', 60, NULL, 9, 11, 'Tactico'), (67, 'ENG', 70, NULL, 14, 16, 'Tactico'), (67, 'ENG', 70, NULL, 10, 17, 'Tactico'),
    (67, 'ENG', 82, NULL, 2, 12, 'Precaucion'),
    (67, 'PAN', 46, NULL, 7, 11, 'Tactico'), (67, 'PAN', 65, NULL, 9, 18, 'Tactico'), (67, 'PAN', 80, NULL, 17, 24, 'Tactico'),
    (68, 'CRO', 60, NULL, 7, 13, 'Tactico'), (68, 'CRO', 72, NULL, 9, 14, 'Tactico'), (68, 'CRO', 85, NULL, 5, 18, 'Tactico'),
    (68, 'GHA', 65, NULL, 8, 20, 'Tactico'), (68, 'GHA', 80, NULL, 9, 13, 'Precaucion'),
    (69, 'ALG', 60, NULL, 8, 14, 'Tactico'), (69, 'ALG', 75, NULL, 9, 12, 'Tactico'), (69, 'ALG', 75, NULL, 6, 19, 'Tactico'),
    (69, 'AUT', 65, NULL, 6, 14, 'Lesion'), (69, 'AUT', 80, NULL, 17, 18, 'Tactico'), (69, 'AUT', 80, NULL, 5, 16, 'Tactico'),
    (70, 'JOR', 46, NULL, 6, 15, 'Tactico'), (70, 'JOR', 60, NULL, 10, 11, 'Tactico'), (70, 'JOR', 75, NULL, 7, 13, 'Tactico'),
    (70, 'ARG', 60, NULL, 5, 11, 'Tactico'), (70, 'ARG', 75, NULL, 10, 17, 'Tactico'),
    (84, 'ESP', 60, NULL, 11, 17, 'Tactico'), (84, 'ESP', 70, NULL, 10, 19, 'Tactico'), (84, 'ESP', 70, NULL, 9, 15, 'Tactico'),
    (84, 'ESP', 85, NULL, 3, 12, 'Tactico'), (84, 'ESP', 85, NULL, 4, 14, 'Precaucion'),
    (84, 'AUT', 46, NULL, 14, 21, 'Lesion'), (84, 'AUT', 65, NULL, 9, 10, 'Tactico'),
    (86, 'ARG', 60, NULL, 5, 14, 'Tactico'), (86, 'ARG', 60, NULL, 11, 16, 'Tactico'), (86, 'ARG', 75, NULL, 3, 13, 'Precaucion'),
    (86, 'ARG', 95, NULL, 7, 20, 'Tactico'),
    (86, 'CPV', 46, NULL, 7, 11, 'Tactico'), (86, 'CPV', 46, NULL, 8, 14, 'Tactico'), (86, 'CPV', 65, NULL, 10, 15, 'Tactico'),
    (86, 'CPV', 65, NULL, 6, 16, 'Tactico'), (86, 'CPV', 80, NULL, 4, 5, 'Tactico'), (86, 'CPV', 100, NULL, 2, 17, 'Precaucion'),
    (99, 'NOR', 60, NULL, 7, 18, 'Tactico'), (99, 'NOR', 75, NULL, 2, 14, 'Tactico'), (99, 'NOR', 85, NULL, 5, 15, 'Tactico'),
    (99, 'NOR', 100, NULL, 8, 19, 'Tactico'),
    (99, 'ENG', 46, NULL, 7, 11, 'Tactico'), (99, 'ENG', 70, NULL, 14, 16, 'Tactico'), (99, 'ENG', 85, NULL, 9, 18, 'Tactico'),
    (101, 'FRA', 55, NULL, 7, 10, 'Tactico'), (101, 'FRA', 70, NULL, 9, 11, 'Tactico'), (101, 'FRA', 70, NULL, 13, 18, 'Tactico'),
    (101, 'FRA', 82, NULL, 2, 15, 'Tactico'),
    (101, 'ESP', 60, NULL, 7, 17, 'Tactico'), (101, 'ESP', 75, NULL, 10, 19, 'Tactico'), (101, 'ESP', 85, NULL, 6, 18, 'Tactico'),
    (102, 'ENG', 60, NULL, 7, 11, 'Tactico'), (102, 'ENG', 70, NULL, 9, 18, 'Tactico'), (102, 'ENG', 70, NULL, 14, 17, 'Tactico'),
    (102, 'ENG', 80, NULL, 2, 12, 'Precaucion'),
    (102, 'ARG', 65, NULL, 5, 14, 'Tactico'), (102, 'ARG', 80, NULL, 10, 17, 'Tactico'),
    (103, 'FRA', 46, NULL, 7, 10, 'Tactico'), (103, 'FRA', 46, NULL, 15, 9, 'Tactico'), (103, 'FRA', 60, NULL, 13, 11, 'Tactico'),
    (103, 'FRA', 75, NULL, 8, 12, 'Tactico'),
    (103, 'ENG', 60, NULL, 9, 11, 'Tactico'), (103, 'ENG', 75, NULL, 4, 14, 'Tactico'), (103, 'ENG', 75, NULL, 12, 15, 'Tactico'),
    (103, 'ENG', 85, NULL, 8, 16, 'Precaucion'),
    (104, 'ESP', 60, NULL, 7, 17, 'Tactico'), (104, 'ESP', 70, NULL, 10, 19, 'Tactico'), (104, 'ESP', 85, NULL, 6, 18, 'Tactico'),
    (104, 'ESP', 85, NULL, 4, 14, 'Tactico'), (104, 'ESP', 85, NULL, 2, 12, 'Precaucion'), (104, 'ESP', 100, NULL, 8, 20, 'Tactico'),
    (104, 'ARG', 46, NULL, 11, 10, 'Tactico'), (104, 'ARG', 70, NULL, 9, 16, 'Tactico'), (104, 'ARG', 70, NULL, 5, 15, 'Tactico'),
    (104, 'ARG', 100, NULL, 13, 19, 'Tactico');

-- Tarjetas: (partido, selección, dorsal, color, minuto, adicional, motivo). 1 a 3 por partido.
-- Ningún jugador recibe amarilla en dos partidos distintos, salvo URU 6 (caso 2). La doble amarilla de IRQ 5
-- (partido 18) genera sola la roja 'Doble amarilla'; la roja directa de JOR 4 es el 'R' del partido 44.
DROP TABLE IF EXISTS #tarjetas;
CREATE TABLE #tarjetas (n int IDENTITY(1,1) PRIMARY KEY, nro int NOT NULL, sel char(3) NOT NULL, dorsal int NOT NULL,
                        color char(1) NOT NULL, minuto tinyint NOT NULL, minutoAdicional tinyint NULL, motivo varchar(80) NOT NULL);
INSERT INTO #tarjetas (nro, sel, dorsal, color, minuto, minutoAdicional, motivo) VALUES
    (14, 'CPV', 4, 'A', 34, NULL, 'Falta táctica'),
    (13, 'URU', 6, 'A', 41, NULL, 'Falta'), (13, 'KSA', 4, 'A', 77, NULL, 'Juego brusco'),
    (17, 'FRA', 3, 'A', 52, NULL, 'Falta'), (17, 'SEN', 6, 'A', 70, NULL, 'Protesta'),
    (18, 'IRQ', 5, 'A', 25, NULL, 'Falta'), (18, 'IRQ', 5, 'A', 71, NULL, 'Falta reiterada'),
    (19, 'ALG', 3, 'A', 36, NULL, 'Falta'), (19, 'ARG', 6, 'A', 74, NULL, 'Juego brusco'),
    (20, 'JOR', 2, 'A', 29, NULL, 'Falta'), (20, 'AUT', 4, 'A', 80, NULL, 'Juego brusco'),
    (22, 'CRO', 6, 'A', 33, NULL, 'Falta'), (22, 'ENG', 5, 'A', 67, NULL, 'Juego brusco'),
    (21, 'PAN', 4, 'A', 50, NULL, 'Falta'), (21, 'GHA', 14, 'A', 66, NULL, 'Protesta'), (21, 'PAN', 8, 'A', 90, 3, 'Pérdida de tiempo'),
    (38, 'KSA', 5, 'A', 22, NULL, 'Falta'), (38, 'KSA', 15, 'A', 58, NULL, 'Juego brusco'),
    (37, 'URU', 6, 'A', 55, NULL, 'Falta'), (37, 'CPV', 5, 'A', 62, NULL, 'Falta'),
    (43, 'AUT', 10, 'A', 51, NULL, 'Falta'), (43, 'ARG', 2, 'A', 80, NULL, 'Pérdida de tiempo'),
    (42, 'IRQ', 14, 'A', 38, NULL, 'Falta'), (42, 'FRA', 5, 'A', 66, NULL, 'Juego brusco'),
    (41, 'NOR', 4, 'A', 40, NULL, 'Falta'), (41, 'SEN', 3, 'A', 79, NULL, 'Protesta'), (41, 'NOR', 15, 'A', 90, 2, 'Pérdida de tiempo'),
    (44, 'JOR', 4, 'R', 63, NULL, 'Juego brusco grave'), (44, 'ALG', 5, 'A', 72, NULL, 'Falta'),
    (45, 'GHA', 6, 'A', 31, NULL, 'Falta'), (45, 'ENG', 8, 'A', 77, NULL, 'Protesta'),
    (46, 'PAN', 9, 'A', 38, NULL, 'Falta'), (46, 'CRO', 13, 'A', 55, NULL, 'Juego brusco'),
    (61, 'NOR', 8, 'A', 33, NULL, 'Falta'), (61, 'FRA', 4, 'A', 62, NULL, 'Falta'), (61, 'NOR', 10, 'A', 70, NULL, 'Protesta'),
    (62, 'IRQ', 6, 'A', 41, NULL, 'Falta'), (62, 'SEN', 8, 'A', 69, NULL, 'Juego brusco'),
    (65, 'CPV', 8, 'A', 49, NULL, 'Falta'), (65, 'KSA', 6, 'A', 83, NULL, 'Pérdida de tiempo'),
    (66, 'URU', 4, 'A', 40, NULL, 'Falta'), (66, 'ESP', 2, 'A', 77, NULL, 'Juego brusco'),
    (67, 'PAN', 3, 'A', 58, NULL, 'Falta'), (67, 'ENG', 4, 'A', 74, NULL, 'Protesta'),
    (68, 'CRO', 3, 'A', 47, NULL, 'Falta'), (68, 'GHA', 4, 'A', 69, NULL, 'Juego brusco'),
    (69, 'ALG', 4, 'A', 37, NULL, 'Falta'), (69, 'AUT', 9, 'A', 63, NULL, 'Protesta'), (69, 'ALG', 10, 'A', 70, NULL, 'Juego brusco'),
    (70, 'JOR', 8, 'A', 55, NULL, 'Falta'), (70, 'ARG', 3, 'A', 68, NULL, 'Juego brusco'),
    (84, 'AUT', 8, 'A', 31, NULL, 'Falta'), (84, 'ESP', 8, 'A', 66, NULL, 'Protesta'),
    (86, 'CPV', 3, 'A', 52, NULL, 'Falta'), (86, 'ARG', 8, 'A', 72, NULL, 'Juego brusco'), (86, 'CPV', 20, 'A', 108, NULL, 'Juego brusco'),
    (99, 'NOR', 6, 'A', 40, NULL, 'Falta'), (99, 'ENG', 6, 'A', 77, NULL, 'Protesta'), (99, 'NOR', 3, 'A', 94, NULL, 'Falta'),
    (101, 'FRA', 6, 'A', 36, NULL, 'Falta'), (101, 'ESP', 3, 'A', 60, NULL, 'Juego brusco'),
    (102, 'ENG', 16, 'A', 49, NULL, 'Falta'), (102, 'ARG', 4, 'A', 58, NULL, 'Protesta'),
    (103, 'FRA', 2, 'A', 50, NULL, 'Falta'), (103, 'ENG', 3, 'A', 66, NULL, 'Juego brusco'),
    (104, 'ESP', 5, 'A', 44, NULL, 'Falta'), (104, 'ARG', 7, 'A', 77, NULL, 'Protesta');

-- Tarjetas al cuerpo técnico: (partido, selección, rol, ordinal del integrante dentro de su rol en esa
-- selección (por Staff.id), color, minuto, adicional, motivo). Con AMARILLAS_SUSPENSION_STAFF = 2:
--   caso 3: roja directa al Director Principal de NOR en el 41 (su partido siguiente es el 61, NOR-FRA).
--   extra E5: amarilla al Ayudante nro 1 de ESP en el 14 y en el 38; la 2ª suspende 1 partido (siguiente: el 66).
DROP TABLE IF EXISTS #tarjetasStaff;
CREATE TABLE #tarjetasStaff (n int IDENTITY(1,1) PRIMARY KEY, nro int NOT NULL, sel char(3) NOT NULL, rol varchar(20) NOT NULL,
                             ordinal int NOT NULL, color char(1) NOT NULL, minuto tinyint NOT NULL,
                             minutoAdicional tinyint NULL, motivo varchar(80) NOT NULL);
INSERT INTO #tarjetasStaff (nro, sel, rol, ordinal, color, minuto, minutoAdicional, motivo) VALUES
    (14, 'ESP', 'Ayudante', 1, 'A', 58, NULL, 'Protestas'),
    (38, 'ESP', 'Ayudante', 1, 'A', 63, NULL, 'Falta de respeto al cuarto árbitro'),
    (41, 'NOR', 'Director Principal', 1, 'R', 77, NULL, 'Protestas airadas al cuarto árbitro');

-- Goles: (partido, selección del AUTOR, dorsal del autor, dorsal del asistente, minuto, adicional, tipo).
-- Dan exactamente el marcador de #marcadores. Los 'En contra' (partidos 37 y 102) los hace un jugador del
-- equipo que los recibe: suman al rival. Los partidos 86, 99 y 104 tienen goles en el alargue.
DROP TABLE IF EXISTS #goles;
CREATE TABLE #goles (n int IDENTITY(1,1) PRIMARY KEY, nro int NOT NULL, sel char(3) NOT NULL, dorsal int NOT NULL,
                     dorsalAsistente int NULL, minuto tinyint NOT NULL, minutoAdicional tinyint NULL, tipo varchar(20) NOT NULL);
INSERT INTO #goles (nro, sel, dorsal, dorsalAsistente, minuto, minutoAdicional, tipo) VALUES
    (13, 'KSA', 9, 7, 28, NULL, 'Jugada'), (13, 'URU', 11, 7, 67, NULL, 'Cabeza'),
    (17, 'FRA', 9, 14, 12, NULL, 'Jugada'), (17, 'FRA', 7, NULL, 49, NULL, 'Penal'), (17, 'SEN', 9, 5, 38, NULL, 'Jugada'),
    (17, 'FRA', 10, NULL, 83, NULL, 'Tiro libre'),
    (18, 'NOR', 7, 10, 11, NULL, 'Jugada'), (18, 'NOR', 10, NULL, 33, NULL, 'Tiro libre'), (18, 'IRQ', 10, NULL, 54, NULL, 'Penal'),
    (18, 'NOR', 7, 16, 61, NULL, 'Cabeza'), (18, 'NOR', 9, 8, 88, NULL, 'Jugada'),
    (19, 'ARG', 10, 7, 22, NULL, 'Jugada'), (19, 'ARG', 9, 13, 58, NULL, 'Cabeza'), (19, 'ARG', 11, NULL, 79, NULL, 'Tiro libre'),
    (20, 'AUT', 7, 11, 9, NULL, 'Jugada'), (20, 'AUT', 11, NULL, 45, 2, 'Penal'), (20, 'JOR', 9, 14, 63, NULL, 'Jugada'),
    (20, 'AUT', 9, 6, 77, NULL, 'Jugada'),
    (22, 'ENG', 9, 10, 14, NULL, 'Jugada'), (22, 'CRO', 9, 8, 25, NULL, 'Jugada'), (22, 'ENG', 7, 11, 31, NULL, 'Jugada'),
    (22, 'ENG', 11, 3, 52, NULL, 'Cabeza'), (22, 'CRO', 14, NULL, 70, NULL, 'Penal'), (22, 'ENG', 18, NULL, 80, NULL, 'Jugada'),
    (21, 'GHA', 7, 11, 81, NULL, 'Cabeza'),
    (38, 'ESP', 7, 8, 18, NULL, 'Jugada'), (38, 'ESP', 10, NULL, 40, NULL, 'Tiro libre'), (38, 'ESP', 11, 9, 63, NULL, 'Jugada'),
    (38, 'ESP', 19, 6, 87, NULL, 'Cabeza'),
    (37, 'URU', 9, 7, 20, NULL, 'Jugada'), (37, 'CPV', 19, 10, 35, NULL, 'Jugada'), (37, 'URU', 13, NULL, 68, NULL, 'En contra'),
    (37, 'URU', 11, 5, 76, NULL, 'Jugada'),
    (43, 'ARG', 10, 8, 33, NULL, 'Jugada'), (43, 'ARG', 9, 10, 67, NULL, 'Jugada'),
    (42, 'FRA', 7, 13, 27, NULL, 'Jugada'), (42, 'FRA', 9, 14, 60, NULL, 'Jugada'), (42, 'FRA', 10, NULL, 75, NULL, 'Penal'),
    (41, 'NOR', 7, 10, 15, NULL, 'Jugada'), (41, 'SEN', 9, 17, 30, NULL, 'Jugada'), (41, 'NOR', 9, 8, 52, NULL, 'Jugada'),
    (41, 'SEN', 7, 8, 70, NULL, 'Cabeza'), (41, 'NOR', 10, NULL, 88, NULL, 'Penal'),
    (44, 'JOR', 9, 8, 40, NULL, 'Jugada'), (44, 'ALG', 7, 10, 58, NULL, 'Jugada'), (44, 'ALG', 11, NULL, 85, NULL, 'Penal'),
    (46, 'CRO', 11, 10, 74, NULL, 'Jugada'),
    (61, 'FRA', 10, 7, 12, NULL, 'Jugada'), (61, 'NOR', 9, 10, 44, NULL, 'Jugada'), (61, 'FRA', 7, 13, 55, NULL, 'Jugada'),
    (61, 'FRA', 9, NULL, 66, NULL, 'Penal'), (61, 'FRA', 11, 14, 89, NULL, 'Jugada'),
    (62, 'SEN', 9, 17, 10, NULL, 'Jugada'), (62, 'SEN', 7, 5, 28, NULL, 'Cabeza'), (62, 'SEN', 10, NULL, 51, NULL, 'Penal'),
    (62, 'SEN', 10, NULL, 66, NULL, 'Tiro libre'), (62, 'SEN', 12, 10, 80, NULL, 'Jugada'),
    (66, 'ESP', 10, 16, 61, NULL, 'Jugada'),
    (67, 'ENG', 9, 14, 22, NULL, 'Jugada'), (67, 'ENG', 7, 10, 64, NULL, 'Cabeza'),
    (68, 'CRO', 9, 10, 38, NULL, 'Jugada'), (68, 'GHA', 9, 11, 55, NULL, 'Jugada'), (68, 'CRO', 11, NULL, 77, NULL, 'Tiro libre'),
    (69, 'ALG', 9, 11, 10, NULL, 'Jugada'), (69, 'AUT', 7, 17, 29, NULL, 'Jugada'), (69, 'ALG', 7, 10, 47, NULL, 'Cabeza'),
    (69, 'AUT', 11, NULL, 55, NULL, 'Penal'), (69, 'AUT', 14, 10, 78, NULL, 'Jugada'), (69, 'ALG', 12, NULL, 90, 3, 'Jugada'),
    (70, 'ARG', 10, 8, 20, NULL, 'Jugada'), (70, 'JOR', 9, 14, 33, NULL, 'Jugada'), (70, 'ARG', 16, NULL, 61, NULL, 'Tiro libre'),
    (70, 'ARG', 9, 7, 82, NULL, 'Jugada'),
    (84, 'ESP', 10, 9, 25, NULL, 'Jugada'), (84, 'ESP', 7, 11, 57, NULL, 'Jugada'), (84, 'ESP', 17, 6, 74, NULL, 'Cabeza'),
    (86, 'ARG', 10, 11, 15, NULL, 'Jugada'), (86, 'CPV', 9, 10, 40, NULL, 'Jugada'), (86, 'ARG', 9, 7, 68, NULL, 'Cabeza'),
    (86, 'CPV', 19, NULL, 80, NULL, 'Penal'), (86, 'ARG', 16, 8, 97, NULL, 'Jugada'),
    (99, 'NOR', 9, 10, 30, NULL, 'Jugada'), (99, 'ENG', 9, 14, 62, NULL, 'Jugada'), (99, 'ENG', 11, 10, 109, NULL, 'Cabeza'),
    (101, 'ESP', 10, 8, 41, NULL, 'Jugada'), (101, 'ESP', 11, 9, 78, NULL, 'Jugada'),
    (102, 'ARG', 10, NULL, 30, NULL, 'Tiro libre'), (102, 'ENG', 9, 10, 55, NULL, 'Jugada'), (102, 'ENG', 3, NULL, 88, NULL, 'En contra'),
    (103, 'FRA', 7, 13, 8, NULL, 'Jugada'), (103, 'ENG', 9, 10, 15, NULL, 'Jugada'), (103, 'ENG', 7, 8, 28, NULL, 'Jugada'),
    (103, 'FRA', 14, NULL, 35, NULL, 'Tiro libre'), (103, 'ENG', 10, NULL, 44, NULL, 'Penal'), (103, 'ENG', 7, 4, 55, NULL, 'Cabeza'),
    (103, 'FRA', 10, 8, 62, NULL, 'Jugada'), (103, 'ENG', 11, NULL, 70, NULL, 'Jugada'), (103, 'FRA', 9, NULL, 81, NULL, 'Penal'),
    (103, 'ENG', 5, 10, 86, NULL, 'Cabeza'),
    (104, 'ESP', 17, 11, 105, 1, 'Jugada');

-- Intentos que el SP debe rechazar (se muestran con PRINT). Los árbitros se buscan por apellido.
DROP TABLE IF EXISTS #intentoArbitros;
CREATE TABLE #intentoArbitros (nro int PRIMARY KEY, etiqueta varchar(40) NOT NULL, descripcion varchar(100) NOT NULL,
                               principal nvarchar(60), asistente1 nvarchar(60), asistente2 nvarchar(60),
                               cuarto nvarchar(60), var nvarchar(60));
INSERT INTO #intentoArbitros (nro, etiqueta, descripcion, principal, asistente1, asistente2, cuarto, var) VALUES
    (19, 'CASO OBLIGATORIO 5', 'un árbitro argentino como principal de ARG-ALG', N'Ferreyra', N'Villaseñor', N'Montoya', N'Thornton', N'Whitfield'),
    (20, 'EXTRA E1', 'dos conflictos de nacionalidad a la vez (un árbitro austríaco y uno jordano en AUT-JOR)', N'Brandstätter', N'Haddad', N'Beaulieu', N'McAllister', N'Villaseñor');

DROP TABLE IF EXISTS #intentoCambio;
CREATE TABLE #intentoCambio (nro int PRIMARY KEY, etiqueta varchar(40) NOT NULL, sel char(3) NOT NULL, minuto tinyint NOT NULL,
                             dorsalSale int NOT NULL, dorsalEntra int NOT NULL, motivo varchar(15) NOT NULL);
INSERT INTO #intentoCambio (nro, etiqueta, sel, minuto, dorsalSale, dorsalEntra, motivo) VALUES
    (22, 'EXTRA E2', 'ENG', 80, 2, 25, 'Tactico');   -- sexto cambio de ENG en un partido sin alargue

DROP TABLE IF EXISTS #intentoTarjeta;
CREATE TABLE #intentoTarjeta (nro int PRIMARY KEY, etiqueta varchar(40) NOT NULL, sel char(3) NOT NULL, dorsal int NOT NULL,
                              color char(1) NOT NULL, minuto tinyint NOT NULL, motivo varchar(80) NOT NULL);
INSERT INTO #intentoTarjeta (nro, etiqueta, sel, dorsal, color, minuto, motivo) VALUES
    (18, 'EXTRA E3', 'IRQ', 5, 'A', 80, 'Protesta');   -- IRQ 5 ya fue expulsado por doble amarilla en el minuto 71

/* =============================================================================
   2. DATOS RESUELTOS A ID (por abreviación de selección + dorsal del convocado
   activo). Cada tabla lleva el orden en que se cargan los eventos. Si algún
   jugador no se encuentra, se informa y el script se detiene.
   ============================================================================= */
DROP TABLE IF EXISTS #cambiosRes;
CREATE TABLE #cambiosRes (ord int IDENTITY(1,1) PRIMARY KEY, nro int NOT NULL, idSale int NULL, idIngresa int NULL,
                          idPeriodo tinyint NOT NULL, minuto tinyint NOT NULL, minutoAdicional tinyint NULL, motivo varchar(15) NOT NULL);
CREATE INDEX IX_cambiosRes_nro ON #cambiosRes (nro, ord);

-- Los cambios van por selección y en orden de instante (el SP no admite uno anterior al último de la selección)
INSERT INTO #cambiosRes (nro, idSale, idIngresa, idPeriodo, minuto, minutoAdicional, motivo)
SELECT c.nro, ljs.idJugador, lje.idJugador,
       CASE WHEN c.minuto <= 45 THEN 1 WHEN c.minuto <= 90 THEN 2 WHEN c.minuto <= 105 THEN 3 ELSE 4 END,
       c.minuto, c.minutoAdicional, c.motivo
FROM #cambios c
JOIN Equipos.Seleccion s ON s.abreviacion = c.sel
LEFT JOIN Equipos.ListadoJugadores ljs ON ljs.idSeleccion = s.id AND ljs.dorsal = c.dorsalSale AND ljs.fechaBaja IS NULL
LEFT JOIN Equipos.ListadoJugadores lje ON lje.idSeleccion = s.id AND lje.dorsal = c.dorsalEntra AND lje.fechaBaja IS NULL
ORDER BY c.nro, c.sel, c.minuto * 1000 + ISNULL(c.minutoAdicional, 0), c.n;

DROP TABLE IF EXISTS #tarjetasRes;
CREATE TABLE #tarjetasRes (ord int IDENTITY(1,1) PRIMARY KEY, nro int NOT NULL, idJugador int NULL,
                           idPeriodo tinyint NOT NULL, color char(1) NOT NULL, minuto tinyint NOT NULL,
                           minutoAdicional tinyint NULL, motivo varchar(80) NOT NULL);
CREATE INDEX IX_tarjetasRes_nro ON #tarjetasRes (nro, ord);

INSERT INTO #tarjetasRes (nro, idJugador, idPeriodo, color, minuto, minutoAdicional, motivo)
SELECT t.nro, lj.idJugador,
       CASE WHEN t.minuto <= 45 THEN 1 WHEN t.minuto <= 90 THEN 2 WHEN t.minuto <= 105 THEN 3 ELSE 4 END,
       t.color, t.minuto, t.minutoAdicional, t.motivo
FROM #tarjetas t
JOIN Equipos.Seleccion s ON s.abreviacion = t.sel
LEFT JOIN Equipos.ListadoJugadores lj ON lj.idSeleccion = s.id AND lj.dorsal = t.dorsal AND lj.fechaBaja IS NULL
ORDER BY t.nro, t.minuto * 1000 + ISNULL(t.minutoAdicional, 0), t.n;

-- Cada integrante se identifica por selección + rol + ordinal dentro de su rol (ROW_NUMBER por Staff.id)
DROP TABLE IF EXISTS #tarjetasStaffRes;
CREATE TABLE #tarjetasStaffRes (ord int IDENTITY(1,1) PRIMARY KEY, nro int NOT NULL, idStaff int NULL,
                                idPeriodo tinyint NOT NULL, color char(1) NOT NULL, minuto tinyint NOT NULL,
                                minutoAdicional tinyint NULL, motivo varchar(80) NOT NULL);
CREATE INDEX IX_tarjetasStaffRes_nro ON #tarjetasStaffRes (nro, ord);

WITH staffOrd AS (
    SELECT st.id AS idStaff, st.idSeleccion, st.rol,
           ROW_NUMBER() OVER (PARTITION BY st.idSeleccion, st.rol ORDER BY st.id) AS ordinal
    FROM Equipos.Staff st
)
INSERT INTO #tarjetasStaffRes (nro, idStaff, idPeriodo, color, minuto, minutoAdicional, motivo)
SELECT t.nro, so.idStaff,
       CASE WHEN t.minuto <= 45 THEN 1 WHEN t.minuto <= 90 THEN 2 WHEN t.minuto <= 105 THEN 3 ELSE 4 END,
       t.color, t.minuto, t.minutoAdicional, t.motivo
FROM #tarjetasStaff t
JOIN Equipos.Seleccion s ON s.abreviacion = t.sel
LEFT JOIN staffOrd so ON so.idSeleccion = s.id AND so.rol = t.rol AND so.ordinal = t.ordinal
ORDER BY t.nro, t.minuto * 1000 + ISNULL(t.minutoAdicional, 0), t.n;

DROP TABLE IF EXISTS #golesRes;
CREATE TABLE #golesRes (ord int IDENTITY(1,1) PRIMARY KEY, nro int NOT NULL, idJugador int NULL, idAsistidor int NULL,
                        asistenteNoEncontrado bit NOT NULL, idPeriodo tinyint NOT NULL, minuto tinyint NOT NULL,
                        minutoAdicional tinyint NULL, tipo varchar(20) NOT NULL);
CREATE INDEX IX_golesRes_nro ON #golesRes (nro, ord);

INSERT INTO #golesRes (nro, idJugador, idAsistidor, asistenteNoEncontrado, idPeriodo, minuto, minutoAdicional, tipo)
SELECT g.nro, lja.idJugador, ljs.idJugador,
       CASE WHEN g.dorsalAsistente IS NOT NULL AND ljs.idJugador IS NULL THEN 1 ELSE 0 END,
       CASE WHEN g.minuto <= 45 THEN 1 WHEN g.minuto <= 90 THEN 2 WHEN g.minuto <= 105 THEN 3 ELSE 4 END,
       g.minuto, g.minutoAdicional, g.tipo
FROM #goles g
JOIN Equipos.Seleccion s ON s.abreviacion = g.sel
LEFT JOIN Equipos.ListadoJugadores lja ON lja.idSeleccion = s.id AND lja.dorsal = g.dorsal AND lja.fechaBaja IS NULL
LEFT JOIN Equipos.ListadoJugadores ljs ON ljs.idSeleccion = s.id AND ljs.dorsal = g.dorsalAsistente AND ljs.fechaBaja IS NULL
ORDER BY g.nro, g.minuto * 1000 + ISNULL(g.minutoAdicional, 0), g.n;

IF EXISTS (SELECT 1 FROM #cambiosRes WHERE idSale IS NULL OR idIngresa IS NULL)
   OR EXISTS (SELECT 1 FROM #tarjetasRes WHERE idJugador IS NULL)
   OR EXISTS (SELECT 1 FROM #golesRes WHERE idJugador IS NULL OR asistenteNoEncontrado = 1)
BEGIN
    SELECT 'cambio' AS evento, nro, ord FROM #cambiosRes WHERE idSale IS NULL OR idIngresa IS NULL
    UNION ALL SELECT 'tarjeta', nro, ord FROM #tarjetasRes WHERE idJugador IS NULL
    UNION ALL SELECT 'gol', nro, ord FROM #golesRes WHERE idJugador IS NULL OR asistenteNoEncontrado = 1;
    THROW 50001, N'Hay jugadores de los datos de eventos que no se encontraron por abreviación de selección y dorsal.', 1;
END;

IF EXISTS (SELECT 1 FROM #tarjetasStaffRes WHERE idStaff IS NULL)
BEGIN
    SELECT 'tarjeta al cuerpo técnico' AS evento, nro, ord FROM #tarjetasStaffRes WHERE idStaff IS NULL;
    THROW 50001, N'Hay integrantes del cuerpo técnico de los datos de tarjetas que no se encontraron por abreviación de selección, rol y ordinal.', 1;
END;

/* =============================================================================
   3. PARTIDOS EN ORDEN CRONOLÓGICO
   ============================================================================= */
DROP TABLE IF EXISTS #orden;
CREATE TABLE #orden (n int PRIMARY KEY, idPartido int NOT NULL, nro int NOT NULL);
INSERT INTO #orden (n, idPartido, nro)
SELECT ROW_NUMBER() OVER (ORDER BY p.fechaHoraUTC, p.idPartido), p.idPartido, p.nroPartidoOficial
FROM Torneo.Partido p
WHERE p.nroPartidoOficial IN (SELECT nro FROM #marcadores);

-- Convocados disponibles de la selección que arma su formación
DROP TABLE IF EXISTS #disponibles;
CREATE TABLE #disponibles (idJugador int PRIMARY KEY, dorsal int NOT NULL, posicion varchar(15) NULL, rk int NOT NULL);

-- Los 5 árbitros candidatos de un partido
DROP TABLE IF EXISTS #candidatos;
CREATE TABLE #candidatos (idArbitro int PRIMARY KEY, carga int NOT NULL, principales int NOT NULL);

DECLARE @n int, @max int, @lado int,
        @idPartido int, @nro int, @estado varchar(15), @fecha datetime2(0), @ordenFase int,
        @idSede int, @idLocal int, @idVisit int, @fase int, @cantPublico int, @esqLocal varchar(10), @esqVisit varchar(10),
        @abrevLocal char(3), @abrevVisit char(3), @idPaisLocal int, @idPaisVisit int,
        @etiqueta varchar(40), @descripcion varchar(100), @rechazado bit,
        @idPpal int, @idAs1 int, @idAs2 int, @idCuarto int, @idVar int, @advertencia nvarchar(2000),
        @idSel int, @abrevSel char(3), @base int, @esquema varchar(10), @cantDef int, @cantMed int, @cantDel int,
        @idSusp int, @dorsalSusp int, @posSusp varchar(15), @cantTit int, @cantSup int,
        @idSuspStaff int, @apellidoSuspStaff nvarchar(60), @etiquetaStaff varchar(40),
        @idStaff int, @idTarjeta int, @rolStaff varchar(20), @abrevStaff char(3),
        @cantCambios int, @cantTarjetas int, @cantGoles int,
        @ord int, @idSale int, @idIngresa int, @idJugador int, @idAsistidor int,
        @idPeriodo tinyint, @minuto tinyint, @minutoAdic tinyint, @motivo varchar(80), @color char(1), @tipo varchar(20);
DECLARE @jugadores    Eventos.FormacionJugadorLista;
DECLARE @jugadoresMal Eventos.FormacionJugadorLista;
DECLARE @cuerpoTecnico Eventos.CuerpoTecnicoLista;
DECLARE @cuerpoTecnicoMal Eventos.CuerpoTecnicoLista;

SELECT @n = 1, @max = (SELECT MAX(n) FROM #orden);
WHILE @n <= @max
BEGIN
    SELECT @idPartido = o.idPartido, @nro = o.nro FROM #orden o WHERE o.n = @n;

    -- Estado actual del partido y datos de las selecciones
    SELECT @estado = p.estado, @fecha = p.fechaHoraUTC, @ordenFase = f.orden,
           @idSede = p.idSede, @idLocal = p.idSeleccionLocal, @idVisit = p.idSeleccionVisitante, @fase = p.fase,
           @cantPublico = p.cantPublico, @abrevLocal = sl.abreviacion, @abrevVisit = sv.abreviacion,
           @idPaisLocal = sl.idPais, @idPaisVisit = sv.idPais
    FROM Torneo.Partido p
    JOIN Torneo.Fase f        ON f.idFase = p.fase
    JOIN Equipos.Seleccion sl ON sl.id = p.idSeleccionLocal
    JOIN Equipos.Seleccion sv ON sv.id = p.idSeleccionVisitante
    WHERE p.idPartido = @idPartido;

    BEGIN TRY
        /* ---- a) Cuerpo arbitral ------------------------------------------------ */
        IF @estado = 'Programado'
           AND NOT EXISTS (SELECT 1 FROM Arbitraje.cuerpoArbitral WHERE idPartido = @idPartido)
        BEGIN
            -- Designación que debe ser rechazada por conflicto de nacionalidad (caso 5 y extra E1)
            SET @etiqueta = NULL;
            SELECT @etiqueta = i.etiqueta, @descripcion = i.descripcion,
                   @idPpal   = (SELECT a.idArbitro FROM Arbitraje.Arbitro a WHERE a.apellido = i.principal),
                   @idAs1    = (SELECT a.idArbitro FROM Arbitraje.Arbitro a WHERE a.apellido = i.asistente1),
                   @idAs2    = (SELECT a.idArbitro FROM Arbitraje.Arbitro a WHERE a.apellido = i.asistente2),
                   @idCuarto = (SELECT a.idArbitro FROM Arbitraje.Arbitro a WHERE a.apellido = i.cuarto),
                   @idVar    = (SELECT a.idArbitro FROM Arbitraje.Arbitro a WHERE a.apellido = i.var)
            FROM #intentoArbitros i
            WHERE i.nro = @nro;

            IF @etiqueta IS NOT NULL
            BEGIN
                SET @rechazado = 0;
                BEGIN TRY
                    EXEC Arbitraje.DesignarCuerpoArbitral @idPartido = @idPartido, @idPrincipal = @idPpal,
                         @idAsistente1 = @idAs1, @idAsistente2 = @idAs2, @idCuartoArbitro = @idCuarto,
                         @idVar = @idVar, @advertencia = @advertencia OUTPUT;
                END TRY
                BEGIN CATCH
                    SET @rechazado = 1;
                    IF ERROR_NUMBER() <> 50002 THROW;
                    PRINT @etiqueta + ' - rechazo esperado (' + CAST(ERROR_NUMBER() AS varchar(10)) + '): ' + @descripcion;
                    PRINT ERROR_MESSAGE();
                END CATCH;
                IF @rechazado = 0
                BEGIN
                    PRINT 'FALLA - ' + @etiqueta + ': el SP no rechazó la designación del partido nro ' + CAST(@nro AS varchar(10)) + '.';
                    THROW 50099, N'Un rechazo esperado de la designación del cuerpo arbitral no ocurrió.', 1;
                END;
            END;

            -- Designación válida: los 5 árbitros con menos designaciones, de países que no juegan el partido y
            -- sin otro partido a menos de 3 horas. El principal es el que menos veces lo fue.
            DELETE FROM #candidatos;
            INSERT INTO #candidatos (idArbitro, carga, principales)
            SELECT TOP (5) x.idArbitro, x.carga, x.principales
            FROM (SELECT a.idArbitro,
                         (SELECT COUNT(*) FROM Arbitraje.cuerpoArbitral c WHERE c.idArbitro = a.idArbitro) AS carga,
                         (SELECT COUNT(*) FROM Arbitraje.cuerpoArbitral c
                          WHERE c.idArbitro = a.idArbitro AND c.rol = 'Principal') AS principales
                  FROM Arbitraje.Arbitro a
                  WHERE a.idPais NOT IN (@idPaisLocal, @idPaisVisit)
                    AND NOT EXISTS (SELECT 1
                                    FROM Arbitraje.cuerpoArbitral c
                                    JOIN Torneo.Partido pc ON pc.idPartido = c.idPartido
                                    WHERE c.idArbitro = a.idArbitro
                                      AND pc.idPartido <> @idPartido
                                      AND ABS(DATEDIFF(MINUTE, pc.fechaHoraUTC, @fecha)) < 180)) x
            ORDER BY x.carga, (x.idArbitro * 7 + @n * 3) % 23, x.idArbitro;

            IF (SELECT COUNT(*) FROM #candidatos) < 5
                THROW 50002, N'No hay 5 árbitros elegibles para el partido.', 1;

            SELECT @idPpal   = SUM(CASE WHEN r.rk = 1 THEN r.idArbitro ELSE 0 END),
                   @idAs1    = SUM(CASE WHEN r.rk = 2 THEN r.idArbitro ELSE 0 END),
                   @idAs2    = SUM(CASE WHEN r.rk = 3 THEN r.idArbitro ELSE 0 END),
                   @idCuarto = SUM(CASE WHEN r.rk = 4 THEN r.idArbitro ELSE 0 END),
                   @idVar    = SUM(CASE WHEN r.rk = 5 THEN r.idArbitro ELSE 0 END)
            FROM (SELECT idArbitro, ROW_NUMBER() OVER (ORDER BY principales, carga, idArbitro) AS rk
                  FROM #candidatos) r;

            EXEC Arbitraje.DesignarCuerpoArbitral @idPartido = @idPartido, @idPrincipal = @idPpal,
                 @idAsistente1 = @idAs1, @idAsistente2 = @idAs2, @idCuartoArbitro = @idCuarto,
                 @idVar = @idVar, @advertencia = @advertencia OUTPUT;

            PRINT 'Partido nro ' + CAST(@nro AS varchar(10)) + ' (' + @abrevLocal + '-' + @abrevVisit + '): cuerpo arbitral designado.';
            IF @advertencia IS NOT NULL
                PRINT 'Partido nro ' + CAST(@nro AS varchar(10)) + ' - advertencia de cruce devuelta en @advertencia:' + CHAR(10) + @advertencia;
        END;

        /* ---- b) Formación de cada selección ------------------------------------- */
        SET @lado = 0;
        WHILE @lado <= 1
        BEGIN
            SELECT @idSel = CASE WHEN @lado = 0 THEN @idLocal ELSE @idVisit END,
                   @abrevSel = CASE WHEN @lado = 0 THEN @abrevLocal ELSE @abrevVisit END;

            IF @estado = 'Programado'
               AND NOT EXISTS (SELECT 1 FROM Eventos.FormacionPartido WHERE idPartido = @idPartido AND idSeleccion = @idSel)
            BEGIN
                -- Convocados activos sin suspensión activa (la misma regla que aplica RegistrarFormacion)
                DELETE FROM #disponibles;
                INSERT INTO #disponibles (idJugador, dorsal, posicion, rk)
                SELECT lj.idJugador, lj.dorsal, j.posicion,
                       ROW_NUMBER() OVER (PARTITION BY j.posicion ORDER BY lj.dorsal)
                FROM Equipos.ListadoJugadores lj
                JOIN Equipos.Jugador j ON j.id = lj.idJugador
                WHERE lj.idSeleccion = @idSel
                  AND lj.fechaBaja IS NULL
                  AND NOT EXISTS (SELECT 1
                                  FROM Eventos.Suspension su
                                  JOIN Torneo.Partido ps ON ps.idPartido = su.idPartido
                                  WHERE su.idJugador = lj.idJugador
                                    AND su.partidosRestantes > 0
                                    AND ps.fechaHoraUTC < @fecha);

                -- Esquema: el que le toca por rotación o, si faltan jugadores de una posición, el siguiente posible
                SELECT @esquema = NULL;
                SET @base = (@n * 5 + @idSel + @lado * 3) % 6;
                SELECT TOP (1) @esquema = e.esquema, @cantDef = e.d, @cantMed = e.m, @cantDel = e.f
                FROM #esquemas e
                WHERE (SELECT COUNT(*) FROM #disponibles WHERE posicion = 'Arquero')       >= 1
                  AND (SELECT COUNT(*) FROM #disponibles WHERE posicion = 'Defensor')      >= e.d
                  AND (SELECT COUNT(*) FROM #disponibles WHERE posicion = 'Mediocampista') >= e.m
                  AND (SELECT COUNT(*) FROM #disponibles WHERE posicion = 'Delantero')     >= e.f
                ORDER BY ((e.idx - @base) % 6 + 6) % 6;

                IF @esquema IS NULL
                    THROW 50002, N'Los jugadores disponibles no alcanzan para ningún esquema táctico.', 1;

                DELETE FROM @jugadores;
                INSERT INTO @jugadores (idJugador, titular, posicion)
                SELECT d.idJugador,
                       CASE WHEN (d.posicion = 'Arquero'       AND d.rk = 1)
                              OR (d.posicion = 'Defensor'      AND d.rk <= @cantDef)
                              OR (d.posicion = 'Mediocampista' AND d.rk <= @cantMed)
                              OR (d.posicion = 'Delantero'     AND d.rk <= @cantDel)
                            THEN 1 ELSE 0 END,
                       d.posicion
                FROM #disponibles d
                ORDER BY d.dorsal;

                -- Cuerpo técnico: todo el Equipos.Staff de la selección menos los integrantes con suspensión
                -- activa para este partido (la misma regla que F19 de RegistrarFormacion)
                DELETE FROM @cuerpoTecnico;
                INSERT INTO @cuerpoTecnico (idStaff)
                SELECT st.id
                FROM Equipos.Staff st
                WHERE st.idSeleccion = @idSel
                  AND NOT EXISTS (SELECT 1
                                  FROM Eventos.Suspension su
                                  JOIN Torneo.Partido ps ON ps.idPartido = su.idPartido
                                  WHERE su.idStaff = st.id
                                    AND su.partidosRestantes > 0
                                    AND ps.fechaHoraUTC < @fecha);

                -- Integrante del cuerpo técnico con suspensión activa (si lo hay): se intenta incluirlo
                SELECT @idSuspStaff = NULL;
                SELECT TOP (1) @idSuspStaff = st.id, @apellidoSuspStaff = st.apellido
                FROM Equipos.Staff st
                WHERE st.idSeleccion = @idSel
                  AND EXISTS (SELECT 1
                              FROM Eventos.Suspension su
                              JOIN Torneo.Partido ps ON ps.idPartido = su.idPartido
                              WHERE su.idStaff = st.id
                                AND su.partidosRestantes > 0
                                AND ps.fechaHoraUTC < @fecha)
                ORDER BY st.id;

                -- Convocado con suspensión activa: se intenta incluirlo como titular y el SP debe rechazarlo
                SELECT @idSusp = NULL;
                SELECT TOP (1) @idSusp = lj.idJugador, @dorsalSusp = lj.dorsal, @posSusp = j.posicion
                FROM Equipos.ListadoJugadores lj
                JOIN Equipos.Jugador j ON j.id = lj.idJugador
                WHERE lj.idSeleccion = @idSel
                  AND lj.fechaBaja IS NULL
                  AND EXISTS (SELECT 1
                              FROM Eventos.Suspension su
                              JOIN Torneo.Partido ps ON ps.idPartido = su.idPartido
                              WHERE su.idJugador = lj.idJugador
                                AND su.partidosRestantes > 0
                                AND ps.fechaHoraUTC < @fecha)
                ORDER BY lj.dorsal;

                IF @idSusp IS NOT NULL
                BEGIN
                    -- Suspensión por acumulación de amarillas = caso 2; por expulsión = extra E4
                    SET @etiqueta = CASE WHEN EXISTS (SELECT 1
                                                      FROM Eventos.Suspension su
                                                      JOIN Eventos.Tarjeta t ON t.idTarjeta = su.idTarjeta AND t.color = 'R'
                                                      WHERE su.idJugador = @idSusp)
                                         THEN 'EXTRA E4' ELSE 'CASO OBLIGATORIO 2' END;

                    SELECT @etiqueta + ' - suspensión ANTES de la formación' AS evidencia, @nro AS nroPartido,
                           @abrevSel AS seleccion, j.apellido, j.nombre, su.idPartido AS partidoOrigen,
                           su.cantPartidos, su.partidosRestantes
                    FROM Eventos.Suspension su
                    JOIN Equipos.Jugador j ON j.id = su.idJugador
                    WHERE su.idJugador = @idSusp;

                    DELETE FROM @jugadoresMal;
                    INSERT INTO @jugadoresMal (idJugador, titular, posicion) SELECT idJugador, titular, posicion FROM @jugadores;
                    DELETE FROM @jugadoresMal
                    WHERE idJugador = (SELECT TOP (1) idJugador FROM @jugadoresMal
                                       WHERE titular = 1 AND posicion = @posSusp ORDER BY idJugador DESC);
                    INSERT INTO @jugadoresMal (idJugador, titular, posicion) VALUES (@idSusp, 1, @posSusp);

                    SET @rechazado = 0;
                    BEGIN TRY
                        EXEC Eventos.RegistrarFormacion @idPartido = @idPartido, @idSeleccion = @idSel,
                             @jugadores = @jugadoresMal, @cuerpoTecnico = @cuerpoTecnico, @esquema = @esquema;
                    END TRY
                    BEGIN CATCH
                        SET @rechazado = 1;
                        IF ERROR_NUMBER() <> 50002 THROW;
                        PRINT @etiqueta + ' - rechazo esperado (' + CAST(ERROR_NUMBER() AS varchar(10))
                            + '): formación de ' + @abrevSel + ' en el partido nro ' + CAST(@nro AS varchar(10))
                            + ' con el suspendido dorsal ' + CAST(@dorsalSusp AS varchar(10)) + ' como titular.';
                        PRINT ERROR_MESSAGE();
                    END CATCH;
                    IF @rechazado = 0
                    BEGIN
                        PRINT 'FALLA - ' + @etiqueta + ': el SP no rechazó la formación con un suspendido (' + @abrevSel
                            + ', partido nro ' + CAST(@nro AS varchar(10)) + ').';
                        THROW 50099, N'Un rechazo esperado de la formación con un suspendido no ocurrió.', 1;
                    END;
                END;

                -- Integrante del cuerpo técnico con suspensión activa: se intenta incluirlo y el SP debe rechazarlo
                -- (roja del staff = caso 3; acumulación de amarillas del staff = extra E5)
                IF @idSuspStaff IS NOT NULL
                BEGIN
                    SET @etiquetaStaff = CASE WHEN EXISTS (SELECT 1
                                                           FROM Eventos.Suspension su
                                                           JOIN Eventos.Tarjeta t ON t.idPartido = su.idPartido
                                                                                 AND t.idStaff = su.idStaff AND t.color = 'R'
                                                           WHERE su.idStaff = @idSuspStaff)
                                              THEN 'CASO OBLIGATORIO 3' ELSE 'EXTRA E5' END;

                    SELECT @etiquetaStaff + ' - suspensión del cuerpo técnico ANTES de la formación' AS evidencia, @nro AS nroPartido,
                           @abrevSel AS seleccion, st.apellido, st.rol, su.idPartido AS partidoOrigen,
                           su.cantPartidos, su.partidosRestantes
                    FROM Eventos.Suspension su
                    JOIN Equipos.Staff st ON st.id = su.idStaff
                    WHERE su.idStaff = @idSuspStaff;

                    DELETE FROM @cuerpoTecnicoMal;
                    INSERT INTO @cuerpoTecnicoMal (idStaff) SELECT idStaff FROM @cuerpoTecnico;
                    INSERT INTO @cuerpoTecnicoMal (idStaff) VALUES (@idSuspStaff);

                    SET @rechazado = 0;
                    BEGIN TRY
                        EXEC Eventos.RegistrarFormacion @idPartido = @idPartido, @idSeleccion = @idSel,
                             @jugadores = @jugadores, @cuerpoTecnico = @cuerpoTecnicoMal, @esquema = @esquema;
                    END TRY
                    BEGIN CATCH
                        SET @rechazado = 1;
                        IF ERROR_NUMBER() <> 50002 THROW;
                        PRINT @etiquetaStaff + ' - rechazo esperado (' + CAST(ERROR_NUMBER() AS varchar(10))
                            + '): formación de ' + @abrevSel + ' en el partido nro ' + CAST(@nro AS varchar(10))
                            + ' con el integrante suspendido ' + @apellidoSuspStaff + ' en el cuerpo técnico.';
                        PRINT ERROR_MESSAGE();
                    END CATCH;
                    IF @rechazado = 0
                    BEGIN
                        PRINT 'FALLA - ' + @etiquetaStaff + ': el SP no rechazó la formación con un integrante suspendido del cuerpo técnico ('
                            + @abrevSel + ', partido nro ' + CAST(@nro AS varchar(10)) + ').';
                        THROW 50099, N'Un rechazo esperado de la formación con un integrante suspendido del cuerpo técnico no ocurrió.', 1;
                    END;
                END;

                -- Formación válida (sin los suspendidos)
                EXEC Eventos.RegistrarFormacion @idPartido = @idPartido, @idSeleccion = @idSel,
                     @jugadores = @jugadores, @cuerpoTecnico = @cuerpoTecnico, @esquema = @esquema;

                SELECT @cantTit = SUM(CASE WHEN titular = 1 THEN 1 ELSE 0 END), @cantSup = SUM(CASE WHEN titular = 0 THEN 1 ELSE 0 END)
                FROM @jugadores;
                PRINT 'Partido nro ' + CAST(@nro AS varchar(10)) + ' - formación de ' + @abrevSel + ' registrada: esquema '
                    + @esquema + ', ' + CAST(@cantTit AS varchar(10)) + ' titulares y ' + CAST(@cantSup AS varchar(10)) + ' suplentes.';

                IF @idSusp IS NOT NULL
                    SELECT @etiqueta + ' - suspensión DESPUÉS de la formación válida' AS evidencia, @nro AS nroPartido,
                           @abrevSel AS seleccion, j.apellido, j.nombre, su.idPartido AS partidoOrigen,
                           su.cantPartidos, su.partidosRestantes
                    FROM Eventos.Suspension su
                    JOIN Equipos.Jugador j ON j.id = su.idJugador
                    WHERE su.idJugador = @idSusp;

                IF @idSuspStaff IS NOT NULL
                    SELECT @etiquetaStaff + ' - suspensión del cuerpo técnico DESPUÉS de la formación válida' AS evidencia, @nro AS nroPartido,
                           @abrevSel AS seleccion, st.apellido, st.rol, su.idPartido AS partidoOrigen,
                           su.cantPartidos, su.partidosRestantes
                    FROM Eventos.Suspension su
                    JOIN Equipos.Staff st ON st.id = su.idStaff
                    WHERE su.idStaff = @idSuspStaff;
            END;
            SET @lado += 1;
        END;

        /* ---- c) Pase a 'En juego' ---------------------------------------------- */
        IF @estado = 'Programado'
           AND (SELECT COUNT(DISTINCT idSeleccion) FROM Eventos.FormacionPartido WHERE idPartido = @idPartido) = 2
        BEGIN
            SELECT @esqLocal = p.esquemaLocal, @esqVisit = p.esquemaVisitante
            FROM Torneo.Partido p
            WHERE p.idPartido = @idPartido;

            EXEC Torneo.Partido_Modificacion @idPartido = @idPartido, @idSede = @idSede,
                 @idSeleccionLocal = @idLocal, @idSeleccionVisitante = @idVisit, @fase = @fase,
                 @fechaHoraUTC = @fecha, @estado = 'En juego', @nroPartidoOficial = @nro,
                 @cantPublico = @cantPublico, @golLocal = NULL, @golVisitante = NULL,
                 @esquemaLocal = @esqLocal, @esquemaVisitante = @esqVisit;
            SET @estado = 'En juego';
            PRINT 'Partido nro ' + CAST(@nro AS varchar(10)) + ' pasa a En juego (esquemas ' + ISNULL(@esqLocal, '-')
                + ' y ' + ISNULL(@esqVisit, '-') + ').';
        END;

        /* ---- d) Cambios, tarjetas y goles --------------------------------------- */
        -- Reanudable por fila: cada cambio, tarjeta y gol se carga solo si todavía no está, así una corrida
        -- cortada a mitad de los eventos de un partido se completa al volver a ejecutar.
        IF @estado = 'En juego'
        BEGIN
            -- Cambios
            SELECT @ord = MIN(ord) FROM #cambiosRes WHERE nro = @nro;
            WHILE @ord IS NOT NULL
            BEGIN
                SELECT @idSale = idSale, @idIngresa = idIngresa, @idPeriodo = idPeriodo, @minuto = minuto,
                       @minutoAdic = minutoAdicional, @motivo = motivo
                FROM #cambiosRes WHERE ord = @ord;

                IF NOT EXISTS (SELECT 1 FROM Eventos.Sustitucion
                               WHERE idPartido = @idPartido AND idSale = @idSale AND idIngresa = @idIngresa)
                BEGIN
                    EXEC Eventos.RegistrarCambio @idPartido = @idPartido, @idSale = @idSale, @idIngresa = @idIngresa,
                         @idPeriodo = @idPeriodo, @minuto = @minuto, @minutoAdicional = @minutoAdic, @motivo = @motivo;

                    IF @motivo = 'Lesion' AND @minuto <= 20
                        PRINT 'CASO OBLIGATORIO 4 - cambio por lesión en el minuto ' + CAST(@minuto AS varchar(10))
                            + ' del partido nro ' + CAST(@nro AS varchar(10)) + ' registrado.';
                END;

                SELECT @ord = MIN(ord) FROM #cambiosRes WHERE nro = @nro AND ord > @ord;
            END;

            -- Sexto cambio que el SP debe rechazar por MAX_CAMBIOS (extra E2)
            SET @etiqueta = NULL;
            SELECT @etiqueta = i.etiqueta, @idSale = ljs.idJugador, @idIngresa = lje.idJugador,
                   @minuto = i.minuto, @motivo = i.motivo
            FROM #intentoCambio i
            JOIN Equipos.Seleccion s ON s.abreviacion = i.sel
            JOIN Equipos.ListadoJugadores ljs ON ljs.idSeleccion = s.id AND ljs.dorsal = i.dorsalSale AND ljs.fechaBaja IS NULL
            JOIN Equipos.ListadoJugadores lje ON lje.idSeleccion = s.id AND lje.dorsal = i.dorsalEntra AND lje.fechaBaja IS NULL
            WHERE i.nro = @nro;

            IF @etiqueta IS NOT NULL
            BEGIN
                SET @rechazado = 0;
                BEGIN TRY
                    EXEC Eventos.RegistrarCambio @idPartido = @idPartido, @idSale = @idSale, @idIngresa = @idIngresa,
                         @idPeriodo = 2, @minuto = @minuto, @minutoAdicional = NULL, @motivo = @motivo;
                END TRY
                BEGIN CATCH
                    SET @rechazado = 1;
                    IF ERROR_NUMBER() <> 50002 THROW;
                    PRINT @etiqueta + ' - rechazo esperado (' + CAST(ERROR_NUMBER() AS varchar(10))
                        + '): sexto cambio de una selección en el partido nro ' + CAST(@nro AS varchar(10)) + ' sin alargue.';
                    PRINT ERROR_MESSAGE();
                END CATCH;
                IF @rechazado = 0
                BEGIN
                    PRINT 'FALLA - ' + @etiqueta + ': el SP no rechazó el sexto cambio del partido nro ' + CAST(@nro AS varchar(10)) + '.';
                    THROW 50099, N'Un rechazo esperado del sexto cambio no ocurrió.', 1;
                END;
            END;

            -- Tarjetas
            SELECT @ord = MIN(ord) FROM #tarjetasRes WHERE nro = @nro;
            WHILE @ord IS NOT NULL
            BEGIN
                SELECT @idJugador = idJugador, @idPeriodo = idPeriodo, @color = color, @minuto = minuto,
                       @minutoAdic = minutoAdicional, @motivo = motivo
                FROM #tarjetasRes WHERE ord = @ord;

                IF NOT EXISTS (SELECT 1 FROM Eventos.Tarjeta
                               WHERE idPartido = @idPartido AND idJugador = @idJugador AND color = @color
                                 AND minuto = @minuto AND ISNULL(CAST(minutoAdicional AS int), -1) = ISNULL(CAST(@minutoAdic AS int), -1))
                BEGIN
                    EXEC Eventos.RegistrarTarjeta @idPartido = @idPartido, @idJugador = @idJugador, @idPeriodo = @idPeriodo,
                         @color = @color, @minuto = @minuto, @minutoAdicional = @minutoAdic, @motivo = @motivo;

                    IF @color = 'R'
                        PRINT 'CASO OBLIGATORIO 1 - roja directa en el partido nro ' + CAST(@nro AS varchar(10))
                            + ' (minuto ' + CAST(@minuto AS varchar(10)) + ') y suspensión de 1 partido generada.';
                END;

                SELECT @ord = MIN(ord) FROM #tarjetasRes WHERE nro = @nro AND ord > @ord;
            END;

            IF EXISTS (SELECT 1 FROM Eventos.Tarjeta WHERE idPartido = @idPartido AND tipoRoja = 'Doble amarilla')
                PRINT 'CASO OBLIGATORIO 1 - doble amarilla en el partido nro ' + CAST(@nro AS varchar(10))
                    + ': la segunda amarilla generó sola la roja y la suspensión de 1 partido.';

            -- Tarjetas al cuerpo técnico (caso 3 y extra E5), después de las de los jugadores del partido
            SELECT @ord = MIN(ord) FROM #tarjetasStaffRes WHERE nro = @nro;
            WHILE @ord IS NOT NULL
            BEGIN
                SELECT @idStaff = idStaff, @idPeriodo = idPeriodo, @color = color, @minuto = minuto,
                       @minutoAdic = minutoAdicional, @motivo = motivo
                FROM #tarjetasStaffRes WHERE ord = @ord;

                IF NOT EXISTS (SELECT 1 FROM Eventos.Tarjeta
                               WHERE idPartido = @idPartido AND idStaff = @idStaff AND color = @color
                                 AND minuto = @minuto AND ISNULL(CAST(minutoAdicional AS int), -1) = ISNULL(CAST(@minutoAdic AS int), -1))
                BEGIN
                    EXEC Eventos.RegistrarTarjeta @idPartido = @idPartido, @idStaff = @idStaff, @idPeriodo = @idPeriodo,
                         @color = @color, @minuto = @minuto, @minutoAdicional = @minutoAdic, @motivo = @motivo,
                         @idTarjeta = @idTarjeta OUTPUT;

                    SELECT @rolStaff = st.rol, @abrevStaff = se.abreviacion
                    FROM Equipos.Staff st
                    JOIN Equipos.Seleccion se ON se.id = st.idSeleccion
                    WHERE st.id = @idStaff;

                    IF @color = 'R'
                        PRINT 'CASO OBLIGATORIO 3 - roja al ' + @rolStaff + ' de ' + @abrevStaff + ' en el partido nro '
                            + CAST(@nro AS varchar(10)) + ' (minuto ' + CAST(@minuto AS varchar(10))
                            + ') y suspensión de 1 partido generada.';
                    ELSE IF EXISTS (SELECT 1 FROM Eventos.Suspension WHERE idTarjeta = @idTarjeta)
                        PRINT 'EXTRA E5 - amarilla al ' + @rolStaff + ' de ' + @abrevStaff + ' en el partido nro '
                            + CAST(@nro AS varchar(10)) + ' (minuto ' + CAST(@minuto AS varchar(10))
                            + '): acumulación de amarillas del cuerpo técnico y suspensión de 1 partido generada.';
                    ELSE
                        PRINT 'EXTRA E5 - amarilla al ' + @rolStaff + ' de ' + @abrevStaff + ' en el partido nro '
                            + CAST(@nro AS varchar(10)) + ' (minuto ' + CAST(@minuto AS varchar(10))
                            + '): todavía sin suspensión (no alcanza AMARILLAS_SUSPENSION_STAFF).';
                END;

                SELECT @ord = MIN(ord) FROM #tarjetasStaffRes WHERE nro = @nro AND ord > @ord;
            END;

            -- Tarjeta a un jugador ya expulsado, que el SP debe rechazar (extra E3)
            SET @etiqueta = NULL;
            SELECT @etiqueta = i.etiqueta, @idJugador = lj.idJugador, @color = i.color, @minuto = i.minuto, @motivo = i.motivo
            FROM #intentoTarjeta i
            JOIN Equipos.Seleccion s ON s.abreviacion = i.sel
            JOIN Equipos.ListadoJugadores lj ON lj.idSeleccion = s.id AND lj.dorsal = i.dorsal AND lj.fechaBaja IS NULL
            WHERE i.nro = @nro;

            IF @etiqueta IS NOT NULL
            BEGIN
                SET @rechazado = 0;
                BEGIN TRY
                    EXEC Eventos.RegistrarTarjeta @idPartido = @idPartido, @idJugador = @idJugador, @idPeriodo = 2,
                         @color = @color, @minuto = @minuto, @minutoAdicional = NULL, @motivo = @motivo;
                END TRY
                BEGIN CATCH
                    SET @rechazado = 1;
                    IF ERROR_NUMBER() <> 50002 THROW;
                    PRINT @etiqueta + ' - rechazo esperado (' + CAST(ERROR_NUMBER() AS varchar(10))
                        + '): tarjeta a un jugador ya expulsado en el partido nro ' + CAST(@nro AS varchar(10)) + '.';
                    PRINT ERROR_MESSAGE();
                END CATCH;
                IF @rechazado = 0
                BEGIN
                    PRINT 'FALLA - ' + @etiqueta + ': el SP no rechazó la tarjeta al expulsado del partido nro ' + CAST(@nro AS varchar(10)) + '.';
                    THROW 50099, N'Un rechazo esperado de la tarjeta a un expulsado no ocurrió.', 1;
                END;
            END;

            -- Goles
            SELECT @ord = MIN(ord) FROM #golesRes WHERE nro = @nro;
            WHILE @ord IS NOT NULL
            BEGIN
                SELECT @idJugador = idJugador, @idAsistidor = idAsistidor, @idPeriodo = idPeriodo, @minuto = minuto,
                       @minutoAdic = minutoAdicional, @tipo = tipo
                FROM #golesRes WHERE ord = @ord;

                IF NOT EXISTS (SELECT 1 FROM Eventos.Gol
                               WHERE idPartido = @idPartido AND idJugador = @idJugador AND minuto = @minuto
                                 AND ISNULL(CAST(minutoAdicional AS int), -1) = ISNULL(CAST(@minutoAdic AS int), -1) AND tipo = @tipo)
                    EXEC Eventos.Gol_Alta @idPartido = @idPartido, @idJugador = @idJugador, @idAsistidor = @idAsistidor,
                         @minuto = @minuto, @minutoAdicional = @minutoAdic, @tipo = @tipo, @idPeriodo = @idPeriodo;

                SELECT @ord = MIN(ord) FROM #golesRes WHERE nro = @nro AND ord > @ord;
            END;

            SELECT @cantCambios  = (SELECT COUNT(*) FROM Eventos.Sustitucion WHERE idPartido = @idPartido),
                   @cantTarjetas = (SELECT COUNT(*) FROM Eventos.Tarjeta WHERE idPartido = @idPartido),
                   @cantGoles    = (SELECT COUNT(*) FROM Eventos.Gol WHERE idPartido = @idPartido);
            PRINT 'Partido nro ' + CAST(@nro AS varchar(10)) + ' - eventos cargados: ' + CAST(@cantCambios AS varchar(10))
                + ' cambios, ' + CAST(@cantTarjetas AS varchar(10)) + ' tarjetas y ' + CAST(@cantGoles AS varchar(10)) + ' goles.';
        END;
    END TRY
    BEGIN CATCH
        PRINT 'Error al procesar el partido nro ' + CAST(@nro AS varchar(10)) + ' (fila ' + CAST(@n AS varchar(10)) + ' de #orden).';
        THROW;
    END CATCH;
    SET @n += 1;
END;
GO

/* =============================================================================
   RESUMEN DE LA CARGA
   ============================================================================= */

-- Por partido: cuerpo arbitral (debe ser 5), formaciones (2 x (11 + hasta 15)), eventos y marcador de los goles
-- contra el marcador que cierra 53 (un 'En contra' suma al rival).
SELECT p.nroPartidoOficial AS nro, sl.abreviacion + '-' + sv.abreviacion AS partido, p.estado,
       (SELECT COUNT(*) FROM Arbitraje.cuerpoArbitral c WHERE c.idPartido = p.idPartido) AS arbitros,
       (SELECT COUNT(*) FROM Eventos.FormacionPartido f WHERE f.idPartido = p.idPartido AND f.titular = 1) AS titulares,
       (SELECT COUNT(*) FROM Eventos.FormacionPartido f WHERE f.idPartido = p.idPartido AND f.titular = 0) AS suplentes,
       (SELECT COUNT(*) FROM Eventos.Sustitucion s WHERE s.idPartido = p.idPartido) AS cambios,
       (SELECT COUNT(*) FROM Eventos.Tarjeta t WHERE t.idPartido = p.idPartido) AS tarjetas,
       (SELECT COUNT(*) FROM Eventos.CuerpoTecnicoPartido ct WHERE ct.idPartido = p.idPartido) AS cuerpoTecnico,
       g.goles, g.golesLocal, g.golesVisitante, m.golLocal AS esperadoLocal, m.golVisitante AS esperadoVisitante,
       CASE WHEN g.golesLocal = m.golLocal AND g.golesVisitante = m.golVisitante THEN 'OK' ELSE 'DIFIERE' END AS marcador
FROM Torneo.Partido p
JOIN #marcadores m        ON m.nro = p.nroPartidoOficial
JOIN Equipos.Seleccion sl ON sl.id = p.idSeleccionLocal
JOIN Equipos.Seleccion sv ON sv.id = p.idSeleccionVisitante
CROSS APPLY (SELECT COUNT(*) AS goles, ISNULL(SUM(x.paraLocal), 0) AS golesLocal, ISNULL(SUM(x.paraVisitante), 0) AS golesVisitante
             FROM (SELECT CASE WHEN (fp.idSeleccion = p.idSeleccionLocal AND go.tipo <> 'En contra')
                                 OR (fp.idSeleccion = p.idSeleccionVisitante AND go.tipo = 'En contra')
                               THEN 1 ELSE 0 END AS paraLocal,
                          CASE WHEN (fp.idSeleccion = p.idSeleccionVisitante AND go.tipo <> 'En contra')
                                 OR (fp.idSeleccion = p.idSeleccionLocal AND go.tipo = 'En contra')
                               THEN 1 ELSE 0 END AS paraVisitante
                   FROM Eventos.Gol go
                   JOIN Eventos.FormacionPartido fp ON fp.idPartido = go.idPartido AND fp.idJugador = go.idJugador
                   WHERE go.idPartido = p.idPartido) x) g
ORDER BY p.fechaHoraUTC, p.idPartido;

-- Totales y estado de los partidos
SELECT (SELECT COUNT(*) FROM Arbitraje.cuerpoArbitral) AS designaciones,
       (SELECT COUNT(*) FROM Eventos.FormacionPartido) AS filasFormacion,
       (SELECT COUNT(*) FROM Eventos.Sustitucion) AS cambios,
       (SELECT COUNT(*) FROM Eventos.Tarjeta) AS tarjetas,
       (SELECT COUNT(*) FROM Eventos.Gol) AS goles,
       (SELECT COUNT(*) FROM Eventos.Gol WHERE tipo = 'En contra') AS golesEnContra,
       (SELECT COUNT(*) FROM Eventos.Suspension) AS suspensiones,
       (SELECT COUNT(*) FROM Eventos.CuerpoTecnicoPartido) AS filasCuerpoTecnico,
       (SELECT COUNT(*) FROM Eventos.Suspension WHERE idTarjeta IS NULL) AS suspensionesSinTarjeta;   -- debe dar 0

SELECT estado, COUNT(*) AS partidos FROM Torneo.Partido GROUP BY estado;

-- Coherencia: goles y tarjetas de jugadores que estaban en cancha en ese minuto (Eventos.fn_EquipoEnCancha de 31).
-- Un gol en contra puede ser de cualquier jugador en cancha. Deben dar 0 filas.
SELECT 'gol con autor o asistente fuera de la cancha' AS incoherencia, g.idGol AS id
FROM Eventos.Gol g
WHERE g.minuto IS NOT NULL
  AND (NOT EXISTS (SELECT 1 FROM Eventos.fn_EquipoEnCancha(g.idPartido, g.minuto) c WHERE c.idJugador = g.idJugador)
       OR (g.idAsistidor IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM Eventos.fn_EquipoEnCancha(g.idPartido, g.minuto) c WHERE c.idJugador = g.idAsistidor)))
UNION ALL
SELECT 'amarilla a un jugador fuera de la cancha', t.idTarjeta
FROM Eventos.Tarjeta t
WHERE t.color = 'A'
  AND t.idJugador IS NOT NULL   -- las tarjetas al cuerpo técnico tienen idJugador NULL
  AND NOT EXISTS (SELECT 1 FROM Eventos.fn_EquipoEnCancha(t.idPartido, t.minuto) c WHERE c.idJugador = t.idJugador)
  -- la segunda amarilla de una doble amarilla genera una roja en el mismo minuto
  AND NOT EXISTS (SELECT 1 FROM Eventos.Tarjeta r WHERE r.idPartido = t.idPartido AND r.idJugador = t.idJugador
                                                     AND r.color = 'R' AND r.minuto = t.minuto)
UNION ALL
SELECT 'tarjeta a un integrante que no figura en el cuerpo técnico del partido', t.idTarjeta
FROM Eventos.Tarjeta t
WHERE t.idStaff IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM Eventos.CuerpoTecnicoPartido ct WHERE ct.idPartido = t.idPartido AND ct.idStaff = t.idStaff);

-- CASO OBLIGATORIO 1 (evidencia): rojas (doble amarilla y directa) con su suspensión
SELECT 'CASO OBLIGATORIO 1' AS caso, p.nroPartidoOficial AS nro, s.abreviacion AS seleccion, lj.dorsal, j.apellido,
       t.color, t.minuto, t.tipoRoja, t.motivo, su.cantPartidos, su.partidosRestantes
FROM Eventos.Tarjeta t
JOIN Torneo.Partido p        ON p.idPartido = t.idPartido
JOIN Equipos.Jugador j       ON j.id = t.idJugador
JOIN Equipos.ListadoJugadores lj ON lj.idJugador = j.id AND lj.fechaBaja IS NULL
JOIN Equipos.Seleccion s     ON s.id = lj.idSeleccion
LEFT JOIN Eventos.Suspension su ON su.idTarjeta = t.idTarjeta
WHERE t.color = 'R' AND t.idJugador IS NOT NULL
ORDER BY p.fechaHoraUTC, t.idTarjeta;

-- CASO OBLIGATORIO 3 (evidencia): rojas al cuerpo técnico con su suspensión
SELECT 'CASO OBLIGATORIO 3' AS caso, p.nroPartidoOficial AS nro, s.abreviacion AS seleccion, st.apellido, st.rol,
       t.color, t.minuto, t.tipoRoja, su.cantPartidos, su.partidosRestantes, su.idTarjeta
FROM Eventos.Tarjeta t
JOIN Torneo.Partido p        ON p.idPartido = t.idPartido
JOIN Equipos.Staff st        ON st.id = t.idStaff
JOIN Equipos.Seleccion s     ON s.id = st.idSeleccion
LEFT JOIN Eventos.Suspension su ON su.idTarjeta = t.idTarjeta
WHERE t.color = 'R' AND t.idStaff IS NOT NULL
ORDER BY p.fechaHoraUTC, t.idTarjeta;

-- Suspensiones (la de URU 6 viene de la acumulación de amarillas: CASO OBLIGATORIO 2)
SELECT p.nroPartidoOficial AS nroPartidoOrigen, s.abreviacion AS seleccion, lj.dorsal, j.apellido,
       su.cantPartidos, su.partidosRestantes,
       CASE WHEN t.color = 'R' THEN 'Expulsion'
            WHEN t.color = 'A' THEN 'Acumulacion de amarillas'
            ELSE 'Manual' END AS origen
FROM Eventos.Suspension su
LEFT JOIN Eventos.Tarjeta t  ON t.idTarjeta = su.idTarjeta
JOIN Torneo.Partido p        ON p.idPartido = su.idPartido
JOIN Equipos.Jugador j       ON j.id = su.idJugador
JOIN Equipos.ListadoJugadores lj ON lj.idJugador = j.id AND lj.fechaBaja IS NULL
JOIN Equipos.Seleccion s     ON s.id = lj.idSeleccion
WHERE su.idJugador IS NOT NULL
ORDER BY p.fechaHoraUTC, su.id;

-- Suspensiones del cuerpo técnico (el Director Principal de NOR viene de una roja: CASO OBLIGATORIO 3;
-- el Ayudante de ESP, de la acumulación de amarillas: EXTRA E5)
SELECT p.nroPartidoOficial AS nroPartidoOrigen, s.abreviacion AS seleccion, st.rol, st.apellido,
       su.cantPartidos, su.partidosRestantes, su.idTarjeta,
       CASE WHEN t.color = 'R' THEN 'Expulsion' ELSE 'Acumulacion de amarillas' END AS origen
FROM Eventos.Suspension su
JOIN Torneo.Partido p        ON p.idPartido = su.idPartido
JOIN Equipos.Staff st        ON st.id = su.idStaff
JOIN Equipos.Seleccion s     ON s.id = st.idSeleccion
LEFT JOIN Eventos.Tarjeta t  ON t.idTarjeta = su.idTarjeta
WHERE su.idStaff IS NOT NULL
ORDER BY p.fechaHoraUTC, su.id;

-- CASO OBLIGATORIO 4 (evidencia): cambio por lesión en los primeros 20 minutos
SELECT 'CASO OBLIGATORIO 4' AS caso, p.nroPartidoOficial AS nro, su.minuto, su.motivo,
       js.apellido AS sale, ji.apellido AS entra
FROM Eventos.Sustitucion su
JOIN Torneo.Partido p ON p.idPartido = su.idPartido
JOIN Equipos.Jugador js ON js.id = su.idSale
JOIN Equipos.Jugador ji ON ji.id = su.idIngresa
WHERE su.motivo = 'Lesion' AND su.minuto <= 20;

-- Carga de trabajo de los árbitros (designaciones y veces como principal)
SELECT a.apellido + N', ' + a.nombre AS arbitro, pa.nombre AS pais, COUNT(c.id) AS designaciones,
       SUM(CASE WHEN c.rol = 'Principal' THEN 1 ELSE 0 END) AS comoPrincipal
FROM Arbitraje.Arbitro a
JOIN Torneo.Pais pa ON pa.id = a.idPais
LEFT JOIN Arbitraje.cuerpoArbitral c ON c.idArbitro = a.idArbitro
GROUP BY a.idArbitro, a.apellido, a.nombre, pa.nombre
ORDER BY designaciones DESC, a.apellido;
GO
