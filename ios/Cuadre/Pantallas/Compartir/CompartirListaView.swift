import SwiftUI
import SwiftData

/// COMPARTIR LA LISTA.
///
/// El caso: una pareja entra al súper y se separa para acabar antes. Lo que
/// hace falta de esta pantalla es que invitar sea un toque y que se vea quién
/// está — no un panel de permisos.
struct CompartirListaView: View {
    @Environment(\.tema) private var tema
    @Environment(\.dismiss) private var cerrar
    @Environment(Sesion.self) private var sesion

    let lista: Lista
    @Binding var miembros: [Compartir.Miembro]

    @State private var correo = ""
    @State private var enlace: Compartir.Enlace?
    @State private var trabajando = false
    @State private var error: String?
    @State private var aQuitar: Compartir.Miembro?
    @FocusState private var enElCorreo: Bool

    private var soyDueño: Bool {
        miembros.first { $0.esDueño }?.email == (sesion.usuario?.email ?? "") || miembros.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    encabezado

                    if soyDueño { invitar }

                    if !miembros.isEmpty {
                        Rotulo("Quién la ve")
                        Grupo {
                            ForEach(Array(miembros.enumerated()), id: \.element.id) { i, m in
                                fila(m, ultima: i == miembros.count - 1)
                            }
                        }
                    }

                    if !soyDueño {
                        Button("Salirme de esta lista", role: .destructive) {
                            aQuitar = miembros.first { $0.email == sesion.usuario?.email }
                        }
                        .buttonStyle(BotonSuave())
                        .padding(.top, 8)
                    }

                    if let error {
                        Text(error).font(tema.texto(14)).foregroundStyle(tema.acento800)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .fondoDelTema(tema)
            .navigationTitle("Compartir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { cerrar() }.font(tema.texto(16, .bold))
                }
            }
        }
        .task { await refresca() }
        .confirmationDialog(
            aQuitar?.email == sesion.usuario?.email ? "¿Salirte de la lista?" : "¿Quitar a \(aQuitar?.comoSeLlama ?? "")?",
            isPresented: .init(get: { aQuitar != nil }, set: { if !$0 { aQuitar = nil } }),
            titleVisibility: .visible) {
            Button("Quitar", role: .destructive) { Task { await quita() } }
            Button("Dejarlo", role: .cancel) { aQuitar = nil }
        } message: {
            Text("Dejará de ver la lista y de poder tocarla. Lo que ya puso se queda.")
        }
    }

    // MARK: - Trozos

    private var encabezado: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lista.nombre).font(tema.titulo(30)).foregroundStyle(tema.texto)
            Text(miembros.count > 1
                 ? "Quien esté en la lista ve lo que marcas al momento. Si tú coges la leche, no la busca nadie más."
                 : "Compártela y la verán al momento: si tú coges la leche, no la busca nadie más.")
                .font(tema.texto(15))
                .foregroundStyle(tema.neutral700)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var invitar: some View {
        HStack(spacing: 8) {
            TextField("Su correo", text: $correo)
                .font(tema.texto(16))
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($enElCorreo)
                .padding(.horizontal, 18)
                .frame(minHeight: 50)
                .background(tema.superficie, in: Capsule())
                .onSubmit { Task { await invita() } }

            Button { Task { await invita() } } label: {
                if trabajando { ProgressView().tint(tema.sobreAcento) }
                else { IconoView(icono: .mas, tamano: 20, grosor: 3) }
            }
            .buttonStyle(BotonRedondo(relleno: tema.acento, tinta: tema.sobreAcento))
            .disabled(trabajando || !correo.contains("@"))
        }

        // El enlace es como se comparte aquí de verdad: por WhatsApp, no
        // escribiendo el correo de alguien de memoria.
        if let enlace {
            ShareLink(item: enlace.texto) {
                HStack(spacing: 8) {
                    IconoView(icono: .compartir, tamano: 18)
                    Text("Mandar el enlace")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(BotonPrincipal(alto: 50))
            Text("Vale siete días. Quien lo abra entra en la lista.")
                .font(tema.texto(12)).foregroundStyle(tema.neutral700)
        } else {
            Button { Task { await haceEnlace() } } label: {
                HStack(spacing: 8) {
                    IconoView(icono: .enlace, tamano: 18)
                    Text("Crear un enlace para WhatsApp")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(BotonSuave(alto: 50))
            .disabled(trabajando)
        }
    }

    private func fila(_ m: Compartir.Miembro, ultima: Bool) -> some View {
        FilaAjuste(titulo: m.comoSeLlama,
                   detalle: m.dentro ? (m.esDueño ? "Creó la lista" : m.email) : "Invitado · todavía no ha entrado",
                   ultima: ultima) {
            HStack(spacing: 10) {
                Text(m.inicial)
                    .font(tema.texto(13, .heavy))
                    .foregroundStyle(m.dentro ? tema.acento2_800 : tema.neutral700)
                    .frame(width: 32, height: 32)
                    .background(m.dentro ? tema.acento2_200 : tema.neutral300, in: Circle())
                if soyDueño, !m.esDueño {
                    Button { aQuitar = m } label: {
                        IconoView(icono: .equis, tamano: 15, grosor: 3)
                            .foregroundStyle(tema.neutral500)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Lo que hace

    private func refresca() async {
        miembros = (try? await Compartir.miembros(de: lista.id)) ?? miembros
    }

    private func invita() async {
        let c = correo.trimmingCharacters(in: .whitespaces).lowercased()
        guard c.contains("@") else { return }
        trabajando = true; error = nil
        defer { trabajando = false }
        do {
            miembros = try await Compartir.invita(c, a: lista.id)
            correo = ""
            enElCorreo = false
            sesion.avisa("Invitación mandada a \(c)", .bien)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "No pude invitar a esa persona."
        }
    }

    private func haceEnlace() async {
        trabajando = true; error = nil
        defer { trabajando = false }
        do { enlace = try await Compartir.enlace(de: lista.id) }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? "No pude crear el enlace." }
    }

    private func quita() async {
        guard let m = aQuitar else { return }
        aQuitar = nil
        do {
            try await Compartir.quita(m.email, de: lista.id)
            if m.email == sesion.usuario?.email { cerrar() } else { await refresca() }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "No pude quitarla."
        }
    }
}
