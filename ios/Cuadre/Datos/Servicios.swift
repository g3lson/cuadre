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
        var nombre: String
        var unidad: String
        var cantidad: Double
        var precio: Double
        var nota: String
        var categoria: String

        // A mano y no sintetizado: lo construye también el lector del teléfono,
        // que no decodifica nada.
        init(nombre: String, unidad: String, cantidad: Double,
             precio: Double, nota: String, categoria: String) {
            self.nombre = nombre; self.unidad = unidad; self.cantidad = cantidad
            self.precio = precio; self.nota = nota; self.categoria = categoria
        }
    }

    private struct RespuestaLista: Decodable { let productos: [ProductoLeido]; var modelo: String = "" }
    private struct RespuestaRecibo: Decodable {
        let tienda: String
        let fecha: String
        let total: Double
        let productos: [ProductoLeido]
        var modelo: String = ""
    }
    struct Recibo {
        var tienda: String
        var total: Double
        var productos: [ProductoLeido]
        /// Quién lo leyó. Vacío cuando lo hizo el propio teléfono.
        var modelo: String = ""

        init(tienda: String, total: Double, productos: [ProductoLeido], modelo: String = "") {
            self.tienda = tienda; self.total = total; self.productos = productos; self.modelo = modelo
        }
    }

    /// Lo que devuelve convertir un texto en productos, con quién lo hizo.
    struct ListaLeida {
        var productos: [ProductoLeido]
        var modelo: String
    }

    private struct PeticionLista: Encodable {
        let texto: String
        let tienda: String
        let conocidos: [Conocido]
        var modelo: String = ""
        struct Conocido: Encodable { let nombre: String; let unidad: String; let precio: Double }
    }
    private struct PeticionRecibo: Encodable { let imagen: String; let tipo: String; var modelo: String = "" }
    private struct PeticionReciboTexto: Encodable { let texto: String; var modelo: String = "" }

    /// De «2 galones de leche y 5 libras de azúcar» a dos filas de lista.
    ///
    /// Se le pasan los productos que esta persona ya compra: así «leche» vuelve
    /// como «Leche entera» con su último precio en vez de como un producto nuevo
    /// sin precio, que es justo el trabajo que se quería ahorrar.
    static func lista(de texto: String, tienda: String,
                      conocidos: [(String, String, Double)], modelo: String = "") async throws -> ListaLeida {
        let r: RespuestaLista = try await Api.shared.pide(
            "api/ia/lista", metodo: "POST",
            cuerpo: PeticionLista(
                texto: texto, tienda: tienda,
                conocidos: conocidos.map { .init(nombre: $0.0, unidad: $0.1, precio: $0.2) },
                modelo: modelo))
        return ListaLeida(productos: r.productos, modelo: r.modelo)
    }

    /// El texto que el propio teléfono sacó del recibo, para que el servidor lo
    /// ordene. Es el camino normal: dos kilobytes en vez de ciento veinte, y la
    /// foto no sale del aparato.
    static func recibo(deTexto texto: String, modelo: String = "") async throws -> Recibo {
        let r: RespuestaRecibo = try await Api.shared.pide(
            "api/ia/recibo-texto", metodo: "POST",
            cuerpo: PeticionReciboTexto(texto: texto, modelo: modelo))
        return Recibo(tienda: r.tienda, total: r.total, productos: r.productos, modelo: r.modelo)
    }

    /// La foto entera. Solo se usa cuando el teléfono no pudo leer letras en
    /// ella. Se manda comprimida y reducida: un JPEG de 1600 px de
    /// lado se lee igual de bien que el original de doce megapíxeles y sube en
    /// una décima parte del tiempo, que en el parqueo del súper es la diferencia
    /// entre funcionar y no.
    static func recibo(_ imagen: UIImage, modelo: String = "") async throws -> Recibo {
        guard let jpeg = comprime(imagen) else { throw Api.Fallo.respuestaRara }
        let r: RespuestaRecibo = try await Api.shared.pide(
            "api/ia/recibo", metodo: "POST",
            cuerpo: PeticionRecibo(imagen: jpeg.base64EncodedString(), tipo: "image/jpeg", modelo: modelo))
        return Recibo(tienda: r.tienda, total: r.total, productos: r.productos, modelo: r.modelo)
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
    static let casa = URL(string: "https://cuadre.fente.com.do")!

    struct Compartible: Decodable {
        let id: String
        let url: String
        // Si el servidor devolviera una dirección rara, mejor mandar a la
        // portada que caerse con un desenvuelto a la fuerza.
        var web: URL { URL(string: url) ?? Reportes.casa }
        var pdf: URL { URL(string: url + ".pdf") ?? Reportes.casa }
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
        var regalado: Double = 0
        /// A nombre de qué negocio se despachó el día. Corona el reporte: es
        /// el papel que se le enseña a un socio o a un cliente.
        var negocio: String = ""
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

// MARK: - Compartir una lista

enum Compartir {
    struct Miembro: Decodable, Identifiable, Hashable {
        var id: String { email }
        let email: String
        var nombre: String = ""
        var rol: String = "editor"
        /// `false` = invitado que todavía no ha entrado a Cuadre.
        var dentro: Bool = false
        var visto: String?

        var comoSeLlama: String { nombre.isEmpty ? String(email.split(separator: "@").first ?? "") : nombre }
        var inicial: String { Formato.inicial(comoSeLlama) }
        var esDueño: Bool { rol == "dueño" }
    }

    private struct RespuestaMiembros: Decodable { let miembros: [Miembro]; var yo: String? }
    private struct Invita: Encodable { let correo: String }
    struct Enlace: Decodable { let codigo: String; let url: String; let texto: String }
    struct Aceptada: Decodable { let listaId: String; var nombre: String?; var ambito: String? }

    /// Qué se comparte: una lista suelta o un grupo entero. Las rutas son las
    /// mismas y solo cambia esto.
    enum Ambito: String {
        case lista, grupo
        var camino: String { self == .grupo ? "grupos" : "listas" }
    }

    static func miembros(de id: String, _ ambito: Ambito = .lista) async throws -> [Miembro] {
        let r: RespuestaMiembros = try await Api.shared.pide("api/\(ambito.camino)/\(id)/miembros")
        return r.miembros
    }

    static func invita(_ correo: String, a id: String, _ ambito: Ambito = .lista) async throws -> [Miembro] {
        let r: RespuestaMiembros = try await Api.shared.pide(
            "api/\(ambito.camino)/\(id)/miembros", metodo: "POST", cuerpo: Invita(correo: correo))
        return r.miembros
    }

    static func quita(_ correo: String, de id: String, _ ambito: Ambito = .lista) async throws {
        let codificado = correo.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? correo
        let _: Vacio = try await Api.shared.pide(
            "api/\(ambito.camino)/\(id)/miembros/\(codificado)", metodo: "DELETE")
    }

    static func enlace(de id: String, _ ambito: Ambito = .lista) async throws -> Enlace {
        try await Api.shared.pide("api/\(ambito.camino)/\(id)/enlace", metodo: "POST", cuerpo: Vacio())
    }

    struct GrupoDelServidor: Decodable, Identifiable {
        let id: String
        let nombre: String
        var mio: Bool = false
        var miembros: Int = 1
    }
    private struct RespuestaGrupos: Decodable { let grupos: [GrupoDelServidor] }

    /// Cuánta gente hay en cada grupo. Los miembros no se sincronizan como los
    /// datos: son permisos, y los permisos los decide el servidor.
    static func grupos() async throws -> [GrupoDelServidor] {
        let r: RespuestaGrupos = try await Api.shared.pide("api/grupos")
        return r.grupos
    }

    static func acepta(_ codigo: String) async throws -> Aceptada {
        try await Api.shared.pide("api/grupos/invitacion/\(codigo)", metodo: "POST")
    }
}

// MARK: - Los modelos de IA que hay

extension IA {
    struct Modelo: Decodable, Identifiable, Hashable {
        let id: String
        let nombre: String
        var proveedor: String = ""
        var contexto: Int = 0
        /// De los que Cuadre trae puestos: comprobados y gratuitos.
        var puesto: Bool = false
    }
    struct Catalogo: Decodable {
        struct Puestos: Decodable { let texto: [String]; let foto: [String] }
        let puestos: Puestos
        let modelos: [Modelo]
    }

    static func modelos() async throws -> Catalogo {
        try await Api.shared.pide("api/ia/modelos")
    }
}
