/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 24/11/2026

 Objetivo    : Entrega 9 - Seguridad para Plataforma BI y App Blazor (Script 71b):
               1. Sistema.CrearRolBI:
                  Crea los roles rol_BI y rol_ImportadorApp si no existen.
               2. Sistema.OtorgarPermisosRolBI_App:
                  Configura permisos de menor privilegio y privacidad estricta:
                  - rol_BI:
                    * SELECT exclusivo sobre las vistas analíticas de BI:
                      Publicidad.vw_BI_Exhibiciones, Torneo.vw_BI_Sedes,
                      Eventos.vw_BI_GolesPorSeleccion.
                    * EXECUTE únicamente sobre reportes sin datos personales:
                      Publicidad.Reporte_OcupacionPublicitaria,
                      Publicidad.Reporte_MatrizPrimeTime,
                      Publicidad.Reporte_IngresosPorMoneda,
                      Torneo.Reporte_Resultados.
                    * SELECT sobre Torneo.vw_Fixture.
                    * DENY SELECT explícito sobre tablas de datos personales
                      (Equipos.Jugador, Equipos.Staff, Arbitraje.Arbitro) y
                      vistas de descifrado (Equipos.vw_Jugador, Equipos.vw_Staff,
                      Arbitraje.vw_Arbitro, Eventos.vw_HistorialTitularidad,
                      Arbitraje.vw_HistorialArbitro).
                  - rol_GestorPublicidad:
                    * SELECT sobre Publicidad.vw_AnuncianteListado,
                      Torneo.vw_PaisCatalogo, Publicidad.vw_MonedaCatalogo.
                  - rol_ImportadorApp (menor privilegio para importación/XML):
                    * EXECUTE exclusivo sobre Arbitraje.Importar_ArbitrosXMLDatos
                      y Equipos.Reporte_SeleccionesPlantillas.
                    * SELECT exclusivo sobre Sistema.vw_ErrorImportacion (sin
                      datoOriginal).
                  - Separación de funciones:
                    * DENY EXECUTE a rol_Administrador sobre los 4 SP de
                      seguridad definidos en este script.
               3. Sistema.CrearUsuarioConLogin:
                  Mapea de manera idempotente un usuario de BD a un login de
                  servidor (con advertencia limpia si el login no existe).
               4. Sistema.CrearUsuarioPruebaBI:
                  Crea los usuarios sin login usr_bi (rol_BI) y usr_import_prueba
                  (rol_ImportadorApp) para pruebas automatizadas.
               5. Configuración automática de usuarios para logins reales:
                  Mapea login_bi (usr_bi_net), login_app (usr_app) y
                  login_import (usr_import).

 Estándares aplicados:
 - Principio de menor privilegio y separación de funciones.
 - Manejo acumulativo de errores con THROW 50001.
 - SQL dinámico estrictamente justificado para DDL sin parámetros (CREATE USER,
   ALTER ROLE), con saneamiento estricto mediante QUOTENAME().
 - Idempotencia en la creación de roles, usuarios y asignación de permisos.
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- 1. SP: Sistema.CrearRolBI
-- =============================================================================
CREATE OR ALTER PROCEDURE Sistema.CrearRolBI
AS
BEGIN
    SET NOCOUNT ON;

    IF DATABASE_PRINCIPAL_ID('rol_BI') IS NULL
    BEGIN
        CREATE ROLE rol_BI;
        PRINT 'Rol [rol_BI] creado exitosamente.';
    END
    ELSE
    BEGIN
        PRINT 'Rol [rol_BI] ya existía.';
    END;

    IF DATABASE_PRINCIPAL_ID('rol_ImportadorApp') IS NULL
    BEGIN
        CREATE ROLE rol_ImportadorApp;
        PRINT 'Rol [rol_ImportadorApp] creado exitosamente.';
    END
    ELSE
    BEGIN
        PRINT 'Rol [rol_ImportadorApp] ya existía.';
    END;
END;
GO

-- =============================================================================
-- 2. SP: Sistema.OtorgarPermisosRolBI_App
-- =============================================================================
CREATE OR ALTER PROCEDURE Sistema.OtorgarPermisosRolBI_App
AS
BEGIN
    SET NOCOUNT ON;

    /* -------------------------------------------------------------------------
       1. Validación acumulativa de roles y objetos requeridos
    ------------------------------------------------------------------------- */
    DECLARE @errores nvarchar(2000) = N'';

    -- Validar roles
    IF DATABASE_PRINCIPAL_ID('rol_BI') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- El rol rol_BI no existe.');
    IF DATABASE_PRINCIPAL_ID('rol_ImportadorApp') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- El rol rol_ImportadorApp no existe.');
    IF DATABASE_PRINCIPAL_ID('rol_GestorPublicidad') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- El rol rol_GestorPublicidad no existe.');
    IF DATABASE_PRINCIPAL_ID('rol_Administrador') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- El rol rol_Administrador no existe.');

    -- Validar vistas analíticas de BI
    IF OBJECT_ID(N'Publicidad.vw_BI_Exhibiciones', N'V') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- Falta la vista Publicidad.vw_BI_Exhibiciones.');
    IF OBJECT_ID(N'Torneo.vw_BI_Sedes', N'V') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- Falta la vista Torneo.vw_BI_Sedes.');
    IF OBJECT_ID(N'Eventos.vw_BI_GolesPorSeleccion', N'V') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- Falta la vista Eventos.vw_BI_GolesPorSeleccion.');

    -- Validar vistas para la App Blazor
    IF OBJECT_ID(N'Publicidad.vw_AnuncianteListado', N'V') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- Falta la vista Publicidad.vw_AnuncianteListado.');
    IF OBJECT_ID(N'Torneo.vw_PaisCatalogo', N'V') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- Falta la vista Torneo.vw_PaisCatalogo.');
    IF OBJECT_ID(N'Publicidad.vw_MonedaCatalogo', N'V') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- Falta la vista Publicidad.vw_MonedaCatalogo.');
    IF OBJECT_ID(N'Sistema.vw_ErrorImportacion', N'V') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- Falta la vista Sistema.vw_ErrorImportacion.');

    -- Validar reportes sin datos personales permitidos para BI
    IF OBJECT_ID(N'Publicidad.Reporte_OcupacionPublicitaria', N'P') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- Falta el procedimiento Publicidad.Reporte_OcupacionPublicitaria.');
    IF OBJECT_ID(N'Publicidad.Reporte_MatrizPrimeTime', N'P') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- Falta el procedimiento Publicidad.Reporte_MatrizPrimeTime.');
    IF OBJECT_ID(N'Publicidad.Reporte_IngresosPorMoneda', N'P') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- Falta el procedimiento Publicidad.Reporte_IngresosPorMoneda.');
    IF OBJECT_ID(N'Torneo.Reporte_Resultados', N'P') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- Falta el procedimiento Torneo.Reporte_Resultados.');

    -- Validar objetos requeridos por rol_ImportadorApp
    IF OBJECT_ID(N'Arbitraje.Importar_ArbitrosXMLDatos', N'P') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- Falta el procedimiento Arbitraje.Importar_ArbitrosXMLDatos.');
    IF OBJECT_ID(N'Equipos.Reporte_SeleccionesPlantillas', N'P') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- Falta el procedimiento Equipos.Reporte_SeleccionesPlantillas.');

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudieron configurar los permisos de BI y App:' + @errores;
        THROW 50001, @errores, 1;
    END;

    /* -------------------------------------------------------------------------
       2. Permisos para rol_BI
    ------------------------------------------------------------------------- */
    GRANT SELECT ON Publicidad.vw_BI_Exhibiciones   TO rol_BI;
    GRANT SELECT ON Torneo.vw_BI_Sedes              TO rol_BI;
    GRANT SELECT ON Eventos.vw_BI_GolesPorSeleccion TO rol_BI;

    GRANT EXECUTE ON Publicidad.Reporte_OcupacionPublicitaria TO rol_BI;
    GRANT EXECUTE ON Publicidad.Reporte_MatrizPrimeTime       TO rol_BI;
    GRANT EXECUTE ON Publicidad.Reporte_IngresosPorMoneda     TO rol_BI;
    GRANT EXECUTE ON Torneo.Reporte_Resultados                TO rol_BI;

    IF OBJECT_ID(N'Torneo.vw_Fixture', N'V') IS NOT NULL
        GRANT SELECT ON Torneo.vw_Fixture TO rol_BI;

    /* -------------------------------------------------------------------------
       3. Protección de privacidad para rol_BI (defensa en profundidad)
    ------------------------------------------------------------------------- */
    DENY SELECT ON Equipos.Jugador   TO rol_BI;
    DENY SELECT ON Equipos.Staff     TO rol_BI;
    DENY SELECT ON Arbitraje.Arbitro TO rol_BI;

    IF OBJECT_ID(N'Equipos.vw_Jugador', N'V') IS NOT NULL
        DENY SELECT ON Equipos.vw_Jugador TO rol_BI;
    IF OBJECT_ID(N'Equipos.vw_Staff', N'V') IS NOT NULL
        DENY SELECT ON Equipos.vw_Staff TO rol_BI;
    IF OBJECT_ID(N'Arbitraje.vw_Arbitro', N'V') IS NOT NULL
        DENY SELECT ON Arbitraje.vw_Arbitro TO rol_BI;
    IF OBJECT_ID(N'Eventos.vw_HistorialTitularidad', N'V') IS NOT NULL
        DENY SELECT ON Eventos.vw_HistorialTitularidad TO rol_BI;
    IF OBJECT_ID(N'Arbitraje.vw_HistorialArbitro', N'V') IS NOT NULL
        DENY SELECT ON Arbitraje.vw_HistorialArbitro TO rol_BI;

    /* -------------------------------------------------------------------------
       4. Permisos de lectura para la App Blazor en rol_GestorPublicidad
    ------------------------------------------------------------------------- */
    GRANT SELECT ON Publicidad.vw_AnuncianteListado TO rol_GestorPublicidad;
    GRANT SELECT ON Torneo.vw_PaisCatalogo          TO rol_GestorPublicidad;
    GRANT SELECT ON Publicidad.vw_MonedaCatalogo    TO rol_GestorPublicidad;

    /* -------------------------------------------------------------------------
       5. Permisos de menor privilegio para importación/XML en rol_ImportadorApp
    ------------------------------------------------------------------------- */
    GRANT EXECUTE ON Arbitraje.Importar_ArbitrosXMLDatos   TO rol_ImportadorApp;
    GRANT EXECUTE ON Equipos.Reporte_SeleccionesPlantillas TO rol_ImportadorApp;
    GRANT SELECT  ON Sistema.vw_ErrorImportacion           TO rol_ImportadorApp;

    /* -------------------------------------------------------------------------
       6. Separación de funciones: impedir que rol_Administrador ejecute los
          SP de seguridad de este script (mismo patrón que 71a_Roles_Seguridad.sql)
    ------------------------------------------------------------------------- */
    DENY EXECUTE ON Sistema.CrearRolBI                TO rol_Administrador;
    DENY EXECUTE ON Sistema.OtorgarPermisosRolBI_App  TO rol_Administrador;
    DENY EXECUTE ON Sistema.CrearUsuarioConLogin      TO rol_Administrador;
    DENY EXECUTE ON Sistema.CrearUsuarioPruebaBI      TO rol_Administrador;

    PRINT 'Permisos de rol_BI, rol_ImportadorApp y App Blazor configurados exitosamente.';
END;
GO

-- =============================================================================
-- 3. SP: Sistema.CrearUsuarioConLogin
-- =============================================================================
CREATE OR ALTER PROCEDURE Sistema.CrearUsuarioConLogin
    @login   sysname,
    @usuario sysname,
    @rol     sysname
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @errores nvarchar(2000) = N'';
    SET @login   = LTRIM(RTRIM(@login));
    SET @usuario = LTRIM(RTRIM(@usuario));
    SET @rol     = LTRIM(RTRIM(@rol));

    IF @login IS NULL OR @login = N''
        SET @errores = CONCAT(@errores, CHAR(10), N'- El nombre de login no puede estar vacío.');
    IF @usuario IS NULL OR @usuario = N''
        SET @errores = CONCAT(@errores, CHAR(10), N'- El nombre de usuario no puede estar vacío.');
    IF @rol IS NULL OR @rol = N''
        SET @errores = CONCAT(@errores, CHAR(10), N'- El nombre de rol no puede estar vacío.');

    IF @rol IS NOT NULL AND @rol <> N'' AND DATABASE_PRINCIPAL_ID(@rol) IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- El rol especificado no existe en la base de datos: ', @rol);

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo procesar la vinculación de usuario con login:' + @errores;
        THROW 50001, @errores, 1;
    END;

    -- Verificar si el login existe en la instancia SQL Server
    IF SUSER_ID(@login) IS NULL
    BEGIN
        PRINT CONCAT('ADVERTENCIA: El login de servidor [', @login, '] no existe en la instancia. ',
                     'Ejecute localmente bi/local/crear_logins.local.sql para crearlo.');
        RETURN;
    END;

    -- Crear usuario mapeado al login si no existe
    IF USER_ID(@usuario) IS NULL
    BEGIN
        DECLARE @sqlCrearUser nvarchar(500) = CONCAT(N'CREATE USER ', QUOTENAME(@usuario), N' FOR LOGIN ', QUOTENAME(@login), N';');
        EXEC sys.sp_executesql @sqlCrearUser;
        PRINT CONCAT('Usuario de base [', @usuario, '] creado para login [', @login, '].');
    END
    ELSE
    BEGIN
        PRINT CONCAT('Usuario de base [', @usuario, '] ya existía.');
    END;

    -- Asignar al rol correspondiente
    IF IS_ROLEMEMBER(@rol, @usuario) = 0 OR IS_ROLEMEMBER(@rol, @usuario) IS NULL
    BEGIN
        DECLARE @sqlAsignarRol nvarchar(500) = CONCAT(N'ALTER ROLE ', QUOTENAME(@rol), N' ADD MEMBER ', QUOTENAME(@usuario), N';');
        EXEC sys.sp_executesql @sqlAsignarRol;
        PRINT CONCAT('Usuario [', @usuario, '] agregado al rol [', @rol, '].');
    END
    ELSE
    BEGIN
        PRINT CONCAT('Usuario [', @usuario, '] ya era miembro del rol [', @rol, '].');
    END;
END;
GO

-- =============================================================================
-- 4. SP: Sistema.CrearUsuarioPruebaBI
-- =============================================================================
CREATE OR ALTER PROCEDURE Sistema.CrearUsuarioPruebaBI
AS
BEGIN
    SET NOCOUNT ON;

    IF USER_ID('usr_bi') IS NULL
    BEGIN
        CREATE USER usr_bi WITHOUT LOGIN;
        PRINT 'Usuario de prueba [usr_bi] creado exitosamente.';
    END
    ELSE
    BEGIN
        PRINT 'Usuario de prueba [usr_bi] ya existía.';
    END;

    IF IS_ROLEMEMBER('rol_BI', 'usr_bi') = 0 OR IS_ROLEMEMBER('rol_BI', 'usr_bi') IS NULL
    BEGIN
        ALTER ROLE rol_BI ADD MEMBER usr_bi;
        PRINT 'Usuario [usr_bi] incorporado a [rol_BI].';
    END;

    IF USER_ID('usr_import_prueba') IS NULL
    BEGIN
        CREATE USER usr_import_prueba WITHOUT LOGIN;
        PRINT 'Usuario de prueba [usr_import_prueba] creado exitosamente.';
    END
    ELSE
    BEGIN
        PRINT 'Usuario de prueba [usr_import_prueba] ya existía.';
    END;

    IF IS_ROLEMEMBER('rol_ImportadorApp', 'usr_import_prueba') = 0 OR IS_ROLEMEMBER('rol_ImportadorApp', 'usr_import_prueba') IS NULL
    BEGIN
        ALTER ROLE rol_ImportadorApp ADD MEMBER usr_import_prueba;
        PRINT 'Usuario [usr_import_prueba] incorporado a [rol_ImportadorApp].';
    END;
END;
GO

-- =============================================================================
-- 5. EJECUCIÓN INICIAL Y CONFIGURACIÓN
-- =============================================================================
EXEC Sistema.CrearRolBI;
EXEC Sistema.OtorgarPermisosRolBI_App;
EXEC Sistema.CrearUsuarioPruebaBI;

-- Mapeos para logins de red si estuvieran presentes en la instancia
EXEC Sistema.CrearUsuarioConLogin @login = N'login_bi',     @usuario = N'usr_bi_net', @rol = N'rol_BI';
EXEC Sistema.CrearUsuarioConLogin @login = N'login_app',    @usuario = N'usr_app',    @rol = N'rol_GestorPublicidad';
EXEC Sistema.CrearUsuarioConLogin @login = N'login_import', @usuario = N'usr_import', @rol = N'rol_ImportadorApp';
GO