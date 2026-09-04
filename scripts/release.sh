#!/bin/zsh
# Publica una versión nueva de OmniMac para las actualizaciones automáticas (Sparkle).
#
#   scripts/release.sh 0.3.0            → compila, empaqueta y firma; deja todo en dist/release
#   scripts/release.sh 0.3.0 --publish  → además crea la release en GitHub con `gh`
#
# Necesita la clave privada EdDSA en tu llavero (la creó `generate_keys`; la pública
# está en Resources/Info.plist como SUPublicEDKey). El appcast de cada release se sube
# como "appcast.xml", y la app lo lee en .../releases/latest/download/appcast.xml.
set -e
cd "$(dirname "$0")/.."

VER="$1"
if [[ -z "$VER" ]]; then
  echo "uso: scripts/release.sh <versión> [--publish]   (p. ej. 0.3.0)"
  exit 1
fi
REPO="BySergiMM/OmniMac"
TOOLS=".build/sparkle-tools"

if [[ ! -x "$TOOLS/bin/generate_appcast" ]]; then
  echo "⬇️  Descargando las herramientas de Sparkle…"
  mkdir -p "$TOOLS"
  curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/2.9.6/Sparkle-2.9.6.tar.xz" | tar -xJ -C "$TOOLS"
fi

# Versión visible y número de build (siempre creciente: Sparkle compara este).
BUILD=$(( $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist) + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VER" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" Resources/Info.plist

./build.sh

OUT="dist/release"
rm -rf "$OUT"
mkdir -p "$OUT"
ditto -c -k --keepParent dist/OmniMac.app "$OUT/OmniMac-$VER.zip"
"$TOOLS/bin/generate_appcast" --download-url-prefix "https://github.com/$REPO/releases/download/v$VER/" "$OUT"

# Instalador .pkg con nombre fijo: la web enlaza siempre a
# https://github.com/$REPO/releases/latest/download/OmniMac.pkg
./build.sh pkg >/dev/null
cp "dist/OmniMac-$VER.pkg" "$OUT/OmniMac.pkg"

echo "✅ Listo: $OUT/OmniMac-$VER.zip, $OUT/OmniMac.pkg y $OUT/appcast.xml (versión $VER, build $BUILD)."
if [[ "$2" == "--publish" ]]; then
  gh release create "v$VER" "$OUT/OmniMac-$VER.zip" "$OUT/OmniMac.pkg" "$OUT/appcast.xml" \
    --repo "$REPO" --title "OmniMac $VER" --generate-notes
  echo "🚀 Publicada: https://github.com/$REPO/releases/tag/v$VER"
  echo "   Las apps instaladas la verán en su próxima comprobación (o con «Buscar actualizaciones…»)."
else
  echo "Para publicarla en GitHub: scripts/release.sh $VER --publish"
fi
