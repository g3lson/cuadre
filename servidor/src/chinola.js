// LA CUENTA DE CHINOLA, CONECTADA.
//
// No es «pega aquí tu clave de API». Es lo que hace Instagram con Facebook: la
// persona toca «Conectar», entra en Chinola con su propia cuenta, ve qué le va a
// dejar tocar, dice que sí, y de ahí en adelante Cuadre puede registrar gastos
// sin volver a preguntar nada.
//
// Lo que hace que se QUEDE conectada: el token de acceso dura ocho horas, pero
// el de refresco no, y vive AQUÍ, en el servidor. La app nunca lo ve. Cuando
// alguien cierra una compra tres semanas después, esto refresca solo y el gasto
// entra. Si el teléfono guardara el token, un reinstalar la app sería
// desconectar la cuenta.
import { randomBytes, createHash } from 'node:crypto';
import { bd, ahora, cuenta, guarda, lee } from './bd.js';
import { config } from './config.js';

const SCOPES = 'movimientos:crear libretas:ver resumen:ver cuentas:ver categorias:ver';
const VUELTA = () => config.sitio + '/chinola/vuelta';
const enUnos = (s) => new Date(Date.now() + s * 1000).toISOString();

const url = (camino) => config.chinola.sitio + camino;

async function pide(camino, opciones = {}) {
  const r = await fetch(url(camino), { signal: AbortSignal.timeout(20_000), ...opciones });
  const texto = await r.text();
  let cuerpo = null;
  try { cuerpo = texto ? JSON.parse(texto) : null; } catch { cuerpo = { error: texto.slice(0, 200) }; }
  return { ok: r.ok, estado: r.status, cuerpo };
}

/* ─────────────────────────── el cliente OAuth ─────────────────────────── */

/**
 * Cuadre se da de alta en Chinola una sola vez, con registro dinámico, y se
 * guarda el `client_id` en la base. Ponerlo en el `.env` a mano obligaría a
 * registrarlo por fuera antes de que la app sirva de algo.
 */
async function clienteId() {
  if (config.chinola.clienteId) return config.chinola.clienteId;
  // El registro se guarda junto con la dirección de vuelta que se usó: si la URL
  // pública de la API cambia, el cliente viejo ya no sirve y hay que registrar
  // otro, porque Chinola compara la vuelta entera.
  const guardado = lee('chinola_cliente');
  if (guardado) {
    const j = JSON.parse(guardado);
    if (j.redirect === VUELTA()) return j.client_id;
  }

  const r = await pide('/oauth/registro', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ client_name: 'Cuadre (iOS)', redirect_uris: [VUELTA()] }),
  });
  if (!r.ok || !r.cuerpo?.client_id) {
    throw Object.assign(new Error('Chinola no dejó registrar la app: ' + (r.cuerpo?.error_description || r.estado)), { estado: 502 });
  }
  guarda('chinola_cliente', JSON.stringify({ client_id: r.cuerpo.client_id, redirect: VUELTA() }));
  return r.cuerpo.client_id;
}

/* ───────────────────────────── conectar ───────────────────────────── */

/** Paso 1: la URL a la que mandar a la persona. Guarda el verificador de PKCE. */
export async function empiezaConexion(usuarioId, vueltaApp = 'cuadre://chinola') {
  const cid = await clienteId();
  const verificador = randomBytes(40).toString('base64url');
  const reto = createHash('sha256').update(verificador).digest('base64url');
  const estado = randomBytes(24).toString('base64url');

  bd.prepare('INSERT INTO chinola_espera (estado, usuario_id, verificador, vuelta, expira) VALUES (?,?,?,?,?)')
    .run(estado, usuarioId, verificador, String(vueltaApp).slice(0, 200), enUnos(600));

  const u = new URL(url('/oauth/autorizar'));
  u.searchParams.set('response_type', 'code');
  u.searchParams.set('client_id', cid);
  u.searchParams.set('redirect_uri', VUELTA());
  u.searchParams.set('scope', SCOPES);
  u.searchParams.set('state', estado);
  u.searchParams.set('code_challenge', reto);
  u.searchParams.set('code_challenge_method', 'S256');
  // RFC 8707: el token se emite para el recurso de Chinola y no vale en otro.
  u.searchParams.set('resource', config.chinola.sitio + '/api/mcp');
  return { url: u.toString(), estado };
}

/** Paso 2: Chinola nos devuelve el código. Se canjea y se guarda la conexión. */
export async function terminaConexion(codigo, estado) {
  const espera = bd.prepare('SELECT * FROM chinola_espera WHERE estado = ?').get(String(estado || ''));
  if (!espera) throw Object.assign(new Error('Esa vuelta no la pedí yo, o ya caducó.'), { estado: 400 });
  bd.prepare('DELETE FROM chinola_espera WHERE estado = ?').run(espera.estado);
  if (espera.expira <= ahora()) throw Object.assign(new Error('Tardaste demasiado. Prueba otra vez.'), { estado: 400 });

  const cid = await clienteId();
  const r = await pide('/oauth/token', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      grant_type: 'authorization_code',
      code: String(codigo || ''),
      code_verifier: espera.verificador,
      client_id: cid,
      redirect_uri: VUELTA(),
    }),
  });
  if (!r.ok || !r.cuerpo?.access_token) {
    throw Object.assign(new Error('Chinola no dio el token: ' + (r.cuerpo?.error_description || r.estado)), { estado: 502 });
  }

  bd.prepare(`INSERT INTO chinola (usuario_id, token, refresco, expira, permisos, creado)
    VALUES (?,?,?,?,?,?)
    ON CONFLICT(usuario_id) DO UPDATE SET token = excluded.token, refresco = excluded.refresco,
      expira = excluded.expira, permisos = excluded.permisos, creado = excluded.creado`)
    .run(espera.usuario_id, r.cuerpo.access_token, r.cuerpo.refresh_token,
         enUnos(Number(r.cuerpo.expires_in || 28800) - 120), String(r.cuerpo.scope || SCOPES), ahora());

  cuenta('chinola.conectada');
  return { usuarioId: espera.usuario_id, vuelta: espera.vuelta || 'cuadre://chinola' };
}

/**
 * El token bueno ahora mismo, refrescando si toca.
 *
 * El de refresco se ROTA en cada uso: si el nuevo no se guarda, la conexión
 * muere. Por eso se guarda antes de devolver nada.
 */
async function token(usuarioId) {
  const c = bd.prepare('SELECT * FROM chinola WHERE usuario_id = ?').get(usuarioId);
  if (!c) throw Object.assign(new Error('No tienes Chinola conectada.'), { estado: 409, sinConexion: true });
  if (c.expira > ahora()) return c;

  const cid = await clienteId();
  const r = await pide('/oauth/token', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ grant_type: 'refresh_token', refresh_token: c.refresco, client_id: cid }),
  });
  if (!r.ok || !r.cuerpo?.access_token) {
    // Un refresco que ya no vale es una conexión revocada desde Chinola: se
    // borra aquí también, para que la app diga «conectar» y no «reintentando».
    bd.prepare('DELETE FROM chinola WHERE usuario_id = ?').run(usuarioId);
    throw Object.assign(new Error('La conexión con Chinola se cerró. Vuelve a conectarla.'), { estado: 409, sinConexion: true });
  }
  bd.prepare('UPDATE chinola SET token = ?, refresco = ?, expira = ? WHERE usuario_id = ?')
    .run(r.cuerpo.access_token, r.cuerpo.refresh_token, enUnos(Number(r.cuerpo.expires_in || 28800) - 120), usuarioId);
  return bd.prepare('SELECT * FROM chinola WHERE usuario_id = ?').get(usuarioId);
}

async function conToken(usuarioId, camino, opciones = {}) {
  const c = await token(usuarioId);
  const r = await pide(camino, {
    ...opciones,
    headers: { authorization: 'Bearer ' + c.token, 'content-type': 'application/json', ...(opciones.headers || {}) },
  });
  bd.prepare('UPDATE chinola SET ultimo_uso = ? WHERE usuario_id = ?').run(ahora(), usuarioId);
  return r;
}

/* ───────────────────────────── usarla ───────────────────────────── */

export const conexionDe = (usuarioId) => bd.prepare(
  'SELECT libreta, medio, cuenta, permisos, creado, ultimo_uso FROM chinola WHERE usuario_id = ?'
).get(usuarioId) || null;

export const desconecta = async (usuarioId) => {
  const c = bd.prepare('SELECT * FROM chinola WHERE usuario_id = ?').get(usuarioId);
  bd.prepare('DELETE FROM chinola WHERE usuario_id = ?').run(usuarioId);
  // Se le avisa a Chinola para que el token muera allí también y la conexión
  // desaparezca de su lista. Si falla, aquí ya no está: no se reintenta.
  if (c) { try { await pide('/oauth/revocar', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ token: c.token }) }); } catch { /* da igual */ } }
  cuenta('chinola.desconectada');
};

/** Las libretas, cuentas y categorías donde se puede anotar. Para la pantalla de «Pasar a Chinola». */
export async function destinos(usuarioId) {
  const r = await conToken(usuarioId, '/api/v1/libretas');
  if (!r.ok) throw Object.assign(new Error(r.cuerpo?.error || 'Chinola no contestó.'), { estado: r.estado });
  return r.cuerpo;
}

/** Guarda a dónde va por defecto, para no preguntarlo en cada compra. */
export function fijaDestino(usuarioId, { libreta, medio, cuenta: nombreCuenta }) {
  bd.prepare('UPDATE chinola SET libreta = ?, medio = ?, cuenta = ? WHERE usuario_id = ?')
    .run(String(libreta || ''), String(medio || ''), String(nombreCuenta || ''), usuarioId);
  return conexionDe(usuarioId);
}

/**
 * Anota el gasto. `lineas` es una por categoría cuando la persona pidió partir
 * la compra, o una sola con el total.
 *
 * `idempotencia` es lo que hace que tocar «Enviar» dos veces no cobre dos
 * veces: el id de la compra viaja con el movimiento y Chinola reconoce el
 * repetido.
 */
export async function anota(usuarioId, { lineas, fecha, libreta, medio, tipo = 'Gasto Variable' }) {
  const c = conexionDe(usuarioId);
  const lb = libreta || c?.libreta || '';
  const md = medio || c?.medio || '';
  const hechos = [];

  for (const l of lineas) {
    const r = await conToken(usuarioId, '/api/v1/movimientos', {
      method: 'POST',
      body: JSON.stringify({
        concepto: String(l.concepto || 'Compra').slice(0, 80),
        monto: Math.abs(Number(l.monto) || 0),
        tipo: l.tipo || tipo,
        categoria: l.categoria || undefined,
        fecha: fecha || undefined,
        libreta: lb || undefined,
        medio: md || undefined,
        origen: 'cuadre',
        idempotencia: l.idempotencia || undefined,
      }),
    });
    if (!r.ok) throw Object.assign(new Error(r.cuerpo?.error || 'Chinola rechazó el movimiento.'), { estado: r.estado });
    hechos.push({ id: r.cuerpo?.movimiento?.id, concepto: l.concepto, monto: l.monto, repetido: !!r.cuerpo?.repetido, libreta: r.cuerpo?.libreta });
  }
  cuenta('chinola.movimientos');
  return { movimientos: hechos, balance: hechos.length ? undefined : null };
}
