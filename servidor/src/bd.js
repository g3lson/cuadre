// LA BASE.
//
// SQLite en un archivo, en modo WAL. Es una app de una persona con sus listas y
// sus ventas: cabe de sobra, se respalda copiando un archivo y no hay un
// servicio más que se pueda caer.
//
// Todo lo que se sincroniza vive en tablas con la misma forma —`id`,
// `usuario_id`, `actualizado`, `borrado`— porque así el sincronizador es UNO y
// no siete: añadir una entidad nueva es añadirla a `TABLAS` y ya.
import Database from 'better-sqlite3';
import { randomBytes, createHash } from 'node:crypto';
import { dirname } from 'node:path';
import { mkdirSync } from 'node:fs';
import { config } from './config.js';

mkdirSync(dirname(config.bd), { recursive: true });
export const bd = new Database(config.bd);
bd.pragma('journal_mode = WAL');
bd.pragma('foreign_keys = ON');
bd.pragma('busy_timeout = 5000');

/** Marca de tiempo con milisegundos: sin ellos, dos cambios del mismo segundo empatan y el que gana es el azar. */
export const ahora = () => new Date().toISOString();
export const uid = () => randomBytes(12).toString('base64url');
export const resumen = (v) => createHash('sha256').update(String(v)).digest('hex');

bd.exec(`
CREATE TABLE IF NOT EXISTS usuarios (
  id        TEXT PRIMARY KEY,
  email     TEXT UNIQUE,
  nombre    TEXT NOT NULL DEFAULT '',
  apple_sub TEXT UNIQUE,
  estado    TEXT NOT NULL DEFAULT 'activo',
  creado    TEXT NOT NULL,
  visto     TEXT
);

CREATE TABLE IF NOT EXISTS sesiones (
  id         TEXT PRIMARY KEY,
  token      TEXT NOT NULL UNIQUE,   -- resumen, nunca el token en claro
  usuario_id TEXT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  dispositivo TEXT NOT NULL DEFAULT '',
  creado     TEXT NOT NULL,
  ultimo_uso TEXT,
  expira     TEXT NOT NULL,
  revocada   TEXT
);
CREATE INDEX IF NOT EXISTS idx_sesiones_usuario ON sesiones (usuario_id);

-- Los códigos de seis dígitos para entrar por correo.
CREATE TABLE IF NOT EXISTS codigos (
  email    TEXT PRIMARY KEY,
  codigo   TEXT NOT NULL,            -- resumen
  expira   TEXT NOT NULL,
  intentos INTEGER NOT NULL DEFAULT 0,
  creado   TEXT NOT NULL
);

-- ─────────────────────────── lo que se sincroniza ───────────────────────────
-- \`datos\` es un JSON con los campos propios de cada entidad. Se guarda entero
-- porque el servidor no necesita entenderlos para sincronizarlos, y así un
-- campo nuevo en la app no obliga a migrar la base ni a desplegar el servidor.
-- Lo que sí es columna es lo que el servidor usa: a quién pertenece, cuándo
-- cambió y si murió.
CREATE TABLE IF NOT EXISTS listas (
  id TEXT PRIMARY KEY, usuario_id TEXT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  datos TEXT NOT NULL, actualizado TEXT NOT NULL, borrado TEXT);
CREATE TABLE IF NOT EXISTS articulos (
  id TEXT PRIMARY KEY, usuario_id TEXT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  datos TEXT NOT NULL, actualizado TEXT NOT NULL, borrado TEXT);
CREATE TABLE IF NOT EXISTS eventos (
  id TEXT PRIMARY KEY, usuario_id TEXT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  datos TEXT NOT NULL, actualizado TEXT NOT NULL, borrado TEXT);
CREATE TABLE IF NOT EXISTS encargos (
  id TEXT PRIMARY KEY, usuario_id TEXT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  datos TEXT NOT NULL, actualizado TEXT NOT NULL, borrado TEXT);
CREATE TABLE IF NOT EXISTS catalogo (
  id TEXT PRIMARY KEY, usuario_id TEXT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  datos TEXT NOT NULL, actualizado TEXT NOT NULL, borrado TEXT);
CREATE TABLE IF NOT EXISTS clientes (
  id TEXT PRIMARY KEY, usuario_id TEXT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  datos TEXT NOT NULL, actualizado TEXT NOT NULL, borrado TEXT);
CREATE TABLE IF NOT EXISTS tiendas (
  id TEXT PRIMARY KEY, usuario_id TEXT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  datos TEXT NOT NULL, actualizado TEXT NOT NULL, borrado TEXT);

-- Los ajustes son uno por persona, así que el id ES el usuario.
CREATE TABLE IF NOT EXISTS ajustes (
  id TEXT PRIMARY KEY, usuario_id TEXT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  datos TEXT NOT NULL, actualizado TEXT NOT NULL, borrado TEXT);

-- Precios vistos: lo que hace que la próxima lista venga con los precios de la
-- anterior sin que nadie los escriba dos veces.
CREATE TABLE IF NOT EXISTS precios (
  usuario_id TEXT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  llano      TEXT NOT NULL,          -- el nombre sin tildes ni mayúsculas
  tienda     TEXT NOT NULL DEFAULT '',
  unidad     TEXT NOT NULL DEFAULT '',
  precio     REAL NOT NULL,
  fecha      TEXT NOT NULL,
  PRIMARY KEY (usuario_id, llano, tienda));

-- La cuenta de Chinola conectada. El token vive AQUÍ y no en el teléfono: así
-- se refresca solo mientras la app duerme, y desconectar es borrar una fila.
CREATE TABLE IF NOT EXISTS chinola (
  usuario_id TEXT PRIMARY KEY REFERENCES usuarios(id) ON DELETE CASCADE,
  token      TEXT NOT NULL,
  refresco   TEXT NOT NULL,
  expira     TEXT NOT NULL,
  permisos   TEXT NOT NULL DEFAULT '',
  libreta    TEXT NOT NULL DEFAULT '',
  medio      TEXT NOT NULL DEFAULT '',
  cuenta     TEXT NOT NULL DEFAULT '',
  creado     TEXT NOT NULL,
  ultimo_uso TEXT);

-- El paso intermedio del OAuth: el verificador de PKCE mientras la persona está
-- en la pantalla de Chinola diciendo que sí.
CREATE TABLE IF NOT EXISTS chinola_espera (
  estado      TEXT PRIMARY KEY,
  usuario_id  TEXT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  verificador TEXT NOT NULL,
  vuelta      TEXT NOT NULL DEFAULT '',
  expira      TEXT NOT NULL);

-- Reportes compartidos por enlace. Se guarda el JSON, no el PDF: pesa nada y
-- se puede volver a dibujar mejor mañana.
CREATE TABLE IF NOT EXISTS reportes (
  id         TEXT PRIMARY KEY,
  usuario_id TEXT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  clase      TEXT NOT NULL,
  datos      TEXT NOT NULL,
  creado     TEXT NOT NULL,
  expira     TEXT);

-- Lo que el servidor necesita recordar de sí mismo: hoy, el client_id con el
-- que Cuadre está dado de alta en Chinola. Una tabla por cada cosa así sería
-- una tabla nueva por fila.
CREATE TABLE IF NOT EXISTS ajustes_servidor (
  clave TEXT PRIMARY KEY, valor TEXT NOT NULL, actualizado TEXT NOT NULL);

-- Para saber por dónde entra la gente y qué se usa, en agregado y sin contenido.
CREATE TABLE IF NOT EXISTS uso (
  clave TEXT PRIMARY KEY, veces INTEGER NOT NULL DEFAULT 0, ultimo TEXT);

-- Lo mismo pero por día, que es lo que se puede dibujar en una gráfica. El
-- acumulado de arriba dice cuánto se ha usado algo desde siempre; esto dice si
-- se está usando más o menos que la semana pasada, que es la pregunta real.
CREATE TABLE IF NOT EXISTS uso_dia (
  dia TEXT NOT NULL, clave TEXT NOT NULL, veces INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (dia, clave));
`);

/** Las tablas que el sincronizador conoce. Añadir una entidad es añadirla aquí. */
export const TABLAS = ['listas', 'articulos', 'eventos', 'encargos', 'catalogo', 'clientes', 'tiendas', 'ajustes'];

export const guarda = (clave, valor) => bd.prepare(
  `INSERT INTO ajustes_servidor (clave, valor, actualizado) VALUES (?,?,?)
   ON CONFLICT(clave) DO UPDATE SET valor = excluded.valor, actualizado = excluded.actualizado`
).run(clave, String(valor), ahora());

export const lee = (clave) => bd.prepare('SELECT valor FROM ajustes_servidor WHERE clave = ?').get(clave)?.valor || null;

export const cuenta = (clave) => {
  const k = String(clave).slice(0, 60);
  const t = ahora();
  bd.prepare(`INSERT INTO uso (clave, veces, ultimo) VALUES (?,1,?)
    ON CONFLICT(clave) DO UPDATE SET veces = veces + 1, ultimo = excluded.ultimo`).run(k, t);
  bd.prepare(`INSERT INTO uso_dia (dia, clave, veces) VALUES (?,?,1)
    ON CONFLICT(dia, clave) DO UPDATE SET veces = veces + 1`).run(t.slice(0, 10), k);
};

/** El nombre sin tildes ni mayúsculas, que es como se comparan los productos. */
export const llano = (t) => String(t || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();

/** Limpieza. Se llama al arrancar y una vez al día: nada crece para siempre. */
export function barre() {
  bd.prepare("DELETE FROM codigos WHERE expira <= ?").run(ahora());
  bd.prepare("DELETE FROM chinola_espera WHERE expira <= ?").run(ahora());
  bd.prepare("DELETE FROM sesiones WHERE expira <= datetime('now','-30 days')").run();
  bd.prepare("DELETE FROM reportes WHERE expira IS NOT NULL AND expira <= ?").run(ahora());
  // Noventa días de cifras por día dan de sobra para ver una tendencia.
  bd.prepare("DELETE FROM uso_dia WHERE dia < date('now','-90 days')").run();
  // Las lápidas se guardan un mes: lo justo para que un teléfono que estuvo
  // apagado se entere de que algo se borró. Más tiempo es guardar basura.
  for (const t of TABLAS) {
    bd.prepare(`DELETE FROM ${t} WHERE borrado IS NOT NULL AND borrado <= datetime('now','-45 days')`).run();
  }
}
