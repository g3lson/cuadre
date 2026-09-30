# Cuadre

**Compra, vende y cuadra — sin sacar cuenta.**

App de iPhone para llevar la compra del súper en vivo, despachar por libra a tus
clientes y cerrar el día con las cuentas claras. En RD, *hacer el cuadre* es
justo eso, y de ahí el nombre.

Hecha por **FENTE** · [cuadre.fente.com.do](https://cuadre.fente.com.do)

---

## Qué hay aquí

| Carpeta | Qué es |
| --- | --- |
| `ios/` | La app. Swift y SwiftUI, sin dependencias de terceros. iOS 17+. |
| `servidor/` | La API. Node, Express y SQLite. Cuenta, sincronización, IA, Chinola y reportes. |
| `sitio/` | La página pública y las legales. HTML plano, servido por el mismo contenedor. |
| `scripts/` | Utilidades. Hoy: generar los iconos desde código. |

## La app

Cuatro pestañas, catorce pantallas y tres temas que cambian colores y
tipografía pero no la estructura.

- **Listas** — una lista por compra, con su tienda, su presupuesto y su color.
  Se repite la del mes pasado con los precios que pagaste, o se arrastra lo que
  faltó la última vez.
- **En tienda** — una fila por producto con cantidad, precio y total. Nueve
  unidades (libra, kilo, onza, unidad, docena, paquete, saco, galón, litro).
  Pones cantidad × precio y sale el total, o escribes lo que te cobraron y sale
  el precio por libra.
- **Ventas** — encargos por libra, peso real al despachar, tres tarifas y
  comprobante por WhatsApp.
- **El cuadre** — lo que vendiste, lo que te costó la mercancía, lo que gastaste
  comprando y lo que falta por cobrar, con la ganancia del día y dónde está el
  dinero.

Funciona entera sin señal: lo que se escribe en el pasillo del súper se guarda
en el teléfono (SwiftData) y sube cuando vuelve la conexión.

### Cómo sincroniza

Una llamada: sube lo pendiente y baja lo que cambió, en el mismo viaje. Gana el
cambio más reciente, fila por fila. Borrar escribe una lápida, porque una fila
que desaparece sin dejar rastro reaparece en cuanto otro teléfono suba lo que
tenía. El detalle está en `ios/Cuadre/Datos/Sincronizador.swift` y en
`servidor/src/rutas/sync.js`.

### Chinola

[Chinola](https://chinola.fente.com.do) es la app de finanzas de FENTE.
Conectarla es opcional y funciona como una cuenta conectada: OAuth 2.1 con PKCE,
la persona entra en Chinola, ve qué permisos da y confirma. El token vive en el
servidor de Cuadre y se refresca solo, así que la conexión sobrevive a
reinstalar la app. Se corta desde cualquiera de las dos.

### La IA

Dos atajos opcionales: dictar o pegar la lista en lenguaje normal, y leer la foto
de un recibo. Van por el servidor contra un router de modelos compatible con
OpenAI, para que la llave no viaje dentro de la app. Todo lo demás funciona sin
IA ninguna.

## Levantarlo en local

```bash
cd servidor && npm install
npm run dev        # API + sitio en http://localhost:3300
```

La app apunta a producción por defecto. Para probarla contra el portátil, en el
esquema de Xcode: `CUADRE_API=http://TU-IP:3300`.

```bash
cd servidor && npm run prueba    # el recorrido entero: entrar, sincronizar, reporte
```

## Desplegar

```bash
scripts/desplegar.sh
```

Sube el código a `athenas:/opt/stacks/cuadre/`, reconstruye el contenedor y
comprueba la salud. Hace falta que existan el registro DNS y el Proxy Host; eso
se hace una vez y a mano.

Un solo dominio, `cuadre.fente.com.do`: la portada y las legales en la raíz, la
API en `/api`. No hay `api.cuadre.…` a propósito — el certificado gratuito de
Cloudflare cubre `*.fente.com.do` y nada más, así que un subdominio de dos
niveles se queda sin certificado en el borde y el TLS falla.

## Licencia

Propietario. Ver [LICENSE](LICENSE). Las tipografías son SIL OFL 1.1 y su aviso
viaja con ellas.
