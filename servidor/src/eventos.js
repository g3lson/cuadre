// EN VIVO.
//
// Cuando dos personas están comprando la misma lista, sincronizar cada minuto
// no sirve: para cuando ella se entera de que él ya cogió la leche, ya la cogió
// ella también. Hace falta que el aviso salga del servidor en el momento.
//
// Se usa SSE (un GET que no se cierra) y no WebSocket por tres razones, y las
// tres importan en un súper:
//   · El navegador y URLSession lo reconectan solos cuando la señal vuelve.
//   · Va por HTTP normal, así que el proxy de siempre lo pasa sin tocar nada.
//   · Solo hace falta en un sentido: el servidor avisa, el teléfono sincroniza
//     por donde ya sabe. Un canal de ida y vuelta sería el doble de cosas que
//     pueden romperse para la mitad de uso.
//
// El aviso NO lleva los datos, solo «esta lista cambió». Así el que llega no
// tiene dos caminos por los que enterarse de lo mismo —y por tanto dos maneras
// de quedar desincronizado— sino uno: el de siempre.
import { bd, ahora } from './bd.js';

/** usuarioId → conexiones abiertas (una persona puede tener dos aparatos). */
const abiertas = new Map();

const LATIDO = 25_000;   // por debajo del minuto que corta cualquier proxy

export function conectar(req, res, usuarioId) {
  res.writeHead(200, {
    'content-type': 'text/event-stream; charset=utf-8',
    'cache-control': 'no-cache, no-transform',
    connection: 'keep-alive',
    // Nginx guarda la respuesta entera antes de mandarla si no se le dice que no,
    // y entonces «en vivo» llega cuando se cierra la conexión, o sea nunca.
    'x-accel-buffering': 'no',
  });
  res.write(`: hola ${ahora()}\n\n`);

  if (!abiertas.has(usuarioId)) abiertas.set(usuarioId, new Set());
  abiertas.get(usuarioId).add(res);

  // Un latido cada veinticinco segundos: sin tráfico, el proxy o la operadora
  // cierran la conexión y el teléfono no se entera hasta que intenta usarla.
  const latido = setInterval(() => {
    try { res.write(`: ${Date.now()}\n\n`); } catch { cerrar(); }
  }, LATIDO);

  const cerrar = () => {
    clearInterval(latido);
    abiertas.get(usuarioId)?.delete(res);
    if (!abiertas.get(usuarioId)?.size) abiertas.delete(usuarioId);
  };
  req.on('close', cerrar);
  req.on('error', cerrar);
}

/** A cuánta gente le estamos hablando ahora mismo. Para /api/salud. */
export const cuantosEscuchan = () =>
  [...abiertas.values()].reduce((a, s) => a + s.size, 0);

/**
 * Quién puede ver esta lista: el dueño y sus miembros. Es a quien hay que
 * avisar, y a nadie más.
 */
export function quienesVen(listaId) {
  const ids = new Set();
  const lista = bd.prepare('SELECT usuario_id, grupo_id FROM listas WHERE id = ?').get(listaId);
  if (lista) ids.add(lista.usuario_id);

  // Quien la tenga compartida suelta…
  for (const m of bd.prepare(
    "SELECT usuario_id FROM miembros WHERE ambito = 'lista' AND ambito_id = ? AND usuario_id IS NOT NULL"
  ).all(listaId)) ids.add(m.usuario_id);

  // …y quien esté en el grupo donde vive, que es la forma normal de compartir.
  if (lista?.grupo_id) {
    const grupo = bd.prepare('SELECT usuario_id FROM grupos WHERE id = ?').get(lista.grupo_id);
    if (grupo) ids.add(grupo.usuario_id);
    for (const m of bd.prepare(
      "SELECT usuario_id FROM miembros WHERE ambito = 'grupo' AND ambito_id = ? AND usuario_id IS NOT NULL"
    ).all(lista.grupo_id)) ids.add(m.usuario_id);
  }
  return ids;
}

/**
 * Avisar de que unas listas cambiaron.
 *
 * `menos` es quien lo escribió: a esa persona no hay que decirle nada, ya lo
 * sabe, y avisarla la haría sincronizar contra sí misma en bucle.
 */
export function avisaDeListas(listaIds, menos) {
  const aQuien = new Map();   // usuarioId → listas suyas que cambiaron
  for (const listaId of listaIds) {
    for (const uid of quienesVen(listaId)) {
      if (uid === menos) continue;
      if (!aQuien.has(uid)) aQuien.set(uid, new Set());
      aQuien.get(uid).add(listaId);
    }
  }

  for (const [uid, listas] of aQuien) {
    const conexiones = abiertas.get(uid);
    if (!conexiones?.size) continue;
    const mensaje = `event: cambio\ndata: ${JSON.stringify({ listas: [...listas], ahora: ahora() })}\n\n`;
    for (const res of conexiones) {
      try { res.write(mensaje); } catch { conexiones.delete(res); }
    }
  }
}

/** Al compartir o dejar de compartir: que la otra persona lo vea sin esperar. */
export function avisaAlguien(usuarioIds, clase) {
  for (const uid of usuarioIds) {
    for (const res of abiertas.get(uid) || []) {
      try { res.write(`event: ${clase}\ndata: {"ahora":${JSON.stringify(ahora())}}\n\n`); } catch { /* se irá sola */ }
    }
  }
}
