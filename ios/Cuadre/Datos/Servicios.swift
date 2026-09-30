import Foundation
import UIKit

/// LO QUE SOLO PUEDE HACER EL SERVIDOR.
///
/// Tres cosas: leer con un modelo lo que dictaste o fotografiaste, hablar con
/// Chinola, y dibujar el reporte. Ninguna es imprescindible —la app entera
/// funciona sin ellas y sin señal— y por eso están juntas y aparte: son el borde
/// mojado, y el resto de la app no debe depender de que respondan.

// MARK: - La ayuda de la IA

enum IA {
    struct ProductoLeido: Decodable, Identifiable {
        var id: String { nombre + unidad + String(cantidad) }
        let nombre: String
        let unidad: String
        let cantidad: Double
        let precio: Double
        let nota: String
        let categoria: String
    }

    private struct RespuestaLista: Decodable { let productos: [ProductoLeido] }
    private struct RespuestaRecibo: Decodable {
        let tienda: String
        let fecha: String
        let total: Double
        let productos: [ProductoLeido]
    }
    struct Recibo {
        let tienda: String
        let total: Double
        let productos: [ProductoLeido]
    }

    private struct PeticionLista: Encodable {
        let texto: String
        let tienda: String
        let conocidos: [Conocido]
        struct Conocido: Encodable { let nombre: String; let unidad: String; let precio: Double }
    }
    private struct PeticionRecibo: Encodable { let imagen: String; let tipo: String }

    /// De «2 galones de leche y 5 libras de azúcar» a dos filas de lista.
    ///
    /// Se le pasan los productos que esta persona ya compra: así «leche» vuelve
    /// como «Leche entera» con su último precio en vez de como un producto nuevo
    /// sin precio, que es justo el trabajo que se quería ahorrar.
    static func lista(de texto: String, tienda: String, conocidos: [(String, String, Double)]) async throws -> [ProductoLeido] {
        let r: RespuestaLista = try await Api.shared.pide(
            "api/ia/lista", metodo: "POST",
            cuerpo: PeticionLista(
                texto: texto, tienda: tienda,
                conocidos: conocidos.map { .init(nombre: $0.0, unidad: $0.1, precio: $0.2) }))
        return r.productos
    }

    /// La foto del recibo. Se manda comprimida y reducida: un JPEG de 1600 px de
    /// lado se lee igual de bien que el original de doce megapíxeles y sube en
    /// una décima parte del tiempo, que en el parqueo del súper es la diferencia
    /// entre funcionar y no.
    static func recibo(_ imagen: UIImage) async throws -> Recibo {
        guard let jpeg = comprime(imagen) else { throw Api.Fallo.respuestaRara }
        let r: RespuestaRecibo = try await Api.shared.pide(
            "api/ia/recibo", metodo: "POST",
            cuerpo: PeticionRecibo(imagen: jpeg.base64EncodedString(), tipo: "image/jpeg"))
        return Recibo(tienda: r.tienda, total: r.total, productos: r.productos)
    }

    private static func comprime(_ imagen: UIImage, lado: CGFloat = 1600) -> Data? {
        let mayor = max(imagen.size.width, imagen.size.height)
        let escala = mayor > lado ? lado / mayor : 1
        let tamano = CGSize(width: imagen.size.width * escala, height: imagen.size.height * escala)
        let r = UIGraphicsImageRenderer(size: tamano)
        let reducida = r.image { _ in imagen.draw(in: CGRect(origin: .zero, size: tamano)) }
        return reducida.jpegData(compressionQuality: 0.72)
    }
}

// MARK: - Chinola

enum ChinolaApi {
    /// Tal como la devuelve Chinola: `medios` son las cuentas y las tarjetas
    /// juntas, ya con el prefijo (`cuenta:3`, `tarjeta:1`) que espera al anotar.
    struct Libreta: Decodable, Identifiable, Hashable {
        let id: String
        let nombre: String
        var tipo: String?
        var rol: String?
        var categorias: [String] = []
        var medios: [Medio] = []

        struct Medio: Decodable, Identifiable, Hashable {
            let id: String
            let nombre: String
        }

        /// Solo se puede anotar donde el rol lo permite; lo demás se enseña apagado.
        var puedeEscribir: Bool { ["Dueño", "Editor", "Registrador"].contains(rol ?? "") }
    }
    private struct RespuestaLibretas: Decodable { let libretas: [Libreta] }
    private struct RespuestaConectar: Decodable { let url: String }
    private struct PideConectar: Encodable { let vuelta: String }
    private struct FijaDestino: Encodable { let libreta: String; let medio: String; let cuenta: String }

    struct Linea: Encodable {
        let concepto: String
        let monto: Double
        var categoria: String?
        var tipo: String?
        var idempotencia: String?
    }
    private struct Envio: Encodable {
        let lineas: [Linea]
        let fecha: String
        var libreta: String?
        var medio: String?
    }
    struct Anotado: Decodable {
        struct Movimiento: Decodable { let id: String?; let concepto: String?; let repetido: Bool? }
        let movimientos: [Movimiento]
    }

    /// La dirección a la que mandar a la persona para que autorice. La abre la
    /// app en una ventana del sistema, no en un navegador aparte: así se ve el
    /// candado y el dominio de Chinola, que es lo único que distingue una
    /// pantalla de permiso de verdad de una copiada.
    static func urlParaConectar() async throws -> URL {
        let r: RespuestaConectar = try await Api.shared.pide(
            "api/chinola/conectar", metodo: "POST", cuerpo: PideConectar(vuelta: "cuadre://chinola"))
        guard let u = URL(string: r.url) else { throw Api.Fallo.respuestaRara }
        return u
    }

    static func libretas() async throws -> [Libreta] {
        let r: RespuestaLibretas = try await Api.shared.pide("api/chinola/destinos")
        return r.libretas
    }

    static func fija(libreta: String, medio: String, cuenta: String) async throws {
        let _: Vacio = try await Api.shared.pide(
            "api/chinola/destino", metodo: "PUT",
            cuerpo: FijaDestino(libreta: libreta, medio: medio, cuenta: cuenta))
    }

    static func anota(_ lineas: [Linea], fecha: Date, libreta: String?, medio: String?) async throws -> Anotado {
        try await Api.shared.pide(
            "api/chinola/enviar", metodo: "POST",
            cuerpo: Envio(lineas: lineas, fecha: Formato.fechaCorta(fecha), libreta: libreta, medio: medio))
    }

    static func desconecta() async throws {
        let _: Vacio = try await Api.shared.pide("api/chinola", metodo: "DELETE")
    }
}

// MARK: - Reportes

enum Reportes {
    struct Compartible: Decodable {
        let id: String
        let url: String
        var web: URL { URL(string: url)! }
        var pdf: URL { URL(string: url + ".pdf")! }
    }

    struct Producto: Encodable {
        let nombre: String, nota: String, unidad: String
        let cantidad: Double, precio: Double
    }
    struct Faltante: Encodable {
        let nombre: String, unidad: String
        let cantidad: Double, destino: String
    }
    struct DeCompra: Encodable {
        let titulo: String, tienda: String, fecha: String
        let presupuesto: Double, pagado: Double
        let productos: [Producto]
        let faltantes: [Faltante]
        var chinola: String?
    }
    struct EncargoReporte: Encodable {
        let cliente: String, producto: String, unidad: String, metodo: String
        let cantidad: Double, total: Double
    }
    struct DelCuadre: Encodable {
        let fecha: String
        let vendido: Double, costo: Double, comprado: Double, porCobrar: Double
        let encargos: [EncargoReporte]
    }

    private struct Sobre<T: Encodable>: Encodable { let clase: String; let datos: T }

    static func deCompra(_ d: DeCompra) async throws -> Compartible {
        try await Api.shared.pide("api/reportes", metodo: "POST", cuerpo: Sobre(clase: "compra", datos: d))
    }

    static func delCuadre(_ d: DelCuadre) async throws -> Compartible {
        try await Api.shared.pide("api/reportes", metodo: "POST", cuerpo: Sobre(clase: "cuadre", datos: d))
    }
}
