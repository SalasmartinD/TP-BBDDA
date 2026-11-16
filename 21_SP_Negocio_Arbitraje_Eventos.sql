/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel - 45066788
               Salas, Martín Daniel - 45205702
               Zito Padró, Ezequiel Nehuén - 46097917
 Fecha       : 15/11/2026

 Objetivo    : Procedimientos almacenados de negocio de Partidos en juego y
               Arbitraje:
               - Eventos.RegistrarFormacion      (titulares, suplentes, cuerpo
                                                  técnico, esquema y cumplimiento
                                                  de suspensiones)
               - Eventos.RegistrarCambio         (cambios, ventanas y alargue)
               - Eventos.RegistrarTarjeta        (tarjeta a jugador o a integrante
                                                  del cuerpo técnico, doble
                                                  amarilla, expulsión y suspensión)
               - Arbitraje.DesignarCuerpoArbitral (5 roles, nacionalidad y
                                                  advertencia de cruce)
               Crea además los tipos tabla Eventos.FormacionJugadorLista, que
               recibe la lista de jugadores de una formación, y
               Eventos.CuerpoTecnicoLista, que recibe la del cuerpo técnico.

               Cambio cuerpo técnico por partido (Fase 2)
               - Tipo tabla nuevo Eventos.CuerpoTecnicoLista (idStaff).
               - RegistrarFormacion recibe además @cuerpoTecnico (obligatorio, no
                 vacío) y lo guarda en Eventos.CuerpoTecnicoPartido. Valida lista
                 vacía, repetidos, integrantes ajenos a la selección, más de un
                 Director Principal, integrantes suspendidos (antes de descontar
                 las suspensiones cumplidas) y cuerpo técnico ya registrado.
               - RegistrarTarjeta recibe @idJugador o @idStaff (exactamente uno).
                 Un integrante del cuerpo técnico solo recibe tarjeta si figura en
                 CuerpoTecnicoPartido del partido. Su roja suspende siempre 1
                 partido y sus amarillas acumulan según el parámetro
                 AMARILLAS_SUSPENSION_STAFF (0 = no acumulan).
               - Cada suspensión que genera RegistrarTarjeta lleva el idTarjeta
                 de la tarjeta que la originó (una suspensión por tarjeta).

 Estándares aplicados:
 - Acumulación exhaustiva de errores en @errores nvarchar(2000).
 - Un solo THROW 50002 (regla de negocio) al final de las validaciones
   informando todos los fallos.
 - Validaciones y DML dentro de la misma transacción (TRY/CATCH con ROLLBACK
   y SET XACT_ABORT ON); las lecturas que deciden estado y cupos se hacen con
   WITH (UPDLOCK, HOLDLOCK) para que nadie cambie los datos entre la
   validación y la escritura.
 - Los límites del reglamento se leen de Sistema.Parametro (no se cargan
   acá: si faltan, el SP lo informa como error).
 - Requiere Torneo.fn_EsquemaTacticoValido (10a_ABM_Torneo.sql): ejecutar el
   10a antes que este script.
 - Nombres en formato Esquema.VerboSustantivo.
 - Parámetros y variables locales estrictamente en @camelCase.
 - Todo set-based (sin recorridos fila por fila), cero SQL dinámico, cero CLR.

 Instante de un evento
 ---------------------
   Para ordenar cambios y tarjetas se usa
       CAST(minuto AS int) * 1000 + ISNULL(minutoAdicional, 0)
   (minuto es tinyint: sin el CAST la multiplicación desborda). Así 45+3 queda
   antes que 46 y 90+5 antes que 91.
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

/* =============================================================================
   0. TIPO TABLA: Eventos.FormacionJugadorLista
   CREATE TYPE no admite CREATE OR ALTER: se crea solo si no existe.
   No tiene PK a propósito: los jugadores repetidos se validan en el SP y se
   informan con el patrón de errores, no con un error del motor.
   ============================================================================= */

IF TYPE_ID(N'Eventos.FormacionJugadorLista') IS NULL
    CREATE TYPE Eventos.FormacionJugadorLista AS TABLE (
        idJugador  int          NOT NULL,
        titular    bit          NOT NULL,
        posicion   varchar(15)  NULL
    );
GO

-- Cuerpo técnico de una formación. Sin PK por el mismo motivo: los repetidos se
-- informan con el patrón de errores (F16).
IF TYPE_ID(N'Eventos.CuerpoTecnicoLista') IS NULL
    CREATE TYPE Eventos.CuerpoTecnicoLista AS TABLE (
        idStaff  int  NOT NULL
    );
GO

/* =============================================================================
   1. Eventos.RegistrarFormacion
   Registra la formación completa (titulares y suplentes) y el cuerpo técnico de
   una selección en un partido, guarda el esquema táctico y descuenta un
   partido a las suspensiones (de jugadores y de cuerpo técnico) que se
   cumplen en este partido.

   Decisiones de diseño:
   - Cuerpo técnico obligatorio: la lista no puede estar vacía, no puede tener
     repetidos, tiene que ser del Equipos.Staff de la selección y a lo sumo un
     integrante con rol 'Director Principal'. Se guarda en
     Eventos.CuerpoTecnicoPartido (igual que los jugadores en FormacionPartido).
   - Un integrante del cuerpo técnico suspendido tampoco puede figurar en el
     partido (F19). Esa validación ocurre antes del descuento: como todo es una
     sola transacción y el THROW sale antes de escribir, un rechazo no descuenta
     ninguna suspensión.
   - Un suspendido no puede estar ni de titular ni de suplente (regla FIFA):
     así no puede entrar por un cambio y la suspensión se cumple al registrar
     la formación.
   - Dorsal: FormacionPartido no tiene columna dorsal; el dorsal es el del
     convocado en Equipos.ListadoJugadores y UX_ListadoJugadores_DorsalActivo
     ya garantiza que no se repite entre convocados activos. Como se exige que
     todos los jugadores sean convocados activos, no puede haber dorsales
     repetidos y no se agrega una validación que nunca podría fallar.
   - Suspensión activa para el partido P: fila en Eventos.Suspension con
     partidosRestantes > 0 generada en un partido anterior a P (fechaHoraUTC).
   ============================================================================= */

CREATE OR ALTER PROCEDURE Eventos.RegistrarFormacion
    @idPartido   int,
    @idSeleccion int,
    @jugadores   Eventos.FormacionJugadorLista READONLY,
    @cuerpoTecnico Eventos.CuerpoTecnicoLista READONLY,   -- obligatorio (no vacío)
    @esquema     varchar(10) = NULL      -- '4-3-3', '4-2-3-1', '3-4-1-1-1'; opcional
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores          nvarchar(2000) = N'';
    DECLARE @estado           varchar(15),
            @fechaPartido     datetime2(0),
            @esLocal          bit,
            @existeSeleccion  bit = 0,
            @cantJugadores    int,
            @cantTitulares    int,
            @cantSuplentes    int,
            @maxSuplentes     int,
            @cantCuerpo       int,
            @lista            nvarchar(1000);

    SET @esquema = NULLIF(LTRIM(RTRIM(@esquema)), '');

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Datos del partido (bloqueado hasta el final de la transacción)
        SELECT @estado       = p.estado,
               @fechaPartido = p.fechaHoraUTC,
               @esLocal      = CASE WHEN p.idSeleccionLocal     = @idSeleccion THEN 1
                                    WHEN p.idSeleccionVisitante = @idSeleccion THEN 0 END
        FROM Torneo.Partido p WITH (UPDLOCK, HOLDLOCK)
        WHERE p.idPartido = @idPartido;

        IF EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE id = @idSeleccion)
            SET @existeSeleccion = 1;

        SELECT @cantJugadores = COUNT(*),
               @cantTitulares = ISNULL(SUM(CASE WHEN titular = 1 THEN 1 ELSE 0 END), 0),
               @cantSuplentes = ISNULL(SUM(CASE WHEN titular = 0 THEN 1 ELSE 0 END), 0)
        FROM @jugadores;

        SELECT @cantCuerpo = COUNT(*) FROM @cuerpoTecnico;

        SELECT @maxSuplentes = valor
        FROM Sistema.Parametro
        WHERE clave = 'MAX_SUPLENTES';

        -- F1. Existencia del partido
        IF @estado IS NULL
            SET @errores += CHAR(10) + N'- El partido especificado no existe.';

        -- F2. Existencia de la selección
        IF @existeSeleccion = 0
            SET @errores += CHAR(10) + N'- La selección especificada no existe.';

        -- F3. La selección debe disputar el partido (solo si ambos existen)
        IF @estado IS NOT NULL AND @existeSeleccion = 1 AND @esLocal IS NULL
            SET @errores += CHAR(10) + N'- La selección especificada no disputa el partido indicado.';

        -- F4. Estado del partido
        IF @estado IN ('En juego', 'Finalizado')
            SET @errores += CHAR(10) + N'- No se puede registrar la formación de un partido en juego o finalizado.';

        -- F5. La selección no puede tener ya una formación en el partido
        IF EXISTS (SELECT 1
                   FROM Eventos.FormacionPartido WITH (UPDLOCK, HOLDLOCK)
                   WHERE idPartido = @idPartido
                     AND idSeleccion = @idSeleccion)
            SET @errores += CHAR(10) + N'- La selección ya tiene una formación registrada para este partido.';

        -- F6. Lista vacía
        IF @cantJugadores = 0
            SET @errores += CHAR(10) + N'- La lista de jugadores está vacía.';

        -- F7. Exactamente 11 titulares
        IF @cantJugadores > 0 AND @cantTitulares <> 11
            SET @errores += CHAR(10) + N'- La formación titular debe tener exactamente 11 jugadores (se informaron '
                          + CAST(@cantTitulares AS nvarchar(12)) + N').';

        -- F8 / F9. Máximo de suplentes según Sistema.Parametro
        IF @maxSuplentes IS NULL
            SET @errores += CHAR(10) + N'- No está configurado el parámetro MAX_SUPLENTES en Sistema.Parametro.';
        ELSE IF @cantSuplentes > @maxSuplentes
            SET @errores += CHAR(10) + N'- La cantidad de suplentes (' + CAST(@cantSuplentes AS nvarchar(12))
                          + N') supera el máximo permitido (' + CAST(@maxSuplentes AS nvarchar(12)) + N').';

        -- F10. Jugadores repetidos en la lista
        SET @lista = NULL;
        SELECT @lista = STRING_AGG(CAST(r.idJugador AS nvarchar(12)), N', ') WITHIN GROUP (ORDER BY r.idJugador)
        FROM (SELECT idJugador
              FROM @jugadores
              GROUP BY idJugador
              HAVING COUNT(*) > 1) r;

        IF @lista IS NOT NULL
            SET @errores += CHAR(10) + N'- Hay jugadores repetidos en la lista: ' + @lista + N'.';

        -- F11. Todos deben ser convocados activos de la selección
        --      (cubre también jugadores inexistentes). Solo si la selección existe.
        IF @existeSeleccion = 1
        BEGIN
            SET @lista = NULL;
            SELECT @lista = STRING_AGG(CAST(d.idJugador AS nvarchar(12)), N', ') WITHIN GROUP (ORDER BY d.idJugador)
            FROM (SELECT DISTINCT idJugador FROM @jugadores) d
            WHERE NOT EXISTS (SELECT 1
                              FROM Equipos.ListadoJugadores lj
                              WHERE lj.idSeleccion = @idSeleccion
                                AND lj.idJugador   = d.idJugador
                                AND lj.fechaBaja IS NULL);

            IF @lista IS NOT NULL
                SET @errores += CHAR(10) + N'- Los siguientes jugadores no son convocados activos de la selección: ' + @lista + N'.';
        END;

        -- F12. Jugadores con suspensión activa para este partido
        IF @fechaPartido IS NOT NULL
        BEGIN
            SET @lista = NULL;
            SELECT @lista = STRING_AGG(CAST(d.idJugador AS nvarchar(12)), N', ') WITHIN GROUP (ORDER BY d.idJugador)
            FROM (SELECT DISTINCT idJugador FROM @jugadores) d
            WHERE EXISTS (SELECT 1
                          FROM Eventos.Suspension su
                          JOIN Torneo.Partido ps ON ps.idPartido = su.idPartido
                          WHERE su.idJugador = d.idJugador
                            AND su.partidosRestantes > 0
                            AND ps.fechaHoraUTC < @fechaPartido);

            IF @lista IS NOT NULL
                SET @errores += CHAR(10) + N'- Los siguientes jugadores están suspendidos y no pueden integrar la formación: ' + @lista + N'.';
        END;

        -- F13. Dominio de posiciones
        IF EXISTS (SELECT 1
                   FROM @jugadores
                   WHERE NULLIF(LTRIM(RTRIM(posicion)), '') NOT IN ('Arquero', 'Defensor', 'Mediocampista', 'Delantero'))
            SET @errores += CHAR(10) + N'- Hay posiciones inválidas: deben ser Arquero, Defensor, Mediocampista o Delantero.';

        -- F14. Esquema táctico: misma regla que Torneo.Partido_Alta (números de
        --      1 a 9 separados por guiones que suman 10), vía Torneo.fn_EsquemaTacticoValido
        IF @esquema IS NOT NULL AND Torneo.fn_EsquemaTacticoValido(@esquema) = 0
            SET @errores += CHAR(10) + N'- El esquema táctico debe tener números de 1 a 9 separados por guiones que sumen 10 (ej. 4-3-3).';

        -- F15. Cuerpo técnico obligatorio: lista vacía
        IF @cantCuerpo = 0
            SET @errores += CHAR(10) + N'- La lista del cuerpo técnico está vacía.';

        -- F16. Integrantes del cuerpo técnico repetidos en la lista
        SET @lista = NULL;
        SELECT @lista = STRING_AGG(CAST(r.idStaff AS nvarchar(12)), N', ') WITHIN GROUP (ORDER BY r.idStaff)
        FROM (SELECT idStaff
              FROM @cuerpoTecnico
              GROUP BY idStaff
              HAVING COUNT(*) > 1) r;

        IF @lista IS NOT NULL
            SET @errores += CHAR(10) + N'- Hay integrantes del cuerpo técnico repetidos en la lista: ' + @lista + N'.';

        -- F17. Todos deben ser del cuerpo técnico (Equipos.Staff) de la selección
        --      (cubre también integrantes inexistentes). Solo si la selección existe.
        IF @existeSeleccion = 1
        BEGIN
            SET @lista = NULL;
            SELECT @lista = STRING_AGG(CAST(d.idStaff AS nvarchar(12)), N', ') WITHIN GROUP (ORDER BY d.idStaff)
            FROM (SELECT DISTINCT idStaff FROM @cuerpoTecnico) d
            WHERE NOT EXISTS (SELECT 1
                              FROM Equipos.Staff st
                              WHERE st.id          = d.idStaff
                                AND st.idSeleccion = @idSeleccion);

            IF @lista IS NOT NULL
                SET @errores += CHAR(10) + N'- Los siguientes integrantes no pertenecen al cuerpo técnico de la selección: ' + @lista + N'.';
        END;

        -- F18. A lo sumo un Director Principal (integrantes distintos de la lista)
        IF (SELECT COUNT(*)
            FROM Equipos.Staff st
            WHERE st.rol = 'Director Principal'
              AND st.id IN (SELECT idStaff FROM @cuerpoTecnico)) > 1
            SET @errores += CHAR(10) + N'- El cuerpo técnico no puede tener más de un Director Principal.';

        -- F19. Integrantes con suspensión activa para este partido (misma regla que F12)
        IF @fechaPartido IS NOT NULL
        BEGIN
            SET @lista = NULL;
            SELECT @lista = STRING_AGG(CAST(d.idStaff AS nvarchar(12)), N', ') WITHIN GROUP (ORDER BY d.idStaff)
            FROM (SELECT DISTINCT idStaff FROM @cuerpoTecnico) d
            WHERE EXISTS (SELECT 1
                          FROM Eventos.Suspension su
                          JOIN Torneo.Partido ps ON ps.idPartido = su.idPartido
                          WHERE su.idStaff = d.idStaff
                            AND su.partidosRestantes > 0
                            AND ps.fechaHoraUTC < @fechaPartido);

            IF @lista IS NOT NULL
                SET @errores += CHAR(10) + N'- Los siguientes integrantes del cuerpo técnico están suspendidos y no pueden figurar en el partido: ' + @lista + N'.';
        END;

        -- F20. La selección no puede tener ya cuerpo técnico en el partido
        --      (solo si el partido y la selección existen)
        IF @estado IS NOT NULL AND @existeSeleccion = 1
           AND EXISTS (SELECT 1
                       FROM Eventos.CuerpoTecnicoPartido ct WITH (UPDLOCK, HOLDLOCK)
                       JOIN Equipos.Staff st ON st.id = ct.idStaff
                       WHERE ct.idPartido   = @idPartido
                         AND st.idSeleccion = @idSeleccion)
            SET @errores += CHAR(10) + N'- La selección ya tiene cuerpo técnico registrado para este partido.';

        -- THROW único
        IF @errores <> N''
        BEGIN
            SET @errores = N'No se pudo registrar la formación:' + @errores;
            THROW 50002, @errores, 1;
        END;

        -- 1. Formación
        INSERT INTO Eventos.FormacionPartido (idPartido, idSeleccion, idJugador, titular, posicion)
        SELECT @idPartido, @idSeleccion, j.idJugador, j.titular, NULLIF(LTRIM(RTRIM(j.posicion)), '')
        FROM @jugadores j;

        -- 1b. Cuerpo técnico del partido (integrantes distintos de la lista)
        INSERT INTO Eventos.CuerpoTecnicoPartido (idPartido, idStaff)
        SELECT DISTINCT @idPartido, ct.idStaff
        FROM @cuerpoTecnico ct;

        -- 2. Esquema táctico del lado que corresponde
        IF @esquema IS NOT NULL
            UPDATE Torneo.Partido
            SET esquemaLocal     = CASE WHEN @esLocal = 1 THEN @esquema ELSE esquemaLocal END,
                esquemaVisitante = CASE WHEN @esLocal = 0 THEN @esquema ELSE esquemaVisitante END
            WHERE idPartido = @idPartido;

        -- 3. Cumplimiento de suspensiones: los convocados activos y el staff de
        --    la selección con suspensión activa no juegan este partido (F12 y F19
        --    ya garantizaron que no figuran en la formación ni en el cuerpo
        --    técnico), así que se les descuenta un partido. Si una persona tiene
        --    más de una suspensión activa (una por tarjeta), se cumplen de a una:
        --    solo se descuenta la más antigua (partido más viejo y, dentro del
        --    mismo partido, la de menor id).
        WITH SuspensionActiva AS (
            SELECT su.id,
                   ROW_NUMBER() OVER (PARTITION BY su.idJugador, su.idStaff
                                      ORDER BY ps.fechaHoraUTC, su.id) AS nro
            FROM Eventos.Suspension su
            JOIN Torneo.Partido ps ON ps.idPartido = su.idPartido
            WHERE su.partidosRestantes > 0
              AND ps.fechaHoraUTC < @fechaPartido
              AND (   su.idJugador IN (SELECT lj.idJugador
                                       FROM Equipos.ListadoJugadores lj
                                       WHERE lj.idSeleccion = @idSeleccion
                                         AND lj.fechaBaja IS NULL)
                   OR su.idStaff   IN (SELECT st.id
                                       FROM Equipos.Staff st
                                       WHERE st.idSeleccion = @idSeleccion))
        )
        UPDATE su
        SET partidosRestantes = su.partidosRestantes - 1
        FROM Eventos.Suspension su
        JOIN SuspensionActiva sa ON sa.id = su.id
        WHERE sa.nro = 1;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END
GO

/* =============================================================================
   2. Eventos.RegistrarCambio
   Registra una sustitución controlando que el que sale esté en cancha, que el
   que entra esté disponible en el banco y los límites de cambios y ventanas.

   Definiciones (T = instante del cambio):
   - En cancha en T: está en la formación del partido y (es titular o entró
     por una sustitución con instante <= T), no salió por una sustitución con
     instante <= T y no tiene roja en el partido con instante <= T.
   - Disponible en el banco: suplente de la formación que todavía no entró en
     el partido y no tiene roja en el partido.
   - Selección del cambio: la del jugador que sale según la formación (si no
     está, la del que entra).
   - Ventana: cada instante distinto en que la selección hizo cambios. Un
     cambio en el mismo instante que otro ya registrado usa la misma ventana.
     No se modela que el entretiempo no consume ventana.
   - Límites: MAX_CAMBIOS y MAX_VENTANAS. Si el cambio es de alargue
     (minuto > 90) el límite de cambios suma CAMBIO_EXTRA_ALARGUE y, si ese
     extra es mayor que 0, se habilita una ventana más (el cambio extra
     necesita su propia ventana).
   ============================================================================= */

CREATE OR ALTER PROCEDURE Eventos.RegistrarCambio
    @idPartido       int,
    @idSale          int,
    @idIngresa       int,
    @idPeriodo       tinyint,
    @minuto          tinyint,
    @minutoAdicional tinyint     = NULL,
    @motivo          varchar(15),
    @id              int         = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores           nvarchar(2000) = N'';
    DECLARE @estado            varchar(15),
            @instante          int,
            @selSale           int,
            @selIngresa        int,
            @idSeleccion       int,
            @maxCambios        int,
            @maxVentanas       int,
            @extraAlargue      int,
            @faltantes         nvarchar(200),
            @limiteCambios     int,
            @limiteVentanas    int,
            @cambiosHechos     int,
            @ventanasUsadas    int,
            @ultimoInstante    int,
            @ventanaExistente  int;

    SET @motivo = NULLIF(LTRIM(RTRIM(@motivo)), '');
    SET @id = NULL;

    -- El instante solo se calcula si el minuto es válido
    IF @minuto IS NOT NULL AND @minuto <= 120
        SET @instante = CAST(@minuto AS int) * 1000 + ISNULL(@minutoAdicional, 0);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Datos del partido (bloqueado hasta el final de la transacción)
        SELECT @estado = p.estado
        FROM Torneo.Partido p WITH (UPDLOCK, HOLDLOCK)
        WHERE p.idPartido = @idPartido;

        -- Selección de cada jugador según la formación del partido
        SELECT @selSale = idSeleccion
        FROM Eventos.FormacionPartido
        WHERE idPartido = @idPartido AND idJugador = @idSale;

        SELECT @selIngresa = idSeleccion
        FROM Eventos.FormacionPartido
        WHERE idPartido = @idPartido AND idJugador = @idIngresa;

        SET @idSeleccion = ISNULL(@selSale, @selIngresa);

        -- Cambios ya registrados por la selección en el partido
        SELECT @cambiosHechos    = COUNT(*),
               @ventanasUsadas   = COUNT(DISTINCT CAST(s.minuto AS int) * 1000 + ISNULL(s.minutoAdicional, 0)),
               @ultimoInstante   = MAX(CAST(s.minuto AS int) * 1000 + ISNULL(s.minutoAdicional, 0)),
               @ventanaExistente = MAX(CASE WHEN CAST(s.minuto AS int) * 1000 + ISNULL(s.minutoAdicional, 0) = @instante
                                            THEN 1 ELSE 0 END)
        FROM Eventos.Sustitucion s WITH (UPDLOCK, HOLDLOCK)
        JOIN Eventos.FormacionPartido fp ON fp.idPartido = s.idPartido
                                        AND fp.idJugador = s.idSale
        WHERE s.idPartido = @idPartido
          AND fp.idSeleccion = @idSeleccion;

        -- Parámetros del reglamento
        SET @maxCambios   = (SELECT valor FROM Sistema.Parametro WHERE clave = 'MAX_CAMBIOS');
        SET @maxVentanas  = (SELECT valor FROM Sistema.Parametro WHERE clave = 'MAX_VENTANAS');
        SET @extraAlargue = (SELECT valor FROM Sistema.Parametro WHERE clave = 'CAMBIO_EXTRA_ALARGUE');

        SELECT @faltantes = STRING_AGG(k.clave, ', ') WITHIN GROUP (ORDER BY k.orden)
        FROM (VALUES (1, 'MAX_CAMBIOS'), (2, 'MAX_VENTANAS'), (3, 'CAMBIO_EXTRA_ALARGUE')) k (orden, clave)
        WHERE NOT EXISTS (SELECT 1 FROM Sistema.Parametro sp WHERE sp.clave = k.clave);

        -- C1. Existencia del partido
        IF @estado IS NULL
            SET @errores += CHAR(10) + N'- El partido especificado no existe.';

        -- C2. Estado del partido
        IF @estado = 'Programado'
            SET @errores += CHAR(10) + N'- No se pueden registrar cambios en un partido que todavía se encuentra en estado programado.';

        -- C3. Período de juego
        IF @idPeriodo IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Periodo WHERE idPeriodo = @idPeriodo)
            SET @errores += CHAR(10) + N'- El período de juego especificado no existe.';

        -- C4. Minuto
        IF @minuto IS NULL OR @minuto > 120
            SET @errores += CHAR(10) + N'- El minuto del cambio es obligatorio y debe encontrarse entre 0 y 120.';

        -- C5. Minuto adicional solo en minutos de cierre
        IF @minutoAdicional IS NOT NULL AND @minuto NOT IN (45, 90, 105, 120)
            SET @errores += CHAR(10) + N'- El minuto adicional solo es válido en los minutos de cierre reglamentario (45, 90, 105 o 120).';

        -- C6. Motivo
        IF @motivo IS NULL OR @motivo NOT IN ('Tactico', 'Lesion', 'Precaucion')
            SET @errores += CHAR(10) + N'- El motivo del cambio debe ser Tactico, Lesion o Precaucion.';

        -- C7. Jugadores distintos
        IF @idSale = @idIngresa
            SET @errores += CHAR(10) + N'- El jugador que sale y el que entra deben ser distintos.';

        -- C8. El que sale debe estar en cancha en T
        --     (solo si el partido existe y el minuto es válido)
        IF @estado IS NOT NULL AND @instante IS NOT NULL
           AND NOT EXISTS (
               SELECT 1
               FROM Eventos.FormacionPartido fp
               WHERE fp.idPartido = @idPartido
                 AND fp.idJugador = @idSale
                 AND (   fp.titular = 1
                      OR EXISTS (SELECT 1 FROM Eventos.Sustitucion si
                                 WHERE si.idPartido = @idPartido
                                   AND si.idIngresa = @idSale
                                   AND CAST(si.minuto AS int) * 1000 + ISNULL(si.minutoAdicional, 0) <= @instante))
                 AND NOT EXISTS (SELECT 1 FROM Eventos.Sustitucion so
                                 WHERE so.idPartido = @idPartido
                                   AND so.idSale    = @idSale
                                   AND CAST(so.minuto AS int) * 1000 + ISNULL(so.minutoAdicional, 0) <= @instante)
                 AND NOT EXISTS (SELECT 1 FROM Eventos.Tarjeta t
                                 WHERE t.idPartido = @idPartido
                                   AND t.idJugador = @idSale
                                   AND t.color     = 'R'
                                   AND CAST(t.minuto AS int) * 1000 + ISNULL(t.minutoAdicional, 0) <= @instante)
           )
            SET @errores += CHAR(10) + N'- El jugador que sale no está en cancha en ese minuto.';

        -- C9. El que entra debe estar disponible en el banco (solo si el partido existe)
        IF @estado IS NOT NULL
           AND NOT EXISTS (
               SELECT 1
               FROM Eventos.FormacionPartido fp
               WHERE fp.idPartido = @idPartido
                 AND fp.idJugador = @idIngresa
                 AND fp.titular   = 0
                 AND NOT EXISTS (SELECT 1 FROM Eventos.Sustitucion si
                                 WHERE si.idPartido = @idPartido
                                   AND si.idIngresa = @idIngresa)
                 AND NOT EXISTS (SELECT 1 FROM Eventos.Tarjeta t
                                 WHERE t.idPartido = @idPartido
                                   AND t.idJugador = @idIngresa
                                   AND t.color     = 'R')
           )
            SET @errores += CHAR(10) + N'- El jugador que entra no está disponible en el banco de suplentes.';

        -- C10. Misma selección (solo si ambos están en la formación)
        IF @selSale IS NOT NULL AND @selIngresa IS NOT NULL AND @selSale <> @selIngresa
            SET @errores += CHAR(10) + N'- Los dos jugadores deben pertenecer a la misma selección.';

        -- C11. No puede ser anterior al último cambio de la selección
        IF @idSeleccion IS NOT NULL AND @instante IS NOT NULL AND @instante < @ultimoInstante
            SET @errores += CHAR(10) + N'- El cambio no puede ser anterior al último cambio registrado de la selección.';

        -- C12. Parámetros del reglamento
        IF @faltantes IS NOT NULL
            SET @errores += CHAR(10) + N'- Faltan configurar en Sistema.Parametro: ' + @faltantes + N'.';

        -- C13 / C14. Límites de cambios y ventanas
        --            (solo si se determinó la selección y están los parámetros)
        IF @idSeleccion IS NOT NULL AND @faltantes IS NULL
        BEGIN
            SET @limiteCambios  = @maxCambios  + CASE WHEN @minuto > 90 THEN @extraAlargue ELSE 0 END;
            SET @limiteVentanas = @maxVentanas + CASE WHEN @minuto > 90 AND @extraAlargue > 0 THEN 1 ELSE 0 END;

            IF @cambiosHechos >= @limiteCambios
                SET @errores += CHAR(10) + N'- La selección ya realizó los ' + CAST(@limiteCambios AS nvarchar(12))
                              + N' cambios permitidos.';

            IF @instante IS NOT NULL
               AND ISNULL(@ventanaExistente, 0) = 0
               AND @ventanasUsadas >= @limiteVentanas
                SET @errores += CHAR(10) + N'- La selección ya usó las ' + CAST(@limiteVentanas AS nvarchar(12))
                              + N' ventanas de cambio permitidas.';
        END;

        -- THROW único
        IF @errores <> N''
        BEGIN
            SET @errores = N'No se pudo registrar el cambio:' + @errores;
            THROW 50002, @errores, 1;
        END;

        INSERT INTO Eventos.Sustitucion (idPartido, idIngresa, idSale, idPeriodo, minuto, minutoAdicional, motivo)
        VALUES (@idPartido, @idIngresa, @idSale, @idPeriodo, @minuto, @minutoAdicional, @motivo);

        SET @id = SCOPE_IDENTITY();

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END
GO

/* =============================================================================
   3. Eventos.RegistrarTarjeta
   Registra una tarjeta a un jugador o a un integrante del cuerpo técnico (se
   informa exactamente uno de @idJugador / @idStaff), genera la roja por doble
   amarilla y la suspensión que corresponda (expulsión y/o acumulación).

   Reglas de diseño (todo para la persona informada, jugador o staff):
   - Una suspensión por tarjeta: cada fila de Eventos.Suspension se crea con
     cantPartidos = partidosRestantes = 1 y el idTarjeta de la tarjeta que la
     originó (UX_Suspension_Tarjeta garantiza una sola por tarjeta).
   - Roja directa (color 'R'): una suspensión de 1 partido con idTarjeta = esa
     roja. Una roja directa no pisa ni modifica suspensiones existentes: si
     viene después de una amarilla que completó el ciclo en el mismo partido
     quedan dos filas (total 2 partidos).
   - Doble amarilla (2ª amarilla de la persona en el partido): se genera la
     roja 'Doble amarilla' y una suspensión de 1 partido con idTarjeta = esa
     roja. Si la 1ª amarilla del mismo partido ya había creado una suspensión
     por acumulación, esa fila se absorbe (se le cambia el idTarjeta a la roja):
     la doble amarilla anula la acumulación de ese partido y el total sigue
     siendo 1 partido.
   - Acumulación (amarilla simple): un partido cuenta si la persona tiene al
     menos una amarilla en él y no tiene roja 'Doble amarilla' (las amarillas
     de una doble amarilla se anulan: esa expulsión ya se paga con 1 partido).
     k = partidos que cuentan hasta este (fechaHoraUTC, desempate idPartido).
     Si k es múltiplo de N se crea una suspensión de 1 partido con idTarjeta =
     la amarilla informada. N = AMARILLAS_SUSPENSION para el jugador;
     N = AMARILLAS_SUSPENSION_STAFF para el cuerpo técnico (0 = las amarillas
     del cuerpo técnico no acumulan; no es un error).
   - Cuerpo técnico: solo recibe tarjeta quien figura en
     Eventos.CuerpoTecnicoPartido del partido. Su roja (directa o doble
     amarilla) siempre suspende 1 partido. Para el staff no se exige
     AMARILLAS_SUSPENSION y para el jugador no se lee AMARILLAS_SUSPENSION_STAFF.
   ============================================================================= */

CREATE OR ALTER PROCEDURE Eventos.RegistrarTarjeta
    @idPartido       int,
    @idJugador       int         = NULL,
    @idStaff         int         = NULL,
    @idPeriodo       tinyint,
    @color           char(1),            -- 'A' amarilla, 'R' roja directa
    @minuto          tinyint,
    @minutoAdicional tinyint     = NULL,
    @motivo          varchar(80),
    @idTarjeta       int         = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores              nvarchar(2000) = N'';
    DECLARE @estado               varchar(15),
            @fechaPartido         datetime2(0),
            @personaValida        bit,
            @amarillasSuspension  int,             -- N del jugador
            @amarillasStaff       int,             -- N del cuerpo técnico (0 = no acumula)
            @n                    int,
            @k                    int,
            @idRojaDoble          int;

    SET @motivo    = NULLIF(LTRIM(RTRIM(@motivo)), '');
    SET @color     = UPPER(@color);
    SET @idTarjeta = NULL;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Datos del partido (bloqueado hasta el final de la transacción)
        SELECT @estado       = p.estado,
               @fechaPartido = p.fechaHoraUTC
        FROM Torneo.Partido p WITH (UPDLOCK, HOLDLOCK)
        WHERE p.idPartido = @idPartido;

        -- Exactamente uno de los dos (si no, no se evalúan los chequeos de la persona)
        SET @personaValida = CASE WHEN (@idJugador IS NULL AND @idStaff IS NOT NULL)
                                    OR (@idJugador IS NOT NULL AND @idStaff IS NULL)
                                  THEN 1 ELSE 0 END;

        -- Cada persona se rige por su propio parámetro: el del jugador no se lee
        -- para una tarjeta de staff y viceversa.
        IF @idJugador IS NOT NULL
            SELECT @amarillasSuspension = valor
            FROM Sistema.Parametro
            WHERE clave = 'AMARILLAS_SUSPENSION';

        IF @idStaff IS NOT NULL
            SELECT @amarillasStaff = valor
            FROM Sistema.Parametro
            WHERE clave = 'AMARILLAS_SUSPENSION_STAFF';

        -- T0. Exactamente un jugador o un integrante del cuerpo técnico
        IF @personaValida = 0
            SET @errores += CHAR(10) + N'- Debe especificar exactamente a un jugador o a un integrante del cuerpo técnico, no ambos ni ninguno.';

        -- T1. Existencia del partido
        IF @estado IS NULL
            SET @errores += CHAR(10) + N'- El partido especificado no existe.';

        -- T2. Estado del partido
        IF @estado = 'Programado'
            SET @errores += CHAR(10) + N'- No se pueden registrar tarjetas en un partido que todavía se encuentra en estado programado.';

        -- T3 (jugador). Debe estar en la formación (solo si el partido existe)
        IF @personaValida = 1 AND @idJugador IS NOT NULL AND @estado IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM Eventos.FormacionPartido
                           WHERE idPartido = @idPartido AND idJugador = @idJugador)
            SET @errores += CHAR(10) + N'- El jugador no está registrado en la formación del partido.';

        -- T3 (staff). Debe figurar en el cuerpo técnico del partido (solo si el partido existe)
        IF @personaValida = 1 AND @idStaff IS NOT NULL AND @estado IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM Eventos.CuerpoTecnicoPartido
                           WHERE idPartido = @idPartido AND idStaff = @idStaff)
            SET @errores += CHAR(10) + N'- El integrante del cuerpo técnico no está registrado en el cuerpo técnico del partido.';

        -- T4 (jugador). No puede estar ya expulsado
        IF @personaValida = 1 AND @idJugador IS NOT NULL
           AND EXISTS (SELECT 1
                       FROM Eventos.Tarjeta WITH (UPDLOCK, HOLDLOCK)
                       WHERE idPartido = @idPartido
                         AND idJugador = @idJugador
                         AND color     = 'R')
            SET @errores += CHAR(10) + N'- El jugador ya fue expulsado en este partido.';

        -- T4 (staff). No puede estar ya expulsado
        IF @personaValida = 1 AND @idStaff IS NOT NULL
           AND EXISTS (SELECT 1
                       FROM Eventos.Tarjeta WITH (UPDLOCK, HOLDLOCK)
                       WHERE idPartido = @idPartido
                         AND idStaff   = @idStaff
                         AND color     = 'R')
            SET @errores += CHAR(10) + N'- El integrante del cuerpo técnico ya fue expulsado en este partido.';

        -- T5. Período de juego
        IF @idPeriodo IS NULL OR NOT EXISTS (SELECT 1 FROM Torneo.Periodo WHERE idPeriodo = @idPeriodo)
            SET @errores += CHAR(10) + N'- El período de juego especificado no existe.';

        -- T6. Color
        IF @color IS NULL OR @color NOT IN ('A', 'R')
            SET @errores += CHAR(10) + N'- El color de la tarjeta debe ser A (amarilla) o R (roja).';

        -- T7. Minuto
        IF @minuto IS NULL OR @minuto > 120
            SET @errores += CHAR(10) + N'- El minuto de la tarjeta es obligatorio y debe encontrarse entre 0 y 120.';

        -- T8. Minuto adicional solo en minutos de cierre
        IF @minutoAdicional IS NOT NULL AND @minuto NOT IN (45, 90, 105, 120)
            SET @errores += CHAR(10) + N'- El minuto adicional solo es válido en los minutos de cierre reglamentario (45, 90, 105 o 120).';

        -- T9. Motivo
        IF @motivo IS NULL
            SET @errores += CHAR(10) + N'- El motivo de la tarjeta es obligatorio.';

        -- T10. Parámetro de acumulación de la persona.
        --       Jugador: AMARILLAS_SUSPENSION es obligatorio y mayor que 0.
        --       Staff: AMARILLAS_SUSPENSION_STAFF debe existir; 0 es válido y
        --       significa que sus amarillas no acumulan.
        IF @personaValida = 1 AND @idJugador IS NOT NULL AND ISNULL(@amarillasSuspension, 0) = 0
            SET @errores += CHAR(10) + N'- El parámetro AMARILLAS_SUSPENSION no está configurado en Sistema.Parametro (o vale 0).';

        IF @personaValida = 1 AND @idStaff IS NOT NULL AND @amarillasStaff IS NULL
            SET @errores += CHAR(10) + N'- El parámetro AMARILLAS_SUSPENSION_STAFF no está configurado en Sistema.Parametro.';

        -- THROW único
        IF @errores <> N''
        BEGIN
            SET @errores = N'No se pudo registrar la tarjeta:' + @errores;
            THROW 50002, @errores, 1;
        END;

        -- 1. Tarjeta informada
        INSERT INTO Eventos.Tarjeta (idPartido, idJugador, idStaff, idPeriodo, color, minuto, minutoAdicional, motivo, tipoRoja)
        VALUES (@idPartido, @idJugador, @idStaff, @idPeriodo, @color, @minuto, @minutoAdicional, @motivo,
                CASE WHEN @color = 'R' THEN 'Directa' END);

        SET @idTarjeta = SCOPE_IDENTITY();

        -- 2. Doble amarilla: segunda amarilla del partido => roja 'Doble amarilla'
        --    (la persona informada es @idJugador o @idStaff; el otro es NULL y su
        --    comparación nunca es verdadera)
        IF @color = 'A'
           AND (SELECT COUNT(*) FROM Eventos.Tarjeta
                WHERE idPartido = @idPartido
                  AND (idJugador = @idJugador OR idStaff = @idStaff)
                  AND color = 'A') >= 2
        BEGIN
            INSERT INTO Eventos.Tarjeta (idPartido, idJugador, idStaff, idPeriodo, color, minuto, minutoAdicional, motivo, tipoRoja)
            VALUES (@idPartido, @idJugador, @idStaff, @idPeriodo, 'R', @minuto, @minutoAdicional, 'Doble amarilla', 'Doble amarilla');

            SET @idRojaDoble = SCOPE_IDENTITY();
        END;

        -- 3. Suspensión: una por tarjeta, de 1 partido y con su idTarjeta
        --    (ver las reglas en el encabezado del SP). Nunca se modifica una
        --    suspensión existente salvo la absorción de la doble amarilla (3b).
        IF @color = 'R'
        BEGIN
            -- 3a. Roja directa
            INSERT INTO Eventos.Suspension (idPartido, idJugador, idStaff, cantPartidos, partidosRestantes, idTarjeta)
            VALUES (@idPartido, @idJugador, @idStaff, 1, 1, @idTarjeta);
        END
        ELSE IF @idRojaDoble IS NOT NULL
        BEGIN
            -- 3b. Doble amarilla: si la 1ª amarilla de este partido ya había creado
            --     una suspensión por acumulación, se absorbe (pasa a depender de la
            --     roja generada); si no, se inserta la suspensión de la roja.
            UPDATE su
            SET idTarjeta = @idRojaDoble
            FROM Eventos.Suspension su
            WHERE su.idPartido = @idPartido
              AND (su.idJugador = @idJugador OR su.idStaff = @idStaff)
              AND su.idTarjeta IN (SELECT t.idTarjeta
                                   FROM Eventos.Tarjeta t
                                   WHERE t.idPartido = @idPartido
                                     AND (t.idJugador = @idJugador OR t.idStaff = @idStaff)
                                     AND t.color = 'A');

            IF @@ROWCOUNT = 0
                INSERT INTO Eventos.Suspension (idPartido, idJugador, idStaff, cantPartidos, partidosRestantes, idTarjeta)
                VALUES (@idPartido, @idJugador, @idStaff, 1, 1, @idRojaDoble);
        END
        ELSE
        BEGIN
            -- 3c. Acumulación (amarilla simple). Este partido cuenta (tiene una
            --     amarilla y ninguna doble amarilla). k = partidos que cuentan
            --     hasta este; si k es múltiplo de N se suspende 1 partido.
            SET @n = CASE WHEN @idJugador IS NOT NULL THEN @amarillasSuspension ELSE @amarillasStaff END;

            IF @n > 0
            BEGIN
                SELECT @k = COUNT(*)
                FROM Torneo.Partido px
                WHERE (   px.fechaHoraUTC < @fechaPartido
                       OR (px.fechaHoraUTC = @fechaPartido AND px.idPartido <= @idPartido))
                  AND EXISTS (SELECT 1 FROM Eventos.Tarjeta t
                              WHERE t.idPartido = px.idPartido
                                AND (t.idJugador = @idJugador OR t.idStaff = @idStaff)
                                AND t.color = 'A')
                  AND NOT EXISTS (SELECT 1 FROM Eventos.Tarjeta t
                                  WHERE t.idPartido = px.idPartido
                                    AND (t.idJugador = @idJugador OR t.idStaff = @idStaff)
                                    AND t.color = 'R' AND t.tipoRoja = 'Doble amarilla');

                IF @k % @n = 0
                    INSERT INTO Eventos.Suspension (idPartido, idJugador, idStaff, cantPartidos, partidosRestantes, idTarjeta)
                    VALUES (@idPartido, @idJugador, @idStaff, 1, 1, @idTarjeta);
            END;
        END;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END
GO

/* =============================================================================
   4. Arbitraje.DesignarCuerpoArbitral
   Designa los 5 roles del cuerpo arbitral de un partido programado.

   Advertencia de cruce (no bloquea): si el partido es de una fase con
   orden >= 2, se avisa en @advertencia (y con PRINT) por cada árbitro cuyo
   país tenga una selección en competencia distinta de las dos que juegan.
   - En competencia: la selección tiene al menos un partido en una fase con
     orden >= 2 y no perdió ningún partido 'Finalizado' de esas fases.
   - Perdió: hizo menos goles que el rival; si empataron, hizo menos goles en
     la definición por penales (goles con minuto NULL, atribuidos a la
     selección del autor según Eventos.FormacionPartido). Un empate sin datos
     de penales no elimina a nadie (se prefiere advertir de más).
   ============================================================================= */

CREATE OR ALTER PROCEDURE Arbitraje.DesignarCuerpoArbitral
    @idPartido        int,
    @idPrincipal      int,
    @idAsistente1     int,
    @idAsistente2     int,
    @idCuartoArbitro  int,
    @idVar            int,
    @advertencia      nvarchar(2000) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @errores          nvarchar(2000) = N'';
    DECLARE @estado           varchar(15),
            @ordenFase        int,
            @idSelLocal       int,
            @idSelVisitante   int,
            @idPaisLocal      int,
            @idPaisVisitante  int,
            @lista            nvarchar(2000);

    DECLARE @designacion TABLE (
        orden      tinyint      NOT NULL,
        rol        varchar(15)  NOT NULL,
        idArbitro  int          NULL
    );

    SET @advertencia = NULL;

    INSERT INTO @designacion (orden, rol, idArbitro)
    VALUES (1, 'Principal',      @idPrincipal),
           (2, 'Asistente 1',    @idAsistente1),
           (3, 'Asistente 2',    @idAsistente2),
           (4, 'Cuarto Arbitro', @idCuartoArbitro),
           (5, 'VAR',            @idVar);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Datos del partido (bloqueado hasta el final de la transacción)
        SELECT @estado          = p.estado,
               @ordenFase       = f.orden,
               @idSelLocal      = p.idSeleccionLocal,
               @idSelVisitante  = p.idSeleccionVisitante,
               @idPaisLocal     = sl.idPais,
               @idPaisVisitante = sv.idPais
        FROM Torneo.Partido p WITH (UPDLOCK, HOLDLOCK)
        JOIN Torneo.Fase f        ON f.idFase = p.fase
        JOIN Equipos.Seleccion sl ON sl.id    = p.idSeleccionLocal
        JOIN Equipos.Seleccion sv ON sv.id    = p.idSeleccionVisitante
        WHERE p.idPartido = @idPartido;

        -- D1. Existencia del partido
        IF @estado IS NULL
            SET @errores += CHAR(10) + N'- El partido especificado no existe.';

        -- D2. Solo partidos programados
        IF @estado IS NOT NULL AND @estado <> 'Programado'
            SET @errores += CHAR(10) + N'- Solo se puede designar el cuerpo arbitral de un partido programado.';

        -- D3. El partido no puede tener árbitros designados
        IF EXISTS (SELECT 1
                   FROM Arbitraje.cuerpoArbitral WITH (UPDLOCK, HOLDLOCK)
                   WHERE idPartido = @idPartido)
            SET @errores += CHAR(10) + N'- El partido ya tiene árbitros designados.';

        -- D4. Los 5 roles son obligatorios
        SET @lista = NULL;
        SELECT @lista = STRING_AGG(CAST(d.rol AS nvarchar(15)), N', ') WITHIN GROUP (ORDER BY d.orden)
        FROM @designacion d
        WHERE d.idArbitro IS NULL;

        IF @lista IS NOT NULL
            SET @errores += CHAR(10) + N'- Faltan designar los roles: ' + @lista + N'.';

        -- D5. Existencia de los árbitros informados
        SET @lista = NULL;
        SELECT @lista = STRING_AGG(CAST(x.idArbitro AS nvarchar(12)), N', ') WITHIN GROUP (ORDER BY x.idArbitro)
        FROM (SELECT DISTINCT d.idArbitro
              FROM @designacion d
              WHERE d.idArbitro IS NOT NULL
                AND NOT EXISTS (SELECT 1 FROM Arbitraje.Arbitro a WHERE a.idArbitro = d.idArbitro)) x;

        IF @lista IS NOT NULL
            SET @errores += CHAR(10) + N'- No existen los árbitros con id: ' + @lista + N'.';

        -- D6. Un árbitro, un rol
        IF EXISTS (SELECT 1
                   FROM @designacion
                   WHERE idArbitro IS NOT NULL
                   GROUP BY idArbitro
                   HAVING COUNT(*) > 1)
            SET @errores += CHAR(10) + N'- Un mismo árbitro no puede cumplir más de un rol en el partido.';

        -- D7. Conflicto de nacionalidad: una línea por árbitro en conflicto
        IF @estado IS NOT NULL
        BEGIN
            SET @lista = NULL;
            SELECT @lista = STRING_AGG(CAST(CHAR(10) + N'- El árbitro ' + a.apellido + N', ' + a.nombre
                                            + N' (' + d.rol + N') es de ' + pa.nombre
                                            + N', que disputa el partido.' AS nvarchar(max)), N'')
                            WITHIN GROUP (ORDER BY d.orden)
            FROM @designacion d
            JOIN Arbitraje.Arbitro a ON a.idArbitro = d.idArbitro
            JOIN Torneo.Pais pa      ON pa.id       = a.idPais
            WHERE a.idPais IN (@idPaisLocal, @idPaisVisitante);

            IF @lista IS NOT NULL
                SET @errores += @lista;
        END;

        -- THROW único
        IF @errores <> N''
        BEGIN
            SET @errores = N'No se pudo designar el cuerpo arbitral:' + @errores;
            THROW 50002, @errores, 1;
        END;

        INSERT INTO Arbitraje.cuerpoArbitral (idArbitro, idPartido, rol)
        SELECT d.idArbitro, @idPartido, d.rol
        FROM @designacion d;

        -- Advertencia de cruce (informativa, solo desde la fase de orden 2)
        IF @ordenFase >= 2
        BEGIN
            WITH PartidoEliminatorio AS (
                SELECT p.idPartido, p.idSeleccionLocal, p.idSeleccionVisitante,
                       p.estado, p.golLocal, p.golVisitante
                FROM Torneo.Partido p
                JOIN Torneo.Fase f ON f.idFase = p.fase
                WHERE f.orden >= 2
            ),
            Lado AS (   -- una fila por selección y partido eliminatorio
                SELECT idPartido, idSeleccionLocal AS idSeleccion, idSeleccionVisitante AS idRival,
                       estado, golLocal AS golesPropios, golVisitante AS golesRival
                FROM PartidoEliminatorio
                UNION ALL
                SELECT idPartido, idSeleccionVisitante, idSeleccionLocal,
                       estado, golVisitante, golLocal
                FROM PartidoEliminatorio
            ),
            LadoPenales AS (
                SELECT l.idSeleccion, l.estado, l.golesPropios, l.golesRival,
                       (SELECT COUNT(*)
                        FROM Eventos.Gol g
                        JOIN Eventos.FormacionPartido fp ON fp.idPartido = g.idPartido
                                                        AND fp.idJugador = g.idJugador
                        WHERE g.idPartido = l.idPartido
                          AND g.minuto IS NULL
                          AND fp.idSeleccion = l.idSeleccion) AS penalesPropios,
                       (SELECT COUNT(*)
                        FROM Eventos.Gol g
                        JOIN Eventos.FormacionPartido fp ON fp.idPartido = g.idPartido
                                                        AND fp.idJugador = g.idJugador
                        WHERE g.idPartido = l.idPartido
                          AND g.minuto IS NULL
                          AND fp.idSeleccion = l.idRival) AS penalesRival
                FROM Lado l
            ),
            Eliminada AS (
                SELECT DISTINCT idSeleccion
                FROM LadoPenales
                WHERE estado = 'Finalizado'
                  AND (   golesPropios < golesRival
                       OR (golesPropios = golesRival AND penalesPropios < penalesRival))
            ),
            EnCompetencia AS (
                SELECT DISTINCT l.idSeleccion
                FROM Lado l
                WHERE NOT EXISTS (SELECT 1 FROM Eliminada e WHERE e.idSeleccion = l.idSeleccion)
            )
            SELECT @advertencia = STRING_AGG(CAST(N'Advertencia: el árbitro ' + a.apellido + N', ' + a.nombre
                                                  + N' (' + d.rol + N') es de ' + pa.nombre
                                                  + N', cuya selección sigue en competencia y podría cruzarse con las selecciones de este partido.'
                                                  AS nvarchar(max)), CHAR(10))
                                  WITHIN GROUP (ORDER BY d.orden)
            FROM @designacion d
            JOIN Arbitraje.Arbitro a  ON a.idArbitro = d.idArbitro
            JOIN Torneo.Pais pa       ON pa.id       = a.idPais
            JOIN Equipos.Seleccion s  ON s.idPais    = a.idPais
            JOIN EnCompetencia ec     ON ec.idSeleccion = s.id
            WHERE s.id NOT IN (@idSelLocal, @idSelVisitante);
        END;

        COMMIT TRANSACTION;

        IF @advertencia IS NOT NULL
            PRINT @advertencia;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END
GO
