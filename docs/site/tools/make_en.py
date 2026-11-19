#!/usr/bin/env python3
"""Genera docs/site/index.html (inglés, la página principal) a partir de
docs/site/es/index.html (la fuente en español, que es la que se edita a mano).

El sitio se escribe en español y esta herramienta produce la versión inglesa. Cada
línea española que cambia en inglés está en en-pairs.json (línea completa es → en);
las líneas sin par se copian tal cual. Al editar la página española: si tocas una línea
traducida, actualiza su par aquí.

La página inglesa vive en la raíz y la española en /es/, así que además de traducir hay
que subir un nivel las rutas relativas (la fuente usa ../img y ../video) y apuntar a las
capturas inglesas (img/en/…); los símbolos (img/sym) se comparten. Ejecutar desde
cualquier sitio:
    python3 docs/site/tools/make_en.py
    python3 docs/site/tools/make_en.py --check

--check no escribe: dice si la página inglesa publicada es la que saldría hoy. Hace falta
porque la inglesa se ha editado a mano más de una vez, y eso no se nota hasta que alguien
regenera: entonces esas líneas vuelven al español de golpe. Va en la lista de publicación.
"""
import json, re, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))          # docs/site
DEST = os.path.join(ROOT, "index.html")
# Explícito en todo: la página va llena de acentos, « » y —, y la comparación de --check
# solo significa algo si leer y escribir usan la misma codificación pase lo que pase.
PAIRS = json.load(open(os.path.join(HERE, "en-pairs.json"), encoding="utf-8"))


def generar():
    """Devuelve la página inglesa y los pares que ya no casan con el español."""
    src = open(os.path.join(ROOT, "es/index.html"), encoding="utf-8").read()
    # La fuente española lleva su propio conmutador (enlace al inglés, en la raíz); se quita
    # aquí y luego se inserta el del inglés (enlace al español, en /es/) antes del botón de
    # descarga.
    src_no_lang = re.sub(r'\s*<a class="lang" href="\.\./" lang="en" title="English version">EN</a>', "", src)
    lines = src_no_lang.split("\n")
    missing = [es for es in PAIRS if es not in lines]
    out = [PAIRS.get(l, l) for l in lines]
    en = "\n".join(out)
    # Rutas: la fuente española está en /es/ (usa ../img, ../video); el inglés va en la raíz.
    # Las capturas de la página inglesa están en img/en/; los símbolos (img/sym) no cambian.
    # Las líneas traducidas ya traen la ruta inglesa correcta desde el par; esto arregla las
    # que no tienen par (símbolos) y sirve de red por si se añade alguna imagen nueva.
    en = en.replace('src="../img/notch-', 'src="img/en/notch-').replace('src="../img/menu.png', 'src="img/en/menu.png')
    en = en.replace('poster="../img/video-poster.jpg', 'poster="img/en/video-poster.jpg')
    en = en.replace('src="../img/', 'src="img/').replace('href="../img/', 'href="img/').replace('src="../video/', 'src="video/')
    en = en.replace('<a class="pill" href="#descargar">Download</a>', '<a class="lang" href="es/" lang="es" title="Versión en español">ES</a>\n    <a class="pill" href="#descargar">Download</a>')
    return en, missing


# Un argumento mal escrito no puede acabar sobrescribiendo la página en silencio.
args = sys.argv[1:]
if args not in ([], ["--check"]):
    sys.exit("uso: make_en.py [--check]")

en, missing = generar()

if args == ["--check"]:
    problemas = []
    # newline="" para comparar el fichero tal y como está, sin que Python toque los saltos.
    publicada = open(DEST, encoding="utf-8", newline="").read() if os.path.exists(DEST) else None
    if publicada is None:
        problemas.append("no existe docs/site/index.html")
    elif publicada != en:
        viejas, nuevas = publicada.split("\n"), en.split("\n")
        distintas = [i + 1 for i in range(min(len(viejas), len(nuevas))) if viejas[i] != nuevas[i]]
        partes = []
        if distintas:
            partes.append(f"{len(distintas)} línea(s) distinta(s): " + ", ".join(str(n) for n in distintas[:10]) + ("…" if len(distintas) > 10 else ""))
        if len(viejas) != len(nuevas):
            partes.append(f"pasaría de {len(viejas)} a {len(nuevas)} líneas")
        problemas.append("regenerar cambiaría docs/site/index.html · " + " · ".join(partes))
        for n in distintas[:3]:
            problemas.append(f"  línea {n} publicada: {viejas[n - 1].strip()[:100]}")
            problemas.append(f"  línea {n} saldría:   {nuevas[n - 1].strip()[:100]}")
    if missing:
        problemas.append(f"{len(missing)} par(es) de en-pairs.json ya no casan con ninguna línea del español:")
        problemas += [f"  · {m.strip()[:90]}" for m in missing[:10]]
    if problemas:
        print("make_en.py --check: la página inglesa no es la que saldría hoy")
        for p in problemas: print(p)
        print("Se arregla en en-pairs.json, no editando la página inglesa; luego make_en.py sin --check.")
        sys.exit(1)
    print(f"make_en.py --check: al día · {len(PAIRS)} pares")
    sys.exit(0)

open(DEST, "w", encoding="utf-8").write(en)
print(f"index.html (inglés, raíz) escrita · {len(PAIRS)} pares · sin correspondencia en el español actual: {len(missing)}")
for m in missing[:10]: print("  ·", m.strip()[:90])
