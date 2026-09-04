# Pendiente

- **Volumen por app no es dinámico** (reportado por Sergi el 2026-09-04): al mover la
  barra de una app en el notch, el volumen no cambia de forma fluida/inmediata.
  Reproducir con el volumen del Mac BAJO (≤ 5 %). Sospechas: la ganancia solo se
  aplica al reconstruir el motor, el dispositivo agregado tarda en arrancar, o la
  barra no llama a `setVolume` durante el arrastre. Ver `AppVolumeMixer.syncEngine`
  y `MixEngine.updateGains`.
