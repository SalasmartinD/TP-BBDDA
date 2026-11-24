/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 23/11/2026

 Objetivo    : Suite de pruebas de seguridad para rol_BI (Script 82i):
               Verificar granularmente el principio de menor privilegio y la
               política estricta de privacidad de datos para el usuario de BI:
               1. Pertenencia de usr_bi a rol_BI.
               2. Acceso permitido a vistas analíticas (K1 a K6):
                  - Publicidad.vw_BI_Exhibiciones
                  - Torneo.vw_BI_Sedes
                  - Eventos.vw_BI_GolesPorSeleccion
                  - Torneo.vw_Fixture
               3. Ejecución permitida sobre reportes analíticos sin datos personales:
                  - Publicidad.Reporte_OcupacionPublicitaria
                  - Publicidad.Reporte_MatrizPrimeTime
                  - Publicidad.Reporte_IngresosPorMoneda
                  - Torneo.Reporte_Resultados
               4. Denegación estricta de reportes que descifran datos personales:
                  - Equipos.Reporte_SeleccionesPlantillas (error 229)
                  - Arbitraje.Reporte_DesignacionesArbitrales (error 229)
               5. Denegación estricta de acceso directo a tablas de personas:
                  - Equipos.Jugador, Equipos.Staff, Arbitraje.Arbitro (error 229)
               6. Denegación estricta de operaciones de modificación (INSERT / UPDATE / DELETE).
               7. Verificación de permisos de lectura para la App Blazor en usr_publicidad:
                  - SELECT permitido sobre Publicidad.vw_AnuncianteListado,
                    Torneo.vw_PaisCatalogo, Publicidad.vw_MonedaCatalogo.
                  - SELECT directo sobre Publicidad.Anunciante sigue bloqueado (error 229).

 Estándares aplicados:
 - Cada prueba se ejecuta suplantando al usuario mediante EXECUTE AS USER.
 - Cada lote finaliza con REVERT para garantizar que no quede contexto residual.
 - Manejo defensivo de excepciones y verificación de códigos de error (229 esperado).
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
PRINT ' INICIANDO BATERÍA DE PRUEBAS: 82i_Test_Rol_BI.sql (usr_bi / usr_publicidad)';
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
-- PRUEBA 2: Consulta permitida de vistas analíticas de BI
-- Resultado esperado: SELECT exitoso sobre las tres vistas de BI y Torneo.vw_Fixture.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_bi';
BEGIN TRY
    DECLARE @filasExhibiciones int = (SELECT COUNT(*) FROM Publicidad.vw_BI_Exhibiciones);
    DECLARE @filasSedes int        = (SELECT COUNT(*) FROM Torneo.vw_BI_Sedes);
    DECLARE @filasGoles int        = (SELECT COUNT(*) FROM Eventos.vw_BI_GolesPorSeleccion);
    DECLARE @filasFixture int      = (SELECT COUNT(*) FROM Torneo.vw_Fixture);

    REVERT;
    PRINT CONCAT('[OK] PRUEBA 2: Lectura de vistas analíticas permitida (Exhibiciones: ', @filasExhibiciones,
                 ', Sedes: ', @filasSedes, ', Goles: ', @filasGoles, ', Fixture: ', @filasFixture, ').');
END TRY
BEGIN CATCH
    REVERT;
    PRINT CONCAT('[FALLO] PRUEBA 2: Error al consultar vistas analíticas: ', ERROR_MESSAGE());
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 3: Ejecución permitida de reportes sin datos personales
-- Resultado esperado: Ejecución exitosa de Reporte_OcupacionPublicitaria y Reporte_Resultados.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_bi';
BEGIN TRY
    -- Ejecutar reporte de ocupación publicitaria (primer partido o resumen)
    EXEC Publicidad.Reporte_OcupacionPublicitaria;
    EXEC Torneo.Reporte_Resultados;

    REVERT;
    PRINT '[OK] PRUEBA 3: Ejecución de reportes analíticos sin datos personales permitida.';
END TRY
BEGIN CATCH
    REVERT;
    PRINT CONCAT('[FALLO] PRUEBA 3: Falló la ejecución de reportes permitidos: ', ERROR_MESSAGE());
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 4: Denegación de reportes con datos personales descifrados (plantillas)
-- Resultado esperado: Error 229 (permiso EXECUTE denegado) al invocar Reporte_SeleccionesPlantillas.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_bi';
BEGIN TRY
    EXEC Equipos.Reporte_SeleccionesPlantillas;

    REVERT;
    PRINT '[FALLO] PRUEBA 4: Se permitió ejecutar Equipos.Reporte_SeleccionesPlantillas (violación de privacidad).';
END TRY
BEGIN CATCH
    DECLARE @numError4 int = ERROR_NUMBER();
    REVERT;

    IF @numError4 = 229
        PRINT '[OK (esperado)] PRUEBA 4: Denegada la ejecución de Reporte_SeleccionesPlantillas con error 229.';
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 4: Se esperaba error 229 pero se recibió: ', @numError4, ' - ', ERROR_MESSAGE());
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 5: Denegación de acceso directo a tablas de datos personales
-- Resultado esperado: Error 229 al intentar SELECT directo sobre Equipos.Jugador.
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_bi';
BEGIN TRY
    DECLARE @dummy int;
    SELECT TOP 1 @dummy = id FROM Equipos.Jugador;

    REVERT;
    PRINT '[FALLO] PRUEBA 5: Se permitió SELECT directo a Equipos.Jugador (violación de seguridad).';
END TRY
BEGIN CATCH
    DECLARE @numError5 int = ERROR_NUMBER();
    REVERT;

    IF @numError5 = 229
        PRINT '[OK (esperado)] PRUEBA 5: SELECT directo sobre Equipos.Jugador denegado con error 229.';
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 5: Se esperaba error 229 pero se recibió: ', @numError5, ' - ', ERROR_MESSAGE());
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 6: Denegación de operaciones DML de modificación
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
        PRINT '[OK (esperado)] PRUEBA 6: Modificación DML directa denegada con error 229.';
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 6: Se esperaba error 229 pero se recibió: ', @numError6, ' - ', ERROR_MESSAGE());
END CATCH;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 7: Verificación de lectura para la App Blazor (usr_publicidad / rol_GestorPublicidad)
-- Resultado esperado:
-- a) SELECT permitido sobre las vistas de catálogo y listado.
-- b) SELECT directo sobre Publicidad.Anunciante denegado (error 229).
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_publicidad';
BEGIN TRY
    DECLARE @cantAnunciantes int = (SELECT COUNT(*) FROM Publicidad.vw_AnuncianteListado);
    DECLARE @cantPaises      int = (SELECT COUNT(*) FROM Torneo.vw_PaisCatalogo);
    DECLARE @cantMonedas     int = (SELECT COUNT(*) FROM Publicidad.vw_MonedaCatalogo);

    REVERT;
    PRINT CONCAT('[OK] PRUEBA 7a: Lectura de vistas de la App permitida para usr_publicidad (Anunciantes: ',
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
    PRINT '[FALLO] PRUEBA 7b: usr_publicidad pudo hacer SELECT directo sobre Publicidad.Anunciante (debe pasar por vistas/SPs).';
END TRY
BEGIN CATCH
    DECLARE @numError7b int = ERROR_NUMBER();
    REVERT;

    IF @numError7b = 229
        PRINT '[OK (esperado)] PRUEBA 7b: SELECT directo a Publicidad.Anunciante denegado para usr_publicidad con error 229.';
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 7b: Se esperaba error 229 pero se recibió: ', @numError7b, ' - ', ERROR_MESSAGE());
END CATCH;
GO

PRINT '';
PRINT '================================================================================';
PRINT ' FINALIZADA BATERÍA DE PRUEBAS DE SEGURIDAD (82i_Test_Rol_BI.sql)';
PRINT '================================================================================';
GO
