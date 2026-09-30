// COMPARTIR LISTAS.
//
// Todo lo que no es sincronizar: invitar, aceptar, ver quién está y salirse.
// El contenido de la lista no pasa por aquí —eso es `sync`— porque tener dos
// caminos para escribir lo mismo es tener dos maneras de quedar descuadrado.
import { Router } from 'express';
import { bd } from '../bd.js';
import { conSesion } from '../auth.js';
import { config } from '../config.js';
import {
  invita, quita, miembrosDe, creaEnlace, aceptaEnlace, rolEn, normaliza,
} from '../compartir.js';
import { avisaAlguien, quienesVen } from '../eventos.js';

export const listas = Router();
listas.use(conSesion);

const nombreDe = (listaId) => {
  const f = bd.prepare('SELECT datos FROM listas WHERE id = ?').get(listaId);
  try { return JSON.parse(f?.datos || '{}').nombre || ''; } catch { return ''; }
};

/** Quién está en esta lista. Lo ve cualquiera que pueda verla. */
listas.get('/:id/miembros', (req, res) => {
  if (!rolEn(req.usuario.id, req.params.id)) {
    return res.status(404).json({ error: 'Esa lista no está.' });
  }
  res.json({ miembros: miembrosDe(req.params.id), yo: normaliza(req.usuario.email) });
});

/** Invitar por correo. Funciona aunque esa persona todavía no tenga cuenta. */
listas.post('/:id/miembros', (req, res) => {
  const r = invita(req.usuario, req.params.id, req.body?.correo, req.body?.rol);
  if (r.estado === 200) avisaAlguien(quienesVen(req.params.id), 'compartida');
  res.status(r.estado).json(r.cuerpo);
});

/** Quitar a alguien — o quitarse uno mismo, que es lo de «dejar la lista». */
listas.delete('/:id/miembros/:correo', (req, res) => {
  const antes = quienesVen(req.params.id);
  const r = quita(req.usuario, req.params.id, decodeURIComponent(req.params.correo));
  if (r.estado === 200) avisaAlguien(antes, 'compartida');
  res.status(r.estado).json(r.cuerpo);
});

/**
 * El enlace para mandar por WhatsApp. Se devuelve entero, listo para pegar: que
 * la app tenga que saber cómo se arma la URL es una manera de que un día se
 * arme mal en un sitio y bien en el otro.
 */
listas.post('/:id/enlace', (req, res) => {
  const r = creaEnlace(req.usuario, req.params.id, req.body?.rol);
  if (r.estado !== 200) return res.status(r.estado).json(r.cuerpo);
  res.json({
    codigo: r.cuerpo.codigo,
    url: `${config.sitio}/invitacion/${r.cuerpo.codigo}`,
    texto: `Te comparto la lista «${nombreDe(req.params.id)}» en Cuadre: `
         + `${config.sitio}/invitacion/${r.cuerpo.codigo}`,
  });
});

/** Aceptar. Lo llama la app cuando abre un enlace de invitación. */
listas.post('/invitacion/:codigo', (req, res) => {
  const r = aceptaEnlace(req.usuario, req.params.codigo);
  if (r.estado === 200) avisaAlguien(quienesVen(r.cuerpo.listaId), 'compartida');
  res.status(r.estado).json(r.cuerpo);
});
