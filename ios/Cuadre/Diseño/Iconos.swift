import SwiftUI

/// LOS ICONOS.
///
/// Los mismos trazos del diseño, dibujados a mano en una rejilla de 24×24 y
/// trazados con el grosor y las puntas redondas del original. Son trazos y no
/// símbolos del sistema porque los del sistema tienen otro peso y otra caja, y
/// mezclarlos con estos se nota a simple vista.
///
/// Todo es `Path` y `stroke`: sin imágenes, sin catálogo y sin nada que pese.
enum Icono: String {
    case lista, bolsa, balanza, circuloCheck
    case check, mas, equis, chevron, atras, abajo
    case columnas, camara, chispa, engranaje, compartir, documento, microfono
    case papelera, lapiz, buscar, reloj, persona, salir, enlace, aviso, whatsapp

    /// El trazo, en la caja de 24×24.
    fileprivate func trazos() -> [Path] {
        var ps: [Path] = []
        func p(_ dibuja: (inout Path) -> Void) { var x = Path(); dibuja(&x); ps.append(x) }
        func linea(_ a: CGPoint, _ b: CGPoint) { p { $0.move(to: a); $0.addLine(to: b) } }
        func puntos(_ pts: [CGPoint]) {
            p { path in
                path.move(to: pts[0])
                for q in pts.dropFirst() { path.addLine(to: q) }
            }
        }
        func circulo(_ c: CGPoint, _ r: CGFloat) {
            p { $0.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }
        }

        switch self {
        case .lista:
            puntos([.init(x: 3, y: 17), .init(x: 5, y: 19), .init(x: 9, y: 15)])
            puntos([.init(x: 3, y: 7), .init(x: 5, y: 9), .init(x: 9, y: 5)])
            linea(.init(x: 13, y: 6), .init(x: 21, y: 6))
            linea(.init(x: 13, y: 12), .init(x: 21, y: 12))
            linea(.init(x: 13, y: 18), .init(x: 21, y: 18))

        case .bolsa:
            p { path in
                path.move(to: .init(x: 6, y: 2))
                path.addLine(to: .init(x: 3, y: 6))
                path.addLine(to: .init(x: 3, y: 20))
                path.addQuadCurve(to: .init(x: 5, y: 22), control: .init(x: 3, y: 22))
                path.addLine(to: .init(x: 19, y: 22))
                path.addQuadCurve(to: .init(x: 21, y: 20), control: .init(x: 21, y: 22))
                path.addLine(to: .init(x: 21, y: 6))
                path.addLine(to: .init(x: 18, y: 2))
                path.closeSubpath()
            }
            linea(.init(x: 3, y: 6), .init(x: 21, y: 6))
            p { path in
                path.move(to: .init(x: 16, y: 10))
                path.addQuadCurve(to: .init(x: 8, y: 10), control: .init(x: 12, y: 16))
            }

        case .balanza:
            p { path in
                path.move(to: .init(x: 16, y: 16)); path.addLine(to: .init(x: 19, y: 8))
                path.addLine(to: .init(x: 22, y: 16))
                path.addQuadCurve(to: .init(x: 16, y: 16), control: .init(x: 19, y: 19))
            }
            p { path in
                path.move(to: .init(x: 2, y: 16)); path.addLine(to: .init(x: 5, y: 8))
                path.addLine(to: .init(x: 8, y: 16))
                path.addQuadCurve(to: .init(x: 2, y: 16), control: .init(x: 5, y: 19))
            }
            linea(.init(x: 7, y: 21), .init(x: 17, y: 21))
            linea(.init(x: 12, y: 3), .init(x: 12, y: 21))
            p { path in
                path.move(to: .init(x: 3, y: 7)); path.addLine(to: .init(x: 5, y: 7))
                path.addCurve(to: .init(x: 12, y: 5), control1: .init(x: 7, y: 7), control2: .init(x: 10, y: 6))
                path.addCurve(to: .init(x: 19, y: 7), control1: .init(x: 14, y: 6), control2: .init(x: 17, y: 7))
                path.addLine(to: .init(x: 21, y: 7))
            }

        case .circuloCheck:
            circulo(.init(x: 12, y: 12), 10)
            puntos([.init(x: 9, y: 12), .init(x: 11, y: 14), .init(x: 15, y: 10)])

        case .check:
            puntos([.init(x: 4, y: 12), .init(x: 9, y: 17), .init(x: 20, y: 6)])

        case .mas:
            linea(.init(x: 5, y: 12), .init(x: 19, y: 12))
            linea(.init(x: 12, y: 5), .init(x: 12, y: 19))

        case .equis:
            linea(.init(x: 18, y: 6), .init(x: 6, y: 18))
            linea(.init(x: 6, y: 6), .init(x: 18, y: 18))

        case .chevron:
            puntos([.init(x: 9, y: 18), .init(x: 15, y: 12), .init(x: 9, y: 6)])

        case .abajo:
            puntos([.init(x: 6, y: 9), .init(x: 12, y: 15), .init(x: 18, y: 9)])

        case .atras:
            puntos([.init(x: 12, y: 19), .init(x: 5, y: 12), .init(x: 12, y: 5)])
            linea(.init(x: 19, y: 12), .init(x: 5, y: 12))

        case .columnas:
            linea(.init(x: 21, y: 4), .init(x: 14, y: 4))
            linea(.init(x: 10, y: 4), .init(x: 3, y: 4))
            linea(.init(x: 21, y: 12), .init(x: 12, y: 12))
            linea(.init(x: 8, y: 12), .init(x: 3, y: 12))
            linea(.init(x: 21, y: 20), .init(x: 16, y: 20))
            linea(.init(x: 12, y: 20), .init(x: 3, y: 20))
            linea(.init(x: 14, y: 2), .init(x: 14, y: 6))
            linea(.init(x: 8, y: 10), .init(x: 8, y: 14))
            linea(.init(x: 16, y: 18), .init(x: 16, y: 22))

        case .camara:
            p { path in
                path.addRoundedRect(in: CGRect(x: 2, y: 6, width: 20, height: 15), cornerSize: .init(width: 3, height: 3))
            }
            puntos([.init(x: 8, y: 6), .init(x: 9.5, y: 3), .init(x: 14.5, y: 3), .init(x: 16, y: 6)])
            circulo(.init(x: 12, y: 13.5), 3.6)

        case .microfono:
            p { path in
                path.addRoundedRect(in: CGRect(x: 9, y: 2, width: 6, height: 11),
                                    cornerSize: .init(width: 3, height: 3))
            }
            p { path in
                path.move(to: .init(x: 5, y: 11))
                path.addCurve(to: .init(x: 19, y: 11), control1: .init(x: 5, y: 18), control2: .init(x: 19, y: 18))
            }
            linea(.init(x: 12, y: 18), .init(x: 12, y: 22))

        case .chispa:
            p { path in
                path.move(to: .init(x: 12, y: 3))
                path.addLine(to: .init(x: 14, y: 9.6))
                path.addLine(to: .init(x: 20.5, y: 11.6))
                path.addLine(to: .init(x: 14, y: 13.6))
                path.addLine(to: .init(x: 12, y: 20))
                path.addLine(to: .init(x: 10, y: 13.6))
                path.addLine(to: .init(x: 3.5, y: 11.6))
                path.addLine(to: .init(x: 10, y: 9.6))
                path.closeSubpath()
            }

        case .engranaje:
            circulo(.init(x: 12, y: 12), 3.2)
            for i in 0..<8 {
                let a = Double(i) * .pi / 4
                let c = CGPoint(x: 12 + cos(a) * 8, y: 12 + sin(a) * 8)
                let d = CGPoint(x: 12 + cos(a) * 5.6, y: 12 + sin(a) * 5.6)
                linea(d, c)
            }

        case .compartir:
            linea(.init(x: 12, y: 3), .init(x: 12, y: 15))
            puntos([.init(x: 8, y: 7), .init(x: 12, y: 3), .init(x: 16, y: 7)])
            p { path in
                path.move(to: .init(x: 5, y: 12))
                path.addLine(to: .init(x: 5, y: 20))
                path.addLine(to: .init(x: 19, y: 20))
                path.addLine(to: .init(x: 19, y: 12))
            }

        case .documento:
            p { path in
                path.move(to: .init(x: 14, y: 2)); path.addLine(to: .init(x: 6, y: 2))
                path.addLine(to: .init(x: 6, y: 22)); path.addLine(to: .init(x: 19, y: 22))
                path.addLine(to: .init(x: 19, y: 7)); path.closeSubpath()
            }
            puntos([.init(x: 14, y: 2), .init(x: 14, y: 7), .init(x: 19, y: 7)])
            linea(.init(x: 9, y: 13), .init(x: 16, y: 13))
            linea(.init(x: 9, y: 17), .init(x: 16, y: 17))

        case .papelera:
            linea(.init(x: 3, y: 6), .init(x: 21, y: 6))
            p { path in
                path.move(to: .init(x: 5, y: 6)); path.addLine(to: .init(x: 6, y: 21))
                path.addLine(to: .init(x: 18, y: 21)); path.addLine(to: .init(x: 19, y: 6))
            }
            puntos([.init(x: 9, y: 6), .init(x: 9, y: 3), .init(x: 15, y: 3), .init(x: 15, y: 6)])

        case .lapiz:
            puntos([.init(x: 4, y: 20), .init(x: 4, y: 16), .init(x: 16, y: 4), .init(x: 20, y: 8), .init(x: 8, y: 20), .init(x: 4, y: 20)])
            linea(.init(x: 13, y: 7), .init(x: 17, y: 11))

        case .buscar:
            circulo(.init(x: 11, y: 11), 7)
            linea(.init(x: 16, y: 16), .init(x: 21, y: 21))

        case .reloj:
            circulo(.init(x: 12, y: 12), 9)
            puntos([.init(x: 12, y: 7), .init(x: 12, y: 12), .init(x: 16, y: 14)])

        case .persona:
            circulo(.init(x: 12, y: 8), 4)
            p { path in
                path.move(to: .init(x: 4, y: 21))
                path.addCurve(to: .init(x: 20, y: 21), control1: .init(x: 5, y: 15), control2: .init(x: 19, y: 15))
            }

        case .salir:
            p { path in
                path.move(to: .init(x: 14, y: 3)); path.addLine(to: .init(x: 5, y: 3))
                path.addLine(to: .init(x: 5, y: 21)); path.addLine(to: .init(x: 14, y: 21))
            }
            linea(.init(x: 10, y: 12), .init(x: 21, y: 12))
            puntos([.init(x: 17, y: 8), .init(x: 21, y: 12), .init(x: 17, y: 16)])

        case .enlace:
            p { path in
                path.move(to: .init(x: 10, y: 14))
                path.addCurve(to: .init(x: 15, y: 14), control1: .init(x: 12, y: 17), control2: .init(x: 13, y: 17))
                path.addLine(to: .init(x: 18, y: 11))
                path.addCurve(to: .init(x: 18, y: 5), control1: .init(x: 20, y: 9), control2: .init(x: 20, y: 6))
                path.addCurve(to: .init(x: 13, y: 6), control1: .init(x: 16, y: 3), control2: .init(x: 14, y: 4))
            }
            p { path in
                path.move(to: .init(x: 14, y: 10))
                path.addCurve(to: .init(x: 9, y: 10), control1: .init(x: 12, y: 7), control2: .init(x: 11, y: 7))
                path.addLine(to: .init(x: 6, y: 13))
                path.addCurve(to: .init(x: 6, y: 19), control1: .init(x: 4, y: 15), control2: .init(x: 4, y: 18))
                path.addCurve(to: .init(x: 11, y: 18), control1: .init(x: 8, y: 21), control2: .init(x: 10, y: 20))
            }

        case .aviso:
            p { path in
                path.move(to: .init(x: 12, y: 3)); path.addLine(to: .init(x: 22, y: 20))
                path.addLine(to: .init(x: 2, y: 20)); path.closeSubpath()
            }
            linea(.init(x: 12, y: 10), .init(x: 12, y: 14))
            linea(.init(x: 12, y: 17), .init(x: 12, y: 17.2))

        case .whatsapp:
            p { path in
                path.move(to: .init(x: 3, y: 21)); path.addLine(to: .init(x: 4.6, y: 16.2))
                path.addArc(center: .init(x: 12, y: 12), radius: 9,
                            startAngle: .degrees(130), endAngle: .degrees(60),
                            clockwise: false)
                path.closeSubpath()
            }
            p { path in
                path.move(to: .init(x: 9, y: 9.5))
                path.addCurve(to: .init(x: 15, y: 15), control1: .init(x: 9.5, y: 13), control2: .init(x: 11.5, y: 14.8))
                path.addLine(to: .init(x: 15.5, y: 13.5))
            }
        }
        return ps
    }
}

/// El icono, ya dibujado. `grosor` sigue al del diseño: 2.75 de 24.
struct IconoView: View {
    let icono: Icono
    var tamano: CGFloat = 22
    var grosor: CGFloat = 2.75

    var body: some View {
        Canvas { ctx, size in
            let k = size.width / 24
            ctx.scaleBy(x: k, y: k)
            let estilo = StrokeStyle(lineWidth: grosor, lineCap: .round, lineJoin: .round)
            // `.foreground` es el color que traiga el entorno, así que
            // `IconoView(...).foregroundStyle(...)` funciona igual que en un
            // `Image`, y un icono dentro de un botón hereda el color del botón.
            for t in icono.trazos() {
                ctx.stroke(t, with: .foreground, style: estilo)
            }
        }
        .frame(width: tamano, height: tamano)
        .accessibilityHidden(true)
    }
}

/// La marca: el círculo con el check y el punto de la otra mitad.
///
/// El check solo se dibuja cuando hay sitio. En la cabecera, a 34 puntos, el
/// diseño lo quita a propósito: a ese tamaño el trazo se convierte en una mancha
/// y el círculo limpio se reconoce mejor.
struct Marca: View {
    @Environment(\.tema) private var tema
    var tamano: CGFloat = 34
    var conCheck: Bool?

    private var dibujaCheck: Bool { conCheck ?? (tamano >= 44) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle().fill(tema.acento)
                if dibujaCheck {
                    IconoView(icono: .check, tamano: tamano * 0.44, grosor: 3.2)
                        .foregroundStyle(tema.oscuro ? tema.neutral900 : tema.fondo)
                }
            }
            .frame(width: tamano * 0.88, height: tamano * 0.88)
            .frame(width: tamano, height: tamano, alignment: .topLeading)

            Circle()
                .fill(tema.acento2)
                .frame(width: tamano * 0.38, height: tamano * 0.38)
                .overlay(Circle().strokeBorder(tema.fondo, lineWidth: tamano * 0.09))
        }
        .frame(width: tamano, height: tamano)
        .accessibilityHidden(true)
    }
}
