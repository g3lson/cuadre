import Foundation
import SwiftUI
import AuthenticationServices

/// LA SESIÓN.
///
/// Quién eres y qué tienes conectado. Es lo único que la app necesita saber
/// antes de enseñar nada, y lo que decide si arranca en la pantalla de entrar o
/// en tus listas.
@Observable
@MainActor
final class Sesion {
    struct Usuario: Codable, Equatable {
        var id: String
        var email: String
        var nombre: String
        var inicial: String
        var conApple: Bool
    }

    struct ConexionChinola: Codable, Equatable {
        var libreta: String
        var medio: String
        var cuenta: String
        var creado: String?
        var ultimoUso: String?

        enum CodingKeys: String, CodingKey {
            case libreta, medio, cuenta, creado
            case ultimoUso = "ultimo_uso"
        }
    }

    private(set) var usuario: Usuario?
    private(set) var chinola: ConexionChinola?
    private(set) var hayIA = false
    private(set) var comprobando = true
    var avisos: [Aviso] = []

    var dentro: Bool { usuario != nil }

    private let claveTestigo = "sesion"

    // MARK: - Arranque

    func arranca() async {
        // El modo demo entra sin servidor y sin testigo: como no hay testigo, el
        // sincronizador ni lo intenta, y lo de mentira no puede subir a ningún lado.
        if Demo.encendido {
            usuario = Demo.usuario()
            hayIA = true
            comprobando = false
            return
        }
        guard let t = Llavero.lee(claveTestigo) else {
            comprobando = false
            return
        }
        await Api.shared.pon(testigo: t)
        // Se pinta lo que había guardado antes de preguntar: abrir la app sin
        // señal no debería mandarte a la pantalla de entrar.
        if let datos = UserDefaults.standard.data(forKey: "usuario"),
           let u = try? JSONDecoder().decode(Usuario.self, from: datos) {
            usuario = u
        }
        await refresca()
        comprobando = false
    }

    private struct RespuestaYo: Decodable {
        let usuario: Usuario
        let chinola: ConexionChinola?
        let ia: Bool
    }

    func refresca() async {
        do {
            let r: RespuestaYo = try await Api.shared.pide("api/yo")
            usuario = r.usuario
            chinola = r.chinola
            hayIA = r.ia
            guarda(r.usuario)
        } catch Api.Fallo.sesionCaida {
            await olvida()
        } catch {
            // Sin red se sigue con lo que había: la app entera funciona sin ella.
        }
    }

    private func guarda(_ u: Usuario) {
        if let d = try? JSONEncoder().encode(u) { UserDefaults.standard.set(d, forKey: "usuario") }
    }

    // MARK: - Entrar

    private struct RespuestaEntrar: Decodable {
        let token: String
        let usuario: Usuario
    }
    private struct PideCodigo: Encodable { let correo: String }
    private struct Canjea: Encodable { let correo: String; let codigo: String; let dispositivo: String }
    private struct ConApple: Encodable { let identityToken: String; let nombre: String; let dispositivo: String }

    func pideCodigo(_ correo: String) async throws {
        let _: Vacio = try await Api.shared.pide(
            "api/auth/codigo", metodo: "POST", cuerpo: PideCodigo(correo: correo), conSesion: false)
    }

    func entra(correo: String, codigo: String) async throws {
        let r: RespuestaEntrar = try await Api.shared.pide(
            "api/auth/entrar", metodo: "POST",
            cuerpo: Canjea(correo: correo, codigo: codigo, dispositivo: Api.dispositivo),
            conSesion: false)
        await acepta(r)
    }

    /// Lo que devuelve el botón de Apple. El nombre solo llega la primera vez
    /// que alguien autoriza la app: si no viene, no se pisa el que ya había.
    func entra(conApple credencial: ASAuthorizationAppleIDCredential) async throws {
        guard let datos = credencial.identityToken, let token = String(data: datos, encoding: .utf8) else {
            throw Api.Fallo.respuestaRara
        }
        let nombre = [credencial.fullName?.givenName, credencial.fullName?.familyName]
            .compactMap { $0 }.joined(separator: " ")
        let r: RespuestaEntrar = try await Api.shared.pide(
            "api/auth/apple", metodo: "POST",
            cuerpo: ConApple(identityToken: token, nombre: nombre, dispositivo: Api.dispositivo),
            conSesion: false)
        await acepta(r)
    }

    private func acepta(_ r: RespuestaEntrar) async {
        Llavero.guarda(r.token, para: claveTestigo)
        await Api.shared.pon(testigo: r.token)
        usuario = r.usuario
        guarda(r.usuario)
        await refresca()
    }

    func sal() async {
        _ = try? await Api.shared.pide("api/yo/salir", metodo: "POST") as Vacio
        await olvida()
    }

    func olvida() async {
        Llavero.borra(claveTestigo)
        UserDefaults.standard.removeObject(forKey: "usuario")
        UserDefaults.standard.removeObject(forKey: "sincronizadoHasta")
        await Api.shared.pon(testigo: nil)
        usuario = nil
        chinola = nil
    }

    private struct CambiaNombre: Encodable { let nombre: String }

    func renombra(_ nombre: String) async {
        struct R: Decodable { let usuario: Usuario }
        if let r: R = try? await Api.shared.pide("api/yo", metodo: "PATCH", cuerpo: CambiaNombre(nombre: nombre)) {
            usuario = r.usuario
            guarda(r.usuario)
        }
    }

    func borraLaCuenta() async throws {
        let _: Vacio = try await Api.shared.pide("api/yo", metodo: "DELETE")
        await olvida()
    }

    // MARK: - Avisos

    func avisa(_ texto: String, _ clase: Aviso.Clase = .info) {
        let a = Aviso(texto: texto, clase: clase)
        withAnimation(.snappy) { avisos.append(a) }
        Task {
            try? await Task.sleep(for: .seconds(clase == .mal ? 5 : 3))
            withAnimation(.snappy) { avisos.removeAll { $0.id == a.id } }
        }
    }
}
