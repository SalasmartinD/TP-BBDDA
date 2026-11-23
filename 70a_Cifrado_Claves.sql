/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 23/11/2026

 Objetivo    : Entrega 8 (cifrado) - Jerarquía de claves y objetos de apoyo para
               cifrar los datos personales de jugadores, cuerpo técnico y árbitros:

                 Service Master Key (la crea el motor)
                  +- Database Master Key
                      +- Certificado CertDatosPersonales
                          +- Clave simétrica ClaveDatosPersonales (AES_256)

               - Seguridad.Secreto          : secretos de la base, cifrados con la
                                              clave simétrica (hoy, la pimienta de
                                              las huellas de búsqueda).
               - Seguridad.AbrirClave /
                 Seguridad.CerrarClave      : abren y cierran la clave simétrica sin
                                              cerrársela a un SP que ya la abrió.
               - Seguridad.ObtenerPimienta  : lee la pimienta con la clave abierta.
               - Seguridad.fn_Huella        : huella (SHA-256) para comparar por
                                              valor datos que están cifrados.

 Cómo se usa el resto del cifrado:
   70b  columnas cifradas + migración     70c  SP de ABM que cifran al escribir
   70d  vistas de descifrado              70e  negocio e importación de árbitros
   70f  reportes                          80j  pruebas

 Contraseña de la Database Master Key (el repositorio es público):
 - La contraseña real NO va en el repositorio. En @claveDMK va el marcador
   '<PASSWORD_DMK>' y cada uno carga la real localmente, sin commitearla.
 - Con el marcador sin reemplazar (por ejemplo, al recrear la base en el coloquio)
   se genera una contraseña aleatoria de un solo uso que no se guarda en ningún
   lado. La clave maestra queda protegida solo por la Service Master Key de este
   servidor: sirve para trabajar, pero no se puede restaurar en otro servidor.
 - Para poder descifrar una copia de la base en otro servidor hay que cargar
   @claveDMK y @rutaBackupClaves (carpeta FUERA del repositorio) antes de crear
   la base: el script respalda la clave maestra y el certificado con su clave
   privada. Si se pierden esos archivos o la contraseña, los datos cifrados no se
   pueden volver a leer. El certificado CertBackupMundial de la política de
   respaldo es otro y no hay que confundirlos.

 Estándares aplicados:
 - Cada objeto se crea solo si no existe (el script puede ejecutarse varias
   veces sin cambiar las claves ni la pimienta ya generadas).
 - SQL dinámico estrictamente justificado: CREATE SCHEMA exige ser la única
   sentencia del lote, y CREATE MASTER KEY / BACKUP CERTIFICATE / BACKUP MASTER KEY
   solo aceptan la contraseña y la ruta como literales, no como variables.
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

/* =============================================================================
   1. Esquema Seguridad
   ============================================================================= */

-- SQL dinámico justificado: CREATE SCHEMA tiene que ser la única sentencia del lote.
IF SCHEMA_ID(N'Seguridad') IS NULL
    EXEC (N'CREATE SCHEMA Seguridad');
GO

/* =============================================================================
   2. Database Master Key, certificado y clave simétrica
   ============================================================================= */

DECLARE @claveDMK          nvarchar(128) = N'<PASSWORD_DMK>';       -- reemplazar localmente; NO commitear
DECLARE @rutaBackupClaves  nvarchar(260) = N'<RUTA_BACKUP_CLAVES>'; -- carpeta fuera del repo, ej. D:\ClavesMundial\
DECLARE @sql               nvarchar(max);
DECLARE @contraseniaReal   bit = CASE WHEN @claveDMK = N'<PASSWORD_DMK>' THEN 0 ELSE 1 END;
DECLARE @respaldar         bit = CASE WHEN @contraseniaReal = 1
                                       AND @rutaBackupClaves <> N'<RUTA_BACKUP_CLAVES>' THEN 1 ELSE 0 END;
DECLARE @creoCertificado   bit = 0;

-- 2.1 Database Master Key
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
BEGIN
    IF @contraseniaReal = 0
    BEGIN
        -- Contraseña de un solo uso: 4 clases de caracteres para cumplir la política de contraseñas.
        SET @claveDMK = N'Dmk#' + CONVERT(nvarchar(64), CRYPT_GEN_RANDOM(24), 2) + N'-a1';
        PRINT N'AVISO: <PASSWORD_DMK> sin reemplazar. Se usó una contraseña aleatoria que no se guarda: la clave maestra queda protegida solo por la Service Master Key de este servidor.';
    END;

    -- SQL dinámico justificado: CREATE MASTER KEY solo acepta la contraseña como literal.
    SET @sql = N'CREATE MASTER KEY ENCRYPTION BY PASSWORD = N' + N'''' + REPLACE(@claveDMK, N'''', N'''''') + N'''';
    EXEC (@sql);
END;

-- 2.2 Certificado que protege la clave simétrica
IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'CertDatosPersonales')
BEGIN
    CREATE CERTIFICATE CertDatosPersonales
        WITH SUBJECT = N'Cifrado de datos personales del Mundial',   -- sin comas ni parentesis: el motor lo interpreta como nombre distinguido
             EXPIRY_DATE = '20361231';
    SET @creoCertificado = 1;
END;

-- 2.3 Clave simétrica AES-256 con la que se cifran las columnas
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'ClaveDatosPersonales')
    CREATE SYMMETRIC KEY ClaveDatosPersonales
        WITH ALGORITHM = AES_256
        ENCRYPTION BY CERTIFICATE CertDatosPersonales;

-- 2.4 Respaldo de la clave maestra y del certificado (solo si se cargaron los datos locales).
-- Los nombres llevan la fecha y la hora: cada base que se crea tiene su propio certificado y
-- recrearla no tiene que chocar con los archivos de la corrida anterior. La carpeta tiene que
-- existir y el servicio de SQL Server tiene que poder escribir en ella.
IF @respaldar = 1
BEGIN
    DECLARE @marca nvarchar(20) = FORMAT(SYSDATETIME(), N'yyyyMMdd_HHmmss');
    IF RIGHT(@rutaBackupClaves, 1) <> N'\' SET @rutaBackupClaves += N'\';

    BEGIN TRY
        -- SQL dinámico justificado: BACKUP ... TO FILE y la contraseña solo aceptan literales.
        SET @sql = N'BACKUP MASTER KEY TO FILE = N' + N'''' + REPLACE(@rutaBackupClaves + N'MundialFutbol_DMK_' + @marca + N'.key', N'''', N'''''') + N''''
                 + N' ENCRYPTION BY PASSWORD = N' + N'''' + REPLACE(@claveDMK, N'''', N'''''') + N'''' + N';';
        EXEC (@sql);

        SET @sql = N'BACKUP CERTIFICATE CertDatosPersonales TO FILE = N'
                 + N'''' + REPLACE(@rutaBackupClaves + N'CertDatosPersonales_' + @marca + N'.cer', N'''', N'''''') + N''''
                 + N' WITH PRIVATE KEY (FILE = N' + N'''' + REPLACE(@rutaBackupClaves + N'CertDatosPersonales_' + @marca + N'.pvk', N'''', N'''''') + N''''
                 + N', ENCRYPTION BY PASSWORD = N' + N'''' + REPLACE(@claveDMK, N'''', N'''''') + N'''' + N');';
        EXEC (@sql);

        PRINT N'Se respaldaron la clave maestra y el certificado en ' + @rutaBackupClaves + N' (guardar la carpeta y la contraseña fuera del servidor).';
    END TRY
    BEGIN CATCH
        DECLARE @msgBackup nvarchar(2000) = N'No se pudieron respaldar la clave maestra y el certificado en ' + @rutaBackupClaves
            + N': ' + ERROR_MESSAGE() + N' Verificar que la carpeta exista y que el servicio de SQL Server pueda escribir en ella; sin estos archivos una copia de la base no se podrá descifrar en otro servidor.';
        THROW 50010, @msgBackup, 1;
    END CATCH;
END
ELSE IF @creoCertificado = 1
    PRINT N'AVISO: no se respaldaron la clave maestra ni el certificado (faltan @claveDMK y @rutaBackupClaves). Una copia de la base restaurada en otro servidor no se podrá descifrar.';
GO

/* =============================================================================
   3. Seguridad.Secreto: secretos de la base, cifrados con la clave simétrica
   ============================================================================= */

IF OBJECT_ID(N'Seguridad.Secreto', N'U') IS NULL
BEGIN
    CREATE TABLE Seguridad.Secreto (
        nombre     varchar(30)     NOT NULL,
        valorCif   varbinary(256)  NOT NULL,

        CONSTRAINT PK_Secreto PRIMARY KEY (nombre)
    );
END
GO

-- La pimienta de las huellas se genera una sola vez: si se regenerara, las huellas
-- ya guardadas dejarían de coincidir y las reglas de duplicados dejarían de andar.
OPEN SYMMETRIC KEY ClaveDatosPersonales DECRYPTION BY CERTIFICATE CertDatosPersonales;

IF NOT EXISTS (SELECT 1 FROM Seguridad.Secreto WHERE nombre = 'PIMIENTA_HUELLA')
    INSERT INTO Seguridad.Secreto (nombre, valorCif)
    VALUES ('PIMIENTA_HUELLA',
            EncryptByKey(Key_GUID(N'ClaveDatosPersonales'),
                         CONVERT(nvarchar(100), CRYPT_GEN_RANDOM(32), 2)));

CLOSE SYMMETRIC KEY ClaveDatosPersonales;
GO

/* =============================================================================
   4. Seguridad.AbrirClave / Seguridad.CerrarClave
   Una clave abierta es de la sesión y un solo CLOSE la cierra para todos. Si un
   SP anidado la cerrara, el SP que lo llamó seguiría descifrando y recibiría NULL
   sin ningún error (verificado en la prueba de factibilidad). Por eso cada SP la
   cierra únicamente si fue él quien la abrió (@abrio = 1).
   ============================================================================= */

CREATE OR ALTER PROCEDURE Seguridad.AbrirClave
    @abrio bit = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @abrio = 0;

    IF NOT EXISTS (SELECT 1 FROM sys.openkeys
                   WHERE key_name = N'ClaveDatosPersonales' AND database_id = DB_ID())
    BEGIN
        OPEN SYMMETRIC KEY ClaveDatosPersonales DECRYPTION BY CERTIFICATE CertDatosPersonales;
        SET @abrio = 1;
    END;
END
GO

CREATE OR ALTER PROCEDURE Seguridad.CerrarClave
    @abrio bit
AS
BEGIN
    SET NOCOUNT ON;

    IF @abrio = 1
       AND EXISTS (SELECT 1 FROM sys.openkeys
                   WHERE key_name = N'ClaveDatosPersonales' AND database_id = DB_ID())
        CLOSE SYMMETRIC KEY ClaveDatosPersonales;
END
GO

/* =============================================================================
   5. Seguridad.ObtenerPimienta
   Lee la pimienta con la clave ya abierta. Si no se pudiera leer, corta con un
   error: calcular una huella sin pimienta la dejaría sin protección y, además,
   no coincidiría con las guardadas, sin que nadie se enterara.
   ============================================================================= */

CREATE OR ALTER PROCEDURE Seguridad.ObtenerPimienta
    @pimienta nvarchar(100) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT @pimienta = CONVERT(nvarchar(100), DecryptByKey(valorCif))
    FROM Seguridad.Secreto
    WHERE nombre = 'PIMIENTA_HUELLA';

    IF @pimienta IS NULL
        THROW 50010, N'No se pudo leer el secreto de cifrado: la clave simétrica no está abierta o el secreto no existe.', 1;
END
GO

/* =============================================================================
   6. Seguridad.fn_Huella
   Huella de búsqueda: SHA-256 de pimienta + nombre + apellido + fecha, con la
   misma normalización que las reglas de duplicados originales
   (UPPER(LTRIM(RTRIM(x)))). Es determinística (el mismo dato da la misma huella),
   a diferencia de EncryptByKey, que da un resultado distinto cada vez. Sirve solo
   para comparar por igualdad. Sin la pimienta, probando nombres de jugadores
   conocidos se podría descubrir qué huella corresponde a quién.
   El separador es el carácter 31 (separador de unidad), que no aparece en nombres.
   ============================================================================= */

CREATE OR ALTER FUNCTION Seguridad.fn_Huella
(
    @pimienta  nvarchar(100),
    @nombre    nvarchar(200),
    @apellido  nvarchar(200),
    @fecha     date
)
RETURNS varbinary(32)
AS
BEGIN
    RETURN HASHBYTES('SHA2_256',
                     CONCAT(@pimienta, NCHAR(31),
                            UPPER(LTRIM(RTRIM(@nombre))), NCHAR(31),
                            UPPER(LTRIM(RTRIM(@apellido))), NCHAR(31),
                            CONVERT(char(10), @fecha, 23)));
END
GO
