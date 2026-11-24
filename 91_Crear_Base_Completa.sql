/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 22/11/2026

 Objetivo    : Crear la base de datos MundialFutbol completa desde un único
               archivo: ejecuta en orden los scripts de TP-BBDDA (esquema, ABM,
               negocio, funciones, importaciones, carga de datos, reportes,
               cifrado de datos personales y roles de seguridad).
               No ejecuta los scripts de testing (8x), que van por separado.
               Para empezar de cero, ejecutar antes 90_Borrar_Base_de_Datos.sql.
               Después del cifrado (70) este archivo NO se puede volver a
               ejecutar sobre la misma base: las cargas y los SP originales
               nombran columnas en claro que el 70b elimina. Si la base ya
               existe, ejecutar primero el 90.

 Requisitos  : Este archivo usa comandos de SQLCMD (:setvar, :r, :on error).
               - SSMS: menú Consulta > Modo SQLCMD activado.
               - Consola:
                   sqlcmd -S .\SQLEXPRESS -E -I -f 65001 -i 91_Crear_Base_Completa.sql
                 (-I deja QUOTED_IDENTIFIER en ON; -f 65001 lee en UTF-8).
               Si el repositorio no está en C:\TP-BBDDA, editar solo la variable
               RUTA (carpeta TP-BBDDA de esta máquina, sin barra final) y no
               commitear ese cambio.
               Cifrado: sin tocar 70a, la clave maestra usa una contraseña
               aleatoria de un solo uso (ver el encabezado de 70a para poder
               restaurar la base en otro servidor).
               Al terminar, ejecutar 92_Ejecutar_Reportes.sql para ver los
               reportes.
================================================================================
*/

:setvar RUTA "C:\TP-BBDDA"

:on error exit

-- 00 Base de datos, esquemas y tablas
:r $(RUTA)\00_InitialSchema.sql

-- 10 a 12: SP de ABM
:r $(RUTA)\10a_ABM_Torneo.sql
:r $(RUTA)\10b_ABM_Equipos.sql
:r $(RUTA)\10c_ABM_TipoCambio.sql
:r $(RUTA)\11a_ABM_Arbitraje.sql
:r $(RUTA)\11b_ABM_EventosPartido.sql
:r $(RUTA)\11c_ABM_CuerpoTecnicoPartido.sql
:r $(RUTA)\12_ABM_Publicidad.sql

-- 20 a 22: SP de negocio
:r $(RUTA)\20a_Negocio_Torneo.sql
:r $(RUTA)\20b_Negocio_Equipos.sql
:r $(RUTA)\21_SP_Negocio_Arbitraje_Eventos.sql
:r $(RUTA)\22_Negocio_Publicidad.sql

-- 30 a 32: vistas, funciones y fixture
:r $(RUTA)\30a_Fixture.sql
:r $(RUTA)\31_Fn_Eventos_Arbitraje.sql
:r $(RUTA)\32_SimulPrimeTime.sql
:r $(RUTA)\32b_Vistas_BI.sql

-- 40 a 43: SP de importación
:r $(RUTA)\40a_Importar_FixtureCSV.sql
:r $(RUTA)\41_Importar_Arbitros_XML.sql
:r $(RUTA)\43_Importar_APIs.sql

-- 50 a 54: carga de datos
:r $(RUTA)\50a_Carga_Torneo.sql
:r $(RUTA)\50b_Carga_Equipos.sql
:r $(RUTA)\50c_Carga_Partidos.sql
:r $(RUTA)\50d_Carga_Parametros.sql
:r $(RUTA)\50f_Carga_APIs.sql
:r $(RUTA)\51a_Carga_Arbitros_Parametros.sql
:r $(RUTA)\51b_Carga_Partidos_Eventos.sql
:r $(RUTA)\51c_Carga_Informes_Arbitrales.sql
:r $(RUTA)\52_CargaPublicidad.sql
:r $(RUTA)\53_Cierre_Partidos.sql
:r $(RUTA)\54_Estados_Exhibiciones.sql

-- 60 a 62: SP de reportes
:r $(RUTA)\60_Reportes_Torneo.sql
:r $(RUTA)\61_Reportes_Arbitraje_Eventos.sql
:r $(RUTA)\62_Reportes_Publicidad.sql

-- 70: cifrado de datos personales (va después de las cargas: el 70b migra los
--     datos ya cargados y redefine SP de 10b, 11a, 21, 31, 41, 60 y 61)
:r $(RUTA)\70a_Cifrado_Claves.sql
:r $(RUTA)\70b_Cifrado_Tablas.sql
:r $(RUTA)\70c_Cifrado_SP_ABM.sql
:r $(RUTA)\70d_Cifrado_Vistas.sql
:r $(RUTA)\70e_Cifrado_Negocio_Importacion.sql
:r $(RUTA)\70f_Cifrado_Reportes.sql

-- 71: roles, permisos y usuarios de prueba (va último: da permisos sobre objetos
--     que el 70 redefine)
:r $(RUTA)\71a_Roles_Seguridad.sql
:r $(RUTA)\71b_Roles_BI_App.sql

PRINT N'Creación de la base de datos MundialFutbol finalizada.';
GO
