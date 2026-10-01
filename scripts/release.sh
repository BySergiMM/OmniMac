#!/bin/zsh
# Publica una versión nueva de OmniMac para las actualizaciones automáticas (Sparkle).
#
#   scripts/release.sh 0.3.0            → compila, empaqueta y firma; deja todo en dist/release.
#                                         Es un ensayo: no toca git (la subida de versión se
#                                         deshace al terminar).
#   scripts/release.sh 0.3.0 --publish  → además la publica, en este orden:
#                                           1. confirma la subida de versión (un commit),
#                                           2. crea la etiqueta anotada v0.3.0 sobre ESE commit,
#                                           3. sube commit y etiqueta (git push --atomic origin main vX.Y.Z),
#                                           4. crea la release (gh release create --verify-tag),
#                                           5. actualiza el cask de Homebrew.
#
# Por qué ese orden: `gh release create` sin la etiqueta en el remoto la crea él, sobre la
# punta de main en ese momento, que no incluye la subida de versión (estaba sin confirmar).
# Así salieron las etiquetas v0.5.x: apuntan al commit ANTERIOR al de «0.5.4 (build 13)», y
# el código de la etiqueta no es el que compiló el binario. Con `--verify-tag`, `gh` se niega
# a publicar si la etiqueta no está ya en el remoto.
#
# Necesita la clave privada EdDSA en tu llavero (la creó `generate_keys`; la pública
# está en Resources/Info.plist como SUPublicEDKey). El appcast de cada release se sube
# como "appcast.xml", y la app lo lee en .../releases/latest/download/appcast.xml.
set -e
cd "$(dirname "$0")/.."

VER="$1"
MODE="$2"
if [[ -z "$VER" ]]; then
  echo "uso: scripts/release.sh <versión> [--publish]   (p. ej. 0.3.0)"
  exit 1
fi
abort() { echo "❌ $1" >&2; exit 1; }

# La versión acaba en una etiqueta de git y en una URL: solo números y puntos. Se compara la
# cadena entera: `grep` mira línea a línea y daría por buena «1.2.3» seguida de un salto de
# línea y cualquier cosa.
[[ "$VER" != *$'\n'* && "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || abort "La versión tiene que ser X.Y.Z (p. ej. 0.3.0), no «$VER»."
PUBLISH=0
if [[ "$MODE" == "--publish" ]]; then
  PUBLISH=1
elif [[ -n "$MODE" ]]; then
  abort "No conozco «$MODE». Solo existe --publish."
fi

REPO="BySergiMM/OmniMac"
TOOLS=".build/sparkle-tools"
PLIST="Resources/Info.plist"
PLISTBUDDY="${PLISTBUDDY:-/usr/libexec/PlistBuddy}"

# --- Antes de tocar nada ---------------------------------------------------------------

# Lo que se compila tiene que ser lo que queda en la etiqueta: sin cambios a medias. (Los
# archivos ignorados, como dist/ y .build/, no cuentan.)
if [[ -n "$(git status --porcelain)" ]]; then
  git status --short >&2
  abort "Hay cambios sin confirmar. Una release sale de lo que está en git: confírmalos o aparta antes de seguir."
fi
if git rev-parse -q --verify "refs/tags/v$VER" >/dev/null; then
  abort "La etiqueta v$VER ya existe en este repositorio. Si es de un intento que quedó a medias, mira «git log -1» y «git tag -n» antes de repetir."
fi

if (( PUBLISH )); then
  BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  [[ "$BRANCH" == "main" ]] || abort "Se publica desde main y estás en «$BRANCH»: la etiqueta tiene que quedar en la historia de main."
  git fetch -q origin main || abort "No se pudo consultar origin/main."
  git merge-base --is-ancestor origin/main HEAD || abort "Tu main no tiene todo lo que hay en origin/main: haz «git pull» antes."
  if git ls-remote --exit-code --tags origin "refs/tags/v$VER" >/dev/null 2>&1; then
    abort "La etiqueta v$VER ya existe en GitHub. No se reetiqueta."
  fi
  # La ventana de Novedades sale del CHANGELOG empaquetado en la app (docs/RELEASE.md, punto 1).
  grep -q "^## $VER " CHANGELOG.md || abort "CHANGELOG.md no tiene la entrada «## $VER — fecha»."
  grep -q "^## $VER " CHANGELOG.en.md || abort "CHANGELOG.en.md no tiene la entrada «## $VER — fecha»."
fi

if [[ ! -x "$TOOLS/bin/generate_appcast" ]]; then
  echo "⬇️  Descargando las herramientas de Sparkle…"
  mkdir -p "$TOOLS"
  curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz" | tar -xJ -C "$TOOLS"
fi

# --- Subir la versión y compilar -------------------------------------------------------

# Hasta que la subida de versión se confirma (solo con --publish), cualquier salida, también
# un fallo de la compilación, la deshace: el árbol estaba limpio, así que esto no pierde nada
# de nadie. Después, si algo falla, se avisa de en qué punto se queda.
#
# Se restaura desde HEAD y no desde el índice: si `git add` llegó a hacerse y el commit falló,
# el índice ya tiene la subida de versión, y `git checkout -- archivo` (que lee del índice) la
# dejaría puesta.
COMMITTED=0
RELEASED=0
cleanup() {
  if [[ "$COMMITTED" != 1 ]]; then
    git checkout -q HEAD -- "$PLIST" 2>/dev/null || true
  elif [[ "$RELEASED" != 1 ]]; then
    echo "⚠️  La publicación se quedó a medias. El commit y la etiqueta v$VER ya existen en local:" >&2
    echo "   mira «git status», «git ls-remote --tags origin v$VER» y «gh release view v$VER»" >&2
    echo "   para saber hasta dónde llegó, y termina a mano lo que falte." >&2
  fi
}
trap cleanup EXIT

# Versión visible y número de build (siempre creciente: Sparkle compara este).
BUILD=$(( $("$PLISTBUDDY" -c 'Print :CFBundleVersion' "$PLIST") + 1 ))
"$PLISTBUDDY" -c "Set :CFBundleShortVersionString $VER" "$PLIST"
"$PLISTBUDDY" -c "Set :CFBundleVersion $BUILD" "$PLIST"

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

if (( ! PUBLISH )); then
  echo "Ensayo: Info.plist vuelve a como estaba; la subida de versión solo se confirma al publicar."
  echo "Para publicarla en GitHub: scripts/release.sh $VER --publish"
  exit 0
fi

# --- Publicar ---------------------------------------------------------------------------

# La compilación no debería haber tocado nada más que la versión. Si lo hizo, el commit no
# tendría lo que se compiló.
if [[ "$(git status --porcelain)" != " M $PLIST" ]]; then
  git status --short >&2
  abort "La compilación ha cambiado algo más que $PLIST: revísalo antes de publicar."
fi

git add -- "$PLIST"
git commit -q -m "$VER (build $BUILD)"
COMMITTED=1
git tag -a "v$VER" -m "OmniMac $VER"
# Solo main y esta etiqueta, y las dos o ninguna: `--follow-tags` subiría también cualquier
# otra etiqueta anotada que hubiera en local, y sin `--atomic` podría quedar la etiqueta en
# GitHub apuntando a un commit que main no tiene (si se rechaza el push de main).
git push --atomic origin main "refs/tags/v$VER"

gh release create "v$VER" "$OUT/OmniMac-$VER.zip" "$OUT/OmniMac.pkg" "$OUT/appcast.xml" \
  --repo "$REPO" --title "OmniMac $VER" --generate-notes --verify-tag
RELEASED=1
echo "🚀 Publicada: https://github.com/$REPO/releases/tag/v$VER"

# Tap de Homebrew: versión y sha256 del zip nuevo. La release ya está publicada, así que si
# esto falla no se deshace nada: se dice en voz alta qué falta y con qué valores, y el script
# termina con error para que no se dé por completa.
SHA=$(shasum -a 256 "$OUT/OmniMac-$VER.zip" | cut -d' ' -f1)
tap_failed() {
  echo "❌ El tap de Homebrew NO está actualizado: $1" >&2
  echo "   Hay que poner a mano en Casks/omnimac.rb de BySergiMM/homebrew-tap:" >&2
  echo "     version \"$VER\"   sha256 \"$SHA\"" >&2
  [[ -n "${TAP:-}" ]] && echo "   (el clon está en $TAP)" >&2
  exit 1
}
TAP=$(mktemp -d)
gh repo clone BySergiMM/homebrew-tap "$TAP" -- -q 2>/dev/null || tap_failed "no se pudo clonar BySergiMM/homebrew-tap."
CASK="$TAP/Casks/omnimac.rb"
[[ -f "$CASK" ]] || tap_failed "no existe Casks/omnimac.rb en el clon."
sed -i '' "s/^  version \".*\"/  version \"$VER\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
# Si los patrones no encontraron las líneas, el `sed` no falla y el cask se queda como estaba.
grep -q "^  version \"$VER\"" "$CASK" && grep -q "^  sha256 \"$SHA\"" "$CASK" \
  || tap_failed "no se encontraron las líneas version y sha256 en el cask."
git -C "$TAP" commit -qam "OmniMac $VER" || tap_failed "no se pudo crear el commit en el tap."
git -C "$TAP" push -q || tap_failed "no se pudo subir el commit al tap."
echo "🍺 Tap de Homebrew actualizado a $VER."
echo "   Las apps instaladas la verán en su próxima comprobación (o con «Buscar actualizaciones…»)."
