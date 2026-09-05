# LinkedIn · post de OmniMac (tono casero, sin gancho) — no publicar sin orden de Sergi

## Texto del post (adjuntar el carrusel `omnimac-carrusel.pdf` o el vídeo `docs/video/omnimac-16x9-es.mp4`)

Llevo unos meses haciendo una app para Mac en mis ratos libres y ya está publicada: se llama OmniMac.

La idea es sencilla. En cada Mac acababa instalando las mismas utilidades pequeñas: una para que no se durmiera, otra para cambiar de ventana con ⌘Tab, otra para colocar ventanas, otra para el portapapeles y alguna para el notch. OmniMac las junta en una sola app de la barra de menús, y he ido añadiendo lo que echaba de menos: volumen por app, copiar el texto de la pantalla, un selector de color y una tarjeta como la del iPhone cuando conecto los AirPods.

Está hecha en Swift, es gratis y de código abierto, y no pide cuentas ni envía nada. Me importaba mucho que no se notara que está ahí, así que la he medido con el mismo método que las apps a las que sustituye, cada una sola en el mismo Mac:

Memoria en reposo
· OmniMac (las cinco cosas en una): 25 MB reales
· Amphetamine: 100 MB
· AltTab: 212 MB
· Rectangle: 84 MB
· Maccy: 91 MB
· BoringNotch: 149 MB
· Las cinco juntas: 636 MB

CPU en reposo: OmniMac 0,017 %; las cinco juntas, 0,42 %.

Cada una de esas apps hace cosas que la mía no hace, y lo digo en la web con detalle. Yo solo quería una sola app residente que hiciera lo que uso a diario.

Si tienes un Mac y la pruebas, me ayuda mucho saber qué te falta o qué te sobra. El enlace va en el primer comentario.

#macOS #Swift #OpenSource #Productividad

## Primer comentario (el enlace, para que LinkedIn no penalice el post)

Web y descarga: https://bysergimm.github.io/OmniMac/ · Código: https://github.com/BySergiMM/OmniMac

## Comentario para cuando alguien pregunte por la App Store o Gatekeeper (punto 5, solo como comentario)

No está en la App Store porque la mitad de lo que hace (colocar ventanas de otras apps, ⌘Tab por ventanas, mantener el Mac despierto con la tapa cerrada) necesita permisos que el sandbox no permite. Es de código abierto y se instala con un .pkg o con Homebrew. Lo que aún no tiene es la notarización de Apple (la cuenta de desarrollador cuesta 99 € al año), así que la primera vez hay que abrirla con clic derecho › Abrir. Si el proyecto crece, será lo primero que pague.

## Consejos
- Publicar entre martes y jueves, de 8 a 10. Responder a todos los comentarios la primera hora.
- Si adjuntas el carrusel, el texto puede ser más corto: quita la tabla y deja el párrafo de la medición (la tabla ya va en la diapositiva 8).
- Un solo post; el comentario del punto 5 solo si alguien pregunta.
