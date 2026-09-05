#!/bin/zsh
# Mide el consumo de OmniMac en reposo (60 s) vigilando que el notch siga plegado;
# si se abre durante la ventana, descarta y reintenta. Uso: scripts/dev/measure.sh
cd "$(dirname "$0")/../.."
cpus() { ps -o cputime= -p $1 | awk -F'[:.]' '{ if (NF==4) print $1*3600+$2*60+$3+$4/100; else print $1*60+$2+$3/100 }'; }
PID=$(pgrep -x OmniMac | head -1); [[ -z "$PID" ]] && { echo "OmniMac no corre"; exit 1; }
echo "OmniMac pid $PID · versión $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/OmniMac.app/Contents/Info.plist)"
swift scripts/dev/mouse.swift hover >/dev/null 2>&1; sleep 1.5; swift scripts/dev/mouse.swift park >/dev/null 2>&1; sleep 2   # calentar: abrir y cerrar una vez
for attempt in 1 2; do
  T1=$(cpus $PID); BAD=0; SAMPLES=""
  for i in $(seq 1 12); do sleep 5; H=$(swift scripts/dev/notch.swift height 2>/dev/null); SAMPLES="$SAMPLES $H"; [[ "$H" != "32" ]] && BAD=1; done
  T2=$(cpus $PID); CPU=$(echo "$T1 $T2 60" | awk '{printf "%.3f", ($2-$1)/$3*100}')
  RSS=$(( $(ps -o rss= -p $PID) / 1024 )); TH=$(ps -M -p $PID | tail -n +2 | wc -l | tr -d ' '); FOOT=$(footprint $PID 2>/dev/null | grep phys_footprint: | awk '{print $2 $3}')
  echo "intento $attempt · alturas:$SAMPLES · CPU $CPU % · RSS $RSS MB · footprint $FOOT · hilos $TH"
  [[ $BAD == 0 ]] && break || echo "  → el notch se abrió durante la medida; reintento…"
done
