# Política de respaldo y RPO

Universidad Nacional de La Matanza · 3641 – Bases de Datos Aplicada · Comisión 2900
Integrantes: Pereira, Marcos Nahuel · Salas, Martín Daniel · Zito Padró, Ezequiel Nehuén
Entrega 8 (Seguridad y respaldo) · Fecha: 19/11/2026

Base protegida: `MundialFutbol` (SQL Server 2022). Cada valor de esta política tiene su fundamento en la sección 5.

---

## 1. Objetivos

| Objetivo | Días de partido | Resto de los días |
|---|---|---|
| **RPO** (pérdida de datos admisible) | **5 minutos** | **15 minutos** |
| **RTO** (tiempo para volver a operar) | **30 minutos** | **30 minutos** |

El RPO es cuántos datos estamos dispuestos a perder: si respaldamos cada 5 minutos, el RPO es de 5 minutos, que es lo máximo que se puede perder. El RTO es cuánto tardamos en restaurar la aplicación y sus datos para volver a operar.

**Día de partido:** desde 1 hora antes del primer inicio hasta 4 horas después del último inicio de ese día, según el fixture (`Torneo.vw_Fixture`). Todo lo demás cuenta como resto de los días.

## 2. Modelo de recuperación

La base hoy está en `SIMPLE` (lo verificamos en `sys.databases`) y nunca tuvo un backup (lo verificamos en `msdb`). En `SIMPLE` no se puede respaldar el log, así que el RPO nunca bajaría del tiempo que pasa entre dos backups completos. **La pasamos a `FULL`** y tomamos enseguida un backup completo, porque sin un completo de entrada no se puede tomar ningún otro tipo de backup.

```sql
ALTER DATABASE MundialFutbol SET RECOVERY FULL;
```

## 3. Plan de backups

| Tipo | Frecuencia en días de partido | Frecuencia el resto de los días |
|---|---|---|
| Completo | 1 por día | 1 por día |
| Diferencial | cada 6 horas | cada 6 horas |
| Log de transacciones | **cada 5 minutos** | **cada 15 minutos** |
| Verificación (`RESTORE VERIFYONLY` + `DBCC CHECKDB`) | después de cada completo | después de cada completo |
| Prueba de restauración en otra base | 1 por semana | 1 por semana |

- **Copias:** estrategia 3-2-1: tres copias, en al menos dos medios distintos, y una de ellas en la nube.
- **Compresión y cifrado:** los backups van comprimidos y cifrados. Tienen datos personales de jugadores, staff y árbitros, que son justamente los que la entrega 8 pide cifrar. El certificado se guarda aparte y en otro lugar: sin él no se puede restaurar, así que hay que cuidarlo como a la base misma.
- **Retención:** guardamos los completos y los diferenciales durante los 39 días del torneo, para poder volver a cualquier día. Los logs se guardan mientras sirvan a algún completo que conservemos.
- **Copy only:** sirve para exportar una copia (por ejemplo, para la plataforma BI) sin alterar la secuencia de respaldos.
- **Programación:** con tareas de SQL Server Agent. Los horarios de los días de partido se calculan a partir del fixture.

```sql
-- Completo (diario), diferencial (cada 6 h) y log (cada 5 o 15 min)
BACKUP DATABASE MundialFutbol TO DISK = N'F:\Backup\MundialFutbol_FULL.bak'
    WITH COMPRESSION, CHECKSUM, ENCRYPTION (ALGORITHM = AES_256, SERVER CERTIFICATE = CertBackupMundial);
BACKUP DATABASE MundialFutbol TO DISK = N'F:\Backup\MundialFutbol_DIF.bak'
    WITH DIFFERENTIAL, COMPRESSION, CHECKSUM, ENCRYPTION (ALGORITHM = AES_256, SERVER CERTIFICATE = CertBackupMundial);
BACKUP LOG MundialFutbol TO DISK = N'F:\Backup\MundialFutbol_LOG.trn'
    WITH COMPRESSION, CHECKSUM, ENCRYPTION (ALGORITHM = AES_256, SERVER CERTIFICATE = CertBackupMundial);

-- Verificación
RESTORE VERIFYONLY FROM DISK = N'F:\Backup\MundialFutbol_FULL.bak' WITH CHECKSUM;
DBCC CHECKDB (N'MundialFutbol') WITH NO_INFOMSGS;
```

## 4. Cómo se restaura

Restauramos el último completo, el último diferencial y todos los logs posteriores. Todos van con `NORECOVERY`, menos el último paso, que deja la base lista para usar.

1. Si la base está dañada pero todavía se puede leer el log, primero respaldamos el **tail log** para perder lo menos posible:
   `BACKUP LOG MundialFutbol TO DISK = N'F:\Backup\MundialFutbol_TAIL.trn' WITH NO_TRUNCATE;`
2. `RESTORE DATABASE MundialFutbol FROM DISK = N'F:\Backup\MundialFutbol_FULL.bak' WITH NORECOVERY, REPLACE;`
3. `RESTORE DATABASE MundialFutbol FROM DISK = N'F:\Backup\MundialFutbol_DIF.bak' WITH NORECOVERY;`
4. Un `RESTORE LOG ... WITH NORECOVERY` por cada log, en orden.
5. El último log con `WITH STOPAT = '<fecha y hora>', RECOVERY;` para volver al instante justo antes del problema.
6. Verificamos con `DBCC CHECKDB` y volvemos a habilitar el acceso.

Antes de restaurar, `RESTORE HEADERONLY` permite ver qué contiene un archivo de backup. En la prueba semanal restauramos con otro nombre de base y `WITH MOVE`, para no pisar la base real.

## 5. Fundamento de cada valor

Las cifras salen del fixture (`datasets/fifa-world-cup-2026-UTC.csv`, fechas en UTC) y de la base de desarrollo con los 31 partidos cargados. Los eventos por partido vienen de datos de carga de prueba, no de partidos reales.

### Cuándo se escribe

- **104 partidos en 39 días (del 11/06 al 19/07/2026); 35 de esos días tienen partido.** El día más cargado tiene 8 partidos (27/06) y hay hasta 2 partidos al mismo tiempo. O sea que los días de partido son casi todos los del torneo, no la excepción.
- **Filas escritas por partido: unas 79** (formación 52, cuerpo técnico 10,5, cuerpo arbitral 5, y los eventos en vivo: 3,2 goles, 6,3 cambios y 2,3 tarjetas, que suman 11,8). La formación y el cuerpo técnico (79 % de las filas) se cargan antes de que arranquen los eventos. Los eventos en vivo son el 15 % de las filas, pero son los que no se pueden reconstruir sin el partido.
- Un partido dura unos 105 minutos de reloj sin alargue (2 × 45 + 15 de descanso). Con 11,8 eventos en vivo, da **un evento cada 9 minutos, o 0,11 por minuto**.

### RPO de 5 minutos en días de partido

- Con un backup de log cada 5 minutos, lo máximo que se puede perder son esos 5 minutos.
- A 0,11 eventos por minuto, perder 5 minutos son **0,56 eventos por partido** (hasta 1,1 con dos partidos a la vez): menos de un gol, un cambio o una tarjeta, que se vuelve a cargar a mano desde el informe del partido.
- Con 15 minutos serían 1,7 eventos por partido (3,4 con dos a la vez). Y una roja que se pierda pesa mucho más que un cambio: genera una suspensión (`Eventos.Suspension`) que deja a un jugador afuera del partido siguiente. No nos conviene arriesgar eso mientras se juega.
- **Ventana de 1 hora antes a 4 horas después del inicio:** la hora previa cubre la carga de la formación, que se registra antes que los eventos. Las 4 horas son el partido más largo posible (hasta 120 minutos de juego más descansos y penales, según los 5 períodos de `Torneo.Periodo`: unas 3 horas) más 1 hora para lo que se escribe después (`Arbitraje.InformeArbitral` y el cierre del partido en `53_Cierre_Partidos`). Los márgenes de 1 hora son un criterio de operación y se pueden ajustar. Hay días con hasta 23,5 horas entre el primer y el último inicio, así que en esos días la ventana abarca casi todo el día.

### RPO de 15 minutos el resto de los días

- Fuera de los partidos solo hay tareas administrativas (ABM, carga de datos, APIs). Son pocas filas y se pueden rehacer: las importaciones y las cargas se pueden volver a correr sin duplicar datos (el `50f` y los upsert de `40` y `43` son idempotentes).
- Es el valor de operación que elegimos para ese caso: se respalda 3 veces menos seguido que en día de partido, con 96 logs por día en lugar de 288. Además, el log se respalda con regularidad para que su archivo no crezca sin control: una vez respaldado, su espacio se puede reutilizar.

### Diferencial cada 6 horas

- Sin diferenciales, para restaurar a la última hora del día habría que aplicar hasta **288 logs** (24 h × 12 por hora) sobre el completo. Con un diferencial cada 6 horas, la cadena queda en un máximo de **72 logs** (6 h × 12) en días de partido y **24** (6 h × 4) el resto de los días. Menos pasos significan un RTO más corto y menos chances de que falte algún archivo.
- El diferencial es acumulativo: su tamaño depende del tiempo que pasó desde el completo y de los cambios. Con la base casi vacía, casi no pesa.

### Completo diario

- La base ocupa **6,55 MB** de datos. Un completo por día es insignificante y evita que la restauración dependa de un archivo de hace varios días.
- Como cota superior, si todo se multiplicara para llegar a los 104 partidos (104 / 31 = 3,4 veces), un completo pesaría unos 22 MB y **39 completos, unos 860 MB sin comprimir**. Por eso no hay motivo para recortar la retención: guardamos todo el torneo.

### RTO de 30 minutos

- Es un **objetivo que todavía no medimos**: la prueba de restauración semanal sirve para confirmarlo o corregirlo, y el resultado lo anotamos en este documento.
- Fundamento: restaurar los datos lleva poco porque la base es chica (6,55 MB y un máximo de 72 logs). La mayor parte del RTO es operativa: detectar el problema, traer los archivos de la copia que corresponda, restaurar, correr `DBCC CHECKDB` y reabrir.
- Con 0,11 eventos por minuto, 30 minutos de parada dejan unos 3 eventos por partido para cargar después desde el informe del partido, y es menos de un tercio de lo que dura un partido.

### Verificación y pruebas

- Un backup que nunca se verificó no es una garantía, y tampoco alcanza con restaurarlo: también corremos los controles de `DBCC`. Con el procedimiento de restauración pasa lo mismo: lo documentamos y lo probamos. De ahí la restauración semanal en otra base (alcanza para unas 5 pruebas durante los 39 días del torneo).

## 6. Qué no cubre

- **Alta disponibilidad.** Esta política protege los datos, pero si hay una caída hay que restaurar a mano, y ese tiempo es el RTO. Un servidor secundario con *log shipping* serviría como recuperación ante desastres (no hace failover automático) y queda como mejora opcional.
- **Cifrado de las columnas.** Se trata en el script `70`. Esta política solo cifra los archivos de backup.
