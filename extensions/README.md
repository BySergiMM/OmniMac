# Controles para el Centro de Control de macOS (aparcado)

Aquí está el código de una extensión que metería los controles de OmniMac dentro
del **Centro de Control de macOS**, el panel del sistema donde salen el wifi, el
bluetooth o el brillo, para poder añadirlos desde «Editar controles».

**No se puede usar todavía, y el motivo no es el código.**

## Qué se probó (7 de septiembre de 2026, macOS 26.5.1)

1. La API existe y compila: `ControlWidget`, `ControlWidgetToggle`,
   `StaticControlConfiguration` y `SetValueIntent` (WidgetKit + AppIntents).
   Ojo: los inicializadores con etiqueta que se usan aquí piden **macOS 26**; en
   macOS 15 la firma es distinta y habría que escribir las dos versiones.
2. Se compiló la extensión como paquete `.appex` (con `-parse-as-library` y el
   punto de entrada `_NSExtensionMain`), con su `Info.plist` copiando las mismas
   claves que usa una extensión del sistema (la de la Calculadora).
3. Se colocó en `OmniMac.app/Contents/PlugIns/`, se firmó y se registró con
   `lsregister`, primero desde el directorio de trabajo y después desde
   `~/Applications` (LaunchServices ignora los directorios ocultos, y el nuestro
   cuelga de `.claude/`).
4. Se probó también con la extensión firmada con el entitlement de sandbox.

En ningún caso aparece en `pluginkit -m -A -D -p com.apple.widgetkit-extension`,
ni siquiera como desactivada, y `pkd` no deja ni un mensaje en el log: el sistema
no llega a mirarla.

## La causa

    codesign -dv OmniMacControls.appex
    Signature=adhoc
    TeamIdentifier=not set

macOS exige que las extensiones vayan firmadas con el **mismo Team ID** que la app
que las contiene. OmniMac se firma ad-hoc (`codesign -s -`) porque no hay cuenta de
desarrollador de Apple, así que no hay Team ID que compartir y el sistema descarta
la extensión sin decir nada.

## Cuándo retomarlo

El día que haya cuenta de desarrollador (99 €/año, la misma que haría falta para
notarizar la app y quitar el aviso del primer arranque). Entonces:

- firmar `.appex` y app con la misma identidad de Developer ID,
- añadir el paquete a `build.sh` (dentro de `Contents/PlugIns/`),
- escribir la variante de la API para macOS 15, si se quiere dar soporte ahí.

Mientras tanto, los controles viven en el panel propio de OmniMac, que no depende
de la firma y funciona desde macOS 14.2.
