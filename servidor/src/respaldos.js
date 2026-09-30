// RESPALDOS.
//
// Una copia al día de la base, dentro del propio contenedor. No hay cron en el
// host y no lo va a haber: un respaldo que depende de que alguien se acuerde de
// configurarlo en otro sitio es un respaldo que no existe.
//
// Se usa `VACUUM INTO`, que es la única manera correcta de copiar una base
// SQLite que está en uso: hace la copia dentro de una transacción, así que el
// archivo que sale está consistente aunque alguien esté escribiendo. Copiar el
// `.db` con `cp` mientras hay un WAL a medias produce un archivo que parece
// bueno hasta el día que hace falta.
import { mkdirSync, readdirSync, statSync, unlinkSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { bd, ahora, guarda, lee } from './bd.js';
import { config } from './config.js';

const CUANTOS = 14;          // dos semanas
const CADA = 24 * 3600_000;

const carpeta = () => join(dirname(config.bd), 'respaldos');

/** El sello del archivo: ordenable como texto y legible por una persona. */
const sello = () => new Date().toISOString().slice(0, 16).replace(/[-:]/g, '').replace('T', '-');

export function respalda() {
  const destino = join(carpeta(), `cuadre-${sello()}.db`);
  mkdirSync(carpeta(), { recursive: true });
  // `VACUUM INTO` no acepta parámetros, así que la ruta va en el texto. La
  // construimos nosotros de una fecha, no llega de fuera.
  bd.exec(`VACUUM INTO '${destino.replace(/'/g, "''")}'`);
  guarda('ultimo_respaldo', ahora());
  barreViejos();
  return destino;
}

/** Se guardan los catorce últimos. Más es llenar el disco de copias que nadie mira. */
function barreViejos() {
  let archivos;
  try {
    archivos = readdirSync(carpeta())
      .filter((f) => f.startsWith('cuadre-') && f.endsWith('.db'))
      .sort()
      .reverse();
  } catch { return; }
  for (const viejo of archivos.slice(CUANTOS)) {
    try { unlinkSync(join(carpeta(), viejo)); } catch { /* ya no está */ }
  }
}

/** Para `/api/salud`: cuándo fue el último y cuántos hay. */
export function estado() {
  let cuantos = 0, ultimoTamano = 0;
  try {
    const archivos = readdirSync(carpeta()).filter((f) => f.endsWith('.db')).sort();
    cuantos = archivos.length;
    if (cuantos) ultimoTamano = statSync(join(carpeta(), archivos[archivos.length - 1])).size;
  } catch { /* todavía no hay carpeta */ }
  return { ultimo: lee('ultimo_respaldo'), cuantos, bytes: ultimoTamano };
}

/**
 * Arranca el reloj. Se comprueba cada hora en vez de dormir veinticuatro: un
 * contenedor que se reinicia tres veces al día nunca llegaría a las veinticuatro
 * y no se respaldaría jamás.
 */
export function arrancaRespaldos() {
  const toca = () => {
    const ultimo = lee('ultimo_respaldo');
    if (ultimo && Date.now() - Date.parse(ultimo) < CADA) return;
    try {
      console.log('[respaldo]', respalda());
    } catch (e) {
      console.error('[respaldo] falló:', e.message);
    }
  };
  // Al minuto de arrancar, no en el acto: primero que la app esté contestando.
  setTimeout(toca, 60_000).unref();
  setInterval(toca, 3600_000).unref();
}
