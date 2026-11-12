/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 10/11/2026

 Objetivo    : Pruebas de 43_Importar_APIs.sql: Sistema.ConsultarAPI,
               Torneo.Procesar_PBIBancoMundial, Torneo.Importar_PBIBancoMundial,
               Publicidad.Procesar_TipoCambioFrankfurter y
               Publicidad.Importar_TipoCambioFrankfurter.

 Cómo se prueba:
 - Los Procesar_* se prueban con respuestas JSON fijas, sin internet: alta,
   modificación, repetición sin duplicados, importación parcial con datos
   inválidos, registro de los errores en Sistema.ErrorImportacion y respuestas
   mal formadas.
 - Los Importar_* se prueban en dos partes: la validación de parámetros (sin
   internet) y una prueba en vivo contra la API real. Las pruebas en vivo
   corren dentro de una transacción que se deshace (no dejan datos) y, si el
   servidor no tiene internet o no tiene habilitado Ole Automation, se
   informan como [OMITIDA] en vez de [FALLO].

 Requisitos  : 00_InitialSchema.sql, 10a, 10c y 43. Para las pruebas en vivo,
               internet y "Ole Automation Procedures" habilitado.
 Datos de prueba: países XTA a XTH (códigos ISO XA a XH), monedas XTA a XTC
               y orígenes que empiezan con prueba_api. Se borran al inicio y
               al final. Los datos reales no se tocan.

 Cada prueba imprime [OK] o [FALLO]. Resultado esperado: todas [OK] (las
 [OMITIDA] no cuentan como fallo).
================================================================================
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

PRINT '================================================================================';
PRINT ' PRUEBAS: 43_Importar_APIs.sql';
PRINT '================================================================================';
GO

/* =============================================================================
   LIMPIEZA PREVIA Y DATOS DE PRUEBA
   ============================================================================= */
DELETE FROM Sistema.ErrorImportacion WHERE archivo LIKE N'prueba_api%';
DELETE FROM Publicidad.TipoCambio WHERE moneda IN ('XTA', 'XTB', 'XTC');
DELETE FROM Torneo.Pais WHERE codigoISO3 IN ('XTA', 'XTB', 'XTC', 'XTD', 'XTE', 'XTF', 'XTG', 'XTH');
GO

DROP TABLE IF EXISTS #rp;
CREATE TABLE #rp (filasLeidas int, actualizados int, sinCambios int, conError int);
DROP TABLE IF EXISTS #rt;
CREATE TABLE #rt (filasLeidas int, insertados int, actualizados int, sinCambios int, conError int);
GO

-- Países de prueba: XTA 1000, XTB sin PBI, XTC 500, XTD y XTE y XTF para los errores, XTH 100 (no se pide)
EXEC Torneo.Pais_Alta @nombre = N'Pais Test API A', @codigoISO2 = 'XA', @codigoISO3 = 'XTA', @pbiPerCapita = 1000;
EXEC Torneo.Pais_Alta @nombre = N'Pais Test API B', @codigoISO2 = 'XB', @codigoISO3 = 'XTB';
EXEC Torneo.Pais_Alta @nombre = N'Pais Test API C', @codigoISO2 = 'XC', @codigoISO3 = 'XTC', @pbiPerCapita = 500;
EXEC Torneo.Pais_Alta @nombre = N'Pais Test API D', @codigoISO2 = 'XD', @codigoISO3 = 'XTD', @pbiPerCapita = 700;
EXEC Torneo.Pais_Alta @nombre = N'Pais Test API E', @codigoISO2 = 'XE', @codigoISO3 = 'XTE', @pbiPerCapita = 800;
EXEC Torneo.Pais_Alta @nombre = N'Pais Test API F', @codigoISO2 = 'XF', @codigoISO3 = 'XTF', @pbiPerCapita = 900;
EXEC Torneo.Pais_Alta @nombre = N'Pais Test API H', @codigoISO2 = 'XH', @codigoISO3 = 'XTH', @pbiPerCapita = 100;
PRINT 'Datos de prueba creados.';
GO

/* =============================================================================
   1. Sistema.ConsultarAPI
   ============================================================================= */
PRINT '--- 1. Sistema.ConsultarAPI ---';
GO

-- PRUEBA 1.1: URL vacía
-- Resultado esperado: THROW 50001 "- La URL es obligatoria."
DECLARE @r nvarchar(max), @e int;
BEGIN TRY
    EXEC Sistema.ConsultarAPI @url = N'   ', @respuesta = @r OUTPUT;
    PRINT '[FALLO] PRUEBA 1.1: no rechazó la URL vacía.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%- La URL es obligatoria.%'
        PRINT '[OK] PRUEBA 1.1: URL vacía rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 1.1: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.2: URL que no es https, tiempo de espera y reintentos inválidos, juntos
-- Resultado esperado: THROW 50001 con los 3 mensajes juntos
DECLARE @r nvarchar(max);
BEGIN TRY
    EXEC Sistema.ConsultarAPI @url = N'http://api.worldbank.org/v2/country', @respuesta = @r OUTPUT, @timeoutSeg = 0,
         @reintentos = 9;
    PRINT '[FALLO] PRUEBA 1.2: no detectó los errores.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%- La URL debe empezar con https://.%'
       AND ERROR_MESSAGE() LIKE N'%- El tiempo de espera debe estar entre 1 y 300 segundos.%'
       AND ERROR_MESSAGE() LIKE N'%- Los reintentos deben estar entre 0 y 5.%'
        PRINT '[OK] PRUEBA 1.2: URL http, tiempo de espera y reintentos inválidos informados juntos.';
    ELSE PRINT '[FALLO] PRUEBA 1.2: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.3: un servidor que no existe
-- Resultado esperado: THROW 50003 "No se pudo consultar la API (...)" (con o sin internet)
DECLARE @r nvarchar(max);
BEGIN TRY
    EXEC Sistema.ConsultarAPI @url = N'https://no-existe.invalid/', @respuesta = @r OUTPUT, @timeoutSeg = 10, @reintentos = 0;
    PRINT '[FALLO] PRUEBA 1.3: no detectó el servidor inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50003 AND ERROR_MESSAGE() LIKE N'No se pudo consultar la API (%'
        PRINT '[OK] PRUEBA 1.3: servidor inexistente informado con 50003.';
    ELSE PRINT '[FALLO] PRUEBA 1.3: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.4 (en vivo): una consulta real al Banco Mundial
-- Resultado esperado: HTTP 200 y un JSON; [OMITIDA] si no hay internet
DECLARE @r nvarchar(max), @est int;
BEGIN TRY
    EXEC Sistema.ConsultarAPI @url = N'https://api.worldbank.org/v2/country/ARG/indicator/NY.GDP.PCAP.CD?format=json&mrnev=1',
         @respuesta = @r OUTPUT, @estadoHttp = @est OUTPUT, @timeoutSeg = 20;
    IF @est = 200 AND ISJSON(@r) = 1 AND JSON_VALUE(@r, '$[1][0].countryiso3code') = 'ARG'
        PRINT '[OK] PRUEBA 1.4: consulta real al Banco Mundial correcta.';
    ELSE PRINT '[FALLO] PRUEBA 1.4: respuesta inesperada.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50003
        PRINT '[OMITIDA] PRUEBA 1.4: sin conexión o sin Ole Automation (' + LEFT(ERROR_MESSAGE(), 120) + ').';
    ELSE PRINT '[FALLO] PRUEBA 1.4: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.5 (en vivo): un HTTP 422 con @exigir200 = 0 devuelve el cuerpo y el estado
-- Resultado esperado: estado 422 y el mensaje de la API; [OMITIDA] si no hay internet
DECLARE @r nvarchar(max), @est int;
BEGIN TRY
    EXEC Sistema.ConsultarAPI @url = N'https://api.frankfurter.dev/v2/rates?base=USD&quotes=ZZZ',
         @respuesta = @r OUTPUT, @estadoHttp = @est OUTPUT, @exigir200 = 0, @timeoutSeg = 20;
    IF @est = 422 AND JSON_VALUE(@r, '$.message') LIKE N'invalid currency%'
        PRINT '[OK] PRUEBA 1.5: el 422 de Frankfurter se devuelve sin cortar.';
    ELSE PRINT '[FALLO] PRUEBA 1.5: estado ' + ISNULL(CAST(@est AS varchar(10)), 'NULL') + ' y respuesta inesperada.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50003
        PRINT '[OMITIDA] PRUEBA 1.5: sin conexión o sin Ole Automation (' + LEFT(ERROR_MESSAGE(), 120) + ').';
    ELSE PRINT '[FALLO] PRUEBA 1.5: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.6 (en vivo): con @exigir200 = 1 un HTTP distinto de 200 corta con 50003
-- Resultado esperado: THROW 50003 "La API respondió HTTP 422"; [OMITIDA] si no hay internet
DECLARE @r nvarchar(max);
BEGIN TRY
    EXEC Sistema.ConsultarAPI @url = N'https://api.frankfurter.dev/v2/rates?base=USD&quotes=ZZZ',
         @respuesta = @r OUTPUT, @timeoutSeg = 20;
    PRINT '[FALLO] PRUEBA 1.6: no cortó con el HTTP 422.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50003 AND ERROR_MESSAGE() LIKE N'%La API respondió HTTP 422%'
        PRINT '[OK] PRUEBA 1.6: HTTP 422 informado con 50003.';
    ELSE IF ERROR_NUMBER() = 50003
            AND (ERROR_MESSAGE() LIKE N'%(crear el objeto HTTP)%' OR ERROR_MESSAGE() LIKE N'%(enviar el pedido)%')
        PRINT '[OMITIDA] PRUEBA 1.6: sin conexión o sin Ole Automation (' + LEFT(ERROR_MESSAGE(), 120) + ').';
    ELSE PRINT '[FALLO] PRUEBA 1.6: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 1.7: un fallo transitorio de red se reintenta antes de rendirse
-- Se pide a una dirección que no responde con espera de 1 segundo y 1 reintento.
-- Resultado esperado: THROW 50003 que informa "tras 2 intentos"; [OMITIDA] si no hay Ole Automation
DECLARE @r nvarchar(max);
BEGIN TRY
    EXEC Sistema.ConsultarAPI @url = N'https://10.255.255.1/', @respuesta = @r OUTPUT, @timeoutSeg = 1, @reintentos = 1;
    PRINT '[FALLO] PRUEBA 1.7: no falló una dirección que no responde.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50003 AND ERROR_MESSAGE() LIKE N'%[[]tras 2 intentos]%'
        PRINT '[OK] PRUEBA 1.7: el fallo de red se reintentó (2 intentos) antes de cortar con 50003.';
    ELSE IF ERROR_NUMBER() = 50003 AND ERROR_MESSAGE() LIKE N'%(crear el objeto HTTP)%'
        PRINT '[OMITIDA] PRUEBA 1.7: sin Ole Automation (' + LEFT(ERROR_MESSAGE(), 120) + ').';
    ELSE PRINT '[FALLO] PRUEBA 1.7: ' + ISNULL(ERROR_MESSAGE(), 'sin mensaje');
END CATCH;
GO

/* =============================================================================
   2. Torneo.Procesar_PBIBancoMundial (con respuestas fijas)
   ============================================================================= */
PRINT '--- 2. Torneo.Procesar_PBIBancoMundial ---';
GO

-- PRUEBA 2.1: importación parcial con datos válidos e inválidos
-- Observaciones: XTA con dos años (se usa el último), XTB sin PBI antes, XTC sin cambios,
-- XTE con valor nulo, XTF negativo, XTH que no se pidió y una fila sin código ISO.
-- XTD se pidió pero la fuente no la trae.
-- Resultado esperado: leídas 8, actualizados 2 (XTA y XTB), sin cambios 1 (XTC), con error 3 (XTD, XTE, XTF)
DECLARE @json nvarchar(max) = N'[
  {"indicator":{"id":"NY.GDP.PCAP.CD","value":"GDP per capita"},"country":{"id":"XA","value":"Pais Test API A"},"countryiso3code":"XTA","date":"2024","value":1500.0},
  {"country":{"id":"XA","value":"Pais Test API A"},"countryiso3code":"XTA","date":"2025","value":2000.5},
  {"countryiso3code":"XTB","date":"2025","value":3000},
  {"countryiso3code":"XTC","date":"2025","value":500},
  {"countryiso3code":"XTE","date":"2025","value":null},
  {"countryiso3code":"XTF","date":"2025","value":-5},
  {"countryiso3code":"XTH","date":"2025","value":999},
  {"countryiso3code":"","date":"2025","value":1234}
]';
DELETE FROM #rp;
BEGIN TRY
    PRINT 'Evidencia previa (PBI antes de importar):';
    SELECT codigoISO3, pbiPerCapita FROM Torneo.Pais WHERE codigoISO3 LIKE 'XT%' ORDER BY codigoISO3;
    INSERT INTO #rp
    EXEC Torneo.Procesar_PBIBancoMundial @observacionesJson = @json, @origen = N'prueba_api_bancomundial',
         @paises = 'XTA,XTB,XTC,XTD,XTE,XTF';
    PRINT 'Evidencia posterior (PBI después de importar):';
    SELECT codigoISO3, pbiPerCapita FROM Torneo.Pais WHERE codigoISO3 LIKE 'XT%' ORDER BY codigoISO3;

    IF EXISTS (SELECT 1 FROM #rp WHERE filasLeidas = 8 AND actualizados = 2 AND sinCambios = 1 AND conError = 3)
        PRINT '[OK] PRUEBA 2.1: 2 actualizados, 1 sin cambios y 3 con error de 8 filas leídas.';
    ELSE PRINT '[FALLO] PRUEBA 2.1: resumen inesperado.';
    SELECT * FROM #rp;
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.1: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 2.2: los valores quedaron bien
-- Resultado esperado: XTA 2000.50 (el año más reciente), XTB 3000.00, XTC 500.00, XTH 100.00 (no se pidió, no se toca)
IF (SELECT pbiPerCapita FROM Torneo.Pais WHERE codigoISO3 = 'XTA') = 2000.50
   AND (SELECT pbiPerCapita FROM Torneo.Pais WHERE codigoISO3 = 'XTB') = 3000.00
   AND (SELECT pbiPerCapita FROM Torneo.Pais WHERE codigoISO3 = 'XTC') = 500.00
   AND (SELECT pbiPerCapita FROM Torneo.Pais WHERE codigoISO3 = 'XTH') = 100.00
    PRINT '[OK] PRUEBA 2.2: XTA toma el año más reciente, XTB se completa, XTC no cambia y XTH no se toca.';
ELSE PRINT '[FALLO] PRUEBA 2.2: valores de PBI inesperados.';
GO

-- PRUEBA 2.3: los 3 errores quedaron registrados con su motivo
-- Resultado esperado: 3 filas en Sistema.ErrorImportacion: no figura, valor nulo y mayor a cero
IF (SELECT COUNT(*) FROM Sistema.ErrorImportacion WHERE archivo = N'prueba_api_bancomundial' AND tablaDestino = 'Torneo.Pais') = 3
   AND EXISTS (SELECT 1 FROM Sistema.ErrorImportacion WHERE archivo = N'prueba_api_bancomundial' AND mensajeError LIKE N'%no figura en la fuente%')
   AND EXISTS (SELECT 1 FROM Sistema.ErrorImportacion WHERE archivo = N'prueba_api_bancomundial' AND mensajeError LIKE N'%valor nulo%')
   AND EXISTS (SELECT 1 FROM Sistema.ErrorImportacion WHERE archivo = N'prueba_api_bancomundial' AND mensajeError LIKE N'%mayor a cero%')
    PRINT '[OK] PRUEBA 2.3: los 3 errores quedaron registrados con su motivo.';
ELSE PRINT '[FALLO] PRUEBA 2.3: errores registrados inesperados.';
SELECT nroFila, LEFT(datoOriginal, 60) AS datoOriginal, mensajeError FROM Sistema.ErrorImportacion
WHERE archivo = N'prueba_api_bancomundial' ORDER BY id;
GO

-- PRUEBA 2.4: repetir la importación no duplica ni vuelve a modificar
-- Resultado esperado: 0 actualizados, 3 sin cambios (XTA, XTB y XTC), los mismos 3 errores
DECLARE @json nvarchar(max) = N'[
  {"countryiso3code":"XTA","date":"2024","value":1500.0},
  {"countryiso3code":"XTA","date":"2025","value":2000.5},
  {"countryiso3code":"XTB","date":"2025","value":3000},
  {"countryiso3code":"XTC","date":"2025","value":500},
  {"countryiso3code":"XTE","date":"2025","value":null},
  {"countryiso3code":"XTF","date":"2025","value":-5},
  {"countryiso3code":"XTH","date":"2025","value":999},
  {"countryiso3code":"","date":"2025","value":1234}
]';
DELETE FROM #rp;
BEGIN TRY
    INSERT INTO #rp
    EXEC Torneo.Procesar_PBIBancoMundial @observacionesJson = @json, @origen = N'prueba_api_bancomundial',
         @paises = 'XTA,XTB,XTC,XTD,XTE,XTF';
    IF EXISTS (SELECT 1 FROM #rp WHERE actualizados = 0 AND sinCambios = 3 AND conError = 3)
        PRINT '[OK] PRUEBA 2.4: la repetición no modificó nada.';
    ELSE PRINT '[FALLO] PRUEBA 2.4: resumen inesperado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.4: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 2.5: un valor que no es un número
-- Resultado esperado: el país queda con error "no es un número válido" y no se modifica
DECLARE @json nvarchar(max) = N'[{"countryiso3code":"XTD","date":"2025","value":"n/a"}]';
DELETE FROM #rp;
BEGIN TRY
    INSERT INTO #rp EXEC Torneo.Procesar_PBIBancoMundial @observacionesJson = @json, @origen = N'prueba_api_bancomundial', @paises = 'XTD';
    IF EXISTS (SELECT 1 FROM #rp WHERE conError = 1 AND actualizados = 0)
       AND (SELECT pbiPerCapita FROM Torneo.Pais WHERE codigoISO3 = 'XTD') = 700.00
       AND EXISTS (SELECT 1 FROM Sistema.ErrorImportacion WHERE archivo = N'prueba_api_bancomundial' AND mensajeError LIKE N'%no es un número válido%')
        PRINT '[OK] PRUEBA 2.5: el valor no numérico se registró como error y XTD no cambió.';
    ELSE PRINT '[FALLO] PRUEBA 2.5: resultado inesperado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.5: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 2.6: un texto que no es JSON
-- Resultado esperado: THROW 50003 "el contenido no es un JSON válido"
BEGIN TRY
    EXEC Torneo.Procesar_PBIBancoMundial @observacionesJson = N'esto no es json', @origen = N'prueba_api_bancomundial';
    PRINT '[FALLO] PRUEBA 2.6: aceptó un texto que no es JSON.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50003 AND ERROR_MESSAGE() LIKE N'%no es un JSON válido%'
        PRINT '[OK] PRUEBA 2.6: JSON inválido cortó la importación con 50003.';
    ELSE PRINT '[FALLO] PRUEBA 2.6: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 2.7: un JSON que no es un arreglo
-- Resultado esperado: THROW 50003 "se esperaba un arreglo de observaciones"
BEGIN TRY
    EXEC Torneo.Procesar_PBIBancoMundial @observacionesJson = N'{"a":1}', @origen = N'prueba_api_bancomundial';
    PRINT '[FALLO] PRUEBA 2.7: aceptó un JSON que no es un arreglo.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50003 AND ERROR_MESSAGE() LIKE N'%se esperaba un arreglo de observaciones%'
        PRINT '[OK] PRUEBA 2.7: un JSON sin forma de arreglo cortó con 50003.';
    ELSE PRINT '[FALLO] PRUEBA 2.7: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 2.8: observaciones nulas, origen vacío y países mal escritos, juntos
-- Resultado esperado: THROW 50001 con los 3 mensajes juntos
BEGIN TRY
    EXEC Torneo.Procesar_PBIBancoMundial @observacionesJson = NULL, @origen = N' ', @paises = 'AR,XTA';
    PRINT '[FALLO] PRUEBA 2.8: no detectó los errores.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%- Las observaciones son obligatorias.%'
       AND ERROR_MESSAGE() LIKE N'%- El origen de los datos es obligatorio.%'
       AND ERROR_MESSAGE() LIKE N'%- Los países deben ser códigos ISO alfa-3%'
        PRINT '[OK] PRUEBA 2.8: los 3 errores de parámetros se informaron juntos.';
    ELSE PRINT '[FALLO] PRUEBA 2.8: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   3. Torneo.Importar_PBIBancoMundial
   ============================================================================= */
PRINT '--- 3. Torneo.Importar_PBIBancoMundial ---';
GO

-- PRUEBA 3.1: parámetros inválidos
-- Resultado esperado: THROW 50001 con los 3 mensajes juntos
BEGIN TRY
    EXEC Torneo.Importar_PBIBancoMundial @urlBase = N'http://api.worldbank.org/v2', @indicador = 'ny.gdp',
         @paisesPorPedido = 0;
    PRINT '[FALLO] PRUEBA 3.1: no detectó los errores.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%- La URL base debe empezar con https://.%'
       AND ERROR_MESSAGE() LIKE N'%- El indicador solo puede tener letras mayúsculas%'
       AND ERROR_MESSAGE() LIKE N'%- Los países por pedido deben estar entre 1 y 15.%'
        PRINT '[OK] PRUEBA 3.1: los 3 errores de parámetros se informaron juntos.';
    ELSE PRINT '[FALLO] PRUEBA 3.1: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.2 (en vivo): importación real; los países de prueba XTA..XTH no existen en el Banco Mundial
-- Se hace dentro de una transacción que se deshace. Resultado esperado: los 7 países de prueba rechazados
-- por la API se registran como error y los demás se procesan; [OMITIDA] si no hay internet
BEGIN TRY
    BEGIN TRANSACTION;
    DELETE FROM #rp;
    CREATE TABLE #rv (filasLeidas int, actualizados int, sinCambios int, conError int);
    INSERT INTO #rv EXEC Torneo.Importar_PBIBancoMundial;
    DECLARE @rechazados int = (SELECT COUNT(*) FROM Sistema.ErrorImportacion WHERE mensajeError LIKE N'%La API rechazó el código de país XT%');
    DECLARE @conError int = (SELECT conError FROM #rv);
    DROP TABLE #rv;
    ROLLBACK TRANSACTION;
    IF @rechazados = 7 AND @conError >= 7
        PRINT CONCAT('[OK] PRUEBA 3.2: los 7 países que la API no conoce se registraron como error (', @conError, ' errores en total).');
    ELSE PRINT CONCAT('[FALLO] PRUEBA 3.2: rechazados = ', @rechazados, ', conError = ', @conError, '.');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF OBJECT_ID('tempdb..#rv') IS NOT NULL DROP TABLE #rv;
    IF ERROR_NUMBER() = 50003
        PRINT '[OMITIDA] PRUEBA 3.2: sin conexión o sin Ole Automation (' + LEFT(ERROR_MESSAGE(), 120) + ').';
    ELSE PRINT '[FALLO] PRUEBA 3.2: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   4. Publicidad.Procesar_TipoCambioFrankfurter (con respuestas fijas)
   ============================================================================= */
PRINT '--- 4. Publicidad.Procesar_TipoCambioFrankfurter ---';
GO

-- Cotizaciones previas: XTB 2026-06-15 = 2.0 (igual a la respuesta) y XTC 2026-06-15 = 2.5 (la respuesta trae 3.0)
EXEC Publicidad.TipoCambio_Alta @moneda = 'XTB', @fecha = '2026-06-15', @cotizacionUSD = 2.0;
EXEC Publicidad.TipoCambio_Alta @moneda = 'XTC', @fecha = '2026-06-15', @cotizacionUSD = 2.5;
GO

-- PRUEBA 4.1: importación parcial: altas, una sin cambios, una modificación y filas inválidas
-- Filas: 1-2 altas de XTA, 3 igual a la guardada, 4 modificación, 5 base EUR, 6 moneda de 2 letras,
-- 7 cotización 0, 8 fecha inválida, 9 cotización "abc", 10 repetida igual, 11 repetida con otro valor,
-- 12 fecha futura (la rechaza TipoCambio_Alta).
-- Resultado esperado: leídas 12, insertados 2, actualizados 1, sin cambios 2 (fila 3 y la repetida igual), con error 7
DECLARE @json nvarchar(max) = N'[
  {"date":"2026-06-15","base":"USD","quote":"XTA","rate":1.5},
  {"date":"2026-06-16","base":"USD","quote":"XTA","rate":1.6},
  {"date":"2026-06-15","base":"USD","quote":"XTB","rate":2.0},
  {"date":"2026-06-15","base":"USD","quote":"XTC","rate":3.0},
  {"date":"2026-06-15","base":"EUR","quote":"XTA","rate":1.1},
  {"date":"2026-06-15","base":"USD","quote":"AB","rate":1.1},
  {"date":"2026-06-15","base":"USD","quote":"XTA","rate":0},
  {"date":"no-es-fecha","base":"USD","quote":"XTA","rate":1.1},
  {"date":"2026-06-17","base":"USD","quote":"XTA","rate":"abc"},
  {"date":"2026-06-15","base":"USD","quote":"XTA","rate":1.5},
  {"date":"2026-06-16","base":"USD","quote":"XTA","rate":9.9},
  {"date":"2099-01-01","base":"USD","quote":"XTA","rate":1.2}
]';
DELETE FROM #rt;
BEGIN TRY
    PRINT 'Evidencia previa (cotizaciones de prueba):';
    SELECT moneda, fecha, cotizacionUSD FROM Publicidad.TipoCambio WHERE moneda LIKE 'XT%' ORDER BY moneda, fecha;
    INSERT INTO #rt
    EXEC Publicidad.Procesar_TipoCambioFrankfurter @cotizacionesJson = @json, @origen = N'prueba_api_frankfurter';
    PRINT 'Evidencia posterior (cotizaciones de prueba):';
    SELECT moneda, fecha, cotizacionUSD FROM Publicidad.TipoCambio WHERE moneda LIKE 'XT%' ORDER BY moneda, fecha;

    IF EXISTS (SELECT 1 FROM #rt WHERE filasLeidas = 12 AND insertados = 2 AND actualizados = 1 AND sinCambios = 2 AND conError = 7)
        PRINT '[OK] PRUEBA 4.1: 2 altas, 1 modificación, 2 sin cambios y 7 con error de 12 filas.';
    ELSE PRINT '[FALLO] PRUEBA 4.1: resumen inesperado.';
    SELECT * FROM #rt;
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 4.1: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 4.2: los valores quedaron bien
-- Resultado esperado: XTA 15/06 = 1.5, XTA 16/06 = 1.6 (la repetida con 9.9 no pisa), XTB = 2.0, XTC = 3.0
IF (SELECT cotizacionUSD FROM Publicidad.TipoCambio WHERE moneda = 'XTA' AND fecha = '2026-06-15') = 1.5
   AND (SELECT cotizacionUSD FROM Publicidad.TipoCambio WHERE moneda = 'XTA' AND fecha = '2026-06-16') = 1.6
   AND (SELECT cotizacionUSD FROM Publicidad.TipoCambio WHERE moneda = 'XTB' AND fecha = '2026-06-15') = 2.0
   AND (SELECT cotizacionUSD FROM Publicidad.TipoCambio WHERE moneda = 'XTC' AND fecha = '2026-06-15') = 3.0
   AND (SELECT COUNT(*) FROM Publicidad.TipoCambio WHERE moneda = 'XTA') = 2
    PRINT '[OK] PRUEBA 4.2: altas y modificación correctas; la repetida con otro valor no pisó la primera.';
ELSE PRINT '[FALLO] PRUEBA 4.2: cotizaciones inesperadas.';
GO

-- PRUEBA 4.3: los 7 errores quedaron registrados con su motivo
-- Resultado esperado: 7 filas en ErrorImportacion; entre ellas la base, la moneda, la fecha, la cotización,
-- la repetida con otro valor y la fecha futura que rechazó el ABM
IF (SELECT COUNT(*) FROM Sistema.ErrorImportacion WHERE archivo = N'prueba_api_frankfurter' AND tablaDestino = 'Publicidad.TipoCambio') = 7
   AND EXISTS (SELECT 1 FROM Sistema.ErrorImportacion WHERE archivo = N'prueba_api_frankfurter' AND mensajeError LIKE N'%La base de la cotización debe ser USD%')
   AND EXISTS (SELECT 1 FROM Sistema.ErrorImportacion WHERE archivo = N'prueba_api_frankfurter' AND mensajeError LIKE N'%código ISO 4217 de 3 letras%')
   AND EXISTS (SELECT 1 FROM Sistema.ErrorImportacion WHERE archivo = N'prueba_api_frankfurter' AND mensajeError LIKE N'%La fecha no es válida%')
   AND EXISTS (SELECT 1 FROM Sistema.ErrorImportacion WHERE archivo = N'prueba_api_frankfurter' AND mensajeError LIKE N'%mayor a cero%')
   AND EXISTS (SELECT 1 FROM Sistema.ErrorImportacion WHERE archivo = N'prueba_api_frankfurter' AND mensajeError LIKE N'%repetidas en la respuesta con otro valor%')
   AND EXISTS (SELECT 1 FROM Sistema.ErrorImportacion WHERE archivo = N'prueba_api_frankfurter' AND mensajeError LIKE N'%no puede ser futura%')
    PRINT '[OK] PRUEBA 4.3: los 7 errores quedaron registrados con su motivo.';
ELSE PRINT '[FALLO] PRUEBA 4.3: errores registrados inesperados.';
SELECT nroFila, LEFT(datoOriginal, 70) AS datoOriginal, LEFT(mensajeError, 100) AS mensajeError
FROM Sistema.ErrorImportacion WHERE archivo = N'prueba_api_frankfurter' ORDER BY nroFila;
GO

-- PRUEBA 4.4: repetir la importación no duplica ni vuelve a modificar
-- Resultado esperado: 0 insertados, 0 actualizados, 5 sin cambios, los mismos 7 errores
DECLARE @json nvarchar(max) = N'[
  {"date":"2026-06-15","base":"USD","quote":"XTA","rate":1.5},
  {"date":"2026-06-16","base":"USD","quote":"XTA","rate":1.6},
  {"date":"2026-06-15","base":"USD","quote":"XTB","rate":2.0},
  {"date":"2026-06-15","base":"USD","quote":"XTC","rate":3.0},
  {"date":"2026-06-15","base":"EUR","quote":"XTA","rate":1.1},
  {"date":"2026-06-15","base":"USD","quote":"AB","rate":1.1},
  {"date":"2026-06-15","base":"USD","quote":"XTA","rate":0},
  {"date":"no-es-fecha","base":"USD","quote":"XTA","rate":1.1},
  {"date":"2026-06-17","base":"USD","quote":"XTA","rate":"abc"},
  {"date":"2026-06-15","base":"USD","quote":"XTA","rate":1.5},
  {"date":"2026-06-16","base":"USD","quote":"XTA","rate":9.9},
  {"date":"2099-01-01","base":"USD","quote":"XTA","rate":1.2}
]';
DELETE FROM #rt;
BEGIN TRY
    INSERT INTO #rt EXEC Publicidad.Procesar_TipoCambioFrankfurter @cotizacionesJson = @json, @origen = N'prueba_api_frankfurter';
    IF EXISTS (SELECT 1 FROM #rt WHERE insertados = 0 AND actualizados = 0 AND sinCambios = 5 AND conError = 7)
       AND (SELECT COUNT(*) FROM Publicidad.TipoCambio WHERE moneda LIKE 'XT%') = 4
        PRINT '[OK] PRUEBA 4.4: la repetición no insertó ni modificó nada.';
    ELSE PRINT '[FALLO] PRUEBA 4.4: resumen inesperado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 4.4: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 4.5: la API devolvió un error (objeto con mensaje, como el 422 de moneda inexistente)
-- Resultado esperado: THROW 50003 con el mensaje de la API
BEGIN TRY
    EXEC Publicidad.Procesar_TipoCambioFrankfurter @cotizacionesJson = N'{"status":422,"message":"invalid currency: ZZZ"}',
         @origen = N'prueba_api_frankfurter';
    PRINT '[FALLO] PRUEBA 4.5: aceptó una respuesta de error.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50003 AND ERROR_MESSAGE() LIKE N'%la API devolvió un error: invalid currency: ZZZ%'
        PRINT '[OK] PRUEBA 4.5: el error de la API cortó la importación con 50003 y su mensaje.';
    ELSE PRINT '[FALLO] PRUEBA 4.5: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 4.6: un texto que no es JSON
-- Resultado esperado: THROW 50003 "el contenido no es un JSON válido"
BEGIN TRY
    EXEC Publicidad.Procesar_TipoCambioFrankfurter @cotizacionesJson = N'<html>no</html>', @origen = N'prueba_api_frankfurter';
    PRINT '[FALLO] PRUEBA 4.6: aceptó un texto que no es JSON.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50003 AND ERROR_MESSAGE() LIKE N'%no es un JSON válido%'
        PRINT '[OK] PRUEBA 4.6: JSON inválido cortó la importación con 50003.';
    ELSE PRINT '[FALLO] PRUEBA 4.6: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 4.7: cotizaciones nulas y origen vacío, juntos
-- Resultado esperado: THROW 50001 con los 2 mensajes juntos
BEGIN TRY
    EXEC Publicidad.Procesar_TipoCambioFrankfurter @cotizacionesJson = NULL, @origen = N'';
    PRINT '[FALLO] PRUEBA 4.7: no detectó los errores.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%- Las cotizaciones son obligatorias.%'
       AND ERROR_MESSAGE() LIKE N'%- El origen de los datos es obligatorio.%'
        PRINT '[OK] PRUEBA 4.7: los 2 errores de parámetros se informaron juntos.';
    ELSE PRINT '[FALLO] PRUEBA 4.7: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   5. Publicidad.Importar_TipoCambioFrankfurter
   ============================================================================= */
PRINT '--- 5. Publicidad.Importar_TipoCambioFrankfurter ---';
GO

-- PRUEBA 5.1: fecha hasta sin fecha desde, y URL http, juntas
-- Resultado esperado: THROW 50001 con los 2 mensajes juntos
BEGIN TRY
    EXEC Publicidad.Importar_TipoCambioFrankfurter @fechaHasta = '2026-06-15', @urlBase = N'http://api.frankfurter.dev/v2';
    PRINT '[FALLO] PRUEBA 5.1: no detectó los errores.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%- La URL base debe empezar con https://.%'
       AND ERROR_MESSAGE() LIKE N'%- Si se indica la fecha hasta, también hay que indicar la fecha desde.%'
        PRINT '[OK] PRUEBA 5.1: URL http y fecha hasta sola informadas juntas.';
    ELSE PRINT '[FALLO] PRUEBA 5.1: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 5.2: fecha desde posterior a la fecha hasta
-- Resultado esperado: THROW 50001 "La fecha desde no puede ser posterior a la fecha hasta."
BEGIN TRY
    EXEC Publicidad.Importar_TipoCambioFrankfurter @fechaDesde = '2026-07-01', @fechaHasta = '2026-06-01';
    PRINT '[FALLO] PRUEBA 5.2: aceptó las fechas invertidas.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%- La fecha desde no puede ser posterior a la fecha hasta.%'
        PRINT '[OK] PRUEBA 5.2: fechas invertidas rechazadas.';
    ELSE PRINT '[FALLO] PRUEBA 5.2: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 5.3: fecha futura
-- Resultado esperado: THROW 50001 "Las fechas no pueden ser futuras."
BEGIN TRY
    EXEC Publicidad.Importar_TipoCambioFrankfurter @fechaDesde = '2099-01-01', @fechaHasta = '2099-01-05';
    PRINT '[FALLO] PRUEBA 5.3: aceptó fechas futuras.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%- Las fechas no pueden ser futuras.%'
        PRINT '[OK] PRUEBA 5.3: fechas futuras rechazadas.';
    ELSE PRINT '[FALLO] PRUEBA 5.3: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 5.4: rango mayor a 400 días
-- Resultado esperado: THROW 50001 "El rango no puede superar los 400 días."
BEGIN TRY
    EXEC Publicidad.Importar_TipoCambioFrankfurter @fechaDesde = '2020-01-01', @fechaHasta = '2026-01-01';
    PRINT '[FALLO] PRUEBA 5.4: aceptó un rango de varios años.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%- El rango no puede superar los 400 días.%'
        PRINT '[OK] PRUEBA 5.4: rango demasiado largo rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 5.4: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 5.5: monedas mal escritas
-- Resultado esperado: THROW 50001 "Las monedas deben ser códigos ISO 4217 de 3 letras separados por coma."
BEGIN TRY
    EXEC Publicidad.Importar_TipoCambioFrankfurter @monedas = 'EUR,12,AB';
    PRINT '[FALLO] PRUEBA 5.5: aceptó monedas inválidas.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%- Las monedas deben ser códigos ISO 4217 de 3 letras%'
        PRINT '[OK] PRUEBA 5.5: monedas inválidas rechazadas.';
    ELSE PRINT '[FALLO] PRUEBA 5.5: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 5.6 (en vivo): rango de 2 días con una moneda real y una que no existe
-- Dentro de una transacción que se deshace. Resultado esperado: EUR cargada (2 filas leídas) y ZZZ registrada como
-- error "no está disponible en Frankfurter"; [OMITIDA] si no hay internet
BEGIN TRY
    BEGIN TRANSACTION;
    CREATE TABLE #rl (filasLeidas int, insertados int, actualizados int, sinCambios int, conError int);
    INSERT INTO #rl EXEC Publicidad.Importar_TipoCambioFrankfurter @fechaDesde = '2026-06-15', @fechaHasta = '2026-06-16',
                         @monedas = 'EUR,ZZZ';
    DECLARE @leidas int = (SELECT filasLeidas FROM #rl);
    DECLARE @cargadas int = (SELECT insertados + actualizados + sinCambios FROM #rl);
    DECLARE @err int = (SELECT conError FROM #rl);
    DECLARE @msj int = (SELECT COUNT(*) FROM Sistema.ErrorImportacion WHERE mensajeError LIKE N'%La moneda ZZZ no está disponible en Frankfurter%');
    DROP TABLE #rl;
    ROLLBACK TRANSACTION;
    IF @leidas = 2 AND @cargadas = 2 AND @err = 1 AND @msj = 1
        PRINT '[OK] PRUEBA 5.6: EUR se cargó (2 días) y ZZZ se registró como moneda no disponible.';
    ELSE PRINT CONCAT('[FALLO] PRUEBA 5.6: leídas ', @leidas, ', cargadas ', @cargadas, ', error ', @err, ', mensajes ', @msj, '.');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF OBJECT_ID('tempdb..#rl') IS NOT NULL DROP TABLE #rl;
    IF ERROR_NUMBER() = 50003
        PRINT '[OMITIDA] PRUEBA 5.6: sin conexión o sin Ole Automation (' + LEFT(ERROR_MESSAGE(), 120) + ').';
    ELSE PRINT '[FALLO] PRUEBA 5.6: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   LIMPIEZA FINAL
   ============================================================================= */
PRINT '--- Limpieza final de los datos de prueba ---';
DELETE FROM Sistema.ErrorImportacion WHERE archivo LIKE N'prueba_api%';
DELETE FROM Publicidad.TipoCambio WHERE moneda IN ('XTA', 'XTB', 'XTC');
DELETE FROM Torneo.Pais WHERE codigoISO3 IN ('XTA', 'XTB', 'XTC', 'XTD', 'XTE', 'XTF', 'XTG', 'XTH');
DROP TABLE IF EXISTS #rp;
DROP TABLE IF EXISTS #rt;
GO

PRINT '================================================================================';
PRINT ' PRUEBAS FINALIZADAS: 43_Importar_APIs.sql';
PRINT '================================================================================';
GO
