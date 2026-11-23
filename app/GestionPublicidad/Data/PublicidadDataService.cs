using System.Data;
using Microsoft.Data.SqlClient;
using GestionPublicidad.Models;

namespace GestionPublicidad.Data;

public class PublicidadDataService
{
    private readonly string _connectionString;

    public PublicidadDataService(IConfiguration configuration)
    {
        _connectionString = configuration.GetConnectionString("MundialFutbol")
            ?? throw new InvalidOperationException("No se encontró la cadena de conexión 'MundialFutbol'.");
    }

    private SqlConnection CreateConnection() => new SqlConnection(_connectionString);

    #region Lecturas de Catálogos y Listados (Vistas)

    public async Task<List<AnuncianteItem>> ObtenerAnunciantesAsync()
    {
        var lista = new List<AnuncianteItem>();
        using var conn = CreateConnection();
        await conn.OpenAsync();

        using var cmd = new SqlCommand(@"
            SELECT id, nombre, rubro, idPais, pais, paisCodigoISO3, monedaFacturacion,
                   cantCampaniasTotal, cantCampaniasActivas, cantCampaniasVencidas
            FROM Publicidad.vw_AnuncianteListado
            ORDER BY nombre;", conn);

        using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            lista.Add(new AnuncianteItem
            {
                Id = reader.GetInt32(0),
                Nombre = reader.GetString(1),
                Rubro = reader.IsDBNull(2) ? null : reader.GetString(2),
                IdPais = reader.GetInt32(3),
                Pais = reader.GetString(4),
                PaisCodigoISO3 = reader.GetString(5),
                MonedaFacturacion = reader.GetString(6),
                CantCampaniasTotal = reader.GetInt32(7),
                CantCampaniasActivas = reader.GetInt32(8),
                CantCampaniasVencidas = reader.GetInt32(9)
            });
        }
        return lista;
    }

    public async Task<List<PaisItem>> ObtenerPaisesAsync()
    {
        var lista = new List<PaisItem>();
        using var conn = CreateConnection();
        await conn.OpenAsync();

        using var cmd = new SqlCommand(@"
            SELECT id, nombre, codigoISO2, codigoISO3
            FROM Torneo.vw_PaisCatalogo
            ORDER BY nombre;", conn);

        using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            lista.Add(new PaisItem
            {
                Id = reader.GetInt32(0),
                Nombre = reader.GetString(1),
                CodigoISO2 = reader.GetString(2),
                CodigoISO3 = reader.GetString(3)
            });
        }
        return lista;
    }

    public async Task<List<MonedaItem>> ObtenerMonedasAsync()
    {
        var lista = new List<MonedaItem>();
        using var conn = CreateConnection();
        await conn.OpenAsync();

        using var cmd = new SqlCommand(@"
            SELECT moneda
            FROM Publicidad.vw_MonedaCatalogo
            ORDER BY moneda;", conn);

        using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            lista.Add(new MonedaItem
            {
                Moneda = reader.GetString(0).Trim()
            });
        }
        return lista;
    }

    #endregion

    #region Operaciones ABM mediante Stored Procedures

    public async Task CrearAnuncianteAsync(AnuncianteForm form)
    {
        using var conn = CreateConnection();
        await conn.OpenAsync();

        using var cmd = new SqlCommand("Publicidad.Anunciante_Alta", conn)
        {
            CommandType = CommandType.StoredProcedure
        };

        cmd.Parameters.Add(new SqlParameter("@nombre", SqlDbType.NVarChar, 100) { Value = form.Nombre.Trim() });
        cmd.Parameters.Add(new SqlParameter("@rubro", SqlDbType.VarChar, 50)
        {
            Value = string.IsNullOrWhiteSpace(form.Rubro) ? DBNull.Value : form.Rubro.Trim()
        });
        cmd.Parameters.Add(new SqlParameter("@idPais", SqlDbType.Int) { Value = form.IdPais });
        cmd.Parameters.Add(new SqlParameter("@monedaFacturacion", SqlDbType.Char, 3)
        {
            Value = (form.MonedaFacturacion ?? "USD").Trim().ToUpperInvariant()
        });

        await cmd.ExecuteNonQueryAsync();
    }

    public async Task ModificarAnuncianteAsync(AnuncianteForm form)
    {
        using var conn = CreateConnection();
        await conn.OpenAsync();

        using var cmd = new SqlCommand("Publicidad.Anunciante_Modificacion", conn)
        {
            CommandType = CommandType.StoredProcedure
        };

        cmd.Parameters.Add(new SqlParameter("@id", SqlDbType.Int) { Value = form.Id });
        cmd.Parameters.Add(new SqlParameter("@nombre", SqlDbType.NVarChar, 100) { Value = form.Nombre.Trim() });
        cmd.Parameters.Add(new SqlParameter("@rubro", SqlDbType.VarChar, 50)
        {
            Value = string.IsNullOrWhiteSpace(form.Rubro) ? DBNull.Value : form.Rubro.Trim()
        });
        cmd.Parameters.Add(new SqlParameter("@idPais", SqlDbType.Int) { Value = form.IdPais });
        cmd.Parameters.Add(new SqlParameter("@monedaFacturacion", SqlDbType.Char, 3)
        {
            Value = (form.MonedaFacturacion ?? "USD").Trim().ToUpperInvariant()
        });

        await cmd.ExecuteNonQueryAsync();
    }

    public async Task EliminarAnuncianteAsync(int id)
    {
        using var conn = CreateConnection();
        await conn.OpenAsync();

        using var cmd = new SqlCommand("Publicidad.Anunciante_Baja", conn)
        {
            CommandType = CommandType.StoredProcedure
        };

        cmd.Parameters.Add(new SqlParameter("@id", SqlDbType.Int) { Value = id });

        await cmd.ExecuteNonQueryAsync();
    }

    #endregion

    #region Extra: Importación XML y Reporte XML

    public async Task<ResumenImportacion> ImportarArbitrosXmlAsync(string xmlContenido, string nombreArchivo)
    {
        using var conn = CreateConnection();
        await conn.OpenAsync();

        string origenUnico = $"{nombreArchivo}_{DateTime.Now:yyyyMMddHHmmss}";

        using var cmd = new SqlCommand("Arbitraje.Importar_ArbitrosXMLDatos", conn)
        {
            CommandType = CommandType.StoredProcedure
        };

        cmd.Parameters.Add(new SqlParameter("@xml", SqlDbType.Xml) { Value = xmlContenido });
        cmd.Parameters.Add(new SqlParameter("@origen", SqlDbType.NVarChar, 260) { Value = origenUnico });

        var pCantFilas = cmd.Parameters.Add(new SqlParameter("@cantFilas", SqlDbType.Int) { Direction = ParameterDirection.Output });
        var pCantInsert = cmd.Parameters.Add(new SqlParameter("@cantInsertados", SqlDbType.Int) { Direction = ParameterDirection.Output });
        var pCantActual = cmd.Parameters.Add(new SqlParameter("@cantActualizados", SqlDbType.Int) { Direction = ParameterDirection.Output });
        var pCantError = cmd.Parameters.Add(new SqlParameter("@cantErrores", SqlDbType.Int) { Direction = ParameterDirection.Output });

        await cmd.ExecuteNonQueryAsync();

        return new ResumenImportacion
        {
            Archivo = nombreArchivo,
            Origen = origenUnico,
            CantFilas = pCantFilas.Value != DBNull.Value ? (int)pCantFilas.Value : 0,
            CantInsertados = pCantInsert.Value != DBNull.Value ? (int)pCantInsert.Value : 0,
            CantActualizados = pCantActual.Value != DBNull.Value ? (int)pCantActual.Value : 0,
            CantErrores = pCantError.Value != DBNull.Value ? (int)pCantError.Value : 0
        };
    }

    public async Task<List<ErrorImportacionItem>> ObtenerErroresImportacionAsync(string origen)
    {
        var lista = new List<ErrorImportacionItem>();
        using var conn = CreateConnection();
        await conn.OpenAsync();

        using var cmd = new SqlCommand(@"
            SELECT id, fechaHora, archivo, tablaDestino, nroFila, mensajeError
            FROM Sistema.vw_ErrorImportacion
            WHERE archivo = @origen
            ORDER BY id;", conn);

        cmd.Parameters.Add(new SqlParameter("@origen", SqlDbType.NVarChar, 260) { Value = origen });

        using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            lista.Add(new ErrorImportacionItem
            {
                Id = reader.GetInt32(0),
                FechaHora = reader.GetDateTime(1),
                Archivo = reader.GetString(2),
                TablaDestino = reader.GetString(3),
                NroFila = reader.IsDBNull(4) ? null : reader.GetInt32(4),
                MensajeError = reader.GetString(5)
            });
        }
        return lista;
    }

    public async Task<string> DescargarXmlPlantillasAsync()
    {
        using var conn = CreateConnection();
        await conn.OpenAsync();

        using var cmd = new SqlCommand("Equipos.Reporte_SeleccionesPlantillas", conn)
        {
            CommandType = CommandType.StoredProcedure
        };

        var result = await cmd.ExecuteScalarAsync();
        return result?.ToString() ?? string.Empty;
    }

    #endregion

    #region Utilidad de Traducción de Errores THROW 50001 / 50002 / 50003

    public static List<string> ParseSqlExceptions(SqlException ex)
    {
        var lineas = new List<string>();
        if (ex.Number == 50001 || ex.Number == 50002 || ex.Number == 50003)
        {
            var raw = ex.Message.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
            foreach (var l in raw)
            {
                var trim = l.Trim();
                if (string.IsNullOrWhiteSpace(trim)) continue;
                if (trim.StartsWith("- "))
                    lineas.Add(trim.Substring(2));
                else if (trim.EndsWith(":"))
                    continue; // Cabecera del SP
                else
                    lineas.Add(trim);
            }
        }
        else
        {
            lineas.Add("Ocurrió un error en la base de datos: " + ex.Message);
        }

        return lineas.Count > 0 ? lineas : new List<string> { ex.Message };
    }

    #endregion
}
