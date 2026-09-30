// SwiftPM exige al menos un .c por cada objetivo de C; las funciones de verdad
// son `static inline` en CAtomics.h. Aquí se comprueba, al compilar, lo que el
// código de audio da por hecho.
#include "CAtomics.h"

// Las operaciones atómicas de 32 bits no pueden llevar un cerrojo escondido: el
// hilo de audio no puede esperar. En x86-64 y arm64 es así; si alguna vez no
// lo fuera, que falle la compilación en vez de bloquear el audio.
_Static_assert(__atomic_always_lock_free(sizeof(uint32_t), 0),
               "los atomicos de 32 bits tienen que ser sin cerrojo");

// Los índices de juego (0, 1 y 2) han de caber en OMNIMAC_MAILBOX_INDEX sin pisar
// el bit de «publicado».
_Static_assert((OMNIMAC_MAILBOX_INDEX & OMNIMAC_MAILBOX_DIRTY) == 0,
               "el bit de publicado no puede solaparse con el indice");
_Static_assert((2u & OMNIMAC_MAILBOX_INDEX) == 2u,
               "la mascara del indice tiene que poder representar el juego 2");
