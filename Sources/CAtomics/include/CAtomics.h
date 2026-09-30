// CAtomics: el buzón con el que el hilo principal le pasa datos al hilo de audio
// sin cerrojos ni reservas de memoria.
//
// Por qué existe: el ecualizador cambia sus coeficientes desde el hilo principal
// (cada vez que se mueve un deslizador) mientras el hilo de audio los está
// leyendo. Con variables normales de Swift eso es una carrera de datos: sin
// `release` al publicar y `acquire` al leer, el hilo de audio puede ver el índice
// nuevo antes que los coeficientes que apunta (en Apple silicon, que reordena
// escrituras, pasa de verdad). `Synchronization.Atomic` pide macOS 15 y el
// proyecto compila para 14.2, así que los átomos se piden a C, que los tiene
// desde C11. Las funciones son `static inline`: Swift las compila dentro del
// propio binario, sin llamadas ni dependencias nuevas.
//
// El buzón es un «triple buffer» para un solo escritor y un solo lector. Hay tres
// juegos de datos (los guarda quien usa el buzón, aquí solo se reparten sus
// índices 0, 1 y 2) y, en todo momento, cada juego es de uno solo:
//
//   back    del escritor: escribe aquí, nadie más lo toca.
//   front   del lector: lee de aquí, nadie más lo toca.
//   shared  el que está en el buzón: el último publicado, o uno viejo ya leído.
//
// Publicar y recoger son un intercambio atómico de índices. Con dos juegos (lo
// que había antes) el escritor podía volver a escribir el juego que el lector
// todavía estaba leyendo si publicaba dos veces seguidas; con tres, eso no puede
// pasar: el juego que se lee no está nunca en manos del escritor.
#ifndef CATOMICS_H
#define CATOMICS_H

#include <stdint.h>

/// Los campos no se tocan desde fuera: solo con las funciones de abajo. `shared`
/// se lee y se escribe siempre de forma atómica; `back` es del escritor y `front`
/// del lector, cada uno con el suyo.
typedef struct {
    uint32_t shared;
    uint32_t back;
    uint32_t front;
} omnimac_mailbox;

/// Bit de `shared` que dice «hay un juego publicado que el lector aún no ha
/// recogido». El índice del juego ocupa los dos bits de abajo (0, 1 o 2).
#define OMNIMAC_MAILBOX_DIRTY 0x4u
#define OMNIMAC_MAILBOX_INDEX 0x3u

/// Reparte los tres juegos: el 0 para el escritor, el 1 en el buzón (sin novedades)
/// y el 2 para el lector. Se llama una vez, antes de que dos hilos usen el buzón.
static inline void omnimac_mailbox_init(omnimac_mailbox *m) {
    __atomic_store_n(&m->shared, 1u, __ATOMIC_RELAXED);
    m->back = 0u;
    m->front = 2u;
}

/// Índice del juego en el que el escritor puede escribir ahora. Solo el hilo
/// escritor.
static inline uint32_t omnimac_mailbox_writer_slot(omnimac_mailbox *m) {
    return m->back;
}

/// Publica el juego que el escritor acaba de rellenar y le da otro libre para la
/// próxima vez. `release`: todo lo escrito en el juego queda visible para quien lo
/// recoja después. `acquire`: el juego que devuelve ya no lo está leyendo nadie.
/// Solo el hilo escritor. No bloquea ni reserva memoria.
static inline void omnimac_mailbox_publish(omnimac_mailbox *m) {
    uint32_t previous = __atomic_exchange_n(&m->shared, m->back | OMNIMAC_MAILBOX_DIRTY, __ATOMIC_ACQ_REL);
    m->back = previous & OMNIMAC_MAILBOX_INDEX;
}

/// Índice del juego que debe leer el lector ahora: si hay uno publicado sin
/// recoger lo recoge (`acquire`: ve todo lo que el escritor dejó escrito antes de
/// publicarlo) y suelta el que tenía. Se puede llamar cuantas veces haga falta;
/// sin novedades devuelve siempre el mismo. Solo el hilo lector. No bloquea ni
/// reserva memoria, así que sirve en el hilo de audio.
static inline uint32_t omnimac_mailbox_reader_slot(omnimac_mailbox *m) {
    // La lectura suelta solo decide si merece la pena el intercambio; el
    // intercambio es el que sincroniza.
    if (__atomic_load_n(&m->shared, __ATOMIC_RELAXED) & OMNIMAC_MAILBOX_DIRTY) {
        uint32_t previous = __atomic_exchange_n(&m->shared, m->front, __ATOMIC_ACQ_REL);
        m->front = previous & OMNIMAC_MAILBOX_INDEX;
    }
    return m->front;
}

#endif
