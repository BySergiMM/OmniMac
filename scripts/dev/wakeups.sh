#!/bin/zsh
# Despertares por segundo de OmniMac en reposo, antes y después de abrir/cerrar el notch
# 3 veces (sirve para detectar temporizadores o animaciones que se quedan colgados).
# Uso: zsh scripts/dev/wakeups.sh
#
# OJO: las columnas IDLEW y CSW de `top -l` son contadores ACUMULADOS desde que arrancó
# el proceso (el "+" solo indica que han crecido); la tasa real es la diferencia entre
# dos muestras dividida por el intervalo. Tomar el valor bruto /3 "descubrió" en 0.4.1
# una fuga que no existía.
cd "$(dirname "$0")/../.."
rate() {  # despertares/s y cambios de contexto/s medidos durante 3 s
  top -l 2 -s 3 -pid $1 -stats idlew,csw 2>/dev/null | grep -A1 IDLEW | grep -v "IDLEW\|^--" | tr -d '+' \
    | awk 'NR==1{a=$1;c=$2} NR==2{b=$1;d=$2} END{printf "%.1f despertares/s · %.1f csw/s", (b-a)/3, (d-c)/3}'
}
osascript -e 'tell application "OmniMac" to quit' >/dev/null 2>&1; sleep 2; pkill -x OmniMac 2>/dev/null; sleep 1
nohup dist/OmniMac.app/Contents/MacOS/OmniMac >/dev/null 2>&1 &
sleep 6; PID=$(pgrep -x OmniMac | head -1)
swift scripts/dev/mouse.swift park >/dev/null 2>&1; sleep 3
BASE=$(rate $PID)
for i in 1 2 3; do swift scripts/dev/mouse.swift hover >/dev/null 2>&1; sleep 1.5; swift scripts/dev/mouse.swift park >/dev/null 2>&1; sleep 1.5; done; sleep 3
AFTER=$(rate $PID)
echo "reposo: $BASE · tras 3 ciclos: $AFTER"
