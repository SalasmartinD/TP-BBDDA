## Qué hace esta PR

<!-- Una o dos oraciones: qué se agrega o cambia y para qué. -->

## Entrega y área

- **Entrega:** <!-- E4, E5, E6, E7, E8 o E9 -->
- **Área:** <!-- Torneo y Equipos / Partidos y Arbitraje / Publicidad / transversal -->

## Archivos

<!-- Lista de archivos agregados o modificados, con una línea sobre cada uno. -->

- `NN_Archivo.sql`: 

## Depende de

<!-- Si esta PR necesita otra que todavía no está en main, poné su número (ej: Depende de #4)
     y elegí como base la rama de esa PR. Si no depende de ninguna, poné "Ninguna". -->

Ninguna

## Cómo probarlo

<!-- Pasos para que quien revisa lo ejecute en su base local. -->

1. Recrear la base desde cero ejecutando los scripts en orden hasta `NN_...`.
2. Ejecutar `8N_Test_....sql`.
3. Resultado esperado: 

## Checklist

- [ ] La base se recrea desde cero sin errores con estos cambios.
- [ ] Cada script nuevo tiene el encabezado (universidad, materia, integrantes, fecha y objetivo).
- [ ] Los SP usan el patrón de validación (todos los errores en un único `THROW`).
- [ ] Cada script de SP tiene su script de testing, con casos exitosos y casos que fallan, y el resultado esperado comentado.
- [ ] No hay datos privados ni claves de API.
