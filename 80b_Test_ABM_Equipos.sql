/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 09/11/2026

 Objetivo    : Pruebas de los SP de 10b_ABM_Equipos.sql (Seleccion, Jugador,
               Staff y ListadoJugadores): casos exitosos con evidencia
               antes/después y casos que deben fallar en cada validación.

 Requisitos  : 00_InitialSchema.sql, 10a (países, sede, fase y partido del
               fixture) y 10b.

 Datos de prueba:
 - Países con códigos ISO de uso privado (QR, QS, QT, QU / QRA, QSA, QTA, QUA),
   que la norma ISO 3166 nunca asigna a un país real.
 - Fase 903, partido oficial 98011, jugadores y staff con apellido Prueba80b.
 - Se limpian al inicio y al final: el script se puede ejecutar varias veces.

 Cada prueba imprime [OK] o [FALLO]. Resultado esperado: todas [OK].
================================================================================
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

PRINT '================================================================================';
PRINT ' PRUEBAS: 10b_ABM_Equipos.sql';
PRINT '================================================================================';
GO

/* =============================================================================
   LIMPIEZA PREVIA (DELETE directo en orden inverso de claves foráneas, por si
   una corrida anterior se cortó y dejó datos con dependencias)
   ============================================================================= */
DELETE FROM Equipos.ListadoJugadores WHERE idReemplazaA IS NOT NULL
    AND idJugador IN (SELECT id FROM Equipos.Jugador WHERE apellido = N'Prueba80b');
DELETE FROM Equipos.ListadoJugadores WHERE idJugador IN (SELECT id FROM Equipos.Jugador WHERE apellido = N'Prueba80b');
DELETE FROM Equipos.Staff WHERE apellido = N'Prueba80b';
DELETE FROM Equipos.Jugador WHERE apellido = N'Prueba80b';
DELETE FROM Torneo.Partido WHERE nroPartidoOficial = 98011;
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('QRA', 'QSA', 'QTA');
DELETE FROM Torneo.Sede WHERE nombreEstadio = N'Estadio Prueba 80b';
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('QR', 'QS', 'QT', 'QU');
DELETE FROM Torneo.Fase WHERE idFase = 903;
GO

-- Fixture con los SP de 10a
EXEC Torneo.Pais_Alta @nombre = N'País Prueba 80b R', @codigoISO2 = 'QR', @codigoISO3 = 'QRA';
EXEC Torneo.Pais_Alta @nombre = N'País Prueba 80b S', @codigoISO2 = 'QS', @codigoISO3 = 'QSA';
EXEC Torneo.Pais_Alta @nombre = N'País Prueba 80b T', @codigoISO2 = 'QT', @codigoISO3 = 'QTA';
EXEC Torneo.Pais_Alta @nombre = N'País Prueba 80b U', @codigoISO2 = 'QU', @codigoISO3 = 'QUA';
EXEC Torneo.Fase_Alta @idFase = 903, @nombre = 'Fase Prueba 80b', @esEliminatoria = 0, @orden = 1;
DECLARE @idPaisR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'QR');
EXEC Torneo.Sede_Alta @nombreEstadio = N'Estadio Prueba 80b', @ciudad = N'Ciudad Prueba', @idPais = @idPaisR,
     @husoHorario = 'UTC', @capacidad = 30000;
GO

/* =============================================================================
   1. Equipos.Seleccion
   ============================================================================= */
PRINT '--- 1. Equipos.Seleccion ---';

DECLARE @idPaisR int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'QR');
DECLARE @idPaisS int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'QS');
DECLARE @idPaisT int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'QT');
DECLARE @idPaisU int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'QU');
DECLARE @id int;

-- PRUEBA 1.1: alta exitosa (abreviación, confederación y grupo en minúscula, se normalizan)
-- Resultado esperado: se crea la selección QRA, confederación CONMEBOL, grupo C.
BEGIN TRY
    SELECT 'ANTES 1.1' AS momento, COUNT(*) AS filas FROM Equipos.Seleccion WHERE idPais = @idPaisR;
    EXEC Equipos.Seleccion_Alta @idPais = @idPaisR, @confederacion = 'conmebol', @abreviacion = 'qra',
         @nombreAsociacion = N'Asociación Prueba R', @grupo = 'c', @id = @id OUTPUT;
    SELECT 'DESPUES 1.1' AS momento, * FROM Equipos.Seleccion WHERE id = @id;
    IF EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE id = @id AND abreviacion = 'QRA'
               AND confederacion = 'CONMEBOL' AND grupo = 'C')
        PRINT '[OK] PRUEBA 1.1: selección creada y datos normalizados.';
    ELSE PRINT '[FALLO] PRUEBA 1.1: la selección no quedó como se esperaba.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.2: país que ya tiene selección
-- Resultado esperado: error 50001 "El país ya tiene una selección registrada."
BEGIN TRY
    EXEC Equipos.Seleccion_Alta @idPais = @idPaisR, @confederacion = 'UEFA', @abreviacion = 'QXX';
    PRINT '[FALLO] PRUEBA 1.2: se aceptó una segunda selección para el país.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%país ya tiene una selección registrada%'
        PRINT '[OK] PRUEBA 1.2: segunda selección del país rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 1.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.3: país inexistente
-- Resultado esperado: error 50001 "El país de la selección no existe."
BEGIN TRY
    EXEC Equipos.Seleccion_Alta @idPais = -1, @confederacion = 'UEFA', @abreviacion = 'QXX';
    PRINT '[FALLO] PRUEBA 1.3: se aceptó un país inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%país de la selección no existe%'
        PRINT '[OK] PRUEBA 1.3: país inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 1.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.4: abreviación repetida
-- Resultado esperado: error 50001 "La abreviación FIFA ya la usa otra selección."
BEGIN TRY
    EXEC Equipos.Seleccion_Alta @idPais = @idPaisS, @confederacion = 'UEFA', @abreviacion = 'QRA';
    PRINT '[FALLO] PRUEBA 1.4: se aceptó una abreviación repetida.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%abreviación FIFA ya la usa otra selección%'
        PRINT '[OK] PRUEBA 1.4: abreviación repetida rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 1.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.5: acumulación (confederación inexistente, abreviación de 2 letras, grupo M)
-- Resultado esperado: error 50001 con las tres líneas en el mismo mensaje.
BEGIN TRY
    EXEC Equipos.Seleccion_Alta @idPais = @idPaisS, @confederacion = 'FIFA', @abreviacion = 'QS', @grupo = 'M';
    PRINT '[FALLO] PRUEBA 1.5: no se detectaron los errores.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'%confederación debe ser%'
       AND ERROR_MESSAGE() LIKE N'%abreviación FIFA debe tener exactamente 3 letras%'
       AND ERROR_MESSAGE() LIKE N'%grupo debe ser una letra de la A a la L%'
        PRINT '[OK] PRUEBA 1.5: los 3 errores se informaron juntos.';
    ELSE PRINT '[FALLO] PRUEBA 1.5: ' + ERROR_MESSAGE();
END CATCH;

-- Selecciones auxiliares S y T
EXEC Equipos.Seleccion_Alta @idPais = @idPaisS, @confederacion = 'UEFA', @abreviacion = 'QSA';
EXEC Equipos.Seleccion_Alta @idPais = @idPaisT, @confederacion = 'OFC',  @abreviacion = 'QTA';

-- PRUEBA 1.6: modificación exitosa
-- Resultado esperado: la selección QRA pasa al grupo F.
BEGIN TRY
    SET @id = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'QRA');
    SELECT 'ANTES 1.6' AS momento, id, grupo FROM Equipos.Seleccion WHERE id = @id;
    EXEC Equipos.Seleccion_Modificacion @id = @id, @idPais = @idPaisR, @confederacion = 'CONMEBOL',
         @abreviacion = 'QRA', @nombreAsociacion = N'Asociación Prueba R', @grupo = 'F';
    SELECT 'DESPUES 1.6' AS momento, id, grupo FROM Equipos.Seleccion WHERE id = @id;
    IF EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE id = @id AND grupo = 'F')
        PRINT '[OK] PRUEBA 1.6: selección modificada.';
    ELSE PRINT '[FALLO] PRUEBA 1.6: la selección no se modificó.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.6: ' + ERROR_MESSAGE();
END CATCH;

-- Partido entre R y S para las reglas que dependen de partidos
DECLARE @selR int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'QRA');
DECLARE @selS int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'QSA');
DECLARE @sede int = (SELECT idSede FROM Torneo.Sede WHERE nombreEstadio = N'Estadio Prueba 80b');
EXEC Torneo.Partido_Alta @idSede = @sede, @idSeleccionLocal = @selR, @idSeleccionVisitante = @selS,
     @fase = 903, @fechaHoraUTC = '2030-06-20 18:00', @nroPartidoOficial = 98011;

-- PRUEBA 1.7: cambiar el país de una selección que ya tiene partidos
-- Resultado esperado: error 50001 "No se puede cambiar el país porque la selección ya tiene partidos asignados."
BEGIN TRY
    EXEC Equipos.Seleccion_Modificacion @id = @selR, @idPais = @idPaisU, @confederacion = 'CONMEBOL',
         @abreviacion = 'QRA', @grupo = 'F';
    PRINT '[FALLO] PRUEBA 1.7: se cambió el país de una selección con partidos.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%cambiar el país porque la selección ya tiene partidos%'
        PRINT '[OK] PRUEBA 1.7: cambio de país con partidos rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 1.7: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   2. Equipos.Jugador
   ============================================================================= */
PRINT '--- 2. Equipos.Jugador ---';

DECLARE @id int;

-- PRUEBA 2.1: alta exitosa
-- Resultado esperado: se crea el jugador con todos sus datos.
BEGIN TRY
    SELECT 'ANTES 2.1' AS momento, COUNT(*) AS filas FROM Equipos.Jugador WHERE apellido = N'Prueba80b';
    EXEC Equipos.Jugador_Alta @nombre = N'Uno', @apellido = N'Prueba80b', @fechaNacimiento = '2000-03-15',
         @altura = 1.80, @peso = 75, @piernaHabil = 'Derecha', @club = N'Club Prueba', @posicion = 'Delantero',
         @id = @id OUTPUT;
    SELECT 'DESPUES 2.1' AS momento, * FROM Equipos.Jugador WHERE id = @id;
    IF @id IS NOT NULL
        PRINT '[OK] PRUEBA 2.1: jugador creado con ID = ' + CAST(@id AS varchar(10));
    ELSE PRINT '[FALLO] PRUEBA 2.1: no se devolvió el ID.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.2: sin nombre ni apellido
-- Resultado esperado: error 50001 con "nombre del jugador es obligatorio" y "apellido del jugador es obligatorio".
BEGIN TRY
    EXEC Equipos.Jugador_Alta @nombre = N'', @apellido = NULL;
    PRINT '[FALLO] PRUEBA 2.2: se aceptó un jugador sin nombre ni apellido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%nombre del jugador es obligatorio%'
       AND ERROR_MESSAGE() LIKE N'%apellido del jugador es obligatorio%'
        PRINT '[OK] PRUEBA 2.2: nombre y apellido obligatorios verificados.';
    ELSE PRINT '[FALLO] PRUEBA 2.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.3: jugador de 10 años
-- Resultado esperado: error 50001 "El jugador debe tener al menos 15 años."
BEGIN TRY
    DECLARE @nacimiento date = DATEADD(YEAR, -10, CAST(GETDATE() AS date));
    EXEC Equipos.Jugador_Alta @nombre = N'Dos', @apellido = N'Prueba80b', @fechaNacimiento = @nacimiento;
    PRINT '[FALLO] PRUEBA 2.3: se aceptó un jugador de 10 años.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%al menos 15 años%'
        PRINT '[OK] PRUEBA 2.3: jugador menor de 15 años rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.4: acumulación (altura, peso, pierna y posición fuera de dominio)
-- Resultado esperado: error 50001 con las cuatro líneas en el mismo mensaje.
BEGIN TRY
    EXEC Equipos.Jugador_Alta @nombre = N'Dos', @apellido = N'Prueba80b', @altura = 2.50, @peso = 30,
         @piernaHabil = 'Zurda', @posicion = 'Volante';
    PRINT '[FALLO] PRUEBA 2.4: no se detectaron los errores.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'%altura debe estar entre%'
       AND ERROR_MESSAGE() LIKE N'%peso debe estar entre%'
       AND ERROR_MESSAGE() LIKE N'%pierna hábil debe ser%'
       AND ERROR_MESSAGE() LIKE N'%posición debe ser%'
        PRINT '[OK] PRUEBA 2.4: los 4 errores se informaron juntos.';
    ELSE PRINT '[FALLO] PRUEBA 2.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.5: jugador repetido (mismo nombre, apellido y fecha de nacimiento)
-- Resultado esperado: error 50001 "Ya existe un jugador con el mismo nombre, apellido y fecha de nacimiento."
BEGIN TRY
    EXEC Equipos.Jugador_Alta @nombre = N'Uno', @apellido = N'Prueba80b', @fechaNacimiento = '2000-03-15';
    PRINT '[FALLO] PRUEBA 2.5: se aceptó un jugador repetido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%mismo nombre, apellido y fecha de nacimiento%'
        PRINT '[OK] PRUEBA 2.5: jugador repetido rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.5: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.6: modificación exitosa
-- Resultado esperado: el jugador Uno cambia de club.
BEGIN TRY
    SET @id = (SELECT id FROM Equipos.Jugador WHERE apellido = N'Prueba80b' AND nombre = N'Uno');
    SELECT 'ANTES 2.6' AS momento, id, club FROM Equipos.Jugador WHERE id = @id;
    EXEC Equipos.Jugador_Modificacion @id = @id, @nombre = N'Uno', @apellido = N'Prueba80b',
         @fechaNacimiento = '2000-03-15', @altura = 1.80, @peso = 75, @piernaHabil = 'Derecha',
         @club = N'Club Prueba Nuevo', @posicion = 'Delantero';
    SELECT 'DESPUES 2.6' AS momento, id, club FROM Equipos.Jugador WHERE id = @id;
    IF EXISTS (SELECT 1 FROM Equipos.Jugador WHERE id = @id AND club = N'Club Prueba Nuevo')
        PRINT '[OK] PRUEBA 2.6: jugador modificado.';
    ELSE PRINT '[FALLO] PRUEBA 2.6: el jugador no se modificó.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.6: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.7: modificación de un jugador inexistente
-- Resultado esperado: error 50001 "El jugador a modificar no existe."
BEGIN TRY
    EXEC Equipos.Jugador_Modificacion @id = -1, @nombre = N'X', @apellido = N'Prueba80b';
    PRINT '[FALLO] PRUEBA 2.7: se modificó un jugador inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%jugador a modificar no existe%'
        PRINT '[OK] PRUEBA 2.7: jugador inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.7: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.8: baja exitosa de un jugador sin convocatorias ni eventos
-- Resultado esperado: el jugador Descartable deja de existir.
BEGIN TRY
    EXEC Equipos.Jugador_Alta @nombre = N'Descartable', @apellido = N'Prueba80b', @id = @id OUTPUT;
    SELECT 'ANTES 2.8' AS momento, COUNT(*) AS filas FROM Equipos.Jugador WHERE id = @id;
    EXEC Equipos.Jugador_Baja @id = @id;
    SELECT 'DESPUES 2.8' AS momento, COUNT(*) AS filas FROM Equipos.Jugador WHERE id = @id;
    IF NOT EXISTS (SELECT 1 FROM Equipos.Jugador WHERE id = @id)
        PRINT '[OK] PRUEBA 2.8: jugador eliminado.';
    ELSE PRINT '[FALLO] PRUEBA 2.8: el jugador sigue existiendo.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.8: ' + ERROR_MESSAGE();
END CATCH;

-- Jugadores auxiliares para la convocatoria
EXEC Equipos.Jugador_Alta @nombre = N'Dos',    @apellido = N'Prueba80b';
EXEC Equipos.Jugador_Alta @nombre = N'Tres',   @apellido = N'Prueba80b';
EXEC Equipos.Jugador_Alta @nombre = N'Cuatro', @apellido = N'Prueba80b';
EXEC Equipos.Jugador_Alta @nombre = N'Cinco',  @apellido = N'Prueba80b';
GO

/* =============================================================================
   3. Equipos.Staff
   ============================================================================= */
PRINT '--- 3. Equipos.Staff ---';

DECLARE @selR int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'QRA');
DECLARE @id int;

-- PRUEBA 3.1: alta exitosa del director principal
-- Resultado esperado: se crea el integrante con rol Director Principal.
BEGIN TRY
    SELECT 'ANTES 3.1' AS momento, COUNT(*) AS filas FROM Equipos.Staff WHERE idSeleccion = @selR;
    EXEC Equipos.Staff_Alta @idSeleccion = @selR, @nombre = N'Director', @apellido = N'Prueba80b',
         @rol = 'Director Principal', @fechaNacimiento = '1970-01-01', @id = @id OUTPUT;
    SELECT 'DESPUES 3.1' AS momento, * FROM Equipos.Staff WHERE id = @id;
    IF EXISTS (SELECT 1 FROM Equipos.Staff WHERE id = @id AND rol = 'Director Principal')
        PRINT '[OK] PRUEBA 3.1: director principal creado.';
    ELSE PRINT '[FALLO] PRUEBA 3.1: el integrante no se creó.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 3.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.2: segundo director principal en la misma selección
-- Resultado esperado: error 50001 "La selección ya tiene un director principal."
BEGIN TRY
    EXEC Equipos.Staff_Alta @idSeleccion = @selR, @nombre = N'Otro', @apellido = N'Prueba80b', @rol = 'Director Principal';
    PRINT '[FALLO] PRUEBA 3.2: se aceptó un segundo director principal.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%ya tiene un director principal%'
        PRINT '[OK] PRUEBA 3.2: segundo director principal rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 3.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.3: acumulación (selección inexistente, rol inválido, fecha de nacimiento futura)
-- Resultado esperado: error 50001 con las tres líneas en el mismo mensaje.
BEGIN TRY
    EXEC Equipos.Staff_Alta @idSeleccion = -1, @nombre = N'Otro', @apellido = N'Prueba80b',
         @rol = 'Utilero', @fechaNacimiento = '2999-01-01';
    PRINT '[FALLO] PRUEBA 3.3: no se detectaron los errores.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'%selección no existe%'
       AND ERROR_MESSAGE() LIKE N'%rol debe ser%'
       AND ERROR_MESSAGE() LIKE N'%fecha de nacimiento no puede ser futura%'
        PRINT '[OK] PRUEBA 3.3: los 3 errores se informaron juntos.';
    ELSE PRINT '[FALLO] PRUEBA 3.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.4: modificación exitosa (ayudante pasa a preparador físico)
-- Resultado esperado: el rol del integrante cambia a Preparador Fisico.
BEGIN TRY
    EXEC Equipos.Staff_Alta @idSeleccion = @selR, @nombre = N'Ayudante', @apellido = N'Prueba80b',
         @rol = 'Ayudante', @id = @id OUTPUT;
    SELECT 'ANTES 3.4' AS momento, id, rol FROM Equipos.Staff WHERE id = @id;
    EXEC Equipos.Staff_Modificacion @id = @id, @idSeleccion = @selR, @nombre = N'Ayudante',
         @apellido = N'Prueba80b', @rol = 'Preparador Fisico';
    SELECT 'DESPUES 3.4' AS momento, id, rol FROM Equipos.Staff WHERE id = @id;
    IF EXISTS (SELECT 1 FROM Equipos.Staff WHERE id = @id AND rol = 'Preparador Fisico')
        PRINT '[OK] PRUEBA 3.4: integrante modificado.';
    ELSE PRINT '[FALLO] PRUEBA 3.4: el integrante no se modificó.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 3.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.5: modificación a director principal cuando la selección ya tiene uno
-- Resultado esperado: error 50001 "La selección ya tiene otro director principal."
BEGIN TRY
    EXEC Equipos.Staff_Modificacion @id = @id, @idSeleccion = @selR, @nombre = N'Ayudante',
         @apellido = N'Prueba80b', @rol = 'Director Principal';
    PRINT '[FALLO] PRUEBA 3.5: se aceptó un segundo director principal.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%ya tiene otro director principal%'
        PRINT '[OK] PRUEBA 3.5: segundo director principal rechazado en la modificación.';
    ELSE PRINT '[FALLO] PRUEBA 3.5: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.6: baja exitosa
-- Resultado esperado: el preparador físico deja de existir.
BEGIN TRY
    SELECT 'ANTES 3.6' AS momento, COUNT(*) AS filas FROM Equipos.Staff WHERE id = @id;
    EXEC Equipos.Staff_Baja @id = @id;
    SELECT 'DESPUES 3.6' AS momento, COUNT(*) AS filas FROM Equipos.Staff WHERE id = @id;
    IF NOT EXISTS (SELECT 1 FROM Equipos.Staff WHERE id = @id)
        PRINT '[OK] PRUEBA 3.6: integrante eliminado.';
    ELSE PRINT '[FALLO] PRUEBA 3.6: el integrante sigue existiendo.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 3.6: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   4. Equipos.ListadoJugadores
   ============================================================================= */
PRINT '--- 4. Equipos.ListadoJugadores ---';

DECLARE @selR int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'QRA');
DECLARE @selS int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'QSA');
DECLARE @j1 int = (SELECT id FROM Equipos.Jugador WHERE apellido = N'Prueba80b' AND nombre = N'Uno');
DECLARE @j2 int = (SELECT id FROM Equipos.Jugador WHERE apellido = N'Prueba80b' AND nombre = N'Dos');
DECLARE @j3 int = (SELECT id FROM Equipos.Jugador WHERE apellido = N'Prueba80b' AND nombre = N'Tres');
DECLARE @j4 int = (SELECT id FROM Equipos.Jugador WHERE apellido = N'Prueba80b' AND nombre = N'Cuatro');
DECLARE @j5 int = (SELECT id FROM Equipos.Jugador WHERE apellido = N'Prueba80b' AND nombre = N'Cinco');
DECLARE @conv1 int, @conv2 int, @convS int, @id int;

-- PRUEBA 4.1: alta exitosa del jugador Uno con el dorsal 10
-- Resultado esperado: se crea el convocado activo (fechaBaja NULL).
BEGIN TRY
    SELECT 'ANTES 4.1' AS momento, COUNT(*) AS filas FROM Equipos.ListadoJugadores WHERE idSeleccion = @selR;
    EXEC Equipos.ListadoJugadores_Alta @idSeleccion = @selR, @idJugador = @j1, @dorsal = 10,
         @fechaAlta = '2026-05-01', @id = @conv1 OUTPUT;
    SELECT 'DESPUES 4.1' AS momento, * FROM Equipos.ListadoJugadores WHERE id = @conv1;
    IF EXISTS (SELECT 1 FROM Equipos.ListadoJugadores WHERE id = @conv1 AND dorsal = 10 AND fechaBaja IS NULL)
        PRINT '[OK] PRUEBA 4.1: convocado creado.';
    ELSE PRINT '[FALLO] PRUEBA 4.1: el convocado no quedó como se esperaba.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 4.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.2: dorsal repetido entre convocados activos
-- Resultado esperado: error 50001 "El dorsal ya lo usa otro convocado activo."
BEGIN TRY
    EXEC Equipos.ListadoJugadores_Alta @idSeleccion = @selR, @idJugador = @j2, @dorsal = 10, @fechaAlta = '2026-05-01';
    PRINT '[FALLO] PRUEBA 4.2: se aceptó un dorsal repetido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%dorsal ya lo usa otro convocado activo%'
        PRINT '[OK] PRUEBA 4.2: dorsal repetido rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 4.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.3: dorsal fuera de rango (100)
-- Resultado esperado: error 50001 "El dorsal es obligatorio y debe estar entre 1 y 99." (no un error de conversión)
BEGIN TRY
    EXEC Equipos.ListadoJugadores_Alta @idSeleccion = @selR, @idJugador = @j2, @dorsal = 100, @fechaAlta = '2026-05-01';
    PRINT '[FALLO] PRUEBA 4.3: se aceptó el dorsal 100.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%dorsal es obligatorio y debe estar entre 1 y 99%'
        PRINT '[OK] PRUEBA 4.3: dorsal fuera de rango rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 4.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.4: jugador ya convocado activo en otra selección
-- Resultado esperado: error 50001 "El jugador ya está convocado activo en una selección."
BEGIN TRY
    EXEC Equipos.ListadoJugadores_Alta @idSeleccion = @selS, @idJugador = @j1, @dorsal = 9, @fechaAlta = '2026-05-01';
    PRINT '[FALLO] PRUEBA 4.4: se convocó a un jugador activo en otra selección.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%ya está convocado activo%'
        PRINT '[OK] PRUEBA 4.4: jugador activo en otra selección rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 4.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.5: acumulación (selección y jugador inexistentes, sin fecha de alta, dorsal 0)
-- Resultado esperado: error 50001 con las cuatro líneas en el mismo mensaje.
BEGIN TRY
    EXEC Equipos.ListadoJugadores_Alta @idSeleccion = -1, @idJugador = -1, @dorsal = 0, @fechaAlta = NULL;
    PRINT '[FALLO] PRUEBA 4.5: no se detectaron los errores.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'%selección no existe%'
       AND ERROR_MESSAGE() LIKE N'%jugador no existe%'
       AND ERROR_MESSAGE() LIKE N'%fecha de alta es obligatoria%'
       AND ERROR_MESSAGE() LIKE N'%dorsal es obligatorio%'
        PRINT '[OK] PRUEBA 4.5: los 4 errores se informaron juntos.';
    ELSE PRINT '[FALLO] PRUEBA 4.5: ' + ERROR_MESSAGE();
END CATCH;

-- Convocados auxiliares: Dos con el 7 en R y Cinco con el 9 en S
EXEC Equipos.ListadoJugadores_Alta @idSeleccion = @selR, @idJugador = @j2, @dorsal = 7, @fechaAlta = '2026-05-01', @id = @conv2 OUTPUT;
EXEC Equipos.ListadoJugadores_Alta @idSeleccion = @selS, @idJugador = @j5, @dorsal = 9, @fechaAlta = '2026-05-01', @id = @convS OUTPUT;

-- PRUEBA 4.6: modificación exitosa del dorsal
-- Resultado esperado: el jugador Uno pasa del 10 al 11.
BEGIN TRY
    SELECT 'ANTES 4.6' AS momento, id, dorsal FROM Equipos.ListadoJugadores WHERE id = @conv1;
    EXEC Equipos.ListadoJugadores_Modificacion @id = @conv1, @dorsal = 11, @fechaAlta = '2026-05-01';
    SELECT 'DESPUES 4.6' AS momento, id, dorsal FROM Equipos.ListadoJugadores WHERE id = @conv1;
    IF EXISTS (SELECT 1 FROM Equipos.ListadoJugadores WHERE id = @conv1 AND dorsal = 11)
        PRINT '[OK] PRUEBA 4.6: dorsal modificado.';
    ELSE PRINT '[FALLO] PRUEBA 4.6: el dorsal no se modificó.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 4.6: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.7: modificación al dorsal de otro convocado activo de la misma selección
-- Resultado esperado: error 50001 "El dorsal ya lo usa otro convocado activo."
BEGIN TRY
    EXEC Equipos.ListadoJugadores_Modificacion @id = @conv1, @dorsal = 7, @fechaAlta = '2026-05-01';
    PRINT '[FALLO] PRUEBA 4.7: se aceptó el dorsal de otro convocado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%dorsal ya lo usa otro convocado activo%'
        PRINT '[OK] PRUEBA 4.7: dorsal de otro convocado rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 4.7: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.8: alta de un reemplazo de alguien que sigue activo
-- Resultado esperado: error 50001 "El convocado reemplazado todavía no fue dado de baja."
BEGIN TRY
    EXEC Equipos.ListadoJugadores_Alta @idSeleccion = @selR, @idJugador = @j3, @dorsal = 21,
         @fechaAlta = '2026-06-01', @idReemplazaA = @conv1;
    PRINT '[FALLO] PRUEBA 4.8: se reemplazó a un convocado activo.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%todavía no fue dado de baja%'
        PRINT '[OK] PRUEBA 4.8: reemplazo de convocado activo rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 4.8: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.9: baja sin motivo y con fecha anterior al alta
-- Resultado esperado: error 50001 con "fecha de baja no puede ser anterior" y "motivo de la baja es obligatorio".
BEGIN TRY
    EXEC Equipos.ListadoJugadores_Baja @id = @conv1, @fechaBaja = '2026-04-01', @motivoBaja = '  ';
    PRINT '[FALLO] PRUEBA 4.9: se aceptó una baja inválida.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%fecha de baja no puede ser anterior%'
       AND ERROR_MESSAGE() LIKE N'%motivo de la baja es obligatorio%'
        PRINT '[OK] PRUEBA 4.9: baja inválida rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 4.9: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.10: baja lógica exitosa del jugador Uno por lesión
-- Resultado esperado: la fila sigue existiendo con fechaBaja y motivoBaja cargados.
BEGIN TRY
    SELECT 'ANTES 4.10' AS momento, id, fechaBaja, motivoBaja FROM Equipos.ListadoJugadores WHERE id = @conv1;
    EXEC Equipos.ListadoJugadores_Baja @id = @conv1, @fechaBaja = '2026-06-01', @motivoBaja = 'Lesión de rodilla';
    SELECT 'DESPUES 4.10' AS momento, id, fechaBaja, motivoBaja FROM Equipos.ListadoJugadores WHERE id = @conv1;
    IF EXISTS (SELECT 1 FROM Equipos.ListadoJugadores WHERE id = @conv1 AND fechaBaja = '2026-06-01')
        PRINT '[OK] PRUEBA 4.10: baja lógica registrada.';
    ELSE PRINT '[FALLO] PRUEBA 4.10: la baja no se registró.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 4.10: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.11: baja de un convocado que ya fue dado de baja
-- Resultado esperado: error 50001 "El convocado ya fue dado de baja."
BEGIN TRY
    EXEC Equipos.ListadoJugadores_Baja @id = @conv1, @fechaBaja = '2026-06-02', @motivoBaja = 'Otra';
    PRINT '[FALLO] PRUEBA 4.11: se dio de baja dos veces.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%ya fue dado de baja%'
        PRINT '[OK] PRUEBA 4.11: doble baja rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 4.11: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.12: modificación de la fecha de alta a una posterior a la baja
-- Resultado esperado: error 50001 "La fecha de alta no puede ser posterior a la fecha de baja."
BEGIN TRY
    EXEC Equipos.ListadoJugadores_Modificacion @id = @conv1, @dorsal = 11, @fechaAlta = '2026-06-10';
    PRINT '[FALLO] PRUEBA 4.12: se aceptó una fecha de alta posterior a la baja.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%alta no puede ser posterior a la fecha de baja%'
        PRINT '[OK] PRUEBA 4.12: fecha de alta posterior a la baja rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 4.12: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.13: reemplazo con un convocado de otra selección y alta anterior a la baja
-- Resultado esperado: error 50001 con "pertenece a otra selección" y "alta del reemplazo es anterior a la baja".
BEGIN TRY
    EXEC Equipos.ListadoJugadores_Alta @idSeleccion = @selS, @idJugador = @j3, @dorsal = 21,
         @fechaAlta = '2026-05-15', @idReemplazaA = @conv1;
    PRINT '[FALLO] PRUEBA 4.13: se aceptó un reemplazo inválido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%pertenece a otra selección%'
       AND ERROR_MESSAGE() LIKE N'%alta del reemplazo es anterior a la baja%'
        PRINT '[OK] PRUEBA 4.13: reemplazo inválido rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 4.13: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.14: reemplazo exitoso con el dorsal que liberó la baja
-- Resultado esperado: el jugador Tres queda convocado con el 11 e idReemplazaA = convocatoria del jugador Uno.
BEGIN TRY
    SELECT 'ANTES 4.14' AS momento, id, idJugador, dorsal, fechaBaja, idReemplazaA
    FROM Equipos.ListadoJugadores WHERE idSeleccion = @selR;
    EXEC Equipos.ListadoJugadores_Alta @idSeleccion = @selR, @idJugador = @j3, @dorsal = 11,
         @fechaAlta = '2026-06-01', @idReemplazaA = @conv1, @id = @id OUTPUT;
    SELECT 'DESPUES 4.14' AS momento, id, idJugador, dorsal, fechaBaja, idReemplazaA
    FROM Equipos.ListadoJugadores WHERE idSeleccion = @selR;
    IF EXISTS (SELECT 1 FROM Equipos.ListadoJugadores WHERE id = @id AND idReemplazaA = @conv1 AND dorsal = 11)
        PRINT '[OK] PRUEBA 4.14: reemplazo registrado.';
    ELSE PRINT '[FALLO] PRUEBA 4.14: el reemplazo no quedó como se esperaba.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 4.14: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.15: segundo reemplazo del mismo convocado
-- Resultado esperado: error 50001 "El convocado reemplazado ya tiene otro reemplazo registrado."
BEGIN TRY
    EXEC Equipos.ListadoJugadores_Alta @idSeleccion = @selR, @idJugador = @j4, @dorsal = 22,
         @fechaAlta = '2026-06-02', @idReemplazaA = @conv1;
    PRINT '[FALLO] PRUEBA 4.15: se aceptó un segundo reemplazo.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%ya tiene otro reemplazo registrado%'
        PRINT '[OK] PRUEBA 4.15: segundo reemplazo rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 4.15: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   5. Bajas con dependencias
   ============================================================================= */
PRINT '--- 5. Bajas con dependencias ---';

-- PRUEBA 5.1: baja de una selección con partido, convocados y cuerpo técnico
-- Resultado esperado: error 50001 con las tres dependencias en el mismo mensaje.
BEGIN TRY
    DECLARE @selR int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'QRA');
    EXEC Equipos.Seleccion_Baja @id = @selR;
    PRINT '[FALLO] PRUEBA 5.1: se eliminó una selección con dependencias.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'%tiene partidos asignados%'
       AND ERROR_MESSAGE() LIKE N'%tiene jugadores convocados%'
       AND ERROR_MESSAGE() LIKE N'%tiene cuerpo técnico registrado%'
        PRINT '[OK] PRUEBA 5.1: baja de selección con dependencias rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 5.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 5.2: baja de un jugador que figura en una convocatoria
-- Resultado esperado: error 50001 "El jugador figura en convocatorias."
BEGIN TRY
    DECLARE @j1 int = (SELECT id FROM Equipos.Jugador WHERE apellido = N'Prueba80b' AND nombre = N'Uno');
    EXEC Equipos.Jugador_Baja @id = @j1;
    PRINT '[FALLO] PRUEBA 5.2: se eliminó un jugador convocado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%figura en convocatorias%'
        PRINT '[OK] PRUEBA 5.2: baja de jugador convocado rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 5.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 5.3: baja exitosa de una selección sin dependencias
-- Resultado esperado: la selección QTA deja de existir.
BEGIN TRY
    DECLARE @selT int = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'QTA');
    SELECT 'ANTES 5.3' AS momento, COUNT(*) AS filas FROM Equipos.Seleccion WHERE id = @selT;
    EXEC Equipos.Seleccion_Baja @id = @selT;
    SELECT 'DESPUES 5.3' AS momento, COUNT(*) AS filas FROM Equipos.Seleccion WHERE id = @selT;
    IF NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE id = @selT)
        PRINT '[OK] PRUEBA 5.3: selección eliminada.';
    ELSE PRINT '[FALLO] PRUEBA 5.3: la selección sigue existiendo.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 5.3: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   LIMPIEZA FINAL
   ============================================================================= */
DELETE FROM Equipos.ListadoJugadores WHERE idReemplazaA IS NOT NULL
    AND idJugador IN (SELECT id FROM Equipos.Jugador WHERE apellido = N'Prueba80b');
DELETE FROM Equipos.ListadoJugadores WHERE idJugador IN (SELECT id FROM Equipos.Jugador WHERE apellido = N'Prueba80b');
DELETE FROM Equipos.Staff WHERE apellido = N'Prueba80b';
DELETE FROM Equipos.Jugador WHERE apellido = N'Prueba80b';
DELETE FROM Torneo.Partido WHERE nroPartidoOficial = 98011;
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('QRA', 'QSA', 'QTA');
DELETE FROM Torneo.Sede WHERE nombreEstadio = N'Estadio Prueba 80b';
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('QR', 'QS', 'QT', 'QU');
DELETE FROM Torneo.Fase WHERE idFase = 903;

PRINT '================================================================================';
PRINT ' FIN DE LAS PRUEBAS: 10b_ABM_Equipos.sql (39 pruebas)';
PRINT '================================================================================';
GO
