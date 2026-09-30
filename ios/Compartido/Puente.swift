import Foundation

/// LO QUE LA APP LE DEJA AL WIDGET.
///
/// El widget es otro proceso: no ve la base de datos de la app ni puede abrirla
/// cuando quiera. Lo que sí comparten es una carpeta —el grupo de aplicaciones—
/// y ahí la app deja un resumen diminuto cada vez que algo cambia.
///
/// Es a propósito un resumen y no los datos: el widget no tiene que decidir
/// nada, solo enseñar cuatro cifras. Si un día el modelo cambia, el widget
/// sigue leyendo esto y no hay que tocarlo.
public struct Resumen: Codable, Sendable {
    /// Lo que se está comprando ahora mismo, si hay algo abierto.
    public var lista: String = ""
    public var faltan: Int = 0
    public var llevados: Int = 0
    public var gastado: Double = 0
    public var presupuesto: Double = 0

    /// El día de venta abierto, si lo hay.
    public var venta: String = ""
    public var negocio: String = ""
    public var porDespachar: Int = 0
    public var cobrado: Double = 0

    public var moneda: String = "RD$"
    public var cuando: Date = .now

    public init() {}

    public var hayCompra: Bool { !lista.isEmpty }
    public var hayVenta: Bool { !venta.isEmpty }
    /// Cuánto del presupuesto va gastado, de 0 a 1. Sin presupuesto, nada.
    public var parte: Double {
        presupuesto > 0 ? min(1, gastado / presupuesto) : 0
    }
}

/// El buzón entre la app y el widget.
public enum Puente {
    /// El grupo de aplicaciones. Tiene que estar en los permisos de LOS DOS
    /// objetivos y activado en el App ID, o `containerURL` devuelve nil y el
    /// widget se queda siempre vacío sin decir por qué.
    public static let grupo = "group.do.com.fente.cuadre"

    private static var archivo: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: grupo)?
            .appending(path: "resumen.json")
    }

    public static func guarda(_ r: Resumen) {
        guard let archivo, let d = try? JSONEncoder().encode(r) else { return }
        try? d.write(to: archivo, options: .atomic)
    }

    public static func lee() -> Resumen? {
        guard let archivo, let d = try? Data(contentsOf: archivo) else { return nil }
        return try? JSONDecoder().decode(Resumen.self, from: d)
    }
}

/// Los pesos, cortos. El widget es pequeño y «RD$ 1,250» no cabe dos veces.
public func pesosCortos(_ n: Double, _ moneda: String) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.maximumFractionDigits = 0
    f.groupingSeparator = ","
    return "\(moneda) \(f.string(from: NSNumber(value: n)) ?? "0")"
}
