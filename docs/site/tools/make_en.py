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
"""
import json, re, os
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))          # docs/site
PAIRS = json.load(open(os.path.join(HERE, "en-pairs.json")))
src = open(os.path.join(ROOT, "es/index.html")).read()
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
open(os.path.join(ROOT, "index.html"), "w").write(en)
print(f"index.html (inglés, raíz) escrita · {len(PAIRS)} pares · sin correspondencia en el español actual: {len(missing)}")
for m in missing[:10]: print("  ·", m.strip()[:90])
