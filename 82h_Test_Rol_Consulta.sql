/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 20/11/2026

 Objetivo    : Suite de pruebas de seguridad para rol_Consulta y el usuario
               de prueba usr_consulta (Entrega 8 - Script 82h):
               Demostrar el perfil de solo lectura/reportes analíticos y las
               restricciones estrictas que impiden cualquier modificación,
               ejecución de SPs de ABM o acceso directo a tablas.

 Perfil      : rol_Consulta (usuario de prueba: usr_consulta)
               - Ejecución de los ocho (8) reportes analíticos del sistema:
                 1. Torneo.Reporte_Resultados
                 2. Equipos.Reporte_SeleccionesPlantillas
                 3. Eventos.Reporte_Goleadores
                 4. Eventos.Reporte_Tarjetas
                 5. Arbitraje.Reporte_DesignacionesArbitrales
                 6. Publicidad.Reporte_OcupacionPublicitaria
                 7. Publicidad.Reporte_MatrizPrimeTime
                 8. Publicidad.Reporte_IngresosPorMoneda
               - Consulta de la vista oficial Torneo.vw_Fixture.
               - Perfil base para la conexión de herramientas BI (Entrega 9).
               - RESTRICCIONES:
                 * Prohibida la ejecución de cualquier SP de ABM o modificación.
                 * Prohibido el acceso directo SELECT a tablas subyacentes.
                 * Prohibido cualquier comando DML (INSERT, UPDATE, DELETE).
                 * Prohibido descifrar datos personales.

 Estándares aplicados:
 - Cada prueba se ejecuta suplantando al usuario mediante EXECUTE AS USER.
 - Cada lote finaliza con REVERT para garantizar que no quede contexto residual.
 - Uso defensivo de REVERT tanto en TRY como en CATCH en cada bloque.
 - Demostración del funcionamiento de WITH EXECUTE AS OWNER en la matriz pivotada.
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
PRINT ' INICIANDO BATERÍA DE PRUEBAS: 82h_Test_Rol_Consulta.sql (usr_consulta)';
PRINT '================================================================================';
PRINT '';

-- -----------------------------------------------------------------------------
-- PRUEBA 0: Verificación de identidad y pertenencia al rol
-- Resultado esperado: El usuario actual en contexto suplantado es 'usr_consulta'
-- y es miembro confirmado de 'rol_Consulta'.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_consulta';
BEGIN TRY
    DECLARE @usuarioActual sysname = USER_NAME();
    DECLARE @esMiembro int = IS_ROLEMEMBER('rol_Consulta', 'usr_consulta');

    REVERT;

    IF @usuarioActual = 'usr_consulta' AND @esMiembro = 1
        PRINT '[OK] PRUEBA 0: Identidad confirmada como usr_consulta y miembro de rol_Consulta.';
    ELSE
        PRINT '[FALLO] PRUEBA 0: La suplantación no devolvió usr_consulta o no pertenece al rol.';
END TRY
BEGIN CATCH
    REVERT;
    PRINT CONCAT('[FALLO] PRUEBA 0: Error inesperado - ', ERROR_MESSAGE());
END CATCH;
GO

/* =============================================================================
   BLOQUE 1: CASOS QUE DEBEN ANDAR (EJECUCIÓN DE LOS 8 REPORTES Y VISTAS)
   ============================================================================= */

-- -----------------------------------------------------------------------------
-- PRUEBA 1: Verificación de permisos EXECUTE sobre los 8 reportes oficiales
-- Resultado esperado: HAS_PERMS_BY_NAME devuelve 1 para los 8 procedimientos.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_consulta';
BEGIN TRY
    DECLARE @p1 int = HAS_PERMS_BY_NAME('Torneo.Reporte_Resultados', 'OBJECT', 'EXECUTE');
    DECLARE @p2 int = HAS_PERMS_BY_NAME('Equipos.Reporte_SeleccionesPlantillas', 'OBJECT', 'EXECUTE');
    DECLARE @p3 int = HAS_PERMS_BY_NAME('Eventos.Reporte_Goleadores', 'OBJECT', 'EXECUTE');
    DECLARE @p4 int = HAS_PERMS_BY_NAME('Eventos.Reporte_Tarjetas', 'OBJECT', 'EXECUTE');
    DECLARE @p5 int = HAS_PERMS_BY_NAME('Arbitraje.Reporte_DesignacionesArbitrales', 'OBJECT', 'EXECUTE');
    DECLARE @p6 int = HAS_PERMS_BY_NAME('Publicidad.Reporte_OcupacionPublicitaria', 'OBJECT', 'EXECUTE');
    DECLARE @p7 int = HAS_PERMS_BY_NAME('Publicidad.Reporte_MatrizPrimeTime', 'OBJECT', 'EXECUTE');
    DECLARE @p8 int = HAS_PERMS_BY_NAME('Publicidad.Reporte_IngresosPorMoneda', 'OBJECT', 'EXECUTE');

    REVERT;

    IF @p1=1 AND @p2=1 AND @p3=1 AND @p4=1 AND @p5=1 AND @p6=1 AND @p7=1 AND @p8=1
        PRINT '[OK] PRUEBA 1: usr_consulta posee permiso EXECUTE confirmado sobre los ocho (8) reportes.';
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 1: Permisos incompletos sobre reportes (', @p1,@p2,@p3,@p4,@p5,@p6,@p7,@p8, ').');
END TRY
BEGIN CATCH
    REVERT;
    PRINT CONCAT('[FALLO] PRUEBA 1: Error inesperado - ', ERROR_MESSAGE());
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 2: Ejecución real del reporte con SQL dinámico (Publicidad.Reporte_MatrizPrimeTime)
-- Resultado esperado: Ejecución exitosa. Demuestra que la declaración WITH EXECUTE AS OWNER
-- resolvió el corte de encadenamiento de propiedad para usr_consulta sin otorgarle
-- permisos directos de SELECT a las tablas del PIVOT.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_consulta';
BEGIN TRY
    -- Se ejecuta el reporte para verificar que no surja error 229
    EXEC Publicidad.Reporte_MatrizPrimeTime @idPartido = 1;

    REVERT;
    PRINT '[OK] PRUEBA 2: Publicidad.Reporte_MatrizPrimeTime ejecutado exitosamente con WITH EXECUTE AS OWNER.';
END TRY
BEGIN CATCH
    REVERT;
    PRINT CONCAT('[FALLO] PRUEBA 2: Error ejecutando matriz dinámica - ', ERROR_MESSAGE());
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 3: Ejecución de reportes analíticos de otras áreas (Torneo y Eventos)
-- Resultado esperado: Ejecución exitosa de Torneo.Reporte_Resultados y Eventos.Reporte_Goleadores.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_consulta';
BEGIN TRY
    EXEC Torneo.Reporte_Resultados;
    EXEC Eventos.Reporte_Goleadores;

    REVERT;
    PRINT '[OK] PRUEBA 3: usr_consulta ejecutó exitosamente Torneo.Reporte_Resultados y Eventos.Reporte_Goleadores.';
END TRY
BEGIN CATCH
    REVERT;
    PRINT CONCAT('[FALLO] PRUEBA 3: Error en ejecución de reportes - ', ERROR_MESSAGE());
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 4: Consulta de fixture oficial mediante la vista Torneo.vw_Fixture
-- Resultado esperado: Permiso SELECT concedido.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_consulta';
BEGIN TRY
    DECLARE @cantPartidos int;
    SELECT @cantPartidos = COUNT(*) FROM Torneo.vw_Fixture;
    REVERT;

    PRINT CONCAT('[OK] PRUEBA 4: usr_consulta consultó Torneo.vw_Fixture exitosamente (partidos visibles: ', @cantPartidos, ').');
END TRY
BEGIN CATCH
    REVERT;
    PRINT CONCAT('[FALLO] PRUEBA 4: No se pudo consultar Torneo.vw_Fixture - ', ERROR_MESSAGE());
END CATCH;
GO

/* =============================================================================
   BLOQUE 2: CASOS QUE DEBEN FALLAR (INTENTOS DE MODIFICACIÓN Y ACCESO A TABLAS)
   ============================================================================= */

-- -----------------------------------------------------------------------------
-- PRUEBA 5: Intento de ejecutar un SP de alta (Publicidad.Anunciante_Alta)
-- Resultado esperado: Acceso denegado (error 229).
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_consulta';
BEGIN TRY
    EXEC Publicidad.Anunciante_Alta @nombre = 'Anunciante Ilegal', @idPais = 1;
    REVERT;
    PRINT '[FALLO] PRUEBA 5: usr_consulta no debió poder ejecutar Publicidad.Anunciante_Alta.';
END TRY
BEGIN CATCH
    DECLARE @errNum5 int = ERROR_NUMBER();
    DECLARE @errMsg5 nvarchar(2000) = ERROR_MESSAGE();
    REVERT;

    IF @errNum5 = 229
        PRINT CONCAT('[OK (esperado)] PRUEBA 5: Ejecución denegada con error 229 (', @errMsg5, ').');
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 5: Se esperaba error 229 pero se recibió: ', @errNum5, ' - ', @errMsg5);
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 6: Intento de ejecutar un SP de eventos (Eventos.Gol_Alta)
-- Resultado esperado: Acceso denegado (error 229).
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_consulta';
BEGIN TRY
    EXEC Eventos.Gol_Alta
        @idPartido  = 1,
        @idJugador  = 1,
        @minuto     = 15,
        @tipo       = 'Jugada',
        @idPeriodo  = 1;
    REVERT;
    PRINT '[FALLO] PRUEBA 6: usr_consulta no debió poder ejecutar SPs de eventos.';
END TRY
BEGIN CATCH
    DECLARE @errNum6 int = ERROR_NUMBER();
    DECLARE @errMsg6 nvarchar(2000) = ERROR_MESSAGE();
    REVERT;

    IF @errNum6 = 229
        PRINT CONCAT('[OK (esperado)] PRUEBA 6: Ejecución denegada con error 229 (', @errMsg6, ').');
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 6: Se esperaba error 229 pero se recibió: ', @errNum6, ' - ', @errMsg6);
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 7: Intento de SELECT directo a tabla de partidos (Torneo.Partido)
-- Resultado esperado: Acceso denegado (error 229). usr_consulta solo debe consultar
-- a través de la vista vw_Fixture o de los reportes.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_consulta';
BEGIN TRY
    SELECT TOP 1 * FROM Torneo.Partido;
    REVERT;
    PRINT '[FALLO] PRUEBA 7: usr_consulta no debió poder realizar SELECT directo a Torneo.Partido.';
END TRY
BEGIN CATCH
    DECLARE @errNum7 int = ERROR_NUMBER();
    DECLARE @errMsg7 nvarchar(2000) = ERROR_MESSAGE();
    REVERT;

    IF @errNum7 = 229
        PRINT CONCAT('[OK (esperado)] PRUEBA 7: SELECT directo denegado con error 229 (', @errMsg7, ').');
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 7: Se esperaba error 229 pero se recibió: ', @errNum7, ' - ', @errMsg7);
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 8: Intento de INSERT directo a Publicidad.Anunciante (DENY explícito)
-- Resultado esperado: Acceso denegado (error 229) por DENY puntual demostrativo.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_consulta';
BEGIN TRY
    INSERT INTO Publicidad.Anunciante (nombre, rubro, idPais, monedaFacturacion)
    VALUES ('Anunciante Ilegal', 'Retail', 1, 'USD');

    REVERT;
    PRINT '[FALLO] PRUEBA 8: El INSERT directo a Publicidad.Anunciante debió ser denegado.';
END TRY
BEGIN CATCH
    DECLARE @errNum8 int = ERROR_NUMBER();
    DECLARE @errMsg8 nvarchar(2000) = ERROR_MESSAGE();
    REVERT;

    IF @errNum8 = 229
        PRINT CONCAT('[OK (esperado)] PRUEBA 8: INSERT denegado por DENY con error 229 (', @errMsg8, ').');
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 8: Se esperaba error 229 pero se recibió: ', @errNum8, ' - ', @errMsg8);
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 9: Verificación de no acceso a descifrado de datos personales
-- Resultado esperado: usr_consulta NO posee permisos sobre claves simétricas.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_consulta';
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
            PRINT CONCAT('[OK (esperado)] PRUEBA 9: usr_consulta no tiene acceso a la clave de descifrado [', @clave, '].');
        ELSE
            PRINT CONCAT('[FALLO] PRUEBA 9: usr_consulta tiene acceso indebido a la clave [', @clave, '].');
    END
    ELSE
    BEGIN
        REVERT;
        PRINT '[OK (esperado)] PRUEBA 9: No existen claves accesibles para usr_consulta.';
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
PRINT ' FIN DE BATERÍA DE PRUEBAS: 82h_Test_Rol_Consulta.sql';
PRINT '================================================================================';
GO
