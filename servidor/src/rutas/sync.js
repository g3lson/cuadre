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

export const sync = Router();
sync.use(conSesion);

const MAX_FILAS = 4000;

/** Lo que cambió en el servidor desde `desde` (todo, si no viene). */
function cambiosDesde(usuarioId, desde) {
  const fuera = {};
  for (const t of TABLAS) {
    fuera[t] = bd.prepare(
      `SELECT id, datos, actualizado, borrado FROM ${t} WHERE usuario_id = ? AND actualizado > ? ORDER BY actualizado LIMIT ?`
    ).all(usuarioId, desde || '', MAX_FILAS).map((f) => ({
      id: f.id,
      datos: JSON.parse(f.datos),
      actualizado: f.actualizado,
      borrado: f.borrado || null,
    }));
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

  // Una sola transacción: o entra el lote completo o no entra nada. Medio lote
  // aplicado con la fecha de sincronización movida es cómo se pierde un cambio.
  const guarda = bd.transaction(() => {
    for (const t of TABLAS) {
      const filas = Array.isArray(entrantes[t]) ? entrantes[t].slice(0, MAX_FILAS) : [];
      if (!filas.length) continue;
      const lee = bd.prepare(`SELECT actualizado FROM ${t} WHERE id = ? AND usuario_id = ?`);
      const pon = bd.prepare(`INSERT INTO ${t} (id, usuario_id, datos, actualizado, borrado) VALUES (?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET datos = excluded.datos, actualizado = excluded.actualizado, borrado = excluded.borrado`);
      for (const f of filas) {
        const id = String(f?.id || '').slice(0, 64);
        if (!id || !f.datos || typeof f.datos !== 'object') { descartados++; continue; }
        // La fecha la pone quien escribió, no el servidor: el teléfono sin señal
        // escribió a las 10:05 y eso es cuando pasó, no cuando pudo subirlo.
        const cuando = typeof f.actualizado === 'string' && f.actualizado ? f.actualizado : marca;
        const mia = lee.get(id, req.usuario.id);
        // Hay una fila ajena con ese id, o la nuestra es más nueva: no se toca.
        if (mia && mia.actualizado >= cuando) { descartados++; continue; }
        if (!mia && bd.prepare(`SELECT 1 FROM ${t} WHERE id = ?`).get(id)) { descartados++; continue; }
        pon.run(id, req.usuario.id, JSON.stringify(f.datos), cuando, f.borrado || null);
        aplicados++;
      }
      if (t === 'articulos') apuntaPrecios(req.usuario.id, filas);
    }
  });

  try { guarda(); } catch (e) {
    console.error('[sync]', e.message);
    return res.status(500).json({ error: 'No pude guardar ese lote.' });
  }

  cuenta('sync.subida');
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
