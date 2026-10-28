# TP Mundial de Fútbol · Bases de Datos Aplicada

Sistema de Registro y Gestión del Mundial de Fútbol.
Universidad Nacional de La Matanza · 3641 – Bases de Datos Aplicada · Comisión 2900.

| Integrante | Usuario de GitHub | Área |
|---|---|---|
| Salas, Martín Daniel | [@SalasmartinD](https://github.com/SalasmartinD) | Persona 1: Torneo, Equipos y APIs |
| Pereira, Marcos Nahuel | _completar_ | _a definir_ |
| Zito Padró, Ezequiel Nehuén | _completar_ | _a definir_ |

La división de tareas completa está en [`docs/Division_de_Tareas_TP_Mundial.pdf`](docs/Division_de_Tareas_TP_Mundial.pdf) y la consigna en [`docs/Consigna_TP.pdf`](docs/Consigna_TP.pdf).

---

## Índice

1. [Estructura del repositorio](#1-estructura-del-repositorio)
2. [Cómo ejecutar los scripts](#2-cómo-ejecutar-los-scripts)
3. [Reglas generales](#3-reglas-generales)
4. [Ramas](#4-ramas)
5. [Commits](#5-commits)
6. [Pull requests](#6-pull-requests)
7. [PRs que dependen de otras (encadenadas)](#7-prs-que-dependen-de-otras-encadenadas)
8. [Estándares de los scripts SQL](#8-estándares-de-los-scripts-sql)

---

## 1. Estructura del repositorio

```
TP-BBDDA/
├── 00_InitialSchema.sql        ← base, esquemas, tablas y restricciones (compartido)
├── 10_..sql … 82_..sql         ← un script por tipo y por persona (ver numeración)
├── datasets/                   ← archivos a importar (CSV, XML), sin modificar
├── docs/                       ← consigna, división de tareas, PDFs de cada entrega, DER
├── .github/
│   └── pull_request_template.md
└── README.md
```

### Numeración de archivos

Cada script empieza con dos dígitos que indican el orden de ejecución. Cada uno de nosotros usa su propio número, así nunca vamos a tener dos archivos con el mismo nombre ni conflictos al mergear.

| Tipo de script | Persona 1 | Persona 2 | Persona 3 |
|---|---|---|---|
| Base, esquemas, tablas y restricciones | `00` (compartido) | | |
| SP de ABM | `10` | `11` | `12` |
| SP de negocio | `20` | `21` | `22` |
| Vistas y funciones | `30` | `31` | `32` |
| Importación | `40` (CSV) · `43` (APIs) | `41` (scraping) | |
| Carga de datos | `50` (corre primero) | `51` | `52` |
| Reportes | `60` | `61` | `62` |
| Seguridad | `70` (cifrado) | | `71` (roles) |
| Testing | `80` | `81` | `82` |

El nombre completo sigue el formato `NN_DescripcionEnPascalCase.sql`, por ejemplo `10_ABM_TorneoEquipos.sql` o `81_Test_EventosArbitraje.sql`. Si un archivo crece mucho, lo podemos partir agregando una letra: `21a_Formaciones.sql`, `21b_Tarjetas.sql`.

---

## 2. Cómo ejecutar los scripts

1. Abrir la solución en SQL Server Management Studio.
2. Ejecutar los scripts en orden numérico, empezando por `00_InitialSchema.sql`.
3. Los scripts de testing (`8x`) se ejecutan al final y cada prueba tiene comentado el resultado esperado.

Para recrear todo desde cero, que es lo primero que nos van a pedir en el coloquio:

```sql
USE master;
DROP DATABASE IF EXISTS MundialFutbol;
-- y volver a ejecutar desde 00_InitialSchema.sql
```

> Antes de abrir una PR tenemos que comprobar que la base se recrea desde cero sin errores con nuestros cambios.

---

## 3. Reglas generales

- **Nadie pushea directo a `main`.** Todo cambio entra por pull request, incluido el de quien administra el repo.
- **`main` siempre tiene que funcionar:** ejecutando los scripts en orden, la base se crea sin errores.
- **Cada uno trabaja sobre sus propios archivos.** Si necesitamos tocar un archivo de otro (por ejemplo, el `00`), lo avisamos en el grupo antes y lo hacemos en una PR aparte, chica y solo con ese cambio.
- **Cada uno hace sus propios commits.** El enunciado desaprueba a quien tenga menos del 20% de las líneas de código del que más aportó, y se mide por lo que figura en el repositorio. No subimos código de otro desde nuestra cuenta.
- **El repositorio es público: no subimos datos privados.** Nada de DNI, contraseñas, cadenas de conexión ni claves de API. Si una API necesita clave (por ejemplo football-data.org), en el script va un marcador como `'<API_KEY>'` y la clave real la carga cada uno localmente.
- **Los archivos de `datasets/` no se modifican** después de descargarlos: el enunciado exige importarlos tal cual (salvo lo obtenido por scraping).

---

## 4. Ramas

Cada funcionalidad va en su propia rama, creada desde `main` actualizada:

```bash
git checkout main
git pull
git checkout -b feat/e5-abm-torneo
```

### Formato del nombre

```
<tipo>/<entrega>-<descripcion-corta>
```

- Todo en minúsculas, palabras separadas con guiones, sin tildes ni ñ.
- `<entrega>` es `e4` a `e9`. Si la rama no es de una entrega en particular, se omite.

| Prefijo | Para qué | Ejemplo |
|---|---|---|
| `feat/` | Funcionalidad nueva: SP, vistas, funciones, reportes, importaciones | `feat/e5-abm-torneo`, `feat/e6-api-frankfurter` |
| `fix/` | Corrección de algo que ya está en `main` | `fix/e5-validacion-dorsal` |
| `test/` | Scripts de testing | `test/e5-abm-torneo` |
| `data/` | Scripts de carga de datos (seed) y datasets | `data/e5-carga-base` |
| `docs/` | Documentación: PDFs de entregas, DER, README | `docs/e4-instalacion` |
| `refactor/` | Cambios que no alteran el comportamiento (renombrar, reordenar, limpiar) | `refactor/sp-eventos` |
| `chore/` | Configuración del repo, plantillas, `.gitignore` | `chore/plantilla-pr` |

### Reglas

- **Una rama, un tema.** Si una rama empieza a mezclar cosas que no tienen relación, la partimos en dos.
- **Ramas cortas.** Mejor varias PRs chicas que una enorme: se revisan más rápido y tienen menos conflictos.
- **Mantener la rama al día con `main`** para no acumular conflictos:
  ```bash
  git fetch origin
  git rebase origin/main      # o: git merge origin/main
  ```
- **Borrar la rama** después de mergear la PR (GitHub ofrece el botón).

---

## 5. Commits

Seguimos la convención [Conventional Commits](https://www.conventionalcommits.org/es/v1.0.0/):

```
<tipo>(<alcance>): <descripción en imperativo y en minúscula>
```

### Tipos

| Tipo | Cuándo |
|---|---|
| `feat` | Agrega algo nuevo (SP, vista, función, reporte, importación) |
| `fix` | Corrige un error |
| `test` | Agrega o modifica scripts de testing |
| `data` | Agrega o modifica carga de datos o datasets |
| `docs` | Documentación |
| `refactor` | Reestructura sin cambiar el comportamiento |
| `chore` | Configuración, plantillas, tareas de mantenimiento |

### Alcances

El alcance indica qué parte del sistema toca. Usamos los esquemas de la base y algunas áreas transversales:

`torneo` · `equipos` · `arbitraje` · `eventos` · `publicidad` · `sistema` · `import` · `api` · `reportes` · `seguridad` · `bi` · `app` · `schema` (cambios en `00_InitialSchema.sql`)

### Ejemplos

```
feat(equipos): agregar SP de alta y baja de convocados
feat(api): consumir API de Frankfurter y cargar TipoCambio
fix(eventos): corregir cálculo de suspensión por acumulación
test(torneo): agregar casos de error en el ABM de partidos
data(equipos): cargar 16 selecciones con 23 convocados
docs(e4): agregar documento de instalación de SQL Server
chore: agregar plantilla de pull request
```

### Reglas

- **Descripción en imperativo**, como una orden: "agregar", "corregir", "eliminar". No "agregué" ni "agregando".
- **Primera línea de 72 caracteres como máximo.** Si hace falta explicar más, dejamos una línea en blanco y seguimos en el cuerpo del commit.
- **Commits chicos y con sentido propio.** Un commit por cambio lógico, no un único commit gigante al final.
- **Si el commit rompe compatibilidad** (por ejemplo, cambia la firma de un SP que usa otro integrante), lo marcamos con `!` y lo explicamos en el cuerpo:
  ```
  feat(equipos)!: agregar parámetro @fechaAlta a ListadoJugadores_Alta

  Los scripts de carga que llamaban al SP sin la fecha tienen que actualizarse.
  ```

---

## 6. Pull requests

1. Pushear la rama y abrir la PR contra `main`. GitHub carga automáticamente la plantilla de [`.github/pull_request_template.md`](.github/pull_request_template.md); hay que completarla.
2. **Título:** con el mismo formato que los commits, por ejemplo `feat(equipos): ABM de convocados con validaciones`.
3. **Asignar como revisor** a al menos uno de los otros dos integrantes.
4. **Para mergear se necesita al menos una aprobación.** Nadie aprueba ni mergea su propia PR sin revisión.
5. El que revisa tiene que **ejecutar los scripts** de la PR en su base local, no solo leer el código.
6. Los comentarios de la revisión se resuelven con nuevos commits en la misma rama. Cuando están todos resueltos, se pide revisión de nuevo.
7. **Mergear con "Create a merge commit"** para conservar los commits individuales de cada uno (sirven como evidencia de participación).
8. Borrar la rama después del merge.

### Qué revisamos

- Que la base se recree desde cero sin errores con los cambios.
- Que cada SP tenga su script de testing, con casos exitosos y casos que fallan, y el resultado esperado comentado.
- Que se respeten la nomenclatura, el encabezado de los scripts y el patrón de validación (ver sección 8).
- Que no haya datos privados ni claves.
- Que no se modifiquen archivos de otro integrante sin haberlo hablado.

---

## 7. PRs que dependen de otras (encadenadas)

A veces una tarea necesita algo que todavía está en revisión. Por ejemplo, la carga de datos (`data/e5-carga-base`) usa los SP de ABM de una PR que todavía no se mergeó (`feat/e5-abm-torneo`). En vez de esperar o de mezclar todo en una sola PR, **encadenamos** las PRs:

```
main
 └── feat/e5-abm-torneo        PR #4  (base: main)
      └── data/e5-carga-base   PR #5  (base: feat/e5-abm-torneo)
```

### Cómo hacerlo

1. Crear la segunda rama **desde la primera**, no desde `main`:
   ```bash
   git checkout feat/e5-abm-torneo
   git checkout -b data/e5-carga-base
   ```
2. Al abrir la PR, elegir como **base la rama de la PR anterior**, no `main`. Así la PR muestra solo sus propios cambios.
3. En la descripción, completar la sección **"Depende de"** de la plantilla con el número de la PR anterior (`Depende de #4`).
4. **Se mergean en orden:** primero la de abajo (#4) y después la que depende de ella (#5).
5. Cuando se mergea la primera y se borra su rama, GitHub cambia automáticamente la base de la segunda a `main`. Si no lo hace, se cambia a mano con el botón **Edit** al lado del título de la PR.
6. Si la primera PR recibe cambios durante la revisión, actualizamos la segunda:
   ```bash
   git checkout data/e5-carga-base
   git rebase feat/e5-abm-torneo
   git push --force-with-lease
   ```

### Reglas

- **No encadenar más de dos o tres PRs.** Si la cadena crece mucho, es señal de que conviene mergear las primeras antes de seguir.
- **No mergear una PR cuya base todavía no está en `main`**, salvo que sea la siguiente de la cadena.
- Si la dependencia es con una PR **de otro integrante**, lo avisamos en el grupo para que priorice su revisión.

---

## 8. Estándares de los scripts SQL

### Encabezado obligatorio

Todos los scripts empiezan con este comentario (lo exige el enunciado):

```sql
/*
================================================================================
 Universidad : Universidad Nacional de La Matanza
 Materia     : 3641 - Bases de Datos Aplicada
 Comisión    : 2900
 Integrantes : Pereira, Marcos Nahuel
               Salas, Martín Daniel
               Zito Padró, Ezequiel Nehuén
 Fecha       : DD/MM/AAAA

 Objetivo    : <qué hace este script>
================================================================================
*/
```

### Nomenclatura

| Objeto | Norma | Ejemplo |
|---|---|---|
| Tablas | PascalCase, en singular, dentro de su esquema | `Torneo.Partido` |
| Columnas | camelCase | `fechaHoraUTC`, `idSeleccionLocal` |
| Claves foráneas | `id` + entidad referenciada | `idPais`, `idPartido` |
| Stored procedures | `Esquema.Tabla_Accion` | `Equipos.ListadoJugadores_Alta` |
| SP de negocio | `Esquema.VerboSustantivo` | `Eventos.RegistrarTarjeta` |
| SP de reportes | `Esquema.Reporte_Nombre` | `Eventos.Reporte_Goleadores` |
| SP de importación | `Esquema.Importar_Origen` | `Torneo.Importar_FixtureCSV` |
| Vistas | `Esquema.vw_Nombre` | `Torneo.vw_Fixture` |
| Funciones | `Esquema.fn_Nombre` | `Eventos.fn_EquipoEnCancha` |
| Parámetros y variables | `@camelCase` | `@idPartido`, `@errores` |
| Restricciones | `PK_`, `FK_`, `UQ_`, `CK_`, `DF_`, `UX_` + tabla + detalle | `FK_Sede_Pais` |

Acciones de los SP de ABM: `_Alta`, `_Baja`, `_Modificacion`.

### Reglas de código

- **Validar existencia antes de crear.** Tablas con `IF OBJECT_ID(...) IS NULL`; SP, vistas y funciones con `CREATE OR ALTER`.
- **No usar SQL dinámico** salvo que sea estrictamente necesario (por ejemplo, `BULK INSERT` con el nombre de archivo como parámetro). Si lo usamos, dejamos un comentario que lo justifique.
- **Nada de acceso directo a las tablas para altas, bajas o modificaciones:** todo pasa por SP, incluida la carga de datos una vez que los SP estén listos.
- **Los SP de negocio que tocan varias tablas** van dentro de una transacción (`BEGIN TRAN` / `COMMIT`, con `ROLLBACK` en el `CATCH`).
- **Todo en T-SQL:** no se admiten scripts ni software externos al motor, tampoco CLR.

### Patrón de validación de los SP

Cada SP revisa **todas** las condiciones, acumula las que fallan en `@errores` y, si hay alguna, corta con **un único `THROW`** que informa todo junto. Solo si no hubo errores modifica la tabla.

```sql
CREATE OR ALTER PROCEDURE Equipos.ListadoJugadores_Alta
    @idSeleccion int, @idJugador int, @dorsal tinyint, @fechaAlta date
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @errores nvarchar(2000) = N'';

    -- 1. Revisar TODAS las condiciones, acumulando las que fallan
    IF NOT EXISTS (SELECT 1 FROM Equipos.Seleccion WHERE id = @idSeleccion)
        SET @errores += CHAR(10) + N'- La selección no existe.';

    IF EXISTS (SELECT 1 FROM Equipos.ListadoJugadores
               WHERE idSeleccion = @idSeleccion AND dorsal = @dorsal
                 AND fechaBaja IS NULL)
        SET @errores += CHAR(10) + N'- El dorsal ya lo usa otro convocado activo.';

    -- 2. Si hubo errores, un único THROW con todos juntos
    IF @errores <> N''
    BEGIN
        SET @errores = N'No se pudo dar de alta el convocado:' + @errores;
        THROW 50001, @errores, 1;   -- THROW no acepta expresiones, solo una variable
    END;

    -- 3. Recién acá se modifica la tabla
    INSERT INTO Equipos.ListadoJugadores (idSeleccion, idJugador, dorsal, fechaAlta)
    VALUES (@idSeleccion, @idJugador, @dorsal, @fechaAlta);
END
```

| Número de error | Uso |
|---|---|
| `50001` | Validaciones de datos en los SP |
| `50002` | Reglas de negocio (por ejemplo, conflicto de nacionalidad del árbitro) |
| `50003` | Errores de importación |

### Testing

- Un script de testing por cada script de SP (relación 1 a 1), en su propio archivo `8x`.
- Cada prueba lleva un comentario con el **resultado esperado** y deja evidencia de los datos (un `SELECT` antes y después).
- Hay que probar tanto los casos exitosos como los que tienen que fallar en las validaciones.

```sql
-- PRUEBA 3: alta con dorsal repetido
-- Resultado esperado: error 50001 con el mensaje "El dorsal ya lo usa otro convocado activo."
EXEC Equipos.ListadoJugadores_Alta @idSeleccion = 1, @idJugador = 45, @dorsal = 10, @fechaAlta = '2026-06-01';
```