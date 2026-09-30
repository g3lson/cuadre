import SwiftUI
import SwiftData

/// LA CUENTA DE CHINOLA CONECTADA.
///
/// Se ve qué está conectado, a dónde van los gastos por defecto, y se corta. La
/// pantalla existe sobre todo por lo último: una conexión que no se puede
/// deshacer desde el mismo sitio donde se hizo no es una conexión, es una
/// trampa.
struct ChinolaAjustesView: View {
    @Environment(\.tema) private var tema
    @Environment(\.openURL) private var abre
    @Environment(Sesion.self) private var sesion

    @State private var libretas: [ChinolaApi.Libreta] = []
    @State private var cargando = false
    @State private var trabajando = false
    @State private var error: String?
    @State private var confirmandoCorte = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if sesion.chinola == nil { sinConectar } else { conectada }
                if let error {
                    Text(error).font(tema.texto(14)).foregroundStyle(tema.acento800)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .fondoDelTema(tema)
        .navigationTitle("Chinola")
        .navigationBarTitleDisplayMode(.inline)
        .task { await carga() }
        .refreshable { await sesion.refresca(); await carga() }
        .confirmationDialog("¿Desconectar Chinola?", isPresented: $confirmandoCorte, titleVisibility: .visible) {
            Button("Desconectar", role: .destructive) { Task { await corta() } }
            Button("Dejarla conectada", role: .cancel) {}
        } message: {
            Text("Dejarás de poder anotar gastos ahí desde Cuadre. Lo que ya anotaste se queda en Chinola.")
        }
    }

    @ViewBuilder
    private var sinConectar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sin conectar").font(tema.titulo(28)).foregroundStyle(tema.texto)
            Text("Chinola es la app de finanzas de FENTE. Conéctala y cada compra que cierres aquí se puede anotar allá con un toque.")
                .font(tema.texto(15)).foregroundStyle(tema.neutral700)
                .fixedSize(horizontal: false, vertical: true)
        }

        Button { Task { await conecta() } } label: {
            if trabajando { ProgressView().tint(tema.sobreAcento) } else { Text("Conectar Chinola") }
        }
        .buttonStyle(BotonPrincipal())
        .disabled(trabajando)

        Link("¿Qué es Chinola?", destination: URL(string: "https://chinola.fente.com.do")!)
            .font(tema.texto(14, .bold))
            .padding(.top, 4)
    }

    @ViewBuilder
    private var conectada: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(tema.acento2_700)
                IconoView(icono: .enlace, tamano: 20).foregroundStyle(tema.fondo)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Conectada").font(tema.texto(16, .heavy))
                Text(sesion.chinola?.cuenta.isEmpty == false
                     ? sesion.chinola!.cuenta
                     : "Todavía sin elegir dónde anotar")
                    .font(tema.texto(13)).foregroundStyle(tema.neutral700)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(tema.acento2_200, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .foregroundStyle(tema.acento2_800)

        if cargando {
            HStack(spacing: 10) {
                ProgressView()
                Text("Buscando tus libretas…").font(tema.texto(14)).foregroundStyle(tema.neutral700)
            }
            .padding(.vertical, 10)
        }

        if !libretas.isEmpty {
            Rotulo("A dónde van los gastos")
            Text("Se puede cambiar en cada compra; esto es solo lo que sale marcado por defecto.")
                .font(tema.texto(13)).foregroundStyle(tema.neutral700)

            ForEach(libretas) { l in
                Tarjeta {
                    HStack {
                        Text(l.nombre).font(tema.texto(16, .heavy))
                        Spacer()
                        if sesion.chinola?.libreta == l.id {
                            IconoView(icono: .check, tamano: 18, grosor: 3).foregroundStyle(tema.acento2_700)
                        }
                    }
                    if !l.puedeEscribir {
                        Text("Tu rol aquí (\(l.rol ?? "?")) no permite anotar.")
                            .font(tema.texto(13)).foregroundStyle(tema.neutral700)
                    } else if l.medios.isEmpty {
                        Text("Esta libreta no tiene cuentas todavía.")
                            .font(tema.texto(13)).foregroundStyle(tema.neutral700)
                    } else {
                        ScrollView(.horizontal) {
                            HStack(spacing: 6) {
                                ForEach(l.medios) { m in
                                    Button { Task { await fija(l, m) } } label: {
                                        Text(m.nombre)
                                            .font(tema.texto(13, .bold))
                                            .padding(.horizontal, 12).padding(.vertical, 9)
                                            .background(esElElegido(l, m) ? tema.neutral900 : tema.fondo, in: Capsule())
                                            .foregroundStyle(esElElegido(l, m)
                                                             ? (tema.oscuro ? tema.texto : tema.neutral100)
                                                             : tema.texto)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
            }
        }

        Button("Desconectar Chinola", role: .destructive) { confirmandoCorte = true }
            .buttonStyle(BotonSuave())
            .padding(.top, 10)
    }

    private func esElElegido(_ l: ChinolaApi.Libreta, _ m: ChinolaApi.Libreta.Medio) -> Bool {
        sesion.chinola?.libreta == l.id && sesion.chinola?.medio == m.id
    }

    // MARK: - Lo que hace

    private func carga() async {
        guard sesion.chinola != nil else { return }
        cargando = true
        defer { cargando = false }
        do { libretas = try await ChinolaApi.libretas() }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? "No pude hablar con Chinola." }
    }

    private func conecta() async {
        trabajando = true
        error = nil
        defer { trabajando = false }
        do { abre(try await ChinolaApi.urlParaConectar()) }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? "No pude empezar la conexión." }
    }

    private func fija(_ l: ChinolaApi.Libreta, _ m: ChinolaApi.Libreta.Medio) async {
        do {
            try await ChinolaApi.fija(libreta: l.id, medio: m.id, cuenta: m.nombre)
            await sesion.refresca()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "No pude guardar eso."
        }
    }

    private func corta() async {
        trabajando = true
        defer { trabajando = false }
        do {
            try await ChinolaApi.desconecta()
            libretas = []
            await sesion.refresca()
            sesion.avisa("Chinola desconectada", .info)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "No pude desconectarla."
        }
    }
}
