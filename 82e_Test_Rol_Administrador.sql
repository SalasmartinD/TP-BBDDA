/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 20/11/2026

 Objetivo    : Suite de pruebas de seguridad para el rol_Administrador
               y el usuario de prueba usr_admin (Entrega 8 - Script 82e):
               Demostrar los permisos que efectivamente posee y los que tiene
               denegados conforme a la matriz de seguridad del sistema.

 Perfil      : rol_Administrador (usuario de prueba: usr_admin)
               - Gestión integral mediante Procedimientos Almacenados sobre
                 todos los esquemas (Torneo, Equipos, Arbitraje, Eventos,
                 Publicidad, Sistema).
               - Consulta de vistas del sistema y parámetros reglamentarios.
               - Acceso a claves de cifrado y descifrado de datos sensibles.
               - REGLA GENERAL: Acceso directo DML (INSERT/UPDATE/DELETE)
                 a tablas bloqueado (todo cambio se realiza por SP).

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
PRINT ' INICIANDO BATERÍA DE PRUEBAS: 82e_Test_Rol_Administrador.sql (usr_admin)';
PRINT '================================================================================';
PRINT '';

-- -----------------------------------------------------------------------------
-- PRUEBA 0: Verificación de identidad y pertenencia al rol
-- Resultado esperado: El usuario actual en contexto suplantado es 'usr_admin'
-- y es miembro confirmado de 'rol_Administrador'.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_admin';
BEGIN TRY
    DECLARE @usuarioActual sysname = USER_NAME();
    DECLARE @esMiembro int = IS_ROLEMEMBER('rol_Administrador', 'usr_admin');

    REVERT;

    IF @usuarioActual = 'usr_admin' AND @esMiembro = 1
        PRINT '[OK] PRUEBA 0: Identidad confirmada como usr_admin y miembro de rol_Administrador.';
    ELSE
        PRINT '[FALLO] PRUEBA 0: La suplantación no devolvió usr_admin o no pertenece al rol.';
END TRY
BEGIN CATCH
    REVERT;
    PRINT CONCAT('[FALLO] PRUEBA 0: Error inesperado - ', ERROR_MESSAGE());
END CATCH;
GO

/* =============================================================================
   BLOQUE 1: CASOS QUE DEBEN ANDAR (OPERACIONES PERMITIDAS PARA ADMINISTRADOR)
   ============================================================================= */

-- -----------------------------------------------------------------------------
-- PRUEBA 1: Ejecución de reportes del esquema Publicidad
-- Resultado esperado: Permiso concedido. Se ejecuta exitosamente.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_admin';
BEGIN TRY
    DECLARE @tienePermiso int = HAS_PERMS_BY_NAME('Publicidad.Reporte_OcupacionPublicitaria', 'OBJECT', 'EXECUTE');

    -- Ejecución de prueba con tabla temporal para descartar salida
    DROP TABLE IF EXISTS #tmpOcup;
    CREATE TABLE #tmpOcup (idPartido int, nro int, fase varchar(60), sede varchar(80), ciudad varchar(60),
                           paisSede varchar(60), selL varchar(60), selV varchar(60), part varchar(150),
                           fUTC datetime2(0), hLocal datetime2(0), estPart varchar(15), idUbic tinyint,
                           nomUbic varchar(50), anun nvarchar(100), rubro varchar(50), paisAnun varchar(60),
                           camp nvarchar(60), pieza nvarchar(80), idio varchar(30), crit varchar(50),
                           estExh varchar(20), tarUSD decimal(12,2), espOcup int, espTot int, porc decimal(5,2),
                           ingExh decimal(12,2), ingConf decimal(12,2), totIng decimal(12,2), acumSede decimal(12,2));
    INSERT INTO #tmpOcup
    EXEC Publicidad.Reporte_OcupacionPublicitaria @idPartido = 1;
    DROP TABLE IF EXISTS #tmpOcup;

    REVERT;

    IF @tienePermiso = 1
        PRINT '[OK] PRUEBA 1: usr_admin puede ejecutar Publicidad.Reporte_OcupacionPublicitaria.';
    ELSE
        PRINT '[FALLO] PRUEBA 1: HAS_PERMS_BY_NAME indicó falta de permiso EXECUTE.';
END TRY
BEGIN CATCH
    REVERT;
    PRINT CONCAT('[FALLO] PRUEBA 1: Error al ejecutar procedimiento - ', ERROR_MESSAGE());
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 2: Ejecución de reportes de Torneo y fixture
-- Resultado esperado: Permiso concedido sobre Torneo.Reporte_Resultados y Torneo.vw_Fixture.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_admin';
BEGIN TRY
    DECLARE @permisoSP int = HAS_PERMS_BY_NAME('Torneo.Reporte_Resultados', 'OBJECT', 'EXECUTE');
    DECLARE @permisoVista int = HAS_PERMS_BY_NAME('Torneo.vw_Fixture', 'OBJECT', 'SELECT');

    -- Lectura de la vista
    DECLARE @cantFixture int;
    SELECT @cantFixture = COUNT(*) FROM Torneo.vw_Fixture;

    REVERT;

    IF @permisoSP = 1 AND @permisoVista = 1
        PRINT CONCAT('[OK] PRUEBA 2: usr_admin puede consultar vistas de Torneo y reportes (partidos en vista: ', @cantFixture, ').');
    ELSE
        PRINT '[FALLO] PRUEBA 2: Falta permiso sobre Torneo.Reporte_Resultados o Torneo.vw_Fixture.';
END TRY
BEGIN CATCH
    REVERT;
    PRINT CONCAT('[FALLO] PRUEBA 2: Error en consulta de Torneo - ', ERROR_MESSAGE());
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 3: Ejecución de reportes de Eventos y Arbitraje
-- Resultado esperado: Permiso concedido sobre Eventos.Reporte_Goleadores y Arbitraje.Reporte_DesignacionesArbitrales.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_admin';
BEGIN TRY
    DECLARE @permGoleadores int = HAS_PERMS_BY_NAME('Eventos.Reporte_Goleadores', 'OBJECT', 'EXECUTE');
    DECLARE @permArbitral int = HAS_PERMS_BY_NAME('Arbitraje.Reporte_DesignacionesArbitrales', 'OBJECT', 'EXECUTE');

    REVERT;

    IF @permGoleadores = 1 AND @permArbitral = 1
        PRINT '[OK] PRUEBA 3: usr_admin posee permisos de ejecución sobre reportes de Eventos y Arbitraje.';
    ELSE
        PRINT '[FALLO] PRUEBA 3: Permisos de Eventos o Arbitraje incompletos.';
END TRY
BEGIN CATCH
    REVERT;
    PRINT CONCAT('[FALLO] PRUEBA 3: Error inesperado - ', ERROR_MESSAGE());
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 4: Ejecución de SP administrativo del esquema Sistema
-- Resultado esperado: Permiso concedido. Al probar Sistema.CrearUsuarioPrueba con
-- un rol inexistente, el SP debe ejecutarse y rechazar por validación de negocio (50001).
-- Esto demuestra que el usuario tiene EXECUTE y no falla por permisos (error 229).
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_admin';
BEGIN TRY
    EXEC Sistema.CrearUsuarioPrueba @usuario = 'usr_temp_invalido', @rol = 'rol_Inexistente_XYZ';
    REVERT;
    PRINT '[FALLO] PRUEBA 4: Debió fallar por rol inexistente pero continuó.';
END TRY
BEGIN CATCH
    DECLARE @errNum int = ERROR_NUMBER();
    DECLARE @errMsg nvarchar(2000) = ERROR_MESSAGE();
    REVERT;

    IF @errNum = 50001
        PRINT CONCAT('[OK] PRUEBA 4: usr_admin ejecutó Sistema.CrearUsuarioPrueba (falló por regla de negocio esperada 50001: ', @errMsg, ').');
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 4: Se esperaba error 50001 pero ocurrió error ', @errNum, ' - ', @errMsg);
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 5: Lectura sobre parámetros del sistema (Sistema.Parametro)
-- Resultado esperado: Permiso concedido. Puede leer la configuración del sistema.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_admin';
BEGIN TRY
    DECLARE @cantParams int;
    SELECT @cantParams = COUNT(*) FROM Sistema.Parametro;
    REVERT;

    PRINT CONCAT('[OK] PRUEBA 5: usr_admin consultó Sistema.Parametro (registros leídos: ', @cantParams, ').');
END TRY
BEGIN CATCH
    REVERT;
    PRINT CONCAT('[FALLO] PRUEBA 5: No se pudo consultar Sistema.Parametro - ', ERROR_MESSAGE());
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 6: Permiso sobre claves simétricas de descifrado (Entrega 8)
-- Resultado esperado: Permiso VIEW DEFINITION sobre clave de cifrado si existe.
-- Si la clave no fue creada todavía por Persona 1, la prueba se marca [OMITIDA].
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_admin';
BEGIN TRY
    DECLARE @clave sysname = NULL;
    SELECT TOP 1 @clave = name
    FROM sys.symmetric_keys
    WHERE name NOT IN (N'##MS_ServiceMasterKey##', N'##MS_DatabaseMasterKey##');

    IF @clave IS NOT NULL
    BEGIN
        DECLARE @tienePermClave int = HAS_PERMS_BY_NAME(@clave, 'SYMMETRIC KEY', 'VIEW DEFINITION');
        REVERT;

        IF @tienePermClave = 1
            PRINT CONCAT('[OK] PRUEBA 6: usr_admin posee permiso VIEW DEFINITION sobre clave [', @clave, '].');
        ELSE
            PRINT CONCAT('[FALLO] PRUEBA 6: usr_admin no posee permiso sobre la clave [', @clave, '].');
    END
    ELSE
    BEGIN
        REVERT;
        PRINT '[OMITIDA] PRUEBA 6: No se detectó clave simétrica de usuario en la base (pendiente de script 70 de Persona 1).';
    END;
END TRY
BEGIN CATCH
    REVERT;
    PRINT CONCAT('[FALLO] PRUEBA 6: Error verificando permisos de clave - ', ERROR_MESSAGE());
END CATCH;
GO

/* =============================================================================
   BLOQUE 2: CASOS QUE DEBEN FALLAR (DENEGACIÓN DE ACCESO DIRECTO A TABLAS)
   ============================================================================= */

-- -----------------------------------------------------------------------------
-- PRUEBA 7: Intento de INSERT directo a Publicidad.Anunciante
-- Resultado esperado: Acceso denegado (error 229). Los cambios deben pasar por SP.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_admin';
BEGIN TRY
    INSERT INTO Publicidad.Anunciante (nombre, rubro, idPais, monedaFacturacion)
    VALUES ('Anunciante Ilegal Directo', 'Tecnología', 1, 'USD');

    REVERT;
    PRINT '[FALLO] PRUEBA 7: El INSERT directo a tabla debió ser denegado.';
END TRY
BEGIN CATCH
    DECLARE @errNum7 int = ERROR_NUMBER();
    DECLARE @errMsg7 nvarchar(2000) = ERROR_MESSAGE();
    REVERT;

    IF @errNum7 = 229
        PRINT CONCAT('[OK (esperado)] PRUEBA 7: Acceso directo denegado con error 229 (', @errMsg7, ').');
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 7: Se esperaba error de seguridad 229 pero se recibió: ', @errNum7, ' - ', @errMsg7);
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 8: Intento de UPDATE directo a Torneo.Partido
-- Resultado esperado: Acceso denegado (error 229).
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_admin';
BEGIN TRY
    UPDATE Torneo.Partido
    SET cantPublico = 99999
    WHERE idPartido = 1;

    REVERT;
    PRINT '[FALLO] PRUEBA 8: El UPDATE directo a tabla debió ser denegado.';
END TRY
BEGIN CATCH
    DECLARE @errNum8 int = ERROR_NUMBER();
    DECLARE @errMsg8 nvarchar(2000) = ERROR_MESSAGE();
    REVERT;

    IF @errNum8 = 229
        PRINT CONCAT('[OK (esperado)] PRUEBA 8: Acceso directo denegado con error 229 (', @errMsg8, ').');
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 8: Se esperaba error de seguridad 229 pero se recibió: ', @errNum8, ' - ', @errMsg8);
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 9: Intento de DELETE directo a Publicidad.PiezaContenido
-- Resultado esperado: Acceso denegado (error 229).
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_admin';
BEGIN TRY
    DELETE FROM Publicidad.PiezaContenido WHERE id = 1;

    REVERT;
    PRINT '[FALLO] PRUEBA 9: El DELETE directo a tabla debió ser denegado.';
END TRY
BEGIN CATCH
    DECLARE @errNum9 int = ERROR_NUMBER();
    DECLARE @errMsg9 nvarchar(2000) = ERROR_MESSAGE();
    REVERT;

    IF @errNum9 = 229
        PRINT CONCAT('[OK (esperado)] PRUEBA 9: Acceso directo denegado con error 229 (', @errMsg9, ').');
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 9: Se esperaba error de seguridad 229 pero se recibió: ', @errNum9, ' - ', @errMsg9);
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
PRINT ' FIN DE BATERÍA DE PRUEBAS: 82e_Test_Rol_Administrador.sql';
PRINT '================================================================================';
GO
