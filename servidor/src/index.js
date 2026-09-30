// CUADRE — SERVIDOR.
//
// Una sola pieza: la API que usa la app del teléfono y el sitio público que
// explica qué es y dónde están las políticas. Van juntas porque son el mismo
// dominio y el mismo despliegue, y separarlas serían dos contenedores para
// servir cuatro archivos HTML.
import express from 'express';
import { join } from 'node:path';
import { existsSync } from 'node:fs';
import { config, hayIA, hayCorreo } from './config.js';
import { bd, ahora, barre, cuenta } from './bd.js';
import {
  conSesion, publico, pideCodigo, entraConCodigo, entraConApple,
  cierraSesion, cierraTodas, sesionesDe, borraCuenta,
} from './auth.js';
import { sync } from './rutas/sync.js';
import { listaDeTexto, listaDeRecibo, reciboDeTexto } from './ia.js';
import * as chin from './chinola.js';
import { guardaReporte, leeReporte, pdf, paginaReporte } from './reportes.js';
import { arrancaRespaldos, estado as estadoRespaldos, respalda } from './respaldos.js';

const app = express();
app.set('trust proxy', 1);       // hay un Nginx delante; sin esto la IP es la del proxy
app.disable('x-powered-by');

/* ────────────────────────────── entrada ────────────────────────────── */

// El recibo viaja en base64 dentro del JSON: una foto de móvil comprimida cabe
// de sobra en 12 MB, y así no hay que montar subida por trozos para una cosa.
app.use('/api/ia/recibo', express.json({ limit: '12mb' }));
app.use(express.json({ limit: '2mb' }));
app.use(express.urlencoded({ extended: false, limit: '64kb' }));

/**
 * Un cubo por IP y minuto, contado en memoria.
 *
 * No pretende parar un ataque —eso es del proxy— sino que un bucle en la app o
 * alguien probando códigos a mano no ocupe el servidor entero. Se guarda el
 * minuto y la cuenta, y el mapa se vacía solo: recordar horas de IPs para esto
 * es una fuga de memoria con forma de defensa.
 */
const cubos = new Map();
function limite(porMinuto) {
  return (req, res, next) => {
    const min = Math.floor(Date.now() / 60000);
    const llave = (req.ip || '?') + '|' + req.path;
    const b = cubos.get(llave);
    if (!b || b.min !== min) cubos.set(llave, { min, n: 1 });
    else if (++b.n > porMinuto) return res.status(429).json({ error: 'Vas muy rápido. Espera un minuto.' });
    if (cubos.size > 5000) for (const [k, v] of cubos) if (v.min < min) cubos.delete(k);
    next();
  };
}

/* ────────────────────────────── salud ────────────────────────────── */

app.get('/api/salud', (req, res) => {
  res.json({ ok: true, version: config.version, ahora: ahora(), ia: hayIA(), correo: hayCorreo() });
});

/**
 * CIFRAS PARA VIGÍA.
 *
 * La forma la manda Vigía: `totales` van a sus series, `diario` a su tabla de
 * días, `tarjetas` se enseñan tal cual y `alertas` llegan al Telegram. Aquí no
 * sale ni un nombre, ni un correo, ni un producto: solo cuántos.
 *
 * Vigía autentica con `Authorization: Bearer`; se acepta también `x-clave`
 * porque es como se prueba a mano desde el servidor.
 */
app.get('/api/metricas', (req, res) => {
  const cab = req.get('authorization') || '';
  const dada = cab.startsWith('Bearer ') ? cab.slice(7).trim() : (req.get('x-clave') || '');
  if (!config.metricasClave || dada !== config.metricasClave) {
    return res.status(401).json({ error: 'Clave inválida.' });
  }

  const uno = (sql, ...p) => bd.prepare(sql).get(...p)?.n ?? 0;
  const respaldo = estadoRespaldos();

  // Por día: los registros salen de cuándo nació cada cuenta; lo demás, del
  // contador por día. Treinta días es lo que dibuja Vigía.
  const dias = {};
  const mete = (dia, clave, valor) => { (dias[dia] = dias[dia] || { dia })[clave] = valor; };
  for (const f of bd.prepare(
    `SELECT substr(creado,1,10) dia, COUNT(*) n FROM usuarios
     WHERE creado >= date('now','-30 days') GROUP BY dia`).all()) mete(f.dia, 'registros', f.n);
  for (const f of bd.prepare(
    `SELECT dia, clave, veces FROM uso_dia WHERE dia >= date('now','-30 days')`).all()) {
    const nombre = { 'reporte.compra': 'reportes', 'reporte.cuadre': 'reportes',
                     'chinola.movimientos': 'chinola', 'ia.lista': 'ia',
                     'ia.recibo': 'ia', 'ia.recibo.texto': 'ia',
                     'sync.subida': 'sincronizaciones' }[f.clave];
    if (nombre) mete(f.dia, nombre, (dias[f.dia]?.[nombre] || 0) + f.veces);
  }

  const alertas = [];
  const horas = respaldo.ultimo ? (Date.now() - Date.parse(respaldo.ultimo)) / 3600e3 : Infinity;
  if (horas > 48) {
    alertas.push({ nivel: 'aviso', texto: respaldo.ultimo
      ? `El último respaldo es de hace ${Math.round(horas)} horas.`
      : 'Todavía no se ha hecho ningún respaldo.' });
  }
  if (!hayCorreo()) alertas.push({ nivel: 'aviso', texto: 'Sin proveedor de correo: nadie puede entrar con código.' });

  res.json({
    nombre: 'Cuadre',
    totales: {
      usuarios: uno('SELECT COUNT(*) n FROM usuarios'),
      activos7d: uno("SELECT COUNT(DISTINCT usuario_id) n FROM sesiones WHERE ultimo_uso >= datetime('now','-7 days')"),
      listas: uno('SELECT COUNT(*) n FROM listas WHERE borrado IS NULL'),
      articulos: uno('SELECT COUNT(*) n FROM articulos WHERE borrado IS NULL'),
      encargos: uno('SELECT COUNT(*) n FROM encargos WHERE borrado IS NULL'),
      catalogo: uno('SELECT COUNT(*) n FROM catalogo WHERE borrado IS NULL'),
      chinolaConectadas: uno('SELECT COUNT(*) n FROM chinola'),
      reportes: uno("SELECT COUNT(*) n FROM reportes WHERE clase != 'interno'"),
    },
    diario: Object.values(dias).sort((a, b) => a.dia.localeCompare(b.dia)),
    tarjetas: [
      { titulo: 'Versión', valor: config.version, estado: 'ok' },
      { titulo: 'Último respaldo', nota: `${respaldo.cuantos} guardados · ${Math.round(respaldo.bytes / 1024)} KB`,
        valor: respaldo.ultimo ? respaldo.ultimo.slice(0, 16).replace('T', ' ') : 'nunca',
        estado: horas > 48 ? 'aviso' : 'ok' },
      { titulo: 'IA', valor: hayIA() ? 'lista' : 'apagada', nota: 'solo modelos gratuitos',
        estado: hayIA() ? 'ok' : 'aviso' },
      { titulo: 'Correo', valor: hayCorreo() ? 'listo' : 'apagado', estado: hayCorreo() ? 'ok' : 'aviso' },
    ],
    alertas,
    detalles: {
      uso: Object.fromEntries(bd.prepare('SELECT clave, veces FROM uso ORDER BY veces DESC LIMIT 40')
        .all().map((f) => [f.clave, f.veces])),
    },
  });
});

app.post('/api/respaldo', (req, res) => {
  if (!config.metricasClave || req.get('x-clave') !== config.metricasClave) {
    return res.status(401).json({ error: 'Clave inválida.' });
  }
  try { res.json({ ok: true, archivo: respalda(), estado: estadoRespaldos() }); }
  catch (e) { res.status(500).json({ error: e.message }); }
});

/* ────────────────────────────── entrar ────────────────────────────── */

const responde = (res, r) => res.status(r.estado).json(r.cuerpo);

app.post('/api/auth/codigo', limite(6), async (req, res) => {
  responde(res, await pideCodigo(req.body?.correo ?? req.body?.email));
});

app.post('/api/auth/entrar', limite(12), (req, res) => {
  responde(res, entraConCodigo(req.body?.correo ?? req.body?.email, req.body?.codigo, req.body?.dispositivo));
});

app.post('/api/auth/apple', limite(12), async (req, res) => {
  responde(res, await entraConApple(req.body?.identityToken, req.body?.nombre, req.body?.dispositivo));
});

/* ────────────────────────────── la cuenta ────────────────────────────── */

const yo = express.Router();
yo.use(conSesion);

yo.get('/', (req, res) => {
  res.json({
    usuario: publico(req.usuario),
    chinola: chin.conexionDe(req.usuario.id),
    ia: hayIA(),
    version: config.version,
  });
});

yo.patch('/', (req, res) => {
  const nombre = String(req.body?.nombre ?? '').slice(0, 60).trim();
  if (nombre) bd.prepare('UPDATE usuarios SET nombre = ? WHERE id = ?').run(nombre, req.usuario.id);
  res.json({ usuario: publico(bd.prepare('SELECT * FROM usuarios WHERE id = ?').get(req.usuario.id)) });
});

yo.get('/sesiones', (req, res) => res.json({ sesiones: sesionesDe(req.usuario.id), actual: req.sesion.id }));

yo.post('/salir', (req, res) => { cierraSesion(req.sesion.id); res.json({ ok: true }); });
yo.post('/salir-todas', (req, res) => { cierraTodas(req.usuario.id); res.json({ ok: true }); });

// Borrar la cuenta de verdad, desde la app. Apple lo exige y además es lo
// correcto: quien se quiere ir no debería tener que escribir un correo.
yo.delete('/', async (req, res) => {
  try { await chin.desconecta(req.usuario.id); } catch { /* la conexión igual se va con la cuenta */ }
  borraCuenta(req.usuario.id);
  res.json({ ok: true });
});

app.use('/api/yo', yo);
app.use('/api/sync', sync);

/* ────────────────────────────── la IA ────────────────────────────── */

const ia = express.Router();
ia.use(conSesion);

ia.post('/lista', limite(20), async (req, res) => {
  try {
    const r = await listaDeTexto(req.body?.texto, { tienda: req.body?.tienda, conocidos: req.body?.conocidos });
    cuenta('ia.lista');
    res.json(r);
  } catch (e) { res.status(e.estado || 502).json({ error: e.message }); }
});

ia.post('/recibo-texto', limite(20), async (req, res) => {
  try {
    const r = await reciboDeTexto(req.body?.texto);
    cuenta('ia.recibo.texto');
    res.json(r);
  } catch (e) { res.status(e.estado || 502).json({ error: e.message }); }
});

ia.post('/recibo', limite(10), async (req, res) => {
  try {
    const r = await listaDeRecibo(req.body?.imagen, req.body?.tipo);
    cuenta('ia.recibo');
    res.json(r);
  } catch (e) { res.status(e.estado || 502).json({ error: e.message }); }
});

app.use('/api/ia', ia);

/* ────────────────────────────── Chinola ────────────────────────────── */

const chinola = express.Router();
chinola.use(conSesion);

chinola.get('/', (req, res) => res.json({ conexion: chin.conexionDe(req.usuario.id) }));

chinola.post('/conectar', limite(10), async (req, res) => {
  try {
    res.json(await chin.empiezaConexion(req.usuario.id, req.body?.vuelta));
  } catch (e) { res.status(e.estado || 502).json({ error: e.message }); }
});

chinola.get('/destinos', async (req, res) => {
  try { res.json(await chin.destinos(req.usuario.id)); }
  catch (e) { res.status(e.estado || 502).json({ error: e.message, sinConexion: !!e.sinConexion }); }
});

chinola.put('/destino', (req, res) => {
  res.json({ conexion: chin.fijaDestino(req.usuario.id, req.body || {}) });
});

chinola.post('/enviar', limite(30), async (req, res) => {
  const lineas = Array.isArray(req.body?.lineas) ? req.body.lineas : [];
  if (!lineas.length) return res.status(400).json({ error: 'No hay nada que anotar.' });
  try {
    res.json(await chin.anota(req.usuario.id, {
      lineas, fecha: req.body?.fecha, libreta: req.body?.libreta, medio: req.body?.medio, tipo: req.body?.tipo,
    }));
  } catch (e) { res.status(e.estado || 502).json({ error: e.message, sinConexion: !!e.sinConexion }); }
});

chinola.delete('/', async (req, res) => { await chin.desconecta(req.usuario.id); res.json({ ok: true }); });

app.use('/api/chinola', chinola);

/**
 * La vuelta del OAuth de Chinola. NO lleva sesión de Cuadre: quien llega aquí es
 * el navegador que Chinola redirigió, y lo único que lo ata a una persona es el
 * `state` que guardamos antes. Por eso el `state` es aleatorio y de un solo uso.
 *
 * Al final se redirige al esquema de la app (`cuadre://`), que es lo que cierra
 * la ventana de autenticación en el teléfono.
 */
app.get('/chinola/vuelta', async (req, res) => {
  const vueltaSegura = (destino, params) => {
    const u = new URL(destino);
    for (const [k, v] of Object.entries(params)) if (v != null) u.searchParams.set(k, String(v));
    res.redirect(u.toString());
  };
  if (req.query.error) {
    return vueltaSegura('cuadre://chinola', { ok: '0', error: String(req.query.error_description || req.query.error) });
  }
  try {
    const r = await chin.terminaConexion(req.query.code, req.query.state);
    return vueltaSegura(r.vuelta, { ok: '1' });
  } catch (e) {
    // Si ni el `state` vale, no hay a dónde volver con seguridad: se enseña.
    return res.status(e.estado || 400).type('html').send(
      `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
       <body style="font:16px/1.5 -apple-system,sans-serif;background:#f5ead8;color:#201e1d;padding:40px 24px">
       <h1 style="font-size:26px">No pude conectar Chinola</h1><p>${String(e.message).replace(/</g, '&lt;')}</p>
       <p style="color:#645c50">Cierra esta ventana y prueba otra vez desde Ajustes.</p></body>`);
  }
});

/* ────────────────────────────── reportes ────────────────────────────── */

app.post('/api/reportes', conSesion, limite(30), (req, res) => {
  const clase = req.body?.clase === 'cuadre' ? 'cuadre' : 'compra';
  const datos = req.body?.datos;
  if (!datos || typeof datos !== 'object') return res.status(400).json({ error: 'Falta el reporte.' });
  cuenta('reporte.' + clase);
  res.status(201).json(guardaReporte(req.usuario.id, clase, datos));
});

/**
 * El enlace público. No lleva sesión a propósito: se comparte con la contadora o
 * con quien mandó a comprar, y esa persona no tiene la app. El id es aleatorio
 * de 96 bits, que es lo único que lo protege, y por eso la página va con
 * `noindex` y el enlace caduca.
 */
app.get('/r/:id', async (req, res) => {
  const pide = String(req.params.id || '');
  const esPdf = pide.endsWith('.pdf');
  const r = leeReporte(esPdf ? pide.slice(0, -4) : pide);
  if (!r) return res.status(404).type('html').send('<!doctype html><meta charset="utf-8"><body style="font:16px -apple-system,sans-serif;padding:40px"><h1>Ese reporte ya no está</h1><p>Los enlaces de Cuadre caducan a los seis meses.</p>');

  if (!esPdf) { res.set('cache-control', 'no-store'); return res.type('html').send(paginaReporte(r)); }
  const buf = await pdf(r.clase, r.datos);
  res.set({
    'content-type': 'application/pdf',
    'content-length': String(buf.length),
    'content-disposition': `inline; filename="cuadre-${r.clase}-${r.creado.slice(0, 10)}.pdf"`,
    'cache-control': 'private, max-age=600',
  });
  res.end(buf);
});

/* ────────────────────────────── el sitio ────────────────────────────── */

if (config.sitioDir && existsSync(config.sitioDir)) {
  const raiz = config.sitioDir;
  // La portada y las páginas legales cambian a mano y se leen una vez: no se
  // cachean en el borde más que un rato, porque una política vieja en caché es
  // exactamente el archivo que no debe quedarse pegado.
  app.use('/fuentes', express.static(join(raiz, 'fuentes'), { maxAge: '1y', immutable: true }));
  app.use(express.static(raiz, { index: 'index.html', maxAge: '10m', extensions: ['html'] }));
  app.get('/', (req, res) => res.sendFile(join(raiz, 'index.html')));
}

app.use('/api', (req, res) => res.status(404).json({ error: 'Ruta desconocida.' }));

// Último recurso: un error que nadie atrapó no se contesta con la pila de
// llamadas, que dice dónde vive el código y qué versión corre.
app.use((err, req, res, next) => {
  console.error('[error]', req.method, req.path, err?.message);
  if (res.headersSent) return next(err);
  const json = req.path.startsWith('/api');
  res.status(err?.estado || 500)[json ? 'json' : 'send'](json ? { error: 'Algo se rompió de este lado.' } : 'Algo se rompió de este lado.');
});

barre();
setInterval(barre, 6 * 3600_000).unref();
arrancaRespaldos();


app.listen(config.puerto, () => {
  console.log(`[cuadre] ${config.version} en :${config.puerto} · sitio ${config.sitio} · ia ${hayIA() ? 'sí' : 'no'} · correo ${hayCorreo() ? 'sí' : 'no'}`);
});
