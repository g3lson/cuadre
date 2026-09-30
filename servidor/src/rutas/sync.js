// SINCRONIZAR.
//
// El teléfono es la fuente: escribe en su base local y sigue funcionando en el
// pasillo del súper sin señal. Esto es el punto de encuentro entre teléfonos.
//
// Regla para juntar dos versiones de una fila: gana la más reciente
// (`actualizado`). Es una app de gente con sus dispositivos, no un documento a
// cuatro manos: un CRDT aquí sería resolver un problema que no existe. Borrar
// escribe una lápida (`borrado`), porque una fila que desaparece sin dejar
// rastro vuelve a aparecer en cuanto otro teléfono suba lo que tenía.
//
// QUIÉN VE QUÉ. Es lo delicado, y se decide en un solo sitio —`loQueVeo()`— por
// una razón: repartir esa comprobación por las rutas es cómo un día una ruta
// nueva se olvida de hacerla. Una fila se ve si:
//   · es tuya, o
//   · está en un GRUPO del que formas parte («Mi negocio», «Casa»), o
//   · es de una lista que te compartieron suelta.
//
// El contenido viaja como un `datos` opaco que el servidor no mira, salvo dos
// campos que sí necesita entender —de qué grupo y de qué lista o venta cuelga—
// y que por eso viven en columnas aparte.
import { Router } from 'express';
import { bd, ahora, TABLAS, llano, cuenta, AMBITO_DE } from '../bd.js';
import { conSesion } from '../auth.js';
import {
  listasCompartidasCon, gruposDe, gruposDondeEscribe, puedeEscribirEn, marcaVisto,
} from '../compartir.js';
import { avisaDeListas } from '../eventos.js';

export const sync = Router();
sync.use(conSesion);

const MAX_FILAS = 4000;

const enFila = (f) => ({
  id: f.id,
  datos: JSON.parse(f.datos),
  actualizado: f.actualizado,
  borrado: f.borrado || null,
  de: f.usuario_id,
});

/**
 * Lo que esta persona alcanza: sus grupos, y las listas y ventas que hay dentro
 * de ellos, más las listas que le compartieron sueltas.
 *
 * Se calcula UNA vez por sincronización y se consulta una vez por fila. Hacerlo
 * al revés —una consulta por fila— es lo mismo escrito mal.
 */
function loQueVeo(usuarioId) {
  const grupos = gruposDe(usuarioId);
  const listas = listasCompartidasCon(usuarioId);
  const eventos = new Set();

  if (grupos.size) {
    const ids = [...grupos];
    const huecos = ids.map(() => '?').join(',');
    for (const f of bd.prepare(`SELECT id FROM listas WHERE grupo_id IN (${huecos})`).all(...ids)) {
      listas.add(f.id);
    }
    for (const f of bd.prepare(`SELECT id FROM eventos WHERE grupo_id IN (${huecos})`).all(...ids)) {
      eventos.add(f.id);
    }
  }
  return { grupos, listas, eventos };
}

/** Lo que cambió desde `desde`. */
function cambiosDesde(usuarioId, desde) {
  const marca = desde || '';
  const veo = loQueVeo(usuarioId);
  const fuera = {};

  // Cuándo una fila ajena entra: la condición extra de cada tabla.
  const ajenas = {
    grupos: veo.grupos,
    listas: veo.listas,
    articulos: veo.listas,
    eventos: veo.eventos,
    encargos: veo.eventos,
    catalogo: veo.grupos,
    clientes: veo.grupos,
    tiendas: veo.grupos,
    pasillos: veo.grupos,
  };
  // Y por qué columna se comprueba.
  const porColumna = {
    grupos: 'id', listas: 'id', articulos: 'lista_id',
    eventos: 'id', encargos: 'evento_id',
    catalogo: 'grupo_id', clientes: 'grupo_id', tiendas: 'grupo_id', pasillos: 'grupo_id',
  };

  for (const t of TABLAS) {
    fuera[t] = bd.prepare(
      `SELECT id, usuario_id, datos, actualizado, borrado FROM ${t}
       WHERE usuario_id = ? AND actualizado > ? ORDER BY actualizado LIMIT ?`
    ).all(usuarioId, marca, MAX_FILAS).map(enFila);

    const suyas = ajenas[t];
    if (!suyas?.size) continue;
    const ids = [...suyas];
    const huecos = ids.map(() => '?').join(',');
    fuera[t].push(...bd.prepare(
      `SELECT id, usuario_id, datos, actualizado, borrado FROM ${t}
       WHERE ${porColumna[t]} IN (${huecos}) AND usuario_id != ? AND actualizado > ?
       ORDER BY actualizado LIMIT ?`
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
  const usuarioId = req.usuario.id;
  let aplicados = 0, descartados = 0;
  const tocadas = new Set();

  const veo = loQueVeo(usuarioId);
  const gruposQueEscribo = gruposDondeEscribe(usuarioId);

  /**
   * ¿Puede escribir esta fila?
   *
   * `ya` es lo que hay guardado, o `undefined` si la fila es nueva. Las dos
   * cosas se comprueban igual: no basta con mirar si la fila existente es tuya,
   * porque entonces cualquiera que acierte el id de una lista ajena podría
   * meterle productos nuevos dentro.
   */
  function puede(tabla, id, datos, ya) {
    if (ya && ya.usuario_id === usuarioId) return true;
    if (tabla === 'ajustes') return !ya;                 // los ajustes son de uno
    if (tabla === 'grupos') {
      return ya ? gruposQueEscribo.has(id) : true;       // un grupo nuevo es tuyo
    }

    const ambito = AMBITO_DE[tabla];
    if (!ambito) return !ya;

    // Cuelga de otra fila (artículo → lista, encargo → venta).
    if (ambito.padre) {
      const padreId = String(datos?.[ambito.campo] || '');
      if (!padreId) return !ya;
      const conjunto = ambito.padre === 'listas' ? veo.listas : veo.eventos;
      const padre = bd.prepare(`SELECT usuario_id, grupo_id FROM ${ambito.padre} WHERE id = ?`).get(padreId);
      if (!padre) return !ya;                            // todavía no llegó: se acepta y ya cuadrará
      if (padre.usuario_id === usuarioId) return true;
      if (padre.grupo_id) return gruposQueEscribo.has(padre.grupo_id);
      return conjunto.has(padreId) && puedeEscribirEn(usuarioId, padreId);
    }

    // Está en un grupo.
    const grupoId = String(datos?.grupoId || '');
    if (grupoId) return gruposQueEscribo.has(grupoId);
    // Sin grupo y de otra persona: solo si es una lista compartida suelta.
    if (tabla === 'listas' && ya) return puedeEscribirEn(usuarioId, id);
    return !ya;
  }

  const guarda = bd.transaction(() => {
    for (const t of TABLAS) {
      const filas = Array.isArray(entrantes[t]) ? entrantes[t].slice(0, MAX_FILAS) : [];
      if (!filas.length) continue;

      const ambito = AMBITO_DE[t];
      const lee = bd.prepare(`SELECT usuario_id, actualizado FROM ${t} WHERE id = ?`);
      const extra = ambito ? `, ${ambito.columna}` : '';
      const hueco = ambito ? ', ?' : '';
      const pon = bd.prepare(`INSERT INTO ${t} (id, usuario_id, datos, actualizado, borrado${extra})
        VALUES (?,?,?,?,?${hueco})
        ON CONFLICT(id) DO UPDATE SET datos = excluded.datos, actualizado = excluded.actualizado,
          borrado = excluded.borrado${ambito ? `, ${ambito.columna} = excluded.${ambito.columna}` : ''}`);

      for (const f of filas) {
        const id = String(f?.id || '').slice(0, 64);
        if (!id || !f.datos || typeof f.datos !== 'object') { descartados++; continue; }
        // La fecha la pone quien escribió, no el servidor: el teléfono sin señal
        // escribió a las 10:05 y eso es cuando pasó, no cuando pudo subirlo.
        const cuando = typeof f.actualizado === 'string' && f.actualizado ? f.actualizado : marca;
        const ya = lee.get(id);

        if (!puede(t, id, f.datos, ya)) { descartados++; continue; }
        if (ya && ya.actualizado >= cuando) { descartados++; continue; }

        // La fila SIGUE SIENDO DE QUIEN LA CREÓ, aunque ahora la edite otro:
        // cambiarle el dueño al marcar un producto partiría la lista en trozos.
        const args = [id, ya ? ya.usuario_id : usuarioId, JSON.stringify(f.datos), cuando, f.borrado || null];
        if (ambito) args.push(String(f.datos[ambito.campo] || '') || null);
        pon.run(...args);
        aplicados++;

        if (t === 'listas') tocadas.add(id);
        else if (t === 'articulos' && f.datos.listaId) tocadas.add(String(f.datos.listaId));
      }
      if (t === 'articulos') apuntaPrecios(usuarioId, filas);
    }
  });

  try { guarda(); } catch (e) {
    console.error('[sync]', e.message);
    return res.status(500).json({ error: 'No pude guardar ese lote.' });
  }

  cuenta('sync.subida');
  // El aviso en vivo va DESPUÉS de guardar: al revés, el otro teléfono
  // sincronizaría y no encontraría nada.
  if (tocadas.size) {
    for (const listaId of tocadas) marcaVisto(usuarioId, listaId);
    avisaDeListas(tocadas, usuarioId);
  }

  // Se contesta con lo que el teléfono no tiene todavía, para que subir y bajar
  // sea UNA llamada: en el súper, con dos barras de señal, cada viaje cuenta.
  res.json({ ahora: ahora(), aplicados, descartados, cambios: cambiosDesde(usuarioId, String(cuerpo.desde || '')) });
});

/** Los precios que ya viste, para que la app rellene sola al escribir un nombre. */
sync.get('/precios', (req, res) => {
  res.json({
    precios: bd.prepare('SELECT llano, tienda, unidad, precio, fecha FROM precios WHERE usuario_id = ? ORDER BY fecha DESC LIMIT 600')
      .all(req.usuario.id),
  });
});
