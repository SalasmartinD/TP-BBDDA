/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 20/11/2026

 Objetivo    : Entrega 8 - Seguridad (Roles y Usuarios de Prueba):
               Implementación mediante Stored Procedures de la gestión granular
               de seguridad basada en roles (RBAC) y creación de usuarios de prueba:
               1. Sistema.CrearRoles:
                  Crea los roles de base de datos definidos en el diseño:
                  - rol_Administrador
                  - rol_CargadorResultados
                  - rol_GestorPublicidad
                  - rol_Consulta
               2. Sistema.OtorgarPermisosRoles:
                  Aplica la matriz granular de permisos:
                  - Principio de menor privilegio (default deny sobre tablas).
                  - Concesión de ejecución sobre esquemas y objetos específicos.
                  - Asignación de reportes a rol_Consulta.
                  - Restricción puntual de cotizaciones para rol_GestorPublicidad.
               3. Sistema.CrearUsuarioPrueba:
                  Crea usuarios de base de datos sin login (WITHOUT LOGIN) y los
                  asigna al rol correspondiente, protegiendo credenciales en el repo.
               4. Sistema.OtorgarPermisosDescifrado:
                  Otorga permisos de apertura/inspección de claves simétricas a
                  rol_Administrador, desacoplado del script de cifrado (70).

 Estándares aplicados:
 - Manejo de errores acumulativo con THROW 50001 ante parámetros u objetos inválidos.
 - SQL dinámico estrictamente acotado y justificado para DDL que no admite parámetros
   (CREATE USER ... WITHOUT LOGIN, ALTER ROLE ... ADD MEMBER, GRANT sobre clave simétrica),
   saneando identificadores con QUOTENAME().
 - Idempotencia en todas las operaciones.
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- 1. SP: Sistema.CrearRoles
-- =============================================================================
/*
   Crea los cuatro roles de seguridad requeridos si no existen previamente en la base.
   - rol_Administrador: Control total sobre los procedimientos del sistema y mantenimiento.
   - rol_CargadorResultados: Carga de eventos de partido, actas y registro de resultados.
   - rol_GestorPublicidad: Administración de anunciantes, campañas, pauta y reportes publicitarios.
   - rol_Consulta: Perfil de solo lectura de vistas y ejecución de reportes analíticos.
*/
CREATE OR ALTER PROCEDURE Sistema.CrearRoles
AS
BEGIN
    SET NOCOUNT ON;

    -- rol_Administrador
    IF DATABASE_PRINCIPAL_ID('rol_Administrador') IS NULL
    BEGIN
        CREATE ROLE rol_Administrador;
        PRINT 'Rol [rol_Administrador] creado exitosamente.';
    END
    ELSE
        PRINT 'Rol [rol_Administrador] ya existía.';

    -- rol_CargadorResultados
    IF DATABASE_PRINCIPAL_ID('rol_CargadorResultados') IS NULL
    BEGIN
        CREATE ROLE rol_CargadorResultados;
        PRINT 'Rol [rol_CargadorResultados] creado exitosamente.';
    END
    ELSE
        PRINT 'Rol [rol_CargadorResultados] ya existía.';

    -- rol_GestorPublicidad
    IF DATABASE_PRINCIPAL_ID('rol_GestorPublicidad') IS NULL
    BEGIN
        CREATE ROLE rol_GestorPublicidad;
        PRINT 'Rol [rol_GestorPublicidad] creado exitosamente.';
    END
    ELSE
        PRINT 'Rol [rol_GestorPublicidad] ya existía.';

    -- rol_Consulta
    IF DATABASE_PRINCIPAL_ID('rol_Consulta') IS NULL
    BEGIN
        CREATE ROLE rol_Consulta;
        PRINT 'Rol [rol_Consulta] creado exitosamente.';
    END
    ELSE
        PRINT 'Rol [rol_Consulta] ya existía.';
END;
GO

-- =============================================================================
-- 2. SP: Sistema.OtorgarPermisosRoles
-- =============================================================================
/*
   Configura la matriz de permisos granulares para cada rol del sistema.
   Aplica el principio de menor privilegio: los roles NO reciben permisos directos
   (SELECT, INSERT, UPDATE, DELETE) sobre las tablas, canalizando todas las
   operaciones a través de procedimientos almacenados mediante Encadenamiento
   de Propiedad (Ownership Chaining).
*/
CREATE OR ALTER PROCEDURE Sistema.OtorgarPermisosRoles
AS
BEGIN
    SET NOCOUNT ON;

    /* -------------------------------------------------------------------------
       1. Validación acumulativa de existencia de roles y objetos críticos
    ------------------------------------------------------------------------- */
    DECLARE @errores nvarchar(2000) = N'';

    -- Verificación de existencia de roles
    IF DATABASE_PRINCIPAL_ID('rol_Administrador') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- El rol rol_Administrador no existe.');
    IF DATABASE_PRINCIPAL_ID('rol_CargadorResultados') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- El rol rol_CargadorResultados no existe.');
    IF DATABASE_PRINCIPAL_ID('rol_GestorPublicidad') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- El rol rol_GestorPublicidad no existe.');
    IF DATABASE_PRINCIPAL_ID('rol_Consulta') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- El rol rol_Consulta no existe.');

    -- Verificación de existencia de los 8 reportes oficiales (Entrega 7)
    IF OBJECT_ID(N'Torneo.Reporte_Resultados', N'P') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- Falta el procedimiento Torneo.Reporte_Resultados.');
    IF OBJECT_ID(N'Equipos.Reporte_SeleccionesPlantillas', N'P') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- Falta el procedimiento Equipos.Reporte_SeleccionesPlantillas.');
    IF OBJECT_ID(N'Eventos.Reporte_Goleadores', N'P') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- Falta el procedimiento Eventos.Reporte_Goleadores.');
    IF OBJECT_ID(N'Eventos.Reporte_Tarjetas', N'P') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- Falta el procedimiento Eventos.Reporte_Tarjetas.');
    IF OBJECT_ID(N'Arbitraje.Reporte_DesignacionesArbitrales', N'P') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- Falta el procedimiento Arbitraje.Reporte_DesignacionesArbitrales.');
    IF OBJECT_ID(N'Publicidad.Reporte_OcupacionPublicitaria', N'P') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- Falta el procedimiento Publicidad.Reporte_OcupacionPublicitaria.');
    IF OBJECT_ID(N'Publicidad.Reporte_MatrizPrimeTime', N'P') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- Falta el procedimiento Publicidad.Reporte_MatrizPrimeTime.');
    IF OBJECT_ID(N'Publicidad.Reporte_IngresosPorMoneda', N'P') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- Falta el procedimiento Publicidad.Reporte_IngresosPorMoneda.');

    -- Verificación de SPs específicos de negocio
    IF OBJECT_ID(N'Torneo.RegistrarResultado', N'P') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- Falta el procedimiento Torneo.RegistrarResultado.');
    IF OBJECT_ID(N'Publicidad.TipoCambio_Alta', N'P') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- Falta el procedimiento Publicidad.TipoCambio_Alta.');
    IF OBJECT_ID(N'Publicidad.TipoCambio_Modificacion', N'P') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- Falta el procedimiento Publicidad.TipoCambio_Modificacion.');
    IF OBJECT_ID(N'Publicidad.TipoCambio_Baja', N'P') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- Falta el procedimiento Publicidad.TipoCambio_Baja.');

    -- Verificación de vistas y consultas de fixture
    IF OBJECT_ID(N'Torneo.vw_Fixture', N'V') IS NULL
        SET @errores = CONCAT(@errores, CHAR(10), N'- Falta la vista Torneo.vw_Fixture.');

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudieron configurar los permisos de seguridad:' + @errores;
        THROW 50001, @errores, 1;
    END;

    /* -------------------------------------------------------------------------
       2. Permisos para rol_Consulta
          - Acceso de solo ejecución a los 8 reportes oficiales.
          - Acceso de lectura a vistas públicas de fixture.
          - DENY explícito de modificación sobre esquemas de negocio como evidencia.
    ------------------------------------------------------------------------- */
    GRANT EXECUTE ON Torneo.Reporte_Resultados                 TO rol_Consulta;
    GRANT EXECUTE ON Equipos.Reporte_SeleccionesPlantillas     TO rol_Consulta;
    GRANT EXECUTE ON Eventos.Reporte_Goleadores                TO rol_Consulta;
    GRANT EXECUTE ON Eventos.Reporte_Tarjetas                  TO rol_Consulta;
    GRANT EXECUTE ON Arbitraje.Reporte_DesignacionesArbitrales TO rol_Consulta;
    GRANT EXECUTE ON Publicidad.Reporte_OcupacionPublicitaria  TO rol_Consulta;
    GRANT EXECUTE ON Publicidad.Reporte_MatrizPrimeTime        TO rol_Consulta;
    GRANT EXECUTE ON Publicidad.Reporte_IngresosPorMoneda      TO rol_Consulta;

    GRANT SELECT ON Torneo.vw_Fixture TO rol_Consulta;
    IF OBJECT_ID(N'Torneo.ConsultarFixture', N'P') IS NOT NULL
        GRANT EXECUTE ON Torneo.ConsultarFixture TO rol_Consulta;

    -- DENY puntual demostrativo para evaluación docente
    DENY INSERT, UPDATE, DELETE ON SCHEMA::Publicidad TO rol_Consulta;
    DENY INSERT, UPDATE, DELETE ON SCHEMA::Torneo     TO rol_Consulta;
    DENY INSERT, UPDATE, DELETE ON SCHEMA::Equipos    TO rol_Consulta;
    DENY INSERT, UPDATE, DELETE ON SCHEMA::Eventos    TO rol_Consulta;

    /* -------------------------------------------------------------------------
       3. Permisos para rol_GestorPublicidad
          - Control operativo total del esquema Publicidad por SP.
          - DENY puntual sobre cotizaciones TipoCambio_* (administradas por API / admin).
          - Consulta de fixture y sedes para calendarización de pauta.
    ------------------------------------------------------------------------- */
    GRANT EXECUTE ON SCHEMA::Publicidad TO rol_GestorPublicidad;

    -- Restricción puntual: TipoCambio es alimentado por APIs externas y mantenido por el admin
    DENY EXECUTE ON Publicidad.TipoCambio_Alta         TO rol_GestorPublicidad;
    DENY EXECUTE ON Publicidad.TipoCambio_Modificacion TO rol_GestorPublicidad;
    DENY EXECUTE ON Publicidad.TipoCambio_Baja         TO rol_GestorPublicidad;

    GRANT SELECT ON Torneo.vw_Fixture TO rol_GestorPublicidad;
    IF OBJECT_ID(N'Torneo.ConsultarFixture', N'P') IS NOT NULL
        GRANT EXECUTE ON Torneo.ConsultarFixture TO rol_GestorPublicidad;

    /* -------------------------------------------------------------------------
       4. Permisos para rol_CargadorResultados
          - Carga operativa de eventos de partido (goles, tarjetas, cambios, formaciones).
          - Ejecución de Torneo.RegistrarResultado (valida coherencia con eventos).
          - Consulta de reportes propios de eventos y resultados.
          - Consulta de fixture.
    ------------------------------------------------------------------------- */
    GRANT EXECUTE ON SCHEMA::Eventos TO rol_CargadorResultados;

    GRANT EXECUTE ON Torneo.RegistrarResultado TO rol_CargadorResultados;
    GRANT EXECUTE ON Torneo.Reporte_Resultados TO rol_CargadorResultados;

    GRANT SELECT ON Torneo.vw_Fixture TO rol_CargadorResultados;
    IF OBJECT_ID(N'Torneo.ConsultarFixture', N'P') IS NOT NULL
        GRANT EXECUTE ON Torneo.ConsultarFixture TO rol_CargadorResultados;

    /* -------------------------------------------------------------------------
       5. Permisos para rol_Administrador
          - Ejecución sobre todos los procedimientos y funciones de los esquemas.
          - Lectura sobre vistas analíticas y tablas de configuración del sistema.
    ------------------------------------------------------------------------- */
    GRANT EXECUTE ON SCHEMA::Torneo     TO rol_Administrador;
    GRANT EXECUTE ON SCHEMA::Equipos    TO rol_Administrador;
    GRANT EXECUTE ON SCHEMA::Arbitraje  TO rol_Administrador;
    GRANT EXECUTE ON SCHEMA::Eventos    TO rol_Administrador;
    GRANT EXECUTE ON SCHEMA::Publicidad TO rol_Administrador;
    GRANT EXECUTE ON SCHEMA::Sistema    TO rol_Administrador;

    GRANT SELECT ON Torneo.vw_Fixture TO rol_Administrador;
    IF OBJECT_ID(N'Eventos.vw_HistorialTitularidad', N'V') IS NOT NULL
        GRANT SELECT ON Eventos.vw_HistorialTitularidad TO rol_Administrador;
    IF OBJECT_ID(N'Arbitraje.vw_HistorialArbitro', N'V') IS NOT NULL
        GRANT SELECT ON Arbitraje.vw_HistorialArbitro TO rol_Administrador;

    GRANT SELECT ON SCHEMA::Sistema TO rol_Administrador;

    PRINT 'Permisos de roles otorgados correctamente.';
END;
GO

-- =============================================================================
-- 3. SP: Sistema.CrearUsuarioPrueba
-- =============================================================================
/*
   Crea un usuario de base de datos sin login (WITHOUT LOGIN) y lo incorpora al rol
   especificado. Permite testear permisos mediante EXECUTE AS USER sin requerir
   exponer contraseñas ni dejar residuos a nivel de servidor tras DROP DATABASE.

   JUSTIFICACIÓN DE SQL DINÁMICO:
   Las instrucciones DDL CREATE USER y ALTER ROLE ... ADD MEMBER no aceptan variables
   ni parámetros como identificadores en la sintaxis de T-SQL. Se emplea SQL dinámico
   saneando los identificadores mediante QUOTENAME() para prevenir inyección SQL.
*/
CREATE OR ALTER PROCEDURE Sistema.CrearUsuarioPrueba
    @usuario sysname,
    @rol     sysname
AS
BEGIN
    SET NOCOUNT ON;

    /* -------------------------------------------------------------------------
       1. Validación acumulativa de parámetros y existencia de objetos
    ------------------------------------------------------------------------- */
    DECLARE @errores nvarchar(2000) = N'';

    SET @usuario = LTRIM(RTRIM(@usuario));
    SET @rol     = LTRIM(RTRIM(@rol));

    IF @usuario IS NULL OR @usuario = N''
        SET @errores = CONCAT(@errores, CHAR(10), N'- El nombre de usuario no puede estar vacío.');

    IF @rol IS NULL OR @rol = N''
        SET @errores = CONCAT(@errores, CHAR(10), N'- El nombre de rol no puede estar vacío.');

    -- Validar que el rol exista y sea de tipo ROLE ('R')
    IF @rol IS NOT NULL AND @rol <> N'' AND NOT EXISTS (
        SELECT 1 FROM sys.database_principals WHERE name = @rol AND type = 'R'
    )
        SET @errores = CONCAT(@errores, CHAR(10), N'- El rol especificado no existe: ', @rol);

    -- Validar que el usuario no exista previamente en la base de datos
    IF @usuario IS NOT NULL AND @usuario <> N'' AND EXISTS (
        SELECT 1 FROM sys.database_principals WHERE name = @usuario
    )
        SET @errores = CONCAT(@errores, CHAR(10), N'- El usuario de base de datos ya existe: ', @usuario);

    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo crear el usuario de prueba:' + @errores;
        THROW 50001, @errores, 1;
    END;

    /* -------------------------------------------------------------------------
       2. Creación del usuario y asociación al rol (SQL dinámico justificado)
    ------------------------------------------------------------------------- */
    DECLARE @sql nvarchar(max);
    SET @sql = N'CREATE USER ' + QUOTENAME(@usuario) + N' WITHOUT LOGIN; '
             + N'ALTER ROLE '  + QUOTENAME(@rol)     + N' ADD MEMBER ' + QUOTENAME(@usuario) + N';';

    EXEC sys.sp_executesql @sql;

    PRINT CONCAT('Usuario de prueba [', @usuario, '] creado y asignado al rol [', @rol, '].');
END;
GO

-- =============================================================================
-- 4. SP: Sistema.OtorgarPermisosDescifrado
-- =============================================================================
/*
   Otorga permisos a rol_Administrador para inspeccionar o abrir claves simétricas
   de cifrado (Entrega 8 - Cifrado de datos sensibles).
   Se diseña desacoplado: si el script 70 de Persona 1 aún no fue ejecutado en el
   ambiente, el procedimiento no aborta ni interrumpe la recreación, emitiendo
   un aviso informativo por consola.
*/
CREATE OR ALTER PROCEDURE Sistema.OtorgarPermisosDescifrado
    @nombreClave sysname = N'ClaveSimetricaMundial'
AS
BEGIN
    SET NOCOUNT ON;

    -- Si no existe la clave indicada, buscar si existe alguna clave simétrica creada por usuario
    IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = @nombreClave)
    BEGIN
        SELECT TOP 1 @nombreClave = name
        FROM sys.symmetric_keys
        WHERE name NOT IN (N'##MS_ServiceMasterKey##', N'##MS_DatabaseMasterKey##')
        ORDER BY create_date DESC;
    END;

    -- Otorgar permiso si se encontró una clave válida
    IF @nombreClave IS NOT NULL AND EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = @nombreClave)
    BEGIN
        DECLARE @sql nvarchar(max);
        SET @sql = N'GRANT VIEW DEFINITION ON SYMMETRIC KEY::' + QUOTENAME(@nombreClave) + N' TO rol_Administrador;';
        EXEC sys.sp_executesql @sql;

        PRINT CONCAT('Permiso VIEW DEFINITION sobre clave simétrica [', @nombreClave, '] concedido a rol_Administrador.');
    END
    ELSE
    BEGIN
        PRINT 'ADVERTENCIA: No se detectó clave simétrica de usuario en la base de datos. Permiso de descifrado omitido temporalmente (pendiente de script 70).';
    END;
END;
GO

-- =============================================================================
-- 5. EJECUCIÓN INICIAL Y CONFIGURACIÓN DE ROLES Y USUARIOS DE PRUEBA
-- =============================================================================
PRINT '------------------------------------------------------------------------';
PRINT 'Iniciando configuración de seguridad de Entrega 8...';
PRINT '------------------------------------------------------------------------';

-- 1. Crear roles
EXEC Sistema.CrearRoles;

-- 2. Otorgar permisos a los roles
EXEC Sistema.OtorgarPermisosRoles;

-- 3. Crear usuarios de prueba (uno por cada rol)
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'usr_admin')
    EXEC Sistema.CrearUsuarioPrueba @usuario = 'usr_admin', @rol = 'rol_Administrador';

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'usr_cargador')
    EXEC Sistema.CrearUsuarioPrueba @usuario = 'usr_cargador', @rol = 'rol_CargadorResultados';

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'usr_publicidad')
    EXEC Sistema.CrearUsuarioPrueba @usuario = 'usr_publicidad', @rol = 'rol_GestorPublicidad';

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'usr_consulta')
    EXEC Sistema.CrearUsuarioPrueba @usuario = 'usr_consulta', @rol = 'rol_Consulta';

-- 4. Permisos de descifrado (condicional / desacoplado)
EXEC Sistema.OtorgarPermisosDescifrado;

PRINT '------------------------------------------------------------------------';
PRINT 'Configuración de seguridad completada exitosamente.';
PRINT '------------------------------------------------------------------------';
GO

-- =============================================================================
-- 6. CONSULTA DE AUDITORÍA: MATRIZ DE PERMISOS EFECTIVOS POR ROL
-- =============================================================================
SELECT
    r.name                                           AS rol,
    p.permission_name                                AS permiso,
    p.state_desc                                     AS estado,
    p.class_desc                                     AS clase,
    COALESCE(
        OBJECT_SCHEMA_NAME(p.major_id) + '.' + OBJECT_NAME(p.major_id),
        SCHEMA_NAME(p.major_id),
        sk.name,
        'Base de Datos'
    )                                                AS objetoOEsquema
FROM sys.database_permissions p
INNER JOIN sys.database_principals r ON r.principal_id = p.grantee_principal_id
LEFT JOIN sys.symmetric_keys sk ON sk.symmetric_key_id = p.major_id AND p.class_desc = 'SYMMETRIC_KEY'
WHERE r.name IN ('rol_Administrador', 'rol_CargadorResultados', 'rol_GestorPublicidad', 'rol_Consulta')
ORDER BY r.name, p.class_desc, objetoOEsquema, p.permission_name;
GO
