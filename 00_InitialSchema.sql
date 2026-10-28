/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900

 Integrantes : Pereira, Marcos Nahuel - 45066788
               Salas, Martin Daniel - 45205702
               Zito Padró, Ezequiel Nehuén - 46097917

 Fecha       : 11/10/2026

 Objetivo    : Crear la base de datos, los esquemas y todas las tablas del sistema con sus claves primarias,
               claves foráneas, restricciones UNIQUE, CHECK y DEFAULT, y los
               índices únicos filtrados.
               Crea primero la base de datos y los esquemas.
               El script puede ejecutarse varias veces: cada objeto se crea
               solo si no existe.

 Esquemas
 --------
   Torneo     -> países, sedes, fases, períodos y partidos
   Equipos    -> selecciones, jugadores, staff y convocatorias
   Arbitraje  -> árbitros, idiomas, designaciones por partido e informes
   Eventos    -> formaciones, goles, tarjetas, sustituciones y suspensiones
   Publicidad -> anunciantes, campañas, piezas, tarifas, exhibiciones,
                 tipos de cambio y feriados
   Sistema    -> parámetros de reglamento y registro de errores de importación

 Norma de nomenclatura
 ---------------------
   Tablas            PascalCase, en singular, dentro de su esquema
                     (Torneo.Partido, Publicidad.Tarifa)
   Columnas          camelCase (fechaHoraUTC, idSeleccionLocal)
   Claves foráneas   id + nombre de la entidad referenciada (idPais, idPartido)
   Primary key       PK_<Tabla>
   Foreign key       FK_<Tabla>_<Referencia>        (FK_Sede_Pais)
                     FK_<Tabla>_<Rol> cuando hay más de una FK a la misma
                     tabla                          (FK_Partido_SeleccionLocal)
   Unique            UQ_<Tabla>_<Columnas>
   Check             CK_<Tabla>_<Regla>
   Default           DF_<Tabla>_<Columna>
   Índice único      UX_<Tabla>_<Descripcion>
================================================================================
*/

/* =============================================================================
   BASE DE DATOS Y ESQUEMAS
   ============================================================================= */

USE master;
GO

IF DB_ID(N'MundialFutbol') IS NULL
    CREATE DATABASE MundialFutbol;
GO

USE MundialFutbol;
GO

/*
 CREATE SCHEMA tiene que ser la única instrucción de su lote, por eso no puede
 ir dentro de un IF. Se usa EXEC solo en este caso: es la forma estándar de
 crear un esquema condicionalmente y no hay alternativa sin SQL dinámico.
*/
IF SCHEMA_ID(N'Torneo') IS NULL
    EXEC (N'CREATE SCHEMA Torneo');
GO

IF SCHEMA_ID(N'Equipos') IS NULL
    EXEC (N'CREATE SCHEMA Equipos');
GO

IF SCHEMA_ID(N'Arbitraje') IS NULL
    EXEC (N'CREATE SCHEMA Arbitraje');
GO

IF SCHEMA_ID(N'Eventos') IS NULL
    EXEC (N'CREATE SCHEMA Eventos');
GO

IF SCHEMA_ID(N'Publicidad') IS NULL
    EXEC (N'CREATE SCHEMA Publicidad');
GO

IF SCHEMA_ID(N'Sistema') IS NULL
    EXEC (N'CREATE SCHEMA Sistema');
GO

-- Necesarios para crear índices filtrados
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* =============================================================================
   ESQUEMA TORNEO
   ============================================================================= */

IF OBJECT_ID(N'Torneo.Pais', N'U') IS NULL
BEGIN
    CREATE TABLE Torneo.Pais (
        id            int IDENTITY(1,1) NOT NULL,
        nombre        nvarchar(60)      NOT NULL,
        codigoISO2    char(2)           NOT NULL,
        codigoISO3    char(3)           NOT NULL,
        husoHorario   varchar(50)       NULL,
        moneda        char(3)           NULL,
        pbiPerCapita  decimal(12,2)     NULL,
        poblacion     bigint            NULL,

        CONSTRAINT PK_Pais              PRIMARY KEY (id),
        CONSTRAINT UQ_Pais_Nombre       UNIQUE (nombre),
        CONSTRAINT UQ_Pais_CodigoISO2   UNIQUE (codigoISO2),
        CONSTRAINT UQ_Pais_CodigoISO3   UNIQUE (codigoISO3),
        CONSTRAINT CK_Pais_PbiPositivo  CHECK (pbiPerCapita IS NULL OR pbiPerCapita >= 0),
        CONSTRAINT CK_Pais_Poblacion    CHECK (poblacion IS NULL OR poblacion >= 0)
    );
END
GO

IF OBJECT_ID(N'Torneo.Fase', N'U') IS NULL
BEGIN
    CREATE TABLE Torneo.Fase (
        idFase          int          NOT NULL,   -- catálogo: ids controlados a mano
        nombre          varchar(60)  NOT NULL,
        esEliminatoria  bit          NOT NULL,
        orden           int          NOT NULL,   -- 1 = grupos, 2 = dieciseisavos, ...

        CONSTRAINT PK_Fase              PRIMARY KEY (idFase),
        CONSTRAINT UQ_Fase_Nombre       UNIQUE (nombre),
        CONSTRAINT CK_Fase_OrdenPositivo CHECK (orden > 0)
    );
END
GO

IF OBJECT_ID(N'Torneo.Periodo', N'U') IS NULL
BEGIN
    CREATE TABLE Torneo.Periodo (
        idPeriodo  tinyint      NOT NULL,        -- catálogo: ids controlados a mano
        nombre     varchar(30)  NOT NULL,
        orden      tinyint      NOT NULL,

        CONSTRAINT PK_Periodo          PRIMARY KEY (idPeriodo),
        CONSTRAINT UQ_Periodo_Nombre   UNIQUE (nombre),
        CONSTRAINT UQ_Periodo_Orden    UNIQUE (orden)
    );
END
GO

IF OBJECT_ID(N'Torneo.Sede', N'U') IS NULL
BEGIN
    CREATE TABLE Torneo.Sede (
        idSede         int IDENTITY(1,1) NOT NULL,
        nombreEstadio  nvarchar(80)      NOT NULL,
        ciudad         nvarchar(60)      NOT NULL,
        idPais         int               NOT NULL,
        capacidad      int               NULL,
        husoHorario    varchar(50)       NOT NULL,   -- nombre de zona de Windows (sys.time_zone_info)
        latitud        decimal(9,6)      NULL,
        longitud       decimal(9,6)      NULL,

        CONSTRAINT PK_Sede                 PRIMARY KEY (idSede),
        CONSTRAINT FK_Sede_Pais            FOREIGN KEY (idPais) REFERENCES Torneo.Pais (id),
        CONSTRAINT UQ_Sede_EstadioCiudad   UNIQUE (nombreEstadio, ciudad),
        CONSTRAINT CK_Sede_Capacidad       CHECK (capacidad IS NULL OR capacidad > 0),
        CONSTRAINT CK_Sede_Latitud         CHECK (latitud  IS NULL OR latitud  BETWEEN -90  AND 90),
        CONSTRAINT CK_Sede_Longitud        CHECK (longitud IS NULL OR longitud BETWEEN -180 AND 180)
    );
END
GO

/* =============================================================================
   ESQUEMA EQUIPOS (Seleccion se crea antes que Partido porque Partido la referencia)
   ============================================================================= */

IF OBJECT_ID(N'Equipos.Seleccion', N'U') IS NULL
BEGIN
    CREATE TABLE Equipos.Seleccion (
        id                int IDENTITY(1,1) NOT NULL,
        idPais            int               NOT NULL,
        confederacion     varchar(10)       NULL,
        nombreAsociacion  nvarchar(100)     NULL,
        abreviacion       char(3)           NULL,   -- código FIFA (ARG, GER, NED...)
        grupo             char(1)           NULL,

        CONSTRAINT PK_Seleccion              PRIMARY KEY (id),
        CONSTRAINT FK_Seleccion_Pais         FOREIGN KEY (idPais) REFERENCES Torneo.Pais (id),
        CONSTRAINT UQ_Seleccion_Pais         UNIQUE (idPais),
        CONSTRAINT CK_Seleccion_Confederacion CHECK (confederacion IS NULL OR
                   confederacion IN ('AFC', 'CAF', 'CONCACAF', 'CONMEBOL', 'OFC', 'UEFA')),
        CONSTRAINT CK_Seleccion_Grupo        CHECK (grupo IS NULL OR grupo LIKE '[A-L]')
    );
END
GO

IF OBJECT_ID(N'Equipos.Jugador', N'U') IS NULL
BEGIN
    CREATE TABLE Equipos.Jugador (
        id               int IDENTITY(1,1) NOT NULL,
        nombre           nvarchar(60)      NOT NULL,
        apellido         nvarchar(60)      NOT NULL,
        fechaNacimiento  date              NULL,
        altura           decimal(5,2)      NULL,   -- en metros
        peso             decimal(5,2)      NULL,   -- en kg
        piernaHabil      varchar(15)       NULL,
        club             nvarchar(80)      NULL,
        posicion         varchar(15)       NULL,   -- posición habitual

        CONSTRAINT PK_Jugador              PRIMARY KEY (id),
        CONSTRAINT CK_Jugador_PiernaHabil  CHECK (piernaHabil IS NULL OR
                   piernaHabil IN ('Izquierda', 'Derecha', 'Ambidiestro')),
        CONSTRAINT CK_Jugador_Posicion     CHECK (posicion IS NULL OR
                   posicion IN ('Arquero', 'Defensor', 'Mediocampista', 'Delantero')),
        CONSTRAINT CK_Jugador_Altura       CHECK (altura IS NULL OR altura BETWEEN 1.40 AND 2.20),
        CONSTRAINT CK_Jugador_Peso         CHECK (peso   IS NULL OR peso   BETWEEN 40   AND 130)
    );
END
GO

IF OBJECT_ID(N'Equipos.Staff', N'U') IS NULL
BEGIN
    CREATE TABLE Equipos.Staff (
        id               int IDENTITY(1,1) NOT NULL,
        idSeleccion      int               NOT NULL,
        nombre           nvarchar(60)      NOT NULL,
        apellido         nvarchar(60)      NOT NULL,
        fechaNacimiento  date              NULL,
        rol              varchar(20)       NOT NULL,

        CONSTRAINT PK_Staff            PRIMARY KEY (id),
        CONSTRAINT FK_Staff_Seleccion  FOREIGN KEY (idSeleccion) REFERENCES Equipos.Seleccion (id),
        CONSTRAINT CK_Staff_Rol        CHECK (rol IN ('Director Principal', 'Ayudante', 'Preparador Fisico', 'Medico'))
    );
END
GO

/* =============================================================================
   PARTIDO (esquema Torneo; se crea acá porque depende de Equipos.Seleccion)
   ============================================================================= */

IF OBJECT_ID(N'Torneo.Partido', N'U') IS NULL
BEGIN
    CREATE TABLE Torneo.Partido (
        idPartido             int IDENTITY(1,1) NOT NULL,
        nroPartidoOficial     int               NULL,       -- número de partido FIFA, clave natural para el upsert
        idSede                int               NOT NULL,
        idSeleccionLocal      int               NOT NULL,
        idSeleccionVisitante  int               NOT NULL,
        fase                  int               NOT NULL,
        fechaHoraUTC          datetime2(0)      NOT NULL,   -- la hora local se calcula con AT TIME ZONE
        estado                varchar(15)       NOT NULL,
        cantPublico           int               NULL,
        golVisitante          tinyint           NULL,
        golLocal              tinyint           NULL,
        esquemaLocal          varchar(10)       NULL,       -- '4-3-3', '4-2-3-1'...
        esquemaVisitante      varchar(10)       NULL,

        CONSTRAINT PK_Partido                      PRIMARY KEY (idPartido),
        CONSTRAINT FK_Partido_Sede                 FOREIGN KEY (idSede)               REFERENCES Torneo.Sede (idSede),
        CONSTRAINT FK_Partido_SeleccionLocal       FOREIGN KEY (idSeleccionLocal)     REFERENCES Equipos.Seleccion (id),
        CONSTRAINT FK_Partido_SeleccionVisitante   FOREIGN KEY (idSeleccionVisitante) REFERENCES Equipos.Seleccion (id),
        CONSTRAINT FK_Partido_Fase                 FOREIGN KEY (fase)                 REFERENCES Torneo.Fase (idFase),
        CONSTRAINT CK_Partido_SeleccionesDistintas CHECK (idSeleccionLocal <> idSeleccionVisitante),
        CONSTRAINT CK_Partido_Estado               CHECK (estado IN ('Programado', 'En juego', 'Finalizado', 'Suspendido')),
        CONSTRAINT CK_Partido_FinalizadoConResultado CHECK (estado <> 'Finalizado' OR
                   (golLocal IS NOT NULL AND golVisitante IS NOT NULL)),
        CONSTRAINT CK_Partido_CantPublico          CHECK (cantPublico IS NULL OR cantPublico >= 0),
        CONSTRAINT CK_Partido_NroPartidoOficial    CHECK (nroPartidoOficial IS NULL OR nroPartidoOficial > 0)
    );
END
GO

-- El número oficial no se repite, pero puede faltar (por eso índice filtrado y no UNIQUE,
-- que en SQL Server admite un solo NULL)
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'UX_Partido_NroPartidoOficial'
                 AND object_id = OBJECT_ID(N'Torneo.Partido'))
    CREATE UNIQUE INDEX UX_Partido_NroPartidoOficial
        ON Torneo.Partido (nroPartidoOficial)
        WHERE nroPartidoOficial IS NOT NULL;
GO

IF OBJECT_ID(N'Equipos.ListadoJugadores', N'U') IS NULL
BEGIN
    CREATE TABLE Equipos.ListadoJugadores (
        id            int IDENTITY(1,1) NOT NULL,
        idSeleccion   int               NOT NULL,
        idJugador     int               NOT NULL,
        fechaAlta     date              NOT NULL,
        fechaBaja     date              NULL,       -- NULL = sigue convocado
        motivoBaja    varchar(100)      NULL,
        dorsal        tinyint           NOT NULL,
        idReemplazaA  int               NULL,       -- a quién reemplaza (ej. por lesión)

        CONSTRAINT PK_ListadoJugadores             PRIMARY KEY (id),
        CONSTRAINT FK_ListadoJugadores_Seleccion   FOREIGN KEY (idSeleccion)  REFERENCES Equipos.Seleccion (id),
        CONSTRAINT FK_ListadoJugadores_Jugador     FOREIGN KEY (idJugador)    REFERENCES Equipos.Jugador (id),
        CONSTRAINT FK_ListadoJugadores_Reemplazo   FOREIGN KEY (idReemplazaA) REFERENCES Equipos.ListadoJugadores (id),
        CONSTRAINT CK_ListadoJugadores_Dorsal      CHECK (dorsal BETWEEN 1 AND 99),
        CONSTRAINT CK_ListadoJugadores_Fechas      CHECK (fechaBaja IS NULL OR fechaBaja >= fechaAlta),
        CONSTRAINT CK_ListadoJugadores_MotivoBaja  CHECK (fechaBaja IS NULL OR motivoBaja IS NOT NULL),
        CONSTRAINT CK_ListadoJugadores_NoSeReemplazaASiMismo CHECK (idReemplazaA IS NULL OR idReemplazaA <> id)
    );
END
GO

-- Dos convocados activos de la misma selección no pueden compartir dorsal
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'UX_ListadoJugadores_DorsalActivo'
                 AND object_id = OBJECT_ID(N'Equipos.ListadoJugadores'))
    CREATE UNIQUE INDEX UX_ListadoJugadores_DorsalActivo
        ON Equipos.ListadoJugadores (idSeleccion, dorsal)
        WHERE fechaBaja IS NULL;
GO

-- Un jugador no puede estar convocado activo en dos selecciones a la vez
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'UX_ListadoJugadores_JugadorActivo'
                 AND object_id = OBJECT_ID(N'Equipos.ListadoJugadores'))
    CREATE UNIQUE INDEX UX_ListadoJugadores_JugadorActivo
        ON Equipos.ListadoJugadores (idJugador)
        WHERE fechaBaja IS NULL;
GO

/* =============================================================================
   ESQUEMA ARBITRAJE
   ============================================================================= */

IF OBJECT_ID(N'Arbitraje.Arbitro', N'U') IS NULL
BEGIN
    CREATE TABLE Arbitraje.Arbitro (
        idArbitro           int IDENTITY(1,1) NOT NULL,
        idPais              int               NOT NULL,
        nombre              nvarchar(60)      NOT NULL,
        apellido            nvarchar(60)      NOT NULL,
        categoria           varchar(15)       NOT NULL,   -- FIFA o Confederacion
        genero              varchar(20)       NULL,
        fechaInternacional  date              NULL,

        CONSTRAINT PK_Arbitro            PRIMARY KEY (idArbitro),
        CONSTRAINT FK_Arbitro_Pais       FOREIGN KEY (idPais) REFERENCES Torneo.Pais (id),
        CONSTRAINT CK_Arbitro_Categoria  CHECK (categoria IN ('FIFA', 'Confederacion'))
    );
END
GO

IF OBJECT_ID(N'Arbitraje.ArbitroIdioma', N'U') IS NULL
BEGIN
    CREATE TABLE Arbitraje.ArbitroIdioma (
        idArbitro  int      NOT NULL,
        idioma     char(2)  NOT NULL,   -- ISO 639-1: 'es', 'en', 'fr'

        CONSTRAINT PK_ArbitroIdioma          PRIMARY KEY (idArbitro, idioma),
        CONSTRAINT FK_ArbitroIdioma_Arbitro  FOREIGN KEY (idArbitro) REFERENCES Arbitraje.Arbitro (idArbitro),
        CONSTRAINT CK_ArbitroIdioma_Codigo   CHECK (idioma LIKE '[a-z][a-z]')
    );
END
GO

IF OBJECT_ID(N'Arbitraje.cuerpoArbitral', N'U') IS NULL
BEGIN
    CREATE TABLE Arbitraje.cuerpoArbitral (
        id         int IDENTITY(1,1) NOT NULL,
        idArbitro  int               NOT NULL,
        idPartido  int               NOT NULL,
        rol        varchar(15)       NOT NULL,

        CONSTRAINT PK_cuerpoArbitral                PRIMARY KEY (id),
        CONSTRAINT FK_cuerpoArbitral_Arbitro        FOREIGN KEY (idArbitro) REFERENCES Arbitraje.Arbitro (idArbitro),
        CONSTRAINT FK_cuerpoArbitral_Partido        FOREIGN KEY (idPartido) REFERENCES Torneo.Partido (idPartido),
        CONSTRAINT UQ_cuerpoArbitral_PartidoRol     UNIQUE (idPartido, rol),        -- un árbitro por rol
        CONSTRAINT UQ_cuerpoArbitral_PartidoArbitro UNIQUE (idPartido, idArbitro),  -- un rol por árbitro
        CONSTRAINT CK_cuerpoArbitral_Rol            CHECK (rol IN ('Principal', 'Asistente 1', 'Asistente 2', 'Cuarto Arbitro', 'VAR'))
    );
END
GO

-- Sanciones e informes post-partido que recibe cada árbitro (módulo G)
IF OBJECT_ID(N'Arbitraje.InformeArbitral', N'U') IS NULL
BEGIN
    CREATE TABLE Arbitraje.InformeArbitral (
        id          int IDENTITY(1,1) NOT NULL,
        idPartido   int               NOT NULL,
        idArbitro   int               NOT NULL,
        fecha       date              NOT NULL,
        esSancion   bit               NOT NULL,   -- 1 = sanción, 0 = informe
        detalle     nvarchar(500)     NULL,

        CONSTRAINT PK_InformeArbitral          PRIMARY KEY (id),
        CONSTRAINT FK_InformeArbitral_Partido  FOREIGN KEY (idPartido) REFERENCES Torneo.Partido (idPartido),
        CONSTRAINT FK_InformeArbitral_Arbitro  FOREIGN KEY (idArbitro) REFERENCES Arbitraje.Arbitro (idArbitro)
    );
END
GO

/* =============================================================================
   ESQUEMA EVENTOS
   ============================================================================= */

IF OBJECT_ID(N'Eventos.FormacionPartido', N'U') IS NULL
BEGIN
    CREATE TABLE Eventos.FormacionPartido (
        id           int IDENTITY(1,1) NOT NULL,
        idPartido    int               NOT NULL,
        idSeleccion  int               NOT NULL,
        idJugador    int               NOT NULL,
        titular      bit               NOT NULL,   -- 1 = titular, 0 = suplente
        posicion     varchar(15)       NULL,

        CONSTRAINT PK_FormacionPartido                PRIMARY KEY (id),
        CONSTRAINT FK_FormacionPartido_Partido        FOREIGN KEY (idPartido)   REFERENCES Torneo.Partido (idPartido),
        CONSTRAINT FK_FormacionPartido_Seleccion      FOREIGN KEY (idSeleccion) REFERENCES Equipos.Seleccion (id),
        CONSTRAINT FK_FormacionPartido_Jugador        FOREIGN KEY (idJugador)   REFERENCES Equipos.Jugador (id),
        CONSTRAINT UQ_FormacionPartido_PartidoJugador UNIQUE (idPartido, idJugador),
        CONSTRAINT CK_FormacionPartido_Posicion       CHECK (posicion IS NULL OR
                   posicion IN ('Arquero', 'Defensor', 'Mediocampista', 'Delantero'))
    );
END
GO

IF OBJECT_ID(N'Eventos.Gol', N'U') IS NULL
BEGIN
    CREATE TABLE Eventos.Gol (
        idGol            int IDENTITY(1,1) NOT NULL,
        idPartido        int               NOT NULL,
        idJugador        int               NOT NULL,
        idAsistidor      int               NULL,
        minuto           tinyint           NULL,    -- NULL en la definición por penales
        minutoAdicional  tinyint           NULL,    -- el "2" de 45+2
        tipo             varchar(20)       NOT NULL,
        idPeriodo        tinyint           NOT NULL,

        CONSTRAINT PK_Gol                    PRIMARY KEY (idGol),
        CONSTRAINT FK_Gol_Partido            FOREIGN KEY (idPartido)   REFERENCES Torneo.Partido (idPartido),
        CONSTRAINT FK_Gol_Jugador            FOREIGN KEY (idJugador)   REFERENCES Equipos.Jugador (id),
        CONSTRAINT FK_Gol_Asistidor          FOREIGN KEY (idAsistidor) REFERENCES Equipos.Jugador (id),
        CONSTRAINT FK_Gol_Periodo            FOREIGN KEY (idPeriodo)   REFERENCES Torneo.Periodo (idPeriodo),
        CONSTRAINT CK_Gol_AsistidorDistinto  CHECK (idAsistidor IS NULL OR idAsistidor <> idJugador),
        CONSTRAINT CK_Gol_Minuto             CHECK (minuto IS NULL OR minuto BETWEEN 0 AND 120),
        CONSTRAINT CK_Gol_MinutoAdicional    CHECK (minutoAdicional IS NULL OR minuto IN (45, 90, 105, 120))
    );
END
GO

IF OBJECT_ID(N'Eventos.Tarjeta', N'U') IS NULL
BEGIN
    CREATE TABLE Eventos.Tarjeta (
        idTarjeta        int IDENTITY(1,1) NOT NULL,
        idPartido        int               NOT NULL,
        idJugador        int               NULL,
        idStaff          int               NULL,
        idPeriodo        tinyint           NOT NULL,
        color            char(1)           NOT NULL,   -- 'A' amarilla, 'R' roja
        minuto           tinyint           NOT NULL,
        minutoAdicional  tinyint           NULL,
        motivo           varchar(80)       NULL,
        tipoRoja         varchar(15)       NULL,       -- NULL si es amarilla

        CONSTRAINT PK_Tarjeta                 PRIMARY KEY (idTarjeta),
        CONSTRAINT FK_Tarjeta_Partido         FOREIGN KEY (idPartido) REFERENCES Torneo.Partido (idPartido),
        CONSTRAINT FK_Tarjeta_Jugador         FOREIGN KEY (idJugador) REFERENCES Equipos.Jugador (id),
        CONSTRAINT FK_Tarjeta_Staff           FOREIGN KEY (idStaff)   REFERENCES Equipos.Staff (id),
        CONSTRAINT FK_Tarjeta_Periodo         FOREIGN KEY (idPeriodo) REFERENCES Torneo.Periodo (idPeriodo),
        -- exactamente uno de los dos: la tarjeta es de un jugador o de un integrante del staff
        CONSTRAINT CK_Tarjeta_JugadorOStaff   CHECK ((idJugador IS NOT NULL AND idStaff IS NULL)
                                                  OR (idJugador IS NULL AND idStaff IS NOT NULL)),
        CONSTRAINT CK_Tarjeta_Color           CHECK (color IN ('A', 'R')),
        CONSTRAINT CK_Tarjeta_TipoRoja        CHECK ((color = 'A' AND tipoRoja IS NULL)
                                                  OR (color = 'R' AND tipoRoja IN ('Directa', 'Doble amarilla'))),
        CONSTRAINT CK_Tarjeta_Minuto          CHECK (minuto BETWEEN 0 AND 120),
        CONSTRAINT CK_Tarjeta_MinutoAdicional CHECK (minutoAdicional IS NULL OR minuto IN (45, 90, 105, 120))
    );
END
GO

IF OBJECT_ID(N'Eventos.Sustitucion', N'U') IS NULL
BEGIN
    CREATE TABLE Eventos.Sustitucion (
        id               int IDENTITY(1,1) NOT NULL,
        idPartido        int               NOT NULL,
        idIngresa        int               NOT NULL,
        idSale           int               NOT NULL,
        idPeriodo        tinyint           NOT NULL,
        minuto           tinyint           NOT NULL,
        minutoAdicional  tinyint           NULL,
        motivo           varchar(15)       NOT NULL,

        CONSTRAINT PK_Sustitucion                  PRIMARY KEY (id),
        CONSTRAINT FK_Sustitucion_Partido          FOREIGN KEY (idPartido) REFERENCES Torneo.Partido (idPartido),
        CONSTRAINT FK_Sustitucion_JugadorIngresa   FOREIGN KEY (idIngresa) REFERENCES Equipos.Jugador (id),
        CONSTRAINT FK_Sustitucion_JugadorSale      FOREIGN KEY (idSale)    REFERENCES Equipos.Jugador (id),
        CONSTRAINT FK_Sustitucion_Periodo          FOREIGN KEY (idPeriodo) REFERENCES Torneo.Periodo (idPeriodo),
        CONSTRAINT CK_Sustitucion_JugadoresDistintos CHECK (idIngresa <> idSale),
        CONSTRAINT CK_Sustitucion_Motivo           CHECK (motivo IN ('Tactico', 'Lesion', 'Precaucion')),
        CONSTRAINT CK_Sustitucion_Minuto           CHECK (minuto BETWEEN 0 AND 120),
        CONSTRAINT CK_Sustitucion_MinutoAdicional  CHECK (minutoAdicional IS NULL OR minuto IN (45, 90, 105, 120))
    );
END
GO

IF OBJECT_ID(N'Eventos.Suspension', N'U') IS NULL
BEGIN
    CREATE TABLE Eventos.Suspension (
        id                 int IDENTITY(1,1) NOT NULL,
        idPartido          int               NOT NULL,   -- partido donde se generó la suspensión
        idJugador          int               NULL,
        idStaff            int               NULL,
        cantPartidos       tinyint           NOT NULL,
        partidosRestantes  tinyint           NOT NULL,

        CONSTRAINT PK_Suspension                PRIMARY KEY (id),
        CONSTRAINT FK_Suspension_Partido        FOREIGN KEY (idPartido) REFERENCES Torneo.Partido (idPartido),
        CONSTRAINT FK_Suspension_Jugador        FOREIGN KEY (idJugador) REFERENCES Equipos.Jugador (id),
        CONSTRAINT FK_Suspension_Staff          FOREIGN KEY (idStaff)   REFERENCES Equipos.Staff (id),
        -- exactamente uno de los dos: la suspensión es de un jugador o de un integrante del staff
        CONSTRAINT CK_Suspension_JugadorOStaff  CHECK ((idJugador IS NOT NULL AND idStaff IS NULL)
                                                    OR (idJugador IS NULL AND idStaff IS NOT NULL)),
        CONSTRAINT CK_Suspension_CantPartidos   CHECK (cantPartidos > 0),
        CONSTRAINT CK_Suspension_Restantes      CHECK (partidosRestantes <= cantPartidos)
    );
END
GO

/* =============================================================================
   ESQUEMA PUBLICIDAD
   ============================================================================= */

IF OBJECT_ID(N'Publicidad.Anunciante', N'U') IS NULL
BEGIN
    CREATE TABLE Publicidad.Anunciante (
        id                 int IDENTITY(1,1) NOT NULL,
        nombre             nvarchar(100)     NOT NULL,
        rubro              varchar(50)       NULL,
        idPais             int               NOT NULL,
        monedaFacturacion  char(3)           NOT NULL
            CONSTRAINT DF_Anunciante_MonedaFacturacion DEFAULT ('USD'),

        CONSTRAINT PK_Anunciante         PRIMARY KEY (id),
        CONSTRAINT FK_Anunciante_Pais    FOREIGN KEY (idPais) REFERENCES Torneo.Pais (id),
        CONSTRAINT UQ_Anunciante_Nombre  UNIQUE (nombre)
    );
END
GO

IF OBJECT_ID(N'Publicidad.Campania', N'U') IS NULL
BEGIN
    CREATE TABLE Publicidad.Campania (
        idCampania    int IDENTITY(1,1) NOT NULL,
        idAnunciante  int               NOT NULL,
        nombre        nvarchar(60)      NOT NULL,
        fechaInicio   date              NOT NULL,
        fechaFin      date              NOT NULL,

        CONSTRAINT PK_Campania             PRIMARY KEY (idCampania),
        CONSTRAINT FK_Campania_Anunciante  FOREIGN KEY (idAnunciante) REFERENCES Publicidad.Anunciante (id),
        CONSTRAINT CK_Campania_Fechas      CHECK (fechaFin >= fechaInicio)
    );
END
GO

IF OBJECT_ID(N'Publicidad.PiezaContenido', N'U') IS NULL
BEGIN
    CREATE TABLE Publicidad.PiezaContenido (
        id           int IDENTITY(1,1) NOT NULL,
        idCampania   int               NOT NULL,
        descripcion  nvarchar(80)      NOT NULL,
        idioma       char(2)           NOT NULL,   -- ISO 639-1: 'es', 'en', 'pt'

        CONSTRAINT PK_PiezaContenido           PRIMARY KEY (id),
        CONSTRAINT FK_PiezaContenido_Campania  FOREIGN KEY (idCampania) REFERENCES Publicidad.Campania (idCampania),
        CONSTRAINT CK_PiezaContenido_Idioma    CHECK (idioma LIKE '[a-z][a-z]')
    );
END
GO

IF OBJECT_ID(N'Publicidad.PiezaMercado', N'U') IS NULL
BEGIN
    CREATE TABLE Publicidad.PiezaMercado (
        idPieza  int  NOT NULL,
        idPais   int  NOT NULL,

        CONSTRAINT PK_PiezaMercado        PRIMARY KEY (idPieza, idPais),
        CONSTRAINT FK_PiezaMercado_Pieza  FOREIGN KEY (idPieza) REFERENCES Publicidad.PiezaContenido (id),
        CONSTRAINT FK_PiezaMercado_Pais   FOREIGN KEY (idPais)  REFERENCES Torneo.Pais (id)
    );
END
GO

IF OBJECT_ID(N'Publicidad.UbicacionPublicitaria', N'U') IS NULL
BEGIN
    CREATE TABLE Publicidad.UbicacionPublicitaria (
        idUbicacion  tinyint       NOT NULL,   -- catálogo: ids controlados a mano
        nombre       varchar(50)   NOT NULL,   -- Cartel principal, Perimetral norte, Pantalla gigante...
        descripcion  varchar(200)  NULL,

        CONSTRAINT PK_UbicacionPublicitaria         PRIMARY KEY (idUbicacion),
        CONSTRAINT UQ_UbicacionPublicitaria_Nombre  UNIQUE (nombre)
    );
END
GO

IF OBJECT_ID(N'Publicidad.Tarifa', N'U') IS NULL
BEGIN
    CREATE TABLE Publicidad.Tarifa (
        idFase       int            NOT NULL,
        idUbicacion  tinyint        NOT NULL,
        montoUSD     decimal(12,2)  NOT NULL,

        CONSTRAINT PK_Tarifa             PRIMARY KEY (idFase, idUbicacion),
        CONSTRAINT FK_Tarifa_Fase        FOREIGN KEY (idFase)      REFERENCES Torneo.Fase (idFase),
        CONSTRAINT FK_Tarifa_Ubicacion   FOREIGN KEY (idUbicacion) REFERENCES Publicidad.UbicacionPublicitaria (idUbicacion),
        CONSTRAINT CK_Tarifa_Monto       CHECK (montoUSD > 0)
    );
END
GO

IF OBJECT_ID(N'Publicidad.ExhibicionPublicitaria', N'U') IS NULL
BEGIN
    CREATE TABLE Publicidad.ExhibicionPublicitaria (
        idPartido         int            NOT NULL,
        idUbicacion       tinyint        NOT NULL,
        idPieza           int            NOT NULL,
        criterioAplicado  tinyint        NOT NULL,   -- 1 país que juega, 2 PBI, 3 prime time
        estado            varchar(15)    NOT NULL,
        montoUSD          decimal(12,2)  NOT NULL,   -- foto de la tarifa al momento de asignar

        CONSTRAINT PK_ExhibicionPublicitaria               PRIMARY KEY (idPartido, idUbicacion),
        CONSTRAINT FK_ExhibicionPublicitaria_Partido       FOREIGN KEY (idPartido)   REFERENCES Torneo.Partido (idPartido),
        CONSTRAINT FK_ExhibicionPublicitaria_Ubicacion     FOREIGN KEY (idUbicacion) REFERENCES Publicidad.UbicacionPublicitaria (idUbicacion),
        CONSTRAINT FK_ExhibicionPublicitaria_Pieza         FOREIGN KEY (idPieza)     REFERENCES Publicidad.PiezaContenido (id),
        CONSTRAINT UQ_ExhibicionPublicitaria_PartidoPieza  UNIQUE (idPartido, idPieza),
        CONSTRAINT CK_ExhibicionPublicitaria_Criterio      CHECK (criterioAplicado BETWEEN 1 AND 3),
        CONSTRAINT CK_ExhibicionPublicitaria_Estado        CHECK (estado IN ('Propuesta', 'Confirmada', 'Exhibida')),
        CONSTRAINT CK_ExhibicionPublicitaria_Monto         CHECK (montoUSD > 0)
        -- El máximo de 4 ubicaciones por partido se valida en el SP de asignación
    );
END
GO

-- Cotizaciones obtenidas de la API Frankfurter (facturación en otras monedas)
IF OBJECT_ID(N'Publicidad.TipoCambio', N'U') IS NULL
BEGIN
    CREATE TABLE Publicidad.TipoCambio (
        moneda         char(3)        NOT NULL,   -- código ISO 4217
        fecha          date           NOT NULL,
        cotizacionUSD  decimal(18,6)  NOT NULL,   -- unidades de la moneda por 1 USD

        CONSTRAINT PK_TipoCambio             PRIMARY KEY (moneda, fecha),
        CONSTRAINT CK_TipoCambio_Moneda      CHECK (moneda LIKE '[A-Z][A-Z][A-Z]'),
        CONSTRAINT CK_TipoCambio_Cotizacion  CHECK (cotizacionUSD > 0)
    );
END
GO

/* =============================================================================
   ESQUEMA SISTEMA
   ============================================================================= */

-- Reglas configurables del reglamento (módulos B, D, F y H). Ejemplos de clave:
-- AMARILLAS_SUSPENSION, MAX_CAMBIOS, MAX_VENTANAS, CAMBIO_EXTRA_ALARGUE,
-- MIN_CONVOCADOS, MAX_CONVOCADOS, PRIME_TIME_INICIO, PRIME_TIME_FIN, MAX_ESPACIOS_PARTIDO
IF OBJECT_ID(N'Sistema.Parametro', N'U') IS NULL
BEGIN
    CREATE TABLE Sistema.Parametro (
        clave        varchar(50)   NOT NULL,
        valor        int           NOT NULL,
        descripcion  varchar(200)  NULL,

        CONSTRAINT PK_Parametro          PRIMARY KEY (clave),
        CONSTRAINT CK_Parametro_Valor    CHECK (valor >= 0)
    );
END
GO

-- Errores de las importaciones: las filas inválidas se registran acá
-- y el resto se importa igual (módulo I y Entrega 6)
IF OBJECT_ID(N'Sistema.ErrorImportacion', N'U') IS NULL
BEGIN
    CREATE TABLE Sistema.ErrorImportacion (
        id            int IDENTITY(1,1) NOT NULL,
        fechaHora     datetime2(0)      NOT NULL
            CONSTRAINT DF_ErrorImportacion_FechaHora DEFAULT (SYSDATETIME()),
        archivo       nvarchar(260)     NOT NULL,   -- nombre recibido por parámetro
        tablaDestino  varchar(100)      NOT NULL,
        nroFila       int               NULL,
        datoOriginal  nvarchar(max)     NULL,       -- la fila tal como venía
        mensajeError  nvarchar(4000)    NOT NULL,

        CONSTRAINT PK_ErrorImportacion  PRIMARY KEY (id)
    );
END
GO
