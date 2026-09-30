import SwiftUI
import AuthenticationServices

/// ENTRAR.
///
/// Dos puertas: la de Apple, que es un toque, y un código al correo, que es la
/// que queda si el iPhone no es tuyo. No hay contraseña que inventar ni que
/// recordar, y por eso tampoco hay «¿olvidaste tu contraseña?».
struct EntrarView: View {
    @Environment(\.tema) private var tema
    @Environment(Sesion.self) private var sesion

    private enum Paso { case puerta, correo, codigo }
    @State private var paso: Paso = .puerta
    @State private var correo = ""
    @State private var codigo = ""
    @State private var trabajando = false
    @State private var error: String?
    @FocusState private var foco: Paso?

    var body: some View {
        // El contenido va centrado, pero dentro de una vista con desplazamiento:
        // cuando sube el teclado o el texto está en grande, tiene que poder
        // subir en vez de recortarse. `minHeight` con la altura de la pantalla
        // es lo que hace que los `Spacer` de dentro empujen de verdad.
        GeometryReader { pantalla in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 24)

                HStack(spacing: 14) {
                    Marca(tamano: 58)
                    Text("cuadre").font(tema.titulo(52)).foregroundStyle(tema.texto)
                }
                .padding(.bottom, 18)

                Text("Compra, vende y cuadra — sin sacar cuenta.")
                    .font(tema.titulo(30))
                    .foregroundStyle(tema.acento700)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 34)

                switch paso {
                case .puerta: puerta
                case .correo: pideCorreo
                case .codigo: pideCodigo
                }

                if let error {
                    HStack(alignment: .top, spacing: 8) {
                        IconoView(icono: .aviso, tamano: 16, grosor: 3)
                        Text(error).font(tema.texto(14, .medium))
                    }
                    .foregroundStyle(tema.acento800)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(tema.acento100, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.top, 18)
                }

                Spacer(minLength: 30)

                Text("Al entrar aceptas los [términos](https://cuadre.fente.com.do/legal/terminos.html) y la [política de privacidad](https://cuadre.fente.com.do/legal/privacidad.html).")
                    .font(tema.texto(12))
                    .foregroundStyle(tema.neutral700)
                    .padding(.top, 20)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, minHeight: pantalla.size.height, alignment: .leading)
        }
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(.snappy(duration: 0.25), value: paso)
        .animation(.snappy, value: error)
    }

    // MARK: - Los pasos

    @ViewBuilder
    private var puerta: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.continue) { peticion in
                peticion.requestedScopes = [.fullName, .email]
            } onCompletion: { resultado in
                entraConApple(resultado)
            }
            .signInWithAppleButtonStyle(tema.oscuro ? .white : .black)
            .frame(height: 54)
            .clipShape(Capsule())

            Button("Entrar con mi correo") {
                error = nil
                paso = .correo
                foco = .correo
            }
            .buttonStyle(BotonSuave())
        }
    }

    @ViewBuilder
    private var pideCorreo: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("¿Cuál es tu correo?").font(tema.titulo(26)).foregroundStyle(tema.texto)
            Text("Te mando un código de seis dígitos. No hay contraseña que recordar.")
                .font(tema.texto(15)).foregroundStyle(tema.neutral700)

            TextField("tucorreo@ejemplo.com", text: $correo)
                .font(tema.texto(17, .semibold))
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($foco, equals: .correo)
                .padding(.horizontal, 18)
                .frame(minHeight: 54)
                .background(tema.superficie, in: Capsule())
                .onSubmit { Task { await manda() } }

            Button { Task { await manda() } } label: {
                if trabajando { ProgressView().tint(tema.sobreAcento) } else { Text("Mandar el código") }
            }
            .buttonStyle(BotonPrincipal())
            .disabled(trabajando || !correoValido)

            Button("Mejor con Apple") { error = nil; paso = .puerta }
                .buttonStyle(BotonFantasma())
        }
    }

    @ViewBuilder
    private var pideCodigo: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Mira tu correo").font(tema.titulo(26)).foregroundStyle(tema.texto)
            Text("Te mandé seis dígitos a \(correo). Valen por diez minutos.")
                .font(tema.texto(15)).foregroundStyle(tema.neutral700)
                .fixedSize(horizontal: false, vertical: true)

            TextField("000000", text: $codigo)
                .font(tema.texto(30, .heavy))
                .tracking(10)
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($foco, equals: .codigo)
                .frame(minHeight: 62)
                .background(tema.superficie, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .onChange(of: codigo) { _, nuevo in
                    codigo = String(nuevo.filter(\.isNumber).prefix(6))
                    // Seis dígitos es el código entero: pedir además que toquen
                    // un botón es un paso de más.
                    if codigo.count == 6 { Task { await canjea() } }
                }

            Button { Task { await canjea() } } label: {
                if trabajando { ProgressView().tint(tema.sobreAcento) } else { Text("Entrar") }
            }
            .buttonStyle(BotonPrincipal())
            .disabled(trabajando || codigo.count != 6)

            Button("Cambiar el correo") { error = nil; codigo = ""; paso = .correo; foco = .correo }
                .buttonStyle(BotonFantasma())
        }
    }

    // MARK: - Lo que hace

    private var correoValido: Bool {
        let t = correo.trimmingCharacters(in: .whitespaces)
        return t.contains("@") && t.contains(".") && t.count > 5
    }

    private func manda() async {
        guard correoValido, !trabajando else { return }
        trabajando = true; error = nil
        defer { trabajando = false }
        do {
            try await sesion.pideCodigo(correo.trimmingCharacters(in: .whitespaces))
            paso = .codigo
            foco = .codigo
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "No pude mandarlo. Prueba otra vez."
        }
    }

    private func canjea() async {
        guard codigo.count == 6, !trabajando else { return }
        trabajando = true; error = nil
        defer { trabajando = false }
        do {
            try await sesion.entra(correo: correo.trimmingCharacters(in: .whitespaces), codigo: codigo)
        } catch {
            codigo = ""
            self.error = (error as? LocalizedError)?.errorDescription ?? "Ese código no es."
        }
    }

    private func entraConApple(_ resultado: Result<ASAuthorization, Error>) {
        switch resultado {
        case .failure(let e):
            // Cancelar no es un error que enseñar: la persona cambió de idea.
            if (e as? ASAuthorizationError)?.code == .canceled { return }
            error = "Apple no pudo completar el inicio de sesión."
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            Task {
                trabajando = true; error = nil
                defer { trabajando = false }
                do { try await sesion.entra(conApple: cred) }
                catch { self.error = (error as? LocalizedError)?.errorDescription ?? "No pude entrar con Apple." }
            }
        }
    }
}
