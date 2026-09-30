// EL RECORRIDO ENTERO, DE UNA VEZ.
//
// No son pruebas de cada función por separado sino una sola que hace lo que
// hace una persona: pedir el código, entrar, subir una lista, cerrarla, y sacar
// el reporte. Es la prueba que de verdad falla cuando algo se rompe, porque es
// el camino que existe.
//
// El servidor arranca de verdad, en un puerto suelto y contra una base
// desechable: probar contra un servidor de mentira solo demuestra que el
// servidor de mentira funciona.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const PUERTO = 3400 + Math.floor(Math.random() * 500);
const BASE = `http://127.0.0.1:${PUERTO}`;
const CORREO = 'prueba@fente.com.do';

let servidor;
let carpeta;
let salida = '';
let testigo = '';

const pide = async (camino, opciones = {}) => {
  const r = await fetch(BASE + camino, {
    ...opciones,
    headers: {
      'content-type': 'application/json',
      ...(testigo ? { authorization: 'Bearer ' + testigo } : {}),
      ...(opciones.headers || {}),
    },
  });
  const texto = await r.text();
  let cuerpo = null;
  try { cuerpo = texto ? JSON.parse(texto) : null; } catch { cuerpo = texto; }
  return { estado: r.status, cuerpo, texto };
};

before(async () => {
  carpeta = mkdtempSync(join(tmpdir(), 'cuadre-'));
  servidor = spawn(process.execPath, ['src/index.js'], {
    cwd: new URL('..', import.meta.url).pathname,
    env: {
      ...process.env,
      PORT: String(PUERTO),
      CUADRE_BD: join(carpeta, 'prueba.db'),
      CUADRE_SITIO: BASE,          // «localhost» hace que el código salga por el registro
      CUADRE_SITIO_DIR: '',
      CUADRE_METRICAS_CLAVE: 'clave-de-prueba',
      CUADRE_IA_CLAVE: '',         // sin IA: se comprueba que lo diga en vez de romperse
    },
  });
  servidor.stdout.on('data', (d) => { salida += d; });
  servidor.stderr.on('data', (d) => { salida += d; });

  for (let i = 0; i < 60; i++) {
    try {
      const r = await fetch(BASE + '/api/salud');
      if (r.ok) return;
    } catch { /* todavía no */ }
    await new Promise((s) => setTimeout(s, 200));
  }
  throw new Error('El servidor no arrancó:\n' + salida);
});

after(() => {
  servidor?.kill();
  if (carpeta) rmSync(carpeta, { recursive: true, force: true });
});

test('la salud contesta', async () => {
  const r = await pide('/api/salud');
  assert.equal(r.estado, 200);
  assert.equal(r.cuerpo.ok, true);
});

test('sin sesión no se ve nada', async () => {
  const r = await pide('/api/yo');
  assert.equal(r.estado, 401);
  assert.equal(r.cuerpo.sesion, false);
});

test('un correo con mala forma se rechaza', async () => {
  const r = await pide('/api/auth/codigo', { method: 'POST', body: JSON.stringify({ correo: 'no-es-un-correo' }) });
  assert.equal(r.estado, 400);
});

test('entrar con el código crea la cuenta y deja los ajustes puestos', async () => {
  const p = await pide('/api/auth/codigo', { method: 'POST', body: JSON.stringify({ correo: CORREO }) });
  assert.equal(p.estado, 200);

  const codigo = (salida.match(/→ (\d{6})/g) || []).pop()?.slice(2);
  assert.ok(codigo, 'el código tenía que salir por el registro en local:\n' + salida);

  const malo = await pide('/api/auth/entrar', { method: 'POST', body: JSON.stringify({ correo: CORREO, codigo: '000000' }) });
  assert.equal(malo.estado, 400);

  const r = await pide('/api/auth/entrar', {
    method: 'POST',
    body: JSON.stringify({ correo: CORREO, codigo, dispositivo: 'iPhone de prueba' }),
  });
  assert.equal(r.estado, 200, r.texto);
  assert.ok(r.cuerpo.token.startsWith('cua_'));
  testigo = r.cuerpo.token;

  const yo = await pide('/api/yo');
  assert.equal(yo.estado, 200);
  assert.equal(yo.cuerpo.usuario.email, CORREO);
  assert.equal(yo.cuerpo.chinola, null);
});

test('un código usado no vale dos veces', async () => {
  const codigo = (salida.match(/→ (\d{6})/g) || []).pop()?.slice(2);
  const r = await pide('/api/auth/entrar', { method: 'POST', body: JSON.stringify({ correo: CORREO, codigo }) });
  assert.equal(r.estado, 400);
});

test('subir una lista, bajarla y que el precio quede recordado', async () => {
  const subida = await pide('/api/sync', {
    method: 'POST',
    body: JSON.stringify({
      desde: '',
      cambios: {
        listas: [{ id: 'L1', actualizado: '2026-09-30T11:00:00.000Z',
                   datos: { nombre: 'Supermercado Semanal', tienda: 'Bravo', presupuesto: 6500 } }],
        articulos: [
          { id: 'A1', actualizado: '2026-09-30T11:00:01.000Z',
            datos: { listaId: 'L1', nombre: 'Leche entera', unidad: 'gal', cantidad: 2, precio: 245, hecho: true, tienda: 'Bravo' } },
          { id: 'A2', actualizado: '2026-09-30T11:00:02.000Z',
            datos: { listaId: 'L1', nombre: 'Azúcar crema', unidad: 'lb', cantidad: 5, precio: 38, hecho: false } },
        ],
      },
    }),
  });
  assert.equal(subida.estado, 200, subida.texto);
  assert.equal(subida.cuerpo.aplicados, 3);   // dos artículos y la lista
  assert.equal(subida.cuerpo.cambios.listas.length, 1);
  // Los ajustes nacen con la cuenta, así que también bajan.
  assert.equal(subida.cuerpo.cambios.ajustes.length, 1);

  const precios = await pide('/api/sync/precios');
  assert.equal(precios.estado, 200);
  // Solo lo que se compró de verdad: el azúcar no estaba marcado.
  assert.equal(precios.cuerpo.precios.length, 1);
  assert.equal(precios.cuerpo.precios[0].precio, 245);
});

test('gana el cambio más reciente y el viejo se descarta', async () => {
  const viejo = await pide('/api/sync', {
    method: 'POST',
    body: JSON.stringify({
      desde: '2026-09-30T12:00:00.000Z',
      cambios: { listas: [{ id: 'L1', actualizado: '2026-09-29T10:00:00.000Z', datos: { nombre: 'Viejo' } }] },
    }),
  });
  assert.equal(viejo.cuerpo.aplicados, 0);
  assert.equal(viejo.cuerpo.descartados, 1);

  const nuevo = await pide('/api/sync', {
    method: 'POST',
    body: JSON.stringify({
      desde: '2026-09-30T12:00:00.000Z',
      cambios: { listas: [{ id: 'L1', actualizado: '2026-10-01T10:00:00.000Z', datos: { nombre: 'Nuevo' } }] },
    }),
  });
  assert.equal(nuevo.cuerpo.aplicados, 1);

  const todo = await pide('/api/sync?desde=');
  assert.equal(todo.cuerpo.cambios.listas[0].datos.nombre, 'Nuevo');
});

test('una fila con id ajeno no se puede pisar', async () => {
  // Se crea otra cuenta y se intenta escribir en la lista de la primera.
  await pide('/api/auth/codigo', { method: 'POST', body: JSON.stringify({ correo: 'otro@fente.com.do' }) });
  const codigo = (salida.match(/→ (\d{6})/g) || []).pop()?.slice(2);
  const entrada = await pide('/api/auth/entrar', {
    method: 'POST', body: JSON.stringify({ correo: 'otro@fente.com.do', codigo }),
  });
  const mio = testigo;
  testigo = entrada.cuerpo.token;

  const intento = await pide('/api/sync', {
    method: 'POST',
    body: JSON.stringify({
      desde: '',
      cambios: { listas: [{ id: 'L1', actualizado: '2026-12-01T10:00:00.000Z', datos: { nombre: 'Robada' } }] },
    }),
  });
  assert.equal(intento.cuerpo.aplicados, 0);
  assert.equal(intento.cuerpo.descartados, 1);
  assert.equal(intento.cuerpo.cambios.listas.length, 0);

  testigo = mio;
  const comprobar = await pide('/api/sync?desde=');
  assert.equal(comprobar.cuerpo.cambios.listas[0].datos.nombre, 'Nuevo');
});

let reporteId = '';

test('el reporte se guarda, se ve en web y sale en PDF', async () => {
  const r = await pide('/api/reportes', {
    method: 'POST',
    body: JSON.stringify({
      clase: 'compra',
      datos: {
        titulo: 'Supermercado Semanal', tienda: 'Supermercado Bravo', fecha: '2026-09-30',
        presupuesto: 6500, pagado: 490,
        productos: [{ nombre: 'Leche entera', nota: 'Rica, la azul', unidad: 'gal', cantidad: 2, precio: 245 }],
        faltantes: [{ nombre: 'Azúcar crema', cantidad: 5, unidad: 'lb', destino: 'pasó a la próxima compra' }],
      },
    }),
  });
  assert.equal(r.estado, 201, r.texto);
  reporteId = r.cuerpo.id;

  const web = await fetch(`${BASE}/r/${reporteId}`);
  assert.equal(web.status, 200);
  const html = await web.text();
  assert.match(html, /Supermercado Semanal/);
  assert.match(html, /noindex/);

  const pdf = await fetch(`${BASE}/r/${reporteId}.pdf`);
  assert.equal(pdf.status, 200);
  assert.equal(pdf.headers.get('content-type'), 'application/pdf');
  const bytes = Buffer.from(await pdf.arrayBuffer());
  assert.ok(bytes.length > 2000, 'el PDF salió sospechosamente pequeño');
  assert.equal(bytes.subarray(0, 4).toString(), '%PDF');
});

test('un reporte que no existe da 404 y no filtra nada', async () => {
  const r = await fetch(`${BASE}/r/noexiste`);
  assert.equal(r.status, 404);
});

test('sin Chinola conectada, enviar avisa en vez de romperse', async () => {
  const r = await pide('/api/chinola/enviar', {
    method: 'POST',
    body: JSON.stringify({ lineas: [{ concepto: 'Compra', monto: 100 }] }),
  });
  assert.equal(r.estado, 409);
  assert.equal(r.cuerpo.sinConexion, true);
});

test('sin IA configurada, las rutas de IA lo dicen y no se rompen', async () => {
  for (const [camino, cuerpo] of [
    ['/api/ia/lista', { texto: 'dos galones de leche' }],
    ['/api/ia/recibo-texto', { texto: '2.00 LECHE RICA GL 490.00' }],
  ]) {
    const r = await pide(camino, { method: 'POST', body: JSON.stringify(cuerpo) });
    assert.equal(r.estado, 503, camino);
    assert.match(r.cuerpo.error, /no está configurada/i);
  }
});

test('el recibo sin texto se rechaza antes de llamar a nadie', async () => {
  const r = await pide('/api/ia/recibo-texto', { method: 'POST', body: JSON.stringify({ texto: '   ' }) });
  assert.equal(r.estado, 400);
});

test('el respaldo se hace y solo con la clave', async () => {
  const sinClave = await pide('/api/respaldo', { method: 'POST' });
  assert.equal(sinClave.estado, 401);

  const r = await pide('/api/respaldo', { method: 'POST', headers: { 'x-clave': 'clave-de-prueba' } });
  assert.equal(r.estado, 200, r.texto);
  assert.ok(r.cuerpo.archivo.endsWith('.db'));
  assert.equal(r.cuerpo.estado.cuantos, 1);
  // Una copia de una base con datos no puede pesar cuatro bytes.
  assert.ok(r.cuerpo.estado.bytes > 4096, 'el respaldo salió sospechosamente pequeño');

  // Y la copia se puede abrir y tiene lo que había.
  const { default: Database } = await import('better-sqlite3');
  const copia = new Database(r.cuerpo.archivo, { readonly: true });
  assert.ok(copia.prepare('SELECT COUNT(*) n FROM listas').get().n >= 1);
  copia.close();
});

test('borrar la cuenta se lleva todo lo suyo', async () => {
  const r = await pide('/api/yo', { method: 'DELETE' });
  assert.equal(r.estado, 200);

  const despues = await pide('/api/yo');
  assert.equal(despues.estado, 401);

  // Y el reporte compartido se va con ella.
  const web = await fetch(`${BASE}/r/${reporteId}`);
  assert.equal(web.status, 404);
});
