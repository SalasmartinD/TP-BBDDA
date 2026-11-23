/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 23/11/2026

 Objetivo    : Entrega 8 (cifrado) - Cifra los datos personales de las tablas
               existentes (script de modificación sobre componentes ya creados):

               Equipos.Jugador   : nombre, apellido, fechaNacimiento, altura, peso
               Equipos.Staff     : nombre, apellido, fechaNacimiento
               Arbitraje.Arbitro : nombre, apellido, genero

               Quedan en claro los datos deportivos o de cargo que los reportes
               filtran y agrupan (posicion, club, piernaHabil, rol, idSeleccion,
               idPais, categoria, fechaInternacional).

 Qué hace:
 1. Agrega una columna varbinary(256) con sufijo Cif por cada dato cifrado
    (nombreCif, apellidoCif...). Con AES_256 un nvarchar(60) lleno ocupa 180 bytes.
 2. Migra los datos existentes con EncryptByKey. Las fechas y los decimales se
    pasan a texto antes de cifrar (fecha con estilo 23).
 3. Agrega la columna huella varbinary(32) en Jugador y Arbitro: sirve para las
    reglas que comparan por valor (ver Seguridad.fn_Huella en 70a). EncryptByKey
    da un resultado distinto cada vez, así que no se pueden comparar dos textos
    cifrados.
 4. Verifica que todo se pueda descifrar y coincida con el original ANTES de
    borrar las columnas en claro. Si algo no coincide, se deshace todo.
 5. Elimina las columnas en claro y los CHECK de altura y peso, que ya no se
    pueden aplicar sobre un valor cifrado. Esas validaciones ya están en los SP de
    alta y modificación (10b), así que no se pierde ninguna.

 Después de este script las columnas en claro ya no existen: se leen con las
 vistas Equipos.vw_Jugador, Equipos.vw_Staff y Arbitraje.vw_Arbitro (70d) y se
 escriben con los SP de ABM (70c).

 Estándares aplicados:
 - El script puede ejecutarse más de una vez: cada paso se saltea si ya se hizo.
 - SQL dinámico estrictamente justificado: en una segunda ejecución las columnas
   en claro ya no existen y un UPDATE que las nombre no compilaría, aunque estuviera
   dentro de un IF. Se arma como texto y se ejecuta solo si las columnas existen.
 - Migración y verificación dentro de una transacción (con ROLLBACK si falla).
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

/* =============================================================================
   1. Columnas cifradas y huellas
   ============================================================================= */

IF COL_LENGTH(N'Equipos.Jugador', N'nombreCif') IS NULL
    ALTER TABLE Equipos.Jugador ADD
        nombreCif           varbinary(256) NULL,
        apellidoCif         varbinary(256) NULL,
        fechaNacimientoCif  varbinary(256) NULL,
        alturaCif           varbinary(256) NULL,
        pesoCif             varbinary(256) NULL,
        huella              varbinary(32)  NULL;   -- nombre + apellido + fechaNacimiento (NULL si no hay fecha)
GO

IF COL_LENGTH(N'Equipos.Staff', N'nombreCif') IS NULL
    ALTER TABLE Equipos.Staff ADD
        nombreCif           varbinary(256) NULL,
        apellidoCif         varbinary(256) NULL,
        fechaNacimientoCif  varbinary(256) NULL;
GO

IF COL_LENGTH(N'Arbitraje.Arbitro', N'nombreCif') IS NULL
    ALTER TABLE Arbitraje.Arbitro ADD
        nombreCif           varbinary(256) NULL,
        apellidoCif         varbinary(256) NULL,
        generoCif           varbinary(256) NULL,
        huella              varbinary(32)  NULL;   -- nombre + apellido (el país se compara en claro)
GO

/* =============================================================================
   2. Migración de los datos existentes y verificación
   ============================================================================= */

DECLARE @abrio bit, @pimienta nvarchar(100), @sql nvarchar(max), @distintos int;

BEGIN TRY
    EXEC Seguridad.AbrirClave @abrio = @abrio OUTPUT;
    EXEC Seguridad.ObtenerPimienta @pimienta = @pimienta OUTPUT;

    BEGIN TRANSACTION;

    -- 2.1 Equipos.Jugador
    IF COL_LENGTH(N'Equipos.Jugador', N'nombre') IS NOT NULL
    BEGIN
        -- SQL dinámico justificado: ver el encabezado (las columnas en claro pueden no existir).
        SET @sql = N'
        UPDATE Equipos.Jugador
        SET nombreCif          = EncryptByKey(Key_GUID(N''ClaveDatosPersonales''), nombre),
            apellidoCif        = EncryptByKey(Key_GUID(N''ClaveDatosPersonales''), apellido),
            fechaNacimientoCif = EncryptByKey(Key_GUID(N''ClaveDatosPersonales''), CONVERT(varchar(10), fechaNacimiento, 23)),
            alturaCif          = EncryptByKey(Key_GUID(N''ClaveDatosPersonales''), CONVERT(varchar(10), altura)),
            pesoCif            = EncryptByKey(Key_GUID(N''ClaveDatosPersonales''), CONVERT(varchar(10), peso)),
            huella             = CASE WHEN fechaNacimiento IS NULL THEN NULL
                                      ELSE Seguridad.fn_Huella(@p, nombre, apellido, fechaNacimiento) END;

        SELECT @n = COUNT(*)
        FROM Equipos.Jugador
        WHERE nombreCif IS NULL OR apellidoCif IS NULL
           OR CONVERT(nvarchar(60), DecryptByKey(nombreCif))   COLLATE Latin1_General_BIN2 <> nombre   COLLATE Latin1_General_BIN2
           OR CONVERT(nvarchar(60), DecryptByKey(apellidoCif)) COLLATE Latin1_General_BIN2 <> apellido COLLATE Latin1_General_BIN2
           OR ISNULL(TRY_CONVERT(date, CONVERT(varchar(10), DecryptByKey(fechaNacimientoCif)), 23), ''19000101'') <> ISNULL(fechaNacimiento, ''19000101'')
           OR ISNULL(TRY_CONVERT(decimal(5,2), CONVERT(varchar(10), DecryptByKey(alturaCif))), -1) <> ISNULL(altura, -1)
           OR ISNULL(TRY_CONVERT(decimal(5,2), CONVERT(varchar(10), DecryptByKey(pesoCif))), -1)   <> ISNULL(peso, -1)
           OR (fechaNacimiento IS NOT NULL AND huella IS NULL);';
        EXEC sys.sp_executesql @sql, N'@p nvarchar(100), @n int OUTPUT', @p = @pimienta, @n = @distintos OUTPUT;

        IF @distintos > 0
            THROW 50010, N'La migración de Equipos.Jugador no coincide con los datos originales. Se deshace todo.', 1;
    END;

    -- 2.2 Equipos.Staff
    IF COL_LENGTH(N'Equipos.Staff', N'nombre') IS NOT NULL
    BEGIN
        SET @sql = N'
        UPDATE Equipos.Staff
        SET nombreCif          = EncryptByKey(Key_GUID(N''ClaveDatosPersonales''), nombre),
            apellidoCif        = EncryptByKey(Key_GUID(N''ClaveDatosPersonales''), apellido),
            fechaNacimientoCif = EncryptByKey(Key_GUID(N''ClaveDatosPersonales''), CONVERT(varchar(10), fechaNacimiento, 23));

        SELECT @n = COUNT(*)
        FROM Equipos.Staff
        WHERE nombreCif IS NULL OR apellidoCif IS NULL
           OR CONVERT(nvarchar(60), DecryptByKey(nombreCif))   COLLATE Latin1_General_BIN2 <> nombre   COLLATE Latin1_General_BIN2
           OR CONVERT(nvarchar(60), DecryptByKey(apellidoCif)) COLLATE Latin1_General_BIN2 <> apellido COLLATE Latin1_General_BIN2
           OR ISNULL(TRY_CONVERT(date, CONVERT(varchar(10), DecryptByKey(fechaNacimientoCif)), 23), ''19000101'') <> ISNULL(fechaNacimiento, ''19000101'');';
        EXEC sys.sp_executesql @sql, N'@n int OUTPUT', @n = @distintos OUTPUT;

        IF @distintos > 0
            THROW 50010, N'La migración de Equipos.Staff no coincide con los datos originales. Se deshace todo.', 1;
    END;

    -- 2.3 Arbitraje.Arbitro
    IF COL_LENGTH(N'Arbitraje.Arbitro', N'nombre') IS NOT NULL
    BEGIN
        SET @sql = N'
        UPDATE Arbitraje.Arbitro
        SET nombreCif   = EncryptByKey(Key_GUID(N''ClaveDatosPersonales''), nombre),
            apellidoCif = EncryptByKey(Key_GUID(N''ClaveDatosPersonales''), apellido),
            generoCif   = EncryptByKey(Key_GUID(N''ClaveDatosPersonales''), genero),
            huella      = Seguridad.fn_Huella(@p, nombre, apellido, NULL);

        SELECT @n = COUNT(*)
        FROM Arbitraje.Arbitro
        WHERE nombreCif IS NULL OR apellidoCif IS NULL OR huella IS NULL
           OR CONVERT(nvarchar(60), DecryptByKey(nombreCif))   COLLATE Latin1_General_BIN2 <> nombre   COLLATE Latin1_General_BIN2
           OR CONVERT(nvarchar(60), DecryptByKey(apellidoCif)) COLLATE Latin1_General_BIN2 <> apellido COLLATE Latin1_General_BIN2
           OR ISNULL(CONVERT(varchar(20), DecryptByKey(generoCif)), '''') COLLATE Latin1_General_BIN2 <> ISNULL(genero, '''') COLLATE Latin1_General_BIN2;';
        EXEC sys.sp_executesql @sql, N'@p nvarchar(100), @n int OUTPUT', @p = @pimienta, @n = @distintos OUTPUT;

        IF @distintos > 0
            THROW 50010, N'La migración de Arbitraje.Arbitro no coincide con los datos originales. Se deshace todo.', 1;
    END;

    COMMIT TRANSACTION;
    EXEC Seguridad.CerrarClave @abrio = @abrio;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    EXEC Seguridad.CerrarClave @abrio = @abrio;
    THROW;
END CATCH;
GO

/* =============================================================================
   3. Restricciones de integridad y borrado de las columnas en claro
   (solo si todavía existen: la verificación del paso 2 ya pasó)
   ============================================================================= */

-- 3.1 Equipos.Jugador. Los CHECK de altura y peso se borran antes que sus columnas.
IF COL_LENGTH(N'Equipos.Jugador', N'nombre') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Jugador_Altura' AND parent_object_id = OBJECT_ID(N'Equipos.Jugador'))
        ALTER TABLE Equipos.Jugador DROP CONSTRAINT CK_Jugador_Altura;
    IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Jugador_Peso' AND parent_object_id = OBJECT_ID(N'Equipos.Jugador'))
        ALTER TABLE Equipos.Jugador DROP CONSTRAINT CK_Jugador_Peso;

    ALTER TABLE Equipos.Jugador DROP COLUMN nombre, apellido, fechaNacimiento, altura, peso;
END;
GO

ALTER TABLE Equipos.Jugador ALTER COLUMN nombreCif   varbinary(256) NOT NULL;
ALTER TABLE Equipos.Jugador ALTER COLUMN apellidoCif varbinary(256) NOT NULL;
GO

-- 3.2 Equipos.Staff
IF COL_LENGTH(N'Equipos.Staff', N'nombre') IS NOT NULL
    ALTER TABLE Equipos.Staff DROP COLUMN nombre, apellido, fechaNacimiento;
GO

ALTER TABLE Equipos.Staff ALTER COLUMN nombreCif   varbinary(256) NOT NULL;
ALTER TABLE Equipos.Staff ALTER COLUMN apellidoCif varbinary(256) NOT NULL;
GO

-- 3.3 Arbitraje.Arbitro
IF COL_LENGTH(N'Arbitraje.Arbitro', N'nombre') IS NOT NULL
    ALTER TABLE Arbitraje.Arbitro DROP COLUMN nombre, apellido, genero;
GO

ALTER TABLE Arbitraje.Arbitro ALTER COLUMN nombreCif   varbinary(256) NOT NULL;
ALTER TABLE Arbitraje.Arbitro ALTER COLUMN apellidoCif varbinary(256) NOT NULL;
ALTER TABLE Arbitraje.Arbitro ALTER COLUMN huella      varbinary(32)  NOT NULL;
GO

/* =============================================================================
   4. Índices de las huellas (aceleran las reglas de duplicados)
   ============================================================================= */

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Jugador_Huella' AND object_id = OBJECT_ID(N'Equipos.Jugador'))
    CREATE INDEX IX_Jugador_Huella ON Equipos.Jugador (huella);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Arbitro_Huella' AND object_id = OBJECT_ID(N'Arbitraje.Arbitro'))
    CREATE INDEX IX_Arbitro_Huella ON Arbitraje.Arbitro (idPais, huella);
GO
