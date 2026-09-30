import Foundation

/// LAS UNIDADES.
///
/// Las nueve con las que se compra en RD. Las tres primeras pesan, y eso
/// importa: si una unidad pesa, la app puede decirte a cuánto te sale la libra
/// aunque hayas comprado en kilos, que es la cuenta que nadie hace de cabeza en
/// el mostrador.
struct Unidad: Identifiable, Hashable {
    let id: String          // «lb», «kg», … el mismo texto que viaja al servidor
    let nombre: String      // «libra», para «precio por libra»
    let etiqueta: String    // «Libra», para el menú
    /// Cuántas libras es una de estas. `nil` si no es cuestión de peso.
    let enLibras: Double?

    var pesa: Bool { enLibras != nil }

    static let todas: [Unidad] = [
        .init(id: "lb", nombre: "libra", etiqueta: "Libra", enLibras: 1),
        .init(id: "kg", nombre: "kilo", etiqueta: "Kilo", enLibras: 2.20462),
        .init(id: "oz", nombre: "onza", etiqueta: "Onza", enLibras: 0.0625),
        .init(id: "ud", nombre: "unidad", etiqueta: "Unidad", enLibras: nil),
        .init(id: "doc", nombre: "docena", etiqueta: "Docena", enLibras: nil),
        .init(id: "paq", nombre: "paquete", etiqueta: "Paquete", enLibras: nil),
        .init(id: "saco", nombre: "saco", etiqueta: "Saco", enLibras: nil),
        .init(id: "gal", nombre: "galón", etiqueta: "Galón", enLibras: nil),
        .init(id: "L", nombre: "litro", etiqueta: "Litro", enLibras: nil),
    ]

    /// La unidad de una clave. Si la clave no existe —porque vino de un
    /// servidor más nuevo— se cae a «unidad», que es la que no promete nada.
    static func de(_ clave: String) -> Unidad {
        todas.first { $0.id == clave } ?? todas[3]
    }

    /// El paso del botón de más y menos: media libra cuando pesa, una unidad
    /// cuando no. Nadie compra media docena de huevos tocando un botón.
    var paso: Double { pesa ? 0.5 : 1 }
}

/// Las categorías con las que se agrupa el gasto al mandarlo a Chinola.
enum Categoria {
    static let todas = [
        "Víveres", "Carnes y pescados", "Lácteos y huevos", "Frutas y vegetales",
        "Panadería", "Limpieza", "Higiene", "Bebidas", "Ferretería", "Otros",
    ]
    static let porDefecto = "Otros"
}

/// Las tres tarifas de venta. El nombre lo puede cambiar quien vende.
enum Tarifa: String, CaseIterable, Codable {
    case detal, mayor, especial

    var etiqueta: String {
        switch self {
        case .detal: return "Detal"
        case .mayor: return "Mayor"
        case .especial: return "Especial"
        }
    }
}
