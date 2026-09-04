#!/bin/zsh
# Desinstala OmniMac por completo: app, regla del modo tapa cerrada, preferencias y permisos.
set -u
echo "🧹 Desinstalando OmniMac…"
pkill -x OmniMac 2>/dev/null || true
sleep 0.5
if [[ -f /etc/sudoers.d/omnimac-lid ]]; then
  echo "   Quitando la regla del modo tapa cerrada (pide la contraseña de administrador)…"
  sudo /usr/bin/pmset -a disablesleep 0 2>/dev/null || true
  sudo rm -f /etc/sudoers.d/omnimac-lid
fi
rm -rf /Applications/OmniMac.app
defaults delete com.seergiii.omnimac 2>/dev/null || true
rm -f ~/Library/Preferences/com.seergiii.omnimac.plist
tccutil reset All com.seergiii.omnimac >/dev/null 2>&1 || true
echo "✅ OmniMac desinstalada."
