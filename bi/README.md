# Guía de Montaje y Visualización en Metabase · Entrega 9
## Sistema de Registro y Gestión del Mundial de Fútbol · Comisión 2900
### GRUPO 09 (Publicidad, Seguridad y BI)

Este documento detalla la instalación, conexión y configuración paso a paso del Dashboard de Business Intelligence utilizando **Metabase** conectado a **SQL Server 2022** (`MundialFutbol`).

---

## 1. Requisitos Previos

1. **Java Runtime Environment (JRE / JDK):**
   - **Java 21 LTS o superior** (probado localmente con **OpenJDK 25 LTS**; verificado con `java -version`), versión mínima requerida por las releases recientes de Metabase.
2. **Archivo ejecutable de Metabase:**
   - Descargar el archivo `metabase.jar` (versión Open Source gratuita) desde [metabase.com/start/oss/jar](https://www.metabase.com/start/oss/jar).
   - Guardarlo en una carpeta local fuera del control de Git (ej: `C:\Metabase\metabase.jar` o en la carpeta `bi/local/`).
3. **Base de Datos y Configuración de SQL Server (Crítico en SQL Express):**
3. **Base de Datos y Configuración de SQL Server (Crítico en SQL Express):**
   - Base de datos `MundialFutbol` con datos cargados y el script `32b_Vistas_BI.sql` ejecutado.
   - **Habilitar protocolo TCP/IP:** en SQL Server Express el protocolo de red TCP viene deshabilitado por defecto. Es obligatorio activarlo para que Metabase (JDBC) pueda conectarse:
     1. Abrir **SQL Server Configuration Manager** (`SQLServerManager16.msc`).
     2. Desplegar *SQL Server Network Configuration* ➔ *Protocols for SQLEXPRESS*.
     3. Hacer doble clic en **TCP/IP** ➔ cambiar **Enabled** a `Yes`.
     4. En la pestaña **IP Addresses**, ir hasta la sección **IPAll**: dejar *TCP Dynamic Ports* en blanco y fijar **TCP Port** en `1433`.
     5. En *SQL Server Services*, reiniciar el servicio **SQL Server (SQLEXPRESS)**.
   - **Habilitar Autenticación Mixta:**
     1. En SSMS, clic derecho en la instancia ➔ *Properties* ➔ *Security*.
     2. Seleccionar *SQL Server and Windows Authentication mode*.
     3. Reiniciar el servicio de SQL Server.
   - **Crear el Login `login_bi` y asignarlo a `rol_BI`:**
     - Ejecutar en SSMS el script de creación local (basado en `bi/local/crear_logins.sql.example`):
       ```sql
       USE master;
       CREATE LOGIN login_bi WITH PASSWORD = N'<PASSWORD>', CHECK_POLICY = OFF;
       GO
       USE MundialFutbol;
       EXEC Sistema.CrearUsuarioConLogin @login = N'login_bi', @usuario = N'usr_bi_net', @rol = N'rol_BI';
       GO
       ```

---

## 2. Puesta en Marcha de Metabase

Desde una terminal situada en la carpeta donde descargó `metabase.jar`:

```powershell
java -jar metabase.jar
```

- Metabase iniciará en unos 60 a 90 segundos.
- Una vez finalizada la inicialización, abrir el navegador web en:  
  👉 **`http://localhost:3000`**

---

## 3. Asistente de Configuración Inicial (Primer Arranque)

1. **Bienvenida:** Hacer clic en *Let's get started* (o seleccionar Español).
2. **Crear usuario administrador:** Completar con nombre y correo (ej. `admin@mundial.com`).
3. **Conectar a la base de datos:**
   - **Database type:** `SQL Server`
   - **Name:** `Mundial de Fútbol 2026`
   - **Host:** `localhost` *(o `127.0.0.1`)*
   - **Port:** `1433` *(para instancias nombradas como `SQLEXPRESS`, asegurarse de que el puerto TCP esté habilitado en SQL Server Configuration Manager, o usar `localhost\SQLEXPRESS` según el soporte JDBC)*
   - **Database name:** `MundialFutbol`
   - **Username:** `login_bi` *(o su usuario local)*
   - **Password:** `<PASSWORD>`
   - **Additional JDBC connection string options:**  
     `trustServerCertificate=true;`
4. Finalizar el asistente desmarcando la opción de telemetría si se prefiere.

---

## 4. Estructura de Consultas Versionadas

Todas las preguntas que conforman el Dashboard están versionadas en este repositorio bajo la carpeta [`bi/consultas/`](consultas/):

| Archivo | Pregunta / KPI | Tipo de Gráfico | Fuente de Datos |
|---|---|---|---|
| [`01_k1_ingresos_por_sede.sql`](consultas/01_k1_ingresos_por_sede.sql) | **K1:** Facturación por Sede (Exhibida) | Barras Horizontales | `Publicidad.vw_BI_Exhibiciones` |
| [`02_k2_ocupacion_por_fase.sql`](consultas/02_k2_ocupacion_por_fase.sql) | **K2:** Ocupación e Ingresos por Fase (Exhibida) | Barras Verticales | `Publicidad.vw_BI_Exhibiciones` |
| [`03_k3_criterios_asignacion.sql`](consultas/03_k3_criterios_asignacion.sql) | **K3:** Criterios de Priorización | Torta / Donut | `Publicidad.vw_BI_Exhibiciones` |
| [`04_k4_evolucion_ingresos.sql`](consultas/04_k4_evolucion_ingresos.sql) | **K4:** Evolución de Ingresos (Exhibida) | Línea / Área | `Publicidad.vw_BI_Exhibiciones` |
| [`05_k5_top_anunciantes.sql`](consultas/05_k5_top_anunciantes.sql) | **K5:** Ranking de Anunciantes (Exhibida) | Barras / Tabla | `Publicidad.vw_BI_Exhibiciones` |
| [`06_k6_mapa_sedes.sql`](consultas/06_k6_mapa_sedes.sql) | **K6:** Mapa de Sedes del Torneo | Mapa de Pines | `Torneo.vw_BI_Sedes` |
| [`07_k7_goles_por_seleccion.sql`](consultas/07_k7_goles_por_seleccion.sql) | **K7:** Goles por Selección | Barras Verticales | `Eventos.vw_BI_GolesPorSeleccion` |
| [`08_reporte_ocupacion_e7.sql`](consultas/08_reporte_ocupacion_e7.sql) | **R1:** Reporte Ocupación E7 | Tabla con Totales | `Reporte_OcupacionPublicitaria` |

---

## 5. Armado de Preguntas y Configuración Visual

En Metabase, hacer clic en **"+ New"** ➔ **"SQL query"**:

### A. Gráfico K1: Ingresos por Sede
- Pegar el código de `01_k1_ingresos_por_sede.sql`.
- Ejecutar y elegir visualización: **Bar** (X: `Estadio`, Y: `Total Facturado (USD)`).
- Guardar como *"K1 - Ingresos por Sede"*.

### B. Gráfico K3: Distribución por Criterio
- Pegar el código de `03_k3_criterios_asignacion.sql`.
- Ejecutar y elegir visualización: **Pie** (Métrica: `Monto Total (USD)` o `Cantidad`, Dimensión: `Criterio de Priorización`).
- Guardar como *"K3 - Criterios de Asignación Publicitaria"*.

### C. Mapa K6: Geolocalización de Sedes
- Pegar el código de `06_k6_mapa_sedes.sql`.
- Ejecutar la consulta.
- En la visualización elegir **Map** ➔ **Pin Map**.
- Seleccionar manualmente el campo  `Latitud` y `Longitud`.
- En tooltip/hover seleccionar que muestre: `Estadio`, `Ciudad`, `Capacidad de Espectadores` y `Partidos Asignados`.
- Guardar como *"K6 - Mapa de Sedes del Torneo"*.

### D. Reporte de la Entrega 7 en Metabase
- Pegar el código de `08_reporte_ocupacion_e7.sql`.
- Visualización: **Table**.
- Guardar como *"Reporte E7 - Ocupación Publicitaria por Sede y Partido"*.

---

## 6. Creación del Dashboard

1. Hacer clic en **"+ New"** ➔ **"Dashboard"**.
2. Nombre: **"Panel de Control: Publicidad, Sedes y BI"**.
3. Añadir cada una de las preguntas guardadas organizando los paneles:
   - Fila superior: *KPIs globales / Tarjetas numéricas* (Facturación total, Sedes activas, Espacios asignados).
   - Fila central izquierda: *Mapa de Sedes (K6)*.
   - Fila central derecha: *Criterios de Asignación (K3)* e *Ingresos por Sede (K1)*.
   - Fila inferior: *Evolución de Ingresos (K4)* y *Tabla del Reporte E7*.
4. **Filtros de Dashboard (Opcional):**
   - Añadir filtro por **Fase** o **Sede** y conectarlo con las preguntas que soportan las variables `[[AND idSede = {{idSede}}]]`.

---

## 7. Privacidad y Seguridad (Plan de Cifrado E8)

El usuario y rol `rol_BI` cumplen estrictamente con la política de seguridad:
- No tienen acceso a nombres, apellidos, documentos ni teléfonos de jugadores o árbitros.
- La pregunta `07_k7_goles_por_seleccion.sql` consulta los goles a nivel selección nacional, protegiendo los datos individuales del deportista.
- Todo acceso a reportes con datos personales está bloqueado a nivel de base de datos (`DENY SELECT` y falta de `EXECUTE`).
