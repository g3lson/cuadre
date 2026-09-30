// COMPARTIR: LISTAS Y GRUPOS.
//
// Las dos cosas se comparten igual —invitar por correo, un enlace, quitar a
// alguien— así que las rutas son las mismas y solo cambia el ámbito. Escribirlo
// dos veces sería tener dos sitios donde arreglar el mismo fallo.
//
// El contenido no pasa por aquí: eso es `sync`. Dos caminos para escribir lo
// mismo son dos maneras de quedar descuadrado.
import { Router } from 'express';
import { bd } from '../bd.js';
import { conSesion } from '../auth.js';
import { config } from '../config.js';
import {
  invita, quita, miembrosDe, creaEnlace, aceptaEnlace, rolEn, normaliza, misGrupos,
} from '../compartir.js';
import { avisaAlguien, quienesVen } from '../eventos.js';

/** Quién hay que avisar cuando algo cambia en este ámbito. */
function aQuienAvisar(ambito, id) {
  if (ambito === 'lista') return quienesVen(id);
  const ids = new Set();
  const g = bd.prepare('SELECT usuario_id FROM grupos WHERE id = ?').get(id);
  if (g) ids.add(g.usuario_id);
  for (const m of bd.prepare(
    "SELECT usuario_id FROM miembros WHERE ambito = 'grupo' AND ambito_id = ? AND usuario_id IS NOT NULL"
  ).all(id)) ids.add(m.usuario_id);
  return ids;
}

const nombreDe = (ambito, id) => {
  const f = bd.prepare(`SELECT datos FROM ${ambito === 'grupo' ? 'grupos' : 'listas'} WHERE id = ?`).get(id);
  try { return JSON.parse(f?.datos || '{}').nombre || ''; } catch { return ''; }
};

/** Las mismas rutas para los dos ámbitos. */
export function rutasDeCompartir(ambito) {
  const r = Router();
  r.use(conSesion);

  r.get('/:id/miembros', (req, res) => {
    if (!rolEn(req.usuario.id, req.params.id, ambito)) {
      return res.status(404).json({ error: 'Eso no está.' });
    }
    res.json({
      miembros: miembrosDe(req.params.id, ambito),
      yo: normaliza(req.usuario.email),
      rol: rolEn(req.usuario.id, req.params.id, ambito),
    });
  });

  r.post('/:id/miembros', (req, res) => {
    const salida = invita(req.usuario, req.params.id, req.body?.correo, req.body?.rol, ambito);
    if (salida.estado === 200) avisaAlguien(aQuienAvisar(ambito, req.params.id), 'compartida');
    res.status(salida.estado).json(salida.cuerpo);
  });

  r.delete('/:id/miembros/:correo', (req, res) => {
    const antes = aQuienAvisar(ambito, req.params.id);
    const salida = quita(req.usuario, req.params.id, decodeURIComponent(req.params.correo), ambito);
    if (salida.estado === 200) avisaAlguien(antes, 'compartida');
    res.status(salida.estado).json(salida.cuerpo);
  });

  /**
   * El enlace para mandar por WhatsApp. Se devuelve entero y con su texto: que
   * la app sepa cómo se arma la URL es una manera de que un día se arme mal en
   * un sitio y bien en el otro.
   */
  r.post('/:id/enlace', (req, res) => {
    const salida = creaEnlace(req.usuario, req.params.id, req.body?.rol, ambito);
    if (salida.estado !== 200) return res.status(salida.estado).json(salida.cuerpo);
    const url = `${config.sitio}/invitacion/${salida.cuerpo.codigo}`;
    const nombre = nombreDe(ambito, req.params.id);
    res.json({
      codigo: salida.cuerpo.codigo,
      url,
      texto: ambito === 'grupo'
        ? `Te sumo al grupo «${nombre}» en Cuadre: ${url}`
        : `Te comparto la lista «${nombre}» en Cuadre: ${url}`,
    });
  });

  return r;
}

export const listas = rutasDeCompartir('lista');
export const grupos = rutasDeCompartir('grupo');

/** Aceptar una invitación, del ámbito que sea: el código ya sabe cuál es. */
grupos.post('/invitacion/:codigo', conSesion, (req, res) => {
  const salida = aceptaEnlace(req.usuario, req.params.codigo);
  if (salida.estado === 200) {
    avisaAlguien(aQuienAvisar(salida.cuerpo.ambito || 'lista', salida.cuerpo.listaId), 'compartida');
  }
  res.status(salida.estado).json(salida.cuerpo);
});

/** Mis grupos con cuánta gente hay en cada uno, para la pantalla de Ajustes. */
grupos.get('/', conSesion, (req, res) => res.json({ grupos: misGrupos(req.usuario.id) }));
