/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 23/11/2026

 Objetivo    : Pruebas del cifrado de datos personales (scripts 70a a 70f):

               1. Estructura: las columnas en claro ya no existen, las cifradas son
                  binarias, la jerarquía de claves existe y todo lo migrado se
                  descifra.
               2. Ida y vuelta: jugador, staff y árbitro se guardan sin el texto
                  original y se leen iguales por las vistas; EncryptByKey da un
                  resultado distinto en cada escritura.
               3. Reglas de duplicados por huella: mismo mensaje y mismo error 50001
                  que antes del cifrado, sin distinguir mayúsculas ni espacios.
               4. Importación XML: el upsert repetido no duplica árbitros.
               5. Manejo de la clave: no queda abierta tras un alta correcta ni tras
                  un error, y un SP no se la cierra a quien ya la había abierto.
               6. Permisos con un usuario sin login: sin permisos sobre la tabla
                  base da error 229; la vista devuelve NULL sin error (o 229 con
                  DENY); no puede abrir la clave ni leer el secreto; con solo
                  EXECUTE puede dar de alta y correr los reportes, que devuelven
                  los nombres en claro.

 Requisitos  : Los scripts 00 a 62 y 70a a 70f (en ese orden). No hace falta el 71:
               el usuario de prueba se crea y se borra en este mismo script.

 Datos de prueba:
 - Personas con apellido que empieza con Prueba80j y el usuario usr_prueba80j.
 - Se limpian al inicio y al final: el script se puede ejecutar varias veces.

 Cada prueba imprime [OK] o [FALLO]. Resultado esperado: todas [OK].
================================================================================
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

PRINT '================================================================================';
PRINT ' PRUEBAS: 70a a 70f (cifrado de datos personales)';
PRINT '================================================================================';
GO

/* =============================================================================
   LIMPIEZA PREVIA
   ============================================================================= */
IF EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = N'ClaveDatosPersonales' AND database_id = DB_ID())
    CLOSE SYMMETRIC KEY ClaveDatosPersonales;
IF DATABASE_PRINCIPAL_ID(N'usr_prueba80j') IS NOT NULL
    DROP USER usr_prueba80j;
DELETE FROM Arbitraje.ArbitroIdioma WHERE idArbitro IN (SELECT idArbitro FROM Arbitraje.vw_Arbitro WHERE apellido LIKE N'Prueba80j%');
DELETE FROM Arbitraje.Arbitro WHERE idArbitro IN (SELECT idArbitro FROM Arbitraje.vw_Arbitro WHERE apellido LIKE N'Prueba80j%');
DELETE FROM Equipos.Staff WHERE id IN (SELECT id FROM Equipos.vw_Staff WHERE apellido LIKE N'Prueba80j%');
DELETE FROM Equipos.Jugador WHERE id IN (SELECT id FROM Equipos.vw_Jugador WHERE apellido LIKE N'Prueba80j%');
GO

/* =============================================================================
   1. ESTRUCTURA
   ============================================================================= */
PRINT '--- 1. Estructura ---';

-- PRUEBA 1.1: las columnas en claro ya no existen
-- Resultado esperado: ninguna de las 11 columnas originales sigue en las tablas.
IF COL_LENGTH('Equipos.Jugador', 'nombre') IS NULL AND COL_LENGTH('Equipos.Jugador', 'apellido') IS NULL
   AND COL_LENGTH('Equipos.Jugador', 'fechaNacimiento') IS NULL AND COL_LENGTH('Equipos.Jugador', 'altura') IS NULL
   AND COL_LENGTH('Equipos.Jugador', 'peso') IS NULL
   AND COL_LENGTH('Equipos.Staff', 'nombre') IS NULL AND COL_LENGTH('Equipos.Staff', 'apellido') IS NULL
   AND COL_LENGTH('Equipos.Staff', 'fechaNacimiento') IS NULL
   AND COL_LENGTH('Arbitraje.Arbitro', 'nombre') IS NULL AND COL_LENGTH('Arbitraje.Arbitro', 'apellido') IS NULL
   AND COL_LENGTH('Arbitraje.Arbitro', 'genero') IS NULL
    PRINT '[OK] PRUEBA 1.1: las 11 columnas en claro ya no existen.';
ELSE PRINT '[FALLO] PRUEBA 1.1: queda alguna columna personal en claro.';

-- PRUEBA 1.2: las columnas cifradas son varbinary
-- Resultado esperado: 11 columnas Cif, todas varbinary.
IF (SELECT COUNT(*) FROM sys.columns c
    WHERE c.object_id IN (OBJECT_ID('Equipos.Jugador'), OBJECT_ID('Equipos.Staff'), OBJECT_ID('Arbitraje.Arbitro'))
      AND c.name LIKE '%Cif' AND TYPE_NAME(c.system_type_id) = 'varbinary') = 11
    PRINT '[OK] PRUEBA 1.2: las 11 columnas cifradas son varbinary.';
ELSE PRINT '[FALLO] PRUEBA 1.2: no hay 11 columnas Cif de tipo varbinary.';

-- PRUEBA 1.3: jerarquía de claves
-- Resultado esperado: clave maestra de la base, certificado y clave simétrica AES_256.
IF EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
   AND EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'CertDatosPersonales')
   AND EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'ClaveDatosPersonales' AND algorithm_desc = N'AES_256')
    PRINT '[OK] PRUEBA 1.3: existen la clave maestra, el certificado y la clave AES_256.';
ELSE PRINT '[FALLO] PRUEBA 1.3: falta algún objeto de la jerarquía de claves.';

-- PRUEBA 1.4: todo lo migrado se descifra
-- Resultado esperado: las vistas tienen tantas filas como las tablas y ninguna con nombre o apellido NULL.
IF (SELECT COUNT(*) FROM Equipos.vw_Jugador)  = (SELECT COUNT(*) FROM Equipos.Jugador)
   AND (SELECT COUNT(*) FROM Equipos.vw_Staff)   = (SELECT COUNT(*) FROM Equipos.Staff)
   AND (SELECT COUNT(*) FROM Arbitraje.vw_Arbitro) = (SELECT COUNT(*) FROM Arbitraje.Arbitro)
   AND NOT EXISTS (SELECT 1 FROM Equipos.vw_Jugador   WHERE nombre IS NULL OR apellido IS NULL)
   AND NOT EXISTS (SELECT 1 FROM Equipos.vw_Staff     WHERE nombre IS NULL OR apellido IS NULL)
   AND NOT EXISTS (SELECT 1 FROM Arbitraje.vw_Arbitro WHERE nombre IS NULL OR apellido IS NULL)
    PRINT '[OK] PRUEBA 1.4: todas las filas se descifran (nombre y apellido no son NULL).';
ELSE PRINT '[FALLO] PRUEBA 1.4: hay filas que no se descifran.';

-- PRUEBA 1.5: la pimienta está cifrada
-- Resultado esperado: sin la clave abierta no se puede leer; con la clave abierta tiene 64 caracteres.
DECLARE @sinClave nvarchar(100) = (SELECT CONVERT(nvarchar(100), DecryptByKey(valorCif)) FROM Seguridad.Secreto WHERE nombre = 'PIMIENTA_HUELLA');
DECLARE @conClave nvarchar(100);
OPEN SYMMETRIC KEY ClaveDatosPersonales DECRYPTION BY CERTIFICATE CertDatosPersonales;
SET @conClave = (SELECT CONVERT(nvarchar(100), DecryptByKey(valorCif)) FROM Seguridad.Secreto WHERE nombre = 'PIMIENTA_HUELLA');
CLOSE SYMMETRIC KEY ClaveDatosPersonales;
IF @sinClave IS NULL AND LEN(@conClave) = 64
    PRINT '[OK] PRUEBA 1.5: la pimienta solo se lee con la clave abierta.';
ELSE PRINT '[FALLO] PRUEBA 1.5: la pimienta se leyó sin la clave o no tiene 64 caracteres.';
GO

/* =============================================================================
   2. IDA Y VUELTA
   ============================================================================= */
PRINT '--- 2. Ida y vuelta ---';

-- PRUEBA 2.1: jugador
-- Resultado esperado: lo guardado no contiene el texto original; la vista devuelve los mismos valores.
DECLARE @id int;
BEGIN TRY
    EXEC Equipos.Jugador_Alta @nombre = N'Uno', @apellido = N'Prueba80j Cifrado', @fechaNacimiento = '2001-02-03',
         @altura = 1.82, @peso = 77.50, @piernaHabil = 'Derecha', @club = N'Club Prueba', @posicion = 'Delantero', @id = @id OUTPUT;

    IF EXISTS (SELECT 1 FROM Equipos.Jugador
               WHERE id = @id
                 AND CHARINDEX(CAST(N'Prueba80j Cifrado' AS varbinary(200)), apellidoCif) = 0
                 AND CHARINDEX(CAST('Prueba80j Cifrado'  AS varbinary(200)), apellidoCif) = 0
                 AND DATALENGTH(apellidoCif) > 32 AND DATALENGTH(fechaNacimientoCif) > 32
                 AND DATALENGTH(alturaCif) > 32 AND DATALENGTH(pesoCif) > 32)
       AND EXISTS (SELECT 1 FROM Equipos.vw_Jugador
                   WHERE id = @id
                     AND nombre   COLLATE Latin1_General_BIN2 = N'Uno'
                     AND apellido COLLATE Latin1_General_BIN2 = N'Prueba80j Cifrado'
                     AND fechaNacimiento = '2001-02-03' AND altura = 1.82 AND peso = 77.50
                     AND piernaHabil = 'Derecha' AND club = N'Club Prueba' AND posicion = 'Delantero')
        PRINT '[OK] PRUEBA 2.1: el jugador se guarda cifrado y se lee igual por la vista.';
    ELSE PRINT '[FALLO] PRUEBA 2.1: lo guardado contiene el texto original o la vista no devuelve lo mismo.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.1: error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 2.2: integrante del cuerpo técnico
-- Resultado esperado: se guarda cifrado y se lee igual por la vista (incluida la fecha de nacimiento).
DECLARE @id int, @idSel int = (SELECT TOP (1) id FROM Equipos.Seleccion ORDER BY id);
BEGIN TRY
    EXEC Equipos.Staff_Alta @idSeleccion = @idSel, @nombre = N'Ayudante', @apellido = N'Prueba80j Staff',
         @rol = 'Ayudante', @fechaNacimiento = '1975-11-20', @id = @id OUTPUT;

    IF EXISTS (SELECT 1 FROM Equipos.Staff
               WHERE id = @id AND CHARINDEX(CAST(N'Prueba80j Staff' AS varbinary(200)), apellidoCif) = 0
                 AND DATALENGTH(fechaNacimientoCif) > 32)
       AND EXISTS (SELECT 1 FROM Equipos.vw_Staff
                   WHERE id = @id AND nombre COLLATE Latin1_General_BIN2 = N'Ayudante'
                     AND apellido COLLATE Latin1_General_BIN2 = N'Prueba80j Staff'
                     AND fechaNacimiento = '1975-11-20' AND rol = 'Ayudante' AND idSeleccion = @idSel)
        PRINT '[OK] PRUEBA 2.2: el integrante del cuerpo técnico se guarda cifrado y se lee igual.';
    ELSE PRINT '[FALLO] PRUEBA 2.2: lo guardado no está cifrado o la vista no devuelve lo mismo.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.2: error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 2.3: árbitro
-- Resultado esperado: nombre, apellido y género se guardan cifrados y se leen iguales; el país queda en claro.
DECLARE @id int, @idPais int = (SELECT TOP (1) id FROM Torneo.Pais ORDER BY id);
BEGIN TRY
    EXEC Arbitraje.Arbitro_Alta @idPais = @idPais, @nombre = N'Arbitro', @apellido = N'Prueba80j Arbitro',
         @categoria = 'FIFA', @genero = 'Femenino', @fechaInternacional = '2015-01-01', @idArbitro = @id OUTPUT;

    IF EXISTS (SELECT 1 FROM Arbitraje.Arbitro
               WHERE idArbitro = @id AND idPais = @idPais
                 AND CHARINDEX(CAST(N'Prueba80j Arbitro' AS varbinary(200)), apellidoCif) = 0
                 AND CHARINDEX(CAST('Femenino' AS varbinary(200)), generoCif) = 0 AND DATALENGTH(generoCif) > 32)
       AND EXISTS (SELECT 1 FROM Arbitraje.vw_Arbitro
                   WHERE idArbitro = @id AND nombre COLLATE Latin1_General_BIN2 = N'Arbitro'
                     AND apellido COLLATE Latin1_General_BIN2 = N'Prueba80j Arbitro'
                     AND genero = 'Femenino' AND categoria = 'FIFA' AND fechaInternacional = '2015-01-01')
        PRINT '[OK] PRUEBA 2.3: el árbitro se guarda cifrado y se lee igual.';
    ELSE PRINT '[FALLO] PRUEBA 2.3: lo guardado no está cifrado o la vista no devuelve lo mismo.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.3: error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 2.4: modificación
-- Resultado esperado: tras Jugador_Modificacion la vista devuelve el valor nuevo y no el anterior.
DECLARE @id int = (SELECT id FROM Equipos.vw_Jugador WHERE apellido = N'Prueba80j Cifrado');
BEGIN TRY
    EXEC Equipos.Jugador_Modificacion @id = @id, @nombre = N'Dos', @apellido = N'Prueba80j Cifrado',
         @fechaNacimiento = '2001-02-03', @altura = 1.90, @peso = 80, @piernaHabil = 'Izquierda',
         @club = N'Otro Club', @posicion = 'Defensor';

    IF EXISTS (SELECT 1 FROM Equipos.vw_Jugador
               WHERE id = @id AND nombre COLLATE Latin1_General_BIN2 = N'Dos' AND altura = 1.90 AND peso = 80
                 AND piernaHabil = 'Izquierda' AND club = N'Otro Club' AND posicion = 'Defensor')
        PRINT '[OK] PRUEBA 2.4: la modificación se guarda cifrada y se lee con el valor nuevo.';
    ELSE PRINT '[FALLO] PRUEBA 2.4: la vista no devuelve los valores modificados.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.4: error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 2.5: EncryptByKey no es determinístico
-- Resultado esperado: dos jugadores con el mismo nombre y apellido (sin fecha, así no chocan con la regla de
-- duplicados) guardan valores cifrados distintos, pero la vista muestra el mismo texto.
DECLARE @a int, @b int;
BEGIN TRY
    EXEC Equipos.Jugador_Alta @nombre = N'Igual', @apellido = N'Prueba80j Mismo', @id = @a OUTPUT;
    EXEC Equipos.Jugador_Alta @nombre = N'Igual', @apellido = N'Prueba80j Mismo', @id = @b OUTPUT;
    IF (SELECT apellidoCif FROM Equipos.Jugador WHERE id = @a) <> (SELECT apellidoCif FROM Equipos.Jugador WHERE id = @b)
       AND (SELECT apellido FROM Equipos.vw_Jugador WHERE id = @a) = (SELECT apellido FROM Equipos.vw_Jugador WHERE id = @b)
        PRINT '[OK] PRUEBA 2.5: mismo texto, distinto valor cifrado, misma lectura.';
    ELSE PRINT '[FALLO] PRUEBA 2.5: el cifrado dio el mismo valor o la lectura no coincide.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.5: error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   3. REGLAS DE DUPLICADOS POR HUELLA
   Jugador: mismo nombre + apellido + fecha de nacimiento.
   Árbitro: mismo país + nombre + apellido.
   ============================================================================= */
PRINT '--- 3. Reglas de duplicados ---';

-- PRUEBA 3.1: jugador repetido
-- Resultado esperado: error 50001 "Ya existe un jugador con el mismo nombre, apellido y fecha de nacimiento."
BEGIN TRY
    EXEC Equipos.Jugador_Alta @nombre = N'Dos', @apellido = N'Prueba80j Cifrado', @fechaNacimiento = '2001-02-03';
    PRINT '[FALLO] PRUEBA 3.1: se aceptó un jugador repetido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%Ya existe un jugador con el mismo nombre, apellido y fecha de nacimiento%'
        PRINT '[OK] PRUEBA 3.1: jugador repetido rechazado con el mensaje de siempre.';
    ELSE PRINT '[FALLO] PRUEBA 3.1: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.2: igual, con otras mayúsculas y espacios en los extremos
-- Resultado esperado: error 50001 (la regla ignora mayúsculas y espacios, como antes).
BEGIN TRY
    EXEC Equipos.Jugador_Alta @nombre = N'  dOS ', @apellido = N' PRUEBA80J cifrado  ', @fechaNacimiento = '2001-02-03';
    PRINT '[FALLO] PRUEBA 3.2: se aceptó un jugador repetido con otras mayúsculas.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%Ya existe un jugador con el mismo nombre%'
        PRINT '[OK] PRUEBA 3.2: la regla ignora mayúsculas y espacios de los extremos.';
    ELSE PRINT '[FALLO] PRUEBA 3.2: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.3: misma persona con otra fecha de nacimiento
-- Resultado esperado: se acepta (no es un duplicado).
BEGIN TRY
    EXEC Equipos.Jugador_Alta @nombre = N'Dos', @apellido = N'Prueba80j Cifrado', @fechaNacimiento = '2002-02-03';
    PRINT '[OK] PRUEBA 3.3: otra fecha de nacimiento no es un duplicado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 3.3: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.4: modificar un jugador para que coincida con otro
-- Resultado esperado: error 50001 "Ya existe otro jugador con el mismo nombre, apellido y fecha de nacimiento."
DECLARE @id int = (SELECT id FROM Equipos.vw_Jugador WHERE apellido = N'Prueba80j Cifrado' AND fechaNacimiento = '2002-02-03');
BEGIN TRY
    EXEC Equipos.Jugador_Modificacion @id = @id, @nombre = N'Dos', @apellido = N'Prueba80j Cifrado', @fechaNacimiento = '2001-02-03';
    PRINT '[FALLO] PRUEBA 3.4: se aceptó una modificación que duplica a otro jugador.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%Ya existe otro jugador con el mismo nombre, apellido y fecha de nacimiento%'
        PRINT '[OK] PRUEBA 3.4: la modificación que duplica a otro jugador fue rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 3.4: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.5: modificar un jugador sin cambiar su nombre, apellido ni fecha
-- Resultado esperado: se acepta (el jugador no cuenta como duplicado de sí mismo).
DECLARE @id int = (SELECT id FROM Equipos.vw_Jugador WHERE apellido = N'Prueba80j Cifrado' AND fechaNacimiento = '2001-02-03');
BEGIN TRY
    EXEC Equipos.Jugador_Modificacion @id = @id, @nombre = N'Dos', @apellido = N'Prueba80j Cifrado',
         @fechaNacimiento = '2001-02-03', @club = N'Club Nuevo';
    IF EXISTS (SELECT 1 FROM Equipos.vw_Jugador WHERE id = @id AND club = N'Club Nuevo')
        PRINT '[OK] PRUEBA 3.5: un jugador no es duplicado de sí mismo al modificarlo.';
    ELSE PRINT '[FALLO] PRUEBA 3.5: la modificación no se aplicó.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 3.5: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.6: árbitro repetido en el mismo país
-- Resultado esperado: error 50001 "Ya existe un árbitro registrado con el mismo nombre y apellido para dicho país."
DECLARE @idPais int = (SELECT TOP (1) idPais FROM Arbitraje.vw_Arbitro WHERE apellido = N'Prueba80j Arbitro');
BEGIN TRY
    EXEC Arbitraje.Arbitro_Alta @idPais = @idPais, @nombre = N' ARBITRO ', @apellido = N'prueba80j arbitro', @categoria = 'FIFA';
    PRINT '[FALLO] PRUEBA 3.6: se aceptó un árbitro repetido en el mismo país.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%Ya existe un árbitro registrado con el mismo nombre y apellido%'
        PRINT '[OK] PRUEBA 3.6: árbitro repetido rechazado (ignora mayúsculas y espacios).';
    ELSE PRINT '[FALLO] PRUEBA 3.6: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.7: el mismo nombre en otro país
-- Resultado esperado: se acepta.
DECLARE @idOtroPais int = (SELECT TOP (1) id FROM Torneo.Pais
                           WHERE id <> (SELECT TOP (1) idPais FROM Arbitraje.vw_Arbitro WHERE apellido = N'Prueba80j Arbitro')
                           ORDER BY id);
BEGIN TRY
    EXEC Arbitraje.Arbitro_Alta @idPais = @idOtroPais, @nombre = N'Arbitro', @apellido = N'Prueba80j Arbitro', @categoria = 'FIFA';
    PRINT '[OK] PRUEBA 3.7: el mismo nombre en otro país no es un duplicado.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 3.7: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.8: modificar un árbitro para que coincida con otro del mismo país
-- Resultado esperado: error 50001 "Ya existe otro árbitro registrado con el mismo nombre y apellido para dicho país."
DECLARE @idPais int = (SELECT TOP (1) idPais FROM Arbitraje.vw_Arbitro WHERE apellido = N'Prueba80j Arbitro' ORDER BY idArbitro);
DECLARE @idAux int;
BEGIN TRY
    EXEC Arbitraje.Arbitro_Alta @idPais = @idPais, @nombre = N'Otro', @apellido = N'Prueba80j Aux', @categoria = 'FIFA', @idArbitro = @idAux OUTPUT;
    EXEC Arbitraje.Arbitro_Modificacion @idArbitro = @idAux, @idPais = @idPais, @nombre = N'Arbitro',
         @apellido = N'Prueba80j Arbitro', @categoria = 'FIFA';
    PRINT '[FALLO] PRUEBA 3.8: se aceptó una modificación que duplica a otro árbitro.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%Ya existe otro árbitro registrado con el mismo nombre y apellido%'
        PRINT '[OK] PRUEBA 3.8: la modificación que duplica a otro árbitro fue rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 3.8: ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 3.9: Arbitro_Buscar
-- Resultado esperado: encuentra al árbitro sin distinguir mayúsculas ni espacios, y devuelve NULL si el nombre no
-- existe o si es de otro país.
DECLARE @idPais int = (SELECT TOP (1) idPais FROM Arbitraje.vw_Arbitro WHERE apellido = N'Prueba80j Arbitro' ORDER BY idArbitro);
DECLARE @esperado int = (SELECT TOP (1) idArbitro FROM Arbitraje.vw_Arbitro WHERE apellido = N'Prueba80j Arbitro' AND idPais = @idPais ORDER BY idArbitro);
DECLARE @encontrado int, @noExiste int, @otroPais int;
EXEC Arbitraje.Arbitro_Buscar @idPais = @idPais, @nombre = N' arbitro', @apellido = N'PRUEBA80J ARBITRO ', @idArbitro = @encontrado OUTPUT;
EXEC Arbitraje.Arbitro_Buscar @idPais = @idPais, @nombre = N'Nadie', @apellido = N'Prueba80j Inexistente', @idArbitro = @noExiste OUTPUT;
EXEC Arbitraje.Arbitro_Buscar @idPais = -1, @nombre = N'Arbitro', @apellido = N'Prueba80j Arbitro', @idArbitro = @otroPais OUTPUT;
IF @encontrado = @esperado AND @noExiste IS NULL AND @otroPais IS NULL
    PRINT '[OK] PRUEBA 3.9: Arbitro_Buscar encuentra por huella y devuelve NULL cuando no hay coincidencia.';
ELSE PRINT '[FALLO] PRUEBA 3.9: la búsqueda devolvió ' + ISNULL(CAST(@encontrado AS varchar(12)), 'NULL') + ' (esperado ' + CAST(@esperado AS varchar(12)) + ').';
GO

/* =============================================================================
   4. IMPORTACIÓN XML (upsert sin duplicados)
   ============================================================================= */
PRINT '--- 4. Importación XML ---';

-- PRUEBA 4.1 y 4.2: importar dos árbitros y repetir la importación
-- Resultado esperado: la primera inserta 2; la segunda actualiza 2 y no inserta ninguno; quedan 2 árbitros.
DECLARE @iso3 nvarchar(3) = (SELECT codigoISO3 FROM Torneo.Pais WHERE codigoISO2 = 'AR');
DECLARE @xml xml = CAST(CONCAT(N'<Arbitros>',
    N'<Arbitro><Nombre>Xml Uno</Nombre><Apellido>Prueba80j Xml A</Apellido><Pais codigoISO3="', @iso3, N'">Argentina</Pais>',
    N'<Categoria>FIFA</Categoria><Genero>Masculino</Genero><FechaInternacional>2012-03-04</FechaInternacional></Arbitro>',
    N'<Arbitro><Nombre>Xml Dos</Nombre><Apellido>Prueba80j Xml B</Apellido><Pais codigoISO3="', @iso3, N'">Argentina</Pais>',
    N'<Categoria>Confederacion</Categoria><Genero>Femenino</Genero><FechaInternacional>2013-04-05</FechaInternacional></Arbitro>',
    N'</Arbitros>') AS xml);
DECLARE @filas int, @ins int, @act int, @err int, @cant int;
BEGIN TRY
    EXEC Arbitraje.Importar_ArbitrosXMLDatos @xml = @xml, @origen = N'80j (en memoria)',
         @cantFilas = @filas OUTPUT, @cantInsertados = @ins OUTPUT, @cantActualizados = @act OUTPUT, @cantErrores = @err OUTPUT;
    IF @filas = 2 AND @ins = 2 AND @act = 0 AND @err = 0
        PRINT '[OK] PRUEBA 4.1: la primera importación insertó los 2 árbitros.';
    ELSE PRINT '[FALLO] PRUEBA 4.1: filas=' + CAST(@filas AS varchar(10)) + ' insertados=' + CAST(@ins AS varchar(10))
             + ' actualizados=' + CAST(@act AS varchar(10)) + ' errores=' + CAST(@err AS varchar(10));

    EXEC Arbitraje.Importar_ArbitrosXMLDatos @xml = @xml, @origen = N'80j (en memoria)',
         @cantFilas = @filas OUTPUT, @cantInsertados = @ins OUTPUT, @cantActualizados = @act OUTPUT, @cantErrores = @err OUTPUT;
    SELECT @cant = COUNT(*) FROM Arbitraje.vw_Arbitro WHERE apellido LIKE N'Prueba80j Xml%';
    IF @filas = 2 AND @ins = 0 AND @act = 2 AND @err = 0 AND @cant = 2
        PRINT '[OK] PRUEBA 4.2: repetir la importación actualiza y no duplica (sigue habiendo 2 árbitros).';
    ELSE PRINT '[FALLO] PRUEBA 4.2: insertados=' + CAST(@ins AS varchar(10)) + ' actualizados=' + CAST(@act AS varchar(10))
             + ' árbitros=' + CAST(@cant AS varchar(10));
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 4.x: error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

-- PRUEBA 4.3: los datos importados quedan cifrados y se leen bien
-- Resultado esperado: el género se lee por la vista y no está en claro en la tabla.
IF EXISTS (SELECT 1 FROM Arbitraje.vw_Arbitro a JOIN Arbitraje.Arbitro t ON t.idArbitro = a.idArbitro
           WHERE a.apellido = N'Prueba80j Xml B' AND a.genero = 'Femenino' AND a.categoria = 'Confederacion'
             AND a.fechaInternacional = '2013-04-05'
             AND CHARINDEX(CAST('Femenino' AS varbinary(200)), t.generoCif) = 0)
    PRINT '[OK] PRUEBA 4.3: lo importado se guarda cifrado y se lee por la vista.';
ELSE PRINT '[FALLO] PRUEBA 4.3: lo importado no coincide o no está cifrado.';
GO

-- PRUEBA 4.4: una fila rechazada se guarda en Sistema.ErrorImportacion sin datos personales
-- Resultado esperado: la fila con un país inexistente queda registrada (1 error) y su datoOriginal conserva el
--   país pero no tiene el nombre, el apellido ni el género (Sistema.ErrorImportacion no está cifrada).
DECLARE @xml44 xml = CAST(CONCAT(N'<Arbitros><Arbitro><Nombre>Secreto80jNombre</Nombre><Apellido>Secreto80jApellido</Apellido>',
    N'<Pais codigoISO3="ZZZ">Pais Inexistente80j</Pais><Categoria>FIFA</Categoria><Genero>Masculino</Genero>',
    N'<FechaInternacional>2012-03-04</FechaInternacional></Arbitro></Arbitros>') AS xml);
DECLARE @f44 int, @i44 int, @a44 int, @e44 int, @dato nvarchar(max), @nodo xml;
BEGIN TRY
    EXEC Arbitraje.Importar_ArbitrosXMLDatos @xml = @xml44, @origen = N'80j (en memoria)',
         @cantFilas = @f44 OUTPUT, @cantInsertados = @i44 OUTPUT, @cantActualizados = @a44 OUTPUT, @cantErrores = @e44 OUTPUT;
    SELECT @dato = datoOriginal FROM Sistema.ErrorImportacion
    WHERE archivo = N'80j (en memoria)' AND datoOriginal LIKE N'%Pais Inexistente80j%';
    SET @nodo = CAST(@dato AS xml);
    IF @e44 = 1 AND @dato IS NOT NULL AND @dato NOT LIKE N'%Secreto80j%'
       AND @nodo.exist('/Arbitro/Nombre') = 0 AND @nodo.exist('/Arbitro/Apellido') = 0 AND @nodo.exist('/Arbitro/Genero') = 0
       AND @nodo.exist('/Arbitro/Pais') = 1
        PRINT '[OK] PRUEBA 4.4: la fila rechazada se guarda sin nombre, apellido ni género y conserva el país.';
    ELSE PRINT '[FALLO] PRUEBA 4.4: errores=' + ISNULL(CAST(@e44 AS varchar(10)), 'NULL') + ' datoOriginal=' + ISNULL(@dato, 'NULL');
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 4.4: error inesperado -> ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   5. MANEJO DE LA CLAVE
   ============================================================================= */
PRINT '--- 5. Manejo de la clave ---';

-- PRUEBA 5.1: tras un alta correcta la clave no queda abierta
-- Resultado esperado: 0 claves abiertas en la sesión.
IF EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = N'ClaveDatosPersonales' AND database_id = DB_ID())
    CLOSE SYMMETRIC KEY ClaveDatosPersonales;
EXEC Equipos.Jugador_Alta @nombre = N'Clave', @apellido = N'Prueba80j Clave Ok';
IF NOT EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = N'ClaveDatosPersonales' AND database_id = DB_ID())
    PRINT '[OK] PRUEBA 5.1: tras un alta correcta la clave quedó cerrada.';
ELSE PRINT '[FALLO] PRUEBA 5.1: la clave quedó abierta.';
GO

-- PRUEBA 5.2: tras un alta que falla la clave tampoco queda abierta
-- Resultado esperado: error 50001 y 0 claves abiertas.
BEGIN TRY
    EXEC Equipos.Jugador_Alta @nombre = N'', @apellido = N'Prueba80j Clave Error';
    PRINT '[FALLO] PRUEBA 5.2: se aceptó un jugador sin nombre.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND NOT EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = N'ClaveDatosPersonales' AND database_id = DB_ID())
        PRINT '[OK] PRUEBA 5.2: tras el error 50001 la clave quedó cerrada.';
    ELSE PRINT '[FALLO] PRUEBA 5.2: error ' + CAST(ERROR_NUMBER() AS varchar(10)) + ' o la clave quedó abierta.';
END CATCH;
GO

-- PRUEBA 5.3: un SP no le cierra la clave a quien ya la había abierto
-- Resultado esperado: después de Arbitro_Alta (y de un alta que falla) la clave sigue abierta y se puede descifrar.
DECLARE @idPais int = (SELECT TOP (1) id FROM Torneo.Pais ORDER BY id);
DECLARE @idAr int, @sigueAbierta1 bit = 0, @sigueAbierta2 bit = 0, @descifra bit = 0;
OPEN SYMMETRIC KEY ClaveDatosPersonales DECRYPTION BY CERTIFICATE CertDatosPersonales;
EXEC Arbitraje.Arbitro_Alta @idPais = @idPais, @nombre = N'Anidado', @apellido = N'Prueba80j Anidado', @categoria = 'FIFA', @idArbitro = @idAr OUTPUT;
IF EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = N'ClaveDatosPersonales' AND database_id = DB_ID()) SET @sigueAbierta1 = 1;
BEGIN TRY
    EXEC Arbitraje.Arbitro_Alta @idPais = @idPais, @nombre = N'', @apellido = N'', @categoria = 'FIFA';
END TRY
BEGIN CATCH
END CATCH;
IF EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = N'ClaveDatosPersonales' AND database_id = DB_ID()) SET @sigueAbierta2 = 1;
IF (SELECT CONVERT(nvarchar(60), DecryptByKey(nombreCif)) FROM Arbitraje.Arbitro WHERE idArbitro = @idAr) = N'Anidado'
    SET @descifra = 1;
CLOSE SYMMETRIC KEY ClaveDatosPersonales;
IF @sigueAbierta1 = 1 AND @sigueAbierta2 = 1 AND @descifra = 1
    PRINT '[OK] PRUEBA 5.3: los SP respetan la clave abierta por quien los llama (también si fallan).';
ELSE PRINT '[FALLO] PRUEBA 5.3: la clave se cerró (tras el alta: ' + CAST(@sigueAbierta1 AS varchar(1))
         + ', tras el error: ' + CAST(@sigueAbierta2 AS varchar(1)) + ', descifra: ' + CAST(@descifra AS varchar(1)) + ').';
GO

/* =============================================================================
   6. PERMISOS (usuario sin login)
   usr_prueba80j tiene EXECUTE sobre los SP de alta y los 4 reportes, y SELECT
   sobre vw_Jugador. No tiene ningún permiso sobre las tablas, el certificado ni
   la clave. Los permisos sobre claves y certificados no se heredan por
   encadenamiento de propiedad: por eso los SP son WITH EXECUTE AS OWNER.
   ============================================================================= */
PRINT '--- 6. Permisos ---';

CREATE USER usr_prueba80j WITHOUT LOGIN;
GRANT EXECUTE ON Equipos.Jugador_Alta                       TO usr_prueba80j;
GRANT EXECUTE ON Equipos.Reporte_SeleccionesPlantillas      TO usr_prueba80j;
GRANT EXECUTE ON Eventos.Reporte_Goleadores                 TO usr_prueba80j;
GRANT EXECUTE ON Eventos.Reporte_Tarjetas                   TO usr_prueba80j;
GRANT EXECUTE ON Arbitraje.Reporte_DesignacionesArbitrales  TO usr_prueba80j;
GRANT SELECT  ON Equipos.vw_Jugador                         TO usr_prueba80j;
GO

-- PRUEBA 6.1: leer la tabla base
-- Resultado esperado: error 229 (permiso denegado).
EXECUTE AS USER = 'usr_prueba80j';
BEGIN TRY
    DECLARE @n1 int = (SELECT COUNT(*) FROM Equipos.Jugador);
    REVERT;
    PRINT '[FALLO] PRUEBA 6.1: se pudo leer la tabla base.';
END TRY
BEGIN CATCH
    DECLARE @e61 int = ERROR_NUMBER();
    REVERT;
    IF @e61 = 229 PRINT '[OK] PRUEBA 6.1: SELECT sobre la tabla base da error 229.';
    ELSE PRINT '[FALLO] PRUEBA 6.1: error ' + CAST(@e61 AS varchar(10));
END CATCH;
GO

-- PRUEBA 6.2: leer la vista de descifrado con SELECT pero sin permiso sobre la clave
-- Resultado esperado: devuelve las filas, con los datos cifrados en NULL y sin ningún error.
-- (Por eso el plan de roles pone DENY SELECT sobre las vistas a quien no deba ver datos personales.)
-- OJO: esta prueba solo documenta qué pasa si falta ese DENY; no demuestra que el acceso sea seguro. El control
-- real lo pone el 71 (DENY SELECT sobre las vistas y las tablas) y el acceso a fn_EquipoEnCancha,
-- vw_HistorialTitularidad y vw_HistorialArbitro depende de que ningún rol tenga SELECT sobre ellos.
DECLARE @filas int, @nulos int, @e62 int;
EXECUTE AS USER = 'usr_prueba80j';
BEGIN TRY
    SELECT @filas = COUNT(*), @nulos = SUM(CASE WHEN nombre IS NULL AND apellido IS NULL THEN 1 ELSE 0 END)
    FROM Equipos.vw_Jugador;
END TRY
BEGIN CATCH
    SET @e62 = ERROR_NUMBER();
END CATCH;
REVERT;
IF @e62 IS NULL AND @filas > 0 AND @nulos = @filas
    PRINT '[OK] PRUEBA 6.2: la vista devuelve ' + CAST(@filas AS varchar(10)) + ' filas con nombre y apellido NULL, sin error.';
ELSE PRINT '[FALLO] PRUEBA 6.2: error=' + ISNULL(CAST(@e62 AS varchar(10)), 'ninguno') + ' filas=' + ISNULL(CAST(@filas AS varchar(10)), 'NULL')
         + ' nulos=' + ISNULL(CAST(@nulos AS varchar(10)), 'NULL');
GO

-- PRUEBA 6.3: con DENY SELECT sobre la vista
-- Resultado esperado: error 229.
DENY SELECT ON Equipos.vw_Jugador TO usr_prueba80j;
EXECUTE AS USER = 'usr_prueba80j';
BEGIN TRY
    DECLARE @n3 int = (SELECT COUNT(*) FROM Equipos.vw_Jugador);
    REVERT;
    PRINT '[FALLO] PRUEBA 6.3: se pudo leer la vista con DENY.';
END TRY
BEGIN CATCH
    DECLARE @e63 int = ERROR_NUMBER();
    REVERT;
    IF @e63 = 229 PRINT '[OK] PRUEBA 6.3: con DENY SELECT la vista da error 229.';
    ELSE PRINT '[FALLO] PRUEBA 6.3: error ' + CAST(@e63 AS varchar(10));
END CATCH;
GO

-- PRUEBA 6.4: abrir la clave directamente
-- Resultado esperado: error (no se encuentra la clave o no hay permiso: 15151).
EXECUTE AS USER = 'usr_prueba80j';
BEGIN TRY
    OPEN SYMMETRIC KEY ClaveDatosPersonales DECRYPTION BY CERTIFICATE CertDatosPersonales;
    REVERT;
    CLOSE SYMMETRIC KEY ClaveDatosPersonales;
    PRINT '[FALLO] PRUEBA 6.4: el usuario pudo abrir la clave.';
END TRY
BEGIN CATCH
    DECLARE @e64 int = ERROR_NUMBER();
    REVERT;
    IF @e64 = 15151 PRINT '[OK] PRUEBA 6.4: el usuario no puede abrir la clave (error 15151).';
    ELSE PRINT '[FALLO] PRUEBA 6.4: error ' + CAST(@e64 AS varchar(10));
END CATCH;
GO

-- PRUEBA 6.5: leer el secreto de la pimienta
-- Resultado esperado: error 229.
EXECUTE AS USER = 'usr_prueba80j';
BEGIN TRY
    DECLARE @n5 int = (SELECT COUNT(*) FROM Seguridad.Secreto);
    REVERT;
    PRINT '[FALLO] PRUEBA 6.5: se pudo leer Seguridad.Secreto.';
END TRY
BEGIN CATCH
    DECLARE @e65 int = ERROR_NUMBER();
    REVERT;
    IF @e65 = 229 PRINT '[OK] PRUEBA 6.5: Seguridad.Secreto no se puede leer (error 229).';
    ELSE PRINT '[FALLO] PRUEBA 6.5: error ' + CAST(@e65 AS varchar(10));
END CATCH;
GO

-- PRUEBA 6.6: dar de alta un jugador con solo EXECUTE
-- Resultado esperado: se acepta (el SP es WITH EXECUTE AS OWNER) y el dato queda cifrado.
DECLARE @e66 int, @id66 int;
EXECUTE AS USER = 'usr_prueba80j';
BEGIN TRY
    EXEC Equipos.Jugador_Alta @nombre = N'Permiso', @apellido = N'Prueba80j Permiso', @id = @id66 OUTPUT;
END TRY
BEGIN CATCH
    SET @e66 = ERROR_NUMBER();
END CATCH;
REVERT;
IF @e66 IS NULL AND EXISTS (SELECT 1 FROM Equipos.vw_Jugador WHERE id = @id66 AND apellido = N'Prueba80j Permiso')
    PRINT '[OK] PRUEBA 6.6: con solo EXECUTE se da de alta y el dato queda cifrado.';
ELSE PRINT '[FALLO] PRUEBA 6.6: error=' + ISNULL(CAST(@e66 AS varchar(10)), 'ninguno');
GO

-- PRUEBA 6.7: reporte de plantillas (XML) con solo EXECUTE
-- Resultado esperado: sin error y con los nombres en claro (todos los <nombre> tienen texto).
DECLARE @r TABLE (plantillas xml);
DECLARE @e67 int, @x xml, @jug int, @jugConNombre int;
EXECUTE AS USER = 'usr_prueba80j';
BEGIN TRY
    INSERT INTO @r EXEC Equipos.Reporte_SeleccionesPlantillas;
END TRY
BEGIN CATCH
    SET @e67 = ERROR_NUMBER();
END CATCH;
REVERT;
SELECT @x = plantillas FROM @r;
SET @jug = @x.value('count(//jugador)', 'int');
SET @jugConNombre = @x.value('count(//jugador/nombre[string-length(.) > 3])', 'int');
IF @e67 IS NULL AND @jug > 0 AND @jug = @jugConNombre
    PRINT '[OK] PRUEBA 6.7: el reporte de plantillas devuelve los nombres en claro (' + CAST(@jug AS varchar(10)) + ' jugadores).';
ELSE PRINT '[FALLO] PRUEBA 6.7: error=' + ISNULL(CAST(@e67 AS varchar(10)), 'ninguno') + ', jugadores sin nombre en el XML.';
GO

-- PRUEBA 6.8: reporte de tarjetas con solo EXECUTE
-- Resultado esperado: sin error, con filas y la columna persona (apellido, nombre) sin NULL.
DECLARE @t TABLE (idSeleccion nvarchar(max), seleccion nvarchar(max), tipoPersona nvarchar(max), persona nvarchar(max),
                  posicionORol nvarchar(max), amarillas nvarchar(max), rojas nvarchar(max), rojasDirectas nvarchar(max),
                  rojasDobleAmarilla nvarchar(max), suspensionesActivas nvarchar(max), partidosPorCumplir nvarchar(max),
                  suspensionesTotales nvarchar(max), detalleSuspensiones nvarchar(max));
DECLARE @e68 int, @filas68 int;
EXECUTE AS USER = 'usr_prueba80j';
BEGIN TRY
    INSERT INTO @t EXEC Eventos.Reporte_Tarjetas;
END TRY
BEGIN CATCH
    SET @e68 = ERROR_NUMBER();
END CATCH;
REVERT;
SELECT @filas68 = COUNT(*) FROM @t;
IF @e68 IS NULL AND @filas68 > 0 AND NOT EXISTS (SELECT 1 FROM @t WHERE persona IS NULL)
    PRINT '[OK] PRUEBA 6.8: el reporte de tarjetas devuelve ' + CAST(@filas68 AS varchar(10)) + ' personas con nombre en claro.';
ELSE PRINT '[FALLO] PRUEBA 6.8: error=' + ISNULL(CAST(@e68 AS varchar(10)), 'ninguno') + ' o hay personas sin nombre.';
GO

-- PRUEBA 6.9: reporte de designaciones arbitrales (XML) con solo EXECUTE
-- Resultado esperado: sin error y todos los <Arbitro> con el atributo nombre con texto.
DECLARE @r TABLE (reporteXML xml);
DECLARE @e69 int, @x xml;
EXECUTE AS USER = 'usr_prueba80j';
BEGIN TRY
    INSERT INTO @r EXEC Arbitraje.Reporte_DesignacionesArbitrales;
END TRY
BEGIN CATCH
    SET @e69 = ERROR_NUMBER();
END CATCH;
REVERT;
SELECT @x = reporteXML FROM @r;
IF @e69 IS NULL AND @x.value('count(//Arbitro)', 'int') > 0
   AND @x.value('count(//Arbitro)', 'int') = @x.value('count(//Arbitro[string-length(@nombre) > 3])', 'int')
   AND @x.value('count(//Tarjeta)', 'int') = @x.value('count(//Tarjeta[string-length(@persona) > 3])', 'int')
    PRINT '[OK] PRUEBA 6.9: el reporte de designaciones devuelve los nombres de árbitros y de personas en claro.';
ELSE PRINT '[FALLO] PRUEBA 6.9: error=' + ISNULL(CAST(@e69 AS varchar(10)), 'ninguno') + ' o hay nombres vacíos en el XML.';
GO

-- PRUEBA 6.10: reporte de goleadores con solo EXECUTE
-- Resultado esperado: se ejecuta sin error. Devuelve 3 resultados y INSERT ... EXEC no admite eso, así que los
-- nombres de este reporte los verifica 81g (ahí se ven los goleadores por selección).
DECLARE @e610 int;
EXECUTE AS USER = 'usr_prueba80j';
BEGIN TRY
    EXEC Eventos.Reporte_Goleadores;
END TRY
BEGIN CATCH
    SET @e610 = ERROR_NUMBER();
END CATCH;
REVERT;
IF @e610 IS NULL PRINT '[OK] PRUEBA 6.10: el reporte de goleadores se ejecuta con solo EXECUTE.';
ELSE PRINT '[FALLO] PRUEBA 6.10: error ' + CAST(@e610 AS varchar(10));
GO

/* =============================================================================
   LIMPIEZA FINAL
   ============================================================================= */
IF EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = N'ClaveDatosPersonales' AND database_id = DB_ID())
    CLOSE SYMMETRIC KEY ClaveDatosPersonales;
DROP USER usr_prueba80j;
DELETE FROM Arbitraje.ArbitroIdioma WHERE idArbitro IN (SELECT idArbitro FROM Arbitraje.vw_Arbitro WHERE apellido LIKE N'Prueba80j%');
DELETE FROM Arbitraje.Arbitro WHERE idArbitro IN (SELECT idArbitro FROM Arbitraje.vw_Arbitro WHERE apellido LIKE N'Prueba80j%');
DELETE FROM Equipos.Staff WHERE id IN (SELECT id FROM Equipos.vw_Staff WHERE apellido LIKE N'Prueba80j%');
DELETE FROM Equipos.Jugador WHERE id IN (SELECT id FROM Equipos.vw_Jugador WHERE apellido LIKE N'Prueba80j%');
DELETE FROM Sistema.ErrorImportacion WHERE archivo = N'80j (en memoria)';
GO

PRINT '================================================================================';
PRINT ' FIN DE LAS PRUEBAS: 70a a 70f';
PRINT '================================================================================';
GO
