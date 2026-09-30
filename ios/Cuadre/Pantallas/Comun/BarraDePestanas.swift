import SwiftUI
import UIKit

/// LA BARRA DE ABAJO.
///
/// Es la del diseño: una pastilla oscura flotando sobre el contenido, con la
/// pestaña activa en acento y con su nombre al lado. No es un `TabView` del
/// sistema porque la forma es esta y pelear con `UITabBar` para que se parezca
/// sale más caro que dibujarla.
enum Pestana: String, CaseIterable, Identifiable {
    case listas, tienda, ventas, cuadre
    var id: String { rawValue }

    var etiqueta: String {
        switch self {
        case .listas: return "Listas"
        case .tienda: return "En tienda"
        case .ventas: return "Ventas"
        case .cuadre: return "Cuadre"
        }
    }

    var icono: Icono {
        switch self {
        case .listas: return .lista
        case .tienda: return .bolsa
        case .ventas: return .balanza
        case .cuadre: return .circuloCheck
        }
    }
}

struct BarraDePestanas: View {
    @Environment(\.tema) private var tema
    @Binding var activa: Pestana
    /// Sin modo vendedor la pestaña de Ventas no aparece: quien solo compra no
    /// tiene por qué cargar con media app que no usa.
    var conVentas: Bool

    private var pestanas: [Pestana] {
        conVentas ? Pestana.allCases : Pestana.allCases.filter { $0 != .ventas }
    }

    var body: some View {
        // La activa toma el ancho que pida su nombre y las demás se reparten lo
        // que sobre. Con `maxWidth: .infinity` en las cuatro, «En tienda» se
        // parte en dos líneas dentro de su pastilla.
        HStack(spacing: 4) {
            ForEach(pestanas) { p in
                Button {
                    if activa != p {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.snappy(duration: 0.22)) { activa = p }
                    }
                } label: {
                    if activa == p {
                        HStack(spacing: 6) {
                            IconoView(icono: p.icono, tamano: 20)
                            Text(p.etiqueta)
                                .font(tema.texto(14, .heavy))
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .foregroundStyle(tema.sobreAcento)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 10)
                        .background(tema.acento, in: Capsule())
                        .fixedSize()
                    } else {
                        IconoView(icono: p.icono, tamano: 22)
                            .foregroundStyle(tema.neutral500)
                            .padding(10)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.plain)
                .layoutPriority(activa == p ? 1 : 0)
                .accessibilityLabel(p.etiqueta)
                .accessibilityAddTraits(activa == p ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 68)
        .background(tema.neutral900, in: Capsule())
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        .padding(.horizontal, 14)
    }
}

/// LA BARRA DE LADO, PARA EL IPAD.
///
/// En una pantalla grande la pastilla de abajo queda a un palmo del pulgar y se
/// come el ancho que se quería aprovechar. En horizontal, las pestañas van a un
/// raíl a la izquierda —donde el iPad las tiene siempre— y el contenido se
/// queda con la pantalla entera.
///
/// Es la misma pastilla oscura y los mismos iconos: no es otra barra, es la
/// misma puesta de canto.
struct RailDePestanas: View {
    @Environment(\.tema) private var tema
    @Binding var activa: Pestana
    var conVentas: Bool
    var alAbrirAjustes: () -> Void

    private var pestanas: [Pestana] {
        conVentas ? Pestana.allCases : Pestana.allCases.filter { $0 != .ventas }
    }

    var body: some View {
        VStack(spacing: 6) {
            Marca(tamano: 28)
                .padding(.top, 18)
                .padding(.bottom, 10)

            ForEach(pestanas) { p in
                Button {
                    if activa != p {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.snappy(duration: 0.22)) { activa = p }
                    }
                } label: {
                    VStack(spacing: 5) {
                        IconoView(icono: p.icono, tamano: 22)
                        Text(p.etiqueta)
                            .font(tema.texto(11, .heavy))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(activa == p ? tema.sobreAcento : tema.neutral500)
                    .frame(width: 74, height: 62)
                    .background(activa == p ? tema.acento : .clear,
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(p.etiqueta)
                .accessibilityAddTraits(activa == p ? [.isSelected, .isButton] : .isButton)
            }

            Spacer(minLength: 0)

            Button(action: alAbrirAjustes) {
                IconoView(icono: .engranaje, tamano: 22)
                    .foregroundStyle(tema.neutral500)
                    .frame(width: 74, height: 56)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ajustes")
            .padding(.bottom, 14)
        }
        .frame(width: 86)
        .frame(maxHeight: .infinity)
        // El color se sale por arriba y por abajo; el contenido NO. Poniendo
        // `ignoresSafeArea` al conjunto, la marca se montaba sobre el reloj.
        .background {
            tema.neutral900
                .overlay(alignment: .trailing) {
                    Rectangle().fill(.black.opacity(0.25)).frame(width: 1)
                }
                .ignoresSafeArea(edges: .vertical)
        }
    }
}

/// EL ANCHO EN EL QUE SE LEE.
///
/// En el iPad, una lista de la compra estirada a mil puntos de ancho es una
/// fila de nombre a la izquierda y precio a la derecha con un desierto en
/// medio: el ojo pierde el renglón. Se centra y se le pone tope.
///
/// La tabla de ventas es la excepción y por eso esto no se aplica a todo: ahí
/// las columnas sí quieren el ancho.
struct AnchoDeLectura: ViewModifier {
    var tope: CGFloat = 780
    func body(content: Content) -> some View {
        // `.infinity` significa «no lo toques»: en el iPhone no hay ancho que
        // sobre y meter dos `frame` de más solo complica el cálculo.
        if tope == .infinity {
            content
        } else {
            content
                .frame(maxWidth: tope)
                .frame(maxWidth: .infinity)
        }
    }
}

extension View {
    @ViewBuilder
    func anchoDeLectura(_ tope: CGFloat = 780) -> some View {
        modifier(AnchoDeLectura(tope: tope))
    }
}
