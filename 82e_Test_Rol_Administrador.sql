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
               - Ve los datos personales en claro solo a través de los SP y reportes:
                 la clave la abre cada SP con EXECUTE AS OWNER y el rol no tiene
                 permisos sobre el certificado ni sobre la clave (plan de cifrado).
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

    -- Ejecución real (el resultado se muestra en la grilla). No se captura en una tabla
    -- temporal para no acoplar el test a las 30 columnas y tipos del reporte.
    EXEC Publicidad.Reporte_OcupacionPublicitaria @idPartido = 1;

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
-- PRUEBA 6: Descifrado controlado por SP (plan de cifrado, opción A)
-- Resultado esperado (después del script 70): usr_admin NO tiene permisos sobre el
-- certificado ni sobre la clave y, aun así, Equipos.Reporte_SeleccionesPlantillas devuelve
-- los nombres en claro, porque el SP descifra con EXECUTE AS OWNER.
-- Antes del script 70 (columnas todavía sin cifrar) la prueba se marca [OMITIDA].
-- Los objetos se buscan ANTES de suplantar: sin permisos el catálogo no los muestra.
-- -----------------------------------------------------------------------------
DECLARE @hayCifrado bit = CASE WHEN COL_LENGTH('Equipos.Jugador', 'nombreCif') IS NOT NULL THEN 1 ELSE 0 END;
DECLARE @hayCert    bit = CASE WHEN EXISTS (SELECT 1 FROM sys.certificates   WHERE name = N'CertDatosPersonales')  THEN 1 ELSE 0 END;
DECLARE @hayClave   bit = CASE WHEN EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'ClaveDatosPersonales') THEN 1 ELSE 0 END;
DECLARE @idSelPrueba int = (SELECT TOP 1 idSeleccion FROM Equipos.ListadoJugadores WHERE fechaBaja IS NULL ORDER BY idSeleccion);

IF @hayCifrado = 0
    PRINT '[OMITIDA] PRUEBA 6: las columnas todavía no están cifradas (pendiente de script 70 de Persona 1).';
ELSE IF @hayCert = 0 OR @hayClave = 0
    PRINT '[FALLO] PRUEBA 6: hay columnas cifradas pero no se encontraron CertDatosPersonales / ClaveDatosPersonales (actualizar los nombres si Persona 1 los cambió).';
ELSE
BEGIN
    -- Variable de tabla (y no temporal) para no depender de qué usuario creó la tabla
    DECLARE @plantillas TABLE (plantillas xml);

    EXECUTE AS USER = 'usr_admin';
    BEGIN TRY
        DECLARE @permCert  int = ISNULL(HAS_PERMS_BY_NAME(N'CertDatosPersonales',  'CERTIFICATE',   'CONTROL'), 0);
        DECLARE @permClave int = ISNULL(HAS_PERMS_BY_NAME(N'ClaveDatosPersonales', 'SYMMETRIC KEY', 'VIEW DEFINITION'), 0);

        INSERT INTO @plantillas EXEC Equipos.Reporte_SeleccionesPlantillas @idSeleccion = @idSelPrueba;
        REVERT;

        DECLARE @x xml = (SELECT TOP 1 plantillas FROM @plantillas);
        DECLARE @conNombre int = @x.value('count(//jugador/nombre[string-length(.) > 0])', 'int');

        IF @permCert = 0 AND @permClave = 0 AND @conNombre > 0
            PRINT CONCAT('[OK] PRUEBA 6: sin permisos sobre la clave, usr_admin ve ', @conNombre, ' nombres en claro a través del reporte.');
        ELSE
            PRINT CONCAT('[FALLO] PRUEBA 6: permisos sobre certificado: ', @permCert, ', sobre clave: ', @permClave, ', nombres en claro: ', ISNULL(@conNombre, 0), '.');
    END TRY
    BEGIN CATCH
        REVERT;
        PRINT CONCAT('[FALLO] PRUEBA 6: Error ejecutando el reporte con cifrado - ', ERROR_MESSAGE());
    END CATCH;
END;
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
-- PRUEBA 10: Intento de SELECT directo a la vista de descifrado Equipos.vw_Jugador
-- Resultado esperado (después del script 70): acceso denegado (error 229). Los nombres se
-- obtienen solo a través de los SP y reportes. Antes del 70 la vista no existe: [OMITIDA].
-- -----------------------------------------------------------------------------
IF OBJECT_ID('Equipos.vw_Jugador', 'V') IS NULL
    PRINT '[OMITIDA] PRUEBA 10: Equipos.vw_Jugador no existe (pendiente de script 70 de Persona 1).';
ELSE
BEGIN
    EXECUTE AS USER = 'usr_admin';
    BEGIN TRY
        SELECT TOP 1 * FROM Equipos.vw_Jugador;
        REVERT;
        PRINT '[FALLO] PRUEBA 10: usr_admin no debió poder leer Equipos.vw_Jugador.';
    END TRY
    BEGIN CATCH
        DECLARE @errNum10 int = ERROR_NUMBER();
        DECLARE @errMsg10 nvarchar(2000) = ERROR_MESSAGE();
        REVERT;

        IF @errNum10 = 229
            PRINT CONCAT('[OK (esperado)] PRUEBA 10: SELECT a la vista de descifrado denegado con error 229 (', @errMsg10, ').');
        ELSE
            PRINT CONCAT('[FALLO] PRUEBA 10: Se esperaba error 229 pero se recibió: ', @errNum10, ' - ', @errMsg10);
    END CATCH;
END;
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
