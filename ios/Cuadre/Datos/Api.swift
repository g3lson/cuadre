import Foundation
import UIKit

/// EL CLIENTE DE LA API.
///
/// Una sola puerta hacia el servidor. Todo lo que sale de la app pasa por aquí,
/// así que aquí está también el único sitio donde se decide qué es un error de
/// red —se reintenta luego— y qué es una sesión caída —hay que volver a entrar—.
/// Esa diferencia es la que evita que la app te eche fuera porque el ascensor
/// no tenía cobertura.
actor Api {
    static let shared = Api()

    /// La dirección pública.
    ///
    /// Es `cuadre.fente.com.do` y no `api.cuadre.…` por una razón concreta: el
    /// certificado gratuito de Cloudflare cubre `fente.com.do` y `*.fente.com.do`
    /// —UN nivel de subdominio—, así que un nombre de dos niveles no tiene
    /// certificado en el borde y el TLS falla antes de llegar a ninguna parte.
    /// La API vive en `/api` del mismo sitio que la portada.
    ///
    /// Se puede pisar desde el esquema de Xcode con `CUADRE_API` para probar
    /// contra el portátil sin tocar código.
    nonisolated static var base: URL {
        if let s = ProcessInfo.processInfo.environment["CUADRE_API"], let u = URL(string: s) { return u }
        if let s = Bundle.main.object(forInfoDictionaryKey: "CuadreAPI") as? String,
           !s.isEmpty, let u = URL(string: s) { return u }
        return URL(string: "https://cuadre.fente.com.do")!
    }

    private var testigo: String?

    private let sesion: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30
        c.timeoutIntervalForResource = 120
        // Que el sistema espere a que haya red en vez de fallar en el acto: en
        // el súper la señal va y viene, y un error inmediato solo obliga a
        // tocar el botón otra vez.
        c.waitsForConnectivity = true
        return URLSession(configuration: c)
    }()

    func pon(testigo nuevo: String?) { testigo = nuevo }
    func hayTestigo() -> Bool { testigo != nil }

    enum Fallo: LocalizedError {
        case sinRed
        case sesionCaida
        case servidor(Int, String)
        case respuestaRara

        var errorDescription: String? {
            switch self {
            case .sinRed: return "Sin conexión."
            case .sesionCaida: return "Tienes que volver a entrar."
            case .servidor(_, let texto): return texto
            case .respuestaRara: return "El servidor contestó algo que no entendí."
            }
        }

        /// Si es esto, no es culpa de nadie: se vuelve a intentar solo más tarde.
        var esPasajero: Bool {
            switch self {
            case .sinRed: return true
            case .servidor(let codigo, _): return codigo >= 500 || codigo == 429
            default: return false
            }
        }
    }

    private struct ErrorDelServidor: Decodable {
        let error: String?
        let sinConexion: Bool?
    }

    static let json: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let f = Formato.iso.date(from: s) { return f }
            // El servidor escribe siempre con milisegundos, pero una fecha
            // guardada a mano puede no tenerlos: mejor aceptarla que romper
            // toda la bajada por un carácter.
            let sinMilis = ISO8601DateFormatter()
            if let f = sinMilis.date(from: s) { return f }
            throw DecodingError.dataCorruptedError(in: try dec.singleValueContainer(),
                                                   debugDescription: "Fecha rara: \(s)")
        }
        return d
    }()

    static let codificador: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { fecha, enc in
            var c = enc.singleValueContainer()
            try c.encode(Formato.iso.string(from: fecha))
        }
        return e
    }()

    /// El nombre que el teléfono se da a sí mismo, para la lista de sesiones.
    /// Va marcado al hilo principal porque `UIDevice` lo está.
    @MainActor
    static var dispositivo: String {
        UIDevice.current.name
    }

    func pide<Respuesta: Decodable>(
        _ camino: String,
        metodo: String = "GET",
        cuerpo: (any Encodable)? = nil,
        conSesion: Bool = true
    ) async throws -> Respuesta {
        var p = URLRequest(url: Api.base.appendingPathComponent(camino))
        p.httpMethod = metodo
        p.setValue("application/json", forHTTPHeaderField: "accept")
        if conSesion, let testigo {
            p.setValue("Bearer " + testigo, forHTTPHeaderField: "authorization")
        }
        if let cuerpo {
            p.setValue("application/json", forHTTPHeaderField: "content-type")
            p.httpBody = try Api.codificador.encode(AnyEncodable(cuerpo))
        }

        let datos: Data, respuesta: URLResponse
        do {
            (datos, respuesta) = try await sesion.data(for: p)
        } catch let e as URLError where e.code == .cancelled {
            throw CancellationError()
        } catch {
            throw Fallo.sinRed
        }

        guard let http = respuesta as? HTTPURLResponse else { throw Fallo.respuestaRara }
        guard (200..<300).contains(http.statusCode) else {
            let detalle = try? JSONDecoder().decode(ErrorDelServidor.self, from: datos)
            if http.statusCode == 401 { throw Fallo.sesionCaida }
            throw Fallo.servidor(http.statusCode, detalle?.error ?? "Error \(http.statusCode).")
        }

        if Respuesta.self == Vacio.self { return Vacio() as! Respuesta }
        do {
            return try Api.json.decode(Respuesta.self, from: datos)
        } catch {
            throw Fallo.respuestaRara
        }
    }

    /// SUBIR UN ARCHIVO TAL CUAL.
    ///
    /// Los bytes van en el cuerpo sin envolver en `multipart`: es UN archivo, y
    /// un formulario de varias partes serían cien líneas de fronteras y
    /// cabeceras para no ganar nada. El servidor comprueba qué es mirando los
    /// primeros bytes, no lo que diga esta cabecera.
    func sube<Respuesta: Decodable>(_ datos: Data, a camino: String,
                                    tipo: String = "image/jpeg",
                                    metodo: String = "PUT") async throws -> Respuesta {
        var p = URLRequest(url: Api.base.appendingPathComponent(camino))
        p.httpMethod = metodo
        p.setValue("application/json", forHTTPHeaderField: "accept")
        p.setValue(tipo, forHTTPHeaderField: "content-type")
        if let testigo { p.setValue("Bearer " + testigo, forHTTPHeaderField: "authorization") }
        p.httpBody = datos
        // Una foto por una red de datos del mercado no cabe en los segundos de
        // una petición normal.
        p.timeoutInterval = 60

        let cuerpo: Data, respuesta: URLResponse
        do {
            (cuerpo, respuesta) = try await sesion.data(for: p)
        } catch let e as URLError where e.code == .cancelled {
            throw CancellationError()
        } catch {
            throw Fallo.sinRed
        }
        guard let http = respuesta as? HTTPURLResponse else { throw Fallo.respuestaRara }
        guard (200..<300).contains(http.statusCode) else {
            let detalle = try? JSONDecoder().decode(ErrorDelServidor.self, from: cuerpo)
            if http.statusCode == 401 { throw Fallo.sesionCaida }
            throw Fallo.servidor(http.statusCode, detalle?.error ?? "Error \(http.statusCode).")
        }
        return try Api.json.decode(Respuesta.self, from: cuerpo)
    }
}

/// Para las rutas que no devuelven nada que importe. Se llama así y no
/// «Vacio» a secas porque eso choca con la pantalla vacía, y el compilador lo
/// dice tarde y mal.
struct Vacio: Codable {}

/// `Encodable` no se puede meter en un `JSONEncoder` sin envolverlo: el
/// protocolo no lleva el tipo concreto y el codificador lo necesita.
private struct AnyEncodable: Encodable {
    let valor: any Encodable
    init(_ v: any Encodable) { valor = v }
    func encode(to encoder: Encoder) throws { try valor.encode(to: encoder) }
}
