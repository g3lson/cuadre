// EL LOGO DE UN NEGOCIO.
//
// Lo que se comprueba es lo que se rompería sin que nadie lo notara: que el
// logo del negocio de Ana no lo pueda cambiar cualquiera, que un archivo que
// no es una imagen no entre aunque venga con cabecera de imagen, y que la
// misma imagen subida dos veces no ocupe dos veces.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const PUERTO = 4400 + Math.floor(Math.random() * 400);
const BASE = `http://127.0.0.1:${PUERTO}`;

let servidor, carpeta, salida = '';
const gente = {};

const pide = async (camino, { token, ...opciones } = {}) => {
  const r = await fetch(BASE + camino, {
    ...opciones,
    headers: {
      ...(opciones.body instanceof Uint8Array ? {} : { 'content-type': 'application/json' }),
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
  assert.ok(codigo, `no salió el código de ${correo}`);
  const r = await pide('/api/auth/entrar', {
    method: 'POST', body: JSON.stringify({ correo, codigo, dispositivo: nombre }),
  });
  gente[nombre] = { correo, token: r.cuerpo.token };
}

/** Un PNG de un píxel, de verdad: con su firma y todo. */
const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  'base64');

before(async () => {
  carpeta = mkdtempSync(join(tmpdir(), 'cuadre-neg-'));
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
  await entra('ana', 'ana@negocio.do');
  await entra('beto', 'beto@negocio.do');

  await pide('/api/sync', {
    method: 'POST', token: gente.ana.token,
    body: JSON.stringify({ desde: '', cambios: {
      grupos: [{ id: 'G1', actualizado: new Date().toISOString(),
                 datos: { nombre: 'Pescadería El Muelle', color: 1 } }],
    } }),
  });
});

after(() => {
  servidor?.kill();
  if (carpeta) rmSync(carpeta, { recursive: true, force: true });
});

test('Ana le pone logo a su negocio y se puede bajar', async () => {
  const r = await pide('/api/grupos/G1/imagen', {
    method: 'PUT', token: gente.ana.token, body: PNG,
    headers: { 'content-type': 'image/png' },
  });
  assert.equal(r.estado, 200, r.texto);
  assert.match(r.cuerpo.url, /\/img\/[0-9a-f]{32}\.png$/);

  const baja = await fetch(r.cuerpo.url);
  assert.equal(baja.status, 200);
  assert.equal(baja.headers.get('content-type'), 'image/png');
  assert.equal((await baja.arrayBuffer()).byteLength, PNG.length);
});

test('la misma imagen dos veces no ocupa dos veces', async () => {
  const uno = await pide('/api/grupos/G1/imagen', {
    method: 'PUT', token: gente.ana.token, body: PNG, headers: { 'content-type': 'image/png' },
  });
  const dos = await pide('/api/grupos/G1/imagen', {
    method: 'PUT', token: gente.ana.token, body: PNG, headers: { 'content-type': 'image/png' },
  });
  assert.equal(uno.cuerpo.url, dos.cuerpo.url, 'el nombre es el hash: tiene que repetirse');
  const archivos = readdirSync(join(carpeta, 'imagenes'));
  assert.equal(archivos.length, 1, `debería haber uno solo, hay ${archivos.length}`);
});

test('Beto no puede cambiarle el logo al negocio de Ana', async () => {
  const r = await pide('/api/grupos/G1/imagen', {
    method: 'PUT', token: gente.beto.token, body: PNG, headers: { 'content-type': 'image/png' },
  });
  assert.equal(r.estado, 403, r.texto);
});

test('un archivo que no es imagen no entra aunque lo diga la cabecera', async () => {
  const r = await pide('/api/grupos/G1/imagen', {
    method: 'PUT', token: gente.ana.token,
    body: Buffer.from('<?php system($_GET["c"]); ?>          '),
    headers: { 'content-type': 'image/png' },
  });
  assert.equal(r.estado, 400, r.texto);
});

test('sin sesión no se sube nada', async () => {
  const r = await pide('/api/grupos/G1/imagen', {
    method: 'PUT', body: PNG, headers: { 'content-type': 'image/png' },
  });
  assert.equal(r.estado, 401, r.texto);
});
