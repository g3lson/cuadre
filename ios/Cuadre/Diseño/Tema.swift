import SwiftUI

/// EL TEMA.
///
/// Tres estilos que cambian colores y tipografía y NADA más: la estructura de
/// cada pantalla es la misma en los tres. Por eso el tema es una tabla de
/// valores y no tres juegos de vistas — una pantalla se escribe una vez.
///
/// Los nombres son los del diseño (`acento`, `acento2`, las rampas 100–900) y no
/// nombres de intención tipo `colorDeBotón`: cuando el diseño dice
/// «acento-2-700», encontrarlo aquí tiene que ser inmediato.
struct Tema: Equatable, Identifiable {
    enum Clave: String, CaseIterable, Codable {
        case barro, mercado, noche
    }

    let id: Clave
    let nombre: String
    let descripcion: String
    /// Para la rueda de Ajustes: el color que representa al tema.
    let muestra: Color
    let oscuro: Bool

    let fondo: Color
    let superficie: Color
    let texto: Color
    let divisor: Color

    let acento: Color
    let acento100: Color
    let acento200: Color
    let acento300: Color
    let acento400: Color
    let acento600: Color
    let acento700: Color
    let acento800: Color

    let acento2: Color
    let acento2_100: Color
    let acento2_200: Color
    let acento2_300: Color
    let acento2_400: Color
    let acento2_700: Color
    let acento2_800: Color

    let neutral100: Color
    let neutral200: Color
    let neutral300: Color
    let neutral500: Color
    let neutral700: Color
    let neutral900: Color

    let fuenteTitulo: String
    let fuenteTituloGrueso: String
    let fuenteTexto: FamiliaTexto

    /// Las tipografías de texto vienen en cinco pesos, cada uno su archivo y su
    /// nombre PostScript. Se resuelven por peso para que las vistas pidan
    /// `.texto(15, .bold)` y no se aprendan catorce nombres de archivo.
    struct FamiliaTexto: Equatable {
        let regular: String, media: String, semi: String, negrita: String, extra: String

        func nombre(_ peso: Font.Weight) -> String {
            switch peso {
            case .medium: return media
            case .semibold: return semi
            case .bold: return negrita
            case .heavy, .black: return extra
            default: return regular
            }
        }
    }

    // MARK: - Los tres

    static let barro = Tema(
        id: .barro, nombre: "Barro", descripcion: "Cálido y redondeado",
        muestra: Color(hex: 0xc67139), oscuro: false,
        fondo: Color(hex: 0xf5ead8), superficie: Color(hex: 0xebddc5),
        texto: Color(hex: 0x201e1d), divisor: Color(hex: 0x201e1d).opacity(0.16),
        acento: Color(hex: 0xc67139),
        acento100: Color(hex: 0xfff2eb), acento200: Color(hex: 0xffe1d0),
        acento300: Color(hex: 0xffc6a5), acento400: Color(hex: 0xf6a06b),
        acento600: Color(hex: 0xb2622d), acento700: Color(hex: 0x8c491a),
        acento800: Color(hex: 0x643312),
        acento2: Color(hex: 0x7a8a5e),
        acento2_100: Color(hex: 0xf0fae1), acento2_200: Color(hex: 0xe1eecc),
        acento2_300: Color(hex: 0xccdbb2), acento2_400: Color(hex: 0xaebf92),
        acento2_700: Color(hex: 0x56633f), acento2_800: Color(hex: 0x3d472b),
        neutral100: Color(hex: 0xf9f4ed), neutral200: Color(hex: 0xeee7db),
        neutral300: Color(hex: 0xdcd3c4), neutral500: Color(hex: 0xa19786),
        neutral700: Color(hex: 0x645c50), neutral900: Color(hex: 0x2e2b25),
        fuenteTitulo: "Caprasimo-Regular", fuenteTituloGrueso: "Caprasimo-Regular",
        fuenteTexto: .init(regular: "Figtree-Regular", media: "Figtree-Medium",
                           semi: "Figtree-SemiBold", negrita: "Figtree-Bold", extra: "Figtree-ExtraBold")
    )

    static let mercado = Tema(
        id: .mercado, nombre: "Mercado", descripcion: "Claro y directo",
        muestra: Color(hex: 0xd9412b), oscuro: false,
        fondo: Color(hex: 0xf7f6f1), superficie: Color(hex: 0xeceae2),
        texto: Color(hex: 0x141414), divisor: Color(hex: 0x141414).opacity(0.10),
        acento: Color(hex: 0xd9412b),
        acento100: Color(hex: 0xfdece8), acento200: Color(hex: 0xf9d3ca),
        acento300: Color(hex: 0xf2a898), acento400: Color(hex: 0xe8705c),
        acento600: Color(hex: 0xb8321f), acento700: Color(hex: 0x962817),
        acento800: Color(hex: 0x6e1d10),
        acento2: Color(hex: 0x1c7c54),
        acento2_100: Color(hex: 0xe3f4ec), acento2_200: Color(hex: 0xc4e6d5),
        acento2_300: Color(hex: 0x93cfb2), acento2_400: Color(hex: 0x5bb38a),
        acento2_700: Color(hex: 0x115237), acento2_800: Color(hex: 0x0c3b28),
        neutral100: Color(hex: 0xffffff), neutral200: Color(hex: 0xe6e4dc),
        neutral300: Color(hex: 0xcfccc2), neutral500: Color(hex: 0x9a968b),
        neutral700: Color(hex: 0x5c5950), neutral900: Color(hex: 0x1a1a1a),
        fuenteTitulo: "BricolageGrotesque-Bold", fuenteTituloGrueso: "BricolageGrotesque-ExtraBold",
        fuenteTexto: .init(regular: "Onest-Regular", media: "Onest-Medium",
                           semi: "Onest-SemiBold", negrita: "Onest-Bold", extra: "Onest-ExtraBold")
    )

    static let noche = Tema(
        id: .noche, nombre: "Noche", descripcion: "Oscuro, ámbar y menta",
        muestra: Color(hex: 0xf0b24a), oscuro: true,
        fondo: Color(hex: 0x141518), superficie: Color(hex: 0x212328),
        texto: Color(hex: 0xf3efe7), divisor: Color(hex: 0xf3efe7).opacity(0.10),
        acento: Color(hex: 0xf0b24a),
        // En oscuro la rampa se invierte: los tonos «claros» (100, 200) son los
        // fondos tenues y los «oscuros» (700, 800) el texto que se lee encima.
        acento100: Color(hex: 0x2e2618), acento200: Color(hex: 0x4a3a1c),
        acento300: Color(hex: 0xf5c46e), acento400: Color(hex: 0xf0b24a),
        acento600: Color(hex: 0xf5c46e), acento700: Color(hex: 0xf5c46e),
        acento800: Color(hex: 0xfbe3b4),
        acento2: Color(hex: 0x6cc49a),
        acento2_100: Color(hex: 0x17291f), acento2_200: Color(hex: 0x1e3a2c),
        acento2_300: Color(hex: 0x8ad6b0), acento2_400: Color(hex: 0x6cc49a),
        acento2_700: Color(hex: 0x4e9c76), acento2_800: Color(hex: 0xa8e3c6),
        neutral100: Color(hex: 0xf3efe7), neutral200: Color(hex: 0x2b2e34),
        neutral300: Color(hex: 0x3a3e45), neutral500: Color(hex: 0x7c8088),
        neutral700: Color(hex: 0xa5a8ae), neutral900: Color(hex: 0x0b0c0e),
        fuenteTitulo: "YoungSerif-Regular", fuenteTituloGrueso: "YoungSerif-Regular",
        fuenteTexto: .init(regular: "Figtree-Regular", media: "Figtree-Medium",
                           semi: "Figtree-SemiBold", negrita: "Figtree-Bold", extra: "Figtree-ExtraBold")
    )

    static let todos: [Tema] = [.barro, .mercado, .noche]
    static func de(_ clave: Clave) -> Tema {
        todos.first { $0.id == clave } ?? .barro
    }

    // MARK: - Tipografía

    /// El titular. `relativeTo` mantiene el Texto Dinámico: alguien que puso el
    /// texto grande en Ajustes del sistema lo ve grande aquí también.
    func titulo(_ tamano: CGFloat, grueso: Bool = true) -> Font {
        .custom(grueso ? fuenteTituloGrueso : fuenteTitulo, size: tamano, relativeTo: .title)
    }

    func texto(_ tamano: CGFloat, _ peso: Font.Weight = .regular) -> Font {
        .custom(fuenteTexto.nombre(peso), size: tamano, relativeTo: .body)
    }

    /// El rótulo en versalitas que separa secciones («YA CUADRADAS»).
    var rotulo: Font { texto(12, .heavy) }

    /// El color que se lee encima del acento. En Noche el acento es un ámbar
    /// claro, así que encima va tinta oscura y no el fondo de la pantalla.
    var sobreAcento: Color { oscuro ? neutral900 : fondo }
    var sobreOscuro: Color { oscuro ? texto : neutral100 }
}

// MARK: - Color desde hexadecimal

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: 1
        )
    }
}

// MARK: - Llevarlo por el árbol de vistas

private struct ClaveTema: EnvironmentKey {
    static let defaultValue: Tema = .barro
}

extension EnvironmentValues {
    var tema: Tema {
        get { self[ClaveTema.self] }
        set { self[ClaveTema.self] = newValue }
    }
}
