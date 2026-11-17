/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 15/11/2026

 Objetivo    : Carga de datos de Persona 2 (parte 1 de 3): reglas del
               reglamento en Sistema.Parametro y plantel de árbitros con sus
               idiomas.
               - Parámetros que leen los SP de 21: AMARILLAS_SUSPENSION,
                 AMARILLAS_SUSPENSION_STAFF (amarillas del cuerpo técnico que
                 generan una suspensión; 0 = no acumulan), MAX_CAMBIOS,
                 MAX_VENTANAS, CAMBIO_EXTRA_ALARGUE y MAX_SUPLENTES.
               - 20 árbitros FIFA FICTICIOS (los nombres son inventados), de 17
                 de los 19 países cargados en 50a (faltan Cabo Verde e Irak):
                 6 de los anfitriones (México, Estados Unidos y Canadá, siempre
                 elegibles porque no tienen selección en esta carga) y 14 de
                 otros tantos países con selección. Así cada uno de los 31
                 partidos tiene al menos 18 árbitros sin
                 conflicto de nacionalidad y existen árbitros de países con
                 selección para los casos de rechazo y la advertencia de cruce
                 de 51b.

 Uso         : Se ejecuta después de 50 (países) y antes de 51b. Las altas de
               árbitros e idiomas pasan por los SP del ABM (11a). Cada alta
               verifica antes si el registro ya existe: el script se puede
               ejecutar varias veces sin duplicar datos ni pisar valores de
               parámetros que se hayan cambiado a mano.
================================================================================
*/

USE MundialFutbol;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

SET NOCOUNT ON;
GO

/* =============================================================================
   1. PARÁMETROS DEL REGLAMENTO
   Sistema.Parametro es compartida y no tiene SP de ABM (igual que en
   50d_Carga_Parametros.sql), así que se cargan con un INSERT que solo agrega
   las claves que faltan.
   ============================================================================= */
INSERT INTO Sistema.Parametro (clave, valor, descripcion)
SELECT nuevo.clave, nuevo.valor, nuevo.descripcion
FROM (VALUES
    ('AMARILLAS_SUSPENSION',   2,  'Amarillas en partidos distintos que generan una suspensión de un partido'),
    ('AMARILLAS_SUSPENSION_STAFF', 2, 'Amarillas del cuerpo técnico en partidos distintos que generan una suspensión de un partido (0 = no acumulan)'),
    ('MAX_CAMBIOS',            5,  'Máximo de cambios por selección en los 90 minutos'),
    ('MAX_VENTANAS',           3,  'Máximo de ventanas (instantes distintos) de cambios por selección en los 90 minutos'),
    ('CAMBIO_EXTRA_ALARGUE',   1,  'Cambios extra (y una ventana más) que se habilitan en el alargue'),
    ('MAX_SUPLENTES',          15, 'Máximo de suplentes por selección en la formación de un partido')
) AS nuevo (clave, valor, descripcion)
WHERE NOT EXISTS (SELECT 1 FROM Sistema.Parametro p WHERE p.clave = nuevo.clave);
GO

/* =============================================================================
   2. ÁRBITROS (todos categoría FIFA) E IDIOMAS
   Se identifican por nombre + apellido + país (la misma regla de unicidad que
   Arbitraje.Arbitro_Alta). Los países se buscan por código ISO3.
   ============================================================================= */
DROP TABLE IF EXISTS #arbitros;
CREATE TABLE #arbitros (n int IDENTITY(1,1) PRIMARY KEY, nombre nvarchar(60), apellido nvarchar(60),
                        pais char(3), genero varchar(20), fechaInternacional date);
INSERT INTO #arbitros (nombre, apellido, pais, genero, fechaInternacional) VALUES
    -- Anfitriones: nunca tienen conflicto de nacionalidad
    (N'Héctor',   N'Villaseñor',    'MEX', 'Masculino', '2012-02-14'),
    (N'Daniela',  N'Montoya',       'MEX', 'Femenino',  '2017-09-03'),
    (N'Michael',  N'Thornton',      'USA', 'Masculino', '2013-05-21'),
    (N'Laura',    N'Whitfield',     'USA', 'Femenino',  '2018-07-09'),
    (N'Étienne',  N'Beaulieu',      'CAN', 'Masculino', '2015-03-30'),
    (N'Sarah',    N'McAllister',    'CAN', 'Femenino',  '2019-01-18'),
    -- Países con selección en esta carga
    (N'Gustavo',  N'Ferreyra',      'ARG', 'Masculino', '2011-08-05'),
    (N'Álvaro',   N'Quintero',      'ESP', 'Masculino', '2014-11-12'),
    (N'Julien',   N'Marchetti',     'FRA', 'Masculino', '2016-04-27'),
    (N'Oliver',   N'Hargreaves',    'GBR', 'Masculino', '2012-10-08'),
    (N'Federico', N'Zubiaurre',     'URY', 'Masculino', '2015-06-16'),
    (N'Henrik',   N'Solberg',       'NOR', 'Masculino', '2017-02-23'),
    (N'Faisal',   N'Al-Mutairi',    'SAU', 'Masculino', '2016-12-01'),
    (N'Mamadou',  N'Ndiaye',        'SEN', 'Masculino', '2014-09-15'),
    (N'Marko',    N'Kovačević',     'HRV', 'Masculino', '2013-07-19'),
    (N'Kwame',    N'Boateng',       'GHA', 'Masculino', '2018-03-11'),
    (N'Samira',   N'Haddad',        'JOR', 'Femenino',  '2019-10-06'),
    (N'Lukas',    N'Brandstätter',  'AUT', 'Masculino', '2015-11-24'),
    (N'Karim',    N'Benali',        'DZA', 'Masculino', '2014-01-28'),
    (N'Valeria',  N'Mendieta',      'PAN', 'Femenino',  '2017-05-17');

DROP TABLE IF EXISTS #idiomas;
CREATE TABLE #idiomas (n int IDENTITY(1,1) PRIMARY KEY, apellido nvarchar(60), pais char(3), idioma varchar(10));
INSERT INTO #idiomas (apellido, pais, idioma) VALUES
    (N'Villaseñor', 'MEX', 'es'), (N'Villaseñor', 'MEX', 'en'),
    (N'Montoya', 'MEX', 'es'), (N'Montoya', 'MEX', 'en'), (N'Montoya', 'MEX', 'pt'),
    (N'Thornton', 'USA', 'en'), (N'Thornton', 'USA', 'es'),
    (N'Whitfield', 'USA', 'en'),
    (N'Beaulieu', 'CAN', 'fr'), (N'Beaulieu', 'CAN', 'en'),
    (N'McAllister', 'CAN', 'en'), (N'McAllister', 'CAN', 'fr'),
    (N'Ferreyra', 'ARG', 'es'), (N'Ferreyra', 'ARG', 'pt'),
    (N'Quintero', 'ESP', 'es'), (N'Quintero', 'ESP', 'en'),
    (N'Marchetti', 'FRA', 'fr'), (N'Marchetti', 'FRA', 'en'),
    (N'Hargreaves', 'GBR', 'en'),
    (N'Zubiaurre', 'URY', 'es'), (N'Zubiaurre', 'URY', 'pt'),
    (N'Solberg', 'NOR', 'en'), (N'Solberg', 'NOR', 'de'),
    (N'Al-Mutairi', 'SAU', 'ar'), (N'Al-Mutairi', 'SAU', 'en'),
    (N'Ndiaye', 'SEN', 'fr'), (N'Ndiaye', 'SEN', 'en'), (N'Ndiaye', 'SEN', 'ar'),
    (N'Kovačević', 'HRV', 'en'), (N'Kovačević', 'HRV', 'de'),
    (N'Boateng', 'GHA', 'en'),
    (N'Haddad', 'JOR', 'ar'), (N'Haddad', 'JOR', 'en'),
    (N'Brandstätter', 'AUT', 'de'), (N'Brandstätter', 'AUT', 'en'),
    (N'Benali', 'DZA', 'ar'), (N'Benali', 'DZA', 'fr'),
    (N'Mendieta', 'PAN', 'es'), (N'Mendieta', 'PAN', 'en');

DECLARE @nombre nvarchar(60), @apellido nvarchar(60), @genero varchar(20), @fecha date,
        @idPais int, @idArbitro int;
DECLARE @n int = 1, @max int = (SELECT MAX(n) FROM #arbitros);
WHILE @n <= @max
BEGIN
    SELECT @idPais = NULL, @idArbitro = NULL;
    SELECT @nombre = a.nombre, @apellido = a.apellido, @genero = a.genero,
           @fecha = a.fechaInternacional, @idPais = p.id
    FROM #arbitros a
    LEFT JOIN Torneo.Pais p ON p.codigoISO3 = a.pais
    WHERE a.n = @n;
    BEGIN TRY
        IF @idPais IS NULL
            THROW 50001, N'El país del árbitro no existe en Torneo.Pais.', 1;
        IF NOT EXISTS (SELECT 1 FROM Arbitraje.Arbitro
                       WHERE idPais = @idPais AND nombre = @nombre AND apellido = @apellido)
            EXEC Arbitraje.Arbitro_Alta @idPais = @idPais, @nombre = @nombre, @apellido = @apellido,
                 @categoria = 'FIFA', @genero = @genero, @fechaInternacional = @fecha,
                 @idArbitro = @idArbitro OUTPUT;
    END TRY
    BEGIN CATCH
        PRINT 'Error al cargar el árbitro de la fila ' + CAST(@n AS varchar(10)) + ' de #arbitros.';
        THROW;
    END CATCH;
    SET @n += 1;
END;

DECLARE @idioma varchar(10);
SELECT @n = 1, @max = (SELECT MAX(n) FROM #idiomas);
WHILE @n <= @max
BEGIN
    SELECT @idArbitro = NULL;
    SELECT @idArbitro = a.idArbitro, @idioma = i.idioma
    FROM #idiomas i
    JOIN Torneo.Pais p ON p.codigoISO3 = i.pais
    JOIN Arbitraje.Arbitro a ON a.idPais = p.id AND a.apellido = i.apellido
    WHERE i.n = @n;
    BEGIN TRY
        IF @idArbitro IS NULL
            THROW 50001, N'No se encontró el árbitro al que pertenece el idioma.', 1;
        IF NOT EXISTS (SELECT 1 FROM Arbitraje.ArbitroIdioma WHERE idArbitro = @idArbitro AND idioma = @idioma)
            EXEC Arbitraje.ArbitroIdioma_Alta @idArbitro = @idArbitro, @idioma = @idioma;
    END TRY
    BEGIN CATCH
        PRINT 'Error al cargar el idioma de la fila ' + CAST(@n AS varchar(10)) + ' de #idiomas.';
        THROW;
    END CATCH;
    SET @n += 1;
END;
GO

/* =============================================================================
   RESUMEN DE LA CARGA
   ============================================================================= */
SELECT clave, valor, descripcion
FROM Sistema.Parametro
WHERE clave IN ('AMARILLAS_SUSPENSION', 'AMARILLAS_SUSPENSION_STAFF', 'MAX_CAMBIOS', 'MAX_VENTANAS', 'CAMBIO_EXTRA_ALARGUE', 'MAX_SUPLENTES')
ORDER BY clave;

SELECT COUNT(*) AS arbitros,
       (SELECT COUNT(*) FROM Arbitraje.ArbitroIdioma) AS idiomasCargados,
       (SELECT COUNT(DISTINCT idPais) FROM Arbitraje.Arbitro) AS paises
FROM Arbitraje.Arbitro;

SELECT pa.nombre AS pais,
       CASE WHEN EXISTS (SELECT 1 FROM Equipos.Seleccion s WHERE s.idPais = pa.id)
            THEN 'Con seleccion' ELSE 'Anfitrion sin seleccion' END AS tipoPais,
       a.apellido + N', ' + a.nombre AS arbitro, a.categoria, a.genero, a.fechaInternacional,
       (SELECT STRING_AGG(ai.idioma, ',') WITHIN GROUP (ORDER BY ai.idioma)
        FROM Arbitraje.ArbitroIdioma ai WHERE ai.idArbitro = a.idArbitro) AS idiomas
FROM Arbitraje.Arbitro a
JOIN Torneo.Pais pa ON pa.id = a.idPais
ORDER BY pa.nombre, a.apellido;
GO
