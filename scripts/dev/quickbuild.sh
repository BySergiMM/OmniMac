#!/bin/zsh
# Compilación rápida (solo Apple silicon) para probar cambios: sustituye el binario
# del bundle ya existente en dist/ y lo vuelve a firmar. Para publicar usa ./build.sh
# (universal). Uso: zsh scripts/dev/quickbuild.sh
set -e
cd "$(dirname "$0")/../.."
APP=dist/OmniMac.app
[ -d "$APP" ] || { echo "No existe $APP: ejecuta ./build.sh primero"; exit 1; }
swift build -c release 2>&1 | grep -E "error|Build complete" || true
cp .build/release/OmniMac "$APP/Contents/MacOS/OmniMac"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/OmniMac" 2>/dev/null || true
# Misma firma que build.sh (requisito designado estable): así el permiso de
# Accesibilidad concedido a OmniMac sigue valiendo tras recompilar.
codesign --force --deep --sign - \
  --identifier com.seergiii.omnimac \
  -r='designated => identifier "com.seergiii.omnimac"' \
  "$APP" 2>/dev/null
echo "✅ $APP actualizado (arm64)"
