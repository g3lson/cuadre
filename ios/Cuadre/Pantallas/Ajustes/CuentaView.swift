import SwiftUI
import SwiftData

/// TU CUENTA.
///
/// Salir, y borrarlo todo. Borrar la cuenta desde la propia app lo exige Apple
/// y además es lo correcto: quien se quiere ir no debería tener que escribir un
/// correo y esperar.
struct CuentaView: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(Sesion.self) private var sesion

    @State private var confirmandoBorrado = false
    @State private var escrito = ""
    @State private var trabajando = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Bloque {
                    FilaAjuste(titulo: "Correo", detalle: sesion.usuario?.email ?? "") { EmptyView() }
                    FilaAjuste(titulo: "Entras con",
                               detalle: sesion.usuario?.conApple == true ? "Apple y código al correo" : "Código al correo",
                               ultima: true) { EmptyView() }
                }

                Rotulo("Tus datos").padding(.top, 6)
                Text("Todo lo que anotas vive en tu iPhone y en el servidor de Cuadre, para que lo veas igual en otro dispositivo. Nada de eso se comparte ni se vende. Lo largo está en la política de privacidad.")
                    .font(tema.texto(14)).foregroundStyle(tema.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
                Link("Leer la política de privacidad",
                     destination: URL(string: "https://cuadre.fente.com.do/legal/privacidad.html")!)
                    .font(tema.texto(14, .bold))

                Button("Cerrar sesión en este teléfono") {
                    Task { await sesion.sal() }
                }
                .buttonStyle(BotonSuave())
                .padding(.top, 12)

                Rotulo("Zona de no volver").padding(.top, 14)
                Text("Borrar la cuenta se lleva tus listas, tus ventas, tus clientes, tus precios y la conexión con Chinola. No hay papelera y no se puede deshacer.")
                    .font(tema.texto(14)).foregroundStyle(tema.neutral700)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Borrar mi cuenta", role: .destructive) { confirmandoBorrado = true }
                    .buttonStyle(BotonSuave())

                if let error {
                    Text(error).font(tema.texto(14)).foregroundStyle(tema.acento800)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .fondoDelTema(tema)
        .navigationTitle("Tu cuenta")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Borrar la cuenta", isPresented: $confirmandoBorrado) {
            // Escribir la palabra es la última defensa: el botón se puede tocar
            // sin querer, esto no.
            TextField("Escribe BORRAR", text: $escrito)
                .textInputAutocapitalization(.characters)
            Button("Borrar para siempre", role: .destructive) {
                guard escrito.uppercased() == "BORRAR" else { return }
                Task { await borra() }
            }
            Button("Cancelar", role: .cancel) { escrito = "" }
        } message: {
            Text("Escribe BORRAR para confirmar. Se va todo y no se puede deshacer.")
        }
    }

    private func borra() async {
        trabajando = true
        defer { trabajando = false }
        do {
            try await sesion.borraLaCuenta()
            // Lo del teléfono también: dejar la base local llena después de
            // borrar la cuenta sería devolverle sus datos a quien entre después.
            try? ctx.delete(model: Lista.self)
            try? ctx.delete(model: Articulo.self)
            try? ctx.delete(model: Evento.self)
            try? ctx.delete(model: Encargo.self)
            try? ctx.delete(model: Producto.self)
            try? ctx.delete(model: Cliente.self)
            try? ctx.delete(model: Tienda.self)
            try? ctx.delete(model: Ajustes.self)
            try? ctx.save()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "No pude borrarla. Prueba otra vez."
        }
    }
}
