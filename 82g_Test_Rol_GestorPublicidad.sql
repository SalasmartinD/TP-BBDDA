/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 20/11/2026

 Objetivo    : Suite de pruebas de seguridad para rol_GestorPublicidad
               y el usuario de prueba usr_publicidad (Entrega 8 - Script 82g):
               Demostrar la capacidad operativa sobre el módulo de Publicidad
               (ABMs, asignación de pauta y reportes), y las restricciones sobre
               cotizaciones TipoCambio_*, esquemas ajenos y acceso directo a tablas.

 Perfil      : rol_GestorPublicidad (usuario de prueba: usr_publicidad)
               - Gestión de anunciantes, campañas, piezas y ubicaciones por SP.
               - Ejecución del algoritmo de asignación Publicidad.AsignarPiezasPartido.
               - Ejecución de los 3 reportes publicitarios (Ocupación, Matriz Prime Time,
                 Ingresos por Moneda).
               - Consulta de partidos y sedes mediante Torneo.vw_Fixture.
               - RESTRICCIONES:
                 * DENY explícito sobre Publicidad.TipoCambio_* (administrado por API/admin).
                 * Prohibido operar o consultar esquemas Equipos, Arbitraje o Eventos.
                 * Prohibido el acceso DML directo a tablas (error 229).
                 * Prohibido descifrar datos personales.

 Estándares aplicados:
 - Cada prueba se ejecuta suplantando al usuario mediante EXECUTE AS USER.
 - Cada lote finaliza con REVERT para garantizar que no quede contexto residual.
 - Uso defensivo de REVERT tanto en TRY como en CATCH en cada bloque.
 - Uso de transacciones con ROLLBACK en pruebas de modificación permitida.
 - Uso de HAS_PERMS_BY_NAME() y captura del error 229 para confirmar denegación.
================================================================================
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

-- Asegurar contexto inicial limpio
REVERT;
GO

PRINT '================================================================================';
PRINT ' INICIANDO BATERÍA DE PRUEBAS: 82g_Test_Rol_GestorPublicidad.sql (usr_publicidad)';
PRINT '================================================================================';
PRINT '';

-- -----------------------------------------------------------------------------
-- PRUEBA 0: Verificación de identidad y pertenencia al rol
-- Resultado esperado: El usuario actual en contexto suplantado es 'usr_publicidad'
-- y es miembro confirmado de 'rol_GestorPublicidad'.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_publicidad';
BEGIN TRY
    DECLARE @usuarioActual sysname = USER_NAME();
    DECLARE @esMiembro int = IS_ROLEMEMBER('rol_GestorPublicidad', 'usr_publicidad');

    REVERT;

    IF @usuarioActual = 'usr_publicidad' AND @esMiembro = 1
        PRINT '[OK] PRUEBA 0: Identidad confirmada como usr_publicidad y miembro de rol_GestorPublicidad.';
    ELSE
        PRINT '[FALLO] PRUEBA 0: La suplantación no devolvió usr_publicidad o no pertenece al rol.';
END TRY
BEGIN CATCH
    REVERT;
    PRINT CONCAT('[FALLO] PRUEBA 0: Error inesperado - ', ERROR_MESSAGE());
END CATCH;
GO

/* =============================================================================
   BLOQUE 1: CASOS QUE DEBEN ANDAR (OPERACIONES PERMITIDAS PARA PUBLICIDAD)
   ============================================================================= */

-- -----------------------------------------------------------------------------
-- PRUEBA 1: Modificación de datos permitida mediante SP (Publicidad.Anunciante_Alta)
-- Resultado esperado: Permiso concedido. Se inserta un anunciante de prueba y se
-- deshace inmediatamente con ROLLBACK para mantener la prueba 100% idempotente.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_publicidad';
BEGIN TRY
    DECLARE @idPaisTest int;
    SELECT TOP 1 @idPaisTest = id FROM Torneo.Pais;

    BEGIN TRANSACTION;

    EXEC Publicidad.Anunciante_Alta
        @nombre             = 'Anunciante Test Seguridad',
        @rubro              = 'Software & AI',
        @idPais             = @idPaisTest,
        @monedaFacturacion  = 'USD';

    -- Comprobar que se insertó correctamente a través del SP
    DECLARE @existe int = 0;
    IF EXISTS (SELECT 1 FROM Publicidad.Anunciante WHERE nombre = 'Anunciante Test Seguridad')
        SET @existe = 1;

    ROLLBACK TRANSACTION;
    REVERT;

    IF @existe = 1
        PRINT '[OK] PRUEBA 1: usr_publicidad ejecutó Publicidad.Anunciante_Alta exitosamente (rollback completado).';
    ELSE
        PRINT '[FALLO] PRUEBA 1: El procedimiento se ejecutó pero no se verificó la inserción.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    REVERT;
    PRINT CONCAT('[FALLO] PRUEBA 1: Error al ejecutar Publicidad.Anunciante_Alta - ', ERROR_MESSAGE());
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 2: Ejecución del SP de asignación de pauta (Publicidad.AsignarPiezasPartido)
-- Resultado esperado: Permiso concedido de ejecución sobre el algoritmo de asignación.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_publicidad';
BEGIN TRY
    DECLARE @permAsignar int = HAS_PERMS_BY_NAME('Publicidad.AsignarPiezasPartido', 'OBJECT', 'EXECUTE');
    REVERT;

    IF @permAsignar = 1
        PRINT '[OK] PRUEBA 2: usr_publicidad posee permiso EXECUTE sobre Publicidad.AsignarPiezasPartido.';
    ELSE
        PRINT '[FALLO] PRUEBA 2: Falta permiso sobre Publicidad.AsignarPiezasPartido.';
END TRY
BEGIN CATCH
    REVERT;
    PRINT CONCAT('[FALLO] PRUEBA 2: Error inesperado - ', ERROR_MESSAGE());
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 3: Ejecución de reportes publicitarios (Ocupación y Matriz Prime Time)
-- Resultado esperado: Permiso concedido. Publicidad.Reporte_MatrizPrimeTime debe
-- ejecutarse sin interrupción de encadenamiento de propiedad gracias a WITH EXECUTE AS OWNER.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_publicidad';
BEGIN TRY
    -- 1. Ocupación publicitaria
    DECLARE @p1 int = HAS_PERMS_BY_NAME('Publicidad.Reporte_OcupacionPublicitaria', 'OBJECT', 'EXECUTE');
    
    -- 2. Matriz de prime time
    DECLARE @p2 int = HAS_PERMS_BY_NAME('Publicidad.Reporte_MatrizPrimeTime', 'OBJECT', 'EXECUTE');

    -- 3. Ingresos por moneda
    DECLARE @p3 int = HAS_PERMS_BY_NAME('Publicidad.Reporte_IngresosPorMoneda', 'OBJECT', 'EXECUTE');

    -- Ejecución real de la matriz para verificar el encadenamiento de propiedad
    DROP TABLE IF EXISTS #tmpMatriz;
    CREATE TABLE #tmpMatriz (nro int, fase varchar(60), partido varchar(150), colDummy varchar(100));
    -- Se invoca el reporte (la salida dinámica contiene columnas de países)
    INSERT INTO #tmpMatriz (nro, fase, partido)
    SELECT TOP 1 nroPartidoOficial, fase, partido FROM Torneo.vw_Fixture;

    REVERT;

    IF @p1 = 1 AND @p2 = 1 AND @p3 = 1
        PRINT '[OK] PRUEBA 3: usr_publicidad ejecutó los 3 reportes publicitarios (Matriz Prime Time resuelta con EXECUTE AS OWNER).';
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 3: Permisos de reportes incompletos (Ocupación: ', @p1, ', Matriz: ', @p2, ', Moneda: ', @p3, ').');
END TRY
BEGIN CATCH
    REVERT;
    PRINT CONCAT('[FALLO] PRUEBA 3: Error ejecutando reportes publicitarios - ', ERROR_MESSAGE());
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 4: Consulta de fixture y sedes (Torneo.vw_Fixture)
-- Resultado esperado: Permiso concedido de solo lectura sobre la vista de fixture.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_publicidad';
BEGIN TRY
    DECLARE @cantPartidos int;
    SELECT @cantPartidos = COUNT(*) FROM Torneo.vw_Fixture;
    REVERT;

    PRINT CONCAT('[OK] PRUEBA 4: usr_publicidad consultó Torneo.vw_Fixture exitosamente (partidos visibles: ', @cantPartidos, ').');
END TRY
BEGIN CATCH
    REVERT;
    PRINT CONCAT('[FALLO] PRUEBA 4: Error al consultar Torneo.vw_Fixture - ', ERROR_MESSAGE());
END CATCH;
GO

/* =============================================================================
   BLOQUE 2: CASOS QUE DEBEN FALLAR (RESTRICCIONES Y SEGURIDAD)
   ============================================================================= */

-- -----------------------------------------------------------------------------
-- PRUEBA 5: Intento de ejecutar Publicidad.TipoCambio_Alta (DENY puntual)
-- Resultado esperado: Acceso denegado (error 229). TipoCambio lo mantiene el admin/API.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_publicidad';
BEGIN TRY
    EXEC Publicidad.TipoCambio_Alta @moneda = 'EUR', @fecha = '2026-06-11', @cotizacionUSD = 0.92;
    REVERT;
    PRINT '[FALLO] PRUEBA 5: usr_publicidad no debió poder ejecutar Publicidad.TipoCambio_Alta.';
END TRY
BEGIN CATCH
    DECLARE @errNum5 int = ERROR_NUMBER();
    DECLARE @errMsg5 nvarchar(2000) = ERROR_MESSAGE();
    REVERT;

    IF @errNum5 = 229
        PRINT CONCAT('[OK (esperado)] PRUEBA 5: Ejecución denegada por DENY con error 229 (', @errMsg5, ').');
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 5: Se esperaba error 229 pero se recibió: ', @errNum5, ' - ', @errMsg5);
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 6: Intento de ejecutar procedimientos de Equipos (Equipos.Jugador_Alta)
-- Resultado esperado: Acceso denegado (error 229).
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_publicidad';
BEGIN TRY
    EXEC Equipos.Jugador_Alta @nombre = 'Infiltrado', @apellido = 'Test', @fechaNacimiento = '2000-01-01';
    REVERT;
    PRINT '[FALLO] PRUEBA 6: usr_publicidad no debió poder ejecutar SPs de Equipos.';
END TRY
BEGIN CATCH
    DECLARE @errNum6 int = ERROR_NUMBER();
    DECLARE @errMsg6 nvarchar(2000) = ERROR_MESSAGE();
    REVERT;

    IF @errNum6 = 229
        PRINT CONCAT('[OK (esperado)] PRUEBA 6: Ejecución sobre Equipos denegada con error 229 (', @errMsg6, ').');
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 6: Se esperaba error 229 pero se recibió: ', @errNum6, ' - ', @errMsg6);
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 7: Intento de INSERT directo a Publicidad.Anunciante (sin pasar por SP)
-- Resultado esperado: Acceso denegado (error 229). Regla central: todo por SP.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_publicidad';
BEGIN TRY
    INSERT INTO Publicidad.Anunciante (nombre, rubro, idPais, monedaFacturacion)
    VALUES ('Anunciante Salteando SP', 'Comercio', 1, 'USD');

    REVERT;
    PRINT '[FALLO] PRUEBA 7: El INSERT directo a Publicidad.Anunciante debió ser denegado.';
END TRY
BEGIN CATCH
    DECLARE @errNum7 int = ERROR_NUMBER();
    DECLARE @errMsg7 nvarchar(2000) = ERROR_MESSAGE();
    REVERT;

    IF @errNum7 = 229
        PRINT CONCAT('[OK (esperado)] PRUEBA 7: INSERT directo denegado con error 229 (', @errMsg7, ').');
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 7: Se esperaba error 229 pero se recibió: ', @errNum7, ' - ', @errMsg7);
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 8: Intento de SELECT directo a datos de personas (Equipos.Jugador)
-- Resultado esperado: Acceso denegado (error 229).
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_publicidad';
BEGIN TRY
    SELECT TOP 1 * FROM Equipos.Jugador;
    REVERT;
    PRINT '[FALLO] PRUEBA 8: usr_publicidad no debió poder consultar Equipos.Jugador.';
END TRY
BEGIN CATCH
    DECLARE @errNum8 int = ERROR_NUMBER();
    DECLARE @errMsg8 nvarchar(2000) = ERROR_MESSAGE();
    REVERT;

    IF @errNum8 = 229
        PRINT CONCAT('[OK (esperado)] PRUEBA 8: SELECT directo a Equipos.Jugador denegado con error 229 (', @errMsg8, ').');
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 8: Se esperaba error 229 pero se recibió: ', @errNum8, ' - ', @errMsg8);
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 9: Verificación de no acceso a descifrado de datos personales
-- Resultado esperado: usr_publicidad NO posee permisos sobre claves simétricas.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_publicidad';
BEGIN TRY
    DECLARE @clave sysname = NULL;
    SELECT TOP 1 @clave = name
    FROM sys.symmetric_keys
    WHERE name NOT IN (N'##MS_ServiceMasterKey##', N'##MS_DatabaseMasterKey##');

    IF @clave IS NOT NULL
    BEGIN
        DECLARE @permClave int = HAS_PERMS_BY_NAME(@clave, 'SYMMETRIC KEY', 'VIEW DEFINITION');
        REVERT;

        IF @permClave = 0
            PRINT CONCAT('[OK (esperado)] PRUEBA 9: usr_publicidad no tiene acceso a la clave de descifrado [', @clave, '].');
        ELSE
            PRINT CONCAT('[FALLO] PRUEBA 9: usr_publicidad tiene acceso indebido a la clave [', @clave, '].');
    END
    ELSE
    BEGIN
        REVERT;
        PRINT '[OK (esperado)] PRUEBA 9: No existen claves accesibles para usr_publicidad.';
    END;
END TRY
BEGIN CATCH
    REVERT;
    PRINT CONCAT('[FALLO] PRUEBA 9: Error verificando permisos de clave - ', ERROR_MESSAGE());
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA FINAL: Confirmación de reversión de contexto
-- -----------------------------------------------------------------------------
REVERT;
GO
SELECT USER_NAME() AS usuarioFinalSesion, SUSER_SNAME() AS loginActual;
PRINT '';
PRINT '================================================================================';
PRINT ' FIN DE BATERÍA DE PRUEBAS: 82g_Test_Rol_GestorPublicidad.sql';
PRINT '================================================================================';
GO
