/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 09/11/2026

 Objetivo    : Pruebas de 40a_Importar_FixtureCSV.sql
               (Torneo.Importar_FixtureCSV): alta, modificación y repetición
               de la importación sin duplicados, importación parcial con
               filas inválidas (caso obligatorio de la consigna), registro de
               los errores en Sistema.ErrorImportacion y errores de archivo.

 Requisitos  : - Ejecutar en modo SQLCMD (en SSMS: Consulta > Modo SQLCMD),
                 porque usa la variable RUTA_DATASETS.
               - Cambiar RUTA_DATASETS (la línea :setvar de más abajo, por
                 defecto C:\TP-BBDDA\datasets\) por la carpeta datasets/ de la
                 repo en esta máquina, terminada en \ y legible por la cuenta
                 que ejecuta. Si la ruta no coincide, todas las pruebas fallan.
                 Se cambia editando esa línea, tanto en SSMS como con sqlcmd:
                 el :setvar del archivo pisa a la opción -v de sqlcmd.
               - 00_InitialSchema.sql, 10a, 10b, 40a y la carga base 50a, 50b y
                 50c (el test usa las selecciones de España, Argentina, Francia,
                 Inglaterra, Noruega y Ghana, y las sedes de Miami y Atlanta).

 Datos de prueba:
 - prueba_fixture_1.csv: 14 filas. 2 altas válidas (partidos 9001 y 9002), el
   partido real 14 sin cambios y 11 filas inválidas, cada una por un motivo.
 - prueba_fixture_2.csv: 3 filas. Modifica los partidos 9001 y 9002 y repite
   el partido real 14.
 - prueba_fixture_encabezado.csv: 8 columnas con otro encabezado.
 - prueba_fixture_columnas.csv: 3 columnas en vez de 8.
 - Los partidos de prueba (9001 y 9002) y los errores de estos archivos se
   borran al inicio y al final. Los 31 partidos reales no se tocan.

 Cada prueba imprime [OK] o [FALLO]. Resultado esperado: todas [OK].
================================================================================
*/

:setvar RUTA_DATASETS "C:\TP-BBDDA\datasets\"

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

PRINT '================================================================================';
PRINT ' PRUEBAS: 40a_Importar_FixtureCSV.sql';
PRINT '================================================================================';
GO

/* =============================================================================
   LIMPIEZA PREVIA
   ============================================================================= */
DELETE FROM Sistema.ErrorImportacion WHERE archivo LIKE N'%prueba_fixture%';
DELETE FROM Torneo.Partido WHERE nroPartidoOficial IN (9001, 9002);
GO

DROP TABLE IF EXISTS #r;
CREATE TABLE #r (filasLeidas int, insertados int, actualizados int, sinCambios int, conError int);
GO

/* =============================================================================
   1. Importación con filas válidas e inválidas (prueba_fixture_1.csv)
   ============================================================================= */
PRINT '--- 1. Importación parcial ---';

-- PRUEBA 1.1: primera importación
-- Resultado esperado: 14 filas leídas, 2 insertadas (9001 y 9002), 0 actualizadas,
-- 1 sin cambios (el partido real 14) y 11 con error. Los 31 partidos reales siguen iguales.
BEGIN TRY
    DECLARE @antes int = (SELECT COUNT(*) FROM Torneo.Partido);
    DECLARE @chkAntes int = (SELECT CHECKSUM_AGG(CHECKSUM(nroPartidoOficial, idSede, idSeleccionLocal,
                             idSeleccionVisitante, fase, fechaHoraUTC, estado, golLocal, golVisitante, cantPublico))
                             FROM Torneo.Partido WHERE nroPartidoOficial < 9000);
    DELETE FROM #r;
    INSERT INTO #r EXEC Torneo.Importar_FixtureCSV @rutaArchivo = N'$(RUTA_DATASETS)prueba_fixture_1.csv';
    SELECT 'DESPUES 1.1' AS momento, * FROM #r;
    SELECT 'DESPUES 1.1' AS momento, nroPartidoOficial, estado, golLocal, golVisitante, fechaHoraUTC
    FROM Torneo.Partido WHERE nroPartidoOficial IN (9001, 9002);
    IF EXISTS (SELECT 1 FROM #r WHERE filasLeidas = 14 AND insertados = 2 AND actualizados = 0
               AND sinCambios = 1 AND conError = 11)
       AND (SELECT COUNT(*) FROM Torneo.Partido) = @antes + 2
       AND EXISTS (SELECT 1 FROM Torneo.Partido WHERE nroPartidoOficial = 9001 AND estado = 'Programado'
                   AND golLocal IS NULL AND fechaHoraUTC = '2030-01-01 18:00')
       AND EXISTS (SELECT 1 FROM Torneo.Partido WHERE nroPartidoOficial = 9002 AND estado = 'Finalizado'
                   AND golLocal = 2 AND golVisitante = 1)
       AND @chkAntes = (SELECT CHECKSUM_AGG(CHECKSUM(nroPartidoOficial, idSede, idSeleccionLocal,
                        idSeleccionVisitante, fase, fechaHoraUTC, estado, golLocal, golVisitante, cantPublico))
                        FROM Torneo.Partido WHERE nroPartidoOficial < 9000)
        PRINT '[OK] PRUEBA 1.1: se importaron las filas válidas y los partidos reales no cambiaron.';
    ELSE PRINT '[FALLO] PRUEBA 1.1: el resultado de la importación no es el esperado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.2: las 11 filas inválidas quedaron en Sistema.ErrorImportacion
-- Resultado esperado: 11 errores con el nombre del archivo, la tabla Torneo.Partido y el número de fila.
BEGIN TRY
    SELECT 'EVIDENCIA 1.2' AS momento, nroFila, datoOriginal, REPLACE(mensajeError, CHAR(10), ' ') AS mensaje
    FROM Sistema.ErrorImportacion WHERE archivo LIKE N'%prueba_fixture_1.csv' ORDER BY nroFila;
    IF (SELECT COUNT(*) FROM Sistema.ErrorImportacion
        WHERE archivo LIKE N'%prueba_fixture_1.csv' AND tablaDestino = 'Torneo.Partido' AND nroFila IS NOT NULL) = 11
       AND (SELECT STRING_AGG(CAST(nroFila AS varchar(5)), ',') WITHIN GROUP (ORDER BY nroFila)
            FROM Sistema.ErrorImportacion WHERE archivo LIKE N'%prueba_fixture_1.csv') = '5,6,7,8,9,10,11,12,13,14,15'
        PRINT '[OK] PRUEBA 1.2: las 11 filas inválidas se registraron con su número de fila.';
    ELSE PRINT '[FALLO] PRUEBA 1.2: los errores registrados no son los esperados.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.3: el motivo de cada fila inválida
-- Resultado esperado: fila 5 número inválido; 6 fecha; 7 sede desconocida; 8 selección
-- desconocida; 9 selección no cargada; 10 selecciones iguales; 11 ronda; 12 resultado;
-- 13 número repetido en el archivo; 15 rechazo del ABM por la sede ocupada.
BEGIN TRY
    IF EXISTS (SELECT 1 FROM Sistema.ErrorImportacion WHERE archivo LIKE N'%prueba_fixture_1.csv' AND nroFila = 5
               AND mensajeError LIKE N'%número de partido no es un entero%')
       AND EXISTS (SELECT 1 FROM Sistema.ErrorImportacion WHERE archivo LIKE N'%prueba_fixture_1.csv' AND nroFila = 6
                   AND mensajeError LIKE N'%fecha no tiene el formato%')
       AND EXISTS (SELECT 1 FROM Sistema.ErrorImportacion WHERE archivo LIKE N'%prueba_fixture_1.csv' AND nroFila = 7
                   AND mensajeError LIKE N'%Nowhere Arena%no es una sede conocida%')
       AND EXISTS (SELECT 1 FROM Sistema.ErrorImportacion WHERE archivo LIKE N'%prueba_fixture_1.csv' AND nroFila = 8
                   AND mensajeError LIKE N'%Atlantis%no es una selección conocida%')
       AND EXISTS (SELECT 1 FROM Sistema.ErrorImportacion WHERE archivo LIKE N'%prueba_fixture_1.csv' AND nroFila = 9
                   AND mensajeError LIKE N'%Brazil%no está cargada%')
       AND EXISTS (SELECT 1 FROM Sistema.ErrorImportacion WHERE archivo LIKE N'%prueba_fixture_1.csv' AND nroFila = 10
                   AND mensajeError LIKE N'%local y la visitante deben ser distintas%')
       AND EXISTS (SELECT 1 FROM Sistema.ErrorImportacion WHERE archivo LIKE N'%prueba_fixture_1.csv' AND nroFila = 11
                   AND mensajeError LIKE N'%ronda "Round of 99"%')
       AND EXISTS (SELECT 1 FROM Sistema.ErrorImportacion WHERE archivo LIKE N'%prueba_fixture_1.csv' AND nroFila = 12
                   AND mensajeError LIKE N'%resultado no tiene el formato%')
       AND EXISTS (SELECT 1 FROM Sistema.ErrorImportacion WHERE archivo LIKE N'%prueba_fixture_1.csv' AND nroFila = 13
                   AND mensajeError LIKE N'%9001 ya figura en la fila 2%')
       AND EXISTS (SELECT 1 FROM Sistema.ErrorImportacion WHERE archivo LIKE N'%prueba_fixture_1.csv' AND nroFila = 15
                   AND mensajeError LIKE N'%sede ya tiene otro partido a menos de 24 horas%')
        PRINT '[OK] PRUEBA 1.3: cada fila inválida tiene su motivo.';
    ELSE PRINT '[FALLO] PRUEBA 1.3: algún motivo de error no es el esperado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.4: una fila con varios problemas los informa todos juntos
-- Resultado esperado: la fila 14 (todo vacío salvo el número) trae fecha, sede, selecciones y
-- resultado en un único mensaje.
BEGIN TRY
    SELECT 'EVIDENCIA 1.4' AS momento, REPLACE(mensajeError, CHAR(10), ' | ') AS mensaje
    FROM Sistema.ErrorImportacion WHERE archivo LIKE N'%prueba_fixture_1.csv' AND nroFila = 14;
    IF EXISTS (SELECT 1 FROM Sistema.ErrorImportacion WHERE archivo LIKE N'%prueba_fixture_1.csv' AND nroFila = 14
               AND mensajeError LIKE N'%fecha no tiene el formato%'
               AND mensajeError LIKE N'%no es una sede conocida%'
               AND mensajeError LIKE N'%selección local%no es una selección conocida%'
               AND mensajeError LIKE N'%selección visitante%no es una selección conocida%')
        PRINT '[OK] PRUEBA 1.4: los errores de una misma fila se informaron juntos.';
    ELSE PRINT '[FALLO] PRUEBA 1.4: los errores de la fila no se informaron juntos.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.4: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   2. Upsert: modificación y repetición (prueba_fixture_2.csv)
   ============================================================================= */
PRINT '--- 2. Upsert ---';

-- PRUEBA 2.1: segundo archivo con cambios sobre los partidos ya importados
-- Resultado esperado: 3 filas, 0 insertadas, 2 actualizadas (9001 pasa a Finalizado 3-2; 9002
-- cambia la hora a las 21:00 y conserva el 2-1 aunque el archivo no trae resultado), 1 sin
-- cambios (partido 14) y 0 errores. No se agregan partidos.
BEGIN TRY
    DECLARE @antes2 int = (SELECT COUNT(*) FROM Torneo.Partido);
    DELETE FROM #r;
    INSERT INTO #r EXEC Torneo.Importar_FixtureCSV @rutaArchivo = N'$(RUTA_DATASETS)prueba_fixture_2.csv';
    SELECT 'DESPUES 2.1' AS momento, * FROM #r;
    SELECT 'DESPUES 2.1' AS momento, nroPartidoOficial, estado, golLocal, golVisitante, fechaHoraUTC
    FROM Torneo.Partido WHERE nroPartidoOficial IN (9001, 9002);
    IF EXISTS (SELECT 1 FROM #r WHERE filasLeidas = 3 AND insertados = 0 AND actualizados = 2
               AND sinCambios = 1 AND conError = 0)
       AND (SELECT COUNT(*) FROM Torneo.Partido) = @antes2
       AND EXISTS (SELECT 1 FROM Torneo.Partido WHERE nroPartidoOficial = 9001 AND estado = 'Finalizado'
                   AND golLocal = 3 AND golVisitante = 2)
       AND EXISTS (SELECT 1 FROM Torneo.Partido WHERE nroPartidoOficial = 9002 AND estado = 'Finalizado'
                   AND golLocal = 2 AND golVisitante = 1 AND fechaHoraUTC = '2030-01-03 21:00')
        PRINT '[OK] PRUEBA 2.1: los partidos existentes se modificaron sin duplicarse.';
    ELSE PRINT '[FALLO] PRUEBA 2.1: el resultado de la importación no es el esperado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.2: repetir el mismo archivo
-- Resultado esperado: 3 filas, todas sin cambios; no se agrega ni modifica nada.
BEGIN TRY
    DECLARE @antes3 int = (SELECT COUNT(*) FROM Torneo.Partido);
    DELETE FROM #r;
    INSERT INTO #r EXEC Torneo.Importar_FixtureCSV @rutaArchivo = N'$(RUTA_DATASETS)prueba_fixture_2.csv';
    SELECT 'DESPUES 2.2' AS momento, * FROM #r;
    IF EXISTS (SELECT 1 FROM #r WHERE filasLeidas = 3 AND insertados = 0 AND actualizados = 0
               AND sinCambios = 3 AND conError = 0)
       AND (SELECT COUNT(*) FROM Torneo.Partido) = @antes3
        PRINT '[OK] PRUEBA 2.2: repetir la importación no duplica ni modifica.';
    ELSE PRINT '[FALLO] PRUEBA 2.2: la repetición no dejó todo sin cambios.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.3: repetir el primer archivo con los partidos ya existentes
-- Resultado esperado: 9001 y 9002 ya existen, así que no se insertan. 9002 vuelve a las 18:00
-- (1 actualizado); 9001 queda sin cambios porque el archivo no trae resultado y se conserva
-- el 3-2 (junto con el partido 14, 2 sin cambios). Las demás filas dan los mismos 11 errores,
-- y en Sistema.ErrorImportacion siguen quedando 11 filas de ese archivo (no se acumulan).
BEGIN TRY
    DELETE FROM #r;
    INSERT INTO #r EXEC Torneo.Importar_FixtureCSV @rutaArchivo = N'$(RUTA_DATASETS)prueba_fixture_1.csv';
    SELECT 'DESPUES 2.3' AS momento, * FROM #r;
    IF EXISTS (SELECT 1 FROM #r WHERE filasLeidas = 14 AND insertados = 0 AND actualizados = 1
               AND sinCambios = 2 AND conError = 11)
       AND (SELECT COUNT(*) FROM Torneo.Partido WHERE nroPartidoOficial IN (9001, 9002)) = 2
       AND EXISTS (SELECT 1 FROM Torneo.Partido WHERE nroPartidoOficial = 9001 AND golLocal = 3 AND golVisitante = 2)
       AND (SELECT COUNT(*) FROM Sistema.ErrorImportacion
            WHERE archivo LIKE N'%prueba_fixture_1.csv' AND tablaDestino = 'Torneo.Partido') = 11
        PRINT '[OK] PRUEBA 2.3: reimportar no duplica ni los partidos ni los errores registrados.';
    ELSE PRINT '[FALLO] PRUEBA 2.3: el resultado de la importación no es el esperado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.3: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   3. Errores que cortan la importación (THROW)
   ============================================================================= */
PRINT '--- 3. Errores de archivo y de parámetro ---';

-- PRUEBA 3.1: archivo inexistente
-- Resultado esperado: error 50003 "No se pudo leer el archivo ..."; no se importa nada.
BEGIN TRY
    DECLARE @antes4 int = (SELECT COUNT(*) FROM Torneo.Partido);
    EXEC Torneo.Importar_FixtureCSV @rutaArchivo = N'$(RUTA_DATASETS)no_existe.csv';
    PRINT '[FALLO] PRUEBA 3.1: se aceptó un archivo inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50003 AND ERROR_MESSAGE() LIKE N'No se pudo leer el archivo%'
       AND (SELECT COUNT(*) FROM Torneo.Partido) = @antes4
        PRINT '[OK] PRUEBA 3.1: archivo inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 3.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.2: archivo con otro encabezado
-- Resultado esperado: error 50003 "no tiene el encabezado esperado".
BEGIN TRY
    EXEC Torneo.Importar_FixtureCSV @rutaArchivo = N'$(RUTA_DATASETS)prueba_fixture_encabezado.csv';
    PRINT '[FALLO] PRUEBA 3.2: se aceptó un archivo con otro encabezado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50003 AND ERROR_MESSAGE() LIKE N'%no tiene el encabezado esperado%'
        PRINT '[OK] PRUEBA 3.2: encabezado inválido rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 3.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.3: archivo con otra cantidad de columnas (3 en vez de 8)
-- Resultado esperado: error 50003 "No se pudo leer el archivo ..."; no se importa nada.
BEGIN TRY
    EXEC Torneo.Importar_FixtureCSV @rutaArchivo = N'$(RUTA_DATASETS)prueba_fixture_columnas.csv';
    PRINT '[FALLO] PRUEBA 3.3: se aceptó un archivo con otra estructura.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50003 AND ERROR_MESSAGE() LIKE N'No se pudo leer el archivo%'
        PRINT '[OK] PRUEBA 3.3: archivo con otra estructura rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 3.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.4: nombre de archivo vacío
-- Resultado esperado: error 50001 "El nombre del archivo es obligatorio."
BEGIN TRY
    EXEC Torneo.Importar_FixtureCSV @rutaArchivo = N'   ';
    PRINT '[FALLO] PRUEBA 3.4: se aceptó un nombre vacío.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%nombre del archivo es obligatorio%'
        PRINT '[OK] PRUEBA 3.4: nombre vacío rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 3.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.5: archivo que no es .csv
-- Resultado esperado: error 50001 "El archivo debe ser un .csv."
BEGIN TRY
    EXEC Torneo.Importar_FixtureCSV @rutaArchivo = N'$(RUTA_DATASETS)prueba_fixture_1.txt';
    PRINT '[FALLO] PRUEBA 3.5: se aceptó una extensión distinta.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%debe ser un .csv%'
        PRINT '[OK] PRUEBA 3.5: extensión inválida rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 3.5: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   4. El archivo real, tal cual se descargó
   ============================================================================= */
PRINT '--- 4. Archivo real ---';

-- PRUEBA 4.1: fifa-world-cup-2026-UTC.csv (104 partidos)
-- Resultado esperado: 104 filas leídas. Con la carga base de 16 selecciones, los 31 partidos
-- entre ellas coinciden con el archivo (sin cambios) y el resto va a ErrorImportacion porque
-- sus selecciones no están cargadas. Sin altas, sin modificaciones y sin cambiar los 31 partidos.
BEGIN TRY
    DECLARE @chk1 int = (SELECT CHECKSUM_AGG(CHECKSUM(nroPartidoOficial, idSede, idSeleccionLocal,
                         idSeleccionVisitante, fase, fechaHoraUTC, estado, golLocal, golVisitante, cantPublico))
                         FROM Torneo.Partido WHERE nroPartidoOficial < 9000);
    DELETE FROM #r;
    INSERT INTO #r EXEC Torneo.Importar_FixtureCSV @rutaArchivo = N'$(RUTA_DATASETS)fifa-world-cup-2026-UTC.csv';
    SELECT 'DESPUES 4.1' AS momento, * FROM #r;
    IF EXISTS (SELECT 1 FROM #r WHERE filasLeidas = 104 AND insertados = 0 AND actualizados = 0
               AND sinCambios + conError = 104 AND sinCambios >= 1)
       AND @chk1 = (SELECT CHECKSUM_AGG(CHECKSUM(nroPartidoOficial, idSede, idSeleccionLocal,
                    idSeleccionVisitante, fase, fechaHoraUTC, estado, golLocal, golVisitante, cantPublico))
                    FROM Torneo.Partido WHERE nroPartidoOficial < 9000)
        PRINT '[OK] PRUEBA 4.1: el archivo real se importó sin alterar los partidos cargados.';
    ELSE PRINT '[FALLO] PRUEBA 4.1: el resultado de la importación no es el esperado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 4.1: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   LIMPIEZA FINAL
   ============================================================================= */
DROP TABLE IF EXISTS #r;
DELETE FROM Sistema.ErrorImportacion WHERE archivo LIKE N'%prueba_fixture%' OR archivo LIKE N'%fifa-world-cup-2026-UTC.csv';
DELETE FROM Torneo.Partido WHERE nroPartidoOficial IN (9001, 9002);

PRINT '================================================================================';
PRINT ' FIN DE LAS PRUEBAS: 40a_Importar_FixtureCSV.sql (13 pruebas)';
PRINT '================================================================================';
GO
