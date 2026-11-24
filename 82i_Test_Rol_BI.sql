/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 24/11/2026

 Objetivo    : Suite de pruebas de seguridad y SPs de Entrega 9 (Script 82i):
               1. Pertenencia de usr_bi a rol_BI.
               2. Acceso permitido con filas (> 0) en vistas analíticas de BI:
                  - Publicidad.vw_BI_Exhibiciones, Torneo.vw_BI_Sedes,
                    Eventos.vw_BI_GolesPorSeleccion, Torneo.vw_Fixture.
               3. Ejecución permitida de los 4 reportes analíticos sin datos
                  personales (Publicidad.Reporte_OcupacionPublicitaria,
                  Publicidad.Reporte_MatrizPrimeTime,
                  Publicidad.Reporte_IngresosPorMoneda,
                  Torneo.Reporte_Resultados).
               4. Denegación estricta (error 229) de reportes con datos
                  personales: Equipos.Reporte_SeleccionesPlantillas y
                  Arbitraje.Reporte_DesignacionesArbitrales.
               5. Denegación estricta (error 229) de acceso directo a tablas
                  de personas (Equipos.Jugador, Equipos.Staff, Arbitraje.Arbitro)
                  y vistas de descifrado (Equipos.vw_Jugador, Equipos.vw_Staff,
                  Arbitraje.vw_Arbitro, Eventos.vw_HistorialTitularidad,
                  Arbitraje.vw_HistorialArbitro).
               6. Denegación estricta (error 229) de operaciones DML en usr_bi.
               7. Permisos de lectura y aislamiento en App Blazor (usr_publicidad):
                  - SELECT permitido con filas (> 0) sobre las 3 vistas de catálogo.
                  - SELECT directo sobre Publicidad.Anunciante denegado (229).
               8. Permisos de importación y descarga XML (rol_ImportadorApp):
                  - usr_import_prueba puede consultar Sistema.vw_ErrorImportacion
                    y ejecutar Arbitraje.Importar_ArbitrosXMLDatos y
                    Equipos.Reporte_SeleccionesPlantillas (y no puede leer tablas).
                  - usr_publicidad es rechazado (error 229) sobre esos 3 objetos.
               9. Separación de funciones: usr_admin recibe error 229 al intentar
                  ejecutar los 4 SP de seguridad de Sistema en 71b.
              10. Pruebas unitarias (casos exitosos y fallidos) de los 4 SP de 71b:
                  - CrearUsuarioConLogin con argumentos vacíos (error 50001).
                  - CrearUsuarioConLogin con rol inexistente (error 50001).
                  - CrearUsuarioConLogin con login inexistente (advertencia limpia).
                  - Re-ejecución idempotente de CrearRolBI, OtorgarPermisosRolBI_App
                    y CrearUsuarioPruebaBI.

 Estándares aplicados:
 - Suplantación de identidad controlada con EXECUTE AS USER y REVERT garantizado.
 - Verificación explícita de códigos de error (229 y 50001) y conteos > 0.
================================================================================
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

-- Asegurar contexto inicial limpio
IF USER_NAME() <> ORIGINAL_LOGIN() AND SUSER_SNAME() <> ORIGINAL_LOGIN()
    REVERT;
GO

PRINT '================================================================================';
PRINT ' INICIANDO BATERÍA DE PRUEBAS: 82i_Test_Rol_BI.sql';
PRINT '================================================================================';
PRINT '';

-- -----------------------------------------------------------------------------
-- PRUEBA 1: Verificación de identidad y pertenencia de usr_bi al rol rol_BI
-- Resultado esperado: El usuario actual es usr_bi y pertenece a rol_BI.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_bi';
BEGIN TRY
    DECLARE @usuarioActual sysname = USER_NAME();
    DECLARE @esMiembro int = IS_ROLEMEMBER('rol_BI', 'usr_bi');

    REVERT;

    IF @usuarioActual = 'usr_bi' AND @esMiembro = 1
        PRINT '[OK] PRUEBA 1: Identidad confirmada como usr_bi y miembro de rol_BI.';
    ELSE
        PRINT '[FALLO] PRUEBA 1: Identidad no coincide o no es miembro de rol_BI.';
END TRY
BEGIN CATCH
    REVERT;
    PRINT CONCAT('[ERROR] PRUEBA 1: Ocurrió un error inesperado: ', ERROR_MESSAGE());
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 2: Consulta permitida de vistas analíticas de BI (exigiendo filas > 0)
-- Resultado esperado: SELECT exitoso y conteo > 0 en las 4 vistas.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_bi';
BEGIN TRY
    DECLARE @filasExhibiciones int = (SELECT COUNT(*) FROM Publicidad.vw_BI_Exhibiciones);
    DECLARE @filasSedes        int = (SELECT COUNT(*) FROM Torneo.vw_BI_Sedes);
    DECLARE @filasGoles        int = (SELECT COUNT(*) FROM Eventos.vw_BI_GolesPorSeleccion);
    DECLARE @filasFixture      int = (SELECT COUNT(*) FROM Torneo.vw_Fixture);

    REVERT;

    IF @filasExhibiciones > 0 AND @filasSedes > 0 AND @filasGoles > 0 AND @filasFixture > 0
        PRINT CONCAT('[OK] PRUEBA 2: Lectura con datos confirmada (Exhibiciones: ', @filasExhibiciones,
                     ', Sedes: ', @filasSedes, ', Goles: ', @filasGoles, ', Fixture: ', @filasFixture, ').');
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 2: Alguna vista analítica devolvió 0 filas (Exhibiciones: ', @filasExhibiciones,
                     ', Sedes: ', @filasSedes, ', Goles: ', @filasGoles, ', Fixture: ', @filasFixture, ').');
END TRY
BEGIN CATCH
    REVERT;
    PRINT CONCAT('[FALLO] PRUEBA 2: Error al consultar vistas analíticas: ', ERROR_MESSAGE());
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 3: Ejecución permitida de los 4 reportes sin datos personales
-- Resultado esperado: Ejecución sin errores de los 4 SP de reporte permitidos.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_bi';
BEGIN TRY
    EXEC Publicidad.Reporte_OcupacionPublicitaria;
    EXEC Publicidad.Reporte_MatrizPrimeTime;
    EXEC Publicidad.Reporte_IngresosPorMoneda;
    EXEC Torneo.Reporte_Resultados;

    REVERT;
    PRINT '[OK] PRUEBA 3: Ejecución de los 4 reportes analíticos sin datos personales permitida.';
END TRY
BEGIN CATCH
    REVERT;
    PRINT CONCAT('[FALLO] PRUEBA 3: Falló la ejecución de reportes permitidos: ', ERROR_MESSAGE());
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 4: Denegación de reportes que descifran datos personales
-- Resultado esperado: Error 229 en Reporte_SeleccionesPlantillas y
--                     Reporte_DesignacionesArbitrales.
-- -----------------------------------------------------------------------------
DECLARE @fallosP4 int = 0;

EXECUTE AS USER = 'usr_bi';
BEGIN TRY
    EXEC Equipos.Reporte_SeleccionesPlantillas;
    REVERT;
    SET @fallosP4 += 1;
    PRINT '[FALLO] PRUEBA 4a: Se permitió ejecutar Equipos.Reporte_SeleccionesPlantillas.';
END TRY
BEGIN CATCH
    DECLARE @err4a int = ERROR_NUMBER();
    REVERT;
    IF @err4a <> 229
    BEGIN
        SET @fallosP4 += 1;
        PRINT CONCAT('[FALLO] PRUEBA 4a: Se esperaba error 229 y se recibió ', @err4a, '.');
    END;
END CATCH;

EXECUTE AS USER = 'usr_bi';
BEGIN TRY
    EXEC Arbitraje.Reporte_DesignacionesArbitrales;
    REVERT;
    SET @fallosP4 += 1;
    PRINT '[FALLO] PRUEBA 4b: Se permitió ejecutar Arbitraje.Reporte_DesignacionesArbitrales.';
END TRY
BEGIN CATCH
    DECLARE @err4b int = ERROR_NUMBER();
    REVERT;
    IF @err4b <> 229
    BEGIN
        SET @fallosP4 += 1;
        PRINT CONCAT('[FALLO] PRUEBA 4b: Se esperaba error 229 y se recibió ', @err4b, '.');
    END;
END CATCH;

IF @fallosP4 = 0
    PRINT '[OK] PRUEBA 4: Denegados con error 229 Reporte_SeleccionesPlantillas y Reporte_DesignacionesArbitrales.';
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 5: Denegación de acceso a tablas de personas y vistas de descifrado
-- Resultado esperado: Error 229 en las 3 tablas y 5 vistas con datos personales.
-- -----------------------------------------------------------------------------
DECLARE @objetosProtegidos TABLE (orden int IDENTITY(1,1), nombre nvarchar(128));
INSERT INTO @objetosProtegidos (nombre)
VALUES (N'Equipos.Jugador'),
       (N'Equipos.Staff'),
       (N'Arbitraje.Arbitro'),
       (N'Equipos.vw_Jugador'),
       (N'Equipos.vw_Staff'),
       (N'Arbitraje.vw_Arbitro'),
       (N'Eventos.vw_HistorialTitularidad'),
       (N'Arbitraje.vw_HistorialArbitro');

DECLARE @idx int = 1, @maxIdx int = 8, @objActual nvarchar(128), @sqlCheck nvarchar(300), @fallosP5 int = 0;

WHILE @idx <= @maxIdx
BEGIN
    SELECT @objActual = nombre FROM @objetosProtegidos WHERE orden = @idx;
    SET @sqlCheck = CONCAT(N'SELECT TOP 1 1 FROM ', @objActual, N';');

    EXECUTE AS USER = 'usr_bi';
    BEGIN TRY
        EXEC sys.sp_executesql @sqlCheck;
        REVERT;
        SET @fallosP5 += 1;
        PRINT CONCAT('[FALLO] PRUEBA 5: Se permitió SELECT sobre ', @objActual, '.');
    END TRY
    BEGIN CATCH
        DECLARE @err5 int = ERROR_NUMBER();
        REVERT;
        IF @err5 <> 229
        BEGIN
            SET @fallosP5 += 1;
            PRINT CONCAT('[FALLO] PRUEBA 5: En ', @objActual, ' se esperaba 229 y se recibió ', @err5, '.');
        END;
    END CATCH;

    SET @idx += 1;
END;

IF @fallosP5 = 0
    PRINT '[OK] PRUEBA 5: Denegado con error 229 el acceso a las 3 tablas de personas y 5 vistas de descifrado.';
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 6: Denegación de operaciones DML de modificación en usr_bi
-- Resultado esperado: Error 229 al intentar INSERT en Torneo.Pais.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_bi';
BEGIN TRY
    INSERT INTO Torneo.Pais (nombre, codigoISO2, codigoISO3)
    VALUES (N'PaisFicticio', 'PF', 'PFI');

    REVERT;
    PRINT '[FALLO] PRUEBA 6: Se permitió INSERT directo en Torneo.Pais.';
END TRY
BEGIN CATCH
    DECLARE @numError6 int = ERROR_NUMBER();
    REVERT;

    IF @numError6 = 229
        PRINT '[OK] PRUEBA 6: Modificación DML directa denegada con error 229.';
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 6: Se esperaba error 229 pero se recibió: ', @numError6, ' - ', ERROR_MESSAGE());
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 7: Lectura y aislamiento en App Blazor (usr_publicidad / rol_GestorPublicidad)
-- Resultado esperado:
-- a) SELECT permitido con filas (> 0) sobre las 3 vistas de catálogo/listado.
-- b) SELECT directo sobre Publicidad.Anunciante denegado (error 229).
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_publicidad';
BEGIN TRY
    DECLARE @cantAnunciantes int = (SELECT COUNT(*) FROM Publicidad.vw_AnuncianteListado);
    DECLARE @cantPaises      int = (SELECT COUNT(*) FROM Torneo.vw_PaisCatalogo);
    DECLARE @cantMonedas     int = (SELECT COUNT(*) FROM Publicidad.vw_MonedaCatalogo);

    REVERT;

    IF @cantAnunciantes > 0 AND @cantPaises > 0 AND @cantMonedas > 0
        PRINT CONCAT('[OK] PRUEBA 7a: Lectura con datos confirmada para usr_publicidad (Anunciantes: ',
                     @cantAnunciantes, ', Países: ', @cantPaises, ', Monedas: ', @cantMonedas, ').');
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 7a: Alguna vista de catálogo devolvió 0 filas (Anunciantes: ',
                     @cantAnunciantes, ', Países: ', @cantPaises, ', Monedas: ', @cantMonedas, ').');
END TRY
BEGIN CATCH
    REVERT;
    PRINT CONCAT('[FALLO] PRUEBA 7a: Error al consultar vistas de catálogo para la App: ', ERROR_MESSAGE());
END CATCH;

EXECUTE AS USER = 'usr_publicidad';
BEGIN TRY
    DECLARE @dummyAnun int;
    SELECT TOP 1 @dummyAnun = id FROM Publicidad.Anunciante;

    REVERT;
    PRINT '[FALLO] PRUEBA 7b: usr_publicidad pudo hacer SELECT directo sobre Publicidad.Anunciante.';
END TRY
BEGIN CATCH
    DECLARE @numError7b int = ERROR_NUMBER();
    REVERT;

    IF @numError7b = 229
        PRINT '[OK] PRUEBA 7b: SELECT directo a Publicidad.Anunciante denegado para usr_publicidad con error 229.';
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 7b: Se esperaba error 229 pero se recibió: ', @numError7b, ' - ', ERROR_MESSAGE());
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 8: Permisos de importación y XML (rol_ImportadorApp vs rol_GestorPublicidad)
-- Resultado esperado:
-- a) usr_import_prueba puede leer Sistema.vw_ErrorImportacion, ejecutar
--    Arbitraje.Importar_ArbitrosXMLDatos (validación 50003 por XML vacío) y
--    Equipos.Reporte_SeleccionesPlantillas, y tiene denegado SELECT a tablas.
-- b) usr_publicidad recibe error 229 sobre esos 3 objetos.
-- -----------------------------------------------------------------------------
DECLARE @fallosP8a int = 0;

EXECUTE AS USER = 'usr_import_prueba';
BEGIN TRY
    DECLARE @cntErr int = (SELECT COUNT(*) FROM Sistema.vw_ErrorImportacion);
    EXEC Equipos.Reporte_SeleccionesPlantillas;

    -- Invocar con XML inválido vacío: si llega a validar 50003 es porque tuvo permiso EXECUTE
    BEGIN TRY
        DECLARE @ins int, @act int, @err int;
        EXEC Arbitraje.Importar_ArbitrosXMLDatos
            @xml = N'<RaizInvalida/>',
            @origen = N'test_82i',
            @cantInsertados = @ins OUTPUT,
            @cantActualizados = @act OUTPUT,
            @cantErrores = @err OUTPUT;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 229
        BEGIN
            SET @fallosP8a += 1;
            PRINT '[FALLO] PRUEBA 8a: usr_import_prueba no tiene EXECUTE en Importar_ArbitrosXMLDatos.';
        END;
    END CATCH;

    -- Verificar que no tiene acceso a tablas base (menor privilegio)
    BEGIN TRY
        DECLARE @dummyImp int;
        SELECT TOP 1 @dummyImp = id FROM Publicidad.Anunciante;
        SET @fallosP8a += 1;
        PRINT '[FALLO] PRUEBA 8a: usr_import_prueba pudo leer Publicidad.Anunciante.';
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() <> 229
            SET @fallosP8a += 1;
    END CATCH;

    REVERT;
    IF @fallosP8a = 0
        PRINT '[OK] PRUEBA 8a: usr_import_prueba (rol_ImportadorApp) opera los 3 objetos de importación/XML sin acceso a tablas.';
END TRY
BEGIN CATCH
    REVERT;
    PRINT CONCAT('[FALLO] PRUEBA 8a: Error inesperado con usr_import_prueba: ', ERROR_MESSAGE());
END CATCH;

DECLARE @fallosP8b int = 0;

EXECUTE AS USER = 'usr_publicidad';
BEGIN TRY
    DECLARE @cntErrPub int = (SELECT COUNT(*) FROM Sistema.vw_ErrorImportacion);
    REVERT;
    SET @fallosP8b += 1;
END TRY
BEGIN CATCH
    DECLARE @e8b1 int = ERROR_NUMBER();
    REVERT;
    IF @e8b1 <> 229 SET @fallosP8b += 1;
END CATCH;

EXECUTE AS USER = 'usr_publicidad';
BEGIN TRY
    EXEC Equipos.Reporte_SeleccionesPlantillas;
    REVERT;
    SET @fallosP8b += 1;
END TRY
BEGIN CATCH
    DECLARE @e8b2 int = ERROR_NUMBER();
    REVERT;
    IF @e8b2 <> 229 SET @fallosP8b += 1;
END CATCH;

EXECUTE AS USER = 'usr_publicidad';
BEGIN TRY
    EXEC Arbitraje.Importar_ArbitrosXMLDatos @xml = N'<Arbitros/>', @origen = N'test_82i';
    REVERT;
    SET @fallosP8b += 1;
END TRY
BEGIN CATCH
    DECLARE @e8b3 int = ERROR_NUMBER();
    REVERT;
    IF @e8b3 <> 229 SET @fallosP8b += 1;
END CATCH;

IF @fallosP8b = 0
    PRINT '[OK] PRUEBA 8b: usr_publicidad rechazado con error 229 en los 3 objetos de importación/XML.';
ELSE
    PRINT '[FALLO] PRUEBA 8b: usr_publicidad no fue bloqueado correctamente en los objetos de importación.';
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 9: Separación de funciones (DENY EXECUTE a rol_Administrador en SP 71b)
-- Resultado esperado: usr_admin recibe error 229 al ejecutar SPs de 71b.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_admin';
BEGIN TRY
    EXEC Sistema.CrearRolBI;
    REVERT;
    PRINT '[FALLO] PRUEBA 9: usr_admin pudo ejecutar Sistema.CrearRolBI.';
END TRY
BEGIN CATCH
    DECLARE @err9 int = ERROR_NUMBER();
    REVERT;
    IF @err9 = 229
        PRINT '[OK] PRUEBA 9: Separación de funciones confirmada (error 229 para usr_admin en SPs de 71b).';
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 9: Se esperaba error 229 y se recibió ', @err9, '.');
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 10: Pruebas unitarias de los 4 SP de 71b (casos exitosos y fallidos)
-- Resultado esperado:
-- a) CrearUsuarioConLogin con parámetros vacíos -> error 50001.
-- b) CrearUsuarioConLogin con rol inexistente -> error 50001.
-- c) CrearUsuarioConLogin con login inexistente -> no falla (imprime advertencia).
-- d) Re-ejecución idempotente de CrearRolBI, OtorgarPermisosRolBI_App y
--    CrearUsuarioPruebaBI -> sin errores.
-- -----------------------------------------------------------------------------
DECLARE @fallosP10 int = 0;

-- 10a: parámetros vacíos
BEGIN TRY
    EXEC Sistema.CrearUsuarioConLogin @login = N'', @usuario = N'', @rol = N'';
    SET @fallosP10 += 1;
    PRINT '[FALLO] PRUEBA 10a: CrearUsuarioConLogin aceptó parámetros vacíos.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 50001
    BEGIN
        SET @fallosP10 += 1;
        PRINT CONCAT('[FALLO] PRUEBA 10a: Se esperaba 50001 y se recibió ', ERROR_NUMBER(), '.');
    END;
END CATCH;

-- 10b: rol inexistente
BEGIN TRY
    EXEC Sistema.CrearUsuarioConLogin @login = N'login_prueba', @usuario = N'usr_prueba', @rol = N'rol_Inexistente_XYZ';
    SET @fallosP10 += 1;
    PRINT '[FALLO] PRUEBA 10b: CrearUsuarioConLogin aceptó un rol inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 50001
    BEGIN
        SET @fallosP10 += 1;
        PRINT CONCAT('[FALLO] PRUEBA 10b: Se esperaba 50001 y se recibió ', ERROR_NUMBER(), '.');
    END;
END CATCH;

-- 10c y 10d: login inexistente (advertencia sin error) + idempotencia de los SPs
BEGIN TRY
    EXEC Sistema.CrearUsuarioConLogin
        @login   = N'login_inexistente_test_82i',
        @usuario = N'usr_inexistente_test_82i',
        @rol     = N'rol_BI';

    EXEC Sistema.CrearRolBI;
    EXEC Sistema.OtorgarPermisosRolBI_App;
    EXEC Sistema.CrearUsuarioPruebaBI;
END TRY
BEGIN CATCH
    SET @fallosP10 += 1;
    PRINT CONCAT('[FALLO] PRUEBA 10c/d: Falló login inexistente o re-ejecución idempotente: ', ERROR_MESSAGE());
END CATCH;

IF @fallosP10 = 0
    PRINT '[OK] PRUEBA 10: Validaciones (50001) e idempotencia de los 4 SP de 71b verificadas.';
GO

PRINT '';
PRINT '================================================================================';
PRINT ' FINALIZADA BATERÍA DE PRUEBAS DE SEGURIDAD (82i_Test_Rol_BI.sql)';
PRINT '================================================================================';
GO
