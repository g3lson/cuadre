import SwiftUI
import UIKit

/// LAS PIEZAS.
///
/// Los botones, las tarjetas y las filas que se repiten en catorce pantallas.
/// Están aquí y no copiadas en cada vista porque el diseño las define una vez:
/// pastilla, 52 de alto, texto en la tipografía de titulares.

// MARK: - Botones

struct BotonPrincipal: ButtonStyle {
    @Environment(\.tema) private var tema
    @Environment(\.isEnabled) private var activo
    var alto: CGFloat = 54

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(tema.texto(16, .heavy))
            .foregroundStyle(tema.sobreAcento)
            .frame(maxWidth: .infinity, minHeight: alto)
            .background(configuration.isPressed ? tema.acento600 : tema.acento, in: Capsule())
            .opacity(activo ? 1 : 0.45)
            .contentShape(Capsule())
    }
}

struct BotonSuave: ButtonStyle {
    @Environment(\.tema) private var tema
    @Environment(\.isEnabled) private var activo
    var alto: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(tema.texto(16, .bold))
            .foregroundStyle(tema.texto)
            .frame(maxWidth: .infinity, minHeight: alto)
            .background(configuration.isPressed ? tema.neutral300 : tema.superficie, in: Capsule())
            .opacity(activo ? 1 : 0.45)
            .contentShape(Capsule())
    }
}

struct BotonFantasma: ButtonStyle {
    @Environment(\.tema) private var tema

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(tema.texto(15, .bold))
            .foregroundStyle(tema.acento700)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(configuration.isPressed ? tema.acento100 : .clear, in: Capsule())
            .contentShape(Capsule())
    }
}

/// El botón redondo de la barra superior: 44×44, que es el mínimo que se toca bien.
struct BotonRedondo: ButtonStyle {
    @Environment(\.tema) private var tema
    var relleno: Color?
    var tinta: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tinta ?? tema.texto)
            .frame(width: 44, height: 44)
            .background(relleno ?? tema.superficie, in: Circle())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Circle())
    }
}

// MARK: - Contenedores

/// La tarjeta de siempre: superficie, esquinas muy redondeadas, 16 de aire.
struct Tarjeta<Contenido: View>: View {
    @Environment(\.tema) private var tema
    var relleno: CGFloat = 16
    var fondo: Color?
    var radio: CGFloat = 26
    @ViewBuilder var contenido: Contenido

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { contenido }
            .padding(relleno)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fondo ?? tema.superficie, in: RoundedRectangle(cornerRadius: radio, style: .continuous))
    }
}

/// El rótulo en versalitas que separa secciones.
struct Rotulo: View {
    @Environment(\.tema) private var tema
    let texto: String
    var color: Color?

    init(_ texto: String, color: Color? = nil) { self.texto = texto; self.color = color }

    var body: some View {
        Text(texto.uppercased())
            .font(tema.rotulo)
            .tracking(1)
            .foregroundStyle(color ?? tema.neutral700)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// La pastilla de estado («Comprando ahora», «Despachando en vivo»).
struct Etiqueta: View {
    @Environment(\.tema) private var tema
    let texto: String
    var fondo: Color?
    var tinta: Color?
    var punto: Color?

    var body: some View {
        HStack(spacing: 7) {
            if let punto {
                Circle().fill(punto).frame(width: 8, height: 8)
            }
            Text(texto.uppercased())
                .font(tema.texto(12, .heavy))
                .tracking(1)
        }
        .foregroundStyle(tinta ?? tema.acento2_800)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(fondo ?? tema.acento2_200, in: Capsule())
    }
}

/// Una fila de ajuste: nombre a la izquierda, valor o control a la derecha.
struct FilaAjuste<Derecha: View>: View {
    @Environment(\.tema) private var tema
    let titulo: String
    var detalle: String?
    var ultima: Bool = false
    @ViewBuilder var derecha: Derecha

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo).font(tema.texto(15, .bold))
                    if let detalle {
                        Text(detalle).font(tema.texto(13)).foregroundStyle(tema.neutral700)
                    }
                }
                Spacer(minLength: 8)
                derecha
            }
            .frame(minHeight: 56)
            if !ultima {
                Rectangle().fill(tema.divisor).frame(height: 1)
            }
        }
    }
}

/// El grupo de filas de ajuste, con su fondo de superficie y sus esquinas.
struct Grupo<Contenido: View>: View {
    @Environment(\.tema) private var tema
    @ViewBuilder var contenido: Contenido

    var body: some View {
        VStack(spacing: 0) { contenido }
            .padding(.horizontal, 16)
            .background(tema.superficie, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

/// El valor gris con el chevron, para las filas que llevan a otra pantalla.
struct ValorYChevron: View {
    @Environment(\.tema) private var tema
    let texto: String

    var body: some View {
        HStack(spacing: 4) {
            Text(texto).font(tema.texto(14)).foregroundStyle(tema.neutral700)
            IconoView(icono: .chevron, tamano: 14, grosor: 3)
                .foregroundStyle(tema.neutral500)
        }
    }
}

/// El campo de texto de la app: pastilla, 50 de alto, sin borde.
struct Campo: View {
    @Environment(\.tema) private var tema
    let marcador: String
    @Binding var valor: String
    var peso: Font.Weight = .regular
    var tamano: CGFloat = 16
    var teclado: UIKeyboardType = .default

    var body: some View {
        TextField(marcador, text: $valor)
            .font(tema.texto(tamano, peso))
            .foregroundStyle(tema.texto)
            .keyboardType(teclado)
            .padding(.horizontal, 18)
            .frame(minHeight: 50)
            .background(tema.superficie, in: Capsule())
    }
}

/// El interruptor, con el verde de «cuadró» en vez del azul del sistema.
struct Interruptor: View {
    @Environment(\.tema) private var tema
    @Binding var encendido: Bool

    var body: some View {
        Toggle("", isOn: $encendido)
            .labelsHidden()
            .tint(tema.acento2_700)
    }
}

/// El círculo de marcar producto: vacío cuando falta, relleno con el check cuando está en el carrito.
struct Marcador: View {
    @Environment(\.tema) private var tema
    let puesto: Bool
    var tamano: CGFloat = 24

    var body: some View {
        ZStack {
            if puesto {
                Circle().fill(tema.acento2_700)
                IconoView(icono: .check, tamano: tamano * 0.6, grosor: 3.5)
                    .foregroundStyle(tema.oscuro ? tema.neutral900 : tema.fondo)
            } else {
                Circle().strokeBorder(tema.neutral500, lineWidth: 2.5)
            }
        }
        .frame(width: tamano, height: tamano)
    }
}

/// El radio de las listas de opciones («Pasarlo a la próxima compra»).
struct Radio: View {
    @Environment(\.tema) private var tema
    let elegido: Bool

    var body: some View {
        Circle()
            .strokeBorder(elegido ? tema.acento2_700 : tema.neutral500, lineWidth: elegido ? 7 : 2.5)
            .frame(width: 22, height: 22)
    }
}

/// La barra de progreso del presupuesto.
struct Barra: View {
    @Environment(\.tema) private var tema
    let porcentaje: Double
    var color: Color
    var pista: Color?
    var alto: CGFloat = 10

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(pista ?? tema.superficie)
                Capsule().fill(color)
                    .frame(width: max(0, min(1, porcentaje)) * g.size.width)
            }
        }
        .frame(height: alto)
    }
}

// MARK: - Avisos

/// El cartelito que aparece arriba y se va solo. Sin botón de cerrar: es un
/// aviso, no una decisión.
struct Aviso: Identifiable, Equatable {
    enum Clase { case bien, mal, info }
    let id = UUID()
    let texto: String
    var clase: Clase = .info
    /// Lo que se puede deshacer, si se puede. Aparece como un botón al lado del
    /// texto y desaparece con el aviso: deshacer algo de hace diez minutos no es
    /// deshacer, es editar.
    var accion: String?
    var alTocar: (() -> Void)?

    static func == (a: Aviso, b: Aviso) -> Bool { a.id == b.id }
}

struct AvisoView: View {
    @Environment(\.tema) private var tema
    let aviso: Aviso

    private var fondo: Color {
        switch aviso.clase {
        case .bien: return tema.acento2_200
        case .mal: return tema.acento200
        case .info: return tema.superficie
        }
    }
    private var tinta: Color {
        switch aviso.clase {
        case .bien: return tema.acento2_800
        case .mal: return tema.acento800
        case .info: return tema.texto
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            IconoView(icono: aviso.clase == .bien ? .check : (aviso.clase == .mal ? .aviso : .reloj),
                      tamano: 18, grosor: 3)
            Text(aviso.texto).font(tema.texto(14, .bold))
            Spacer(minLength: 0)
            if let accion = aviso.accion, let alTocar = aviso.alTocar {
                Button(accion, action: alTocar)
                    .font(tema.texto(14, .heavy))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(tinta.opacity(0.12), in: Capsule())
            }
        }
        .foregroundStyle(tinta)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(fondo, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.14), radius: 14, y: 5)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Atajos

extension View {
    /// El fondo de pantalla del tema, hasta los bordes.
    func fondoDelTema(_ tema: Tema) -> some View {
        background(tema.fondo.ignoresSafeArea())
    }

    /// El agarradero de las hojas que suben desde abajo.
    func hojaDeCuadre(_ tema: Tema) -> some View {
        self
            .background(tema.fondo)
            .presentationDragIndicator(.visible)
            .presentationBackground(tema.fondo)
    }
}
