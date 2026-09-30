// COMPARTIR UNA LISTA.
//
// El caso que hay que resolver es concreto: una pareja entra al súper y se
// separa para acabar antes. Si él marca la leche, ella tiene que verlo en su
// teléfono antes de llegar al pasillo de la nevera. Todo lo demás —los permisos,
// las invitaciones— existe para que eso funcione y no se convierta en un lío.
//
// La decisión que lo ordena todo: **el dueño de la fila y quién puede verla
// dejan de ser lo mismo**. Hasta ahora `usuario_id` era las dos cosas. Ahora
// `usuario_id` sigue siendo quién la escribió —y eso no cambia nunca, ni
// cuando otro la edita— y quién la ve sale de `miembros`.
import { randomBytes } from 'node:crypto';
import { bd, ahora, cuenta } from './bd.js';

const ROLES = ['dueño', 'editor', 'mira'];
const PUEDEN_ESCRIBIR = new Set(['dueño', 'editor']);

export const normaliza = (e) => String(e || '').trim().toLowerCase();

/* ─────────────────────────── quién ve qué ─────────────────────────── */

/**
 * Las listas donde esta persona ve filas de OTRA gente.
 *
 * Son dos casos y hay que contar los dos, cosa que es fácil olvidar:
 *   · aquellas a las que la invitaron, y
 *   · **las suyas que ella misma compartió** — si no, la dueña de la lista no ve
 *     el café que acaba de añadir su pareja, que es justo el caso para el que se
 *     hizo todo esto.
 *
 * Devuelve un Set porque se pregunta una vez por sincronización y después se
 * consulta una vez por fila: una consulta por artículo sería lo mismo escrito mal.
 */
export function listasCompartidasCon(usuarioId) {
  const fuera = new Set(bd.prepare('SELECT lista_id FROM miembros WHERE usuario_id = ?')
    .all(usuarioId).map((f) => f.lista_id));
  for (const f of bd.prepare(`
    SELECT DISTINCT l.id FROM listas l JOIN miembros m ON m.lista_id = l.id
    WHERE l.usuario_id = ?`).all(usuarioId)) fuera.add(f.id);
  return fuera;
}

/** El rol de alguien en una lista. `null` si no pinta nada ahí. */
export function rolEn(usuarioId, listaId) {
  const propia = bd.prepare('SELECT 1 FROM listas WHERE id = ? AND usuario_id = ?').get(listaId, usuarioId);
  if (propia) return 'dueño';
  return bd.prepare('SELECT rol FROM miembros WHERE lista_id = ? AND usuario_id = ?')
    .get(listaId, usuarioId)?.rol || null;
}

export const puedeEscribirEn = (usuarioId, listaId) => PUEDEN_ESCRIBIR.has(rolEn(usuarioId, listaId) || '');

/* ─────────────────────────── los miembros ─────────────────────────── */

export function miembrosDe(listaId) {
  const lista = bd.prepare('SELECT usuario_id FROM listas WHERE id = ?').get(listaId);
  const dueño = lista ? bd.prepare('SELECT email, nombre FROM usuarios WHERE id = ?').get(lista.usuario_id) : null;

  const filas = bd.prepare(`
    SELECT m.email, m.rol, m.creado, m.visto, m.usuario_id, u.nombre
    FROM miembros m LEFT JOIN usuarios u ON u.id = m.usuario_id
    WHERE m.lista_id = ? ORDER BY m.creado`).all(listaId);

  const fuera = filas.map((f) => ({
    email: f.email,
    nombre: f.nombre || '',
    rol: f.rol,
    dentro: !!f.usuario_id,        // false = invitado que todavía no ha entrado
    visto: f.visto,
  }));

  // El dueño va primero y siempre, aunque no tenga fila en `miembros`.
  if (dueño && !fuera.some((m) => m.email === dueño.email)) {
    fuera.unshift({ email: dueño.email, nombre: dueño.nombre || '', rol: 'dueño', dentro: true, visto: null });
  }
  return fuera;
}

/**
 * Invitar por correo. Funciona aunque esa persona no tenga cuenta todavía: la
 * fila se queda con el correo y sin `usuario_id`, y se ata sola cuando entre.
 * Lo contrario —«esa persona no existe, dile que se registre primero»— es pedirle
 * a alguien que haga dos cosas para hacer una.
 */
export function invita(usuario, listaId, emailCrudo, rol = 'editor') {
  if (rolEn(usuario.id, listaId) !== 'dueño') {
    return { estado: 403, cuerpo: { error: 'Solo quien creó la lista puede invitar.' } };
  }
  const email = normaliza(emailCrudo);
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) {
    return { estado: 400, cuerpo: { error: 'Ese correo no tiene buena forma.' } };
  }
  if (email === normaliza(usuario.email)) {
    return { estado: 400, cuerpo: { error: 'Esa lista ya es tuya.' } };
  }
  const suRol = ROLES.includes(rol) && rol !== 'dueño' ? rol : 'editor';
  const quien = bd.prepare('SELECT id FROM usuarios WHERE email = ?').get(email);

  bd.prepare(`INSERT INTO miembros (lista_id, email, usuario_id, rol, creado) VALUES (?,?,?,?,?)
    ON CONFLICT(lista_id, email) DO UPDATE SET rol = excluded.rol`)
    .run(listaId, email, quien?.id || null, suRol, ahora());

  cuenta('lista.compartida');
  return { estado: 200, cuerpo: { miembros: miembrosDe(listaId) } };
}

export function quita(usuario, listaId, emailCrudo) {
  const email = normaliza(emailCrudo);
  const soyDueño = rolEn(usuario.id, listaId) === 'dueño';
  // Uno siempre puede quitarse a sí mismo, aunque no sea el dueño.
  if (!soyDueño && email !== normaliza(usuario.email)) {
    return { estado: 403, cuerpo: { error: 'No puedes quitar a otra persona de esta lista.' } };
  }
  bd.prepare('DELETE FROM miembros WHERE lista_id = ? AND email = ?').run(listaId, email);
  return { estado: 200, cuerpo: { miembros: soyDueño ? miembrosDe(listaId) : [] } };
}

/* ─────────────────────────── el enlace ─────────────────────────── */

/**
 * Un enlace para mandar por WhatsApp, que es como se comparte aquí. Caduca a
 * los siete días: un enlace que vale para siempre acaba reenviado en un grupo
 * de la familia y dentro de la lista de la compra hay precios y costumbres.
 */
export function creaEnlace(usuario, listaId, rol = 'editor') {
  if (rolEn(usuario.id, listaId) !== 'dueño') {
    return { estado: 403, cuerpo: { error: 'Solo quien creó la lista puede compartirla.' } };
  }
  const codigo = randomBytes(9).toString('base64url');
  bd.prepare('INSERT INTO invitaciones (codigo, lista_id, rol, creador, expira) VALUES (?,?,?,?,?)')
    .run(codigo, listaId, ROLES.includes(rol) && rol !== 'dueño' ? rol : 'editor', usuario.id,
         new Date(Date.now() + 7 * 864e5).toISOString());
  cuenta('lista.enlace');
  return { estado: 200, cuerpo: { codigo } };
}

export function aceptaEnlace(usuario, codigo) {
  const inv = bd.prepare('SELECT * FROM invitaciones WHERE codigo = ?').get(String(codigo || ''));
  if (!inv) return { estado: 404, cuerpo: { error: 'Ese enlace no vale.' } };
  if (inv.expira <= ahora()) {
    bd.prepare('DELETE FROM invitaciones WHERE codigo = ?').run(inv.codigo);
    return { estado: 410, cuerpo: { error: 'Ese enlace caducó. Pide otro.' } };
  }
  const lista = bd.prepare('SELECT id, usuario_id, datos FROM listas WHERE id = ? AND borrado IS NULL').get(inv.lista_id);
  if (!lista) return { estado: 404, cuerpo: { error: 'Esa lista ya no está.' } };
  if (lista.usuario_id === usuario.id) return { estado: 200, cuerpo: { ok: true, listaId: lista.id, tuya: true } };

  bd.prepare(`INSERT INTO miembros (lista_id, email, usuario_id, rol, creado) VALUES (?,?,?,?,?)
    ON CONFLICT(lista_id, email) DO UPDATE SET usuario_id = excluded.usuario_id`)
    .run(lista.id, normaliza(usuario.email), usuario.id, inv.rol, ahora());
  bd.prepare('UPDATE invitaciones SET usos = usos + 1 WHERE codigo = ?').run(inv.codigo);

  cuenta('lista.aceptada');
  let nombre = '';
  try { nombre = JSON.parse(lista.datos).nombre || ''; } catch { /* da igual */ }
  return { estado: 200, cuerpo: { ok: true, listaId: lista.id, nombre } };
}

/**
 * Al entrar: atar las invitaciones que llegaron a ese correo antes de que
 * existiera la cuenta. Sin esto, invitar a alguien que todavía no se ha
 * registrado no sirve de nada.
 */
export function reclamaInvitaciones(usuario) {
  const n = bd.prepare('UPDATE miembros SET usuario_id = ? WHERE email = ? AND usuario_id IS NULL')
    .run(usuario.id, normaliza(usuario.email)).changes;
  if (n) cuenta('lista.invitacion.reclamada');
  return n;
}

/** Que la otra persona vea que estás mirando, y cuándo estuviste. */
export function marcaVisto(usuarioId, listaId) {
  bd.prepare('UPDATE miembros SET visto = ? WHERE lista_id = ? AND usuario_id = ?')
    .run(ahora(), listaId, usuarioId);
}
