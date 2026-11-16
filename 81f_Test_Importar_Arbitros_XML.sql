/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel - 45066788
               Salas, Martín Daniel - 45205702
               Zito Padró, Ezequiel Nehuén - 46097917
 Fecha       : 15/11/2026

 Objetivo    : Suite de pruebas unitarias para 41_Importar_Arbitros_XML.sql.
               Cubre Arbitraje.Importar_ArbitrosXML:
               - Importación del dataset real (datasets/arbitros_fifa_reducido.xml,
                 500 filas): contadores, árbitros e idiomas cargados y errores de
                 fila registrados en Sistema.ErrorImportacion.
               - Reimportación del mismo archivo (upsert, sin duplicados).
               - Una fila con país inexistente es un error de fila y no corta la
                 importación (las demás entran).
               - Errores de ruta / lectura / transacción abierta (THROW 50003), una
                 prueba por mensaje, y una acumulación (transacción + ruta nula).
               - Arbitraje.Importar_ArbitrosXMLDatos con un XML literal (sin
                 archivo): estructura inesperada, importación parcial (fila válida
                 + filas inválidas), errores propios del archivo acumulados y error
                 de un SP de ABM (categoría inválida).

 Estándares aplicados:
 - Relación 1:1 con 41_Importar_Arbitros_XML.sql.
 - No se crean archivos de prueba: se usa el dataset real y, para "existe pero
   no es XML", el script docs/scrap_fifa_arbitros.py.
 - Una prueba negativa por cada mensaje de validación del 41 (mapa mensaje ->
   prueba en el resumen final).
 - Los XML literales usan el país Argentina (ISO3 ARG) y nombres claramente de
   prueba ('Test81f'): lo que insertan lo borra la limpieza final.
 - Supuesto: se corre sobre la base recién cargada (00, 11a, 41, 50a y 51a),
   sin que el dataset se haya importado antes. Si ya estaba importado, la
   PRUEBA 2 lo informa como [FALLO] (no se borra nada previo: recrear la base).
 - Idempotencia: saca una foto de los árbitros, idiomas y errores de importación
   preexistentes (los de 51a), al final borra solo lo que creó este test
   (árbitros nuevos respecto de la foto vía Arbitro_Baja, que borra sus
   idiomas, y las filas de Sistema.ErrorImportacion con id mayor al máximo
   previo) y verifica que la base quedó igual que al inicio, lista para que la
   importación real vuelva a insertar los mismos árbitros.
 - Sin SQL dinámico.

 Requisitos  : - Ejecutar en modo SQLCMD (en SSMS: Consulta > Modo SQLCMD),
                 porque usa la variable RUTA_REPO.
               - Cambiar RUTA_REPO (la línea :setvar de más abajo, por defecto
                 C:\TP-BBDDA\) por la raíz de la repo en esta máquina, terminada
                 en \ y legible por la cuenta que ejecuta SQL Server: de ahí se
                 leen datasets\arbitros_fifa_reducido.xml y
                 docs\scrap_fifa_arbitros.py. Si la ruta no coincide, las
                 pruebas de importación fallan. Se cambia editando esa línea,
                 tanto en SSMS como con sqlcmd: el :setvar del archivo pisa a la
                 opción -v de sqlcmd (igual que RUTA_DATASETS en 80g).
               - 00_InitialSchema.sql, 11a, 41, 50a y 51a.
================================================================================
*/

:setvar RUTA_REPO "C:\TP-BBDDA\"

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

PRINT '================================================================================';
PRINT ' INICIANDO BATERÍA DE PRUEBAS: 41_Importar_Arbitros_XML.sql';
PRINT '================================================================================';
GO

/* =============================================================================
   PREPARACIÓN DEL ENTORNO DE PRUEBAS (FOTO INICIAL)
   No hay limpieza previa: el test no borra nada que exista antes de correr.
   ============================================================================= */
PRINT '--- Foto inicial ---';

-- Rutas de los archivos: salen de RUTA_REPO (:setvar del inicio del archivo).
-- SQL Server lee los archivos desde su propio equipo.
IF OBJECT_ID('tempdb..#cfg') IS NOT NULL DROP TABLE #cfg;
CREATE TABLE #cfg (rutaXml nvarchar(260) NOT NULL, rutaPy nvarchar(260) NOT NULL);
INSERT INTO #cfg (rutaXml, rutaPy)
VALUES (N'$(RUTA_REPO)datasets\arbitros_fifa_reducido.xml', N'$(RUTA_REPO)docs\scrap_fifa_arbitros.py');

-- FOTO INICIAL: lo preexistente (países de 50a, árbitros de 51a) que el test
-- no debe modificar.
IF OBJECT_ID('tempdb..#arbPre') IS NOT NULL DROP TABLE #arbPre;
CREATE TABLE #arbPre (idArbitro int PRIMARY KEY);
INSERT INTO #arbPre (idArbitro) SELECT idArbitro FROM Arbitraje.Arbitro;

IF OBJECT_ID('tempdb..#foto') IS NOT NULL DROP TABLE #foto;
SELECT (SELECT COUNT(*) FROM Torneo.Pais)                                  AS cantPais,
       (SELECT COUNT(*) FROM Arbitraje.Arbitro)                            AS cantArbitro,
       (SELECT COUNT(*) FROM Arbitraje.ArbitroIdioma)                      AS cantIdioma,
       (SELECT COUNT(*) FROM Sistema.ErrorImportacion)                     AS cantError,
       (SELECT ISNULL(MAX(id), 0) FROM Sistema.ErrorImportacion)           AS maxIdError,
       (SELECT ISNULL(CHECKSUM_AGG(CHECKSUM(idArbitro, idPais, nombre, apellido, categoria, genero, fechaInternacional)), 0)
          FROM Arbitraje.Arbitro)                                          AS chkArbitro,
       (SELECT ISNULL(CHECKSUM_AGG(CHECKSUM(idArbitro, idioma)), 0)
          FROM Arbitraje.ArbitroIdioma)                                    AS chkIdioma
INTO #foto;

SELECT 'FOTO INICIAL' AS momento, * FROM #foto;

PRINT 'Fixture de pruebas inicializado con éxito.';
PRINT '';
GO

/* =============================================================================
   SECCIÓN 1: Arbitraje.Importar_ArbitrosXML con el dataset real
   (sin GO entre pruebas: comparten ruta, foto y resultados de la importación)
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 1. PRUEBAS: importación del dataset real (importación, reimportación, errores)';
PRINT '--------------------------------------------------------------------------------';

DECLARE @rutaXml nvarchar(260) = (SELECT rutaXml FROM #cfg);
DECLARE @maxIdAntes int = (SELECT maxIdError FROM #foto);
DECLARE @arbAntes int, @idiAntes int;
DECLARE @cantFilas int, @cantInsertados int, @cantActualizados int, @cantErrores int;
DECLARE @cantFilas2 int, @cantInsertados2 int, @cantActualizados2 int, @cantErrores2 int;
DECLARE @arbNuevos int, @idiNuevos int, @erroresNuevos int, @erroresMalFormados int;
DECLARE @maxIdImp1 int, @idError int, @paisError nvarchar(200), @cantPaisFaltante int, @cantPais int = (SELECT cantPais FROM #foto);

-- PRUEBA 1: Precondición: los países de 50a están cargados
-- Resultado esperado: Torneo.Pais tiene filas (sin países toda fila fallaría).
IF @cantPais > 0
    PRINT '[OK] PRUEBA 1: Precondición cumplida: Torneo.Pais tiene ' + CAST(@cantPais AS varchar(10)) + ' países.';
ELSE PRINT '[FALLO] PRUEBA 1: Torneo.Pais está vacía; ejecutar 50a antes de este test.';

-- PRUEBA 2: Importación del dataset real (500 filas)
-- Resultado esperado: cantFilas = 500; insertados + actualizados + errores = cantFilas;
--   insertados > 0 y errores > 0 (los países que no están en Torneo.Pais fallan sin
--   cortar la importación); Arbitro aumenta en la cantidad de insertados y los
--   árbitros nuevos tienen idiomas. Los números exactos dependen de la carga de 50a.
SET @arbAntes = (SELECT COUNT(*) FROM Arbitraje.Arbitro);
SET @idiAntes = (SELECT COUNT(*) FROM Arbitraje.ArbitroIdioma);
BEGIN TRY
    EXEC Arbitraje.Importar_ArbitrosXML @rutaArchivo = @rutaXml,
         @cantFilas = @cantFilas OUTPUT, @cantInsertados = @cantInsertados OUTPUT,
         @cantActualizados = @cantActualizados OUTPUT, @cantErrores = @cantErrores OUTPUT;

    SET @arbNuevos = (SELECT COUNT(*) FROM Arbitraje.Arbitro) - @arbAntes;
    SET @idiNuevos = (SELECT COUNT(*) FROM Arbitraje.ArbitroIdioma) - @idiAntes;

    PRINT '  Se insertaron ' + CAST(@cantInsertados AS varchar(10)) + ' árbitros correctos y fallaron '
        + CAST(@cantErrores AS varchar(10)) + ' (actualizados: ' + CAST(@cantActualizados AS varchar(10))
        + ', filas del archivo: ' + CAST(@cantFilas AS varchar(10)) + ').';
    SELECT 'IMPORTACION 1' AS momento, @cantFilas AS cantFilas, @cantInsertados AS cantInsertados,
           @cantActualizados AS cantActualizados, @cantErrores AS cantErrores,
           @arbNuevos AS arbitrosNuevos, @idiNuevos AS idiomasNuevos;

    IF @cantInsertados = 0
        PRINT '[FALLO] PRUEBA 2: La base ya tenía importado el dataset: recrear la base antes de correr este test.';
    ELSE IF @cantFilas = 500
       AND @cantInsertados + @cantActualizados + @cantErrores = @cantFilas
       AND @cantInsertados > 0 AND @cantErrores > 0
       AND @arbNuevos = @cantInsertados
       AND @idiNuevos > 0
        PRINT '[OK] PRUEBA 2: 500 filas procesadas; insertados > 0, errores > 0 (contadores consistentes) y árbitros nuevos con idiomas.';
    ELSE PRINT '[FALLO] PRUEBA 2: Contadores o altas inconsistentes con lo esperado (ver IMPORTACION 1).';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3: Los errores de fila quedan registrados con trazabilidad
-- Resultado esperado: una fila de Sistema.ErrorImportacion por fila fallida
--   (= cantErrores), cada una con archivo, tablaDestino = 'Arbitraje.Arbitro',
--   nroFila y datoOriginal no nulos. Se muestran las causas agrupadas.
SET @erroresNuevos = (SELECT COUNT(*) FROM Sistema.ErrorImportacion WHERE id > @maxIdAntes);
SET @erroresMalFormados = (SELECT COUNT(*) FROM Sistema.ErrorImportacion
                           WHERE id > @maxIdAntes
                             AND (archivo <> @rutaXml OR tablaDestino <> 'Arbitraje.Arbitro'
                                  OR nroFila IS NULL OR datoOriginal IS NULL));

SELECT REPLACE(mensajeError, CHAR(10), N' ') AS mensajeError, COUNT(*) AS cantidad
FROM Sistema.ErrorImportacion
WHERE id > @maxIdAntes
GROUP BY REPLACE(mensajeError, CHAR(10), N' ')
ORDER BY 2 DESC;

IF @erroresNuevos = @cantErrores AND @erroresNuevos > 0 AND @erroresMalFormados = 0
    PRINT '[OK] PRUEBA 3: ' + CAST(@erroresNuevos AS varchar(10)) + ' errores registrados, todos con archivo, tabla destino, fila y dato original.';
ELSE PRINT '[FALLO] PRUEBA 3: Errores registrados = ' + ISNULL(CAST(@erroresNuevos AS varchar(10)), 'NULL')
         + ' (esperado ' + ISNULL(CAST(@cantErrores AS varchar(10)), 'NULL') + '), mal formados = '
         + ISNULL(CAST(@erroresMalFormados AS varchar(10)), 'NULL') + '.';

SET @maxIdImp1 = (SELECT ISNULL(MAX(id), 0) FROM Sistema.ErrorImportacion);   -- último error de la 1ª importación

-- PRUEBA 4: Reimportación del mismo archivo (upsert)
-- Resultado esperado: 0 insertados; actualizados = insertados + actualizados de la
--   corrida 1 (los árbitros ya cargados se modifican); los mismos errores; y los
--   conteos de Arbitro y ArbitroIdioma no cambian (sin duplicados).
SET @arbAntes = (SELECT COUNT(*) FROM Arbitraje.Arbitro);
SET @idiAntes = (SELECT COUNT(*) FROM Arbitraje.ArbitroIdioma);
BEGIN TRY
    EXEC Arbitraje.Importar_ArbitrosXML @rutaArchivo = @rutaXml,
         @cantFilas = @cantFilas2 OUTPUT, @cantInsertados = @cantInsertados2 OUTPUT,
         @cantActualizados = @cantActualizados2 OUTPUT, @cantErrores = @cantErrores2 OUTPUT;

    SELECT 'REIMPORTACION' AS momento, @cantFilas2 AS cantFilas, @cantInsertados2 AS cantInsertados,
           @cantActualizados2 AS cantActualizados, @cantErrores2 AS cantErrores,
           (SELECT COUNT(*) FROM Arbitraje.Arbitro) - @arbAntes AS variacionArbitros,
           (SELECT COUNT(*) FROM Arbitraje.ArbitroIdioma) - @idiAntes AS variacionIdiomas;

    IF @cantInsertados2 = 0
       AND @cantActualizados2 = @cantInsertados + @cantActualizados
       AND @cantErrores2 = @cantErrores
       AND (SELECT COUNT(*) FROM Arbitraje.Arbitro) = @arbAntes
       AND (SELECT COUNT(*) FROM Arbitraje.ArbitroIdioma) = @idiAntes
        PRINT '[OK] PRUEBA 4: Reimportación sin altas, ' + CAST(@cantActualizados2 AS varchar(10)) + ' actualizados y sin duplicados de árbitros ni idiomas.';
    ELSE PRINT '[FALLO] PRUEBA 4: La reimportación insertó, duplicó o cambió los contadores (ver REIMPORTACION).';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 5: Una fila con país inexistente es un error de fila y no corta el proceso
--   (se miran solo los errores de la 1ª importación: id entre @maxIdAntes y @maxIdImp1)
-- Resultado esperado: hay filas de ErrorImportacion con "El país especificado no
--   existe." y todas son de países que realmente no están en Torneo.Pais (por
--   ISO3 o, si viene vacío, por nombre); y Abigail BYRNE (Inglaterra, ISO3 vacío:
--   se resuelve por nombre) figura insertada en Arbitro aunque haya filas
--   inválidas antes y después en el archivo.
SELECT TOP (1) @idError = e.id,
       @paisError = CAST(e.datoOriginal AS xml).value('(/Arbitro/Pais)[1]', 'nvarchar(200)')
FROM Sistema.ErrorImportacion AS e
WHERE e.id > @maxIdAntes AND e.id <= @maxIdImp1 AND e.mensajeError LIKE N'%- El país especificado no existe.%'
ORDER BY e.id;

SET @cantPaisFaltante = (
    SELECT COUNT(*)
    FROM Sistema.ErrorImportacion AS e
    CROSS APPLY (SELECT CAST(e.datoOriginal AS xml) AS x) AS d
    WHERE e.id > @maxIdAntes AND e.id <= @maxIdImp1 AND e.mensajeError LIKE N'%- El país especificado no existe.%'
      AND NOT EXISTS (SELECT 1 FROM Torneo.Pais AS p
                      WHERE (ISNULL(d.x.value('(/Arbitro/Pais/@codigoISO3)[1]', 'nvarchar(20)'), N'') <> N''
                             AND p.codigoISO3 = d.x.value('(/Arbitro/Pais/@codigoISO3)[1]', 'nvarchar(20)'))
                         OR (ISNULL(d.x.value('(/Arbitro/Pais/@codigoISO3)[1]', 'nvarchar(20)'), N'') = N''
                             AND p.nombre = d.x.value('(/Arbitro/Pais)[1]', 'nvarchar(200)'))));

SELECT 'PAIS INEXISTENTE' AS momento, @idError AS idError, @paisError AS paisNoCargado,
       (SELECT COUNT(*) FROM Sistema.ErrorImportacion
        WHERE id > @maxIdAntes AND id <= @maxIdImp1 AND mensajeError LIKE N'%- El país especificado no existe.%') AS filasConEseError;
SELECT 'INGLATERRA' AS momento, a.idArbitro, a.nombre, a.apellido, p.nombre AS pais
FROM Arbitraje.Arbitro AS a JOIN Torneo.Pais AS p ON p.id = a.idPais
WHERE a.nombre = N'Abigail' AND a.apellido = N'BYRNE';

IF @idError IS NOT NULL AND @cantPaisFaltante = (SELECT COUNT(*) FROM Sistema.ErrorImportacion
                                                 WHERE id > @maxIdAntes AND id <= @maxIdImp1 AND mensajeError LIKE N'%- El país especificado no existe.%')
   AND EXISTS (SELECT 1 FROM Arbitraje.Arbitro AS a JOIN Torneo.Pais AS p ON p.id = a.idPais
               WHERE a.nombre = N'Abigail' AND a.apellido = N'BYRNE' AND p.nombre = N'Inglaterra')
    PRINT '[OK] PRUEBA 5: País inexistente (' + @paisError + ') informado como error de fila; Inglaterra (ISO3 vacío) se resolvió por nombre y se insertó.';
ELSE PRINT '[FALLO] PRUEBA 5: No hay error por país inexistente coherente o falta el árbitro de Inglaterra.';
GO

/* =============================================================================
   SECCIÓN 2: Errores de ruta y lectura (THROW 50003)
   El SP público valida la transacción abierta y la ruta de forma acumulativa
   (la ruta usa ELSE IF: un valor da un solo mensaje de ruta).
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 2. PRUEBAS: Arbitraje.Importar_ArbitrosXML - errores de ruta y de lectura';
PRINT '--------------------------------------------------------------------------------';

DECLARE @dirRuta nvarchar(260) = (SELECT LEFT(rutaXml, LEN(rutaXml) - LEN(N'arbitros_fifa_reducido.xml')) FROM #cfg);
DECLARE @rutaPy nvarchar(260) = (SELECT rutaPy FROM #cfg);
DECLARE @ruta nvarchar(260);
DECLARE @rutaXml nvarchar(260) = (SELECT rutaXml FROM #cfg);

-- PRUEBA 6: Ruta nula
-- Resultado esperado: THROW 50003 "- La ruta del archivo es obligatoria."
BEGIN TRY
    EXEC Arbitraje.Importar_ArbitrosXML @rutaArchivo = NULL;
    PRINT '[FALLO] PRUEBA 6: No detectó la ruta nula.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50003 AND ERROR_MESSAGE() LIKE N'%- La ruta del archivo es obligatoria.%'
        PRINT '[OK] PRUEBA 6: Ruta nula rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 6: ' + CAST(ERROR_NUMBER() AS varchar(10)) + ' - ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 7: Ruta con caracteres inválidos
-- Resultado esperado: THROW 50003 "- La ruta del archivo contiene caracteres inválidos"
SET @ruta = @dirRuta + N'datos*.xml';
BEGIN TRY
    EXEC Arbitraje.Importar_ArbitrosXML @rutaArchivo = @ruta;
    PRINT '[FALLO] PRUEBA 7: No detectó los caracteres inválidos.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50003 AND ERROR_MESSAGE() LIKE N'%- La ruta del archivo contiene caracteres inválidos%'
        PRINT '[OK] PRUEBA 7: Ruta con caracteres inválidos rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 7: ' + CAST(ERROR_NUMBER() AS varchar(10)) + ' - ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 8: Archivo inexistente
-- Resultado esperado: THROW 50003 "No se pudo leer el archivo XML de árbitros ..."
SET @ruta = @dirRuta + N'no_existe_arbitros.xml';
BEGIN TRY
    EXEC Arbitraje.Importar_ArbitrosXML @rutaArchivo = @ruta;
    PRINT '[FALLO] PRUEBA 8: No detectó el archivo inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50003 AND ERROR_MESSAGE() LIKE N'No se pudo leer el archivo XML de árbitros%'
        PRINT '[OK] PRUEBA 8: Archivo inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 8: ' + CAST(ERROR_NUMBER() AS varchar(10)) + ' - ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 9: Archivo que existe pero no es XML (docs/scrap_fifa_arbitros.py)
-- Resultado esperado: THROW 50003 con mensaje no vacío. Cae en "No se pudo leer el
--   archivo XML ..." (el contenido no se puede convertir a xml); "Estructura
--   inesperada" también sería 50003 (se prueba aparte con un XML literal).
BEGIN TRY
    EXEC Arbitraje.Importar_ArbitrosXML @rutaArchivo = @rutaPy;
    PRINT '[FALLO] PRUEBA 9: Aceptó un archivo que no es XML.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50003 AND ISNULL(ERROR_MESSAGE(), N'') <> N''
        PRINT '[OK] PRUEBA 9: Archivo no XML rechazado con 50003 (' + LEFT(ERROR_MESSAGE(), 60) + '...).';
    ELSE PRINT '[FALLO] PRUEBA 9: ' + CAST(ERROR_NUMBER() AS varchar(10)) + ' - ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 10: Importación dentro de una transacción abierta (ruta válida)
-- Resultado esperado: THROW 50003 "- El proceso de importación no puede ejecutarse
--   dentro de una transacción abierta ..." y la transacción externa sigue abierta
--   (@@TRANCOUNT = 1, no se revierte); se cierra con ROLLBACK al terminar.
BEGIN TRY
    BEGIN TRANSACTION;
    EXEC Arbitraje.Importar_ArbitrosXML @rutaArchivo = @rutaXml;
    PRINT '[FALLO] PRUEBA 10: Permitió importar dentro de una transacción abierta.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50003
       AND ERROR_MESSAGE() LIKE N'%- El proceso de importación no puede ejecutarse dentro de una transacción abierta%'
       AND @@TRANCOUNT = 1
        PRINT '[OK] PRUEBA 10: Transacción abierta rechazada y la transacción externa sigue intacta (@@TRANCOUNT = 1).';
    ELSE PRINT '[FALLO] PRUEBA 10: ' + CAST(ERROR_NUMBER() AS varchar(10)) + ' - ' + ERROR_MESSAGE() + ' (@@TRANCOUNT = ' + CAST(@@TRANCOUNT AS varchar(10)) + ')';
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

-- PRUEBA 11: Acumulación: transacción abierta + ruta nula
-- Resultado esperado: THROW 50003 con los dos mensajes juntos ("- El proceso de
--   importación no puede ejecutarse dentro de una transacción abierta" y
--   "- La ruta del archivo es obligatoria.").
BEGIN TRY
    BEGIN TRANSACTION;
    EXEC Arbitraje.Importar_ArbitrosXML @rutaArchivo = NULL;
    PRINT '[FALLO] PRUEBA 11: No detectó los errores acumulados.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50003
       AND ERROR_MESSAGE() LIKE N'%- El proceso de importación no puede ejecutarse dentro de una transacción abierta%'
       AND ERROR_MESSAGE() LIKE N'%- La ruta del archivo es obligatoria.%'
        PRINT '[OK] PRUEBA 11: Transacción abierta y ruta nula informadas juntas.';
    ELSE PRINT '[FALLO] PRUEBA 11: ' + CAST(ERROR_NUMBER() AS varchar(10)) + ' - ' + ERROR_MESSAGE();
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO

/* =============================================================================
   SECCIÓN 3: Arbitraje.Importar_ArbitrosXMLDatos con un XML literal (sin archivo)
   Un único XML con 3 filas de Argentina (ISO3 ARG):
     1. válida (Test81f VALIDO81F, con 2 idiomas);
     2. con errores propios del archivo acumulados: fecha inválida, nombre y
        apellido de más de 60 caracteres, género de más de 20 y categoría de más
        de 15;
     3. con categoría 'XXX' (la rechaza el ABM Arbitro_Alta).
   La fila 1 entra (importación parcial) y las 2 y 3 quedan en ErrorImportacion.
   Lo creado lo borra la limpieza final (árbitro nuevo / id de error nuevo).
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 3. PRUEBAS: Arbitraje.Importar_ArbitrosXMLDatos (XML literal)';
PRINT '--------------------------------------------------------------------------------';

DECLARE @origen nvarchar(260) = N'81f_xml_literal';
DECLARE @maxIdAntes int = (SELECT maxIdError FROM #foto);
DECLARE @xmlTexto nvarchar(max), @xmlLit xml, @xmlSinNodos xml = N'<Otro/>';
DECLARE @cantFilas int, @cantInsertados int, @cantActualizados int, @cantErrores int;

SET @xmlTexto = N'<Arbitros>'
  + N'<Arbitro><Nombre>Test81f</Nombre><Apellido>VALIDO81F</Apellido><Pais codigoISO3="ARG">Argentina</Pais>'
  +   N'<Categoria>FIFA</Categoria><Genero>Masculino</Genero><FechaInternacional>2020-01-01</FechaInternacional>'
  +   N'<Idiomas><Idioma>es</Idioma><Idioma>en</Idioma></Idiomas></Arbitro>'
  + N'<Arbitro><Nombre>' + REPLICATE(N'N', 61) + N'</Nombre><Apellido>' + REPLICATE(N'A', 61) + N'</Apellido>'
  +   N'<Pais codigoISO3="ARG">Argentina</Pais><Categoria>CategoriaMuyLarga</Categoria>'
  +   N'<Genero>' + REPLICATE(N'G', 21) + N'</Genero><FechaInternacional>2025-13-45</FechaInternacional></Arbitro>'
  + N'<Arbitro><Nombre>Test81f</Nombre><Apellido>CATEGORIAXXX</Apellido><Pais codigoISO3="ARG">Argentina</Pais>'
  +   N'<Categoria>XXX</Categoria><Genero>Masculino</Genero><FechaInternacional>2020-01-01</FechaInternacional></Arbitro>'
  + N'</Arbitros>';
SET @xmlLit = CAST(@xmlTexto AS xml);

-- PRUEBA 12: El SP interno también rechaza una transacción abierta
-- Resultado esperado: THROW 50003 "- El proceso de importación no puede ejecutarse
--   dentro de una transacción abierta ..." y @@TRANCOUNT = 1 (la externa no se revierte).
BEGIN TRY
    BEGIN TRANSACTION;
    EXEC Arbitraje.Importar_ArbitrosXMLDatos @xml = @xmlLit, @origen = @origen;
    PRINT '[FALLO] PRUEBA 12: Permitió importar dentro de una transacción abierta.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50003
       AND ERROR_MESSAGE() LIKE N'%- El proceso de importación no puede ejecutarse dentro de una transacción abierta%'
       AND @@TRANCOUNT = 1
        PRINT '[OK] PRUEBA 12: Transacción abierta rechazada por el SP interno (@@TRANCOUNT = 1).';
    ELSE PRINT '[FALLO] PRUEBA 12: ' + CAST(ERROR_NUMBER() AS varchar(10)) + ' - ' + ERROR_MESSAGE();
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

-- PRUEBA 13: XML válido sin nodos /Arbitros/Arbitro
-- Resultado esperado: THROW 50003 "Estructura inesperada: el archivo no contiene nodos
--   /Arbitros/Arbitro."
BEGIN TRY
    EXEC Arbitraje.Importar_ArbitrosXMLDatos @xml = @xmlSinNodos, @origen = @origen;
    PRINT '[FALLO] PRUEBA 13: Aceptó un XML sin nodos /Arbitros/Arbitro.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50003 AND ERROR_MESSAGE() LIKE N'Estructura inesperada:%/Arbitros/Arbitro%'
        PRINT '[OK] PRUEBA 13: XML sin nodos /Arbitros/Arbitro rechazado (Estructura inesperada).';
    ELSE PRINT '[FALLO] PRUEBA 13: ' + CAST(ERROR_NUMBER() AS varchar(10)) + ' - ' + ERROR_MESSAGE();
END CATCH;

-- Importación del XML literal (una sola vez para las pruebas 14 y 15)
BEGIN TRY
    EXEC Arbitraje.Importar_ArbitrosXMLDatos @xml = @xmlLit, @origen = @origen,
         @cantFilas = @cantFilas OUTPUT, @cantInsertados = @cantInsertados OUTPUT,
         @cantActualizados = @cantActualizados OUTPUT, @cantErrores = @cantErrores OUTPUT;
END TRY
BEGIN CATCH
    PRINT '  La importación del XML literal falló: ' + ERROR_MESSAGE();
END CATCH;

SELECT 'XML LITERAL' AS momento, @cantFilas AS cantFilas, @cantInsertados AS cantInsertados,
       @cantActualizados AS cantActualizados, @cantErrores AS cantErrores;
SELECT 'ERRORES XML LITERAL' AS momento, nroFila, archivo, tablaDestino, REPLACE(mensajeError, CHAR(10), N' ') AS mensajeError
FROM Sistema.ErrorImportacion WHERE id > @maxIdAntes AND archivo = @origen ORDER BY nroFila;
SELECT 'ARBITRO VALIDO' AS momento, a.idArbitro, a.nombre, a.apellido,
       (SELECT COUNT(*) FROM Arbitraje.ArbitroIdioma i WHERE i.idArbitro = a.idArbitro) AS idiomas
FROM Arbitraje.Arbitro AS a WHERE a.nombre = N'Test81f' AND a.apellido = N'VALIDO81F';

-- PRUEBA 14: Importación parcial con una fila de errores propios acumulados
-- Resultado esperado: cantFilas = 3, cantInsertados = 1 (la fila válida entró con sus
--   2 idiomas) y cantErrores = 2; la fila 2 quedó en ErrorImportacion (nroFila = 2,
--   datoOriginal no nulo) con "Datos inválidos en el archivo:" y los 5 textos: fecha
--   inválida, nombre y apellido > 60, género > 20 y categoría > 15.
IF @cantFilas = 3 AND @cantInsertados = 1 AND @cantActualizados = 0 AND @cantErrores = 2
   AND (SELECT COUNT(*) FROM Arbitraje.ArbitroIdioma AS i JOIN Arbitraje.Arbitro AS a ON a.idArbitro = i.idArbitro
        WHERE a.nombre = N'Test81f' AND a.apellido = N'VALIDO81F') = 2
   AND EXISTS (SELECT 1 FROM Sistema.ErrorImportacion
               WHERE id > @maxIdAntes AND archivo = @origen AND nroFila = 2 AND datoOriginal IS NOT NULL
                 AND tablaDestino = 'Arbitraje.Arbitro'
                 AND mensajeError LIKE N'%Datos inválidos en el archivo:%'
                 AND mensajeError LIKE N'%- La fecha internacional ''2025-13-45'' no es una fecha válida%'
                 AND mensajeError LIKE N'%- El nombre supera los 60 caracteres.%'
                 AND mensajeError LIKE N'%- El apellido supera los 60 caracteres.%'
                 AND mensajeError LIKE N'%- El género supera los 20 caracteres.%'
                 AND mensajeError LIKE N'%- La categoría supera los 15 caracteres.%')
    PRINT '[OK] PRUEBA 14: Fila válida insertada con idiomas y fila 2 registrada con los 5 errores propios acumulados.';
ELSE PRINT '[FALLO] PRUEBA 14: Importación parcial o errores propios distintos de lo esperado (ver XML LITERAL y ERRORES XML LITERAL).';

-- PRUEBA 15: Fila con un campo roto que detecta el ABM (categoría 'XXX')
-- Resultado esperado: la fila 3 queda registrada en ErrorImportacion (nroFila = 3,
--   datoOriginal no nulo) con "- La categoría debe ser 'FIFA' o 'Confederacion'." y
--   no se creó ningún árbitro con ese apellido; la importación no se cortó (la fila
--   válida de la prueba 14 sí entró).
IF EXISTS (SELECT 1 FROM Sistema.ErrorImportacion
           WHERE id > @maxIdAntes AND archivo = @origen AND nroFila = 3 AND datoOriginal IS NOT NULL
             AND mensajeError LIKE N'%- La categoría debe ser ''FIFA'' o ''Confederacion''.%')
   AND NOT EXISTS (SELECT 1 FROM Arbitraje.Arbitro WHERE apellido = N'CATEGORIAXXX')
   AND @cantInsertados = 1
    PRINT '[OK] PRUEBA 15: Categoría inválida rechazada por el ABM, registrada como error de fila sin cortar la importación.';
ELSE PRINT '[FALLO] PRUEBA 15: La fila con categoría XXX no quedó registrada como error esperado.';
GO

/* =============================================================================
   SECCIÓN 4: LIMPIEZA FINAL Y VERIFICACIÓN DE LA BASE
   Se borra solo lo que creó el test (árbitros nuevos con Arbitro_Baja, que borra
   sus idiomas, y las filas nuevas de ErrorImportacion) para dejar la base lista
   para la importación real.
   ============================================================================= */
PRINT '--------------------------------------------------------------------------------';
PRINT ' 4. LIMPIEZA FINAL Y VERIFICACIÓN';
PRINT '--------------------------------------------------------------------------------';

DECLARE @maxIdAntes int = (SELECT maxIdError FROM #foto);
DECLARE @id int = 0, @borrados int = 0, @noBorrados int = 0;

IF OBJECT_ID('tempdb..#nuevos') IS NOT NULL DROP TABLE #nuevos;
CREATE TABLE #nuevos (idArbitro int PRIMARY KEY);
INSERT INTO #nuevos (idArbitro)
SELECT a.idArbitro FROM Arbitraje.Arbitro AS a
WHERE NOT EXISTS (SELECT 1 FROM #arbPre AS p WHERE p.idArbitro = a.idArbitro);

WHILE EXISTS (SELECT 1 FROM #nuevos WHERE idArbitro > @id)
BEGIN
    SELECT TOP (1) @id = idArbitro FROM #nuevos WHERE idArbitro > @id ORDER BY idArbitro;
    BEGIN TRY
        EXEC Arbitraje.Arbitro_Baja @idArbitro = @id;
        SET @borrados += 1;
    END TRY
    BEGIN CATCH
        SET @noBorrados += 1;
    END CATCH;
END;

DELETE FROM Sistema.ErrorImportacion WHERE id > @maxIdAntes;

-- PRUEBA 16: La base quedó igual que al inicio
-- Resultado esperado: los conteos de Arbitro, ArbitroIdioma y ErrorImportacion
--   vuelven a los valores de la foto inicial, los árbitros e idiomas preexistentes
--   no cambiaron (mismo checksum) y no quedó ningún árbitro nuevo.
SELECT 'FOTO FINAL' AS momento,
       (SELECT COUNT(*) FROM Arbitraje.Arbitro)                        AS cantArbitro,
       (SELECT COUNT(*) FROM Arbitraje.ArbitroIdioma)                  AS cantIdioma,
       (SELECT COUNT(*) FROM Sistema.ErrorImportacion)                 AS cantError,
       (SELECT ISNULL(MAX(id), 0) FROM Sistema.ErrorImportacion)       AS maxIdError,
       @borrados AS arbitrosBorrados, @noBorrados AS arbitrosNoBorrados;

IF @noBorrados = 0
   AND (SELECT COUNT(*) FROM Arbitraje.Arbitro) = (SELECT cantArbitro FROM #foto)
   AND (SELECT COUNT(*) FROM Arbitraje.ArbitroIdioma) = (SELECT cantIdioma FROM #foto)
   AND (SELECT COUNT(*) FROM Sistema.ErrorImportacion) = (SELECT cantError FROM #foto)
   AND (SELECT ISNULL(MAX(id), 0) FROM Sistema.ErrorImportacion) = (SELECT maxIdError FROM #foto)
   AND (SELECT ISNULL(CHECKSUM_AGG(CHECKSUM(idArbitro, idPais, nombre, apellido, categoria, genero, fechaInternacional)), 0)
        FROM Arbitraje.Arbitro) = (SELECT chkArbitro FROM #foto)
   AND (SELECT ISNULL(CHECKSUM_AGG(CHECKSUM(idArbitro, idioma)), 0)
        FROM Arbitraje.ArbitroIdioma) = (SELECT chkIdioma FROM #foto)
    PRINT '[OK] PRUEBA 16: Base restaurada: ' + CAST(@borrados AS varchar(10)) + ' árbitros nuevos borrados; conteos y árbitros/idiomas preexistentes idénticos a la foto inicial.';
ELSE PRINT '[FALLO] PRUEBA 16: La base no volvió al estado inicial (ver FOTO FINAL contra FOTO INICIAL).';

DROP TABLE #nuevos;
DROP TABLE #arbPre;
DROP TABLE #foto;
DROP TABLE #cfg;

PRINT 'Fixture de pruebas limpiado con éxito.';
PRINT '================================================================================';
PRINT ' BATERÍA DE PRUEBAS DE IMPORTACIÓN FINALIZADA: 16 pruebas';
PRINT '   1. Dataset real: 5 | 2. Ruta, lectura y transacción (SP público): 6 | 3. XML literal (SP interno): 4 | 4. Limpieza: 1';
PRINT ' Mapa mensaje -> prueba:';
PRINT '   Ruta obligatoria: 6 | Caracteres inválidos: 7 | No se pudo leer: 8 y 9';
PRINT '   Transacción abierta: 10 (SP público) y 12 (SP interno) | Acumulación: 11';
PRINT '   Estructura inesperada: 13 | Datos inválidos, fecha, nombre, apellido, género y categoría largos: 14';
PRINT '   Error de un ABM (categoría inválida): 15 | País inexistente: 5 | Restauración: 16';
PRINT '================================================================================';
GO
