#!/usr/bin/env python3
"""EL PERFIL DE FIRMA DE CADA PAQUETE, DENTRO DEL PROYECTO.

Codemagic baja los perfiles pero no siempre los mete en el `project.pbxproj`:
su analizador es para el formato viejo y este proyecto está en el de Xcode 16+
(carpetas sincronizadas, objectVersion 77). Cuando no los mete, no avisa, y el
archivado se cae después con «requires a provisioning profile».

Pasárselo a `xcodebuild` por la línea de órdenes tampoco sirve ya: eso pone EL
MISMO perfil para todos los objetivos, y la app y la extensión del widget son
dos paquetes distintos con dos perfiles distintos.

Así que se escriben aquí, uno por objetivo, emparejando cada configuración
Release con el perfil cuyo `application-identifier` termina en su
`PRODUCT_BUNDLE_IDENTIFIER`. Emparejar por el id del paquete y no por el nombre
del archivo es lo que hace que esto siga funcionando cuando Apple renombra los
perfiles, que lo hace.

    python3 scripts/firma.py ruta/al/project.pbxproj  id.de.la.app  id.de.la.extension
"""
import os
import plistlib
import re
import subprocess
import sys
from pathlib import Path

CARPETAS = [
    Path.home() / "Library/MobileDevice/Provisioning Profiles",
    Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
]


def perfiles():
    """Lo que hay bajado: id del paquete → nombre del perfil."""
    encontrados = {}
    for carpeta in CARPETAS:
        for p in sorted(carpeta.glob("*.mobileprovision")) if carpeta.is_dir() else []:
            try:
                crudo = subprocess.run(["security", "cms", "-D", "-i", str(p)],
                                       capture_output=True, check=True).stdout
                d = plistlib.loads(crudo)
            except Exception as e:                       # noqa: BLE001
                print(f"  (no pude leer {p.name}: {e})")
                continue
            app_id = d.get("Entitlements", {}).get("application-identifier", "")
            # Viene con el prefijo del equipo delante: «B375R2BWX8.do.com.fente.cuadre».
            paquete = app_id.split(".", 1)[1] if "." in app_id else app_id
            if paquete and not paquete.endswith("*"):
                encontrados[paquete] = d.get("Name", "")
    return encontrados


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2

    ruta = Path(sys.argv[1])
    paquetes = sys.argv[2:]
    texto = ruta.read_text()

    hay = perfiles()
    print("Perfiles bajados:")
    for k, v in sorted(hay.items()):
        print(f"  {k} → {v}")

    faltan = [b for b in paquetes if b not in hay]
    if faltan:
        print()
        print("No bajó perfil para: " + ", ".join(faltan))
        print("Revisa que el App ID esté registrado en el portal de Apple y que")
        print("tenga las capacidades que pide el .entitlements (Sign in with")
        print("Apple y App Groups).")
        return 1

    # Cada bloque `buildSettings = { … };` de una configuración. Se le pone el
    # perfil al que lleve dentro el id del paquete que toca.
    puestos = 0
    for paquete in paquetes:
        nombre = hay[paquete]
        patron = re.compile(
            r"(buildSettings = \{)((?:(?!\n\t\t\t\};)[\s\S])*?PRODUCT_BUNDLE_IDENTIFIER = "
            + re.escape(paquete) + r";(?:(?!\n\t\t\t\};)[\s\S])*?)(\n\t\t\t\};)")

        def pon(m):
            nonlocal puestos
            cuerpo = m.group(2)
            # Solo la configuración que firma a mano. En Debug la firma es
            # automática y ponerle un perfil de distribución ahí solo estorba.
            if "CODE_SIGN_STYLE = Manual" not in cuerpo:
                return m.group(0)
            if "PROVISIONING_PROFILE_SPECIFIER" in cuerpo:
                cuerpo = re.sub(r'PROVISIONING_PROFILE_SPECIFIER = [^;]*;',
                                f'PROVISIONING_PROFILE_SPECIFIER = "{nombre}";', cuerpo)
            else:
                # El cuerpo termina justo antes del salto de línea que cierra el
                # bloque, así que la línea nueva empieza por el salto.
                cuerpo += f'\n\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = "{nombre}";'
            puestos += 1
            return m.group(1) + cuerpo + m.group(3)

        texto = patron.sub(pon, texto)
        print(f"{paquete}: «{nombre}»")

    if puestos == 0:
        print("No encontré ninguna configuración que tocar. ¿Cambió el proyecto?")
        return 1

    ruta.write_text(texto)
    print(f"{puestos} configuración(es) con su perfil.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
