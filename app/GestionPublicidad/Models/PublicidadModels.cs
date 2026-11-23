namespace GestionPublicidad.Models;

public class AnuncianteItem
{
    public int Id { get; set; }
    public string Nombre { get; set; } = string.Empty;
    public string? Rubro { get; set; }
    public int IdPais { get; set; }
    public string Pais { get; set; } = string.Empty;
    public string PaisCodigoISO3 { get; set; } = string.Empty;
    public string MonedaFacturacion { get; set; } = "USD";
    public int CantCampaniasTotal { get; set; }
    public int CantCampaniasActivas { get; set; }
    public int CantCampaniasVencidas { get; set; }

    public bool PuedeDarseDeBaja => CantCampaniasTotal == 0;
}

public class AnuncianteForm
{
    public int Id { get; set; }
    public string Nombre { get; set; } = string.Empty;
    public string? Rubro { get; set; }
    public int IdPais { get; set; }
    public string MonedaFacturacion { get; set; } = "USD";
}

public class PaisItem
{
    public int Id { get; set; }
    public string Nombre { get; set; } = string.Empty;
    public string CodigoISO2 { get; set; } = string.Empty;
    public string CodigoISO3 { get; set; } = string.Empty;
}

public class MonedaItem
{
    public string Moneda { get; set; } = string.Empty;
}

public class ResumenImportacion
{
    public string Archivo { get; set; } = string.Empty;
    public string Origen { get; set; } = string.Empty;
    public int CantFilas { get; set; }
    public int CantInsertados { get; set; }
    public int CantActualizados { get; set; }
    public int CantErrores { get; set; }
}

public class ErrorImportacionItem
{
    public int Id { get; set; }
    public DateTime FechaHora { get; set; }
    public string Archivo { get; set; } = string.Empty;
    public string TablaDestino { get; set; } = string.Empty;
    public int? NroFila { get; set; }
    public string MensajeError { get; set; } = string.Empty;
}
