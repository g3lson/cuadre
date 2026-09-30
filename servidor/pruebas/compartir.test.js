// UNA LISTA A DOS MANOS.
//
// El caso de verdad: una pareja entra al súper y se separa. Lo que se comprueba
// aquí es exactamente lo que se rompería sin darse cuenta —que uno vea lo del
// otro, que no vea lo que no es suyo, y que el aviso llegue en el momento— y no
// que las funciones devuelvan lo que devuelven.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const PUERTO = 3900 + Math.floor(Math.random() * 400);
const BASE = `http://127.0.0.1:${PUERTO}`;

let servidor, carpeta, salida = '';
const gente = {};   // nombre → { correo, token }

const pide = async (camino, { token, ...opciones } = {}) => {
  const r = await fetch(BASE + camino, {
    ...opciones,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: 'Bearer ' + token } : {}),
      ...(opciones.headers || {}),
    },
  });
  const texto = await r.text();
  let cuerpo = null;
  try { cuerpo = texto ? JSON.parse(texto) : null; } catch { cuerpo = texto; }
  return { estado: r.status, cuerpo, texto };
};

async function entra(nombre, correo) {
  await pide('/api/auth/codigo', { method: 'POST', body: JSON.stringify({ correo }) });
  const codigo = (salida.match(new RegExp(`código para ${correo} → (\\d{6})`)) || [])[1];
  assert.ok(codigo, `no salió el código de ${correo}:\n${salida.slice(-500)}`);
  const r = await pide('/api/auth/entrar', {
    method: 'POST', body: JSON.stringify({ correo, codigo, dispositivo: nombre }),
  });
  assert.equal(r.estado, 200, r.texto);
  gente[nombre] = { correo, token: r.cuerpo.token, id: r.cuerpo.usuario.id };
}

/** Subir un lote y devolver lo que baja. */
const sube = (quien, cambios, desde = '') =>
  pide('/api/sync', { method: 'POST', token: gente[quien].token, body: JSON.stringify({ desde, cambios }) });

const articulo = (id, listaId, nombre, extra = {}) => ({
  id, actualizado: new Date().toISOString(),
  datos: { listaId, nombre, unidad: 'ud', cantidad: 1, precio: 100, hecho: false, ...extra },
});

before(async () => {
  carpeta = mkdtempSync(join(tmpdir(), 'cuadre-comp-'));
  servidor = spawn(process.execPath, ['src/index.js'], {
    cwd: new URL('..', import.meta.url).pathname,
    env: { ...process.env, PORT: String(PUERTO), CUADRE_BD: join(carpeta, 'p.db'),
           CUADRE_SITIO: BASE, CUADRE_SITIO_DIR: '' },
  });
  servidor.stdout.on('data', (d) => { salida += d; });
  servidor.stderr.on('data', (d) => { salida += d; });
  for (let i = 0; i < 60; i++) {
    try { if ((await fetch(BASE + '/api/salud')).ok) break; } catch { /* todavía no */ }
    await new Promise((s) => setTimeout(s, 200));
  }
  await entra('ana', 'ana@ejemplo.do');
  await entra('beto', 'beto@ejemplo.do');
});

after(() => {
  servidor?.kill();
  if (carpeta) rmSync(carpeta, { recursive: true, force: true });
});

test('Ana crea la lista y Beto no la ve', async () => {
  const r = await sube('ana', {
    listas: [{ id: 'L1', actualizado: new Date().toISOString(),
               datos: { nombre: 'Supermercado', tienda: 'Bravo', presupuesto: 5000 } }],
    articulos: [articulo('A1', 'L1', 'Leche'), articulo('A2', 'L1', 'Pan')],
  });
  assert.equal(r.cuerpo.aplicados, 3);

  const suyo = await pide('/api/sync?desde=', { token: gente.beto.token });
  assert.equal(suyo.cuerpo.cambios.listas.length, 0, 'Beto no debería ver la lista de Ana');
  assert.equal(suyo.cuerpo.cambios.articulos.length, 0);
});

test('Beto no puede escribir en una lista que no es suya', async () => {
  const r = await sube('beto', { articulos: [articulo('A1', 'L1', 'Leche', { hecho: true })] });
  assert.equal(r.cuerpo.aplicados, 0);
  assert.equal(r.cuerpo.descartados, 1);
});

test('Ana comparte y entonces Beto la ve entera', async () => {
  const r = await pide('/api/listas/L1/miembros', {
    method: 'POST', token: gente.ana.token, body: JSON.stringify({ correo: 'beto@ejemplo.do' }),
  });
  assert.equal(r.estado, 200, r.texto);
  assert.ok(r.cuerpo.miembros.some((m) => m.email === 'beto@ejemplo.do' && m.dentro));

  const suyo = await pide('/api/sync?desde=', { token: gente.beto.token });
  assert.equal(suyo.cuerpo.cambios.listas.length, 1);
  assert.equal(suyo.cuerpo.cambios.listas[0].datos.nombre, 'Supermercado');
  assert.equal(suyo.cuerpo.cambios.articulos.length, 2, 'tienen que bajar los dos productos');
});

test('Beto marca la leche y Ana lo ve', async () => {
  const r = await sube('beto', { articulos: [articulo('A1', 'L1', 'Leche', { hecho: true })] });
  assert.equal(r.cuerpo.aplicados, 1, r.texto);

  const deAna = await pide('/api/sync?desde=', { token: gente.ana.token });
  const leche = deAna.cuerpo.cambios.articulos.find((a) => a.id === 'A1');
  assert.equal(leche.datos.hecho, true, 'Ana tiene que ver que Beto ya la cogió');
  // Y la fila sigue siendo de Ana: marcarla no cambia de dueño.
  assert.equal(leche.de, gente.ana.id);
});

test('lo que Beto añade a la lista compartida, Ana lo ve', async () => {
  await sube('beto', { articulos: [articulo('A3', 'L1', 'Café')] });
  const deAna = await pide('/api/sync?desde=', { token: gente.ana.token });
  const cafe = deAna.cuerpo.cambios.articulos.find((a) => a.id === 'A3');
  assert.ok(cafe, 'el producto de Beto tiene que llegarle a Ana');
  assert.equal(cafe.de, gente.beto.id, 'y saberse que lo puso Beto');
});

test('el aviso en vivo llega al otro teléfono', async () => {
  const ctrl = new AbortController();
  const r = await fetch(BASE + '/api/eventos', {
    headers: { authorization: 'Bearer ' + gente.ana.token },
    signal: ctrl.signal,
  });
  assert.equal(r.status, 200);
  assert.match(r.headers.get('content-type') || '', /event-stream/);

  const lector = r.body.getReader();
  const decodificador = new TextDecoder();
  // El saludo inicial, para saber que la conexión está de verdad abierta.
  await lector.read();

  // Beto toca la lista mientras Ana escucha.
  const escribe = sube('beto', { articulos: [articulo('A4', 'L1', 'Azúcar')] });

  const aviso = await Promise.race([
    (async () => {
      let texto = '';
      while (!texto.includes('event: cambio')) {
        const { value, done } = await lector.read();
        if (done) break;
        texto += decodificador.decode(value, { stream: true });
      }
      return texto;
    })(),
    new Promise((s) => setTimeout(() => s(''), 8000)),
  ]);
  await escribe;
  ctrl.abort();

  assert.match(aviso, /event: cambio/, 'Ana tenía que enterarse sin preguntar');
  assert.match(aviso, /"L1"/, 'y de QUÉ lista cambió');
});

test('el enlace de invitación entra a un tercero', async () => {
  await entra('carmen', 'carmen@ejemplo.do');
  const enlace = await pide('/api/listas/L1/enlace', { method: 'POST', token: gente.ana.token, body: '{}' });
  assert.equal(enlace.estado, 200, enlace.texto);
  assert.match(enlace.cuerpo.url, /\/invitacion\//);

  const acepta = await pide('/api/listas/invitacion/' + enlace.cuerpo.codigo,
    { method: 'POST', token: gente.carmen.token });
  assert.equal(acepta.estado, 200, acepta.texto);
  assert.equal(acepta.cuerpo.listaId, 'L1');

  const suyo = await pide('/api/sync?desde=', { token: gente.carmen.token });
  assert.equal(suyo.cuerpo.cambios.listas.length, 1);

  const malo = await pide('/api/listas/invitacion/noexiste', { method: 'POST', token: gente.carmen.token });
  assert.equal(malo.estado, 404);
});

test('solo quien creó la lista invita', async () => {
  const r = await pide('/api/listas/L1/miembros', {
    method: 'POST', token: gente.beto.token, body: JSON.stringify({ correo: 'otro@ejemplo.do' }),
  });
  assert.equal(r.estado, 403);
});

test('se puede invitar a quien todavía no tiene cuenta, y le llega al entrar', async () => {
  const r = await pide('/api/listas/L1/miembros', {
    method: 'POST', token: gente.ana.token, body: JSON.stringify({ correo: 'nuevo@ejemplo.do' }),
  });
  assert.equal(r.estado, 200);
  assert.ok(r.cuerpo.miembros.some((m) => m.email === 'nuevo@ejemplo.do' && !m.dentro));

  await entra('nuevo', 'nuevo@ejemplo.do');
  const suyo = await pide('/api/sync?desde=', { token: gente.nuevo.token });
  assert.equal(suyo.cuerpo.cambios.listas.length, 1, 'la invitación tenía que atarse sola al entrar');
});

test('cualquiera puede salirse, y deja de verla', async () => {
  const r = await pide('/api/listas/L1/miembros/' + encodeURIComponent('beto@ejemplo.do'),
    { method: 'DELETE', token: gente.beto.token });
  assert.equal(r.estado, 200);

  const suyo = await pide('/api/sync?desde=', { token: gente.beto.token });
  assert.equal(suyo.cuerpo.cambios.listas.length, 0);
  // Y ya no puede escribir.
  const intento = await sube('beto', { articulos: [articulo('A5', 'L1', 'Sal')] });
  assert.equal(intento.cuerpo.aplicados, 0);
});
