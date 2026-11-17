/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 15/11/2026

 Objetivo    : ABM de Eventos.CuerpoTecnicoPartido (qué integrantes del cuerpo
               técnico figuran en cada partido). Procedimientos de Alta, Baja
               y Modificación (reemplazo de un integrante por otro).

 Estándares aplicados:
 - Acumulación exhaustiva de errores en @errores nvarchar(2000).
 - Un solo THROW 50001 al final de las validaciones informando todos los fallos.
 - Nombres en formato Esquema.Tabla_Accion.
 - Modificación de datos sólo tras validar con éxito todas las precondiciones.
 - Parámetros y variables locales estrictamente en @camelCase.
 - Cero uso de SQL dinámico o CLR.

 Decisiones de diseño:
 - Suspensión activa para el partido P: fila en Eventos.Suspension con
   partidosRestantes > 0 generada en un partido anterior a P (fechaHoraUTC).
   Misma definición que Eventos.RegistrarFormacion.
 - Como la formación, el cuerpo técnico se carga mientras el partido está
   Programado: con el partido en juego o finalizado no se agrega, quita ni
   reemplaza a nadie.
 - Una selección tiene como máximo un Director Principal por partido.
 - No se quita ni reemplaza a un integrante que ya registra tarjetas en el
   partido (las tarjetas de staff exigen figurar en el cuerpo técnico).
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

/* =============================================================================
   TABLA: Eventos.CuerpoTecnicoPartido
   ============================================================================= */

-- 1. ALTA DE INTEGRANTE EN EL CUERPO TÉCNICO DEL PARTIDO
CREATE OR ALTER PROCEDURE Eventos.CuerpoTecnicoPartido_Alta
    @idPartido int,
    @idStaff   int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    DECLARE @existePartido bit = 0;
    DECLARE @existeStaff   bit = 0;

    IF @idPartido IS NOT NULL AND EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido)
        SET @existePartido = 1;

    IF @idStaff IS NOT NULL AND EXISTS (SELECT 1 FROM Equipos.Staff WHERE id = @idStaff)
        SET @existeStaff = 1;

    -- Existencia de partido y de integrante
    IF @existePartido = 0
        SET @errores += CHAR(10) + N'- El partido especificado no existe.';

    IF @existeStaff = 0
        SET @errores += CHAR(10) + N'- El integrante del cuerpo técnico especificado no existe.';

    -- Coherencia: el integrante debe pertenecer a una de las dos selecciones del partido
    IF @existePartido = 1 AND @existeStaff = 1
       AND NOT EXISTS (
           SELECT 1
           FROM Equipos.Staff st
           JOIN Torneo.Partido p ON p.idPartido = @idPartido
           WHERE st.id = @idStaff
             AND (st.idSeleccion = p.idSeleccionLocal OR st.idSeleccion = p.idSeleccionVisitante)
       )
        SET @errores += CHAR(10) + N'- El integrante del cuerpo técnico no pertenece a ninguna de las selecciones que disputan el partido.';

    -- Estado del partido (no permitir si ya finalizó o está en juego)
    IF EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido AND estado IN ('Finalizado', 'En juego'))
        SET @errores += CHAR(10) + N'- No se pueden agregar integrantes al cuerpo técnico de un partido ya finalizado o que se encuentra en juego.';

    -- Unicidad (PK_CuerpoTecnicoPartido)
    IF EXISTS (SELECT 1 FROM Eventos.CuerpoTecnicoPartido WHERE idPartido = @idPartido AND idStaff = @idStaff)
        SET @errores += CHAR(10) + N'- El integrante ya figura en el cuerpo técnico de este partido.';

    -- Suspensión activa para este partido
    IF @existePartido = 1 AND @existeStaff = 1
       AND EXISTS (
           SELECT 1
           FROM Eventos.Suspension su
           JOIN Torneo.Partido ps ON ps.idPartido = su.idPartido
           JOIN Torneo.Partido pa ON pa.idPartido = @idPartido
           WHERE su.idStaff = @idStaff
             AND su.partidosRestantes > 0
             AND ps.fechaHoraUTC < pa.fechaHoraUTC
       )
        SET @errores += CHAR(10) + N'- El integrante del cuerpo técnico está suspendido y no puede figurar en el partido.';

    -- Un solo Director Principal por selección en el partido
    IF @existePartido = 1 AND @existeStaff = 1
       AND EXISTS (SELECT 1 FROM Equipos.Staff WHERE id = @idStaff AND rol = 'Director Principal')
       AND EXISTS (
           SELECT 1
           FROM Equipos.Staff st
           JOIN Equipos.Staff otro ON otro.idSeleccion = st.idSeleccion
                                  AND otro.rol = 'Director Principal'
                                  AND otro.id <> st.id
           JOIN Eventos.CuerpoTecnicoPartido ctp ON ctp.idStaff = otro.id
                                                AND ctp.idPartido = @idPartido
           WHERE st.id = @idStaff
       )
        SET @errores += CHAR(10) + N'- La selección ya tiene otro director principal en el cuerpo técnico de este partido.';

    -- THROW único
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo registrar el integrante en el cuerpo técnico del partido:' + @errores;
        THROW 50001, @errores, 1;
    END;

    INSERT INTO Eventos.CuerpoTecnicoPartido (idPartido, idStaff)
    VALUES (@idPartido, @idStaff);
END
GO

-- 2. BAJA DE INTEGRANTE DEL CUERPO TÉCNICO DEL PARTIDO
CREATE OR ALTER PROCEDURE Eventos.CuerpoTecnicoPartido_Baja
    @idPartido int,
    @idStaff   int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    -- Existencia del registro; el resto de las reglas solo aplica si figura
    IF NOT EXISTS (SELECT 1 FROM Eventos.CuerpoTecnicoPartido WHERE idPartido = @idPartido AND idStaff = @idStaff)
        SET @errores += CHAR(10) + N'- El integrante no figura en el cuerpo técnico de este partido.';
    ELSE
    BEGIN
        -- Estado del partido
        IF EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido AND estado IN ('Finalizado', 'En juego'))
            SET @errores += CHAR(10) + N'- No se puede eliminar a un integrante del cuerpo técnico de un partido ya finalizado o en juego.';

        -- Integridad referencial: tarjetas
        IF EXISTS (SELECT 1 FROM Eventos.Tarjeta WHERE idPartido = @idPartido AND idStaff = @idStaff)
            SET @errores += CHAR(10) + N'- No se puede eliminar al integrante del cuerpo técnico porque registra tarjetas en este partido.';
    END;

    -- THROW único
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de baja al integrante del cuerpo técnico del partido:' + @errores;
        THROW 50001, @errores, 1;
    END;

    DELETE FROM Eventos.CuerpoTecnicoPartido
    WHERE idPartido = @idPartido AND idStaff = @idStaff;
END
GO

-- 3. MODIFICACIÓN: REEMPLAZO DE UN INTEGRANTE POR OTRO EN EL PARTIDO
CREATE OR ALTER PROCEDURE Eventos.CuerpoTecnicoPartido_Modificacion
    @idPartido      int,
    @idStaffActual  int,
    @idStaffNuevo   int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';
    DECLARE @existePartido bit = 0;
    DECLARE @figuraActual  bit = 0;
    DECLARE @existeNuevo   bit = 0;

    IF @idPartido IS NOT NULL AND EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido)
        SET @existePartido = 1;

    IF EXISTS (SELECT 1 FROM Eventos.CuerpoTecnicoPartido WHERE idPartido = @idPartido AND idStaff = @idStaffActual)
        SET @figuraActual = 1;

    IF @idStaffNuevo IS NOT NULL AND EXISTS (SELECT 1 FROM Equipos.Staff WHERE id = @idStaffNuevo)
        SET @existeNuevo = 1;

    -- Existencia del partido y del integrante actual (si el partido no existe, el actual no puede figurar)
    IF @existePartido = 0
        SET @errores += CHAR(10) + N'- El partido especificado no existe.';
    ELSE IF @figuraActual = 0
        SET @errores += CHAR(10) + N'- El integrante actual no figura en el cuerpo técnico de este partido.';

    -- Existencia del nuevo integrante
    IF @existeNuevo = 0
        SET @errores += CHAR(10) + N'- El nuevo integrante del cuerpo técnico especificado no existe.';

    -- El reemplazo debe ser un integrante distinto
    IF @idStaffActual IS NOT NULL AND @idStaffNuevo IS NOT NULL AND @idStaffActual = @idStaffNuevo
        SET @errores += CHAR(10) + N'- El nuevo integrante no puede ser idéntico al actual.';

    -- Coherencia: el nuevo debe pertenecer a una de las dos selecciones del partido
    IF @existePartido = 1 AND @existeNuevo = 1
       AND NOT EXISTS (
           SELECT 1
           FROM Equipos.Staff st
           JOIN Torneo.Partido p ON p.idPartido = @idPartido
           WHERE st.id = @idStaffNuevo
             AND (st.idSeleccion = p.idSeleccionLocal OR st.idSeleccion = p.idSeleccionVisitante)
       )
        SET @errores += CHAR(10) + N'- El nuevo integrante del cuerpo técnico no pertenece a ninguna de las selecciones que disputan el partido.';

    -- Unicidad del nuevo en el partido (si es el mismo que el actual ya se informó arriba)
    IF @existeNuevo = 1 AND (@idStaffActual IS NULL OR @idStaffActual <> @idStaffNuevo)
       AND EXISTS (SELECT 1 FROM Eventos.CuerpoTecnicoPartido WHERE idPartido = @idPartido AND idStaff = @idStaffNuevo)
        SET @errores += CHAR(10) + N'- El nuevo integrante ya figura en el cuerpo técnico de este partido.';

    -- Suspensión activa del nuevo para este partido
    IF @existePartido = 1 AND @existeNuevo = 1
       AND EXISTS (
           SELECT 1
           FROM Eventos.Suspension su
           JOIN Torneo.Partido ps ON ps.idPartido = su.idPartido
           JOIN Torneo.Partido pa ON pa.idPartido = @idPartido
           WHERE su.idStaff = @idStaffNuevo
             AND su.partidosRestantes > 0
             AND ps.fechaHoraUTC < pa.fechaHoraUTC
       )
        SET @errores += CHAR(10) + N'- El nuevo integrante del cuerpo técnico está suspendido y no puede figurar en el partido.';

    -- Un solo Director Principal por selección (se excluye al actual, que será reemplazado)
    IF @existePartido = 1 AND @existeNuevo = 1
       AND EXISTS (SELECT 1 FROM Equipos.Staff WHERE id = @idStaffNuevo AND rol = 'Director Principal')
       AND EXISTS (
           SELECT 1
           FROM Equipos.Staff st
           JOIN Equipos.Staff otro ON otro.idSeleccion = st.idSeleccion
                                  AND otro.rol = 'Director Principal'
                                  AND otro.id <> st.id
                                  AND (@idStaffActual IS NULL OR otro.id <> @idStaffActual)
           JOIN Eventos.CuerpoTecnicoPartido ctp ON ctp.idStaff = otro.id
                                                AND ctp.idPartido = @idPartido
           WHERE st.id = @idStaffNuevo
       )
        SET @errores += CHAR(10) + N'- La selección ya tiene otro director principal en el cuerpo técnico de este partido.';

    -- Estado del partido
    IF EXISTS (SELECT 1 FROM Torneo.Partido WHERE idPartido = @idPartido AND estado IN ('Finalizado', 'En juego'))
        SET @errores += CHAR(10) + N'- No se puede modificar el cuerpo técnico de un partido ya finalizado o que se encuentra en juego.';

    -- Integridad referencial: tarjetas del integrante actual
    IF @figuraActual = 1
       AND EXISTS (SELECT 1 FROM Eventos.Tarjeta WHERE idPartido = @idPartido AND idStaff = @idStaffActual)
        SET @errores += CHAR(10) + N'- No se puede reemplazar al integrante actual porque registra tarjetas en este partido.';

    -- THROW único
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo modificar el cuerpo técnico del partido:' + @errores;
        THROW 50001, @errores, 1;
    END;

    UPDATE Eventos.CuerpoTecnicoPartido
    SET idStaff = @idStaffNuevo
    WHERE idPartido = @idPartido AND idStaff = @idStaffActual;
END
GO
