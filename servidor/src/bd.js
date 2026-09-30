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
-- \«datos\» es un JSON con los campos propios de cada entidad. Se guarda entero
-- porque el servidor no necesita entenderlos para sincronizarlos, y así un
-- campo nuevo en la app no obliga a migrar la base ni a desplegar el servidor.
-- Lo que sí es columna es lo que el servidor usa: a quién pertenece, cuándo
-- cambió y si murió.
CREATE TABLE IF NOT EXISTS listas (
  id TEXT PRIMARY KEY, usuario_id TEXT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  datos TEXT NOT NULL, actualizado TEXT NOT NULL, borrado TEXT);
-- «lista_id» sale de dentro de «datos» y se guarda aparte a propósito: es lo
-- único que el servidor SÍ necesita entender de un artículo, porque de él
-- depende quién puede verlo cuando la lista está compartida. Buscarlo dentro
-- del JSON en cada consulta sería un escaneo entero por cada sincronización.
-- El índice sobre «lista_id» NO va aquí: en una base que ya existía, la tabla
-- se queda como estaba —«IF NOT EXISTS» no añade columnas— y crear un índice
-- sobre una columna que aún no está tira el arranque entero. Va abajo, después
-- de la migración que la añade.
CREATE TABLE IF NOT EXISTS articulos (
  id TEXT PRIMARY KEY, usuario_id TEXT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  lista_id TEXT, datos TEXT NOT NULL, actualizado TEXT NOT NULL, borrado TEXT);
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

-- Los pasillos: las categorías con las que se agrupa la lista en la tienda.
-- Son datos y no una constante porque cada quien compra en un sitio distinto y
-- recorre los pasillos en otro orden; y porque un colmado no tiene «Ferretería».
CREATE TABLE IF NOT EXISTS pasillos (
  id TEXT PRIMARY KEY, usuario_id TEXT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  datos TEXT NOT NULL, actualizado TEXT NOT NULL, borrado TEXT);

-- CLASIFICACIONES.
--
-- Maneras de ordenar los productos que decide cada quien: «Pasillo» viene de
-- fábrica, pero uno que venda ropa querrá «Marca» y «Talla», y quien venda
-- pescado no quiere ninguna. Los valores de cada una viven en «pasillos», que
-- es la tabla que ya existía y guarda exactamente eso.
CREATE TABLE IF NOT EXISTS clasificaciones (
  id TEXT PRIMARY KEY, usuario_id TEXT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  datos TEXT NOT NULL, actualizado TEXT NOT NULL, borrado TEXT);

-- GRUPOS.
--
-- «Mi negocio», «El otro negocio», «Casa». Un grupo tiene gente dentro, y todo
-- lo que se cree dentro de él —listas, ventas, catálogo, clientes— se comparte
-- solo con esa gente. Es la diferencia entre compartir una lista y compartir un
-- negocio: lo segundo se hace una vez.
CREATE TABLE IF NOT EXISTS grupos (
  id TEXT PRIMARY KEY, usuario_id TEXT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  datos TEXT NOT NULL, actualizado TEXT NOT NULL, borrado TEXT);

-- Los ajustes son uno por persona, así que el id ES el usuario.
CREATE TABLE IF NOT EXISTS ajustes (
  id TEXT PRIMARY KEY, usuario_id TEXT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  datos TEXT NOT NULL, actualizado TEXT NOT NULL, borrado TEXT);

-- COMPARTIR UNA LISTA.
--
-- Una pareja que se separa en el súper tiene que ver lo mismo: si él ya cogió
-- la leche, ella no debería buscarla. Por eso una lista puede tener miembros
-- además de dueño, y por eso el dueño de la FILA («usuario_id») y quién puede
-- verla dejan de ser lo mismo.
--
-- Se invita por correo aunque esa persona todavía no tenga cuenta: cuando entre
-- con ese correo, la invitación se convierte en membresía sola.
-- Los miembros son de un ÁMBITO, no de una lista: una lista suelta o un grupo
-- entero. Es la misma pregunta —«¿quién ve esto?»— y tenerla en dos tablas
-- sería tenerla contestada de dos maneras.
CREATE TABLE IF NOT EXISTS miembros (
  ambito     TEXT NOT NULL DEFAULT 'lista',    -- 'lista' | 'grupo'
  ambito_id  TEXT NOT NULL,
  email      TEXT NOT NULL,
  usuario_id TEXT REFERENCES usuarios(id) ON DELETE CASCADE,
  rol        TEXT NOT NULL DEFAULT 'editor',   -- 'dueño' | 'editor' | 'mira'
  creado     TEXT NOT NULL,
  visto      TEXT,
  PRIMARY KEY (ambito, ambito_id, email));
CREATE INDEX IF NOT EXISTS idx_miembros_usuario ON miembros (usuario_id);
CREATE INDEX IF NOT EXISTS idx_miembros_email ON miembros (email);

-- El enlace para invitar sin escribir un correo: se manda por WhatsApp y quien
-- lo abra entra. Caduca, porque un enlace que vale para siempre acaba en un
-- grupo de la familia.
CREATE TABLE IF NOT EXISTS invitaciones (
  codigo    TEXT PRIMARY KEY,
  ambito    TEXT NOT NULL DEFAULT 'lista',
  ambito_id TEXT NOT NULL,
  rol       TEXT NOT NULL DEFAULT 'editor',
  creador   TEXT NOT NULL,
  expira    TEXT NOT NULL,
  usos      INTEGER NOT NULL DEFAULT 0);

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

/**
 * AÑADIR UNA COLUMNA A UNA TABLA QUE YA EXISTE.
 *
 * `CREATE TABLE IF NOT EXISTS` con la columna nueva dentro **no hace nada** si
 * la tabla ya está: se queda como estaba y todo lo que la use se cae con «no
 * such column». Pasó con `lista_id` y tiró el servidor entero en bucle, así que
 * a partir de ahora toda columna nueva se añade por aquí.
 */
function columna(tabla, nombre, tipo) {
  const hay = bd.prepare(`PRAGMA table_info(${tabla})`).all().some((c) => c.name === nombre);
  if (hay) return false;
  bd.exec(`ALTER TABLE ${tabla} ADD COLUMN ${nombre} ${tipo}`);
  console.log('[bd] columna nueva:', tabla + '.' + nombre);
  return true;
}

/** Renombrar una columna sin romper la base que ya existe. */
function renombra(tabla, viejo, nuevo) {
  const cols = bd.prepare(`PRAGMA table_info(${tabla})`).all().map((c) => c.name);
  if (!cols.includes(viejo) || cols.includes(nuevo)) return false;
  bd.exec(`ALTER TABLE ${tabla} RENAME COLUMN ${viejo} TO ${nuevo}`);
  console.log('[bd] columna renombrada:', tabla + '.' + viejo, '→', nuevo);
  return true;
}

columna('articulos', 'lista_id', 'TEXT');
bd.exec('CREATE INDEX IF NOT EXISTS idx_articulos_lista ON articulos (lista_id)');

// De «esto es de una lista» a «esto es de un ámbito».
renombra('miembros', 'lista_id', 'ambito_id');
columna('miembros', 'ambito', "TEXT NOT NULL DEFAULT 'lista'");
renombra('invitaciones', 'lista_id', 'ambito_id');
columna('invitaciones', 'ambito', "TEXT NOT NULL DEFAULT 'lista'");

// A qué grupo pertenece cada cosa. Sale de dentro de `datos` y se guarda aparte
// porque de ella depende quién puede verla, y buscarla dentro del JSON en cada
// sincronización sería recorrer la tabla entera cada vez.
for (const tabla of ['listas', 'eventos', 'catalogo', 'clientes', 'tiendas', 'pasillos', 'clasificaciones']) {
  columna(tabla, 'grupo_id', 'TEXT');
  bd.exec(`CREATE INDEX IF NOT EXISTS idx_${tabla}_grupo ON ${tabla} (grupo_id)`);
}
// Y de qué venta es cada encargo, por lo mismo.
columna('encargos', 'evento_id', 'TEXT');
bd.exec('CREATE INDEX IF NOT EXISTS idx_encargos_evento ON encargos (evento_id)');

// Lo guardado antes de que existieran las columnas no las tiene. Se rellenan
// una vez, al arrancar: es la diferencia entre que una venta compartida se vea
// entera o a medias.
for (const [tabla, { columna: col, campo }] of Object.entries({
  listas: { columna: 'grupo_id', campo: 'grupoId' },
  eventos: { columna: 'grupo_id', campo: 'grupoId' },
  catalogo: { columna: 'grupo_id', campo: 'grupoId' },
  clientes: { columna: 'grupo_id', campo: 'grupoId' },
  tiendas: { columna: 'grupo_id', campo: 'grupoId' },
  encargos: { columna: 'evento_id', campo: 'eventoId' },
})) {
  try {
    const filas = bd.prepare(`SELECT id, datos FROM ${tabla} WHERE ${col} IS NULL`).all();
    if (!filas.length) continue;
    const pon = bd.prepare(`UPDATE ${tabla} SET ${col} = ? WHERE id = ?`);
    bd.transaction(() => {
      for (const f of filas) {
        try { pon.run(JSON.parse(f.datos)[campo] || null, f.id); } catch { /* fila ilegible */ }
      }
    })();
  } catch (e) { console.error('[bd] no pude rellenar', tabla + '.' + col, e.message); }
}

// Los artículos guardados antes de que existiera la columna no tienen
// `lista_id`. Se rellena una vez, al arrancar: son cuatro filas hoy y es la
// diferencia entre que una lista compartida se vea entera o a medias.
try {
  const sinLista = bd.prepare("SELECT id, datos FROM articulos WHERE lista_id IS NULL").all();
  if (sinLista.length) {
    const pon = bd.prepare('UPDATE articulos SET lista_id = ? WHERE id = ?');
    const todos = bd.transaction(() => {
      for (const a of sinLista) {
        try { pon.run(JSON.parse(a.datos).listaId || null, a.id); } catch { /* fila ilegible */ }
      }
    });
    todos();
    console.log('[bd] lista_id rellenado en', sinLista.length, 'artículo(s)');
  }
} catch (e) { console.error('[bd] no pude rellenar lista_id:', e.message); }

/** Las tablas que el sincronizador conoce. Añadir una entidad es añadirla aquí. */
export const TABLAS = ['grupos', 'clasificaciones', 'pasillos', 'listas', 'articulos', 'eventos', 'encargos', 'catalogo', 'clientes', 'tiendas', 'ajustes'];

/**
 * De dónde sale el «a quién pertenece» de cada tabla, para poder guardarlo en
 * una columna y consultarlo rápido. `grupo` es el ámbito compartido; `padre` es
 * la fila de la que cuelga (un artículo es de una lista, un encargo de una venta).
 */
export const AMBITO_DE = {
  listas: { columna: 'grupo_id', campo: 'grupoId' },
  eventos: { columna: 'grupo_id', campo: 'grupoId' },
  catalogo: { columna: 'grupo_id', campo: 'grupoId' },
  clientes: { columna: 'grupo_id', campo: 'grupoId' },
  tiendas: { columna: 'grupo_id', campo: 'grupoId' },
  pasillos: { columna: 'grupo_id', campo: 'grupoId' },
  clasificaciones: { columna: 'grupo_id', campo: 'grupoId' },
  articulos: { columna: 'lista_id', campo: 'listaId', padre: 'listas' },
  encargos: { columna: 'evento_id', campo: 'eventoId', padre: 'eventos' },
};

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
  bd.prepare('DELETE FROM invitaciones WHERE expira <= ?').run(ahora());
  // Las lápidas se guardan un mes: lo justo para que un teléfono que estuvo
  // apagado se entere de que algo se borró. Más tiempo es guardar basura.
  for (const t of TABLAS) {
    bd.prepare(`DELETE FROM ${t} WHERE borrado IS NOT NULL AND borrado <= datetime('now','-45 days')`).run();
  }
}
