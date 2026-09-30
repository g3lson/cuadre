import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// EL DÍA DE VENTA, EN LA PANTALLA BLOQUEADA.
///
/// Quien despacha no tiene las manos libres para desbloquear el teléfono cada
/// vez que quiere saber cuánto lleva. La actividad en vivo pone eso en la
/// pantalla bloqueada y en la isla: cuántos encargos faltan y cuánto se ha
/// cobrado, mientras el día esté abierto.
///
/// Vive en `Compartido/` porque el tipo tiene que ser el MISMO en la app, que
/// la arranca, y en la extensión, que la dibuja. Dos copias iguales no valen:
/// ActivityKit las compara por tipo y no por forma.
@available(iOS 16.1, *)
public struct VentaEnVivo: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var porDespachar: Int
        public var cobrado: Double
        public var ultimo: String

        public init(porDespachar: Int, cobrado: Double, ultimo: String = "") {
            self.porDespachar = porDespachar
            self.cobrado = cobrado
            self.ultimo = ultimo
        }
    }

    public var titulo: String
    public var negocio: String
    public var moneda: String

    public init(titulo: String, negocio: String = "", moneda: String = "RD$") {
        self.titulo = titulo
        self.negocio = negocio
        self.moneda = moneda
    }
}
#endif
