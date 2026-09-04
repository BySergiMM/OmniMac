#!/bin/zsh
# Compila OmniMac y genera dist/OmniMac.app
# Uso:
#   ./build.sh        → compila y crea el .app
#   ./build.sh run    → compila, crea el .app y lo abre
set -e
cd "$(dirname "$0")"

echo "🔨 Compilando OmniMac (release)…"
swift build -c release

APP="dist/OmniMac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/OmniMac "$APP/Contents/MacOS/OmniMac"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Sparkle (actualizaciones automáticas): el framework va dentro del .app y el
# binario lo busca en Contents/Frameworks.
mkdir -p "$APP/Contents/Frameworks"
cp -R .build/release/Sparkle.framework "$APP/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/OmniMac" 2>/dev/null || true

# Icono de la app (se genera una vez con scripts/make-icon.swift)
if [[ ! -f Resources/AppIcon.icns ]]; then
  echo "🎨 Generando icono…"
  swift scripts/make-icon.swift
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Firma ad-hoc CON UN REQUISITO DESIGNADO ESTABLE (solo el identificador, no la
# huella del binario). El permiso de Accesibilidad que concedes se ancla al
# identificador de la app, así que NO se revoca al recompilar: lo concedes una vez.
codesign --force --deep --sign - \
  --identifier com.seergiii.omnimac \
  -r='designated => identifier "com.seergiii.omnimac"' \
  "$APP" 2>/dev/null

echo "✅ Listo: $APP"
echo "   Ábrela con: open $APP"
echo "   ℹ️  La primera vez, concede Accesibilidad a OmniMac en Ajustes del Sistema →"
echo "      Privacidad y seguridad → Accesibilidad. Gracias a la firma estable, ya"
echo "      no hará falta repetirlo tras cada recompilación."

if [[ "$1" == "pkg" ]]; then
  # Instalador .pkg: al instalarlo, macOS pide la contraseña UNA vez y el propio
  # instalador deja la app en /Applications y la regla del modo «tapa cerrada»
  # (scripts/pkg/postinstall). La app no vuelve a pedir nada.
  VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist 2>/dev/null || echo 0.2.0)
  echo "📦 Creando el instalador…"
  chmod +x scripts/pkg/preinstall scripts/pkg/postinstall
  pkgbuild --component "$APP" --install-location /Applications --scripts scripts/pkg \
    --identifier com.seergiii.omnimac.pkg --version "$VERSION" dist/OmniMac-component.pkg >/dev/null
  sed "s/@VERSION@/$VERSION/g" scripts/pkg/distribution.xml.in > dist/distribution.xml
  productbuild --distribution dist/distribution.xml --resources scripts/pkg/resources \
    --package-path dist "dist/OmniMac-$VERSION.pkg" >/dev/null
  rm -f dist/OmniMac-component.pkg dist/distribution.xml
  echo "✅ Instalador: dist/OmniMac-$VERSION.pkg"
  echo "   Doble clic → contraseña una sola vez → app en /Applications + modo tapa cerrada listo."
fi

if [[ "$1" == "run" ]]; then
  # Si ya hay una instancia abierta, `open` solo la traería al frente y seguiría
  # corriendo el binario viejo: la cerramos primero (con gracia, luego a la fuerza).
  if pgrep -xq OmniMac; then
    echo "🔁 Cerrando la instancia anterior…"
    osascript -e 'tell application "OmniMac" to quit' >/dev/null 2>&1 || true
    for _ in {1..20}; do pgrep -xq OmniMac || break; sleep 0.25; done
    pkill -x OmniMac 2>/dev/null || true
    sleep 0.5
  fi
  open "$APP"
  echo "🚀 OmniMac abierta (versión recién compilada)."
fi
