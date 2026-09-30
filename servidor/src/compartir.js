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
export function ambitosDe(usuarioId, ambito) {
  return new Set(bd.prepare('SELECT ambito_id FROM miembros WHERE usuario_id = ? AND ambito = ?')
    .all(usuarioId, ambito).map((f) => f.ambito_id));
}

export function listasCompartidasCon(usuarioId) {
  const fuera = ambitosDe(usuarioId, 'lista');
  // Y las suyas que ella misma compartió: si no, la dueña no ve el café que
  // acaba de añadir su pareja, que es justo el caso para el que se hizo esto.
  for (const f of bd.prepare(`
    SELECT DISTINCT l.id FROM listas l JOIN miembros m ON m.ambito_id = l.id AND m.ambito = 'lista'
    WHERE l.usuario_id = ?`).all(usuarioId)) fuera.add(f.id);
  return fuera;
}

/** Los grupos de los que forma parte, incluidos los suyos. */
export function gruposDe(usuarioId) {
  const fuera = ambitosDe(usuarioId, 'grupo');
  for (const f of bd.prepare('SELECT id FROM grupos WHERE usuario_id = ? AND borrado IS NULL').all(usuarioId)) {
    fuera.add(f.id);
  }
  return fuera;
}

/** Dónde puede ESCRIBIR: sus grupos y aquellos donde es editor. */
export function gruposDondeEscribe(usuarioId) {
  const fuera = new Set(bd.prepare(
    "SELECT ambito_id FROM miembros WHERE usuario_id = ? AND ambito = 'grupo' AND rol IN ('dueño','editor')"
  ).all(usuarioId).map((f) => f.ambito_id));
  for (const f of bd.prepare('SELECT id FROM grupos WHERE usuario_id = ? AND borrado IS NULL').all(usuarioId)) {
    fuera.add(f.id);
  }
  return fuera;
}

/** El rol de alguien en una lista. `null` si no pinta nada ahí. */
export function rolEn(usuarioId, id, ambito = 'lista') {
  const tabla = ambito === 'grupo' ? 'grupos' : 'listas';
  const propia = bd.prepare(`SELECT 1 FROM ${tabla} WHERE id = ? AND usuario_id = ?`).get(id, usuarioId);
  if (propia) return 'dueño';
  const suyo = bd.prepare('SELECT rol FROM miembros WHERE ambito = ? AND ambito_id = ? AND usuario_id = ?')
    .get(ambito, id, usuarioId)?.rol;
  if (suyo) return suyo;

  // Una lista dentro de un grupo la ve quien esté en el grupo, sin invitarla
  // aparte: eso es lo que hace que compartir un negocio se haga una vez.
  if (ambito === 'lista') {
    const grupo = bd.prepare('SELECT grupo_id FROM listas WHERE id = ?').get(id)?.grupo_id;
    if (grupo) return rolEn(usuarioId, grupo, 'grupo');
  }
  return null;
}

export const puedeEscribirEn = (usuarioId, id, ambito = 'lista') =>
  PUEDEN_ESCRIBIR.has(rolEn(usuarioId, id, ambito) || '');

/* ─────────────────────────── los miembros ─────────────────────────── */

export function miembrosDe(listaId, ambito = 'lista') {
  const tabla = ambito === 'grupo' ? 'grupos' : 'listas';
  const lista = bd.prepare(`SELECT usuario_id FROM ${tabla} WHERE id = ?`).get(listaId);
  const dueño = lista ? bd.prepare('SELECT email, nombre FROM usuarios WHERE id = ?').get(lista.usuario_id) : null;

  const filas = bd.prepare(`
    SELECT m.email, m.rol, m.creado, m.visto, m.usuario_id, u.nombre
    FROM miembros m LEFT JOIN usuarios u ON u.id = m.usuario_id
    WHERE m.ambito = ? AND m.ambito_id = ? ORDER BY m.creado`).all(ambito, listaId);

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
export function invita(usuario, listaId, emailCrudo, rol = 'editor', ambito = 'lista') {
  if (rolEn(usuario.id, listaId, ambito) !== 'dueño') {
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

  bd.prepare(`INSERT INTO miembros (ambito, ambito_id, email, usuario_id, rol, creado) VALUES (?,?,?,?,?,?)
    ON CONFLICT(ambito, ambito_id, email) DO UPDATE SET rol = excluded.rol`)
    .run(ambito, listaId, email, quien?.id || null, suRol, ahora());

  cuenta(ambito + '.compartido');
  return { estado: 200, cuerpo: { miembros: miembrosDe(listaId, ambito) } };
}

export function quita(usuario, listaId, emailCrudo, ambito = 'lista') {
  const email = normaliza(emailCrudo);
  const soyDueño = rolEn(usuario.id, listaId, ambito) === 'dueño';
  // Uno siempre puede quitarse a sí mismo, aunque no sea el dueño.
  if (!soyDueño && email !== normaliza(usuario.email)) {
    return { estado: 403, cuerpo: { error: 'No puedes quitar a otra persona de esta lista.' } };
  }
  bd.prepare('DELETE FROM miembros WHERE ambito = ? AND ambito_id = ? AND email = ?')
    .run(ambito, listaId, email);
  return { estado: 200, cuerpo: { miembros: soyDueño ? miembrosDe(listaId, ambito) : [] } };
}

/* ─────────────────────────── el enlace ─────────────────────────── */

/**
 * Un enlace para mandar por WhatsApp, que es como se comparte aquí. Caduca a
 * los siete días: un enlace que vale para siempre acaba reenviado en un grupo
 * de la familia y dentro de la lista de la compra hay precios y costumbres.
 */
export function creaEnlace(usuario, listaId, rol = 'editor', ambito = 'lista') {
  if (rolEn(usuario.id, listaId, ambito) !== 'dueño') {
    return { estado: 403, cuerpo: { error: 'Solo quien creó la lista puede compartirla.' } };
  }
  const codigo = randomBytes(9).toString('base64url');
  bd.prepare('INSERT INTO invitaciones (codigo, ambito, ambito_id, rol, creador, expira) VALUES (?,?,?,?,?,?)')
    .run(codigo, ambito, listaId, ROLES.includes(rol) && rol !== 'dueño' ? rol : 'editor', usuario.id,
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
  const tabla = inv.ambito === 'grupo' ? 'grupos' : 'listas';
  const lista = bd.prepare(`SELECT id, usuario_id, datos FROM ${tabla} WHERE id = ? AND borrado IS NULL`).get(inv.ambito_id);
  if (!lista) return { estado: 404, cuerpo: { error: 'Eso ya no está.' } };
  if (lista.usuario_id === usuario.id) {
    return { estado: 200, cuerpo: { ok: true, listaId: lista.id, ambito: inv.ambito, tuya: true } };
  }

  bd.prepare(`INSERT INTO miembros (ambito, ambito_id, email, usuario_id, rol, creado) VALUES (?,?,?,?,?,?)
    ON CONFLICT(ambito, ambito_id, email) DO UPDATE SET usuario_id = excluded.usuario_id`)
    .run(inv.ambito, lista.id, normaliza(usuario.email), usuario.id, inv.rol, ahora());
  bd.prepare('UPDATE invitaciones SET usos = usos + 1 WHERE codigo = ?').run(inv.codigo);

  cuenta(inv.ambito + '.aceptado');
  let nombre = '';
  try { nombre = JSON.parse(lista.datos).nombre || ''; } catch { /* da igual */ }
  return { estado: 200, cuerpo: { ok: true, listaId: lista.id, ambito: inv.ambito, nombre } };
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
  bd.prepare('UPDATE miembros SET visto = ? WHERE ambito_id = ? AND usuario_id = ?')
    .run(ahora(), listaId, usuarioId);
}

/** Los grupos de alguien, con cuánta gente hay en cada uno. Para la app. */
export function misGrupos(usuarioId) {
  return [...gruposDe(usuarioId)].map((id) => {
    const g = bd.prepare('SELECT datos, usuario_id FROM grupos WHERE id = ? AND borrado IS NULL').get(id);
    if (!g) return null;
    let datos = {};
    try { datos = JSON.parse(g.datos); } catch { /* ilegible */ }
    return {
      id,
      nombre: datos.nombre || 'Grupo',
      mio: g.usuario_id === usuarioId,
      miembros: miembrosDe(id, 'grupo').length,
    };
  }).filter(Boolean);
}
