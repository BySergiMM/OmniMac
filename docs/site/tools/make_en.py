#!/usr/bin/env python3
"""Genera docs/site/en/index.html a partir de docs/site/index.html.

Cada línea española que cambia en la versión inglesa está en PAIRS (línea completa
es → en). Al editar la página española: si tocas una línea traducida, actualiza su par
aquí; las líneas sin par se copian tal cual. Ejecutar desde la raíz del repositorio:
    python3 docs/site/tools/make_en.py
"""
import json, re, os, sys
ROOT = os.path.dirname(os.path.abspath(__file__)) + "/../../.."
PAIRS = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "en-pairs.json")))
src = open(os.path.join(ROOT, "docs/site/index.html")).read()
src_no_lang = re.sub(r'\s*<a class="lang" href="en/" lang="en" title="English version">EN</a>', "", src)
lines = src_no_lang.split("\n")
missing = [es for es in PAIRS if es not in lines]
out = [PAIRS.get(l, l) for l in lines]
en = "\n".join(out)
en = en.replace('src="img/notch-', 'src="../img/en/notch-').replace('src="img/menu.png', 'src="../img/en/menu.png').replace('src="img/', 'src="../img/').replace('href="img/', 'href="../img/')
en = en.replace('<a class="pill" href="#descargar">Download</a>', '<a class="lang" href="../" lang="es" title="Versión en español">ES</a>\n    <a class="pill" href="#descargar">Download</a>')
open(os.path.join(ROOT, "docs/site/en/index.html"), "w").write(en)
print(f"en/index.html escrita · {len(PAIRS)} pares · sin correspondencia en el español actual: {len(missing)}")
for m in missing[:10]: print("  ·", m.strip()[:90])
