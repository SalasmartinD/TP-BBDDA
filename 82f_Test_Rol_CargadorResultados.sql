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
               - Registro de incidencias de partido: solo ALTAS y REGISTROS, mediante
                 Eventos.Gol_Alta y los SP de negocio Eventos.RegistrarFormacion,
                 RegistrarCambio y RegistrarTarjeta (con sus tipos tabla). Las bajas,
                 las modificaciones y Suspension_* son del administrador.
               - Cierre de partidos y carga de resultado oficial mediante
                 Torneo.RegistrarResultado (con validaciones de negocio).
               - Consulta de fixture (Torneo.vw_Fixture) y reportes de su área
                 (Torneo.Reporte_Resultados, Eventos.Reporte_Goleadores,
                 Eventos.Reporte_Tarjetas).
               - RESTRICCIONES:
                 * Prohibido ejecutar Torneo.Partido_Modificacion (atajo sin controles).
                 * Prohibido operar en esquemas de Publicidad o Sistema.
                 * Prohibido el acceso DML directo a tablas (error 229).
                 * Sin permisos sobre el certificado ni la clave de cifrado (los SP
                   descifran con EXECUTE AS OWNER; plan de cifrado).

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
-- PRUEBA 4: Ejecución de procedimientos del esquema Eventos (Eventos.Gol_Alta)
-- Resultado esperado: Permiso concedido sobre el esquema Eventos. Se invoca SIN argumentos
-- a propósito: con permiso EXECUTE el motor llega al SP y reclama los parámetros obligatorios
-- (error 201) o el SP rechaza por su validación (50001); sin permiso daría el error 229.
-- Así la prueba no depende de los nombres de parámetros de Eventos.Gol_Alta.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('Eventos.Gol_Alta', 'P') IS NULL
    PRINT '[OMITIDA] PRUEBA 4: Eventos.Gol_Alta no existe; ajustar el nombre del SP de eventos.';
ELSE
BEGIN
    EXECUTE AS USER = 'usr_cargador';
    BEGIN TRY
        DECLARE @permGolAlta int = HAS_PERMS_BY_NAME('Eventos.Gol_Alta', 'OBJECT', 'EXECUTE');

        EXEC Eventos.Gol_Alta;

        REVERT;
        PRINT '[FALLO] PRUEBA 4: Debió fallar por falta de parámetros pero continuó.';
    END TRY
    BEGIN CATCH
        DECLARE @errNum4 int = ERROR_NUMBER();
        DECLARE @errMsg4 nvarchar(2000) = ERROR_MESSAGE();
        REVERT;

        IF @permGolAlta = 1 AND @errNum4 IN (201, 50001)
            PRINT CONCAT('[OK (permiso concedido)] PRUEBA 4: usr_cargador llegó a Eventos.Gol_Alta (error ', @errNum4, ': ', @errMsg4, ').');
        ELSE
            PRINT CONCAT('[FALLO] PRUEBA 4: permiso EXECUTE = ', ISNULL(@permGolAlta, 0), ', error ', @errNum4, ' - ', @errMsg4);
    END CATCH;
END;
GO

-- -----------------------------------------------------------------------------
-- PRUEBA 4b: Permisos de registro del cargador (SP de negocio y tipos tabla)
-- Resultado esperado: EXECUTE sobre Eventos.RegistrarFormacion, RegistrarCambio y
-- RegistrarTarjeta, y sobre los tipos tabla Eventos.FormacionJugadorLista y
-- Eventos.CuerpoTecnicoLista (hacen falta para declarar los parámetros de RegistrarFormacion).
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_cargador';
BEGIN TRY
    DECLARE @pFormacion int = ISNULL(HAS_PERMS_BY_NAME('Eventos.RegistrarFormacion', 'OBJECT', 'EXECUTE'), 0);
    DECLARE @pCambio    int = ISNULL(HAS_PERMS_BY_NAME('Eventos.RegistrarCambio',    'OBJECT', 'EXECUTE'), 0);
    DECLARE @pTarjeta   int = ISNULL(HAS_PERMS_BY_NAME('Eventos.RegistrarTarjeta',   'OBJECT', 'EXECUTE'), 0);
    DECLARE @pTipoForm  int = ISNULL(HAS_PERMS_BY_NAME('Eventos.FormacionJugadorLista', 'TYPE', 'EXECUTE'), 0);
    DECLARE @pTipoCT    int = ISNULL(HAS_PERMS_BY_NAME('Eventos.CuerpoTecnicoLista',    'TYPE', 'EXECUTE'), 0);
    REVERT;

    IF @pFormacion = 1 AND @pCambio = 1 AND @pTarjeta = 1 AND @pTipoForm = 1 AND @pTipoCT = 1
        PRINT '[OK] PRUEBA 4b: usr_cargador puede ejecutar los 3 SP de registro y usar sus tipos tabla.';
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 4b: permisos incompletos (Formación: ', @pFormacion, ', Cambio: ', @pCambio, ', Tarjeta: ', @pTarjeta, ', tipo formación: ', @pTipoForm, ', tipo cuerpo técnico: ', @pTipoCT, ').');
END TRY
BEGIN CATCH
    REVERT;
    PRINT CONCAT('[FALLO] PRUEBA 4b: Error inesperado - ', ERROR_MESSAGE());
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
    EXEC Torneo.Partido_Modificacion
        @idPartido            = 1,
        @idSede               = 1,
        @idSeleccionLocal     = 1,
        @idSeleccionVisitante = 2,
        @fase                 = 1,
        @fechaHoraUTC         = '2026-06-11 19:00:00',
        @estado               = 'Programado',
        @cantPublico          = 50000;
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
    INSERT INTO Eventos.Gol (idPartido, idJugador, minuto, idPeriodo, tipo)
    VALUES (1, 1, 45, 1, 'Jugada');

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
-- PRUEBA 9: El rol no tiene permisos sobre el certificado ni sobre la clave de cifrado
-- Resultado esperado: HAS_PERMS_BY_NAME devuelve 0 sobre CertDatosPersonales (CONTROL)
-- y sobre ClaveDatosPersonales (VIEW DEFINITION): los abre cada SP con EXECUTE AS OWNER.
-- La existencia de los objetos se resuelve ANTES de suplantar: sin permisos el catálogo
-- no los muestra, y una búsqueda dentro del EXECUTE AS pasaría sin verificar nada.
-- Antes del script 70 (todavía no existen) la prueba se marca [OMITIDA].
-- -----------------------------------------------------------------------------
DECLARE @hayCert  bit = CASE WHEN EXISTS (SELECT 1 FROM sys.certificates   WHERE name = N'CertDatosPersonales')  THEN 1 ELSE 0 END;
DECLARE @hayClave bit = CASE WHEN EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'ClaveDatosPersonales') THEN 1 ELSE 0 END;

IF @hayCert = 0 OR @hayClave = 0
    PRINT '[OMITIDA] PRUEBA 9: no existen CertDatosPersonales / ClaveDatosPersonales (pendiente de script 70 de Persona 1).';
ELSE
BEGIN
    EXECUTE AS USER = 'usr_cargador';
    BEGIN TRY
        DECLARE @permCert  int = ISNULL(HAS_PERMS_BY_NAME(N'CertDatosPersonales',  'CERTIFICATE',   'CONTROL'), 0);
        DECLARE @permClave int = ISNULL(HAS_PERMS_BY_NAME(N'ClaveDatosPersonales', 'SYMMETRIC KEY', 'VIEW DEFINITION'), 0);
        REVERT;

        IF @permCert = 0 AND @permClave = 0
            PRINT '[OK (esperado)] PRUEBA 9: usr_cargador no tiene permisos sobre el certificado ni sobre la clave.';
        ELSE
            PRINT CONCAT('[FALLO] PRUEBA 9: usr_cargador tiene permisos indebidos (certificado: ', @permCert, ', clave: ', @permClave, ').');
    END TRY
    BEGIN CATCH
        REVERT;
        PRINT CONCAT('[FALLO] PRUEBA 9: Error verificando permisos - ', ERROR_MESSAGE());
    END CATCH;
END;
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
    EXECUTE AS USER = 'usr_cargador';
    BEGIN TRY
        SELECT TOP 1 * FROM Equipos.vw_Jugador;
        REVERT;
        PRINT '[FALLO] PRUEBA 10: usr_cargador no debió poder leer Equipos.vw_Jugador.';
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
-- PRUEBA 11: Bajas, modificaciones, suspensiones y ABM de alta que saltean la lógica de negocio
-- Resultado esperado: usr_cargador no tiene EXECUTE sobre ninguno de esos SP, y un intento
-- real (Eventos.Gol_Baja) da error 229. Las correcciones las hace el administrador; para
-- tarjetas, cambios y formaciones se usan los SP Registrar* (el ABM de alta no aplica sus reglas).
-- -----------------------------------------------------------------------------
EXECUTE AS USER = 'usr_cargador';
DECLARE @conPermiso nvarchar(max);
BEGIN TRY
    SELECT @conPermiso = STRING_AGG(CAST(v.n AS nvarchar(max)), N', ')
    FROM (VALUES (N'Eventos.Gol_Modificacion'), (N'Eventos.Gol_Baja'),
                 (N'Eventos.Tarjeta_Alta'), (N'Eventos.Tarjeta_Modificacion'), (N'Eventos.Tarjeta_Baja'),
                 (N'Eventos.Sustitucion_Alta'), (N'Eventos.Sustitucion_Modificacion'), (N'Eventos.Sustitucion_Baja'),
                 (N'Eventos.FormacionPartido_Alta'), (N'Eventos.FormacionPartido_Modificacion'), (N'Eventos.FormacionPartido_Baja'),
                 (N'Eventos.CuerpoTecnicoPartido_Alta'), (N'Eventos.CuerpoTecnicoPartido_Modificacion'), (N'Eventos.CuerpoTecnicoPartido_Baja'),
                 (N'Eventos.Suspension_Alta'), (N'Eventos.Suspension_Modificacion'), (N'Eventos.Suspension_Baja')) AS v(n)
    WHERE HAS_PERMS_BY_NAME(v.n, 'OBJECT', 'EXECUTE') = 1;

    EXEC Eventos.Gol_Baja;

    REVERT;
    PRINT '[FALLO] PRUEBA 11: usr_cargador no debió poder ejecutar Eventos.Gol_Baja.';
END TRY
BEGIN CATCH
    DECLARE @errNum11 int = ERROR_NUMBER();
    DECLARE @errMsg11 nvarchar(2000) = ERROR_MESSAGE();
    REVERT;

    IF @errNum11 = 229 AND @conPermiso IS NULL
        PRINT CONCAT('[OK (esperado)] PRUEBA 11: sin permisos sobre bajas, modificaciones, Suspension_* ni ABM de alta; Eventos.Gol_Baja denegado con error 229 (', @errMsg11, ').');
    ELSE
        PRINT CONCAT('[FALLO] PRUEBA 11: error ', @errNum11, ' - ', @errMsg11, ' | SP con permiso indebido: ', ISNULL(@conPermiso, N'ninguno'));
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
