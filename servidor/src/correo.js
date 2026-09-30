// EL CORREO.
//
// Un solo mensaje que mandar: el código de seis dígitos para entrar. Va por
// Resend porque es el proveedor que ya usa el dominio, y si no hay clave no se
// finge que salió: se dice, y la app enseña la puerta de Apple en su lugar.
import { config, hayCorreo } from './config.js';

const escapa = (t) => String(t).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

/** El cuerpo del mensaje. Sin imágenes ni rastreadores: solo el código, grande. */
function plantilla(codigo) {
  return `<!doctype html><html lang="es"><body style="margin:0;background:#f5ead8;font-family:-apple-system,Segoe UI,Roboto,sans-serif;color:#201e1d">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f5ead8;padding:32px 16px">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:460px;background:#fff;border-radius:28px;padding:32px">
        <tr><td style="font-size:22px;font-weight:800;padding-bottom:4px">cuadre</td></tr>
        <tr><td style="font-size:15px;color:#645c50;padding-bottom:24px">Compra, vende y cuadra — sin sacar cuenta.</td></tr>
        <tr><td style="font-size:17px;padding-bottom:12px">Tu código para entrar:</td></tr>
        <tr><td align="center" style="padding:8px 0 20px">
          <div style="display:inline-block;background:#f5ead8;border-radius:18px;padding:16px 26px;font-size:34px;font-weight:800;letter-spacing:8px">${escapa(codigo)}</div>
        </td></tr>
        <tr><td style="font-size:14px;color:#645c50;line-height:1.5">Vale por diez minutos y solo una vez. Si no lo pediste tú, ignora este mensaje: nadie entra sin él.</td></tr>
        <tr><td style="padding-top:24px;border-top:1px solid #ebddc5;font-size:12px;color:#82796a">Cuadre, de FENTE · <a href="mailto:soporte@fente.com.do" style="color:#8c491a">soporte@fente.com.do</a></td></tr>
      </table>
    </td></tr>
  </table></body></html>`;
}

/** Manda el código. Devuelve true si salió; nunca lanza, para no filtrar si el correo existe. */
export async function mandaCodigo(email, codigo) {
  if (!hayCorreo()) return false;
  try {
    const r = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { authorization: 'Bearer ' + config.resend, 'content-type': 'application/json' },
      body: JSON.stringify({
        from: config.correoDe,
        to: [email],
        subject: codigo + ' es tu código de Cuadre',
        html: plantilla(codigo),
        text: `Tu código para entrar a Cuadre es ${codigo}. Vale por diez minutos.`,
      }),
      signal: AbortSignal.timeout(15000),
    });
    if (!r.ok) { console.error('[correo]', r.status, (await r.text()).slice(0, 300)); return false; }
    return true;
  } catch (e) {
    console.error('[correo]', e.message);
    return false;
  }
}
