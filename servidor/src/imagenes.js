// EL LOGO Y LA PORTADA DE UN NEGOCIO.
//
// Las imágenes NO viajan por la sincronización. El `datos` de cada fila es
// JSON, y meter un logo ahí en base64 significa mandarlo entero en cada
// sincronización de cada teléfono del grupo: kilobytes que se pagan cien veces
// por una foto que cambia una vez al año. Aquí se sube una vez, se guarda en
// disco junto a la base, y lo que viaja es la dirección.
//
// El nombre del archivo es el HASH de su contenido. Tres cosas salen gratis de
// eso: subir dos veces la misma imagen no ocupa el doble, la dirección cambia
// sola cuando cambia la imagen (así que se puede cachear para siempre sin que
// nadie se quede viendo el logo viejo), y no se puede adivinar la de otro.

import { createHash } from 'node:crypto';
import { mkdirSync, writeFileSync, existsSync, statSync, readdirSync, unlinkSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { config } from './config.js';

/** Junto a la base de datos: quien respalda una, respalda la otra. */
export const carpeta = resolve(dirname(resolve(config.bd)), 'imagenes');

/** Lo más grande que se acepta. Un logo de 3 MB es una foto sin recortar. */
export const MAXIMO = 3 * 1024 * 1024;

/**
 * Qué es de verdad este archivo, mirando sus primeros bytes y no lo que diga
 * la cabecera: el `Content-Type` lo escribe quien sube.
 */
function tipoDe(buf) {
  if (buf.length < 12) return null;
  if (buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'jpg';
  if (buf[0] === 0x89 && buf.toString('latin1', 1, 4) === 'PNG') return 'png';
  if (buf.toString('latin1', 0, 4) === 'RIFF' && buf.toString('latin1', 8, 12) === 'WEBP') return 'webp';
  return null;
}

export const MIME = { jpg: 'image/jpeg', png: 'image/png', webp: 'image/webp' };

/**
 * Guarda y devuelve la dirección pública. Si ya estaba, no escribe nada.
 * @returns {{url: string, archivo: string, bytes: number}}
 */
export function guarda(buf) {
  const tipo = tipoDe(buf);
  if (!tipo) throw Object.assign(new Error('Eso no es una imagen.'), { estado: 400 });
  if (buf.length > MAXIMO) throw Object.assign(new Error('La imagen pesa demasiado.'), { estado: 413 });

  mkdirSync(carpeta, { recursive: true });
  const hash = createHash('sha256').update(buf).digest('hex').slice(0, 32);
  const archivo = `${hash}.${tipo}`;
  const ruta = join(carpeta, archivo);
  if (!existsSync(ruta)) writeFileSync(ruta, buf);
  return { url: `${config.sitio}/img/${archivo}`, archivo, bytes: buf.length };
}

/** El nombre del archivo dentro de una dirección nuestra, o null. */
export function archivoDe(url) {
  const m = /\/img\/([0-9a-f]{32}\.(?:jpg|png|webp))(?:$|[?#])/.exec(String(url || ''));
  return m ? m[1] : null;
}

/**
 * Borra las imágenes que ya no nombra nadie. Se llama con el respaldo diario:
 * cambiar un logo cinco veces deja cuatro huérfanas, y nadie las va a barrer a
 * mano.
 */
export function barre(enUso) {
  if (!existsSync(carpeta)) return 0;
  const vivas = new Set([...enUso].map(archivoDe).filter(Boolean));
  let barridas = 0;
  const hace = Date.now() - 24 * 60 * 60 * 1000;
  for (const f of readdirSync(carpeta)) {
    if (vivas.has(f)) continue;
    // Margen de un día: una imagen recién subida puede estar esperando a que
    // el teléfono sincronice la fila que la nombra.
    try {
      if (statSync(join(carpeta, f)).mtimeMs > hace) continue;
      unlinkSync(join(carpeta, f));
      barridas += 1;
    } catch { /* ya no está */ }
  }
  return barridas;
}
