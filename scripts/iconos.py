#!/usr/bin/env python3
"""
LOS ICONOS, DIBUJADOS.

El símbolo de Cuadre es geometría pura —un círculo, un check y un punto—, así
que se dibuja con código y no se guarda como imagen: cambiar el color de la
marca es cambiar una línea aquí y volver a correrlo, no reexportar doce
archivos a mano y que uno se quede viejo.

Se dibuja al cuádruple y se reduce: es la manera de tener bordes suaves sin
depender de un rasterizador de SVG instalado en la máquina.

    python3 scripts/iconos.py
"""
from PIL import Image, ImageDraw, ImageFont
from pathlib import Path

BARRO = (198, 113, 57)
SALVIA = (122, 138, 94)
ARENA = (245, 234, 216)
CARBON = (32, 30, 29)

RAIZ = Path(__file__).resolve().parent.parent
SUPER = 4  # se dibuja a 4× y se reduce


def marca(lado, fondo, redondeo=0.0, circulo=ARENA, check=None, punto=SALVIA):
    """El icono: fondo, círculo con el check dentro, y el punto de la otra mitad."""
    s = lado * SUPER
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    if redondeo > 0:
        d.rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * redondeo), fill=fondo)
    else:
        d.rectangle([0, 0, s, s], fill=fondo)

    # Las medidas vienen del diseño, en una rejilla de 120.
    u = s / 120.0
    cx0, cy0, diam = 22 * u, 22 * u, 64 * u
    d.ellipse([cx0, cy0, cx0 + diam, cy0 + diam], fill=circulo)

    # El check, en la rejilla de 24 del icono original: M20 6 9 17l-5-5.
    e = diam / 24.0
    grosor = max(2, int(3 * e))
    puntos = [(cx0 + 4 * e, cy0 + 12 * e), (cx0 + 9 * e, cy0 + 17 * e), (cx0 + 20 * e, cy0 + 6 * e)]
    d.line(puntos, fill=check or fondo, width=grosor, joint="curve")
    # Las puntas redondeadas: `line` no las hace, así que se ponen a mano.
    for p in (puntos[0], puntos[2]):
        r = grosor / 2
        d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=check or fondo)

    px0, py0, pd = 74 * u, 74 * u, 28 * u
    d.ellipse([px0, py0, px0 + pd, py0 + pd], fill=punto)

    return img.resize((lado, lado), Image.LANCZOS)


def guarda(img, destino):
    destino.parent.mkdir(parents=True, exist_ok=True)
    img.save(destino)
    print(f"  {destino.relative_to(RAIZ)}  {img.size[0]}×{img.size[1]}")


SVG = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120" role="img" aria-label="Cuadre">
  <rect width="120" height="120" rx="30" fill="#c67139"/>
  <circle cx="54" cy="54" r="32" fill="#f5ead8"/>
  <path d="M32.7 54 46 67.3 75.3 38" fill="none" stroke="#c67139"
        stroke-width="8" stroke-linecap="round" stroke-linejoin="round"/>
  <circle cx="88" cy="88" r="14" fill="#7a8a5e"/>
</svg>
"""

def tarjeta_og():
    """La imagen que sale cuando alguien pega el enlace en WhatsApp: 1200×630."""
    w, h = 1200 * 2, 630 * 2
    img = Image.new("RGB", (w, h), ARENA)
    d = ImageDraw.Draw(img)

    fuentes = RAIZ / "ios" / "Cuadre" / "Recursos" / "Fuentes"
    titulo = ImageFont.truetype(str(fuentes / "Caprasimo-Regular.ttf"), 210)
    claim = ImageFont.truetype(str(fuentes / "Figtree-SemiBold.ttf"), 74)
    pie = ImageFont.truetype(str(fuentes / "Figtree-Bold.ttf"), 46)

    icono = marca(300, BARRO, redondeo=0.25)
    img.paste(icono, (150, 250), icono)
    d.text((500, 275), "cuadre", font=titulo, fill=CARBON)
    d.text((504, 530), "Compra, vende y cuadra —", font=claim, fill=(140, 73, 26))
    d.text((504, 630), "sin sacar cuenta.", font=claim, fill=(140, 73, 26))
    d.rounded_rectangle([150, 880, w - 150, 892], radius=6, fill=(227, 214, 191))
    d.text((152, 960), "LISTAS  ·  EN TIENDA  ·  VENTAS  ·  EL CUADRE", font=pie, fill=(100, 92, 80))
    d.text((152, 1060), "PARA IPHONE  ·  DE FENTE", font=pie, fill=(140, 73, 26))

    return img.resize((1200, 630), Image.LANCZOS)


def main():
    sitio = RAIZ / "sitio"
    ios = RAIZ / "ios" / "Cuadre" / "Recursos" / "Assets.xcassets" / "AppIcon.appiconset"

    print("Sitio:")
    (sitio / "favicon.svg").write_text(SVG)
    print(f"  sitio/favicon.svg")
    guarda(marca(192, BARRO, redondeo=0.25), sitio / "icon-192.png")
    guarda(marca(512, BARRO, redondeo=0.25), sitio / "icon-512.png")
    # El de Apple va sin esquinas redondeadas ni transparencia: iOS pone la suya.
    guarda(marca(180, BARRO), sitio / "apple-touch-icon.png")
    guarda(marca(32, BARRO, redondeo=0.25), sitio / "favicon.png")
    guarda(tarjeta_og(), sitio / "og.png")

    print("App:")
    # Un solo archivo de 1024: desde Xcode 14 el catálogo saca el resto.
    guarda(marca(1024, BARRO), ios / "icono-1024.png")
    # El icono oscuro y el translúcido de iOS 18, para que no se vea un parche
    # naranja pegado cuando el sistema está en modo oscuro.
    guarda(marca(1024, CARBON, circulo=BARRO, check=CARBON), ios / "icono-1024-oscuro.png")


if __name__ == "__main__":
    main()
