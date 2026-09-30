import SwiftUI

/// TE COMPARTIERON UNA LISTA.
///
/// Se abre al tocar el enlace que llegó por WhatsApp. Una pantalla y un botón:
/// quien la abre está en el súper o yendo, no leyendo condiciones.
struct InvitacionView: View {
    @Environment(\.tema) private var tema
    @Environment(\.dismiss) private var cerrar
    @Environment(Sesion.self) private var sesion

    let codigo: String
    var alEntrar: (String) -> Void

    @State private var trabajando = true
    @State private var error: String?
    @State private var nombre = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if trabajando {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Abriendo la lista…").font(tema.texto(16, .bold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error {
                ZStack {
                    Circle().fill(tema.acento100)
                    IconoView(icono: .aviso, tamano: 30, grosor: 2.6).foregroundStyle(tema.acento800)
                }
                .frame(width: 64, height: 64)
                Text("No pude abrirla").font(tema.titulo(28)).foregroundStyle(tema.texto)
                Text(error).font(tema.texto(15)).foregroundStyle(tema.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Cerrar") { cerrar() }.buttonStyle(BotonSuave())
            } else {
                ZStack {
                    Circle().fill(tema.acento2_700)
                    IconoView(icono: .check, tamano: 30, grosor: 3).foregroundStyle(tema.fondo)
                }
                .frame(width: 64, height: 64)
                Text("Ya estás dentro").font(tema.titulo(30)).foregroundStyle(tema.texto)
                Text(nombre.isEmpty
                     ? "Verás lo que marquen los demás al momento."
                     : "«\(nombre)» es tuya también. Verás lo que marquen los demás al momento.")
                    .font(tema.texto(15)).foregroundStyle(tema.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Abrir la lista") { cerrar() }.buttonStyle(BotonPrincipal())
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.height(320)])
        .task { await acepta() }
    }

    private func acepta() async {
        defer { trabajando = false }
        do {
            let r = try await Compartir.acepta(codigo)
            nombre = r.nombre ?? ""
            alEntrar(r.listaId)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription
                ?? "Ese enlace ya no vale. Pídele otro a quien te lo mandó."
        }
    }
}
