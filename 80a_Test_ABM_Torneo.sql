/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 09/11/2026

 Objetivo    : Pruebas de los SP de 10a_ABM_Torneo.sql (Pais, Fase, Periodo,
               Sede y Partido): casos exitosos con evidencia antes/después y
               casos que deben fallar en cada validación.

 Requisitos  : 00_InitialSchema.sql, 10a, 10b (selecciones y jugadores del
               fixture) y 11b (formación y gol para las reglas de Partido).

 Datos de prueba:
 - Países con códigos ISO de uso privado (QM, QN, QO, QP / QMA, QNA, QOA, QPA),
   que la norma ISO 3166 nunca asigna a un país real.
 - Fases 901-902, períodos 201-202, partidos oficiales 98001-98004.
 - Se limpian al inicio y al final: el script se puede ejecutar varias veces.

 Cada prueba imprime [OK] o [FALLO]. Resultado esperado: todas [OK].
================================================================================
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

PRINT '================================================================================';
PRINT ' PRUEBAS: 10a_ABM_Torneo.sql';
PRINT '================================================================================';
GO

/* =============================================================================
   LIMPIEZA PREVIA
   Se borra en orden inverso de claves foráneas con DELETE directo: si una
   corrida anterior se cortó a mitad, los SP de baja rechazarían los datos
   que quedaron con dependencias.
   ============================================================================= */
DELETE FROM Eventos.Gol WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 98001 AND 98004);
DELETE FROM Eventos.FormacionPartido WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 98001 AND 98004);
DELETE FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 98001 AND 98004
    OR idSede IN (SELECT idSede FROM Torneo.Sede WHERE nombreEstadio LIKE N'Estadio Prueba 80a%');
DELETE FROM Equipos.Jugador WHERE apellido = N'Prueba80a';
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('QMA', 'QNA', 'QOA');
DELETE FROM Torneo.Sede WHERE nombreEstadio LIKE N'Estadio Prueba 80a%';
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('QM', 'QN', 'QO', 'QP');
DELETE FROM Torneo.Fase WHERE idFase IN (901, 902);
DELETE FROM Torneo.Periodo WHERE idPeriodo IN (201, 202);
GO

/* =============================================================================
   1. Torneo.Pais
   ============================================================================= */
PRINT '--- 1. Torneo.Pais ---';

-- PRUEBA 1.1: alta exitosa (códigos en minúscula y con espacios, se normalizan)
-- Resultado esperado: se crea el país con codigoISO2 = 'QM' y codigoISO3 = 'QMA'.
DECLARE @id int;
BEGIN TRY
    SELECT 'ANTES 1.1' AS momento, COUNT(*) AS filas FROM Torneo.Pais WHERE codigoISO2 = 'QM';
    EXEC Torneo.Pais_Alta @nombre = N'País Prueba Uno', @codigoISO2 = ' qm ', @codigoISO3 = 'qma',
         @husoHorario = 'UTC', @moneda = 'usd', @pbiPerCapita = 1000, @poblacion = 5000, @id = @id OUTPUT;
    SELECT 'DESPUES 1.1' AS momento, * FROM Torneo.Pais WHERE id = @id;
    IF EXISTS (SELECT 1 FROM Torneo.Pais WHERE id = @id AND codigoISO2 = 'QM' AND codigoISO3 = 'QMA' AND moneda = 'USD')
        PRINT '[OK] PRUEBA 1.1: país creado y códigos normalizados.';
    ELSE PRINT '[FALLO] PRUEBA 1.1: el país no quedó como se esperaba.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.2: alta sin nombre
-- Resultado esperado: error 50001 "El nombre del país es obligatorio."
BEGIN TRY
    EXEC Torneo.Pais_Alta @nombre = N'  ', @codigoISO2 = 'QN', @codigoISO3 = 'QNA';
    PRINT '[FALLO] PRUEBA 1.2: se aceptó un país sin nombre.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%nombre del país es obligatorio%'
        PRINT '[OK] PRUEBA 1.2: país sin nombre rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 1.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.3: código ISO alfa-2 con un dígito
-- Resultado esperado: error 50001 "El código ISO alfa-2 debe tener exactamente 2 letras."
BEGIN TRY
    EXEC Torneo.Pais_Alta @nombre = N'País Prueba Dos', @codigoISO2 = 'Q1', @codigoISO3 = 'QNA';
    PRINT '[FALLO] PRUEBA 1.3: se aceptó un ISO alfa-2 con un dígito.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%alfa-2 debe tener exactamente 2 letras%'
        PRINT '[OK] PRUEBA 1.3: ISO alfa-2 inválido rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 1.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.4: código ISO alfa-2 repetido
-- Resultado esperado: error 50001 "El código ISO alfa-2 ya está registrado."
BEGIN TRY
    EXEC Torneo.Pais_Alta @nombre = N'País Prueba Dos', @codigoISO2 = 'QM', @codigoISO3 = 'QNA';
    PRINT '[FALLO] PRUEBA 1.4: se aceptó un ISO alfa-2 repetido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%alfa-2 ya está registrado%'
        PRINT '[OK] PRUEBA 1.4: ISO alfa-2 repetido rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 1.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.5: código ISO alfa-3 de 2 letras
-- Resultado esperado: error 50001 "El código ISO alfa-3 debe tener exactamente 3 letras."
BEGIN TRY
    EXEC Torneo.Pais_Alta @nombre = N'País Prueba Dos', @codigoISO2 = 'QN', @codigoISO3 = 'QN';
    PRINT '[FALLO] PRUEBA 1.5: se aceptó un ISO alfa-3 de 2 letras.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%alfa-3 debe tener exactamente 3 letras%'
        PRINT '[OK] PRUEBA 1.5: ISO alfa-3 inválido rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 1.5: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.6: huso horario inexistente
-- Resultado esperado: error 50001 "El huso horario no es un nombre válido de sys.time_zone_info."
BEGIN TRY
    EXEC Torneo.Pais_Alta @nombre = N'País Prueba Dos', @codigoISO2 = 'QN', @codigoISO3 = 'QNA',
         @husoHorario = 'GMT-3';
    PRINT '[FALLO] PRUEBA 1.6: se aceptó un huso horario inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%huso horario no es un nombre válido%'
        PRINT '[OK] PRUEBA 1.6: huso horario inválido rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 1.6: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.7: moneda que no es un código de 3 letras
-- Resultado esperado: error 50001 "La moneda debe ser un código ISO 4217 de 3 letras."
BEGIN TRY
    EXEC Torneo.Pais_Alta @nombre = N'País Prueba Dos', @codigoISO2 = 'QN', @codigoISO3 = 'QNA',
         @moneda = 'U$S';
    PRINT '[FALLO] PRUEBA 1.7: se aceptó una moneda inválida.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%moneda debe ser un código ISO 4217%'
        PRINT '[OK] PRUEBA 1.7: moneda inválida rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 1.7: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.8: acumulación de errores (sin nombre, ISO alfa-2 inválido, PBI y población negativos)
-- Resultado esperado: error 50001 con las cuatro líneas en el mismo mensaje.
BEGIN TRY
    EXEC Torneo.Pais_Alta @nombre = NULL, @codigoISO2 = '12', @codigoISO3 = 'QNA',
         @pbiPerCapita = -1, @poblacion = -1;
    PRINT '[FALLO] PRUEBA 1.8: no se detectaron los errores.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'%nombre del país es obligatorio%'
       AND ERROR_MESSAGE() LIKE N'%alfa-2 debe tener exactamente 2 letras%'
       AND ERROR_MESSAGE() LIKE N'%PBI per cápita no puede ser negativo%'
       AND ERROR_MESSAGE() LIKE N'%población no puede ser negativa%'
        PRINT '[OK] PRUEBA 1.8: los 4 errores se informaron juntos.';
    ELSE PRINT '[FALLO] PRUEBA 1.8: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.9: modificación exitosa
-- Resultado esperado: cambian el nombre y el huso horario del país QM.
BEGIN TRY
    SET @id = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'QM');
    SELECT 'ANTES 1.9' AS momento, nombre, husoHorario FROM Torneo.Pais WHERE id = @id;
    EXEC Torneo.Pais_Modificacion @id = @id, @nombre = N'País Prueba Uno Modificado', @codigoISO2 = 'QM',
         @codigoISO3 = 'QMA', @husoHorario = 'Argentina Standard Time', @moneda = 'USD';
    SELECT 'DESPUES 1.9' AS momento, nombre, husoHorario FROM Torneo.Pais WHERE id = @id;
    IF EXISTS (SELECT 1 FROM Torneo.Pais WHERE id = @id AND husoHorario = 'Argentina Standard Time')
        PRINT '[OK] PRUEBA 1.9: país modificado.';
    ELSE PRINT '[FALLO] PRUEBA 1.9: el país no se modificó.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 1.9: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 1.10: modificación de un país inexistente
-- Resultado esperado: error 50001 "El país a modificar no existe."
BEGIN TRY
    EXEC Torneo.Pais_Modificacion @id = -1, @nombre = N'X', @codigoISO2 = 'QP', @codigoISO3 = 'QPA';
    PRINT '[FALLO] PRUEBA 1.10: se modificó un país inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%país a modificar no existe%'
        PRINT '[OK] PRUEBA 1.10: país inexistente rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 1.10: ' + ERROR_MESSAGE();
END CATCH;

-- Países auxiliares para las pruebas siguientes
EXEC Torneo.Pais_Alta @nombre = N'País Prueba Dos',    @codigoISO2 = 'QN', @codigoISO3 = 'QNA';
EXEC Torneo.Pais_Alta @nombre = N'País Prueba Tres',   @codigoISO2 = 'QO', @codigoISO3 = 'QOA';
EXEC Torneo.Pais_Alta @nombre = N'País Prueba Cuatro', @codigoISO2 = 'QP', @codigoISO3 = 'QPA';

-- PRUEBA 1.11: modificación con un ISO alfa-2 que ya usa otro país
-- Resultado esperado: error 50001 "El código ISO alfa-2 ya lo usa otro país."
BEGIN TRY
    SET @id = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'QN');
    EXEC Torneo.Pais_Modificacion @id = @id, @nombre = N'País Prueba Dos', @codigoISO2 = 'QM', @codigoISO3 = 'QNA';
    PRINT '[FALLO] PRUEBA 1.11: se aceptó un ISO alfa-2 de otro país.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%alfa-2 ya lo usa otro país%'
        PRINT '[OK] PRUEBA 1.11: ISO alfa-2 de otro país rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 1.11: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   2. Torneo.Fase
   ============================================================================= */
PRINT '--- 2. Torneo.Fase ---';

-- PRUEBA 2.1: alta exitosa
-- Resultado esperado: se crea la fase 901.
BEGIN TRY
    SELECT 'ANTES 2.1' AS momento, COUNT(*) AS filas FROM Torneo.Fase WHERE idFase = 901;
    EXEC Torneo.Fase_Alta @idFase = 901, @nombre = 'Fase Prueba Grupos', @esEliminatoria = 0, @orden = 1;
    SELECT 'DESPUES 2.1' AS momento, * FROM Torneo.Fase WHERE idFase = 901;
    IF EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = 901)
        PRINT '[OK] PRUEBA 2.1: fase creada.';
    ELSE PRINT '[FALLO] PRUEBA 2.1: la fase no se creó.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.2: id y nombre repetidos
-- Resultado esperado: error 50001 con "Ya existe una fase con ese id." y "Ya existe una fase con ese nombre."
BEGIN TRY
    EXEC Torneo.Fase_Alta @idFase = 901, @nombre = 'Fase Prueba Grupos', @esEliminatoria = 0, @orden = 1;
    PRINT '[FALLO] PRUEBA 2.2: se aceptó una fase repetida.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%fase con ese id%'
       AND ERROR_MESSAGE() LIKE N'%fase con ese nombre%'
        PRINT '[OK] PRUEBA 2.2: id y nombre repetidos rechazados juntos.';
    ELSE PRINT '[FALLO] PRUEBA 2.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.3: sin indicar si es eliminatoria y con orden 0
-- Resultado esperado: error 50001 con "Debe indicar si la fase es eliminatoria" y "orden ... mayor a cero".
BEGIN TRY
    EXEC Torneo.Fase_Alta @idFase = 902, @nombre = 'Fase Prueba Final', @esEliminatoria = NULL, @orden = 0;
    PRINT '[FALLO] PRUEBA 2.3: se aceptó una fase sin datos obligatorios.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%si la fase es eliminatoria%'
       AND ERROR_MESSAGE() LIKE N'%orden de la fase es obligatorio%'
        PRINT '[OK] PRUEBA 2.3: datos obligatorios de la fase verificados.';
    ELSE PRINT '[FALLO] PRUEBA 2.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.4: modificación exitosa
-- Resultado esperado: la fase 902 pasa de orden 5 a orden 7.
BEGIN TRY
    EXEC Torneo.Fase_Alta @idFase = 902, @nombre = 'Fase Prueba Final', @esEliminatoria = 1, @orden = 5;
    SELECT 'ANTES 2.4' AS momento, * FROM Torneo.Fase WHERE idFase = 902;
    EXEC Torneo.Fase_Modificacion @idFase = 902, @nombre = 'Fase Prueba Final', @esEliminatoria = 1, @orden = 7;
    SELECT 'DESPUES 2.4' AS momento, * FROM Torneo.Fase WHERE idFase = 902;
    IF EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = 902 AND orden = 7)
        PRINT '[OK] PRUEBA 2.4: fase modificada.';
    ELSE PRINT '[FALLO] PRUEBA 2.4: la fase no se modificó.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 2.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 2.5: modificación con el nombre de otra fase
-- Resultado esperado: error 50001 "Ya existe otra fase con ese nombre."
BEGIN TRY
    EXEC Torneo.Fase_Modificacion @idFase = 902, @nombre = 'Fase Prueba Grupos', @esEliminatoria = 1, @orden = 7;
    PRINT '[FALLO] PRUEBA 2.5: se aceptó el nombre de otra fase.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%otra fase con ese nombre%'
        PRINT '[OK] PRUEBA 2.5: nombre de otra fase rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 2.5: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   3. Torneo.Periodo
   ============================================================================= */
PRINT '--- 3. Torneo.Periodo ---';

-- PRUEBA 3.1: alta exitosa
-- Resultado esperado: se crea el período 201.
BEGIN TRY
    SELECT 'ANTES 3.1' AS momento, COUNT(*) AS filas FROM Torneo.Periodo WHERE idPeriodo = 201;
    EXEC Torneo.Periodo_Alta @idPeriodo = 201, @nombre = 'Periodo Prueba 1', @orden = 201;
    SELECT 'DESPUES 3.1' AS momento, * FROM Torneo.Periodo WHERE idPeriodo = 201;
    IF EXISTS (SELECT 1 FROM Torneo.Periodo WHERE idPeriodo = 201)
        PRINT '[OK] PRUEBA 3.1: período creado.';
    ELSE PRINT '[FALLO] PRUEBA 3.1: el período no se creó.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 3.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.2: id fuera del rango de tinyint
-- Resultado esperado: error 50001 "El id del período ... debe estar entre 1 y 255." (no un error de conversión)
BEGIN TRY
    EXEC Torneo.Periodo_Alta @idPeriodo = 300, @nombre = 'Periodo Prueba 2', @orden = 202;
    PRINT '[FALLO] PRUEBA 3.2: se aceptó un id fuera de rango.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%id del período es obligatorio y debe estar entre 1 y 255%'
        PRINT '[OK] PRUEBA 3.2: id fuera de rango rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 3.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.3: orden repetido
-- Resultado esperado: error 50001 "Ya existe un período con ese orden."
BEGIN TRY
    EXEC Torneo.Periodo_Alta @idPeriodo = 202, @nombre = 'Periodo Prueba 2', @orden = 201;
    PRINT '[FALLO] PRUEBA 3.3: se aceptó un orden repetido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%período con ese orden%'
        PRINT '[OK] PRUEBA 3.3: orden repetido rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 3.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.4: modificación exitosa
-- Resultado esperado: el período 202 cambia de nombre.
BEGIN TRY
    EXEC Torneo.Periodo_Alta @idPeriodo = 202, @nombre = 'Periodo Prueba 2', @orden = 202;
    SELECT 'ANTES 3.4' AS momento, * FROM Torneo.Periodo WHERE idPeriodo = 202;
    EXEC Torneo.Periodo_Modificacion @idPeriodo = 202, @nombre = 'Periodo Prueba 2 Mod', @orden = 202;
    SELECT 'DESPUES 3.4' AS momento, * FROM Torneo.Periodo WHERE idPeriodo = 202;
    IF EXISTS (SELECT 1 FROM Torneo.Periodo WHERE idPeriodo = 202 AND nombre = 'Periodo Prueba 2 Mod')
        PRINT '[OK] PRUEBA 3.4: período modificado.';
    ELSE PRINT '[FALLO] PRUEBA 3.4: el período no se modificó.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 3.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 3.5: modificación con el nombre de otro período
-- Resultado esperado: error 50001 "Ya existe otro período con ese nombre."
BEGIN TRY
    EXEC Torneo.Periodo_Modificacion @idPeriodo = 202, @nombre = 'Periodo Prueba 1', @orden = 202;
    PRINT '[FALLO] PRUEBA 3.5: se aceptó el nombre de otro período.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%otro período con ese nombre%'
        PRINT '[OK] PRUEBA 3.5: nombre de otro período rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 3.5: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   4. Torneo.Sede
   ============================================================================= */
PRINT '--- 4. Torneo.Sede ---';

DECLARE @idPais int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'QM');
DECLARE @idSede int;

-- PRUEBA 4.1: alta exitosa
-- Resultado esperado: se crea la sede con capacidad 50000.
BEGIN TRY
    SELECT 'ANTES 4.1' AS momento, COUNT(*) AS filas FROM Torneo.Sede WHERE nombreEstadio = N'Estadio Prueba 80a';
    EXEC Torneo.Sede_Alta @nombreEstadio = N'Estadio Prueba 80a', @ciudad = N'Ciudad Prueba', @idPais = @idPais,
         @husoHorario = 'Eastern Standard Time', @capacidad = 50000, @latitud = 40.5, @longitud = -74.2,
         @idSede = @idSede OUTPUT;
    SELECT 'DESPUES 4.1' AS momento, * FROM Torneo.Sede WHERE idSede = @idSede;
    IF @idSede IS NOT NULL
        PRINT '[OK] PRUEBA 4.1: sede creada con ID = ' + CAST(@idSede AS varchar(10));
    ELSE PRINT '[FALLO] PRUEBA 4.1: no se devolvió el ID.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 4.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.2: sede repetida (mismo estadio y ciudad)
-- Resultado esperado: error 50001 "Ya existe una sede con ese estadio en esa ciudad."
BEGIN TRY
    EXEC Torneo.Sede_Alta @nombreEstadio = N'Estadio Prueba 80a', @ciudad = N'Ciudad Prueba', @idPais = @idPais,
         @husoHorario = 'UTC';
    PRINT '[FALLO] PRUEBA 4.2: se aceptó una sede repetida.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%sede con ese estadio en esa ciudad%'
        PRINT '[OK] PRUEBA 4.2: sede repetida rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 4.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.3: acumulación (país inexistente, huso inválido, capacidad 0, latitud y longitud fuera de rango)
-- Resultado esperado: error 50001 con las cinco líneas en el mismo mensaje.
BEGIN TRY
    EXEC Torneo.Sede_Alta @nombreEstadio = N'Estadio Prueba 80a Error', @ciudad = N'Ciudad Prueba', @idPais = -1,
         @husoHorario = 'Hora de Marte', @capacidad = 0, @latitud = 95, @longitud = 200;
    PRINT '[FALLO] PRUEBA 4.3: no se detectaron los errores.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
       AND ERROR_MESSAGE() LIKE N'%país de la sede no existe%'
       AND ERROR_MESSAGE() LIKE N'%huso horario es obligatorio%'
       AND ERROR_MESSAGE() LIKE N'%capacidad del estadio debe ser mayor a cero%'
       AND ERROR_MESSAGE() LIKE N'%latitud debe estar entre%'
       AND ERROR_MESSAGE() LIKE N'%longitud debe estar entre%'
        PRINT '[OK] PRUEBA 4.3: los 5 errores se informaron juntos.';
    ELSE PRINT '[FALLO] PRUEBA 4.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.4: alta sin huso horario
-- Resultado esperado: error 50001 "El huso horario es obligatorio..."
BEGIN TRY
    EXEC Torneo.Sede_Alta @nombreEstadio = N'Estadio Prueba 80a Error', @ciudad = N'Ciudad Prueba',
         @idPais = @idPais, @husoHorario = NULL;
    PRINT '[FALLO] PRUEBA 4.4: se aceptó una sede sin huso horario.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%huso horario es obligatorio%'
        PRINT '[OK] PRUEBA 4.4: sede sin huso horario rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 4.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 4.5: modificación exitosa
-- Resultado esperado: la capacidad pasa de 50000 a 60000.
BEGIN TRY
    SET @idSede = (SELECT idSede FROM Torneo.Sede WHERE nombreEstadio = N'Estadio Prueba 80a');
    SELECT 'ANTES 4.5' AS momento, idSede, capacidad FROM Torneo.Sede WHERE idSede = @idSede;
    EXEC Torneo.Sede_Modificacion @idSede = @idSede, @nombreEstadio = N'Estadio Prueba 80a', @ciudad = N'Ciudad Prueba',
         @idPais = @idPais, @husoHorario = 'Eastern Standard Time', @capacidad = 60000, @latitud = 40.5, @longitud = -74.2;
    SELECT 'DESPUES 4.5' AS momento, idSede, capacidad FROM Torneo.Sede WHERE idSede = @idSede;
    IF EXISTS (SELECT 1 FROM Torneo.Sede WHERE idSede = @idSede AND capacidad = 60000)
        PRINT '[OK] PRUEBA 4.5: sede modificada.';
    ELSE PRINT '[FALLO] PRUEBA 4.5: la sede no se modificó.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 4.5: ' + ERROR_MESSAGE();
END CATCH;

-- Segunda sede para la prueba de partidos simultáneos de una selección
EXEC Torneo.Sede_Alta @nombreEstadio = N'Estadio Prueba 80a Dos', @ciudad = N'Ciudad Prueba',
     @idPais = @idPais, @husoHorario = 'Pacific Standard Time', @capacidad = 40000;
GO

/* =============================================================================
   5. Torneo.Partido
   ============================================================================= */
PRINT '--- 5. Torneo.Partido ---';

-- Selecciones del fixture (SP de 10b)
DECLARE @idPaisQM int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'QM');
DECLARE @idPaisQN int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'QN');
DECLARE @idPaisQO int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'QO');
EXEC Equipos.Seleccion_Alta @idPais = @idPaisQM, @confederacion = 'UEFA', @abreviacion = 'QMA';
EXEC Equipos.Seleccion_Alta @idPais = @idPaisQN, @confederacion = 'CAF',  @abreviacion = 'QNA';
EXEC Equipos.Seleccion_Alta @idPais = @idPaisQO, @confederacion = 'AFC',  @abreviacion = 'QOA';

DECLARE @selA int  = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'QMA');
DECLARE @selB int  = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'QNA');
DECLARE @selC int  = (SELECT id FROM Equipos.Seleccion WHERE abreviacion = 'QOA');
DECLARE @sede1 int = (SELECT idSede FROM Torneo.Sede WHERE nombreEstadio = N'Estadio Prueba 80a');
DECLARE @sede2 int = (SELECT idSede FROM Torneo.Sede WHERE nombreEstadio = N'Estadio Prueba 80a Dos');
DECLARE @idPartido int;

-- PRUEBA 5.1: alta exitosa de un partido programado con esquemas válidos
-- Resultado esperado: se crea el partido 98001 en estado Programado.
BEGIN TRY
    SELECT 'ANTES 5.1' AS momento, COUNT(*) AS filas FROM Torneo.Partido WHERE nroPartidoOficial = 98001;
    EXEC Torneo.Partido_Alta @idSede = @sede1, @idSeleccionLocal = @selA, @idSeleccionVisitante = @selB, @fase = 901,
         @fechaHoraUTC = '2030-06-11 18:00', @nroPartidoOficial = 98001,
         @esquemaLocal = '4-3-3', @esquemaVisitante = '4-2-3-1', @idPartido = @idPartido OUTPUT;
    SELECT 'DESPUES 5.1' AS momento, * FROM Torneo.Partido WHERE idPartido = @idPartido;
    IF EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido AND estado = 'Programado')
        PRINT '[OK] PRUEBA 5.1: partido creado en estado Programado.';
    ELSE PRINT '[FALLO] PRUEBA 5.1: el partido no quedó como se esperaba.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 5.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 5.2: misma selección de los dos lados
-- Resultado esperado: error 50001 "La selección local y la visitante deben ser distintas."
BEGIN TRY
    EXEC Torneo.Partido_Alta @idSede = @sede1, @idSeleccionLocal = @selA, @idSeleccionVisitante = @selA, @fase = 901,
         @fechaHoraUTC = '2030-07-01 18:00';
    PRINT '[FALLO] PRUEBA 5.2: se aceptó la misma selección de los dos lados.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%local y la visitante deben ser distintas%'
        PRINT '[OK] PRUEBA 5.2: misma selección rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 5.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 5.3: partido programado con resultado
-- Resultado esperado: error 50001 "Un partido programado no puede tener resultado cargado."
BEGIN TRY
    EXEC Torneo.Partido_Alta @idSede = @sede1, @idSeleccionLocal = @selA, @idSeleccionVisitante = @selB, @fase = 901,
         @fechaHoraUTC = '2030-07-01 18:00', @golLocal = 1, @golVisitante = 0;
    PRINT '[FALLO] PRUEBA 5.3: se aceptó un programado con resultado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%programado no puede tener resultado%'
        PRINT '[OK] PRUEBA 5.3: programado con resultado rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 5.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 5.4: partido finalizado sin resultado
-- Resultado esperado: error 50001 "Un partido finalizado requiere el resultado completo."
BEGIN TRY
    EXEC Torneo.Partido_Alta @idSede = @sede1, @idSeleccionLocal = @selA, @idSeleccionVisitante = @selB, @fase = 901,
         @fechaHoraUTC = '2030-07-01 18:00', @estado = 'Finalizado';
    PRINT '[FALLO] PRUEBA 5.4: se aceptó un finalizado sin resultado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%finalizado requiere el resultado completo%'
        PRINT '[OK] PRUEBA 5.4: finalizado sin resultado rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 5.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 5.5: partido en juego con el resultado incompleto
-- Resultado esperado: error 50001 "El resultado debe cargarse completo..."
BEGIN TRY
    EXEC Torneo.Partido_Alta @idSede = @sede1, @idSeleccionLocal = @selA, @idSeleccionVisitante = @selB, @fase = 901,
         @fechaHoraUTC = '2030-07-01 18:00', @estado = 'En juego', @golLocal = 1;
    PRINT '[FALLO] PRUEBA 5.5: se aceptó un resultado incompleto.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%resultado debe cargarse completo%'
        PRINT '[OK] PRUEBA 5.5: resultado incompleto rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 5.5: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 5.6: público mayor a la capacidad de la sede (60000)
-- Resultado esperado: error 50001 "La cantidad de público supera la capacidad de la sede."
BEGIN TRY
    EXEC Torneo.Partido_Alta @idSede = @sede1, @idSeleccionLocal = @selA, @idSeleccionVisitante = @selB, @fase = 901,
         @fechaHoraUTC = '2030-07-01 18:00', @cantPublico = 60001;
    PRINT '[FALLO] PRUEBA 5.6: se aceptó público mayor a la capacidad.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%público supera la capacidad%'
        PRINT '[OK] PRUEBA 5.6: público mayor a la capacidad rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 5.6: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 5.7: esquemas inválidos (4-4-3 suma 11 jugadores; 4-a-3 tiene una letra)
-- Resultado esperado: error 50001 con el error del esquema local y el del visitante.
BEGIN TRY
    EXEC Torneo.Partido_Alta @idSede = @sede1, @idSeleccionLocal = @selA, @idSeleccionVisitante = @selB, @fase = 901,
         @fechaHoraUTC = '2030-07-01 18:00', @esquemaLocal = '4-4-3', @esquemaVisitante = '4-a-3';
    PRINT '[FALLO] PRUEBA 5.7: se aceptaron esquemas inválidos.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%esquema local debe tener%'
       AND ERROR_MESSAGE() LIKE N'%esquema visitante debe tener%'
        PRINT '[OK] PRUEBA 5.7: esquemas inválidos rechazados.';
    ELSE PRINT '[FALLO] PRUEBA 5.7: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 5.8: otro partido en la misma sede 2 horas después del 98001
-- Resultado esperado: error 50001 "La sede ya tiene otro partido a menos de 24 horas."
--                     (también falla la regla de selecciones, porque son las mismas)
BEGIN TRY
    EXEC Torneo.Partido_Alta @idSede = @sede1, @idSeleccionLocal = @selA, @idSeleccionVisitante = @selB, @fase = 901,
         @fechaHoraUTC = '2030-06-11 20:00';
    PRINT '[FALLO] PRUEBA 5.8: se aceptó un partido superpuesto en la sede.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%sede ya tiene otro partido a menos de 24 horas%'
        PRINT '[OK] PRUEBA 5.8: superposición en la sede rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 5.8: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 5.9: la selección A juega en otra sede al día siguiente del 98001 (menos de 24 h)
-- Resultado esperado: error 50001 "Alguna de las selecciones ya tiene otro partido a menos de 24 horas."
BEGIN TRY
    EXEC Torneo.Partido_Alta @idSede = @sede2, @idSeleccionLocal = @selC, @idSeleccionVisitante = @selA, @fase = 901,
         @fechaHoraUTC = '2030-06-12 12:00';
    PRINT '[FALLO] PRUEBA 5.9: se aceptó una selección con dos partidos en menos de 24 h.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%selecciones ya tiene otro partido a menos de 24 horas%'
       AND ERROR_MESSAGE() NOT LIKE N'%sede ya tiene%'
        PRINT '[OK] PRUEBA 5.9: selección con partidos superpuestos rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 5.9: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 5.10: número de partido oficial repetido
-- Resultado esperado: error 50001 "El número de partido oficial ya está registrado."
BEGIN TRY
    EXEC Torneo.Partido_Alta @idSede = @sede2, @idSeleccionLocal = @selC, @idSeleccionVisitante = @selB, @fase = 901,
         @fechaHoraUTC = '2030-07-10 18:00', @nroPartidoOficial = 98001;
    PRINT '[FALLO] PRUEBA 5.10: se aceptó un número oficial repetido.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%partido oficial ya está registrado%'
        PRINT '[OK] PRUEBA 5.10: número oficial repetido rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 5.10: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 5.11: modificación exitosa a Finalizado con resultado y público
-- Resultado esperado: el 98001 queda Finalizado 2 a 1 con 45000 espectadores.
BEGIN TRY
    SET @idPartido = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 98001);
    SELECT 'ANTES 5.11' AS momento, estado, golLocal, golVisitante, cantPublico FROM Torneo.Partido WHERE idPartido = @idPartido;
    EXEC Torneo.Partido_Modificacion @idPartido = @idPartido, @idSede = @sede1, @idSeleccionLocal = @selA,
         @idSeleccionVisitante = @selB, @fase = 901, @fechaHoraUTC = '2030-06-11 18:00', @estado = 'Finalizado',
         @nroPartidoOficial = 98001, @cantPublico = 45000, @golLocal = 2, @golVisitante = 1,
         @esquemaLocal = '4-3-3', @esquemaVisitante = '4-2-3-1';
    SELECT 'DESPUES 5.11' AS momento, estado, golLocal, golVisitante, cantPublico FROM Torneo.Partido WHERE idPartido = @idPartido;
    IF EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido AND estado = 'Finalizado' AND golLocal = 2)
        PRINT '[OK] PRUEBA 5.11: partido finalizado con resultado.';
    ELSE PRINT '[FALLO] PRUEBA 5.11: el partido no se modificó.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 5.11: ' + ERROR_MESSAGE();
END CATCH;

-- Partido 98002 con una formación cargada (SP de 11b) para las reglas siguientes
DECLARE @idJugador int;
EXEC Torneo.Partido_Alta @idSede = @sede1, @idSeleccionLocal = @selA, @idSeleccionVisitante = @selB, @fase = 901,
     @fechaHoraUTC = '2030-06-15 18:00', @nroPartidoOficial = 98002;
SET @idPartido = (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial = 98002);
EXEC Equipos.Jugador_Alta @nombre = N'Jugador', @apellido = N'Prueba80a', @id = @idJugador OUTPUT;
EXEC Eventos.FormacionPartido_Alta @idPartido = @idPartido, @idSeleccion = @selA, @idJugador = @idJugador, @titular = 1;

-- PRUEBA 5.12: cambiar las selecciones de un partido con formaciones
-- Resultado esperado: error 50001 "No se pueden cambiar las selecciones porque el partido ya tiene formaciones cargadas."
BEGIN TRY
    EXEC Torneo.Partido_Modificacion @idPartido = @idPartido, @idSede = @sede1, @idSeleccionLocal = @selC,
         @idSeleccionVisitante = @selB, @fase = 901, @fechaHoraUTC = '2030-06-15 18:00', @estado = 'Programado',
         @nroPartidoOficial = 98002;
    PRINT '[FALLO] PRUEBA 5.12: se cambiaron las selecciones de un partido con formaciones.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%ya tiene formaciones cargadas%'
        PRINT '[OK] PRUEBA 5.12: cambio de selecciones con formaciones rechazado.';
    ELSE PRINT '[FALLO] PRUEBA 5.12: ' + ERROR_MESSAGE();
END CATCH;

-- El 98002 pasa a En juego y se registra un gol en el período 201 (SP de 11b)
EXEC Torneo.Partido_Modificacion @idPartido = @idPartido, @idSede = @sede1, @idSeleccionLocal = @selA,
     @idSeleccionVisitante = @selB, @fase = 901, @fechaHoraUTC = '2030-06-15 18:00', @estado = 'En juego',
     @nroPartidoOficial = 98002, @golLocal = 1, @golVisitante = 0;
EXEC Eventos.Gol_Alta @idPartido = @idPartido, @idJugador = @idJugador, @minuto = 10, @tipo = 'Jugada', @idPeriodo = 201;

-- PRUEBA 5.13: volver a Programado un partido con eventos
-- Resultado esperado: error 50001 "No se puede volver a Programado porque el partido tiene eventos registrados."
BEGIN TRY
    EXEC Torneo.Partido_Modificacion @idPartido = @idPartido, @idSede = @sede1, @idSeleccionLocal = @selA,
         @idSeleccionVisitante = @selB, @fase = 901, @fechaHoraUTC = '2030-06-15 18:00', @estado = 'Programado',
         @nroPartidoOficial = 98002;
    PRINT '[FALLO] PRUEBA 5.13: se volvió a Programado un partido con eventos.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%volver a Programado%'
        PRINT '[OK] PRUEBA 5.13: vuelta a Programado con eventos rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 5.13: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 5.14: baja de un partido con formación y gol
-- Resultado esperado: error 50001 con "tiene formaciones cargadas" y "tiene goles, tarjetas...".
BEGIN TRY
    EXEC Torneo.Partido_Baja @idPartido = @idPartido;
    PRINT '[FALLO] PRUEBA 5.14: se eliminó un partido con eventos.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%tiene formaciones cargadas%'
       AND ERROR_MESSAGE() LIKE N'%tiene goles, tarjetas%'
        PRINT '[OK] PRUEBA 5.14: baja de partido con eventos rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 5.14: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 5.15: baja exitosa de un partido sin dependencias
-- Resultado esperado: el partido 98003 deja de existir.
BEGIN TRY
    EXEC Torneo.Partido_Alta @idSede = @sede2, @idSeleccionLocal = @selC, @idSeleccionVisitante = @selB, @fase = 901,
         @fechaHoraUTC = '2030-07-10 18:00', @nroPartidoOficial = 98003, @idPartido = @idPartido OUTPUT;
    SELECT 'ANTES 5.15' AS momento, COUNT(*) AS filas FROM Torneo.Partido WHERE idPartido = @idPartido;
    EXEC Torneo.Partido_Baja @idPartido = @idPartido;
    SELECT 'DESPUES 5.15' AS momento, COUNT(*) AS filas FROM Torneo.Partido WHERE idPartido = @idPartido;
    IF NOT EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido)
        PRINT '[OK] PRUEBA 5.15: partido eliminado.';
    ELSE PRINT '[FALLO] PRUEBA 5.15: el partido sigue existiendo.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 5.15: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   6. Bajas con dependencias y bajas exitosas de los catálogos
   ============================================================================= */
PRINT '--- 6. Bajas ---';

-- PRUEBA 6.1: baja de una fase con partidos
-- Resultado esperado: error 50001 "La fase tiene partidos asignados."
BEGIN TRY
    EXEC Torneo.Fase_Baja @idFase = 901;
    PRINT '[FALLO] PRUEBA 6.1: se eliminó una fase con partidos.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%fase tiene partidos asignados%'
        PRINT '[OK] PRUEBA 6.1: baja de fase con partidos rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 6.1: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 6.2: baja de un período con un gol
-- Resultado esperado: error 50001 "El período tiene goles, tarjetas o sustituciones registrados."
BEGIN TRY
    EXEC Torneo.Periodo_Baja @idPeriodo = 201;
    PRINT '[FALLO] PRUEBA 6.2: se eliminó un período con goles.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%período tiene goles%'
        PRINT '[OK] PRUEBA 6.2: baja de período con goles rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 6.2: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 6.3: baja de una sede con partidos
-- Resultado esperado: error 50001 "La sede tiene partidos asignados."
BEGIN TRY
    DECLARE @sede1 int = (SELECT idSede FROM Torneo.Sede WHERE nombreEstadio = N'Estadio Prueba 80a');
    EXEC Torneo.Sede_Baja @idSede = @sede1;
    PRINT '[FALLO] PRUEBA 6.3: se eliminó una sede con partidos.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%sede tiene partidos asignados%'
        PRINT '[OK] PRUEBA 6.3: baja de sede con partidos rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 6.3: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 6.4: baja de un país con sedes y selección
-- Resultado esperado: error 50001 con "tiene sedes registradas" y "tiene una selección registrada".
BEGIN TRY
    DECLARE @idPaisQM int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'QM');
    EXEC Torneo.Pais_Baja @id = @idPaisQM;
    PRINT '[FALLO] PRUEBA 6.4: se eliminó un país con dependencias.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 AND ERROR_MESSAGE() LIKE N'%tiene sedes registradas%'
       AND ERROR_MESSAGE() LIKE N'%tiene una selección registrada%'
        PRINT '[OK] PRUEBA 6.4: baja de país con dependencias rechazada.';
    ELSE PRINT '[FALLO] PRUEBA 6.4: ' + ERROR_MESSAGE();
END CATCH;

-- PRUEBA 6.5: bajas exitosas de un país, una fase y un período sin dependencias
-- Resultado esperado: dejan de existir el país QP, la fase 902 y el período 202.
BEGIN TRY
    DECLARE @idPaisQP int = (SELECT id FROM Torneo.Pais WHERE codigoISO2 = 'QP');
    EXEC Torneo.Pais_Baja @id = @idPaisQP;
    EXEC Torneo.Fase_Baja @idFase = 902;
    EXEC Torneo.Periodo_Baja @idPeriodo = 202;
    SELECT 'DESPUES 6.5' AS momento,
           (SELECT COUNT(*) FROM Torneo.Pais WHERE codigoISO2 = 'QP') AS paises,
           (SELECT COUNT(*) FROM Torneo.Fase WHERE idFase = 902) AS fases,
           (SELECT COUNT(*) FROM Torneo.Periodo WHERE idPeriodo = 202) AS periodos;
    IF NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE codigoISO2 = 'QP')
       AND NOT EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = 902)
       AND NOT EXISTS (SELECT 1 FROM Torneo.Periodo WHERE idPeriodo = 202)
        PRINT '[OK] PRUEBA 6.5: país, fase y período eliminados.';
    ELSE PRINT '[FALLO] PRUEBA 6.5: algún registro sigue existiendo.';
END TRY
BEGIN CATCH
    PRINT '[FALLO] PRUEBA 6.5: ' + ERROR_MESSAGE();
END CATCH;
GO

/* =============================================================================
   LIMPIEZA FINAL
   ============================================================================= */
DELETE FROM Eventos.Gol WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 98001 AND 98004);
DELETE FROM Eventos.FormacionPartido WHERE idPartido IN (SELECT idPartido FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 98001 AND 98004);
DELETE FROM Torneo.Partido WHERE nroPartidoOficial BETWEEN 98001 AND 98004
    OR idSede IN (SELECT idSede FROM Torneo.Sede WHERE nombreEstadio LIKE N'Estadio Prueba 80a%');
DELETE FROM Equipos.Jugador WHERE apellido = N'Prueba80a';
DELETE FROM Equipos.Seleccion WHERE abreviacion IN ('QMA', 'QNA', 'QOA');
DELETE FROM Torneo.Sede WHERE nombreEstadio LIKE N'Estadio Prueba 80a%';
DELETE FROM Torneo.Pais WHERE codigoISO2 IN ('QM', 'QN', 'QO', 'QP');
DELETE FROM Torneo.Fase WHERE idFase IN (901, 902);
DELETE FROM Torneo.Periodo WHERE idPeriodo IN (201, 202);

PRINT '================================================================================';
PRINT ' FIN DE LAS PRUEBAS: 10a_ABM_Torneo.sql (46 pruebas)';
PRINT '================================================================================';
GO
