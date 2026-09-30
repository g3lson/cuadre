// La configuración, en un solo sitio y leída una sola vez. Todo lo que puede
// cambiar entre el portátil y el servidor sale de aquí.

const s = (v, pordefecto = '') => (v === undefined || v === null || v === '' ? pordefecto : String(v));

export const config = {
  puerto: Number(process.env.PORT || 3000),
  // La URL pública de la API. La necesita el redirect de OAuth de Chinola y los
  // enlaces de los reportes: los dos tienen que apuntar a esta máquina desde
  // fuera, y `req.host` no sirve cuando hay un proxy delante.
  sitio: s(process.env.CUADRE_SITIO, 'http://localhost:3000').replace(/\/$/, ''),
  sitioDir: s(process.env.CUADRE_SITIO_DIR, ''),
  bd: s(process.env.CUADRE_BD, './datos/cuadre.db'),
  version: s(process.env.CUADRE_VERSION, 'dev'),

  // Correo: el código de seis dígitos para entrar. Sin esto, la única puerta es
  // Sign in with Apple.
  resend: s(process.env.RESEND_API_KEY),
  correoDe: s(process.env.CUADRE_CORREO_DE, 'Cuadre <soporte@fente.com.do>'),

  // Sign in with Apple. `audiencia` es el bundle id de la app: un token de Apple
  // vale para la app a la que se emitió y para ninguna otra.
  appleAudiencia: s(process.env.CUADRE_APPLE_AUD, 'do.com.fente.cuadre'),

  // El router de modelos del propio servidor, compatible con OpenAI.
  ia: {
    base: s(process.env.CUADRE_IA_BASE, 'http://freellmapi:3001/v1').replace(/\/$/, ''),
    clave: s(process.env.CUADRE_IA_CLAVE),
    // Uno que lea imágenes, porque la foto del recibo pasa por el mismo sitio.
    modelo: s(process.env.CUADRE_IA_MODELO, 'claude-haiku-4-5'),
    respaldo: s(process.env.CUADRE_IA_RESPALDO, 'auto'),
  },

  // Chinola: la cuenta que se conecta una vez y se queda conectada.
  chinola: {
    sitio: s(process.env.CUADRE_CHINOLA_SITIO, 'https://chinola.fente.com.do').replace(/\/$/, ''),
    clienteId: s(process.env.CUADRE_CHINOLA_CLIENTE),
  },

  // El admin, para /api/salud detallada y nada más.
  metricasClave: s(process.env.CUADRE_METRICAS_CLAVE),
};

export const hayCorreo = () => !!config.resend;
export const hayIA = () => !!config.ia.clave;
