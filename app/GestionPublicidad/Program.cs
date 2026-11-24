using GestionPublicidad.Components;
using GestionPublicidad.Data;

var builder = WebApplication.CreateBuilder(args);

// Inyección de Razor Components y servidor interactivo
builder.Services.AddRazorComponents()
    .AddInteractiveServerComponents();

// Registrar servicio de acceso a datos con SqlClient
builder.Services.AddScoped<PublicidadDataService>();

var app = builder.Build();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error", createScopeForErrors: true);
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();
app.UseAntiforgery();

app.MapRazorComponents<App>()
    .AddInteractiveServerRenderMode();

app.Run();
