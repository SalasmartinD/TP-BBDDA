/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 09/11/2026

 Objetivo    : Carga las claves de Sistema.Parametro que usan los SP de
               negocio de convocatorias (20b), según el reglamento de la Copa
               Mundial de la FIFA 2026:
               - MIN_CONVOCADOS = 23 y MAX_CONVOCADOS = 26 jugadores por lista.
               - HORAS_LIMITE_REEMPLAZO = 24: un jugador de campo lesionado se
                 puede reemplazar hasta 24 horas antes del primer partido de su
                 selección (a un arquero, en cualquier momento).

 Uso         : Sistema.Parametro es compartida y no tiene SP de ABM, así que
               cada integrante carga sus propias claves con un INSERT. Solo se
               insertan las que no existen: el script se puede ejecutar varias
               veces y no pisa un valor que se haya cambiado a mano.
================================================================================
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

INSERT INTO Sistema.Parametro (clave, valor, descripcion)
SELECT nuevo.clave, nuevo.valor, nuevo.descripcion
FROM (VALUES
    ('MIN_CONVOCADOS',         23, 'Mínimo de convocados activos por selección'),
    ('MAX_CONVOCADOS',         26, 'Máximo de convocados activos por selección'),
    ('HORAS_LIMITE_REEMPLAZO', 24, 'Horas antes del primer partido hasta las que se reemplaza a un jugador de campo')
) AS nuevo (clave, valor, descripcion)
WHERE NOT EXISTS (SELECT 1 FROM Sistema.Parametro p WHERE p.clave = nuevo.clave);
GO

-- Resumen de la carga
SELECT clave, valor, descripcion FROM Sistema.Parametro
WHERE clave IN ('MIN_CONVOCADOS', 'MAX_CONVOCADOS', 'HORAS_LIMITE_REEMPLAZO');
GO
