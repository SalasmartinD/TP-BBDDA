# DER v3 - Cambios respecto de la v2

- Nueva tabla `Eventos.CuerpoTecnicoPartido` (`idPartido`, `idStaff`): staff que figura en cada partido, igual que `FormacionPartido` con los jugadores. Solo quien figura puede recibir tarjeta.
- `Eventos.Suspension`: nueva columna `idTarjeta` (FK a `Eventos.Tarjeta`, NULL = suspensión manual).
- Nuevo índice único filtrado `UX_Suspension_Tarjeta`: una tarjeta origina como máximo una suspensión.
- `CuerpoTecnicoPartido` agregada al TableGroup `Eventos`.
