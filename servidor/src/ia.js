// LA IA, DE PASO.
//
// El modelo no se conecta desde el teléfono: se conecta desde aquí, contra el
// router de modelos que ya corre en este mismo servidor. Así la llave no viaja
// dentro de la app —donde cualquiera la saca— y cambiar de modelo mañana no
// obliga a publicar una versión nueva en el App Store.
//
// Dos trabajos, y los dos son el mismo: convertir algo que una persona dijo o
// fotografió en filas de una lista. Nada de conversación: entra texto o imagen,
// sale JSON, y si no sale JSON la app sigue funcionando a mano.
import { config, hayIA } from './config.js';

const UNIDADES = ['lb', 'kg', 'oz', 'ud', 'doc', 'paq', 'saco', 'gal', 'L'];
const CATEGORIAS = ['Víveres', 'Carnes y pescados', 'Lácteos y huevos', 'Frutas y vegetales',
  'Panadería', 'Limpieza', 'Higiene', 'Bebidas', 'Ferretería', 'Otros'];

const REGLAS = `Eres el ayudante de Cuadre, una app dominicana de compras y ventas. Devuelves SOLO un objeto JSON, sin texto alrededor y sin bloques de código.

Unidades válidas (usa exactamente estas claves): ${UNIDADES.join(', ')}.
 lb=libra, kg=kilo, oz=onza, ud=unidad, doc=docena, paq=paquete, saco=saco, gal=galón, L=litro.
Categorías válidas: ${CATEGORIAS.join(', ')}.

Reglas del país y del oficio:
- La moneda es el peso dominicano. Los precios son números, sin símbolo ni separadores de miles.
- «precio» es SIEMPRE el precio de UNA unidad de la unidad elegida, no el total.
- Si te dan el total y la cantidad, divide para sacar el precio.
- Habla dominicano: «plátanos barahoneros», «pan sobao», «queso de freír», «azúcar crema», «chillo», «víveres».
- Un saco de arroz son 50 lb y se pide como 1 saco, no como 50 lb.
- Si no sabes el precio, pon 0. Nunca lo inventes.
- Si no sabes la unidad, usa "ud".
- La nota es para marca, tamaño o detalle («Rica, la azul», «bien fresco», «50 lb»), no para repetir el nombre.`;

async function pregunta(mensajes, { maxTokens = 1800 } = {}) {
  if (!hayIA()) throw Object.assign(new Error('La IA no está configurada en este servidor.'), { estado: 503 });

  const intentar = async (modelo) => {
    const r = await fetch(config.ia.base + '/chat/completions', {
      method: 'POST',
      headers: { authorization: 'Bearer ' + config.ia.clave, 'content-type': 'application/json' },
      body: JSON.stringify({
        model: modelo,
        max_tokens: maxTokens,
        temperature: 0,
        messages: mensajes,
        response_format: { type: 'json_object' },
      }),
      signal: AbortSignal.timeout(90_000),
    });
    if (!r.ok) throw new Error(modelo + ' → ' + r.status + ' ' + (await r.text()).slice(0, 240));
    const j = await r.json();
    return j?.choices?.[0]?.message?.content || '';
  };

  try {
    return await intentar(config.ia.modelo);
  } catch (e) {
    // El router tiene cadena de respaldo, pero un modelo concreto puede estar
    // sin cuota justo hoy. `auto` deja que el router elija, y eso es mejor que
    // decirle a alguien en el súper que la foto no se pudo leer.
    console.error('[ia]', e.message);
    if (!config.ia.respaldo || config.ia.respaldo === config.ia.modelo) throw e;
    return await intentar(config.ia.respaldo);
  }
}

/**
 * Saca el JSON aunque venga con adornos. Un modelo que casi siempre obedece y
 * de vez en cuando escribe ```json alrededor no debería tumbar la función.
 */
function extrae(texto) {
  const t = String(texto || '').trim().replace(/^```(?:json)?/i, '').replace(/```$/, '').trim();
  try { return JSON.parse(t); } catch { /* sigue */ }
  const a = t.indexOf('{'), b = t.lastIndexOf('}');
  if (a >= 0 && b > a) { try { return JSON.parse(t.slice(a, b + 1)); } catch { /* sigue */ } }
  throw Object.assign(new Error('El modelo no devolvió JSON.'), { estado: 502 });
}

const num = (v) => { const n = Number(String(v ?? '').replace(',', '.')); return Number.isFinite(n) && n >= 0 ? n : 0; };
const r2 = (n) => Math.round(n * 100) / 100;

/** Limpia lo que vino del modelo. Nada entra en la app sin pasar por aquí. */
function limpia(productos) {
  return (Array.isArray(productos) ? productos : []).slice(0, 80).map((p) => ({
    nombre: String(p?.nombre || '').trim().slice(0, 70),
    unidad: UNIDADES.includes(p?.unidad) ? p.unidad : 'ud',
    cantidad: r2(num(p?.cantidad)) || 1,
    precio: r2(num(p?.precio)),
    nota: String(p?.nota || '').trim().slice(0, 90),
    categoria: CATEGORIAS.includes(p?.categoria) ? p.categoria : 'Otros',
  })).filter((p) => p.nombre);
}

/** De lo que alguien dictó o pegó, a filas de lista. */
export async function listaDeTexto(texto, { tienda = '', conocidos = [] } = {}) {
  const t = String(texto || '').trim().slice(0, 4000);
  if (!t) return { productos: [] };

  const pista = conocidos.length
    ? `\n\nProductos que esta persona ya compra, con su último precio. Si reconoces uno, usa SU nombre y SU precio:\n${
      conocidos.slice(0, 60).map((c) => `- ${c.nombre} · ${c.unidad} · ${c.precio}`).join('\n')}`
    : '';

  const bruto = await pregunta([
    { role: 'system', content: REGLAS + `\n\nFormato: {"productos":[{"nombre","unidad","cantidad","precio","nota","categoria"}]}` },
    { role: 'user', content: `Tienda: ${tienda || 'sin especificar'}.${pista}\n\nConvierte esto en productos:\n\n${t}` },
  ]);
  return { productos: limpia(extrae(bruto).productos) };
}

/**
 * De la foto del recibo, a filas con lo que de verdad te cobraron. Es la parte
 * que más tiempo ahorra: diez productos escritos a mano son diez oportunidades
 * de teclear un número mal.
 */
export async function listaDeRecibo(imagenBase64, tipo = 'image/jpeg') {
  const datos = String(imagenBase64 || '').replace(/^data:[^,]+,/, '');
  if (!datos) throw Object.assign(new Error('No llegó la imagen.'), { estado: 400 });

  const bruto = await pregunta([
    { role: 'system', content: REGLAS + `\n\nFormato: {"tienda":"","fecha":"AAAA-MM-DD","total":0,"productos":[{"nombre","unidad","cantidad","precio","nota","categoria"}]}` },
    {
      role: 'user',
      content: [
        { type: 'text', text: 'Este es un recibo de compra dominicano. Lee cada línea y devuélvela como producto, con el precio POR UNIDAD (si el recibo trae el total de la línea, divídelo por la cantidad). Si una línea es un impuesto, una propina o un descuento, no la incluyas como producto.' },
        { type: 'image_url', image_url: { url: `data:${tipo};base64,${datos}` } },
      ],
    },
  ], { maxTokens: 2600 });

  const j = extrae(bruto);
  return {
    tienda: String(j?.tienda || '').trim().slice(0, 60),
    fecha: /^\d{4}-\d{2}-\d{2}$/.test(j?.fecha || '') ? j.fecha : '',
    total: r2(num(j?.total)),
    productos: limpia(j?.productos),
  };
}
