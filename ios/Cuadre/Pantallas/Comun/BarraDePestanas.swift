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
