# DER v2 - Cambios respecto de la v1

Alineado con `00_InitialSchema.sql`.

- Tablas agrupadas en esquemas: `Torneo`, `Equipos`, `Arbitraje`, `Eventos`, `Publicidad`, `Sistema`.
- Se eliminan los enums: pasan a `varchar` con CHECK (detallado en las notas).
- Tipos de datos definidos (`nvarchar`, `decimal`, `date`, `datetime2`) y PK con `increment`.
- Nuevas tablas: `Arbitraje.InformeArbitral`, `Publicidad.TipoCambio`, `Sistema.Parametro`, `Sistema.ErrorImportacion`.
- `Torneo.Partido`: nuevo campo `nroPartidoOficial` y CHECK de estado, local <> visitante y goles.
- `Equipos.Seleccion`: `idPais` único.
- `Arbitraje.Arbitro`: nuevo campo `categoria`.
- `Equipos.ListadoJugadores`: dorsal obligatorio e índices únicos filtrados (dorsal activo y jugador activo).
- `Eventos` (`Tarjeta`, `Sustitucion`, `Gol`): CHECK de minutos; `Suspension` con campos obligatorios y CHECK Jugador/Staff.
- Se agregan restricciones `NOT NULL` y CHECK en el resto de las tablas.
