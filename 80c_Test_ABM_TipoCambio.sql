/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 09/11/2026

 Objetivo    : Pruebas de los SP de 10c_ABM_TipoCambio.sql: casos exitosos con
               evidencia antes/después y casos que deben fallar en cada
               validación.

 Datos de prueba:
 - Moneda XTS, que la norma ISO 4217 reserva para pruebas y nunca se usa
   como moneda real. Las pruebas con USD solo verifican rechazos: no insertan.
 - Se limpian al inicio y al final: el script se puede ejecutar varias veces.

 Cada prueba imprime [OK] o [FALLO]. Resultado esperado: todas [OK].
================================================================================
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

PRINT '================================================================================';
PRINT ' PRUEBAS: 10c_ABM_TipoCambio.sql';
PRINT '================================================================================';
GO

DELETE FROM Publicidad.TipoCambio WHERE moneda = 'XTS';
GO

-- PRUEBA 1: alta exitosa (moneda en minúscula, se normaliza)
-- Resultado esperado: se crea la cotización XTS del 01/06/2026 con valor 950,5.
BEGIN TRY
    SELECT 'ANTES 1' AS momento, COUNT(*) AS filas FROM Publicidad.TipoCambio WHERE moneda = 'XTS';
    EXEC Publicidad.TipoCambio_Alta @moneda = 'xts', @fecha = '2026-06-01', @cotizacionUSD = 950.5;
    SELECT 'DESPUES 1' AS momento, * FROM Publicidad.TipoCambio WHERE moneda = 'XTS';
    IF EXISTS (SELECT 1 FROM Publicidad.TipoCambio WHERE moneda = 'XTS' AND fecha = '2026-06-01')
        PRINT '[OK] PRUEBA 1: cotización creada.';
    ELSE PRINT '[FALLO] PRUEBA 1: la cotización no se creó.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2: misma moneda y fecha
-- Resultado esperado: error 50001 "Ya existe una cotización para esa moneda y fecha."
BEGIN TRY
    EXEC Publicidad.TipoCambio_Alta @moneda = 'XTS', @fecha = '2026-06-01', @cotizacionUSD = 960;
    PRINT '[FALLO] PRUEBA 2: se aceptó una cotización repetida.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%Ya existe una cotización para esa moneda y fecha%'
        PRINT '[OK] PRUEBA 2: cotización repetida rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3: acumulación (moneda de 2 letras, fecha futura, cotización negativa)
-- Resultado esperado: error 50001 con las tres líneas en el mismo mensaje.
BEGIN TRY
    EXEC Publicidad.TipoCambio_Alta @moneda = 'XT', @fecha = '2999-01-01', @cotizacionUSD = -5;
    PRINT '[FALLO] PRUEBA 3: no se detectaron los errores.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'%código ISO 4217 de 3 letras%'
       AND ERROR_MESSAGE() LIKE N'%no puede ser futura%'
       AND ERROR_MESSAGE() LIKE N'%debe ser mayor a cero%'
        PRINT '[OK] PRUEBA 3: los 3 errores se informaron juntos.';
    ELSE PRINT '[FALLO] PRUEBA 3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4: alta sin fecha
-- Resultado esperado: error 50001 "La fecha de la cotización es obligatoria."
BEGIN TRY
    EXEC Publicidad.TipoCambio_Alta @moneda = 'XTS', @fecha = NULL, @cotizacionUSD = 1;
    PRINT '[FALLO] PRUEBA 4: se aceptó una cotización sin fecha.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%fecha de la cotización es obligatoria%'
        PRINT '[OK] PRUEBA 4: cotización sin fecha rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 5: USD con cotización distinta de 1
-- Resultado esperado: error 50001 "La cotización del USD contra sí mismo debe ser 1."
BEGIN TRY
    EXEC Publicidad.TipoCambio_Alta @moneda = 'USD', @fecha = '2026-06-01', @cotizacionUSD = 2;
    PRINT '[FALLO] PRUEBA 5: se aceptó USD con cotización 2.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%USD contra sí mismo debe ser 1%'
        PRINT '[OK] PRUEBA 5: USD con cotización distinta de 1 rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 5: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 6: modificación exitosa
-- Resultado esperado: la cotización XTS del 01/06/2026 pasa a 975,25.
BEGIN TRY
    SELECT 'ANTES 6' AS momento, * FROM Publicidad.TipoCambio WHERE moneda = 'XTS';
    EXEC Publicidad.TipoCambio_Modificacion @moneda = 'XTS', @fecha = '2026-06-01', @cotizacionUSD = 975.25;
    SELECT 'DESPUES 6' AS momento, * FROM Publicidad.TipoCambio WHERE moneda = 'XTS';
    IF EXISTS (SELECT 1 FROM Publicidad.TipoCambio WHERE moneda = 'XTS' AND cotizacionUSD = 975.25)
        PRINT '[OK] PRUEBA 6: cotización modificada.';
    ELSE PRINT '[FALLO] PRUEBA 6: la cotización no se modificó.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 6: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 7: modificación de una cotización inexistente con valor 0
-- Resultado esperado: error 50001 con "No existe una cotización" y "debe ser mayor a cero".
BEGIN TRY
    EXEC Publicidad.TipoCambio_Modificacion @moneda = 'XTS', @fecha = '2026-06-02', @cotizacionUSD = 0;
    PRINT '[FALLO] PRUEBA 7: se modificó una cotización inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%No existe una cotización%'
       AND ERROR_MESSAGE() LIKE N'%debe ser mayor a cero%'
        PRINT '[OK] PRUEBA 7: modificación inválida rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 7: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 8: baja de una cotización inexistente
-- Resultado esperado: error 50001 "No existe una cotización para esa moneda y fecha."
BEGIN TRY
    EXEC Publicidad.TipoCambio_Baja @moneda = 'XTS', @fecha = '2026-06-02';
    PRINT '[FALLO] PRUEBA 8: se eliminó una cotización inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%No existe una cotización%'
        PRINT '[OK] PRUEBA 8: baja de cotización inexistente rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 8: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 9: baja exitosa
-- Resultado esperado: la cotización XTS del 01/06/2026 deja de existir.
BEGIN TRY
    SELECT 'ANTES 9' AS momento, COUNT(*) AS filas FROM Publicidad.TipoCambio WHERE moneda = 'XTS';
    EXEC Publicidad.TipoCambio_Baja @moneda = 'XTS', @fecha = '2026-06-01';
    SELECT 'DESPUES 9' AS momento, COUNT(*) AS filas FROM Publicidad.TipoCambio WHERE moneda = 'XTS';
    IF NOT EXISTS (SELECT 1 FROM Publicidad.TipoCambio WHERE moneda = 'XTS')
        PRINT '[OK] PRUEBA 9: cotización eliminada.';
    ELSE PRINT '[FALLO] PRUEBA 9: la cotización sigue existiendo.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 9: ' + ERROR_MESSAGE();
END CATCH;
GO

DELETE FROM Publicidad.TipoCambio WHERE moneda = 'XTS';

PRINT '================================================================================';
PRINT ' FIN DE LAS PRUEBAS: 10c_ABM_TipoCambio.sql (9 pruebas)';
PRINT '================================================================================';
GO
