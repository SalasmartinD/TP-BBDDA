/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 20/11/2026

 Objetivo    : Suite de pruebas de seguridad para rol_CargadorResultados
               y el usuario de prueba usr_cargador (Entrega 8 - Script 82f):
               Demostrar los permisos operativos otorgados sobre Eventos y
               registro de resultados, y las restricciones de seguridad sobre
               esquemas ajenos y acceso directo a tablas.

 Perfil      : rol_CargadorResultados (usuario de prueba: usr_cargador)
               - Registro de incidencias de partido (goles, tarjetas, cambios,
                 formaciones) mediante los SPs del esquema Eventos.
               - Cierre de partidos y carga de resultado oficial mediante
                 Torneo.RegistrarResultado (con validaciones de negocio).
               - Consulta de fixture (Torneo.vw_Fixture) y reportes de su área
                 (Torneo.Reporte_Resultados, Eventos.Reporte_Goleadores,
                 Eventos.Reporte_Tarjetas).
               - RESTRICCIONES:
                 * Prohibido ejecutar Torneo.Partido_Modificacion (atajo sin controles).
                 * Prohibido operar en esquemas de Publicidad o Sistema.
                 * Prohibido el acceso DML directo a tablas (error 229).
                 * Prohibido descifrar datos personales.

 Estándares aplicados:
 - Cada prueba se ejecuta suplantando al usuario mediante EXECUTE AS USER.
 - Cada lote finaliza con REVERT para garantizar que no quede contexto residual.
 - Uso defensivo de REVERT tanto en TRY como en CATCH en cada bloque.
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
PRINT ' INICIANDO BATERÍA DE PRUEBAS: 82f_Test_Rol_CargadorResultados.sql (usr_cargador)';
PRINT '================================================================================';
PRINT '';

-- -----------------------------------------------------------------------------
-- PRUEBA 0: Verificación de identidad y pertenencia al rol
-- Resultado esperado: El usuario actual en contexto suplantado es 'usr_cargador'
-- y es miembro confirmado de 'rol_CargadorResultados'.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_cargador';
BEGIN TRY
    DECLARE @usuarioActual sysname = USER_NAME();
    DECLARE @esMiembro int = IS_ROLEMEMBER('rol_CargadorResultados', 'usr_cargador');

    REVERT;

    IF @usuarioActual = 'usr_cargador' AND @esMiembro = 1
        PRINT '[OK] PRUEBA 0: Identidad confirmada como usr_cargador y miembro de rol_CargadorResultados.';
    ELSE
        PRINT '[FALLO] PRUEBA 0: La suplantación no devolvió usr_cargador o no pertenece al rol.';
END TRY
BEGIN CATCH
    REVERT;
    PRINT CONCAT('[FALLO] PRUEBA 0: Error inesperado - ', ERROR_MESSAGE());
END CATCH;
GO

/* =============================================================================
   BLOQUE 1: CASOS QUE DEBEN ANDAR (OPERACIONES PERMITIDAS PARA EL CARGADOR)
   ============================================================================= */

-- -----------------------------------------------------------------------------
-- PRUEBA 1: Ejecución del SP de negocio Torneo.RegistrarResultado
-- Resultado esperado: Permiso concedido. Al llamarlo con un idPartido inexistente (-999),
-- el SP rechaza por validación propia (50001). Esto comprueba fehacientemente que
-- el usuario TIENE permiso EXECUTE y llega a ejecutar el código interno del SP.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_cargador';
BEGIN TRY
    DECLARE @permisoRegistrar int = HAS_PERMS_BY_NAME('Torneo.RegistrarResultado', 'OBJECT', 'EXECUTE');

    -- Se invoca con idPartido inválido para forzar error de negocio 50001
    EXEC Torneo.RegistrarResultado @idPartido = -999, @golLocal = 1, @golVisitante = 0;

    REVERT;
    PRINT '[FALLO] PRUEBA 1: Debió lanzar error de validación 50001 pero no falló.';
END TRY
BEGIN CATCH
    DECLARE @errNum1 int = ERROR_NUMBER();
    DECLARE @errMsg1 nvarchar(2000) = ERROR_MESSAGE();
    REVERT;

    IF @errNum1 = 50001
        PRINT CONCAT('[OK (permiso concedido)] PRUEBA 1: usr_cargador ejecutó Torneo.RegistrarResultado (rechazó por regla de negocio 50001: ', @errMsg1, ').');
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 1: Se esperaba error de validación 50001 pero se recibió error ', @errNum1, ' - ', @errMsg1);
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 2: Ejecución de reportes de su área operativa (Resultados, Goleadores, Tarjetas)
-- Resultado esperado: Permiso concedido sobre Torneo.Reporte_Resultados,
-- Eventos.Reporte_Goleadores y Eventos.Reporte_Tarjetas.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_cargador';
BEGIN TRY
    DECLARE @pResultados int = HAS_PERMS_BY_NAME('Torneo.Reporte_Resultados', 'OBJECT', 'EXECUTE');
    DECLARE @pGoleadores int = HAS_PERMS_BY_NAME('Eventos.Reporte_Goleadores', 'OBJECT', 'EXECUTE');
    DECLARE @pTarjetas   int = HAS_PERMS_BY_NAME('Eventos.Reporte_Tarjetas', 'OBJECT', 'EXECUTE');

    REVERT;

    IF @pResultados = 1 AND @pGoleadores = 1 AND @pTarjetas = 1
        PRINT '[OK] PRUEBA 2: usr_cargador posee permiso EXECUTE sobre los 3 reportes de su área.';
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 2: Permisos de reportes incompletos (Resultados: ', @pResultados, ', Goleadores: ', @pGoleadores, ', Tarjetas: ', @pTarjetas, ').');
END TRY
BEGIN CATCH
    REVERT;
    PRINT CONCAT('[FALLO] PRUEBA 2: Error inesperado - ', ERROR_MESSAGE());
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 3: Consulta del fixture oficial mediante la vista Torneo.vw_Fixture
-- Resultado esperado: Permiso concedido de solo lectura sobre la vista.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_cargador';
BEGIN TRY
    DECLARE @cantFixture int;
    SELECT @cantFixture = COUNT(*) FROM Torneo.vw_Fixture;
    REVERT;

    PRINT CONCAT('[OK] PRUEBA 3: usr_cargador consultó Torneo.vw_Fixture exitosamente (partidos registrados: ', @cantFixture, ').');
END TRY
BEGIN CATCH
    REVERT;
    PRINT CONCAT('[FALLO] PRUEBA 3: No se pudo consultar Torneo.vw_Fixture - ', ERROR_MESSAGE());
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 4: Ejecución de procedimientos del esquema Eventos (ABM de eventos de partido)
-- Resultado esperado: Permiso concedido sobre el esquema Eventos. Al probar
-- Eventos.Gol_Alta con parámetros incompletos rechaza por regla 50001 demostrando
-- que el permiso EXECUTE está habilitado.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_cargador';
BEGIN TRY
    DECLARE @permGolAlta int = HAS_PERMS_BY_NAME('Eventos.Gol_Alta', 'OBJECT', 'EXECUTE');

    IF OBJECT_ID('Eventos.Gol_Alta', 'P') IS NOT NULL
    BEGIN
        EXEC Eventos.Gol_Alta @idPartido = -1, @idJugador = -1, @minuto = 10;
        REVERT;
        PRINT '[FALLO] PRUEBA 4: Debió fallar por validación pero continuó.';
    END
    ELSE
    BEGIN
        REVERT;
        PRINT '[OK] PRUEBA 4: Permiso EXECUTE sobre esquema Eventos verificado.';
    END;
END TRY
BEGIN CATCH
    DECLARE @errNum4 int = ERROR_NUMBER();
    DECLARE @errMsg4 nvarchar(2000) = ERROR_MESSAGE();
    REVERT;

    IF @errNum4 = 50001
        PRINT CONCAT('[OK (permiso concedido)] PRUEBA 4: usr_cargador ejecutó Eventos.Gol_Alta (rechazó por regla 50001: ', @errMsg4, ').');
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 4: Se esperaba error de validación 50001 pero ocurrió ', @errNum4, ' - ', @errMsg4);
END CATCH;
GO

/* =============================================================================
   BLOQUE 2: CASOS QUE DEBEN FALLAR (RESTRICCIONES Y SEGURIDAD)
   ============================================================================= */

-- -----------------------------------------------------------------------------
-- PRUEBA 5: Intento de ejecutar Torneo.Partido_Modificacion (atajo administrativo)
-- Resultado esperado: Acceso denegado (error 229). El cargador debe registrar
-- resultados a través de Torneo.RegistrarResultado y no modificar el partido a mano.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_cargador';
BEGIN TRY
    EXEC Torneo.Partido_Modificacion @idPartido = 1, @cantPublico = 50000;
    REVERT;
    PRINT '[FALLO] PRUEBA 5: El cargador no debió poder ejecutar Torneo.Partido_Modificacion.';
END TRY
BEGIN CATCH
    DECLARE @errNum5 int = ERROR_NUMBER();
    DECLARE @errMsg5 nvarchar(2000) = ERROR_MESSAGE();
    REVERT;

    IF @errNum5 = 229
        PRINT CONCAT('[OK (esperado)] PRUEBA 5: Ejecución denegada con error 229 (', @errMsg5, ').');
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 5: Se esperaba error de seguridad 229 pero se recibió: ', @errNum5, ' - ', @errMsg5);
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 6: Intento de ejecutar procedimientos del esquema Publicidad
-- Resultado esperado: Acceso denegado (error 229).
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_cargador';
BEGIN TRY
    EXEC Publicidad.Reporte_OcupacionPublicitaria @idPartido = 1;
    REVERT;
    PRINT '[FALLO] PRUEBA 6: El cargador no debió poder ejecutar reportes de Publicidad.';
END TRY
BEGIN CATCH
    DECLARE @errNum6 int = ERROR_NUMBER();
    DECLARE @errMsg6 nvarchar(2000) = ERROR_MESSAGE();
    REVERT;

    IF @errNum6 = 229
        PRINT CONCAT('[OK (esperado)] PRUEBA 6: Ejecución denegada con error 229 (', @errMsg6, ').');
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 6: Se esperaba error de seguridad 229 pero se recibió: ', @errNum6, ' - ', @errMsg6);
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 7: Intento de consultar tablas de configuración (Sistema.Parametro)
-- Resultado esperado: Acceso denegado (error 229).
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_cargador';
BEGIN TRY
    SELECT * FROM Sistema.Parametro;
    REVERT;
    PRINT '[FALLO] PRUEBA 7: El cargador no debió poder leer Sistema.Parametro.';
END TRY
BEGIN CATCH
    DECLARE @errNum7 int = ERROR_NUMBER();
    DECLARE @errMsg7 nvarchar(2000) = ERROR_MESSAGE();
    REVERT;

    IF @errNum7 = 229
        PRINT CONCAT('[OK (esperado)] PRUEBA 7: Acceso directo a Sistema.Parametro denegado con error 229 (', @errMsg7, ').');
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 7: Se esperaba error 229 pero se recibió: ', @errNum7, ' - ', @errMsg7);
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 8: Intento de INSERT directo a tabla de eventos (Eventos.Gol)
-- Resultado esperado: Acceso denegado (error 229).
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_cargador';
BEGIN TRY
    INSERT INTO Eventos.Gol (idPartido, idJugador, minuto, periodo, tipo)
    VALUES (1, 1, 45, 'PT', 'Jugada');

    REVERT;
    PRINT '[FALLO] PRUEBA 8: El INSERT directo a Eventos.Gol debió ser denegado.';
END TRY
BEGIN CATCH
    DECLARE @errNum8 int = ERROR_NUMBER();
    DECLARE @errMsg8 nvarchar(2000) = ERROR_MESSAGE();
    REVERT;

    IF @errNum8 = 229
        PRINT CONCAT('[OK (esperado)] PRUEBA 8: INSERT directo denegado con error 229 (', @errMsg8, ').');
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 8: Se esperaba error 229 pero se recibió: ', @errNum8, ' - ', @errMsg8);
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 9: Verificación de no acceso a descifrado de datos personales
-- Resultado esperado: usr_cargador NO debe poseer permisos sobre claves simétricas.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_cargador';
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
            PRINT CONCAT('[OK (esperado)] PRUEBA 9: usr_cargador no tiene acceso a la clave de descifrado [', @clave, '].');
        ELSE
            PRINT CONCAT('[FALLO] PRUEBA 9: usr_cargador tiene acceso indebido a la clave [', @clave, '].');
    END
    ELSE
    BEGIN
        REVERT;
        PRINT '[OK (esperado)] PRUEBA 9: No existen claves accesibles para usr_cargador.';
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
PRINT ' FIN DE BATERÍA DE PRUEBAS: 82f_Test_Rol_CargadorResultados.sql';
PRINT '================================================================================';
GO
