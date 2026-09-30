// EL REPORTE.
//
// Dos formas del mismo dato: un PDF que se comparte o se imprime, y una página
// que se abre con un enlace para quien no quiere descargar nada. Se guarda el
// JSON, no el PDF: pesa mil veces menos y el dibujo se puede mejorar mañana sin
// perder los reportes viejos.
import PDFDocument from 'pdfkit';
import { bd, ahora, uid } from './bd.js';
import { config } from './config.js';

const BARRO = '#c67139';
const SALVIA = '#56633f';
const CARBON = '#201e1d';
const TINTA_SUAVE = '#645c50';
const ARENA = '#f5ead8';
const LINEA = '#dcd3c4';

const pesos = (n) => 'RD$' + Math.round(Number(n) || 0).toLocaleString('en-US');
const dec = (n) => String(Math.round((Number(n) || 0) * 100) / 100);

const MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio',
  'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
function fechaLarga(iso) {
  const d = /^\d{4}-\d{2}-\d{2}/.test(String(iso || '')) ? new Date(iso + 'T12:00:00') : new Date();
  return `${d.getDate()} de ${MESES[d.getMonth()]} de ${d.getFullYear()}`;
}

/* ───────────────────────────── guardar ───────────────────────────── */

/** Guarda el reporte y devuelve su id. El enlace vive 180 días y luego se barre. */
export function guardaReporte(usuarioId, clase, datos) {
  const id = uid();
  bd.prepare('INSERT INTO reportes (id, usuario_id, clase, datos, creado, expira) VALUES (?,?,?,?,?,?)')
    .run(id, usuarioId, clase, JSON.stringify(datos), ahora(),
         new Date(Date.now() + 180 * 864e5).toISOString());
  return { id, url: config.sitio + '/r/' + id };
}

export const leeReporte = (id) => {
  const f = bd.prepare('SELECT * FROM reportes WHERE id = ?').get(String(id || ''));
  if (!f || f.clase === 'interno') return null;
  if (f.expira && f.expira <= ahora()) return null;
  return { ...f, datos: JSON.parse(f.datos) };
};

/* ───────────────────────────────  PDF  ─────────────────────────────── */

/** El logo: un círculo con el check y el punto salvia. Dibujado, no una imagen. */
function marca(doc, x, y, r) {
  doc.circle(x + r, y + r, r).fill(BARRO);
  const e = r * 0.75;
  doc.save().lineWidth(r * 0.30).strokeColor(ARENA).lineCap('round').lineJoin('round')
    .moveTo(x + r - e * 0.52, y + r + e * 0.02)
    .lineTo(x + r - e * 0.12, y + r + e * 0.42)
    .lineTo(x + r + e * 0.58, y + r - e * 0.40)
    .stroke().restore();
  doc.circle(x + r * 1.72, y + r * 1.72, r * 0.42).fill(ARENA);
  doc.circle(x + r * 1.72, y + r * 1.72, r * 0.30).fill(SALVIA);
}

/**
 * El cursor vertical se lleva a mano y todo se dibuja con coordenadas absolutas.
 * pdfkit arrastra la `x` del último `text()`, y en cuanto se mezcla texto
 * posicionado con texto en flujo el documento empieza a escalonarse hacia la
 * derecha y a inventarse páginas. Una `y` propia y `x` siempre explícita quita
 * esa clase entera de fallos.
 */
const IZQ = 48;
const ancho = (doc) => doc.page.width - IZQ * 2;

function cabecera(doc, titulo, subtitulo, negocio = '') {
  // Si el día se despachó a nombre de un negocio, el reporte es DE ese negocio
  // y lo dice arriba: es el papel que se le enseña a un socio o a un cliente.
  // Cuadre pasa a la línea de abajo, donde va la herramienta y no el dueño.
  marca(doc, IZQ, 44, 13);
  doc.font('Helvetica-Bold').fontSize(17).fillColor(CARBON)
    .text(negocio ? String(negocio).slice(0, 48) : 'cuadre', 84, 46, { lineBreak: false });
  doc.font('Helvetica').fontSize(9).fillColor(TINTA_SUAVE)
    .text(negocio ? 'con Cuadre, de FENTE' : 'de FENTE', 84, 65, { lineBreak: false });
  doc.font('Helvetica').fontSize(9).fillColor(TINTA_SUAVE)
    .text('cuadre.fente.com.do', IZQ, 50, { width: ancho(doc), align: 'right' });

  doc.moveTo(IZQ, 92).lineTo(doc.page.width - IZQ, 92).lineWidth(1).strokeColor(LINEA).stroke();
  doc.font('Helvetica-Bold').fontSize(24).fillColor(CARBON).text(titulo, IZQ, 112, { width: ancho(doc) });
  let y = doc.y + 2;
  if (subtitulo) {
    doc.font('Helvetica').fontSize(11).fillColor(TINTA_SUAVE).text(subtitulo, IZQ, y, { width: ancho(doc) });
    y = doc.y;
  }
  return y + 22;
}

function pie(doc) {
  // Escribir por debajo del margen inferior hace que pdfkit abra una página
  // nueva, y el pie queda solo en una hoja en blanco. Se anula el margen
  // mientras se dibuja y se devuelve como estaba.
  const antes = doc.page.margins.bottom;
  doc.page.margins.bottom = 0;
  const y = doc.page.height - 56;
  doc.moveTo(IZQ, y).lineTo(doc.page.width - IZQ, y).lineWidth(1).strokeColor(LINEA).stroke();
  doc.font('Helvetica').fontSize(8).fillColor(TINTA_SUAVE)
    .text('Generado por Cuadre · soporte@fente.com.do', IZQ, y + 10, { width: ancho(doc), lineBreak: false })
    .text(fechaLarga(new Date().toISOString().slice(0, 10)), IZQ, y + 10, { width: ancho(doc), align: 'right', lineBreak: false });
  doc.page.margins.bottom = antes;
}

/** Un rótulo de sección. */
function seccion(doc, texto, y) {
  doc.font('Helvetica-Bold').fontSize(12).fillColor(CARBON).text(texto, IZQ, y, { width: ancho(doc), lineBreak: false });
  return y + 22;
}

/** Cifras en fila: presupuesto, pagado y la diferencia. */
function cifras(doc, items, y) {
  const w = (ancho(doc) - 8 * (items.length - 1)) / items.length;
  items.forEach((c, i) => {
    const x = IZQ + i * (w + 8);
    doc.roundedRect(x, y, w, 58, 14).fill(c.fondo || ARENA);
    doc.font('Helvetica-Bold').fontSize(8).fillColor(c.tinta || TINTA_SUAVE)
      .text(String(c.rotulo).toUpperCase(), x + 12, y + 13, { width: w - 24, characterSpacing: 0.6, lineBreak: false });
    doc.font('Helvetica-Bold').fontSize(17).fillColor(c.tinta || CARBON)
      .text(c.valor, x + 12, y + 28, { width: w - 24, lineBreak: false });
  });
  return y + 58 + 26;
}

/** La tabla, con la cabecera repetida si hay que pasar de página. */
function tabla(doc, filas, columnas, y) {
  const cabeza = (y0) => {
    let x = IZQ;
    doc.font('Helvetica-Bold').fontSize(8).fillColor(TINTA_SUAVE);
    for (const c of columnas) {
      doc.text(c.rotulo.toUpperCase(), x, y0, { width: c.ancho - 6, align: c.align || 'left', characterSpacing: 0.6, lineBreak: false });
      x += c.ancho;
    }
    doc.moveTo(IZQ, y0 + 14).lineTo(doc.page.width - IZQ, y0 + 14).lineWidth(1).strokeColor(LINEA).stroke();
    return y0 + 22;
  };
  y = cabeza(y);

  for (const f of filas) {
    if (y > doc.page.height - 120) { pie(doc); doc.addPage(); y = cabeza(60); }
    let x = IZQ, alto = 0;
    for (const c of columnas) {
      doc.font(c.fuerte ? 'Helvetica-Bold' : 'Helvetica').fontSize(10).fillColor(c.suave ? TINTA_SUAVE : CARBON);
      doc.text(String(f[c.clave] ?? ''), x, y, { width: c.ancho - 6, align: c.align || 'left' });
      alto = Math.max(alto, doc.y - y);
      x += c.ancho;
    }
    y += alto + 7;
    doc.moveTo(IZQ, y - 4).lineTo(doc.page.width - IZQ, y - 4).lineWidth(0.5).strokeColor('#ece5d9').stroke();
  }
  return y + 10;
}

/**
 * Dibuja el reporte y devuelve el PDF como Buffer. Se arma en memoria porque son
 * dos páginas como mucho y así la ruta puede poner `content-length`.
 */
export function pdf(clase, d) {
  const doc = new PDFDocument({ size: 'LETTER', margins: { top: 48, bottom: 56, left: IZQ, right: IZQ }, info: {
    Title: (clase === 'cuadre' ? 'El cuadre · ' : 'Compra · ') + (d.titulo || ''),
    Author: 'Cuadre (FENTE)', Creator: 'Cuadre',
  } });
  const trozos = [];
  doc.on('data', (t) => trozos.push(t));

  if (clase === 'cuadre') dibujaCuadre(doc, d);
  else dibujaCompra(doc, d);

  pie(doc);
  doc.end();
  return new Promise((listo) => doc.on('end', () => listo(Buffer.concat(trozos))));
}

function dibujaCompra(doc, d) {
  const pagado = Number(d.pagado || 0), presupuesto = Number(d.presupuesto || 0);
  const diferencia = presupuesto - pagado;
  let y = cabecera(doc, d.titulo || 'Compra', [d.tienda, fechaLarga(d.fecha)].filter(Boolean).join(' · '));

  y = cifras(doc, [
    { rotulo: 'Presupuesto', valor: presupuesto ? pesos(presupuesto) : '—' },
    { rotulo: 'Pagaste', valor: pesos(pagado) },
    presupuesto
      ? (diferencia >= 0
        ? { rotulo: 'Te sobró', valor: pesos(diferencia), fondo: '#e1eecc', tinta: '#3d472b' }
        : { rotulo: 'Te pasaste', valor: pesos(-diferencia), fondo: '#ffe1d0', tinta: '#643312' })
      : { rotulo: 'Productos', valor: String((d.productos || []).length) },
  ], y);

  y = seccion(doc, 'Lo que compraste', y);
  y = tabla(doc, (d.productos || []).map((p) => ({
    nombre: p.nombre + (p.nota ? '\n' + p.nota : ''),
    cantidad: dec(p.cantidad) + ' ' + (p.unidad || ''),
    precio: pesos(p.precio),
    total: pesos((Number(p.cantidad) || 0) * (Number(p.precio) || 0)),
  })), [
    { clave: 'nombre', rotulo: 'Producto', ancho: 236 },
    { clave: 'cantidad', rotulo: 'Cant.', ancho: 80, align: 'right', suave: true },
    { clave: 'precio', rotulo: 'Precio', ancho: 90, align: 'right', suave: true },
    { clave: 'total', rotulo: 'Total', ancho: 110, align: 'right', fuerte: true },
  ], y);

  if (y > doc.page.height - 140) { pie(doc); doc.addPage(); y = 60; }
  doc.roundedRect(doc.page.width - IZQ - 230, y, 230, 48, 14).fill(CARBON);
  doc.font('Helvetica').fontSize(10).fillColor('#dcd3c4')
    .text('Total pagado', doc.page.width - IZQ - 212, y + 10, { width: 194, lineBreak: false });
  doc.font('Helvetica-Bold').fontSize(19).fillColor('#f9f4ed')
    .text(pesos(pagado), doc.page.width - IZQ - 212, y + 23, { width: 194, lineBreak: false });
  y += 48 + 26;

  if ((d.faltantes || []).length) {
    y = seccion(doc, 'Lo que faltó', y);
    doc.font('Helvetica').fontSize(10).fillColor(TINTA_SUAVE);
    for (const f of d.faltantes) {
      const linea = `· ${f.nombre}${f.cantidad ? ' (' + dec(f.cantidad) + ' ' + (f.unidad || '') + ')' : ''} · ${f.destino || 'pendiente'}`;
      doc.text(linea, IZQ, y, { width: ancho(doc) });
      y = doc.y + 3;
    }
    y += 12;
  }
  if (d.chinola) {
    doc.font('Helvetica-Bold').fontSize(9).fillColor(SALVIA)
      .text('Registrado en Chinola · ' + d.chinola, IZQ, y, { width: ancho(doc), lineBreak: false });
  }
}

function dibujaCuadre(doc, d) {
  const vendido = Number(d.vendido || 0), costo = Number(d.costo || 0);
  const comprado = Number(d.comprado || 0), porCobrar = Number(d.porCobrar || 0);
  const regalado = Number(d.regalado || 0);
  const ganancia = vendido - costo - regalado;
  let y = cabecera(doc, 'El cuadre', fechaLarga(d.fecha), d.negocio);

  doc.roundedRect(IZQ, y, ancho(doc), 100, 18).fill(SALVIA);
  doc.font('Helvetica').fontSize(11).fillColor('#e1eecc').text('Te quedó de ganancia', IZQ + 22, y + 20, { lineBreak: false });
  doc.font('Helvetica-Bold').fontSize(38).fillColor('#f9f4ed').text(pesos(ganancia), IZQ + 22, y + 38, { lineBreak: false });
  doc.font('Helvetica').fontSize(10).fillColor('#e1eecc')
    .text(vendido ? `Margen de ${Math.round((ganancia / vendido) * 100)}% sobre lo vendido` : 'Sin ventas todavía',
          IZQ + 22, y + 78, { lineBreak: false });
  y += 100 + 26;

  for (const [rotulo, valor] of [
    ['Vendiste', pesos(vendido)],
    ['Te costó la mercancía', '- ' + pesos(costo)],
    ...(regalado > 0 ? [['Regalaste y donaste', '- ' + pesos(regalado)]] : []),
    ['Gastaste en compras', '- ' + pesos(comprado)],
    ['Falta por cobrar', pesos(porCobrar)],
  ]) {
    doc.font('Helvetica').fontSize(11).fillColor(CARBON).text(rotulo, IZQ, y, { width: ancho(doc), lineBreak: false });
    doc.font('Helvetica-Bold').fontSize(11).fillColor(CARBON)
      .text(valor, IZQ, y, { width: ancho(doc), align: 'right', lineBreak: false });
    y += 22;
    doc.moveTo(IZQ, y - 5).lineTo(doc.page.width - IZQ, y - 5).lineWidth(0.5).strokeColor(LINEA).stroke();
  }
  y += 20;

  if ((d.encargos || []).length) {
    y = seccion(doc, 'Lo que despachaste', y);
    tabla(doc, d.encargos.map((o) => ({
      cliente: o.cliente,
      producto: `${o.producto} · ${dec(o.cantidad)} ${o.unidad || 'lb'}`,
      metodo: o.metodo || '',
      total: pesos(o.total),
    })), [
      { clave: 'cliente', rotulo: 'Cliente', ancho: 150, fuerte: true },
      { clave: 'producto', rotulo: 'Producto', ancho: 190, suave: true },
      { clave: 'metodo', rotulo: 'Pago', ancho: 90, suave: true },
      { clave: 'total', rotulo: 'Total', ancho: 86, align: 'right', fuerte: true },
    ], y);
  }
}

/* ─────────────────────────── la página del enlace ─────────────────────────── */

const esc = (t) => String(t == null ? '' : t).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

/**
 * La versión web del mismo reporte. Es una página sola, sin CSS externo: quien
 * la abre puede no tener nada de esta app y tiene que verse bien igual.
 */
export function paginaReporte(r) {
  const d = r.datos;
  const esCuadre = r.clase === 'cuadre';
  const pagado = Number(d.pagado || 0), presupuesto = Number(d.presupuesto || 0);
  const vendido = Number(d.vendido || 0), costo = Number(d.costo || 0);
  const diferencia = presupuesto - pagado;

  const filas = esCuadre
    ? (d.encargos || []).map((o) => `<tr><td><strong>${esc(o.cliente)}</strong><small>${esc(o.producto)} · ${esc(dec(o.cantidad))} ${esc(o.unidad || 'lb')}</small></td><td class="d">${esc(o.metodo || '')}</td><td class="n">${pesos(o.total)}</td></tr>`).join('')
    : (d.productos || []).map((p) => `<tr><td><strong>${esc(p.nombre)}</strong>${p.nota ? `<small>${esc(p.nota)}</small>` : ''}</td><td class="d">${esc(dec(p.cantidad))} ${esc(p.unidad || '')}</td><td class="d">${pesos(p.precio)}</td><td class="n">${pesos((Number(p.cantidad) || 0) * (Number(p.precio) || 0))}</td></tr>`).join('');

  const cabezas = esCuadre
    ? '<tr><th>Cliente</th><th class="d">Pago</th><th class="n">Total</th></tr>'
    : '<tr><th>Producto</th><th class="d">Cant.</th><th class="d">Precio</th><th class="n">Total</th></tr>';

  const regalado = Number(d.regalado || 0);
  const tarjetas = esCuadre
    ? [['Vendiste', pesos(vendido)], ['Te costó', pesos(costo + regalado)],
       ['Ganancia', pesos(vendido - costo - regalado), true]]
    : [['Presupuesto', presupuesto ? pesos(presupuesto) : '—'], ['Pagaste', pesos(pagado)],
       [diferencia >= 0 ? 'Te sobró' : 'Te pasaste', pesos(Math.abs(diferencia)), diferencia >= 0]];

  return `<!doctype html><html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>${esc(esCuadre ? 'El cuadre' : d.titulo || 'Compra')} · Cuadre</title>
<meta name="theme-color" content="#f5ead8">
<meta name="robots" content="noindex">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<style>
:root{--bg:#f5ead8;--sup:#ebddc5;--tinta:#201e1d;--suave:#645c50;--barro:#c67139;--salvia:#56633f;--linea:#dcd3c4}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--tinta);font:16px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;padding:24px 16px 64px}
main{max-width:680px;margin:0 auto}
.marca{display:flex;align-items:center;gap:10px;font-weight:800;font-size:20px;margin-bottom:28px}
.punto{width:26px;height:26px;border-radius:50%;background:var(--barro);position:relative;flex:none}
.punto::after{content:"";position:absolute;right:-3px;bottom:-3px;width:12px;height:12px;border-radius:50%;background:var(--salvia);border:2.5px solid var(--bg)}
.marca small{font-weight:500;color:var(--suave);font-size:13px}
h1{font-size:34px;line-height:1.08;margin:0 0 6px}
.sub{color:var(--suave);margin:0 0 26px}
.cifras{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin-bottom:28px}
.cifra{background:var(--sup);border-radius:18px;padding:14px}
.cifra span{display:block;font-size:11px;font-weight:800;letter-spacing:.8px;text-transform:uppercase;color:var(--suave)}
.cifra strong{display:block;font-size:19px;margin-top:4px}
.cifra.bien{background:#e1eecc}.cifra.bien span,.cifra.bien strong{color:#3d472b}
table{width:100%;border-collapse:collapse}
th{text-align:left;font-size:11px;letter-spacing:.8px;text-transform:uppercase;color:var(--suave);padding:0 0 8px;border-bottom:1px solid var(--linea)}
td{padding:12px 0;border-bottom:1px solid #ece5d9;vertical-align:top}
td small{display:block;color:var(--suave);font-size:13px}
.d{text-align:right;color:var(--suave);white-space:nowrap}
.n{text-align:right;font-weight:800;white-space:nowrap}
th.d,th.n{text-align:right}
.total{display:flex;justify-content:space-between;align-items:baseline;background:#2e2b25;color:#f9f4ed;border-radius:18px;padding:16px 20px;margin-top:20px}
.total b{font-size:24px}
.falto{background:#fff2eb;color:#643312;border-radius:18px;padding:16px 20px;margin-top:20px}
.falto h2{font-size:12px;letter-spacing:.8px;text-transform:uppercase;margin:0 0 8px}
.falto p{margin:4px 0}
.pie{margin-top:36px;padding-top:16px;border-top:1px solid var(--linea);color:var(--suave);font-size:13px}
.pie a{color:#8c491a}
@media (prefers-color-scheme:dark){
  :root{--bg:#141518;--sup:#212328;--tinta:#f3efe7;--suave:#a5a8ae;--linea:#3a3e45}
  .cifra.bien{background:#1e3a2c}.cifra.bien span,.cifra.bien strong{color:#a8e3c6}
  td{border-bottom-color:#2a2d33}
  .total{background:#212328}
  .falto{background:#2e2618;color:#fbe3b4}
}
</style></head><body><main>
<div class="marca"><span class="punto"></span>${d.negocio ? `${esc(String(d.negocio).slice(0, 48))}<small>con Cuadre</small>` : 'cuadre<small>de FENTE</small>'}</div>
<h1>${esc(esCuadre ? 'El cuadre' : d.titulo || 'Compra')}</h1>
<p class="sub">${esc([d.tienda, fechaLarga(d.fecha)].filter(Boolean).join(' · '))}</p>
<div class="cifras">${tarjetas.map(([r2, v, bien]) => `<div class="cifra${bien ? ' bien' : ''}"><span>${esc(r2)}</span><strong>${esc(v)}</strong></div>`).join('')}</div>
<table><thead>${cabezas}</thead><tbody>${filas || '<tr><td colspan="4" class="d">Nada todavía.</td></tr>'}</tbody></table>
<div class="total"><span>${esCuadre ? 'Ganancia' : 'Total pagado'}</span><b>${pesos(esCuadre ? vendido - costo - regalado : pagado)}</b></div>
${(d.faltantes || []).length ? `<div class="falto"><h2>Lo que faltó</h2>${d.faltantes.map((f) => `<p><strong>${esc(f.nombre)}</strong> → ${esc(f.destino || 'pendiente')}</p>`).join('')}</div>` : ''}
<p class="pie">Reporte hecho con <a href="https://cuadre.fente.com.do">Cuadre</a>, de FENTE. Este enlace solo lo tiene quien lo recibió.
<br><a href="/r/${esc(r.id)}.pdf">Descargar en PDF</a></p>
</main></body></html>`;
}
