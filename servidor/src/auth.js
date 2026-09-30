// ENTRAR.
//
// Dos puertas y una sola sesión detrás: Sign in with Apple, que es la que usa
// casi todo el mundo desde el teléfono, y un código de seis dígitos al correo,
// que es la que queda cuando el iPhone no es tuyo o cuando algún día haya
// Android.
//
// La sesión es un token opaco (`cua_…`) que se guarda RESUMIDO: si alguien se
// lleva la base, no se lleva las sesiones.
import { randomBytes, randomInt, timingSafeEqual } from 'node:crypto';
import { createRemoteJWKSet, jwtVerify } from 'jose';
import { bd, ahora, uid, resumen, cuenta } from './bd.js';
import { config } from './config.js';
import { mandaCodigo } from './correo.js';

const DIAS = 90;

/** Si la API se sirve desde esta misma máquina, esto es un portátil o el CI. */
const esLocal = () => /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(:|\/|$)/.test(config.sitio);
const enUnos = (ms) => new Date(Date.now() + ms).toISOString();

/* ────────────────────────────── usuarios ────────────────────────────── */

const porEmail = (email) => bd.prepare('SELECT * FROM usuarios WHERE email = ?').get(email);

export function creaUsuario({ email = null, nombre = '', appleSub = null }) {
  const id = uid();
  bd.prepare('INSERT INTO usuarios (id, email, nombre, apple_sub, creado) VALUES (?,?,?,?,?)')
    .run(id, email, String(nombre || '').slice(0, 60), appleSub, ahora());
  // Los ajustes nacen con la persona para que el primer arranque no tenga que
  // decidir nada: tema Barro, RD$, libra, modo vendedor apagado.
  bd.prepare('INSERT INTO ajustes (id, usuario_id, datos, actualizado) VALUES (?,?,?,?)')
    .run(id, id, JSON.stringify({
      tema: 'barro', moneda: 'RD$', unidadPorDefecto: 'lb', modoVendedor: false,
      columnas: { cantidad: true, precio: true, total: true, nota: false },
      tarifas: ['Detal', 'Mayor', 'Especial'],
    }), ahora());
  return bd.prepare('SELECT * FROM usuarios WHERE id = ?').get(id);
}

export const publico = (u) => ({
  id: u.id,
  email: u.email || '',
  nombre: u.nombre || '',
  inicial: (u.nombre || u.email || '?').replace(/^(doña|don|sr\.?|sra\.?)\s+/i, '').trim().charAt(0).toUpperCase(),
  conApple: !!u.apple_sub,
  creado: u.creado,
});

/* ────────────────────────────── sesiones ────────────────────────────── */

export function abreSesion(usuario, dispositivo) {
  const token = 'cua_' + randomBytes(32).toString('base64url');
  bd.prepare('INSERT INTO sesiones (id, token, usuario_id, dispositivo, creado, expira) VALUES (?,?,?,?,?,?)')
    .run(uid(), resumen(token), usuario.id, String(dispositivo || '').slice(0, 80), ahora(), enUnos(DIAS * 864e5));
  bd.prepare('UPDATE usuarios SET visto = ? WHERE id = ?').run(ahora(), usuario.id);
  return { token, dura: DIAS * 86400 };
}

/**
 * El guardia. Deja `req.usuario` y `req.sesion` listos, o contesta 401.
 *
 * La sesión se estira al usarla: quien abre la app cada semana no vuelve a
 * escribir un código nunca, y quien la abandonó tres meses sí.
 */
export function conSesion(req, res, next) {
  const cab = req.get('authorization') || '';
  const enClaro = cab.startsWith('Bearer ') ? cab.slice(7).trim() : '';
  if (!enClaro) return res.status(401).json({ error: 'Hace falta iniciar sesión.', sesion: false });

  const s = bd.prepare('SELECT * FROM sesiones WHERE token = ? AND revocada IS NULL').get(resumen(enClaro));
  if (!s || s.expira <= ahora()) return res.status(401).json({ error: 'La sesión caducó.', sesion: false });

  const u = bd.prepare('SELECT * FROM usuarios WHERE id = ?').get(s.usuario_id);
  if (!u || u.estado !== 'activo') return res.status(403).json({ error: 'Esta cuenta no está activa.' });

  bd.prepare('UPDATE sesiones SET ultimo_uso = ?, expira = ? WHERE id = ?').run(ahora(), enUnos(DIAS * 864e5), s.id);
  req.usuario = u;
  req.sesion = s;
  next();
}

export const cierraSesion = (id) => bd.prepare('UPDATE sesiones SET revocada = ? WHERE id = ?').run(ahora(), id);
export const cierraTodas = (usuarioId) =>
  bd.prepare('UPDATE sesiones SET revocada = ? WHERE usuario_id = ? AND revocada IS NULL').run(ahora(), usuarioId);
export const sesionesDe = (usuarioId) => bd.prepare(
  'SELECT id, dispositivo, creado, ultimo_uso FROM sesiones WHERE usuario_id = ? AND revocada IS NULL ORDER BY creado DESC'
).all(usuarioId);

/* ───────────────────────── código por correo ───────────────────────── */

const normaliza = (e) => String(e || '').trim().toLowerCase();
const esEmail = (e) => /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(e);

/**
 * Pide un código. Contesta lo mismo exista la cuenta o no —si no existe, se
 * crea al entrar—: decir «ese correo no está registrado» es regalar la lista de
 * quién usa la app.
 */
export async function pideCodigo(emailCrudo) {
  const email = normaliza(emailCrudo);
  if (!esEmail(email)) return { estado: 400, cuerpo: { error: 'Ese correo no tiene buena forma.' } };

  const ya = bd.prepare('SELECT * FROM codigos WHERE email = ?').get(email);
  // Un código por minuto: sin esto, el buzón de cualquiera es un blanco.
  if (ya && Date.parse(ya.creado) > Date.now() - 60_000) {
    return { estado: 429, cuerpo: { error: 'Acabo de mandarte uno. Espera un minuto.' } };
  }

  const codigo = String(randomInt(0, 1_000_000)).padStart(6, '0');
  bd.prepare(`INSERT INTO codigos (email, codigo, expira, intentos, creado) VALUES (?,?,?,0,?)
    ON CONFLICT(email) DO UPDATE SET codigo = excluded.codigo, expira = excluded.expira, intentos = 0, creado = excluded.creado`)
    .run(email, resumen(codigo), enUnos(10 * 60_000), ahora());

  const salio = await mandaCodigo(email, codigo);
  cuenta('auth.codigo');
  if (!salio) {
    // En desarrollo no hay Resend y el código sale por el registro, que es donde
    // lo va a buscar quien esté probando. Se decide por la URL pública y no por
    // «¿hay clave de correo?»: un servidor de verdad con el correo mal
    // configurado imprimiría códigos de gente real en el registro.
    if (esLocal()) console.log('[auth] código para', email, '→', codigo);
    else return { estado: 503, cuerpo: { error: 'No pude mandar el correo ahora mismo. Prueba con Apple.' } };
  }
  return { estado: 200, cuerpo: { ok: true, correo: email } };
}

/** Canjea el código por una sesión. Crea la cuenta si es la primera vez. */
export function entraConCodigo(emailCrudo, codigoCrudo, dispositivo) {
  const email = normaliza(emailCrudo);
  const codigo = String(codigoCrudo || '').replace(/\D/g, '');
  const fila = bd.prepare('SELECT * FROM codigos WHERE email = ?').get(email);
  if (!fila || fila.expira <= ahora()) return { estado: 400, cuerpo: { error: 'Ese código ya no vale. Pide otro.' } };
  if (fila.intentos >= 5) {
    bd.prepare('DELETE FROM codigos WHERE email = ?').run(email);
    return { estado: 429, cuerpo: { error: 'Demasiados intentos. Pide un código nuevo.' } };
  }

  const a = Buffer.from(resumen(codigo));
  const b = Buffer.from(fila.codigo);
  if (a.length !== b.length || !timingSafeEqual(a, b)) {
    bd.prepare('UPDATE codigos SET intentos = intentos + 1 WHERE email = ?').run(email);
    return { estado: 400, cuerpo: { error: 'Ese código no es.' } };
  }
  bd.prepare('DELETE FROM codigos WHERE email = ?').run(email);

  const u = porEmail(email) || creaUsuario({ email });
  cuenta('auth.entrar.correo');
  return { estado: 200, cuerpo: { ok: true, ...abreSesion(u, dispositivo), usuario: publico(u) } };
}

/* ────────────────────── Sign in with Apple ────────────────────── */

// Las llaves públicas de Apple. `jose` las cachea y las renueva sola: pedirlas
// en cada inicio de sesión sería llamar a Apple por cada arranque de la app.
const llavesApple = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));

/**
 * Comprueba el `identityToken` que devuelve Apple en el teléfono y abre sesión.
 *
 * El nombre solo viene la PRIMERA vez que alguien autoriza la app; después Apple
 * no lo manda más. Por eso se guarda si viene y no se toca si no.
 */
export async function entraConApple(identityToken, nombre, dispositivo) {
  let carga;
  try {
    const { payload } = await jwtVerify(String(identityToken || ''), llavesApple, {
      issuer: 'https://appleid.apple.com',
      audience: config.appleAudiencia,
    });
    carga = payload;
  } catch (e) {
    return { estado: 401, cuerpo: { error: 'Apple no validó esa sesión.', detalle: e.message } };
  }

  const sub = String(carga.sub || '');
  if (!sub) return { estado: 401, cuerpo: { error: 'A ese token de Apple le falta el identificador.' } };
  // Con «Ocultar mi correo» esto es una dirección de reenvío de Apple; sirve
  // igual para mandar el reporte, así que se guarda tal cual.
  const email = carga.email ? normaliza(carga.email) : null;

  let u = bd.prepare('SELECT * FROM usuarios WHERE apple_sub = ?').get(sub);
  if (!u && email) {
    // Ya entró antes por correo y ahora usa Apple: es la misma persona, se pega
    // el identificador de Apple a la cuenta que ya tiene en vez de partirla en dos.
    u = porEmail(email);
    if (u) bd.prepare('UPDATE usuarios SET apple_sub = ? WHERE id = ?').run(sub, u.id);
  }
  if (!u) u = creaUsuario({ email, nombre, appleSub: sub });
  else if (nombre && !u.nombre) {
    bd.prepare('UPDATE usuarios SET nombre = ? WHERE id = ?').run(String(nombre).slice(0, 60), u.id);
    u = bd.prepare('SELECT * FROM usuarios WHERE id = ?').get(u.id);
  }

  cuenta('auth.entrar.apple');
  return { estado: 200, cuerpo: { ok: true, ...abreSesion(u, dispositivo), usuario: publico(u) } };
}

/** Borrar la cuenta de verdad: se va la persona y con ella todo lo suyo (ON DELETE CASCADE). */
export function borraCuenta(usuarioId) {
  bd.prepare('DELETE FROM usuarios WHERE id = ?').run(usuarioId);
  cuenta('cuenta.borrada');
}
