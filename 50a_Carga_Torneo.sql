/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 09/11/2026

 Objetivo    : Carga base del torneo: países, fases, períodos y las 16 sedes
               del Mundial 2026.

 Fuente      : Copa Mundial de la FIFA 2026 (datos reales). Wikipedia en inglés,
               artículos del torneo, de los grupos H, I, J y L, de la fase
               eliminatoria, de los planteles y de cada selección (versión al
               15/06/2026 para los cuerpos técnicos), consultados el 09/11/2026.

 Uso         : Todas las altas pasan por los SP del ABM (10a/10b). Cada alta
               verifica antes si el registro ya existe, así que el script se
               puede ejecutar varias veces sin duplicar datos.
================================================================================
*/

USE MundialFutbol;
GO

SET NOCOUNT ON;
GO

/* =============================================================================
   PAÍSES: las 16 selecciones cargadas y los 3 anfitriones (dueños de las sedes).
   PBI per cápita y población quedan NULL: los completa la API del Banco
   Mundial (E6). Inglaterra usa los códigos ISO del Reino Unido (GB/GBR):
   ISO 3166 no asigna códigos propios a las naciones que lo componen.
   ============================================================================= */
DROP TABLE IF EXISTS #paises;
CREATE TABLE #paises (n int IDENTITY(1,1) PRIMARY KEY, nombre nvarchar(60), codigoISO2 char(2),
                      codigoISO3 char(3), husoHorario varchar(50), moneda char(3));
INSERT INTO #paises (nombre, codigoISO2, codigoISO3, husoHorario, moneda) VALUES
    (N'España', N'ES', N'ESP', N'Romance Standard Time', N'EUR'),
    (N'Cabo Verde', N'CV', N'CPV', N'Cape Verde Standard Time', N'CVE'),
    (N'Uruguay', N'UY', N'URY', N'Montevideo Standard Time', N'UYU'),
    (N'Arabia Saudita', N'SA', N'SAU', N'Arab Standard Time', N'SAR'),
    (N'Francia', N'FR', N'FRA', N'Romance Standard Time', N'EUR'),
    (N'Noruega', N'NO', N'NOR', N'W. Europe Standard Time', N'NOK'),
    (N'Senegal', N'SN', N'SEN', N'Greenwich Standard Time', N'XOF'),
    (N'Irak', N'IQ', N'IRQ', N'Arabic Standard Time', N'IQD'),
    (N'Argentina', N'AR', N'ARG', N'Argentina Standard Time', N'ARS'),
    (N'Austria', N'AT', N'AUT', N'W. Europe Standard Time', N'EUR'),
    (N'Argelia', N'DZ', N'DZA', N'W. Central Africa Standard Time', N'DZD'),
    (N'Jordania', N'JO', N'JOR', N'Jordan Standard Time', N'JOD'),
    (N'Inglaterra', N'GB', N'GBR', N'GMT Standard Time', N'GBP'),
    (N'Croacia', N'HR', N'HRV', N'Central European Standard Time', N'EUR'),
    (N'Ghana', N'GH', N'GHA', N'Greenwich Standard Time', N'GHS'),
    (N'Panamá', N'PA', N'PAN', N'SA Pacific Standard Time', N'PAB'),
    (N'Estados Unidos', N'US', N'USA', N'Eastern Standard Time', N'USD'),
    (N'México', N'MX', N'MEX', N'Central Standard Time (Mexico)', N'MXN'),
    (N'Canadá', N'CA', N'CAN', N'Eastern Standard Time', N'CAD');

DECLARE @nombre nvarchar(60), @iso2 char(2), @iso3 char(3), @huso varchar(50), @moneda char(3);
DECLARE @n int = 1, @max int = (SELECT MAX(n) FROM #paises);
WHILE @n <= @max
BEGIN
    SELECT @nombre = nombre, @iso2 = codigoISO2, @iso3 = codigoISO3, @huso = husoHorario, @moneda = moneda FROM #paises WHERE n = @n;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM Torneo.Pais WHERE codigoISO3 = @iso3)
            EXEC Torneo.Pais_Alta @nombre = @nombre, @codigoISO2 = @iso2, @codigoISO3 = @iso3,
                 @husoHorario = @huso, @moneda = @moneda;
    END TRY
    BEGIN CATCH
        PRINT 'Error al cargar el país de la fila ' + CAST(@n AS varchar(10)) + ' de #paises.';
        THROW;
    END CATCH;
    SET @n += 1;
END;
GO

/* FASES (catálogo). En 2026 hubo dieciseisavos por el formato de 48 selecciones. */
IF NOT EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = 1) EXEC Torneo.Fase_Alta @idFase = 1, @nombre = N'Fase de grupos', @esEliminatoria = 0, @orden = 1;
IF NOT EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = 2) EXEC Torneo.Fase_Alta @idFase = 2, @nombre = N'Dieciseisavos de final', @esEliminatoria = 1, @orden = 2;
IF NOT EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = 3) EXEC Torneo.Fase_Alta @idFase = 3, @nombre = N'Octavos de final', @esEliminatoria = 1, @orden = 3;
IF NOT EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = 4) EXEC Torneo.Fase_Alta @idFase = 4, @nombre = N'Cuartos de final', @esEliminatoria = 1, @orden = 4;
IF NOT EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = 5) EXEC Torneo.Fase_Alta @idFase = 5, @nombre = N'Semifinal', @esEliminatoria = 1, @orden = 5;
IF NOT EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = 6) EXEC Torneo.Fase_Alta @idFase = 6, @nombre = N'Tercer puesto', @esEliminatoria = 1, @orden = 6;
IF NOT EXISTS (SELECT 1 FROM Torneo.Fase WHERE idFase = 7) EXEC Torneo.Fase_Alta @idFase = 7, @nombre = N'Final', @esEliminatoria = 1, @orden = 7;
GO

/* PERÍODOS (catálogo). El tiempo adicionado se registra en minutoAdicional, no como período. */
IF NOT EXISTS (SELECT 1 FROM Torneo.Periodo WHERE idPeriodo = 1) EXEC Torneo.Periodo_Alta @idPeriodo = 1, @nombre = N'Primer tiempo', @orden = 1;
IF NOT EXISTS (SELECT 1 FROM Torneo.Periodo WHERE idPeriodo = 2) EXEC Torneo.Periodo_Alta @idPeriodo = 2, @nombre = N'Segundo tiempo', @orden = 2;
IF NOT EXISTS (SELECT 1 FROM Torneo.Periodo WHERE idPeriodo = 3) EXEC Torneo.Periodo_Alta @idPeriodo = 3, @nombre = N'Primer tiempo suplementario', @orden = 3;
IF NOT EXISTS (SELECT 1 FROM Torneo.Periodo WHERE idPeriodo = 4) EXEC Torneo.Periodo_Alta @idPeriodo = 4, @nombre = N'Segundo tiempo suplementario', @orden = 4;
IF NOT EXISTS (SELECT 1 FROM Torneo.Periodo WHERE idPeriodo = 5) EXEC Torneo.Periodo_Alta @idPeriodo = 5, @nombre = N'Definición por penales', @orden = 5;
GO

/* =============================================================================
   SEDES: las 16 del torneo, con la capacidad publicada por la FIFA y 4 husos
   horarios distintos (Eastern, Central, Pacific y Central de México).
   ============================================================================= */
DROP TABLE IF EXISTS #sedes;
CREATE TABLE #sedes (n int IDENTITY(1,1) PRIMARY KEY, nombreEstadio nvarchar(80), ciudad nvarchar(60),
                     pais char(3), husoHorario varchar(50), capacidad int, latitud decimal(9,6), longitud decimal(9,6));
INSERT INTO #sedes (nombreEstadio, ciudad, pais, husoHorario, capacidad, latitud, longitud) VALUES
    (N'Estadio Azteca', N'Ciudad de México', N'MEX', N'Central Standard Time (Mexico)', 80824, 19.303, -99.1505),
    (N'MetLife Stadium', N'East Rutherford', N'USA', N'Eastern Standard Time', 80663, 40.813611, -74.074444),
    (N'AT&T Stadium', N'Arlington', N'USA', N'Central Standard Time', 70649, 32.747778, -97.092778),
    (N'SoFi Stadium', N'Inglewood', N'USA', N'Pacific Standard Time', 70492, 33.953, -118.339),
    (N'Arrowhead Stadium', N'Kansas City', N'USA', N'Central Standard Time', 69045, 39.048889, -94.483889),
    (N'Levi''s Stadium', N'Santa Clara', N'USA', N'Pacific Standard Time', 68827, 37.403, -121.97),
    (N'NRG Stadium', N'Houston', N'USA', N'Central Standard Time', 68777, 29.684722, -95.410833),
    (N'Lincoln Financial Field', N'Philadelphia', N'USA', N'Eastern Standard Time', 68324, 39.900833, -75.1675),
    (N'Mercedes-Benz Stadium', N'Atlanta', N'USA', N'Eastern Standard Time', 68239, 33.755556, -84.4),
    (N'Lumen Field', N'Seattle', N'USA', N'Pacific Standard Time', 66925, 47.5952, -122.3316),
    (N'Hard Rock Stadium', N'Miami Gardens', N'USA', N'Eastern Standard Time', 64478, 25.958056, -80.238889),
    (N'Gillette Stadium', N'Foxborough', N'USA', N'Eastern Standard Time', 64146, 42.091, -71.264),
    (N'BC Place', N'Vancouver', N'CAN', N'Pacific Standard Time', 52497, 49.276667, -123.111944),
    (N'Estadio BBVA', N'Guadalupe', N'MEX', N'Central Standard Time (Mexico)', 51243, 25.669167, -100.244444),
    (N'Estadio Akron', N'Zapopan', N'MEX', N'Central Standard Time (Mexico)', 45664, 20.681667, -103.462778),
    (N'BMO Field', N'Toronto', N'CAN', N'Eastern Standard Time', 43036, 43.633333, -79.418611);

DECLARE @estadio nvarchar(80), @ciudad nvarchar(60), @idPais int, @huso varchar(50),
        @capacidad int, @latitud decimal(9,6), @longitud decimal(9,6);
DECLARE @n int = 1, @max int = (SELECT MAX(n) FROM #sedes);
WHILE @n <= @max
BEGIN
    SET @idPais = NULL;
    SELECT @estadio = s.nombreEstadio, @ciudad = s.ciudad, @idPais = p.id, @huso = s.husoHorario,
           @capacidad = s.capacidad, @latitud = s.latitud, @longitud = s.longitud
    FROM #sedes s JOIN Torneo.Pais p ON p.codigoISO3 = s.pais WHERE s.n = @n;
    BEGIN TRY
        IF @idPais IS NULL
            THROW 50001, N'El país de la sede no existe en Torneo.Pais.', 1;
        IF NOT EXISTS (SELECT 1 FROM Torneo.Sede WHERE nombreEstadio = @estadio AND ciudad = @ciudad)
            EXEC Torneo.Sede_Alta @nombreEstadio = @estadio, @ciudad = @ciudad, @idPais = @idPais,
                 @husoHorario = @huso, @capacidad = @capacidad, @latitud = @latitud, @longitud = @longitud;
    END TRY
    BEGIN CATCH
        PRINT 'Error al cargar la sede de la fila ' + CAST(@n AS varchar(10)) + ' de #sedes.';
        THROW;
    END CATCH;
    SET @n += 1;
END;
GO

-- Resumen de la carga
SELECT (SELECT COUNT(*) FROM Torneo.Pais) AS paises, (SELECT COUNT(*) FROM Torneo.Fase) AS fases,
       (SELECT COUNT(*) FROM Torneo.Periodo) AS periodos, (SELECT COUNT(*) FROM Torneo.Sede) AS sedes;
GO
