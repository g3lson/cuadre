import SwiftUI
import SwiftData

/// QUÉ IA USA LA APP.
///
/// Se enseña cuál está puesta y se puede cambiar. Existe por dos motivos y los
/// dos son del dueño de la app, no del usuario final: saber qué modelo contestó
/// cuando algo sale raro, y poder cambiarlo sin publicar una versión nueva.
///
/// Lo que Cuadre trae puesto son modelos **gratuitos**, y se dice: elegir otro
/// tiene que ser una decisión, no un descuido.
struct ModelosIAView: View {
    @Environment(\.tema) private var tema
    @Environment(Sesion.self) private var sesion
    @Bindable var ajustes: Ajustes

    @State private var catalogo: IA.Catalogo?
    @State private var cargando = true
    @State private var error: String?
    @State private var busca = ""

    private var visibles: [IA.Modelo] {
        guard let m = catalogo?.modelos else { return [] }
        let t = busca.folding(options: .diacriticInsensitive, locale: nil).lowercased()
        guard !t.isEmpty else { return m }
        return m.filter { ($0.id + " " + $0.nombre).lowercased().contains(t) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                explicacion

                if cargando {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Preguntando qué modelos hay…")
                            .font(tema.texto(14)).foregroundStyle(tema.neutral700)
                    }
                    .padding(.vertical, 12)
                }
                if let error { aviso(error) }

                if let c = catalogo {
                    Rotulo("Lo que trae Cuadre")
                    Bloque {
                        FilaAjuste(titulo: "Para el texto", detalle: c.puestos.texto.joined(separator: " → ")) { EmptyView() }
                        FilaAjuste(titulo: "Para las fotos", detalle: c.puestos.foto.joined(separator: " → "), ultima: true) { EmptyView() }
                    }
                    Text("Se prueban en ese orden: si uno se queda sin cuota, entra el siguiente. Todos son gratuitos.")
                        .font(tema.texto(13)).foregroundStyle(tema.neutral700)
                        .fixedSize(horizontal: false, vertical: true)

                    Rotulo("Elegir uno").padding(.top, 8)
                    Bloque {
                        Button { ajustes.modeloIA = ""; ajustes.toco() } label: {
                            FilaAjuste(titulo: "El que decida Cuadre",
                                       detalle: "Lo normal. Va probando la cadena de arriba.") {
                                if ajustes.modeloIA.isEmpty {
                                    IconoView(icono: .check, tamano: 18, grosor: 3)
                                        .foregroundStyle(tema.acento2_700)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        HStack(spacing: 8) {
                            IconoView(icono: .buscar, tamano: 15).foregroundStyle(tema.neutral500)
                            TextField("Buscar entre \(c.modelos.count) modelos", text: $busca)
                                .font(tema.texto(15))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        .frame(minHeight: 50)
                    }

                    VStack(spacing: 6) {
                        ForEach(visibles.prefix(60)) { m in fila(m) }
                    }
                    if visibles.count > 60 {
                        Text("Y \(visibles.count - 60) más. Busca por nombre.")
                            .font(tema.texto(13)).foregroundStyle(tema.neutral700)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .fondoDelTema(tema)
        .navigationTitle("La IA")
        .navigationBarTitleDisplayMode(.inline)
        .task { await carga() }
    }

    private var explicacion: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("La foto del recibo la lee tu iPhone: las letras con Vision y, si lo tiene, Apple Intelligence las ordena sin que nada salga de aquí.")
                .font(tema.texto(15)).foregroundStyle(tema.neutral700)
                .fixedSize(horizontal: false, vertical: true)
            Text("El modelo de abajo es para lo demás: dictar una lista, y ordenar el recibo cuando tu iPhone no puede hacerlo solo.")
                .font(tema.texto(15)).foregroundStyle(tema.neutral700)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fila(_ m: IA.Modelo) -> some View {
        Button { ajustes.modeloIA = m.id; ajustes.toco() } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.id).font(tema.texto(15, .bold))
                    Text([m.nombre == m.id ? nil : m.nombre,
                          m.proveedor.isEmpty ? nil : m.proveedor,
                          m.contexto > 0 ? "\(m.contexto / 1000)k de contexto" : nil]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(tema.texto(12)).foregroundStyle(tema.neutral700)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if m.puesto {
                    Text("GRATIS")
                        .font(tema.texto(10, .heavy)).tracking(0.6)
                        .foregroundStyle(tema.acento2_800)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(tema.acento2_200, in: Capsule())
                }
                if ajustes.modeloIA == m.id {
                    IconoView(icono: .check, tamano: 18, grosor: 3).foregroundStyle(tema.acento2_700)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ajustes.modeloIA == m.id ? tema.acento2_200 : tema.superficie,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(tema.texto)
        }
        .buttonStyle(.plain)
    }

    private func aviso(_ t: String) -> some View {
        Text(t).font(tema.texto(14)).foregroundStyle(tema.acento800)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tema.acento100, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func carga() async {
        cargando = true
        defer { cargando = false }
        do { catalogo = try await IA.modelos() }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? "No pude preguntar qué modelos hay." }
    }
}
