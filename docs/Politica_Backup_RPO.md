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

El RPO es el tiempo de pérdida de datos admisible: si se respalda cada 5 minutos, se admite un RPO de 5 minutos, que es lo máximo que se puede perder. El RTO es el tiempo necesario para restaurar la aplicación y sus datos y reanudar la operación.

**Día de partido:** desde 1 hora antes del primer inicio hasta 4 horas después del último inicio de ese día, según el fixture (`Torneo.vw_Fixture`). Todo lo demás es resto de los días.

## 2. Modelo de recuperación

La base hoy está en `SIMPLE` (verificado en `sys.databases`) y nunca tuvo un backup (verificado en `msdb`). En `SIMPLE` no se puede respaldar el log, así que el RPO no podría bajar del tiempo entre dos backups completos. **Se pasa a `FULL`** y se toma enseguida un backup completo, porque sin un completo previo no se puede tomar ningún otro tipo.

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

- **Copias:** estrategia 3-2-1: tres copias, en al menos dos medios distintos, una de ellas en la nube.
- **Compresión y cifrado:** los backups se comprimen y se cifran. Contienen datos personales de jugadores, staff y árbitros, que son justamente los que la entrega 8 manda cifrar. El certificado se respalda aparte y en otro lugar: sin él no se puede restaurar, así que su manejo es crítico.
- **Retención:** completos y diferenciales durante los 39 días del torneo, para poder volver a cualquier día; los logs, mientras sirvan a algún completo guardado.
- **Copy only:** para exportar una copia (por ejemplo, para la plataforma BI) sin alterar la secuencia de respaldos.
- **Programación:** con tareas de SQL Server Agent. Los horarios de los días de partido se calculan del fixture.

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

Se restaura el último completo, el último diferencial y todos los logs posteriores. Todos con `NORECOVERY`, salvo el último paso, que deja la base lista.

1. Si la base está dañada pero el log es accesible, se respalda primero el **tail log** para perder lo menos posible:
   `BACKUP LOG MundialFutbol TO DISK = N'F:\Backup\MundialFutbol_TAIL.trn' WITH NO_TRUNCATE;`
2. `RESTORE DATABASE MundialFutbol FROM DISK = N'F:\Backup\MundialFutbol_FULL.bak' WITH NORECOVERY, REPLACE;`
3. `RESTORE DATABASE MundialFutbol FROM DISK = N'F:\Backup\MundialFutbol_DIF.bak' WITH NORECOVERY;`
4. Un `RESTORE LOG ... WITH NORECOVERY` por cada log, en orden.
5. El último log con `WITH STOPAT = '<fecha y hora>', RECOVERY;` para volver al instante anterior al problema.
6. Verificar con `DBCC CHECKDB` y reabrir el acceso.

Antes de restaurar se puede mirar qué contiene un archivo con `RESTORE HEADERONLY`. En la prueba semanal se restaura con otro nombre de base y `WITH MOVE`, para no pisar la base real.

## 5. Fundamento de cada valor

Las cifras salen del fixture (`datasets/fifa-world-cup-2026-UTC.csv`, fechas en UTC) y de la base de desarrollo con los 31 partidos cargados. Los eventos por partido provienen de datos de carga de prueba, no de partidos reales.

### Cuándo se escribe

- **104 partidos en 39 días (11/06 al 19/07/2026); 35 de esos días tienen partido.** El día más cargado tiene 8 partidos (27/06) y hay hasta 2 partidos simultáneos. Por eso los días de partido son casi todos los días del torneo, no una excepción.
- **Filas escritas por partido: unas 79** (formación 52, cuerpo técnico 10,5, cuerpo arbitral 5, y los eventos en vivo: 3,2 goles, 6,3 cambios y 2,3 tarjetas, que suman 11,8). La formación y el cuerpo técnico (79 % de las filas) se cargan antes de que empiecen los eventos. Los eventos en vivo son el 15 % de las filas, pero son los que no se pueden reconstruir sin el partido.
- Un partido dura unos 105 minutos de reloj sin alargue (2 × 45 + 15 de descanso). Con 11,8 eventos en vivo, es **un evento cada 9 minutos, o 0,11 por minuto**.

### RPO de 5 minutos en días de partido

- Con un backup de log cada 5 minutos, lo máximo que se puede perder son esos 5 minutos.
- A 0,11 eventos por minuto, perder 5 minutos son **0,56 eventos por partido** (hasta 1,1 con dos partidos simultáneos): menos de un gol, cambio o tarjeta, que se vuelve a cargar a mano desde el informe del partido.
- Con 15 minutos serían 1,7 eventos por partido (3,4 con dos simultáneos). Una tarjeta roja perdida pesa mucho más que un cambio: genera una suspensión (`Eventos.Suspension`) que deja a un jugador afuera del partido siguiente, así que no se justifica admitir ese riesgo mientras se juega.
- **Ventana de 1 hora antes a 4 horas después del inicio:** la hora previa cubre la carga de la formación, que se registra antes de los eventos. Las 4 horas son el partido más largo posible (hasta 120 minutos de juego más descansos y penales, según los 5 períodos de `Torneo.Periodo`: unas 3 horas) más 1 hora para lo que se escribe después (`Arbitraje.InformeArbitral` y el cierre del partido en `53_Cierre_Partidos`). Los márgenes de 1 hora son un criterio de operación y se pueden ajustar. Hay días con hasta 23,5 horas entre el primer y el último inicio, así que en esos días la ventana ocupa casi todo el día.

### RPO de 15 minutos el resto de los días

- Fuera de los partidos solo hay tareas administrativas (ABM, carga de datos, APIs). Son pocas filas y se pueden reproducir: las importaciones y las cargas se pueden volver a ejecutar sin duplicar datos (el `50f` y los upsert de `40` y `43` son idempotentes).
- Es el valor de operación elegido para ese caso: 3 veces menos frecuente que en día de partido, con 96 logs por día en lugar de 288. El log se respalda con regularidad también para que su archivo no crezca sin control: una vez respaldado, su espacio se puede reutilizar.

### Diferencial cada 6 horas

- Sin diferenciales, restaurar a la última hora del día exigiría hasta **288 logs** (24 h × 12 por hora) sobre el completo. Con un diferencial cada 6 horas, la cadena queda en como máximo **72 logs** (6 h × 12) en días de partido y **24** (6 h × 4) el resto de los días. Menos pasos son un RTO más corto y menos riesgo de que falte un archivo.
- El diferencial es acumulativo: su tamaño depende del tiempo desde el completo y de los cambios. Con la base casi vacía, no pesa.

### Completo diario

- La base ocupa **6,55 MB** de datos. Un completo diario es insignificante, y evita que la cadena de restauración dependa de un archivo de hace días.
- Como cota superior, si todo escalara a los 104 partidos (104 / 31 = 3,4 veces) un completo pesaría unos 22 MB, y **39 completos unos 860 MB sin comprimir**. Por eso no hay razón para recortar la retención: queda guardado todo el torneo.

### RTO de 30 minutos

- Es un **objetivo, todavía no medido**: la prueba de restauración semanal sirve para confirmarlo o corregirlo, y el resultado se anota en este documento.
- Fundamento: la restauración de datos es corta porque la base es chica (6,55 MB y un máximo de 72 logs). La mayor parte del RTO es operativa: detectar el problema, traer los archivos de la copia que corresponda, restaurar, correr `DBCC CHECKDB` y reabrir.
- Con 0,11 eventos por minuto, 30 minutos de parada dejan unos 3 eventos por partido para cargar después desde el informe del partido, y es menos de un tercio de lo que dura un partido.

### Verificación y pruebas

- Un backup que nunca se verificó no es una garantía, y restaurar sin más no alcanza: se hacen también los controles de `DBCC`. Lo mismo vale para el procedimiento de restauración: se documenta y se prueba. De ahí la restauración semanal en otra base (alcanza para unas 5 pruebas durante los 39 días del torneo).

## 6. Qué no cubre

- **Alta disponibilidad.** Esta política protege los datos, pero con una caída hay que restaurar a mano, y ese tiempo es el RTO. Un servidor secundario con *log shipping* sería una solución de recuperación ante desastres (no hace failover automático) y queda como mejora opcional.
- **Cifrado de las columnas.** Se trata en el script `70`. Esta política solo cifra los archivos de backup.
