Markdown
# Aplicación de Gestión de Publicidad y Soporte · Entrega 9
## Sistema de Registro y Gestión del Mundial de Fútbol · Comisión 2900
### Grupo 09

Aplicación interactiva desarrollada en **Blazor Server (.NET 8)** para la gestión del padrón de anunciantes (ABM) e importación masiva de datos en SQL Server.

---

## 1. Características

- **ABM de Anunciante (Módulo H):**
  - Alta, Modificación y Baja operando exclusivamente a través de Stored Procedures (`Publicidad.Anunciante_Alta`, `Publicidad.Anunciante_Modificacion`, `Publicidad.Anunciante_Baja`).
  - Sin sentencias `INSERT`, `UPDATE` ni `DELETE` directas sobre tablas.
  - Validación de reglas de negocio en base de datos: unicidad de nombre, formato ISO de moneda (3 letras mayúsculas), existencia de país y restricción de baja para anunciantes con campañas registradas.
  - Parsing de errores de validación (`THROW 50001`/`50002`) visualizados en la UI de forma limpia y desglosada, ocultando detalles técnicos del motor.
  - Catálogos de países y monedas cargados desde vistas (`Torneo.vw_PaisCatalogo` y `Publicidad.vw_MonedaCatalogo`).
- **Importación XML y Reportes (Extra elegido):**
  - Subida de archivos XML de árbitros ejecutando `Arbitraje.Importar_ArbitrosXMLDatos` mediante variable set-based (sin necesidad de permisos de servidor ni acceso al filesystem local de SQL Server).
  - Resumen en tiempo real (filas leídas, insertadas, actualizadas y con error).
  - Visualización de errores parciales de importación a través de la vista sanitizada `Sistema.vw_ErrorImportacion`.
  - Descarga directa del reporte XML oficial `Equipos.Reporte_SeleccionesPlantillas`.

---

## 2. Requisitos Previos

- **.NET 8 SDK** (o superior).
- **SQL Server 2022** con la base de datos `MundialFutbol` creada y con los scripts ejecutados (hasta el `71b_Roles_BI_App.sql`), más los logins locales creados a partir de `bi/local/crear_logins.sql.example`.

---

## 3. Configuración de Conexión (Seguridad y Menor Privilegio)

Por política del proyecto, **no se versionan contraseñas en el repositorio**. La aplicación separa las conexiones por responsabilidad:

- `MundialFutbol`: usa `login_app` (`rol_GestorPublicidad`), con permisos exclusivos para el ABM de anunciantes y sus vistas de catálogo.
- `MundialFutbolImportacion`: usa `login_import` (`rol_ImportadorApp`), con permisos acotados a `Arbitraje.Importar_ArbitrosXMLDatos`, `Equipos.Reporte_SeleccionesPlantillas` y `Sistema.vw_ErrorImportacion` (sin exponer datos personales ni reportes descifrados al rol de gestión publicitaria).

1. El archivo `appsettings.json` contiene la plantilla:
   ```json
   "ConnectionStrings": {
     "MundialFutbol": "Server=localhost;Database=MundialFutbol;User Id=login_app;Password=<PASSWORD_APP>;TrustServerCertificate=True;Encrypt=True;",
     "MundialFutbolImportacion": "Server=localhost;Database=MundialFutbol;User Id=login_import;Password=<PASSWORD_IMPORT>;TrustServerCertificate=True;Encrypt=True;"
   }
2. Para desarrollo local, cree el archivo `appsettings.Development.json` (ignorado por Git) en esta misma carpeta con sus credenciales locales o Windows Authentication:
   ```json
{
  "ConnectionStrings": {
    "MundialFutbol": "Server=localhost;Database=MundialFutbol;User Id=login_app;Password=SU_PASSWORD_APP;TrustServerCertificate=True;Encrypt=True;",
    "MundialFutbolImportacion": "Server=localhost;Database=MundialFutbol;User Id=login_import;Password=SU_PASSWORD_IMPORT;TrustServerCertificate=True;Encrypt=True;"
  }
}
   ```

---

## 4. Cómo Ejecutar la Aplicación

Desde una terminal situada en la carpeta `app/GestionPublicidad`:

```bash
dotnet run
```

La aplicación quedará disponible en el navegador según Properties/launchSettings.json en http://localhost:5274 o https://localhost:7168.