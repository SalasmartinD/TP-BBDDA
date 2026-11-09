/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : 09/11/2026

 Objetivo    : Carga base de equipos: las 16 selecciones de los grupos H, I, J y L
               del Mundial 2026, con su cuerpo técnico y sus 26 convocados
               (dorsal, posición, club y fecha de nacimiento de la lista
               oficial). La consigna pide al menos 23 por selección.

               Altura, peso y pierna hábil no figuran en la lista de la FIFA:
               se tomaron de Wikidata y de las fichas de Wikipedia en español,
               francés, portugués y neerlandés. Cuando ninguna fuente tenía el
               dato se usó un valor de ejemplo, marcado con un comentario en
               la fila del jugador.

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
   SELECCIONES
   ============================================================================= */
DROP TABLE IF EXISTS #selecciones;
CREATE TABLE #selecciones (n int IDENTITY(1,1) PRIMARY KEY, abreviacion char(3), pais char(3),
                           confederacion varchar(10), grupo char(1), nombreAsociacion nvarchar(100));
INSERT INTO #selecciones (abreviacion, pais, confederacion, grupo, nombreAsociacion) VALUES
    (N'ESP', N'ESP', N'UEFA', N'H', N'Real Federación Española de Fútbol'),
    (N'CPV', N'CPV', N'CAF', N'H', N'Federação Cabo-Verdiana de Futebol'),
    (N'URU', N'URY', N'CONMEBOL', N'H', N'Asociación Uruguaya de Fútbol'),
    (N'KSA', N'SAU', N'AFC', N'H', N'Saudi Arabian Football Federation'),
    (N'FRA', N'FRA', N'UEFA', N'I', N'Fédération Française de Football'),
    (N'NOR', N'NOR', N'UEFA', N'I', N'Norges Fotballforbund'),
    (N'SEN', N'SEN', N'CAF', N'I', N'Fédération Sénégalaise de Football'),
    (N'IRQ', N'IRQ', N'AFC', N'I', N'Iraq Football Association'),
    (N'ARG', N'ARG', N'CONMEBOL', N'J', N'Asociación del Fútbol Argentino'),
    (N'AUT', N'AUT', N'UEFA', N'J', N'Österreichischer Fußball-Bund'),
    (N'ALG', N'DZA', N'CAF', N'J', N'Fédération Algérienne de Football'),
    (N'JOR', N'JOR', N'AFC', N'J', N'Jordan Football Association'),
    (N'ENG', N'GBR', N'UEFA', N'L', N'The Football Association'),
    (N'CRO', N'HRV', N'UEFA', N'L', N'Hrvatski nogometni savez'),
    (N'GHA', N'GHA', N'CAF', N'L', N'Ghana Football Association'),
    (N'PAN', N'PAN', N'CONCACAF', N'L', N'Federación Panameña de Fútbol');

DECLARE @abrev char(3), @idPais int, @conf varchar(10), @grupo char(1), @asoc nvarchar(100);
DECLARE @n int = 1, @max int = (SELECT MAX(n) FROM #selecciones);
WHILE @n <= @max
BEGIN
    SELECT @abrev = s.abreviacion, @idPais = p.id, @conf = s.confederacion, @grupo = s.grupo, @asoc = s.nombreAsociacion
    FROM #selecciones s JOIN Torneo.Pais p ON p.codigoISO3 = s.pais WHERE s.n = @n;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE abreviacion = @abrev)
            EXEC Equipos.Seleccion_Alta @idPais = @idPais, @confederacion = @conf, @abreviacion = @abrev,
                 @nombreAsociacion = @asoc, @grupo = @grupo;
    END TRY
    BEGIN CATCH
        PRINT 'Error al cargar la selección de la fila ' + CAST(@n AS varchar(10)) + ' de #selecciones.';
        THROW;
    END CATCH;
    SET @n += 1;
END;
GO

/* =============================================================================
   CUERPOS TÉCNICOS durante el Mundial (los entrenadores de arqueros van como
   Ayudante). Cabo Verde: Bubista figura con su nombre real, Pedro Leitão Brito.
   ============================================================================= */
DROP TABLE IF EXISTS #staff;
CREATE TABLE #staff (n int IDENTITY(1,1) PRIMARY KEY, seleccion char(3), nombre nvarchar(60),
                     apellido nvarchar(60), rol varchar(20));
INSERT INTO #staff (seleccion, nombre, apellido, rol) VALUES
    (N'ESP', N'Luis', N'de la Fuente', N'Director Principal'),
    (N'ESP', N'Juanjo', N'González', N'Ayudante'),
    (N'ESP', N'Miguel Ángel', N'España', N'Ayudante'),
    (N'ESP', N'Carlos Alberto', N'Cruz', N'Preparador Fisico'),
    (N'CPV', N'Pedro', N'Leitão Brito', N'Director Principal'),
    (N'CPV', N'Humberto', N'Bettencourt', N'Ayudante'),
    (N'URU', N'Marcelo', N'Bielsa', N'Director Principal'),
    (N'URU', N'Pablo', N'Quiroga', N'Ayudante'),
    (N'URU', N'Diego', N'Reyes', N'Ayudante'),
    (N'URU', N'Diego', N'Bermúdez', N'Ayudante'),
    (N'URU', N'Enzo', N'Ferrari', N'Ayudante'),
    (N'URU', N'Santiago', N'Ferro', N'Preparador Fisico'),
    (N'KSA', N'Georgios', N'Donis', N'Director Principal'),
    (N'KSA', N'Makis', N'Angelinas', N'Ayudante'),
    (N'KSA', N'Leonidas', N'Vokolos', N'Ayudante'),
    (N'KSA', N'Savvas', N'Pantelidis', N'Ayudante'),
    (N'KSA', N'Yaya', N'Touré', N'Ayudante'),
    (N'KSA', N'Mohammed', N'Amin', N'Ayudante'),
    (N'KSA', N'Panagiotis', N'Maliaritsis', N'Ayudante'),
    (N'KSA', N'Giannis', N'Stavrinos', N'Preparador Fisico'),
    (N'FRA', N'Didier', N'Deschamps', N'Director Principal'),
    (N'FRA', N'Guy', N'Stéphan', N'Ayudante'),
    (N'FRA', N'Franck', N'Raviot', N'Ayudante'),
    (N'FRA', N'Cyril', N'Moine', N'Preparador Fisico'),
    (N'FRA', N'Franck', N'Le Gall', N'Medico'),
    (N'NOR', N'Ståle', N'Solbakken', N'Director Principal'),
    (N'NOR', N'Kent', N'Bergersen', N'Ayudante'),
    (N'NOR', N'Bjørn Vidar', N'Stenersen', N'Preparador Fisico'),
    (N'SEN', N'Pape', N'Thiaw', N'Director Principal'),
    (N'SEN', N'Pape Ibrahim', N'Ndiaye', N'Ayudante'),
    (N'SEN', N'Alsény', N'Thiam', N'Ayudante'),
    (N'SEN', N'Boubacarr', N'Mbodj', N'Ayudante'),
    (N'SEN', N'Ousmane', N'Thioub', N'Preparador Fisico'),
    (N'SEN', N'Ismaïl', N'Kébé', N'Medico'),
    (N'IRQ', N'Graham', N'Arnold', N'Director Principal'),
    (N'IRQ', N'René', N'Meulensteen', N'Ayudante'),
    (N'IRQ', N'Robert', N'Stanton', N'Ayudante'),
    (N'IRQ', N'Zeljko', N'Kalac', N'Ayudante'),
    (N'IRQ', N'Chris', N'Pappas', N'Preparador Fisico'),
    (N'IRQ', N'Mourad', N'Mokrani', N'Medico'),
    (N'ARG', N'Lionel', N'Scaloni', N'Director Principal'),
    (N'ARG', N'Pablo', N'Aimar', N'Ayudante'),
    (N'ARG', N'Roberto', N'Ayala', N'Ayudante'),
    (N'ARG', N'Walter', N'Samuel', N'Ayudante'),
    (N'ARG', N'Martín', N'Tocalli', N'Ayudante'),
    (N'ARG', N'Luis', N'Martín', N'Preparador Fisico'),
    (N'AUT', N'Ralf', N'Rangnick', N'Director Principal'),
    (N'AUT', N'Lars', N'Kornetka', N'Ayudante'),
    (N'AUT', N'Peter', N'Perchtold', N'Ayudante'),
    (N'AUT', N'Onur', N'Cinel', N'Ayudante'),
    (N'AUT', N'Michael', N'Gspurning', N'Ayudante'),
    (N'ALG', N'Vladimir', N'Petković', N'Director Principal'),
    (N'ALG', N'Davide', N'Morandi', N'Ayudante'),
    (N'ALG', N'Nabil', N'Neghiz', N'Ayudante'),
    (N'ALG', N'Merouane', N'Messai', N'Ayudante'),
    (N'ALG', N'Nacereddine', N'Berarma', N'Ayudante'),
    (N'ALG', N'Paolo', N'Rongoni', N'Preparador Fisico'),
    (N'ALG', N'Mohamed', N'Boughlali', N'Medico'),
    (N'JOR', N'Jamal', N'Sellami', N'Director Principal'),
    (N'JOR', N'Mustapha', N'Khalfi', N'Ayudante'),
    (N'JOR', N'Omar', N'Najhi', N'Ayudante'),
    (N'JOR', N'Ibrahim', N'Ayed', N'Ayudante'),
    (N'JOR', N'Youssef', N'Al-Aramsheh', N'Medico'),
    (N'ENG', N'Thomas', N'Tuchel', N'Director Principal'),
    (N'ENG', N'Anthony', N'Barry', N'Ayudante'),
    (N'ENG', N'Justin', N'Cochrane', N'Ayudante'),
    (N'ENG', N'Henrique', N'Hilário', N'Ayudante'),
    (N'ENG', N'Steve', N'Kemp', N'Preparador Fisico'),
    (N'ENG', N'Mark', N'Williams', N'Medico'),
    (N'CRO', N'Zlatko', N'Dalić', N'Director Principal'),
    (N'CRO', N'Vedran', N'Ćorluka', N'Ayudante'),
    (N'CRO', N'Marjan', N'Mrmić', N'Ayudante'),
    (N'CRO', N'Danijel', N'Subašić', N'Ayudante'),
    (N'CRO', N'Marin', N'Dadić', N'Preparador Fisico'),
    (N'CRO', N'Luka', N'Milanović', N'Preparador Fisico'),
    (N'CRO', N'Saša', N'Janković', N'Medico'),
    (N'CRO', N'Eduard', N'Rod', N'Medico'),
    (N'CRO', N'Tomislav', N'Vlahović', N'Medico'),
    (N'GHA', N'Carlos', N'Queiroz', N'Director Principal'),
    (N'GHA', N'Roger', N'De Sá', N'Ayudante'),
    (N'GHA', N'John', N'Paintsil', N'Ayudante'),
    (N'GHA', N'Daniel', N'Gaspar', N'Ayudante'),
    (N'GHA', N'Fatau', N'Dauda', N'Ayudante'),
    (N'PAN', N'Thomas', N'Christiansen', N'Director Principal'),
    (N'PAN', N'Francisco Javier', N'Sánchez Jara', N'Ayudante'),
    (N'PAN', N'Jorge', N'Dely Valdés', N'Ayudante'),
    (N'PAN', N'Donaldo', N'González', N'Ayudante');

DECLARE @idSel int, @nombre nvarchar(60), @apellido nvarchar(60), @rol varchar(20);
DECLARE @n int = 1, @max int = (SELECT MAX(n) FROM #staff);
WHILE @n <= @max
BEGIN
    SELECT @idSel = s.id, @nombre = t.nombre, @apellido = t.apellido, @rol = t.rol
    FROM #staff t JOIN Equipos.Seleccion s ON s.abreviacion = t.seleccion WHERE t.n = @n;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM Equipos.Staff WHERE idSeleccion = @idSel AND nombre = @nombre AND apellido = @apellido)
            EXEC Equipos.Staff_Alta @idSeleccion = @idSel, @nombre = @nombre, @apellido = @apellido, @rol = @rol;
    END TRY
    BEGIN CATCH
        PRINT 'Error al cargar el integrante del cuerpo técnico de la fila ' + CAST(@n AS varchar(10)) + ' de #staff.';
        THROW;
    END CATCH;
    SET @n += 1;
END;
GO

/* =============================================================================
   CONVOCADOS: jugador + convocatoria con fecha de alta 2026-06-01 (fecha
   límite de entrega de las listas a la FIFA). Los jugadores conocidos por un
   solo nombre (Rodri, Pedri, Gavi...) se cargan con su nombre completo.
   ============================================================================= */
DROP TABLE IF EXISTS #convocados;
CREATE TABLE #convocados (n int IDENTITY(1,1) PRIMARY KEY, seleccion char(3), dorsal tinyint,
                          nombre nvarchar(60), apellido nvarchar(60), fechaNacimiento date,
                          altura decimal(5,2), peso decimal(5,2), piernaHabil varchar(15),
                          club nvarchar(80), posicion varchar(15));
INSERT INTO #convocados (seleccion, dorsal, nombre, apellido, fechaNacimiento, altura, peso, piernaHabil, club, posicion) VALUES
    (N'ESP', 1, N'David', N'Raya', N'1995-09-15', 1.84, 84, N'Derecha', N'Arsenal', N'Arquero'),  -- valor de ejemplo: peso
    (N'ESP', 2, N'Marc', N'Pubill', N'2003-06-20', 1.91, 86.0, N'Derecha', N'Atlético Madrid', N'Defensor'),
    (N'ESP', 3, N'Álex', N'Grimaldo', N'1995-09-20', 1.7, 70.0, N'Izquierda', N'Bayer Leverkusen', N'Defensor'),
    (N'ESP', 4, N'Eric', N'García', N'2001-01-09', 1.82, 77.0, N'Derecha', N'Barcelona', N'Defensor'),
    (N'ESP', 5, N'Marcos', N'Llorente', N'1995-01-30', 1.84, 71.0, N'Derecha', N'Atlético Madrid', N'Defensor'),
    (N'ESP', 6, N'Mikel', N'Merino', N'1996-06-22', 1.88, 78.0, N'Izquierda', N'Arsenal', N'Mediocampista'),
    (N'ESP', 7, N'Ferran', N'Torres', N'2000-02-29', 1.84, 80.0, N'Derecha', N'Barcelona', N'Delantero'),
    (N'ESP', 8, N'Fabián', N'Ruiz', N'1996-04-03', 1.89, 70.0, N'Izquierda', N'Paris Saint-Germain', N'Mediocampista'),
    (N'ESP', 9, N'Pablo Martín', N'Páez Gavira', N'2004-08-05', 1.73, 69.0, N'Ambidiestro', N'Barcelona', N'Mediocampista'),
    (N'ESP', 10, N'Dani', N'Olmo', N'1998-05-07', 1.76, 68.0, N'Derecha', N'Barcelona', N'Delantero'),
    (N'ESP', 11, N'Yéremy', N'Pino', N'2002-10-20', 1.72, 79, N'Derecha', N'Crystal Palace', N'Delantero'),  -- valor de ejemplo: peso
    (N'ESP', 12, N'Pedro', N'Porro', N'1999-09-13', 1.76, 71.0, N'Derecha', N'Tottenham Hotspur', N'Defensor'),
    (N'ESP', 13, N'Joan', N'Garcia', N'2001-05-04', 1.94, 85.0, N'Derecha', N'Barcelona', N'Arquero'),
    (N'ESP', 14, N'Aymeric', N'Laporte', N'1994-05-27', 1.91, 85.0, N'Izquierda', N'Athletic Bilbao', N'Defensor'),
    (N'ESP', 15, N'Álex', N'Baena', N'2001-07-20', 1.74, 70.0, N'Derecha', N'Atlético Madrid', N'Mediocampista'),
    (N'ESP', 16, N'Rodrigo', N'Hernández Cascante', N'1996-06-22', 1.9, 78.0, N'Derecha', N'Manchester City', N'Mediocampista'),
    (N'ESP', 17, N'Nico', N'Williams', N'2002-07-12', 1.81, 73.0, N'Ambidiestro', N'Athletic Bilbao', N'Delantero'),
    (N'ESP', 18, N'Martín', N'Zubimendi', N'1999-02-02', 1.81, 74.0, N'Derecha', N'Arsenal', N'Mediocampista'),
    (N'ESP', 19, N'Lamine', N'Yamal', N'2007-07-13', 1.8, 76.0, N'Izquierda', N'Barcelona', N'Delantero'),
    (N'ESP', 20, N'Pedro', N'González López', N'2002-11-25', 1.74, 61.0, N'Derecha', N'Barcelona', N'Mediocampista'),
    (N'ESP', 21, N'Mikel', N'Oyarzabal', N'1997-04-21', 1.81, 78.0, N'Izquierda', N'Real Sociedad', N'Delantero'),
    (N'ESP', 22, N'Pau', N'Cubarsí', N'2007-01-22', 1.84, 79.0, N'Ambidiestro', N'Barcelona', N'Defensor'),
    (N'ESP', 23, N'Unai', N'Simón', N'1997-06-11', 1.92, 86.0, N'Derecha', N'Athletic Bilbao', N'Arquero'),
    (N'ESP', 24, N'Marc', N'Cucurella', N'1998-07-22', 1.73, 67.0, N'Izquierda', N'Chelsea', N'Defensor'),
    (N'ESP', 25, N'Víctor', N'Muñoz', N'2003-07-13', 1.73, 70.0, N'Derecha', N'Osasuna', N'Delantero'),
    (N'ESP', 26, N'Borja', N'Iglesias', N'1993-01-17', 1.87, 86.0, N'Derecha', N'Celta Vigo', N'Delantero'),
    (N'CPV', 1, N'Josimar José', N'Évora Dias', N'1986-06-03', 1.89, 75.0, N'Derecha', N'Chaves', N'Arquero'),
    (N'CPV', 2, N'Ianique', N'dos Santos Tavares', N'1988-05-20', 1.8, 75.0, N'Izquierda', N'Torreense', N'Defensor'),
    (N'CPV', 3, N'Edilson Alberto', N'Monteiro Sanches Borges', N'1995-01-17', 1.85, 78.0, N'Derecha', N'Al Bataeh', N'Defensor'),
    (N'CPV', 4, N'Roberto Carlos', N'Lopes', N'1992-06-17', 1.86, 83.0, N'Derecha', N'Shamrock Rovers', N'Defensor'),
    (N'CPV', 5, N'Logan', N'Costa', N'2001-04-01', 1.9, 79, N'Derecha', N'Villarreal', N'Defensor'),  -- valor de ejemplo: peso
    (N'CPV', 6, N'Kevin', N'Pina', N'1997-01-27', 1.81, 70, N'Derecha', N'Krasnodar', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'CPV', 7, N'Jovane', N'Cabral', N'1998-06-14', 1.76, 72.0, N'Derecha', N'Estrela Amadora', N'Mediocampista'),
    (N'CPV', 8, N'João Paulo', N'Moreira Fernandes', N'1998-05-26', 1.76, 77, N'Izquierda', N'FCSB', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'CPV', 9, N'Gilson', N'Benchimol', N'2001-12-29', 1.87, 79.0, N'Derecha', N'Akron Tolyatti', N'Delantero'),
    (N'CPV', 10, N'Jamiro', N'Monteiro', N'1993-11-23', 1.75, 72.0, N'Derecha', N'PEC Zwolle', N'Mediocampista'),
    (N'CPV', 11, N'Garry', N'Rodrigues', N'1990-11-27', 1.73, 72.0, N'Derecha', N'Apollon Limassol', N'Mediocampista'),
    (N'CPV', 12, N'Márcio', N'Rosa', N'1997-02-23', 1.86, 80, N'Derecha', N'Montana', N'Arquero'),  -- valor de ejemplo: peso
    (N'CPV', 13, N'Sidny', N'Lopes Cabral', N'2002-09-18', 1.76, 74, N'Ambidiestro', N'Benfica', N'Defensor'),  -- valor de ejemplo: peso
    (N'CPV', 14, N'Deroy', N'Duarte', N'1999-07-04', 1.77, 72.0, N'Derecha', N'Ludogorets Razgrad', N'Mediocampista'),
    (N'CPV', 15, N'Laros', N'Duarte', N'1997-02-28', 1.8, 76, N'Derecha', N'Puskás Akadémia', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'CPV', 16, N'Yannick', N'Semedo', N'1995-12-29', 1.71, 70, N'Izquierda', N'Farense', N'Mediocampista'),  -- valor de ejemplo: peso, pie
    (N'CPV', 17, N'Willy', N'Semedo', N'1994-04-27', 1.85, 72, N'Derecha', N'Omonia', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'CPV', 18, N'Telmo', N'Arcanjo', N'2001-06-21', 1.8, 77.0, N'Izquierda', N'Vitória de Guimarães', N'Mediocampista'),
    (N'CPV', 19, N'Dailon', N'Livramento', N'2001-05-04', 1.85, 82.0, N'Derecha', N'Casa Pia', N'Delantero'),
    (N'CPV', 20, N'Ryan', N'Mendes', N'1990-01-08', 1.78, 77.0, N'Derecha', N'Iğdır', N'Delantero'),
    (N'CPV', 21, N'Nuno', N'da Costa', N'1991-02-10', 1.82, 85.0, N'Derecha', N'İstanbul Başakşehir', N'Mediocampista'),
    (N'CPV', 22, N'Steven', N'Moreira', N'1994-08-13', 1.76, 67.0, N'Derecha', N'Columbus Crew', N'Defensor'),
    (N'CPV', 23, N'CJ', N'dos Santos', N'2000-08-24', 1.94, 85.0, N'Derecha', N'San Diego FC', N'Arquero'),
    (N'CPV', 24, N'Wagner', N'Pina', N'2002-11-03', 1.8, 75, N'Derecha', N'Trabzonspor', N'Defensor'),  -- valor de ejemplo: peso
    (N'CPV', 25, N'Kelvin', N'Pires', N'2000-06-05', 1.93, 76, N'Derecha', N'SJK', N'Defensor'),  -- valor de ejemplo: peso
    (N'CPV', 26, N'Hélio', N'Varela', N'2002-05-03', 1.76, 71, N'Derecha', N'Maccabi Tel Aviv', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'URU', 1, N'Sergio', N'Rochet', N'1993-03-23', 1.9, 82.0, N'Derecha', N'Internacional', N'Arquero'),
    (N'URU', 2, N'José María', N'Giménez', N'1995-01-20', 1.85, 76.0, N'Derecha', N'Atlético Madrid', N'Defensor'),
    (N'URU', 3, N'Sebastián', N'Cáceres', N'1999-08-18', 1.8, 76.0, N'Derecha', N'América', N'Defensor'),
    (N'URU', 4, N'Ronald', N'Araújo', N'1999-03-07', 1.91, 96.0, N'Derecha', N'Barcelona', N'Defensor'),
    (N'URU', 5, N'Manuel', N'Ugarte', N'2001-04-11', 1.82, 77.0, N'Derecha', N'Manchester United', N'Mediocampista'),
    (N'URU', 6, N'Rodrigo', N'Bentancur', N'1997-06-25', 1.85, 73.0, N'Derecha', N'Tottenham Hotspur', N'Mediocampista'),
    (N'URU', 7, N'Nicolás de la', N'Cruz', N'1997-06-01', 1.67, 65.0, N'Derecha', N'Flamengo', N'Mediocampista'),
    (N'URU', 8, N'Federico', N'Valverde', N'1998-07-22', 1.83, 72.0, N'Derecha', N'Real Madrid', N'Mediocampista'),
    (N'URU', 9, N'Darwin', N'Núñez', N'1999-06-24', 1.87, 81.0, N'Derecha', N'Al-Hilal', N'Delantero'),
    (N'URU', 10, N'Giorgian de', N'Arrascaeta', N'1994-06-01', 1.72, 67.0, N'Derecha', N'Flamengo', N'Mediocampista'),
    (N'URU', 11, N'Facundo', N'Pellistri', N'2001-12-20', 1.74, 72, N'Derecha', N'Panathinaikos', N'Delantero'),  -- valor de ejemplo: peso
    (N'URU', 12, N'Santiago', N'Mele', N'1997-09-06', 1.85, 78.0, N'Derecha', N'Monterrey', N'Arquero'),  -- valor de ejemplo: pie
    (N'URU', 13, N'Guillermo', N'Varela', N'1993-03-24', 1.71, 69.0, N'Derecha', N'Flamengo', N'Defensor'),
    (N'URU', 14, N'Agustín', N'Canobbio', N'1998-10-01', 1.75, 72.0, N'Derecha', N'Fluminense', N'Mediocampista'),
    (N'URU', 15, N'Emiliano', N'Martínez', N'1999-08-17', 1.85, 72.0, N'Derecha', N'Palmeiras', N'Mediocampista'),
    (N'URU', 16, N'Mathías', N'Olivera', N'1997-10-31', 1.84, 78.0, N'Izquierda', N'Napoli', N'Defensor'),
    (N'URU', 17, N'Matías', N'Viña', N'1997-11-09', 1.83, 70.0, N'Izquierda', N'River Plate', N'Defensor'),
    (N'URU', 18, N'Brian', N'Rodríguez', N'2000-05-20', 1.74, 68.0, N'Derecha', N'América', N'Delantero'),
    (N'URU', 19, N'Rodrigo', N'Aguirre', N'1994-10-01', 1.86, 75.0, N'Izquierda', N'Tigres UANL', N'Delantero'),
    (N'URU', 20, N'Maximiliano', N'Araújo', N'2000-02-15', 1.76, 73.0, N'Izquierda', N'Sporting CP', N'Mediocampista'),
    (N'URU', 21, N'Federico', N'Viñas', N'1998-06-30', 1.83, 85.0, N'Izquierda', N'Oviedo', N'Delantero'),
    (N'URU', 22, N'Joaquín', N'Piquerez', N'1998-08-24', 1.85, 81.0, N'Izquierda', N'Palmeiras', N'Mediocampista'),
    (N'URU', 23, N'Fernando', N'Muslera', N'1986-06-16', 1.91, 74.0, N'Ambidiestro', N'Estudiantes', N'Arquero'),
    (N'URU', 24, N'Santiago', N'Bueno', N'1998-11-09', 1.9, 79.0, N'Derecha', N'Wolverhampton Wanderers', N'Defensor'),
    (N'URU', 25, N'Juan Manuel', N'Sanabria', N'2000-03-29', 1.73, 70.0, N'Izquierda', N'Real Salt Lake', N'Mediocampista'),
    (N'URU', 26, N'Rodrigo', N'Zalazar', N'1999-08-12', 1.78, 70.0, N'Derecha', N'Braga', N'Mediocampista'),
    (N'KSA', 1, N'Nawaf', N'Al-Aqidi', N'2000-05-10', 1.88, 79, N'Derecha', N'Al-Nassr', N'Arquero'),  -- valor de ejemplo: peso
    (N'KSA', 2, N'Ali', N'Majrashi', N'1999-10-02', 1.77, 64.0, N'Derecha', N'Al-Ahli', N'Defensor'),
    (N'KSA', 3, N'Ali', N'Lajami', N'1996-04-24', 1.75, 76.0, N'Derecha', N'Al-Hilal', N'Defensor'),
    (N'KSA', 4, N'Abdulelah', N'Al-Amri', N'1997-01-15', 1.83, 81, N'Derecha', N'Al-Nassr', N'Defensor'),  -- valor de ejemplo: peso
    (N'KSA', 5, N'Hassan', N'Al-Tambakti', N'1999-02-09', 1.82, 82, N'Derecha', N'Al-Hilal', N'Defensor'),  -- valor de ejemplo: peso
    (N'KSA', 6, N'Nasser', N'Al-Dawsari', N'1998-12-19', 1.78, 64.0, N'Izquierda', N'Al-Hilal', N'Mediocampista'),
    (N'KSA', 7, N'Musab', N'Al-Juwayr', N'2003-06-20', 1.78, 70.0, N'Derecha', N'Al-Qadsiah', N'Mediocampista'),
    (N'KSA', 8, N'Ayman', N'Yahya', N'2001-05-14', 1.68, 70.0, N'Ambidiestro', N'Al-Nassr', N'Delantero'),
    (N'KSA', 9, N'Firas', N'Al-Buraikan', N'2000-05-14', 1.81, 79.0, N'Izquierda', N'Al-Ahli', N'Delantero'),
    (N'KSA', 10, N'Salem', N'Al-Dawsari', N'1991-08-19', 1.71, 72.0, N'Derecha', N'Al-Hilal', N'Delantero'),
    (N'KSA', 11, N'Saleh', N'Al-Shehri', N'1993-11-01', 1.77, 75, N'Derecha', N'Al-Ittihad', N'Delantero'),  -- valor de ejemplo: peso
    (N'KSA', 12, N'Saud', N'Abdulhamid', N'1999-07-18', 1.78, 70.0, N'Derecha', N'Lens', N'Defensor'),
    (N'KSA', 13, N'Nawaf', N'Boushal', N'1999-09-16', 1.78, 64.0, N'Derecha', N'Al-Nassr', N'Defensor'),
    (N'KSA', 14, N'Hassan', N'Kadesh', N'1992-09-26', 1.8, 75.0, N'Derecha', N'Al-Ittihad', N'Defensor'),  -- valor de ejemplo: pie
    (N'KSA', 15, N'Abdullah', N'Al-Khaibari', N'1996-08-16', 1.78, 66.0, N'Derecha', N'Al-Nassr', N'Mediocampista'),
    (N'KSA', 16, N'Ziyad', N'Al-Johani', N'2001-11-11', 1.8, 61.0, N'Izquierda', N'Al-Ahli', N'Mediocampista'),
    (N'KSA', 17, N'Khalid', N'Al-Ghannam', N'2000-11-08', 1.71, 66.0, N'Derecha', N'Al-Ettifaq', N'Delantero'),  -- valor de ejemplo: pie
    (N'KSA', 18, N'Alaa', N'Al-Hejji', N'1995-12-03', 1.78, 70, N'Derecha', N'Neom', N'Mediocampista'),  -- valor de ejemplo: peso, pie
    (N'KSA', 19, N'Abdullah', N'Al-Hamdan', N'1999-09-13', 1.84, 78.0, N'Ambidiestro', N'Al-Nassr', N'Delantero'),
    (N'KSA', 20, N'Sultan', N'Mandash', N'1994-10-17', 1.72, 66.0, N'Derecha', N'Al-Hilal', N'Delantero'),  -- valor de ejemplo: pie
    (N'KSA', 21, N'Mohammed', N'Al-Owais', N'1991-10-10', 1.85, 70.0, N'Izquierda', N'Al-Ula', N'Arquero'),
    (N'KSA', 22, N'Ahmed', N'Al-Kassar', N'1991-05-08', 1.79, 78.0, N'Izquierda', N'Al-Qadsiah', N'Arquero'),  -- valor de ejemplo: pie
    (N'KSA', 23, N'Mohamed', N'Kanno', N'1994-09-22', 1.92, 71.0, N'Derecha', N'Al-Hilal', N'Mediocampista'),
    (N'KSA', 24, N'Moteb', N'Al-Harbi', N'2000-02-20', 1.73, 60.0, N'Derecha', N'Al-Hilal', N'Defensor'),  -- valor de ejemplo: pie
    (N'KSA', 25, N'Jehad', N'Thakri', N'2001-07-21', 1.83, 74.0, N'Derecha', N'Al-Qadsiah', N'Defensor'),
    (N'KSA', 26, N'Mohammed', N'Abu Al-Shamat', N'2002-08-11', 1.7, 73, N'Derecha', N'Al-Qadsiah', N'Defensor'),  -- valor de ejemplo: peso
    (N'FRA', 1, N'Brice', N'Samba', N'1994-04-25', 1.86, 79.0, N'Izquierda', N'Rennes', N'Arquero'),
    (N'FRA', 2, N'Malo', N'Gusto', N'2003-05-19', 1.79, 75, N'Derecha', N'Chelsea', N'Defensor'),  -- valor de ejemplo: peso
    (N'FRA', 3, N'Lucas', N'Digne', N'1993-07-20', 1.78, 74.0, N'Izquierda', N'Aston Villa', N'Defensor'),
    (N'FRA', 4, N'Dayot', N'Upamecano', N'1998-10-27', 1.86, 90.0, N'Derecha', N'Bayern Munich', N'Defensor'),
    (N'FRA', 5, N'Jules', N'Koundé', N'1998-11-12', 1.8, 70.0, N'Derecha', N'Barcelona', N'Defensor'),
    (N'FRA', 6, N'Manu', N'Koné', N'2001-05-17', 1.85, 77.0, N'Derecha', N'Roma', N'Mediocampista'),
    (N'FRA', 7, N'Ousmane', N'Dembélé', N'1997-05-15', 1.79, 67.0, N'Ambidiestro', N'Paris Saint-Germain', N'Delantero'),
    (N'FRA', 8, N'Aurélien', N'Tchouaméni', N'2000-01-27', 1.87, 81.0, N'Derecha', N'Real Madrid', N'Mediocampista'),
    (N'FRA', 9, N'Marcus', N'Thuram', N'1997-08-06', 1.92, 90.0, N'Derecha', N'Inter Milan', N'Delantero'),
    (N'FRA', 10, N'Kylian', N'Mbappé', N'1998-12-20', 1.78, 75.0, N'Derecha', N'Real Madrid', N'Delantero'),
    (N'FRA', 11, N'Michael', N'Olise', N'2001-12-12', 1.8, 78.0, N'Izquierda', N'Bayern Munich', N'Delantero'),
    (N'FRA', 12, N'Bradley', N'Barcola', N'2002-09-02', 1.82, 73.0, N'Derecha', N'Paris Saint-Germain', N'Delantero'),
    (N'FRA', 13, N'N''Golo', N'Kanté', N'1991-03-29', 1.71, 70.0, N'Derecha', N'Fenerbahçe', N'Mediocampista'),
    (N'FRA', 14, N'Adrien', N'Rabiot', N'1995-04-03', 1.91, 72.0, N'Izquierda', N'AC Milan', N'Mediocampista'),
    (N'FRA', 15, N'Ibrahima', N'Konaté', N'1999-05-25', 1.94, 95.0, N'Derecha', N'Liverpool', N'Defensor'),
    (N'FRA', 16, N'Mike', N'Maignan', N'1995-07-03', 1.91, 80.0, N'Derecha', N'AC Milan', N'Arquero'),
    (N'FRA', 17, N'William', N'Saliba', N'2001-03-24', 1.92, 92.0, N'Derecha', N'Arsenal', N'Defensor'),
    (N'FRA', 18, N'Warren', N'Zaïre-Emery', N'2006-03-08', 1.78, 68.0, N'Derecha', N'Paris Saint-Germain', N'Mediocampista'),
    (N'FRA', 19, N'Théo', N'Hernandez', N'1997-10-06', 1.84, 81.0, N'Izquierda', N'Al-Hilal', N'Defensor'),
    (N'FRA', 20, N'Désiré', N'Doué', N'2005-06-03', 1.81, 79.0, N'Derecha', N'Paris Saint-Germain', N'Delantero'),
    (N'FRA', 21, N'Lucas', N'Hernandez', N'1996-02-14', 1.84, 79.0, N'Izquierda', N'Paris Saint-Germain', N'Defensor'),
    (N'FRA', 22, N'Jean-Philippe', N'Mateta', N'1997-06-28', 1.92, 84.0, N'Derecha', N'Crystal Palace', N'Delantero'),
    (N'FRA', 23, N'Robin', N'Risser', N'2004-12-02', 1.93, 87, N'Derecha', N'Lens', N'Arquero'),  -- valor de ejemplo: peso
    (N'FRA', 24, N'Rayan', N'Cherki', N'2003-08-17', 1.76, 70.0, N'Ambidiestro', N'Manchester City', N'Mediocampista'),
    (N'FRA', 25, N'Maghnes', N'Akliouche', N'2002-02-25', 1.83, 78, N'Izquierda', N'Monaco', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'FRA', 26, N'Maxence', N'Lacroix', N'2000-04-06', 1.9, 88.0, N'Derecha', N'Crystal Palace', N'Defensor'),
    (N'NOR', 1, N'Ørjan', N'Nyland', N'1990-09-10', 1.92, 78.0, N'Ambidiestro', N'Sevilla', N'Arquero'),
    (N'NOR', 2, N'Morten', N'Thorsby', N'1996-05-05', 1.86, 72.0, N'Derecha', N'Cremonese', N'Mediocampista'),
    (N'NOR', 3, N'Kristoffer', N'Ajer', N'1998-04-17', 1.98, 93.5, N'Derecha', N'Brentford', N'Defensor'),
    (N'NOR', 4, N'Leo', N'Østigård', N'1999-11-28', 1.82, 80.0, N'Derecha', N'Genoa', N'Defensor'),
    (N'NOR', 5, N'David', N'Møller Wolfe', N'2002-04-23', 1.85, 79.0, N'Izquierda', N'Wolverhampton Wanderers', N'Defensor'),
    (N'NOR', 6, N'Patrick', N'Berg', N'1997-11-24', 1.78, 78, N'Derecha', N'Bodø/Glimt', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'NOR', 7, N'Alexander', N'Sørloth', N'1995-12-05', 1.94, 90.0, N'Izquierda', N'Atlético Madrid', N'Delantero'),
    (N'NOR', 8, N'Sander', N'Berge', N'1998-02-14', 1.95, 97.0, N'Derecha', N'Fulham', N'Mediocampista'),
    (N'NOR', 9, N'Erling', N'Haaland', N'2000-07-21', 1.95, 87.0, N'Izquierda', N'Manchester City', N'Delantero'),
    (N'NOR', 10, N'Martin', N'Ødegaard', N'1998-12-17', 1.78, 68.0, N'Izquierda', N'Arsenal', N'Mediocampista'),
    (N'NOR', 11, N'Jørgen', N'Strand Larsen', N'2000-02-06', 1.93, 79.0, N'Derecha', N'Crystal Palace', N'Delantero'),
    (N'NOR', 12, N'Sander', N'Tangvik', N'2002-11-29', 1.93, 78, N'Derecha', N'Hamburger SV', N'Arquero'),  -- valor de ejemplo: peso
    (N'NOR', 13, N'Egil', N'Selvik', N'1997-07-30', 1.87, 75.0, N'Izquierda', N'Watford', N'Arquero'),
    (N'NOR', 14, N'Fredrik', N'Aursnes', N'1995-12-10', 1.79, 73, N'Derecha', N'Benfica', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'NOR', 15, N'Fredrik André', N'Bjørkan', N'1998-08-21', 1.8, 79, N'Izquierda', N'Bodø/Glimt', N'Defensor'),  -- valor de ejemplo: peso
    (N'NOR', 16, N'Marcus Holmgren', N'Pedersen', N'2000-07-16', 1.84, 76, N'Derecha', N'Torino', N'Defensor'),  -- valor de ejemplo: peso
    (N'NOR', 17, N'Torbjørn', N'Heggem', N'1999-01-12', 1.92, 73.0, N'Izquierda', N'Bologna', N'Defensor'),
    (N'NOR', 18, N'Kristian', N'Thorstvedt', N'1999-03-13', 1.9, 69, N'Izquierda', N'Sassuolo', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'NOR', 19, N'Thelo', N'Aasgaard', N'2002-05-02', 1.88, 80.0, N'Derecha', N'Rangers', N'Mediocampista'),
    (N'NOR', 20, N'Antonio', N'Nusa', N'2005-04-17', 1.8, 73.0, N'Derecha', N'RB Leipzig', N'Mediocampista'),
    (N'NOR', 21, N'Andreas', N'Schjelderup', N'2004-06-01', 1.76, 70, N'Derecha', N'Benfica', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'NOR', 22, N'Oscar', N'Bobb', N'2003-07-12', 1.69, 74, N'Izquierda', N'Fulham', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'NOR', 23, N'Jens Petter', N'Hauge', N'1999-10-12', 1.85, 75.0, N'Derecha', N'Bodø/Glimt', N'Mediocampista'),
    (N'NOR', 24, N'Sondre', N'Langås', N'2001-02-02', 1.8, 83.0, N'Derecha', N'Derby County', N'Defensor'),
    (N'NOR', 25, N'Henrik', N'Falchener', N'2003-05-08', 1.94, 78, N'Derecha', N'Viking', N'Defensor'),  -- valor de ejemplo: peso
    (N'NOR', 26, N'Julian', N'Ryerson', N'1997-11-17', 1.83, 79, N'Derecha', N'Borussia Dortmund', N'Defensor'),  -- valor de ejemplo: peso
    (N'SEN', 1, N'Yehvann', N'Diouf', N'1999-11-16', 1.9, 85, N'Derecha', N'Nice', N'Arquero'),  -- valor de ejemplo: peso
    (N'SEN', 2, N'Mamadou', N'Sarr', N'2005-08-29', 1.94, 80.5, N'Derecha', N'Chelsea', N'Defensor'),
    (N'SEN', 3, N'Kalidou', N'Koulibaly', N'1991-06-20', 1.88, 89.0, N'Ambidiestro', N'Al-Hilal', N'Defensor'),
    (N'SEN', 4, N'Abdoulaye', N'Seck', N'1992-06-04', 1.92, 74, N'Derecha', N'Maccabi Haifa', N'Defensor'),  -- valor de ejemplo: peso
    (N'SEN', 5, N'Idrissa', N'Gueye', N'1989-09-26', 1.74, 64.0, N'Derecha', N'Everton', N'Mediocampista'),
    (N'SEN', 6, N'Pathé', N'Ciss', N'1994-03-16', 1.86, 75, N'Derecha', N'Rayo Vallecano', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'SEN', 7, N'Assane', N'Diao', N'2005-09-07', 1.85, 73, N'Derecha', N'Como', N'Delantero'),  -- valor de ejemplo: peso
    (N'SEN', 8, N'Lamine', N'Camara', N'2004-01-01', 1.73, 71, N'Derecha', N'Monaco', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'SEN', 9, N'Bamba', N'Dieng', N'2000-03-23', 1.78, 74, N'Derecha', N'Lorient', N'Delantero'),  -- valor de ejemplo: peso
    (N'SEN', 10, N'Sadio', N'Mané', N'1992-04-10', 1.74, 70.0, N'Derecha', N'Al-Nassr', N'Delantero'),
    (N'SEN', 11, N'Nicolas', N'Jackson', N'2001-06-20', 1.87, 78.0, N'Derecha', N'Bayern Munich', N'Delantero'),
    (N'SEN', 12, N'Cherif', N'Ndiaye', N'1996-01-23', 1.9, 75, N'Derecha', N'Samsunspor', N'Delantero'),  -- valor de ejemplo: peso
    (N'SEN', 13, N'Iliman', N'Ndiaye', N'2000-03-06', 1.8, 78, N'Derecha', N'Everton', N'Delantero'),  -- valor de ejemplo: peso
    (N'SEN', 14, N'Ismail', N'Jakobs', N'1999-08-17', 1.84, 76, N'Izquierda', N'Galatasaray', N'Defensor'),  -- valor de ejemplo: peso
    (N'SEN', 15, N'Krépin', N'Diatta', N'1999-02-25', 1.75, 68.0, N'Derecha', N'Monaco', N'Defensor'),
    (N'SEN', 16, N'Édouard', N'Mendy', N'1992-03-01', 1.94, 86.0, N'Derecha', N'Al-Ahli', N'Arquero'),
    (N'SEN', 17, N'Pape Matar', N'Sarr', N'2002-09-14', 1.85, 72, N'Derecha', N'Tottenham Hotspur', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'SEN', 18, N'Ismaïla', N'Sarr', N'1998-02-25', 1.8, 70.0, N'Derecha', N'Crystal Palace', N'Delantero'),
    (N'SEN', 19, N'Moussa', N'Niakhaté', N'1996-03-08', 1.9, 82.0, N'Izquierda', N'Lyon', N'Defensor'),
    (N'SEN', 20, N'Ibrahim', N'Mbaye', N'2008-01-24', 1.85, 65.0, N'Derecha', N'Paris Saint-Germain', N'Delantero'),
    (N'SEN', 21, N'Habib', N'Diarra', N'2004-01-03', 1.79, 74, N'Derecha', N'Sunderland', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'SEN', 22, N'Bara', N'Sapoko Ndiaye', N'2007-12-31', 1.8, 73, N'Derecha', N'Bayern Munich', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'SEN', 23, N'Mory', N'Diaw', N'1993-06-22', 1.95, 80, N'Derecha', N'Le Havre', N'Arquero'),  -- valor de ejemplo: peso
    (N'SEN', 24, N'Antoine', N'Mendy', N'2004-05-27', 1.87, 75, N'Derecha', N'Nice', N'Defensor'),  -- valor de ejemplo: peso
    (N'SEN', 25, N'El Hadji Malick', N'Diouf', N'2004-12-29', 1.83, 75.0, N'Izquierda', N'West Ham United', N'Defensor'),
    (N'SEN', 26, N'Pape', N'Gueye', N'1999-01-24', 1.89, 79.0, N'Izquierda', N'Villarreal', N'Mediocampista'),
    (N'IRQ', 1, N'Fahad', N'Talib', N'1994-10-21', 1.92, 84.0, N'Izquierda', N'Al-Talaba', N'Arquero'),  -- valor de ejemplo: pie
    (N'IRQ', 2, N'Rebin', N'Sulaka', N'1992-04-12', 1.92, 78, N'Derecha', N'Port', N'Defensor'),  -- valor de ejemplo: peso
    (N'IRQ', 3, N'Hussein', N'Ali', N'2002-03-01', 1.8, 75.0, N'Derecha', N'Pogoń Szczecin', N'Defensor'),
    (N'IRQ', 4, N'Zaid', N'Tahseen', N'2001-01-29', 1.93, 84.0, N'Derecha', N'Pakhtakor', N'Defensor'),  -- valor de ejemplo: pie
    (N'IRQ', 5, N'Akam', N'Hashim', N'1998-08-16', 1.86, 80, N'Izquierda', N'Al-Zawraa', N'Defensor'),  -- valor de ejemplo: peso
    (N'IRQ', 6, N'Manaf', N'Younis', N'1996-11-16', 1.9, 83.0, N'Derecha', N'Al-Shorta', N'Defensor'),  -- valor de ejemplo: pie
    (N'IRQ', 7, N'Youssef', N'Amyn', N'2003-08-21', 1.75, 69.0, N'Derecha', N'AEK Larnaca', N'Mediocampista'),
    (N'IRQ', 8, N'Ibrahim', N'Bayesh', N'2000-05-01', 1.77, 74.0, N'Derecha', N'Al Dhafra', N'Mediocampista'),
    (N'IRQ', 9, N'Ali', N'Al-Hamadi', N'2002-03-01', 1.83, 81.0, N'Derecha', N'Luton Town', N'Delantero'),
    (N'IRQ', 10, N'Mohanad', N'Ali', N'2000-06-20', 1.83, 73.0, N'Derecha', N'Dibba', N'Delantero'),
    (N'IRQ', 11, N'Ahmed', N'Qasem', N'2003-07-12', 1.83, 72, N'Izquierda', N'Nashville SC', N'Delantero'),  -- valor de ejemplo: peso
    (N'IRQ', 12, N'Jalal', N'Hassan', N'1991-05-18', 1.84, 81, N'Derecha', N'Al-Zawraa', N'Arquero'),  -- valor de ejemplo: peso
    (N'IRQ', 13, N'Ali', N'Yousif', N'1996-01-19', 1.83, 77, N'Derecha', N'Al-Talaba', N'Delantero'),  -- valor de ejemplo: altura, peso
    (N'IRQ', 14, N'Zidane', N'Iqbal', N'2003-04-27', 1.81, 65.0, N'Derecha', N'Utrecht', N'Mediocampista'),
    (N'IRQ', 15, N'Ahmed', N'Maknzi', N'2001-09-24', 1.8, 74.0, N'Izquierda', N'Al-Karma', N'Defensor'),
    (N'IRQ', 16, N'Amir', N'Al-Ammari', N'1997-07-27', 1.8, 71.0, N'Izquierda', N'Cracovia', N'Mediocampista'),
    (N'IRQ', 17, N'Ali', N'Jasim', N'2004-01-20', 1.78, 71, N'Derecha', N'Al-Najma', N'Delantero'),  -- valor de ejemplo: peso, pie
    (N'IRQ', 18, N'Aymen', N'Hussein', N'1996-03-22', 1.89, 75, N'Derecha', N'Al-Karma', N'Delantero'),  -- valor de ejemplo: peso
    (N'IRQ', 19, N'Kevin', N'Yakob', N'2000-10-10', 1.77, 70, N'Derecha', N'AGF', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'IRQ', 20, N'Aimar', N'Sher', N'2002-12-20', 1.75, 68, N'Derecha', N'Sarpsborg 08', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'IRQ', 21, N'Marko', N'Farji', N'2004-03-16', 1.84, 76, N'Derecha', N'Venezia', N'Delantero'),  -- valor de ejemplo: peso
    (N'IRQ', 22, N'Ahmed', N'Basil', N'1996-08-19', 1.95, 87, N'Derecha', N'Al-Shorta', N'Arquero'),  -- valor de ejemplo: altura, peso
    (N'IRQ', 23, N'Merchas', N'Doski', N'1999-12-07', 1.73, 73, N'Izquierda', N'Viktoria Plzeň', N'Defensor'),  -- valor de ejemplo: peso
    (N'IRQ', 24, N'Zaid', N'Ismail', N'2002-01-03', 1.8, 75, N'Derecha', N'Al-Talaba', N'Mediocampista'),  -- valor de ejemplo: altura, peso, pie
    (N'IRQ', 25, N'Mustafa', N'Saadoon', N'2001-05-25', 1.82, 73.0, N'Derecha', N'Al-Shorta', N'Defensor'),
    (N'IRQ', 26, N'Frans', N'Putros', N'1993-07-14', 1.81, 80, N'Derecha', N'Persib', N'Defensor'),  -- valor de ejemplo: peso, pie
    (N'ARG', 1, N'Juan', N'Musso', N'1994-05-06', 1.91, 93.0, N'Derecha', N'Atlético Madrid', N'Arquero'),
    (N'ARG', 2, N'Marcos', N'Senesi', N'1997-05-10', 1.84, 79.0, N'Izquierda', N'Bournemouth', N'Defensor'),
    (N'ARG', 3, N'Nicolás', N'Tagliafico', N'1992-08-31', 1.72, 65.0, N'Izquierda', N'Lyon', N'Defensor'),
    (N'ARG', 4, N'Gonzalo', N'Montiel', N'1997-01-01', 1.75, 70.0, N'Derecha', N'River Plate', N'Defensor'),
    (N'ARG', 5, N'Leandro', N'Paredes', N'1994-06-29', 1.84, 75.0, N'Derecha', N'Boca Juniors', N'Mediocampista'),
    (N'ARG', 6, N'Lisandro', N'Martínez', N'1998-01-18', 1.75, 77.0, N'Izquierda', N'Manchester United', N'Defensor'),
    (N'ARG', 7, N'Rodrigo', N'De Paul', N'1994-05-24', 1.8, 74.0, N'Derecha', N'Inter Miami CF', N'Mediocampista'),
    (N'ARG', 8, N'Valentín', N'Barco', N'2004-07-23', 1.7, 67.0, N'Izquierda', N'Strasbourg', N'Mediocampista'),
    (N'ARG', 9, N'Julián', N'Alvarez', N'2000-01-31', 1.69, 71.0, N'Derecha', N'Atlético Madrid', N'Delantero'),
    (N'ARG', 10, N'Lionel', N'Messi', N'1987-06-24', 1.69, 72.0, N'Izquierda', N'Inter Miami CF', N'Delantero'),
    (N'ARG', 11, N'Giovani', N'Lo Celso', N'1996-04-09', 1.77, 78.0, N'Izquierda', N'Real Betis', N'Mediocampista'),
    (N'ARG', 12, N'Gerónimo', N'Rulli', N'1992-05-20', 1.89, 80.0, N'Derecha', N'Marseille', N'Arquero'),
    (N'ARG', 13, N'Cristian', N'Romero', N'1998-04-27', 1.88, 85.0, N'Derecha', N'Tottenham Hotspur', N'Defensor'),
    (N'ARG', 14, N'Exequiel', N'Palacios', N'1998-10-05', 1.77, 70.0, N'Derecha', N'Bayer Leverkusen', N'Mediocampista'),
    (N'ARG', 15, N'Nicolás', N'González', N'1998-04-06', 1.8, 69, N'Izquierda', N'Atlético Madrid', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'ARG', 16, N'Thiago', N'Almada', N'2001-04-26', 1.71, 63.0, N'Derecha', N'Atlético Madrid', N'Delantero'),
    (N'ARG', 17, N'Giuliano', N'Simeone', N'2002-12-18', 1.73, 74, N'Derecha', N'Atlético Madrid', N'Delantero'),  -- valor de ejemplo: peso
    (N'ARG', 18, N'Nico', N'Paz', N'2004-09-08', 1.85, 81.0, N'Izquierda', N'Como', N'Delantero'),
    (N'ARG', 19, N'Nicolás', N'Otamendi', N'1988-02-12', 1.83, 81.0, N'Derecha', N'Benfica', N'Defensor'),
    (N'ARG', 20, N'Alexis', N'Mac Allister', N'1998-12-24', 1.76, 72.0, N'Derecha', N'Liverpool', N'Mediocampista'),
    (N'ARG', 21, N'José Manuel', N'López', N'2000-12-06', 1.9, 74.0, N'Izquierda', N'Palmeiras', N'Delantero'),
    (N'ARG', 22, N'Lautaro', N'Martínez', N'1997-08-22', 1.74, 72.0, N'Derecha', N'Inter Milan', N'Delantero'),
    (N'ARG', 23, N'Emiliano', N'Martínez', N'1992-09-02', 1.95, 85.0, N'Derecha', N'Aston Villa', N'Arquero'),
    (N'ARG', 24, N'Enzo', N'Fernández', N'2001-01-17', 1.78, 78.0, N'Derecha', N'Chelsea', N'Mediocampista'),
    (N'ARG', 25, N'Facundo', N'Medina', N'1999-05-28', 1.84, 78.0, N'Izquierda', N'Marseille', N'Defensor'),
    (N'ARG', 26, N'Nahuel', N'Molina', N'1998-04-06', 1.75, 70.0, N'Derecha', N'Atlético Madrid', N'Defensor'),
    (N'AUT', 1, N'Alexander', N'Schlager', N'1996-02-01', 1.84, 87, N'Derecha', N'Red Bull Salzburg', N'Arquero'),  -- valor de ejemplo: peso
    (N'AUT', 2, N'David', N'Affengruber', N'2001-03-19', 1.85, 79.0, N'Derecha', N'Elche', N'Defensor'),
    (N'AUT', 3, N'Kevin', N'Danso', N'1998-09-19', 1.9, 80.0, N'Derecha', N'Tottenham Hotspur', N'Defensor'),
    (N'AUT', 4, N'Xaver', N'Schlager', N'1997-09-28', 1.74, 75.0, N'Izquierda', N'RB Leipzig', N'Mediocampista'),
    (N'AUT', 5, N'Stefan', N'Posch', N'1997-05-14', 1.89, 82.0, N'Derecha', N'Mainz 05', N'Defensor'),
    (N'AUT', 6, N'Nicolas', N'Seiwald', N'2001-05-04', 1.79, 75, N'Derecha', N'RB Leipzig', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'AUT', 7, N'Marko', N'Arnautović', N'1989-04-19', 1.89, 83.0, N'Ambidiestro', N'Red Star Belgrade', N'Delantero'),
    (N'AUT', 8, N'David', N'Alaba', N'1992-06-24', 1.8, 76.0, N'Izquierda', N'Real Madrid', N'Defensor'),
    (N'AUT', 9, N'Marcel', N'Sabitzer', N'1994-03-17', 1.76, 70.0, N'Derecha', N'Borussia Dortmund', N'Mediocampista'),
    (N'AUT', 10, N'Florian', N'Grillitsch', N'1995-08-07', 1.86, 73.0, N'Derecha', N'Braga', N'Mediocampista'),
    (N'AUT', 11, N'Michael', N'Gregoritsch', N'1994-04-18', 1.94, 76, N'Izquierda', N'FC Augsburg', N'Delantero'),  -- valor de ejemplo: peso
    (N'AUT', 12, N'Florian', N'Wiegele', N'2001-03-21', 2.05, 80, N'Izquierda', N'Viktoria Plzeň', N'Arquero'),  -- valor de ejemplo: peso
    (N'AUT', 13, N'Patrick', N'Pentz', N'1997-01-02', 1.86, 72.0, N'Izquierda', N'Brøndby', N'Arquero'),
    (N'AUT', 14, N'Saša', N'Kalajdžić', N'1997-07-07', 2.0, 76.0, N'Derecha', N'LASK', N'Delantero'),
    (N'AUT', 15, N'Philipp', N'Lienhart', N'1996-07-11', 1.89, 83.0, N'Derecha', N'SC Freiburg', N'Defensor'),
    (N'AUT', 16, N'Phillipp', N'Mwene', N'1994-01-29', 1.7, 66.0, N'Derecha', N'Mainz 05', N'Defensor'),
    (N'AUT', 17, N'Carney', N'Chukwuemeka', N'2003-10-20', 1.87, 77.0, N'Derecha', N'Borussia Dortmund', N'Mediocampista'),
    (N'AUT', 18, N'Romano', N'Schmid', N'2000-01-27', 1.68, 77, N'Derecha', N'Werder Bremen', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'AUT', 19, N'Dejan', N'Ljubičić', N'1997-10-08', 1.87, 74.0, N'Derecha', N'Schalke 04', N'Mediocampista'),
    (N'AUT', 20, N'Konrad', N'Laimer', N'1997-05-27', 1.79, 68.0, N'Derecha', N'Bayern Munich', N'Mediocampista'),
    (N'AUT', 21, N'Patrick', N'Wimmer', N'2001-05-30', 1.82, 78, N'Derecha', N'VfL Wolfsburg', N'Delantero'),  -- valor de ejemplo: peso
    (N'AUT', 22, N'Alexander', N'Prass', N'2001-05-26', 1.8, 75, N'Izquierda', N'TSG Hoffenheim', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'AUT', 23, N'Marco', N'Friedl', N'1998-03-16', 1.87, 71.0, N'Izquierda', N'Werder Bremen', N'Defensor'),
    (N'AUT', 24, N'Paul', N'Wanner', N'2005-12-23', 1.85, 72.0, N'Izquierda', N'PSV Eindhoven', N'Mediocampista'),
    (N'AUT', 25, N'Michael', N'Svoboda', N'1998-10-15', 1.95, 86.0, N'Derecha', N'Venezia', N'Defensor'),
    (N'AUT', 26, N'Alessandro', N'Schöpf', N'1994-02-07', 1.78, 75.0, N'Derecha', N'Wolfsberger AC', N'Mediocampista'),
    (N'ALG', 1, N'Melvin', N'Mastil', N'2000-02-19', 1.94, 80, N'Derecha', N'Stade Nyonnais', N'Arquero'),  -- valor de ejemplo: peso
    (N'ALG', 2, N'Aïssa', N'Mandi', N'1991-10-22', 1.86, 78.0, N'Derecha', N'Lille', N'Defensor'),
    (N'ALG', 3, N'Achref', N'Abada', N'1999-06-15', 1.85, 73, N'Derecha', N'USM Alger', N'Defensor'),  -- valor de ejemplo: peso
    (N'ALG', 4, N'Mohamed Amine', N'Tougai', N'2000-01-22', 1.81, 79.0, N'Derecha', N'Espérance de Tunis', N'Defensor'),  -- valor de ejemplo: altura
    (N'ALG', 5, N'Zineddine', N'Belaïd', N'1999-03-20', 1.87, 89.0, N'Derecha', N'JS Kabylie', N'Defensor'),
    (N'ALG', 6, N'Ramiz', N'Zerrouki', N'1998-05-26', 1.83, 72, N'Derecha', N'Twente', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'ALG', 7, N'Riyad', N'Mahrez', N'1991-02-21', 1.81, 66.0, N'Izquierda', N'Al-Ahli', N'Delantero'),
    (N'ALG', 8, N'Houssem', N'Aouar', N'1998-06-30', 1.75, 70.0, N'Derecha', N'Al-Ittihad', N'Mediocampista'),
    (N'ALG', 9, N'Amine', N'Gouiri', N'2000-02-16', 1.8, 72.0, N'Derecha', N'Marseille', N'Delantero'),
    (N'ALG', 10, N'Farès', N'Chaïbi', N'2002-11-28', 1.83, 78, N'Derecha', N'Eintracht Frankfurt', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'ALG', 11, N'Anis', N'Hadj Moussa', N'2002-02-11', 1.76, 70, N'Izquierda', N'Feyenoord', N'Delantero'),  -- valor de ejemplo: peso
    (N'ALG', 12, N'Nadhir', N'Benbouali', N'2000-04-17', 1.9, 70, N'Ambidiestro', N'Győri ETO', N'Delantero'),  -- valor de ejemplo: peso
    (N'ALG', 13, N'Jaouen', N'Hadjam', N'2003-03-26', 1.84, 77, N'Izquierda', N'Young Boys', N'Defensor'),  -- valor de ejemplo: peso
    (N'ALG', 14, N'Hicham', N'Boudaoui', N'1999-09-23', 1.75, 73.0, N'Derecha', N'Nice', N'Mediocampista'),
    (N'ALG', 15, N'Rayan', N'Aït-Nouri', N'2001-06-06', 1.8, 70.0, N'Izquierda', N'Manchester City', N'Defensor'),
    (N'ALG', 16, N'Oussama', N'Benbot', N'1994-10-11', 1.88, 90.0, N'Derecha', N'USM Alger', N'Arquero'),  -- valor de ejemplo: pie
    (N'ALG', 17, N'Rafik', N'Belghali', N'2002-06-07', 1.86, 80, N'Derecha', N'Hellas Verona', N'Defensor'),  -- valor de ejemplo: peso
    (N'ALG', 18, N'Mohamed', N'Amoura', N'2000-05-09', 1.68, 61.0, N'Derecha', N'VfL Wolfsburg', N'Delantero'),
    (N'ALG', 19, N'Nabil', N'Bentaleb', N'1994-11-24', 1.87, 78.0, N'Izquierda', N'Lille', N'Mediocampista'),
    (N'ALG', 20, N'Adil', N'Boulbina', N'2003-05-02', 1.77, 77.0, N'Derecha', N'Al-Duhail', N'Delantero'),
    (N'ALG', 21, N'Ramy', N'Bensebaini', N'1995-04-16', 1.88, 85.0, N'Izquierda', N'Borussia Dortmund', N'Defensor'),
    (N'ALG', 22, N'Ibrahim', N'Maza', N'2005-11-24', 1.77, 70.0, N'Derecha', N'Bayer Leverkusen', N'Mediocampista'),
    (N'ALG', 23, N'Luca', N'Zidane', N'1998-05-13', 1.83, 76.0, N'Derecha', N'Granada', N'Arquero'),
    (N'ALG', 24, N'Yacine', N'Titraoui', N'2003-07-26', 1.73, 69, N'Derecha', N'Charleroi', N'Mediocampista'),  -- valor de ejemplo: altura, peso
    (N'ALG', 25, N'Farès', N'Ghedjemis', N'2002-09-06', 1.8, 70, N'Izquierda', N'Frosinone', N'Delantero'),  -- valor de ejemplo: peso
    (N'ALG', 26, N'Samir', N'Chergui', N'1999-02-06', 1.85, 78.0, N'Derecha', N'Paris FC', N'Defensor'),
    (N'JOR', 1, N'Yazeed', N'Abulaila', N'1993-01-08', 1.89, 83.0, N'Derecha', N'Al-Hussein', N'Arquero'),
    (N'JOR', 2, N'Mohammad', N'Abu Hashish', N'1995-05-09', 1.77, 75, N'Derecha', N'Al-Karma', N'Defensor'),  -- valor de ejemplo: peso, pie
    (N'JOR', 3, N'Abdallah', N'Nasib', N'1994-02-25', 1.84, 83, N'Derecha', N'Al-Zawraa', N'Defensor'),  -- valor de ejemplo: peso
    (N'JOR', 4, N'Husam', N'Abu Dahab', N'2000-05-13', 1.86, 80.0, N'Izquierda', N'Al-Faisaly', N'Defensor'),
    (N'JOR', 5, N'Yazan', N'Al-Arab', N'1996-01-31', 1.87, 80, N'Izquierda', N'FC Seoul', N'Defensor'),  -- valor de ejemplo: peso
    (N'JOR', 6, N'Amer', N'Jamous', N'2002-07-03', 1.74, 76.0, N'Derecha', N'Al-Zawraa', N'Mediocampista'),
    (N'JOR', 7, N'Mohammad', N'Abu Zrayq', N'1997-12-30', 1.68, 74, N'Izquierda', N'Raja Casablanca', N'Delantero'),  -- valor de ejemplo: peso, pie
    (N'JOR', 8, N'Noor', N'Al-Rawabdeh', N'1997-02-24', 1.82, 71, N'Derecha', N'Selangor', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'JOR', 9, N'Ali', N'Olwan', N'2000-03-26', 1.83, 80.0, N'Derecha', N'Al-Sailiya', N'Delantero'),
    (N'JOR', 10, N'Musa', N'Al-Taamari', N'1997-06-10', 1.78, 75.0, N'Izquierda', N'Rennes', N'Delantero'),
    (N'JOR', 11, N'Odeh', N'Al-Fakhouri', N'2005-11-22', 1.85, 75, N'Derecha', N'Pyramids', N'Delantero'),  -- valor de ejemplo: peso
    (N'JOR', 12, N'Nour', N'Bani Attiah', N'1993-01-25', 1.95, 83.0, N'Derecha', N'Al-Faisaly', N'Arquero'),  -- valor de ejemplo: altura, pie
    (N'JOR', 13, N'Mahmoud', N'Al-Mardi', N'1993-10-06', 1.73, 76, N'Derecha', N'Al-Hussein', N'Delantero'),  -- valor de ejemplo: peso
    (N'JOR', 14, N'Rajaei', N'Ayed', N'1993-07-25', 1.77, 74, N'Ambidiestro', N'Al-Hussein', N'Mediocampista'),  -- valor de ejemplo: peso, pie
    (N'JOR', 15, N'Ibrahim', N'Sadeh', N'2000-04-27', 1.81, 75.0, N'Derecha', N'Al-Karma', N'Mediocampista'),
    (N'JOR', 16, N'Mo', N'Abualnadi', N'2001-02-08', 1.85, 75.0, N'Izquierda', N'Selangor', N'Defensor'),
    (N'JOR', 17, N'Salim', N'Obaid', N'1992-01-17', 1.87, 80, N'Derecha', N'Al-Hussein', N'Defensor'),  -- valor de ejemplo: peso, pie
    (N'JOR', 18, N'Mohammad', N'Abu Ghoush', N'2005-07-13', 1.72, 68, N'Izquierda', N'Al-Hussein', N'Mediocampista'),  -- valor de ejemplo: altura, peso, pie
    (N'JOR', 19, N'Saed', N'Al-Rosan', N'1997-02-01', 1.85, 73, N'Derecha', N'Al-Hussein', N'Defensor'),  -- valor de ejemplo: peso, pie
    (N'JOR', 20, N'Mohannad', N'Abu Taha', N'2003-02-02', 1.77, 76.0, N'Izquierda', N'Al-Quwa Al-Jawiya', N'Mediocampista'),
    (N'JOR', 21, N'Nizar', N'Al-Rashdan', N'1999-03-23', 1.85, 70, N'Derecha', N'Qatar SC', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'JOR', 22, N'Abdallah', N'Al-Fakhouri', N'2000-01-22', 1.87, 84.0, N'Derecha', N'Al-Wehdat', N'Arquero'),
    (N'JOR', 23, N'Ihsan', N'Haddad', N'1994-02-05', 1.81, 80, N'Derecha', N'Al-Hussein', N'Defensor'),  -- valor de ejemplo: peso
    (N'JOR', 24, N'Ali', N'Azaizeh', N'2004-04-13', 1.78, 77.0, N'Izquierda', N'Al-Shabab', N'Delantero'),
    (N'JOR', 25, N'Mohammad', N'Al-Dawoud', N'1992-04-12', 1.81, 69, N'Derecha', N'Al-Wehdat', N'Mediocampista'),  -- valor de ejemplo: peso, pie
    (N'JOR', 26, N'Anas', N'Badawi', N'1997-09-13', 1.74, 70.0, N'Izquierda', N'Al-Faisaly', N'Defensor'),  -- valor de ejemplo: pie
    (N'ENG', 1, N'Jordan', N'Pickford', N'1994-03-07', 1.85, 77.0, N'Izquierda', N'Everton', N'Arquero'),
    (N'ENG', 2, N'Ezri', N'Konsa', N'1997-10-23', 1.83, 77.0, N'Derecha', N'Aston Villa', N'Defensor'),
    (N'ENG', 3, N'Nico', N'O''Reilly', N'2005-03-21', 1.93, 75, N'Izquierda', N'Manchester City', N'Defensor'),  -- valor de ejemplo: peso
    (N'ENG', 4, N'Declan', N'Rice', N'1999-01-14', 1.88, 80.0, N'Derecha', N'Arsenal', N'Mediocampista'),
    (N'ENG', 5, N'John', N'Stones', N'1994-05-28', 1.88, 70.0, N'Derecha', N'Manchester City', N'Defensor'),
    (N'ENG', 6, N'Marc', N'Guéhi', N'2000-07-13', 1.82, 82.0, N'Derecha', N'Manchester City', N'Defensor'),
    (N'ENG', 7, N'Bukayo', N'Saka', N'2001-09-05', 1.78, 72.0, N'Izquierda', N'Arsenal', N'Delantero'),
    (N'ENG', 8, N'Elliot', N'Anderson', N'2002-11-06', 1.79, 73, N'Derecha', N'Nottingham Forest', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'ENG', 9, N'Harry', N'Kane', N'1993-07-28', 1.88, 86.0, N'Derecha', N'Bayern Munich', N'Delantero'),
    (N'ENG', 10, N'Jude', N'Bellingham', N'2003-06-29', 1.86, 75.0, N'Derecha', N'Real Madrid', N'Mediocampista'),
    (N'ENG', 11, N'Marcus', N'Rashford', N'1997-10-31', 1.88, 80.0, N'Derecha', N'Barcelona', N'Delantero'),
    (N'ENG', 12, N'Trevoh', N'Chalobah', N'1999-07-05', 1.92, 84.0, N'Derecha', N'Chelsea', N'Defensor'),
    (N'ENG', 13, N'Dean', N'Henderson', N'1997-03-12', 1.88, 85.0, N'Derecha', N'Crystal Palace', N'Arquero'),
    (N'ENG', 14, N'Jordan', N'Henderson', N'1990-06-17', 1.82, 67.0, N'Derecha', N'Brentford', N'Mediocampista'),
    (N'ENG', 15, N'Dan', N'Burn', N'1992-05-09', 2.01, 87.0, N'Izquierda', N'Newcastle United', N'Defensor'),
    (N'ENG', 16, N'Kobbie', N'Mainoo', N'2005-04-19', 1.75, 70.0, N'Derecha', N'Manchester United', N'Mediocampista'),
    (N'ENG', 17, N'Morgan', N'Rogers', N'2002-07-26', 1.87, 69, N'Derecha', N'Aston Villa', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'ENG', 18, N'Anthony', N'Gordon', N'2001-02-24', 1.83, 72.0, N'Derecha', N'Newcastle United', N'Delantero'),
    (N'ENG', 19, N'Ollie', N'Watkins', N'1995-12-30', 1.8, 70.0, N'Derecha', N'Aston Villa', N'Delantero'),
    (N'ENG', 20, N'Noni', N'Madueke', N'2002-03-10', 1.82, 70.0, N'Izquierda', N'Arsenal', N'Delantero'),
    (N'ENG', 21, N'Eberechi', N'Eze', N'1998-06-29', 1.78, 67.0, N'Derecha', N'Arsenal', N'Mediocampista'),
    (N'ENG', 22, N'Ivan', N'Toney', N'1996-03-16', 1.79, 70.0, N'Derecha', N'Al-Ahli', N'Delantero'),
    (N'ENG', 23, N'James', N'Trafford', N'2002-10-10', 1.97, 80, N'Derecha', N'Manchester City', N'Arquero'),  -- valor de ejemplo: peso
    (N'ENG', 24, N'Reece', N'James', N'1999-12-08', 1.79, 90.0, N'Derecha', N'Chelsea', N'Defensor'),
    (N'ENG', 25, N'Djed', N'Spence', N'2000-08-09', 1.85, 73, N'Derecha', N'Tottenham Hotspur', N'Defensor'),  -- valor de ejemplo: peso
    (N'ENG', 26, N'Jarell', N'Quansah', N'2003-01-29', 1.9, 75.0, N'Derecha', N'Bayer Leverkusen', N'Defensor'),
    (N'CRO', 1, N'Dominik', N'Livaković', N'1995-01-09', 1.86, 79.0, N'Derecha', N'Dinamo Zagreb', N'Arquero'),
    (N'CRO', 2, N'Josip', N'Stanišić', N'2000-04-02', 1.86, 78, N'Ambidiestro', N'Bayern Munich', N'Defensor'),  -- valor de ejemplo: peso
    (N'CRO', 3, N'Marin', N'Pongračić', N'1997-09-11', 1.93, 85.0, N'Derecha', N'Fiorentina', N'Defensor'),
    (N'CRO', 4, N'Joško', N'Gvardiol', N'2002-01-23', 1.85, 82, N'Izquierda', N'Manchester City', N'Defensor'),  -- valor de ejemplo: peso
    (N'CRO', 5, N'Duje', N'Ćaleta-Car', N'1996-09-17', 1.93, 89.0, N'Derecha', N'Real Sociedad', N'Defensor'),
    (N'CRO', 6, N'Josip', N'Šutalo', N'2000-02-28', 1.9, 82, N'Derecha', N'Ajax', N'Defensor'),  -- valor de ejemplo: peso
    (N'CRO', 7, N'Nikola', N'Moro', N'1998-03-12', 1.85, 77.0, N'Derecha', N'Bologna', N'Mediocampista'),
    (N'CRO', 8, N'Mateo', N'Kovačić', N'1994-05-06', 1.77, 75.0, N'Derecha', N'Manchester City', N'Mediocampista'),
    (N'CRO', 9, N'Andrej', N'Kramarić', N'1991-06-19', 1.8, 75.0, N'Derecha', N'TSG Hoffenheim', N'Delantero'),
    (N'CRO', 10, N'Luka', N'Modrić', N'1985-09-09', 1.74, 65.0, N'Derecha', N'AC Milan', N'Mediocampista'),
    (N'CRO', 11, N'Ante', N'Budimir', N'1991-07-22', 1.9, 75.0, N'Izquierda', N'Osasuna', N'Delantero'),
    (N'CRO', 12, N'Ivor', N'Pandur', N'2000-03-25', 1.87, 76.0, N'Derecha', N'Hull City', N'Arquero'),
    (N'CRO', 13, N'Nikola', N'Vlašić', N'1997-10-04', 1.78, 72.0, N'Derecha', N'Torino', N'Mediocampista'),
    (N'CRO', 14, N'Ivan', N'Perišić', N'1989-02-02', 1.86, 80.0, N'Ambidiestro', N'PSV Eindhoven', N'Delantero'),
    (N'CRO', 15, N'Mario', N'Pašalić', N'1995-02-09', 1.88, 82.0, N'Derecha', N'Atalanta', N'Mediocampista'),
    (N'CRO', 16, N'Martin', N'Baturina', N'2003-02-16', 1.72, 69, N'Derecha', N'Como', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'CRO', 17, N'Petar', N'Sučić', N'2003-10-25', 1.83, 76.0, N'Derecha', N'Inter Milan', N'Mediocampista'),
    (N'CRO', 18, N'Kristijan', N'Jakić', N'1997-05-14', 1.81, 76.0, N'Derecha', N'FC Augsburg', N'Defensor'),
    (N'CRO', 19, N'Toni', N'Fruk', N'2001-03-09', 1.74, 74, N'Izquierda', N'Rijeka', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'CRO', 20, N'Igor', N'Matanović', N'2003-03-31', 1.94, 93.0, N'Derecha', N'SC Freiburg', N'Delantero'),
    (N'CRO', 21, N'Luka', N'Sučić', N'2002-09-08', 1.85, 73, N'Izquierda', N'Real Sociedad', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'CRO', 22, N'Luka', N'Vušković', N'2007-02-24', 1.93, 86.0, N'Derecha', N'Hamburger SV', N'Defensor'),
    (N'CRO', 23, N'Dominik', N'Kotarski', N'2000-02-10', 1.89, 80, N'Derecha', N'Copenhagen', N'Arquero'),  -- valor de ejemplo: peso
    (N'CRO', 24, N'Marco', N'Pašalić', N'2000-09-14', 1.77, 80, N'Izquierda', N'Orlando City SC', N'Delantero'),  -- valor de ejemplo: peso
    (N'CRO', 25, N'Martin', N'Erlić', N'1998-01-24', 1.93, 88.0, N'Derecha', N'Midtjylland', N'Defensor'),
    (N'CRO', 26, N'Petar', N'Musa', N'1998-03-04', 1.9, 77, N'Derecha', N'FC Dallas', N'Delantero'),  -- valor de ejemplo: peso
    (N'GHA', 1, N'Lawrence', N'Ati-Zigi', N'1996-11-29', 1.88, 83.0, N'Derecha', N'St. Gallen', N'Arquero'),
    (N'GHA', 2, N'Alidu', N'Seidu', N'2000-06-04', 1.73, 68.0, N'Derecha', N'Rennes', N'Defensor'),
    (N'GHA', 3, N'Caleb', N'Yirenkyi', N'2006-01-15', 1.82, 77.0, N'Derecha', N'Nordsjælland', N'Mediocampista'),
    (N'GHA', 4, N'Jonas', N'Adjetey', N'2003-12-13', 1.88, 75, N'Derecha', N'VfL Wolfsburg', N'Defensor'),  -- valor de ejemplo: peso
    (N'GHA', 5, N'Thomas', N'Partey', N'1993-06-13', 1.85, 78.0, N'Derecha', N'Villarreal', N'Mediocampista'),
    (N'GHA', 6, N'Abdul', N'Mumin', N'1998-06-06', 1.88, 79.0, N'Derecha', N'Rayo Vallecano', N'Defensor'),
    (N'GHA', 7, N'Abdul', N'Fatawu', N'2004-03-08', 1.77, 73.0, N'Izquierda', N'Leicester City', N'Delantero'),
    (N'GHA', 8, N'Kwasi', N'Sibo', N'1998-06-24', 1.82, 75.0, N'Derecha', N'Oviedo', N'Mediocampista'),  -- valor de ejemplo: pie
    (N'GHA', 9, N'Jordan', N'Ayew', N'1991-09-11', 1.82, 81.0, N'Derecha', N'Leicester City', N'Delantero'),
    (N'GHA', 10, N'Brandon', N'Thomas-Asante', N'1998-12-29', 1.8, 80.0, N'Derecha', N'Coventry City', N'Delantero'),  -- valor de ejemplo: pie
    (N'GHA', 11, N'Antoine', N'Semenyo', N'2000-01-07', 1.85, 77, N'Derecha', N'Manchester City', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'GHA', 12, N'Joseph', N'Anang', N'2000-06-08', 1.9, 72.0, N'Derecha', N'St Patrick''s Athletic', N'Arquero'),
    (N'GHA', 13, N'Christopher', N'Bonsu Baah', N'2004-12-14', 1.72, 76, N'Izquierda', N'Al-Qadsiah', N'Delantero'),  -- valor de ejemplo: peso
    (N'GHA', 14, N'Gideon', N'Mensah', N'1998-07-18', 1.78, 70.0, N'Izquierda', N'Auxerre', N'Defensor'),
    (N'GHA', 15, N'Elisha', N'Owusu', N'1997-11-07', 1.82, 77, N'Derecha', N'Auxerre', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'GHA', 16, N'Benjamin', N'Asare', N'1992-07-13', 1.88, 78, N'Derecha', N'Hearts of Oak', N'Arquero'),  -- valor de ejemplo: peso, pie
    (N'GHA', 17, N'Abdul Rahman', N'Baba', N'1994-07-02', 1.79, 70.0, N'Izquierda', N'PAOK', N'Defensor'),
    (N'GHA', 18, N'Jerome', N'Opoku', N'1998-10-14', 1.94, 83, N'Izquierda', N'İstanbul Başakşehir', N'Defensor'),  -- valor de ejemplo: peso
    (N'GHA', 19, N'Iñaki', N'Williams', N'1994-06-15', 1.86, 77.0, N'Derecha', N'Athletic Bilbao', N'Delantero'),
    (N'GHA', 20, N'Augustine', N'Boakye', N'2000-11-03', 1.78, 70, N'Izquierda', N'Saint-Étienne', N'Mediocampista'),  -- valor de ejemplo: peso
    (N'GHA', 21, N'Kojo', N'Peprah Oppong', N'2004-06-04', 1.85, 74, N'Derecha', N'Nice', N'Defensor'),  -- valor de ejemplo: peso
    (N'GHA', 22, N'Kamaldeen', N'Sulemana', N'2002-02-15', 1.75, 80, N'Derecha', N'Atalanta', N'Delantero'),  -- valor de ejemplo: peso
    (N'GHA', 23, N'Derrick', N'Luckassen', N'1995-07-03', 1.86, 73, N'Derecha', N'Pafos', N'Defensor'),  -- valor de ejemplo: peso
    (N'GHA', 24, N'Ernest', N'Nuamah', N'2003-11-01', 1.78, 75, N'Izquierda', N'Lyon', N'Delantero'),  -- valor de ejemplo: peso
    (N'GHA', 25, N'Prince Kwabena', N'Adu', N'2003-09-23', 1.8, 77, N'Derecha', N'Viktoria Plzeň', N'Delantero'),  -- valor de ejemplo: peso
    (N'GHA', 26, N'Marvin', N'Senaya', N'2001-01-28', 1.81, 75, N'Derecha', N'Auxerre', N'Defensor'),  -- valor de ejemplo: peso
    (N'PAN', 1, N'Luis', N'Mejía', N'1991-03-16', 1.91, 75.0, N'Izquierda', N'Nacional', N'Arquero'),
    (N'PAN', 2, N'César', N'Blackman', N'1998-04-02', 1.74, 70.0, N'Derecha', N'Slovan Bratislava', N'Defensor'),
    (N'PAN', 3, N'José', N'Córdoba', N'2001-06-03', 1.87, 78.0, N'Izquierda', N'Norwich City', N'Defensor'),
    (N'PAN', 4, N'Fidel', N'Escobar', N'1995-01-09', 1.81, 74.0, N'Derecha', N'Saprissa', N'Defensor'),
    (N'PAN', 5, N'Edgardo', N'Fariña', N'2001-10-19', 1.94, 85.0, N'Derecha', N'Pari Nizhny Novgorod', N'Defensor'),
    (N'PAN', 6, N'Cristian', N'Martínez', N'1997-02-06', 1.7, 79.0, N'Derecha', N'Ironi Kiryat Shmona', N'Mediocampista'),  -- valor de ejemplo: pie
    (N'PAN', 7, N'José Luis', N'Rodríguez', N'1998-06-19', 1.8, 77.0, N'Izquierda', N'Juárez', N'Mediocampista'),
    (N'PAN', 8, N'Adalberto', N'Carrasquilla', N'1998-11-28', 1.7, 64.0, N'Derecha', N'Pumas UNAM', N'Mediocampista'),
    (N'PAN', 9, N'Tomás', N'Rodríguez', N'1999-03-09', 1.83, 75.0, N'Derecha', N'Saprissa', N'Delantero'),  -- valor de ejemplo: pie
    (N'PAN', 10, N'Ismael', N'Díaz', N'1997-05-12', 1.82, 77.0, N'Derecha', N'León', N'Mediocampista'),
    (N'PAN', 11, N'Yoel', N'Bárcenas', N'1993-10-23', 1.75, 75.0, N'Derecha', N'Mazatlán', N'Mediocampista'),  -- valor de ejemplo: pie
    (N'PAN', 12, N'César', N'Samudio', N'1994-02-23', 1.88, 88.0, N'Izquierda', N'Marathón', N'Arquero'),  -- valor de ejemplo: pie
    (N'PAN', 13, N'Jiovany', N'Ramos', N'1997-01-26', 1.89, 75.0, N'Derecha', N'Puerto Cabello', N'Defensor'),  -- valor de ejemplo: pie
    (N'PAN', 14, N'Carlos', N'Harvey', N'2000-02-03', 1.84, 82.0, N'Derecha', N'Minnesota United FC', N'Defensor'),  -- valor de ejemplo: pie
    (N'PAN', 15, N'Eric', N'Davis', N'1991-03-31', 1.79, 77.0, N'Izquierda', N'Plaza Amador', N'Defensor'),
    (N'PAN', 16, N'Andrés', N'Andrade', N'1998-10-16', 1.87, 87.0, N'Izquierda', N'LASK', N'Defensor'),
    (N'PAN', 17, N'José', N'Fajardo', N'1993-08-18', 1.8, 68.0, N'Izquierda', N'Universidad Católica', N'Delantero'),  -- valor de ejemplo: pie
    (N'PAN', 18, N'Cecilio', N'Waterman', N'1991-04-13', 1.81, 81.0, N'Derecha', N'Universidad de Concepción', N'Delantero'),  -- valor de ejemplo: pie
    (N'PAN', 19, N'Alberto', N'Quintero', N'1987-12-18', 1.67, 60.0, N'Derecha', N'Plaza Amador', N'Mediocampista'),
    (N'PAN', 20, N'Aníbal', N'Godoy', N'1990-02-10', 1.82, 79.0, N'Izquierda', N'San Diego FC', N'Mediocampista'),
    (N'PAN', 21, N'César', N'Yanis', N'1996-01-28', 1.7, 70, N'Derecha', N'Cobresal', N'Mediocampista'),  -- valor de ejemplo: peso, pie
    (N'PAN', 22, N'Orlando', N'Mosquera', N'1994-12-25', 1.91, 79.0, N'Derecha', N'Al-Fayha', N'Arquero'),
    (N'PAN', 23, N'Michael Amir', N'Murillo', N'1996-02-11', 1.83, 80.0, N'Derecha', N'Beşiktaş', N'Defensor'),
    (N'PAN', 24, N'Azarias', N'Londoño', N'2001-06-21', 1.85, 70.0, N'Izquierda', N'Universidad Católica', N'Delantero'),  -- valor de ejemplo: pie
    (N'PAN', 25, N'Roderick', N'Miller', N'1992-04-03', 1.89, 94.0, N'Izquierda', N'Turan Tovuz', N'Defensor'),
    (N'PAN', 26, N'Jorge', N'Gutiérrez', N'1998-09-01', 1.71, 63.0, N'Izquierda', N'Deportivo La Guaira', N'Defensor');

DECLARE @idSel int, @idJug int, @dorsal tinyint, @nombre nvarchar(60), @apellido nvarchar(60),
        @nacimiento date, @altura decimal(5,2), @peso decimal(5,2), @pierna varchar(15),
        @club nvarchar(80), @posicion varchar(15);
DECLARE @n int = 1, @max int = (SELECT MAX(n) FROM #convocados);
WHILE @n <= @max
BEGIN
    SELECT @idSel = s.id, @dorsal = c.dorsal, @nombre = c.nombre, @apellido = c.apellido,
           @nacimiento = c.fechaNacimiento, @altura = c.altura, @peso = c.peso, @pierna = c.piernaHabil,
           @club = c.club, @posicion = c.posicion
    FROM #convocados c JOIN Equipos.Seleccion s ON s.abreviacion = c.seleccion WHERE c.n = @n;
    BEGIN TRY
        SET @idJug = (SELECT id FROM Equipos.Jugador
                      WHERE nombre = @nombre AND apellido = @apellido AND fechaNacimiento = @nacimiento);
        IF @idJug IS NULL
            EXEC Equipos.Jugador_Alta @nombre = @nombre, @apellido = @apellido, @fechaNacimiento = @nacimiento,
                 @altura = @altura, @peso = @peso, @piernaHabil = @pierna, @club = @club,
                 @posicion = @posicion, @id = @idJug OUTPUT;
        IF NOT EXISTS (SELECT 1 FROM Equipos.ListadoJugadores WHERE idJugador = @idJug AND idSeleccion = @idSel)
            EXEC Equipos.ListadoJugadores_Alta @idSeleccion = @idSel, @idJugador = @idJug,
                 @dorsal = @dorsal, @fechaAlta = '2026-06-01';
    END TRY
    BEGIN CATCH
        PRINT 'Error al cargar el convocado de la fila ' + CAST(@n AS varchar(10)) + ' de #convocados.';
        THROW;
    END CATCH;
    SET @n += 1;
END;
GO

-- Resumen de la carga
SELECT (SELECT COUNT(*) FROM Equipos.Seleccion) AS selecciones,
       (SELECT COUNT(*) FROM Equipos.ListadoJugadores WHERE fechaBaja IS NULL) AS convocadosActivos,
       (SELECT COUNT(*) FROM Equipos.Staff) AS cuerpoTecnico;
GO
