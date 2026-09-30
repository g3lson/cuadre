// SINCRONIZAR.
//
// El teléfono es la fuente: escribe en su base local y sigue funcionando en el
// pasillo del súper sin señal. Esto es el punto de encuentro entre teléfonos.
//
// Regla única: gana el cambio más reciente, fila por fila (`actualizado`). Es
// una app de una persona con sus dispositivos, no un documento a cuatro manos:
// un CRDT aquí sería resolver un problema que no existe. Borrar es escribir una
// lápida (`borrado`), porque una fila que desaparece sin dejar rastro vuelve a
// aparecer en el siguiente teléfono que suba lo que tenía.
import { Router } from 'express';
import { bd, ahora, TABLAS, llano, cuenta } from '../bd.js';
import { conSesion } from '../auth.js';
import { listasCompartidasCon, puedeEscribirEn, marcaVisto } from '../compartir.js';
import { avisaDeListas } from '../eventos.js';

export const sync = Router();
sync.use(conSesion);

const MAX_FILAS = 4000;

const enFila = (f) => ({
  id: f.id,
  datos: JSON.parse(f.datos),
  actualizado: f.actualizado,
  borrado: f.borrado || null,
  ...(f.usuario_id ? { de: f.usuario_id } : {}),
});

/**
 * Lo que cambió desde `desde`: lo propio y lo de las listas compartidas.
 *
 * Lo compartido se busca aparte y no con un `OR` en la consulta de siempre
 * porque son dos preguntas distintas —«lo mío» y «aquello a lo que me
 * invitaron»— y mezclarlas hace que un error en una se lleve la otra por
 * delante. Además, casi nadie comparte: la consulta normal no debería pagar el
 * precio de una función que la mayoría no usa.
 */
function cambiosDesde(usuarioId, desde) {
  const marca = desde || '';
  const fuera = {};
  for (const t of TABLAS) {
    fuera[t] = bd.prepare(
      `SELECT id, usuario_id, datos, actualizado, borrado FROM ${t} WHERE usuario_id = ? AND actualizado > ? ORDER BY actualizado LIMIT ?`
    ).all(usuarioId, marca, MAX_FILAS).map(enFila);
  }

  const compartidas = listasCompartidasCon(usuarioId);
  if (compartidas.size) {
    const ids = [...compartidas];
    const huecos = ids.map(() => '?').join(',');
    // La lista en sí, y sus artículos, sean de quien sean.
    fuera.listas.push(...bd.prepare(
      `SELECT id, usuario_id, datos, actualizado, borrado FROM listas
       WHERE id IN (${huecos}) AND usuario_id != ? AND actualizado > ? ORDER BY actualizado LIMIT ?`
    ).all(...ids, usuarioId, marca, MAX_FILAS).map(enFila));

    fuera.articulos.push(...bd.prepare(
      `SELECT id, usuario_id, datos, actualizado, borrado FROM articulos
       WHERE lista_id IN (${huecos}) AND usuario_id != ? AND actualizado > ? ORDER BY actualizado LIMIT ?`
    ).all(...ids, usuarioId, marca, MAX_FILAS).map(enFila));
  }

  return fuera;
}

/**
 * Guarda los precios que la persona acabó de pagar, para que la próxima lista
 * llegue con ellos puestos. Solo de lo que de verdad se compró y con precio.
 */
function apuntaPrecios(usuarioId, articulos) {
  const poner = bd.prepare(`INSERT INTO precios (usuario_id, llano, tienda, unidad, precio, fecha) VALUES (?,?,?,?,?,?)
    ON CONFLICT(usuario_id, llano, tienda) DO UPDATE SET precio = excluded.precio, unidad = excluded.unidad, fecha = excluded.fecha
    WHERE excluded.fecha >= precios.fecha`);
  for (const a of articulos) {
    const d = a.datos || {};
    if (a.borrado || !d.hecho || !(Number(d.precio) > 0) || !d.nombre) continue;
    poner.run(usuarioId, llano(d.nombre), String(d.tienda || ''), String(d.unidad || ''), Number(d.precio), a.actualizado);
  }
}

sync.get('/', (req, res) => {
  const desde = String(req.query.desde || '');
  res.json({ ahora: ahora(), completo: !desde, cambios: cambiosDesde(req.usuario.id, desde) });
});

sync.post('/', (req, res) => {
  const cuerpo = req.body || {};
  const entrantes = cuerpo.cambios && typeof cuerpo.cambios === 'object' ? cuerpo.cambios : {};
  const marca = ahora();
  let aplicados = 0, descartados = 0;
  const tocadas = new Set();

  // Una sola transacción: o entra el lote completo o no entra nada. Medio lote
  // aplicado con la fecha de sincronización movida es cómo se pierde un cambio.
  const guarda = bd.transaction(() => {
    for (const t of TABLAS) {
      const filas = Array.isArray(entrantes[t]) ? entrantes[t].slice(0, MAX_FILAS) : [];
      if (!filas.length) continue;
      const lee = bd.prepare(`SELECT usuario_id, actualizado FROM ${t} WHERE id = ?`);
      const columnaLista = t === 'articulos' ? ', lista_id' : '';
      const valorLista = t === 'articulos' ? ', ?' : '';
      const pon = bd.prepare(`INSERT INTO ${t} (id, usuario_id, datos, actualizado, borrado${columnaLista})
        VALUES (?,?,?,?,?${valorLista})
        ON CONFLICT(id) DO UPDATE SET datos = excluded.datos, actualizado = excluded.actualizado, borrado = excluded.borrado`);

      for (const f of filas) {
        const id = String(f?.id || '').slice(0, 64);
        if (!id || !f.datos || typeof f.datos !== 'object') { descartados++; continue; }
        // La fecha la pone quien escribió, no el servidor: el teléfono sin señal
        // escribió a las 10:05 y eso es cuando pasó, no cuando pudo subirlo.
        const cuando = typeof f.actualizado === 'string' && f.actualizado ? f.actualizado : marca;
        const ya = lee.get(id);

        // De otra persona: solo se acepta si es de una lista donde puede escribir,
        // y la fila SIGUE SIENDO DE QUIEN LA CREÓ. Cambiarle el dueño al marcar
        // un producto haría que la lista se fragmentara en trozos de cada uno.
        if (ya && ya.usuario_id !== req.usuario.id) {
          const listaId = t === 'listas' ? id : (t === 'articulos' ? String(f.datos.listaId || '') : '');
          if (!listaId || !puedeEscribirEn(req.usuario.id, listaId)) { descartados++; continue; }
        }

        // Un artículo NUEVO también tiene dueño: el de la lista donde dice que
        // va. Sin esta comprobación, cualquiera que acierte el id de una lista
        // ajena le mete productos dentro, y la fila sería suya así que ni
        // siquiera se podría quitar desde el otro lado.
        if (!ya && t === 'articulos') {
          const listaId = String(f.datos.listaId || '');
          if (listaId) {
            const suya = bd.prepare('SELECT usuario_id FROM listas WHERE id = ?').get(listaId);
            if (suya && suya.usuario_id !== req.usuario.id && !puedeEscribirEn(req.usuario.id, listaId)) {
              descartados++; continue;
            }
          }
        }
        if (ya && ya.actualizado >= cuando) { descartados++; continue; }

        const dueño = ya ? ya.usuario_id : req.usuario.id;
        const args = [id, dueño, JSON.stringify(f.datos), cuando, f.borrado || null];
        if (t === 'articulos') args.push(String(f.datos.listaId || '') || null);
        pon.run(...args);
        aplicados++;

        // A quién hay que avisar: la lista que se tocó.
        if (t === 'listas') tocadas.add(id);
        else if (t === 'articulos' && f.datos.listaId) tocadas.add(String(f.datos.listaId));
      }
      if (t === 'articulos') apuntaPrecios(req.usuario.id, filas);
    }
  });

  try { guarda(); } catch (e) {
    console.error('[sync]', e.message);
    return res.status(500).json({ error: 'No pude guardar ese lote.' });
  }

  cuenta('sync.subida');
  // Y el aviso en vivo, a quien comparte esas listas. Va después de guardar: si
  // se avisara antes, el otro teléfono sincronizaría y no encontraría nada.
  if (tocadas.size) {
    for (const listaId of tocadas) marcaVisto(req.usuario.id, listaId);
    avisaDeListas(tocadas, req.usuario.id);
  }
  // Se contesta con lo que el teléfono no tiene todavía, para que subir y bajar
  // sea UNA llamada: en el súper, con dos barras de señal, cada viaje cuenta.
  res.json({ ahora: ahora(), aplicados, descartados, cambios: cambiosDesde(req.usuario.id, String(cuerpo.desde || '')) });
});

/** Los precios que ya viste, para que la app rellene sola al escribir un nombre. */
sync.get('/precios', (req, res) => {
  res.json({
    precios: bd.prepare('SELECT llano, tienda, unidad, precio, fecha FROM precios WHERE usuario_id = ? ORDER BY fecha DESC LIMIT 600')
      .all(req.usuario.id),
  });
});
