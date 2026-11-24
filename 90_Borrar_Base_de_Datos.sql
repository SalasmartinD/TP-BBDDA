/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 22/11/2026

 Objetivo    : Borrar la base de datos MundialFutbol para poder recrearla desde
               cero (91_Crear_Base_Completa.sql), y diagnosticar qué sesiones y
               transacciones la mantienen abierta.
               1. Lista las sesiones conectadas a la base y sus transacciones
                  activas (antes de borrar, para saber qué se va a cortar).
               2. Borra la base solo si existe. Antes la pasa a SINGLE_USER con
                  ROLLBACK IMMEDIATE: cierra las conexiones abiertas (por
                  ejemplo, otras ventanas de SSMS) y deshace sus transacciones,
                  así el DROP no falla con "la base de datos está en uso".
               El script puede ejecutarse varias veces: si la base no existe,
               informa que no hay nada para borrar.

 Uso         : Ejecutar completo, conectado a la instancia local. Para solo
               diagnosticar, ejecutar únicamente la sección 1.
               Por consola:
                 sqlcmd -S .\SQLEXPRESS -E -I -f 65001 -i 90_Borrar_Base_de_Datos.sql
================================================================================
*/

USE master;
GO

/* =============================================================================
   1. Diagnóstico: sesiones y transacciones sobre MundialFutbol
   Si la base no existe (DB_ID devuelve NULL), ambas consultas devuelven 0 filas.
   ============================================================================= */

-- 1.a) Sesiones conectadas a la base
SELECT s.session_id,
       s.login_name,
       s.host_name,
       s.program_name,
       s.status,
       c.client_net_address
FROM sys.dm_exec_sessions    AS s
INNER JOIN sys.dm_exec_connections AS c ON c.session_id = s.session_id
WHERE s.database_id = DB_ID(N'MundialFutbol');

-- 1.b) Transacciones activas de esas sesiones
SELECT s.session_id,
       s.login_name,
       s.host_name,
       s.program_name,
       t.transaction_begin_time,
       CASE t.transaction_state
            WHEN 0 THEN N'La transacción no se ha inicializado completamente'
            WHEN 1 THEN N'La transacción está iniciada y no ha empezado a modificarse'
            WHEN 2 THEN N'La transacción está activa'
            WHEN 3 THEN N'La transacción ha sido convalidada (commit) pero no totalmente finalizada'
            WHEN 4 THEN N'La transacción está siendo abortada'
            WHEN 5 THEN N'La transacción ha sido abortada'
       END AS transaction_state_desc
FROM sys.dm_exec_sessions AS s
INNER JOIN sys.dm_tran_session_transactions AS st ON st.session_id = s.session_id
INNER JOIN sys.dm_tran_active_transactions  AS t  ON t.transaction_id = st.transaction_id
WHERE s.database_id = DB_ID(N'MundialFutbol');
GO

/* =============================================================================
   2. Borrado de la base (solo si existe)
   La sentencia ALTER DATABASE / DROP DATABASE no admite el nombre como variable,
   por eso va escrito fijo (sin SQL dinámico).
   ============================================================================= */
IF DB_ID(N'MundialFutbol') IS NOT NULL
BEGIN
    ALTER DATABASE MundialFutbol SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE MundialFutbol;
    PRINT N'Base de datos MundialFutbol borrada.';
END
ELSE
    PRINT N'La base de datos MundialFutbol no existe: no hay nada para borrar.';
GO
