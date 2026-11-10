# -*- coding: utf-8 -*-
"""
Scraping de la Lista Internacional de Árbitros FIFA -> XML
=========================================================
Materia : 3641 Bases de Datos Aplicada (UNLaM) - Com. 2900
Entrega : 6 - Importación y scraping (script 41)
Fuente  : https://inside.fifa.com/refereeing/international-referees

Técnica
-------
La página está construida con Next.js. El servidor ya devuelve, dentro del HTML,
un bloque <script id="__NEXT_DATA__" type="application/json"> con todo el
contenido de la página (incluida la lista completa de oficiales). Por eso no
hace falta un navegador ni ejecutar JavaScript: se descarga el HTML con una
petición HTTP GET, se extrae ese bloque, se parsea como JSON y se recorre el
árbol buscando los objetos que representan un oficial.

Salida
------
arbitros_fifa.xml (en la misma carpeta que este script), con solo los datos que
necesita la tabla Arbitraje.Arbitro (y Arbitraje.ArbitroIdioma), ya adaptados
a las validaciones de Arbitraje.Arbitro_Alta / Arbitraje.ArbitroIdioma_Alta.

Uso
---
    python scrap_fifa_arbitros.py                 # descarga la página
    python scrap_fifa_arbitros.py --html pag.html # reprocesa un HTML guardado
    python scrap_fifa_arbitros.py --max 500 --salida arbitros_fifa_reducido.xml
                                                  # muestra estratificada de hasta 500

Solo usa la biblioteca estándar de Python (3.9+).
"""

import argparse
import json
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
from collections import Counter
from datetime import date
from pathlib import Path

URL = "https://inside.fifa.com/refereeing/international-referees"
USER_AGENT = "Mozilla/5.0 (TP academico UNLaM - Bases de Datos Aplicada)"
SALIDA = Path(__file__).with_name("arbitros_fifa.xml")

# Roles de fútbol 11. Se excluyen "Futsal Referee" y "Beach Soccer Referee".
ROLES_FUTBOL_11 = {"Referee", "Assistant Referee", "Video Match Official"}

GENERO = {"Male": "Masculino", "Female": "Femenino"}

# ---------------------------------------------------------------------------
# Tabla de países: código FIFA -> (nombre en español, ISO2, ISO3, idiomas)
#   - El código FIFA sale de la URL de la bandera que trae la fuente.
#   - ISO 3166-1 alfa-2 / alfa-3 para enlazar con Torneo.Pais.
#     Inglaterra, Escocia, Gales e Irlanda del Norte no tienen código ISO propio
#     (son parte del Reino Unido): quedan vacíos y se enlazan por nombre.
#     Kosovo usa XK / XKX (códigos de uso generalizado, asignados por usuario).
#   - Idiomas (ISO 639-1): DATO SINTÉTICO. La fuente no informa idiomas. Se
#     asignan los idiomas oficiales o predominantes del país del árbitro.
#     A todos se les agrega además el inglés ('en'), idioma de trabajo de
#     FIFA en las competiciones internacionales.
# ---------------------------------------------------------------------------
PAISES = {
    "AFG": ("Afganistán", "AF", "AFG", "ps fa"),
    "AIA": ("Anguila", "AI", "AIA", "en"),
    "ALB": ("Albania", "AL", "ALB", "sq"),
    "ALG": ("Argelia", "DZ", "DZA", "ar fr"),
    "AND": ("Andorra", "AD", "AND", "ca es"),
    "ANG": ("Angola", "AO", "AGO", "pt"),
    "ARG": ("Argentina", "AR", "ARG", "es"),
    "ARM": ("Armenia", "AM", "ARM", "hy ru"),
    "ARU": ("Aruba", "AW", "ABW", "nl es"),
    "ATG": ("Antigua y Barbuda", "AG", "ATG", "en"),
    "AUS": ("Australia", "AU", "AUS", "en"),
    "AUT": ("Austria", "AT", "AUT", "de"),
    "AZE": ("Azerbaiyán", "AZ", "AZE", "az ru"),
    "BAH": ("Bahamas", "BS", "BHS", "en"),
    "BAN": ("Bangladés", "BD", "BGD", "bn"),
    "BDI": ("Burundi", "BI", "BDI", "rn fr"),
    "BEL": ("Bélgica", "BE", "BEL", "nl fr"),
    "BEN": ("Benín", "BJ", "BEN", "fr"),
    "BER": ("Bermudas", "BM", "BMU", "en"),
    "BFA": ("Burkina Faso", "BF", "BFA", "fr"),
    "BHR": ("Baréin", "BH", "BHR", "ar"),
    "BHU": ("Bután", "BT", "BTN", "dz"),
    "BIH": ("Bosnia y Herzegovina", "BA", "BIH", "bs hr sr"),
    "BLR": ("Bielorrusia", "BY", "BLR", "be ru"),
    "BLZ": ("Belice", "BZ", "BLZ", "en es"),
    "BOL": ("Bolivia", "BO", "BOL", "es"),
    "BOT": ("Botsuana", "BW", "BWA", "tn"),
    "BRA": ("Brasil", "BR", "BRA", "pt"),
    "BRB": ("Barbados", "BB", "BRB", "en"),
    "BRU": ("Brunéi", "BN", "BRN", "ms"),
    "BUL": ("Bulgaria", "BG", "BGR", "bg"),
    "CAM": ("Camboya", "KH", "KHM", "km"),
    "CAN": ("Canadá", "CA", "CAN", "en fr"),
    "CAY": ("Islas Caimán", "KY", "CYM", "en"),
    "CGO": ("Congo", "CG", "COG", "fr"),
    "CHA": ("Chad", "TD", "TCD", "fr ar"),
    "CHI": ("Chile", "CL", "CHL", "es"),
    "CHN": ("China", "CN", "CHN", "zh"),
    "CIV": ("Costa de Marfil", "CI", "CIV", "fr"),
    "CMR": ("Camerún", "CM", "CMR", "fr"),
    "COD": ("República Democrática del Congo", "CD", "COD", "fr"),
    "COL": ("Colombia", "CO", "COL", "es"),
    "COM": ("Comoras", "KM", "COM", "ar fr"),
    "CPV": ("Cabo Verde", "CV", "CPV", "pt"),
    "CRC": ("Costa Rica", "CR", "CRI", "es"),
    "CRO": ("Croacia", "HR", "HRV", "hr"),
    "CTA": ("República Centroafricana", "CF", "CAF", "fr sg"),
    "CUB": ("Cuba", "CU", "CUB", "es"),
    "CUW": ("Curazao", "CW", "CUW", "nl"),
    "CYP": ("Chipre", "CY", "CYP", "el tr"),
    "CZE": ("Chequia", "CZ", "CZE", "cs"),
    "DEN": ("Dinamarca", "DK", "DNK", "da"),
    "DJI": ("Yibuti", "DJ", "DJI", "fr ar"),
    "DMA": ("Dominica", "DM", "DMA", "en"),
    "DOM": ("República Dominicana", "DO", "DOM", "es"),
    "ECU": ("Ecuador", "EC", "ECU", "es"),
    "EGY": ("Egipto", "EG", "EGY", "ar"),
    "ENG": ("Inglaterra", "", "", "en"),
    "EQG": ("Guinea Ecuatorial", "GQ", "GNQ", "es fr"),
    "ERI": ("Eritrea", "ER", "ERI", "ti ar"),
    "ESP": ("España", "ES", "ESP", "es"),
    "EST": ("Estonia", "EE", "EST", "et"),
    "ETH": ("Etiopía", "ET", "ETH", "am"),
    "FIJ": ("Fiyi", "FJ", "FJI", "en fj"),
    "FIN": ("Finlandia", "FI", "FIN", "fi sv"),
    "FRA": ("Francia", "FR", "FRA", "fr"),
    "FRO": ("Islas Feroe", "FO", "FRO", "fo da"),
    "GAB": ("Gabón", "GA", "GAB", "fr"),
    "GAM": ("Gambia", "GM", "GMB", "en"),
    "GEO": ("Georgia", "GE", "GEO", "ka"),
    "GER": ("Alemania", "DE", "DEU", "de"),
    "GHA": ("Ghana", "GH", "GHA", "en"),
    "GIB": ("Gibraltar", "GI", "GIB", "en"),
    "GNB": ("Guinea-Bisáu", "GW", "GNB", "pt"),
    "GRE": ("Grecia", "GR", "GRC", "el"),
    "GRN": ("Granada", "GD", "GRD", "en"),
    "GUA": ("Guatemala", "GT", "GTM", "es"),
    "GUI": ("Guinea", "GN", "GIN", "fr"),
    "GUY": ("Guyana", "GY", "GUY", "en"),
    "HAI": ("Haití", "HT", "HTI", "fr ht"),
    "HKG": ("Hong Kong", "HK", "HKG", "zh"),
    "HON": ("Honduras", "HN", "HND", "es"),
    "HUN": ("Hungría", "HU", "HUN", "hu"),
    "IDN": ("Indonesia", "ID", "IDN", "id"),
    "IND": ("India", "IN", "IND", "hi"),
    "IRL": ("Irlanda", "IE", "IRL", "ga"),
    "IRN": ("Irán", "IR", "IRN", "fa"),
    "IRQ": ("Irak", "IQ", "IRQ", "ar ku"),
    "ISL": ("Islandia", "IS", "ISL", "is"),
    "ISR": ("Israel", "IL", "ISR", "he ar"),
    "ITA": ("Italia", "IT", "ITA", "it"),
    "JAM": ("Jamaica", "JM", "JAM", "en"),
    "JOR": ("Jordania", "JO", "JOR", "ar"),
    "JPN": ("Japón", "JP", "JPN", "ja"),
    "KAZ": ("Kazajistán", "KZ", "KAZ", "kk ru"),
    "KEN": ("Kenia", "KE", "KEN", "sw"),
    "KGZ": ("Kirguistán", "KG", "KGZ", "ky ru"),
    "KOR": ("Corea del Sur", "KR", "KOR", "ko"),
    "KOS": ("Kosovo", "XK", "XKX", "sq sr"),
    "KSA": ("Arabia Saudita", "SA", "SAU", "ar"),
    "KUW": ("Kuwait", "KW", "KWT", "ar"),
    "LAO": ("Laos", "LA", "LAO", "lo"),
    "LBN": ("Líbano", "LB", "LBN", "ar fr"),
    "LBR": ("Liberia", "LR", "LBR", "en"),
    "LBY": ("Libia", "LY", "LBY", "ar"),
    "LCA": ("Santa Lucía", "LC", "LCA", "en"),
    "LES": ("Lesoto", "LS", "LSO", "st"),
    "LTU": ("Lituania", "LT", "LTU", "lt"),
    "LUX": ("Luxemburgo", "LU", "LUX", "lb fr de"),
    "LVA": ("Letonia", "LV", "LVA", "lv"),
    "MAC": ("Macao", "MO", "MAC", "zh pt"),
    "MAD": ("Madagascar", "MG", "MDG", "mg fr"),
    "MAR": ("Marruecos", "MA", "MAR", "ar fr"),
    "MAS": ("Malasia", "MY", "MYS", "ms"),
    "MDA": ("Moldavia", "MD", "MDA", "ro"),
    "MDV": ("Maldivas", "MV", "MDV", "dv"),
    "MEX": ("México", "MX", "MEX", "es"),
    "MKD": ("Macedonia del Norte", "MK", "MKD", "mk"),
    "MLI": ("Malí", "ML", "MLI", "fr"),
    "MLT": ("Malta", "MT", "MLT", "mt"),
    "MNE": ("Montenegro", "ME", "MNE", "sr"),
    "MNG": ("Mongolia", "MN", "MNG", "mn"),
    "MOZ": ("Mozambique", "MZ", "MOZ", "pt"),
    "MRI": ("Mauricio", "MU", "MUS", "fr"),
    "MTN": ("Mauritania", "MR", "MRT", "ar fr"),
    "MWI": ("Malaui", "MW", "MWI", "ny"),
    "MYA": ("Myanmar", "MM", "MMR", "my"),
    "NAM": ("Namibia", "NA", "NAM", "af"),
    "NCA": ("Nicaragua", "NI", "NIC", "es"),
    "NCL": ("Nueva Caledonia", "NC", "NCL", "fr"),
    "NED": ("Países Bajos", "NL", "NLD", "nl"),
    "NEP": ("Nepal", "NP", "NPL", "ne"),
    "NGA": ("Nigeria", "NG", "NGA", "en"),
    "NIG": ("Níger", "NE", "NER", "fr ha"),
    "NIR": ("Irlanda del Norte", "", "", "en"),
    "NOR": ("Noruega", "NO", "NOR", "no"),
    "NZL": ("Nueva Zelanda", "NZ", "NZL", "mi"),
    "OMA": ("Omán", "OM", "OMN", "ar"),
    "PAK": ("Pakistán", "PK", "PAK", "ur"),
    "PAN": ("Panamá", "PA", "PAN", "es"),
    "PAR": ("Paraguay", "PY", "PRY", "es gn"),
    "PER": ("Perú", "PE", "PER", "es"),
    "PHI": ("Filipinas", "PH", "PHL", "tl"),
    "PLE": ("Palestina", "PS", "PSE", "ar"),
    "PNG": ("Papúa Nueva Guinea", "PG", "PNG", "en"),
    "POL": ("Polonia", "PL", "POL", "pl"),
    "POR": ("Portugal", "PT", "PRT", "pt"),
    "PRK": ("Corea del Norte", "KP", "PRK", "ko"),
    "PUR": ("Puerto Rico", "PR", "PRI", "es"),
    "QAT": ("Catar", "QA", "QAT", "ar"),
    "ROU": ("Rumania", "RO", "ROU", "ro"),
    "RSA": ("Sudáfrica", "ZA", "ZAF", "af zu"),
    "RUS": ("Rusia", "RU", "RUS", "ru"),
    "RWA": ("Ruanda", "RW", "RWA", "rw fr"),
    "SAM": ("Samoa", "WS", "WSM", "sm"),
    "SCO": ("Escocia", "", "", "en"),
    "SDN": ("Sudán", "SD", "SDN", "ar"),
    "SEN": ("Senegal", "SN", "SEN", "fr wo"),
    "SEY": ("Seychelles", "SC", "SYC", "fr"),
    "SGP": ("Singapur", "SG", "SGP", "zh ms"),
    "SKN": ("San Cristóbal y Nieves", "KN", "KNA", "en"),
    "SLE": ("Sierra Leona", "SL", "SLE", "en"),
    "SLV": ("El Salvador", "SV", "SLV", "es"),
    "SMR": ("San Marino", "SM", "SMR", "it"),
    "SOL": ("Islas Salomón", "SB", "SLB", "en"),
    "SOM": ("Somalia", "SO", "SOM", "so ar"),
    "SRB": ("Serbia", "RS", "SRB", "sr"),
    "SRI": ("Sri Lanka", "LK", "LKA", "si ta"),
    "SSD": ("Sudán del Sur", "SS", "SSD", "ar"),
    "STP": ("Santo Tomé y Príncipe", "ST", "STP", "pt"),
    "SUI": ("Suiza", "CH", "CHE", "de fr it"),
    "SUR": ("Surinam", "SR", "SUR", "nl"),
    "SVK": ("Eslovaquia", "SK", "SVK", "sk"),
    "SVN": ("Eslovenia", "SI", "SVN", "sl"),
    "SWE": ("Suecia", "SE", "SWE", "sv"),
    "SWZ": ("Esuatini", "SZ", "SWZ", "ss"),
    "SYR": ("Siria", "SY", "SYR", "ar"),
    "TAN": ("Tanzania", "TZ", "TZA", "sw"),
    "TGA": ("Tonga", "TO", "TON", "to"),
    "THA": ("Tailandia", "TH", "THA", "th"),
    "TJK": ("Tayikistán", "TJ", "TJK", "tg ru"),
    "TKM": ("Turkmenistán", "TM", "TKM", "tk ru"),
    "TLS": ("Timor Oriental", "TL", "TLS", "pt"),
    "TOG": ("Togo", "TG", "TGO", "fr"),
    "TPE": ("China Taipéi", "TW", "TWN", "zh"),
    "TRI": ("Trinidad y Tobago", "TT", "TTO", "en"),
    "TUN": ("Túnez", "TN", "TUN", "ar fr"),
    "TUR": ("Turquía", "TR", "TUR", "tr"),
    "UAE": ("Emiratos Árabes Unidos", "AE", "ARE", "ar"),
    "UGA": ("Uganda", "UG", "UGA", "sw"),
    "UKR": ("Ucrania", "UA", "UKR", "uk"),
    "URU": ("Uruguay", "UY", "URY", "es"),
    "USA": ("Estados Unidos", "US", "USA", "en"),
    "UZB": ("Uzbekistán", "UZ", "UZB", "uz ru"),
    "VAN": ("Vanuatu", "VU", "VUT", "bi fr"),
    "VEN": ("Venezuela", "VE", "VEN", "es"),
    "VGB": ("Islas Vírgenes Británicas", "VG", "VGB", "en"),
    "VIE": ("Vietnam", "VN", "VNM", "vi"),
    "VIN": ("San Vicente y las Granadinas", "VC", "VCT", "en"),
    "WAL": ("Gales", "", "", "cy"),
    "YEM": ("Yemen", "YE", "YEM", "ar"),
    "ZAM": ("Zambia", "ZM", "ZMB", "en"),
    "ZIM": ("Zimbabue", "ZW", "ZWE", "sn"),
}


def descargar(url):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read().decode("utf-8")


def extraer_json(html):
    m = re.search(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', html, re.S)
    if not m:
        sys.exit("No se encontró el bloque __NEXT_DATA__: la estructura del sitio cambió.")
    return json.loads(m.group(1))


def buscar_oficiales(nodo):
    """Recorre el JSON y devuelve los objetos que representan un oficial."""
    if isinstance(nodo, dict):
        if "internationalSince" in nodo and "role" in nodo and "name" in nodo:
            yield nodo
        for v in nodo.values():
            yield from buscar_oficiales(v)
    elif isinstance(nodo, list):
        for x in nodo:
            yield from buscar_oficiales(x)


def es_apellido(token):
    """FIFA escribe el apellido en MAYÚSCULAS ('ARASA Nazareno Jose').
    Contempla prefijos escoceses/irlandeses: 'McMASTER'."""
    base = re.sub(r"^(Mc|Mac)(?=[A-ZÀ-Þ])", "", token)
    return any(c.isalpha() for c in base) and base == base.upper()


def separar_nombre(completo, cod_fifa=""):
    """Separa 'APELLIDO Nombre' en (nombre, apellido).

    Caso general: los tokens en MAYÚSCULAS son el apellido y el resto el nombre.
    Caso especial: si TODO el texto viene en mayúsculas (pasa en ~20 registros)
    no se puede distinguir por formato y se aplica una heurística:
      - País hispanohablante y 3+ palabras: las dos primeras son los apellidos
        (convención 'GARCIA ROMERO LEONEL').
      - Resto: la última palabra es el apellido y lo anterior el nombre
        ('PAULO ZANOVELLI', 'MOHAMMED ALSHAMMARI').
    Un nombre de una sola palabra (p. ej. árbitros de Bután, que no usan
    apellido) queda con un campo vacío y el SP lo envía a Sistema.ErrorImportacion.
    """
    tokens = completo.split()
    if len(tokens) > 1 and all(es_apellido(t) for t in tokens):
        idiomas = PAISES.get(cod_fifa, ("", "", "", ""))[3].split()
        corte = 2 if ("es" in idiomas and len(tokens) >= 3) else len(tokens) - 1
        if corte == 2:
            apellido, nombre = tokens[:2], tokens[2:]
        else:
            nombre, apellido = tokens[:corte], tokens[corte:]
        return " ".join(nombre).title(), " ".join(apellido)
    apellido = " ".join(t for t in tokens if es_apellido(t))
    nombre = " ".join(t for t in tokens if not es_apellido(t))
    return nombre, apellido


def codigo_fifa(oficial):
    flag = (oficial.get("country") or {}).get("flag") or ""
    return flag.rstrip("/").rsplit("/", 1)[-1].upper()


def muestra_estratificada(oficiales, maximo):
    """Devuelve como máximo `maximo` oficiales manteniendo la proporción de cada
    estrato (confederación + rol). Es determinística: dentro de cada estrato
    ordena por id FIFA y toma elementos equiespaciados, así cada corrida genera
    el mismo archivo. Los registros con nombre o apellido vacío se incluyen
    siempre, para que la versión reducida también pruebe la importación parcial."""
    if len(oficiales) <= maximo:
        return list(oficiales)

    forzados = [o for o in oficiales if "" in separar_nombre(o["name"], codigo_fifa(o))]
    ids_forzados = {o["id"] for o in forzados}
    resto = [o for o in oficiales if o["id"] not in ids_forzados]
    cupo_total = maximo - len(forzados)

    estratos = {}
    for o in resto:
        estratos.setdefault((o.get("confederation"), o["role"]["name"]), []).append(o)

    # Cupo proporcional por estrato (método del resto mayor)
    exactos = {k: len(v) * cupo_total / len(resto) for k, v in estratos.items()}
    cupos = {k: int(x) for k, x in exactos.items()}
    faltan = cupo_total - sum(cupos.values())
    for k in sorted(exactos, key=lambda k: exactos[k] - cupos[k], reverse=True)[:faltan]:
        cupos[k] += 1

    elegidos = list(forzados)
    for k, grupo in estratos.items():
        grupo = sorted(grupo, key=lambda o: int(o["id"]))
        n = cupos[k]
        if n:
            paso = len(grupo) / n
            elegidos += [grupo[int(i * paso)] for i in range(n)]
    return elegidos


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--html", help="procesar un HTML ya descargado en lugar de la URL")
    ap.add_argument("--max", type=int, help="genera una muestra estratificada de como máximo N árbitros")
    ap.add_argument("--salida", help="nombre del XML de salida (por defecto arbitros_fifa.xml)")
    args = ap.parse_args()
    salida = Path(args.salida) if args.salida else SALIDA

    html = Path(args.html).read_text(encoding="utf-8") if args.html else descargar(URL)
    datos = extraer_json(html)

    vistos, oficiales = set(), []
    for o in buscar_oficiales(datos):
        rol = (o.get("role") or {}).get("name")
        if rol in ROLES_FUTBOL_11 and o["id"] not in vistos:
            vistos.add(o["id"])
            oficiales.append(o)

    sin_mapeo = sorted({codigo_fifa(o) for o in oficiales} - PAISES.keys())
    if sin_mapeo:
        print("AVISO: países sin mapeo (se exportan con el nombre de la fuente):", sin_mapeo)

    if args.max:
        oficiales = muestra_estratificada(oficiales, args.max)

    raiz = ET.Element("Arbitros", {
        "fuente": URL,
        "fechaExtraccion": date.today().isoformat(),
        "cantidad": str(len(oficiales)),
    })

    for o in sorted(oficiales, key=lambda x: (codigo_fifa(x), x["name"])):
        nombre, apellido = separar_nombre(o["name"], codigo_fifa(o))
        cod = codigo_fifa(o)
        if cod in PAISES:
            nombre_pais, iso2, iso3, idiomas = PAISES[cod]
        else:
            nombre_pais = (o.get("country") or {}).get("name") or ""
            iso2 = iso3 = idiomas = ""
        lista_idiomas = list(dict.fromkeys(idiomas.split() + ["en"]))  # sin repetidos, 'en' al final
        anio = str(o.get("internationalSince") or "").strip()

        a = ET.SubElement(raiz, "Arbitro", {"idFifa": str(o["id"])})
        ET.SubElement(a, "Nombre").text = nombre
        ET.SubElement(a, "Apellido").text = apellido
        ET.SubElement(a, "Pais", {"codigoFIFA": cod, "codigoISO2": iso2, "codigoISO3": iso3}).text = nombre_pais
        ET.SubElement(a, "Categoria").text = "FIFA"
        ET.SubElement(a, "Genero").text = GENERO.get(o.get("gender"), "")
        ET.SubElement(a, "FechaInternacional").text = f"{anio}-01-01" if anio.isdigit() else ""
        nodo_idiomas = ET.SubElement(a, "Idiomas")
        for cod_idioma in lista_idiomas:
            ET.SubElement(nodo_idiomas, "Idioma").text = cod_idioma

    ET.indent(raiz)
    ET.ElementTree(raiz).write(salida, encoding="utf-8", xml_declaration=True)

    # Resumen
    por_rol = Counter(o["role"]["name"] for o in oficiales)
    por_conf = Counter(o.get("confederation") for o in oficiales)
    por_genero = Counter(GENERO.get(o.get("gender"), "") for o in oficiales)
    incompletos = [o["name"] for o in oficiales if "" in separar_nombre(o["name"], codigo_fifa(o))]
    print(f"Archivo generado: {salida}")
    print(f"Oficiales exportados: {len(oficiales)}  {dict(por_rol)}")
    print(f"Confederaciones: {dict(por_conf)}")
    print(f"Género: {dict(por_genero)}")
    print(f"Países: {len({codigo_fifa(o) for o in oficiales})}")
    if incompletos:
        print(f"Registros con nombre o apellido vacío (los rechazará el SP): {incompletos}")


if __name__ == "__main__":
    main()
