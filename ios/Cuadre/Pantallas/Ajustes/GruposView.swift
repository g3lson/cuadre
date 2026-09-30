import SwiftUI
import SwiftData

/// LOS GRUPOS.
///
/// «Mi negocio», «El otro», «Casa». Compartir un negocio se hace UNA vez: a
/// partir de ahí, todo lo que se cree dentro —listas, ventas, catálogo,
/// clientes— lo ve esa gente sin invitarla a cada cosa.
///
/// Lo que no está en ningún grupo es solo tuyo, y esa es la opción por defecto:
/// compartir tiene que ser una decisión.
struct GruposView: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(\.sincronizador) private var sincronizador
    @Environment(Sesion.self) private var sesion

    @Query(filter: #Predicate<Grupo> { $0.borrado == nil }, sort: \Grupo.nombre)
    private var grupos: [Grupo]

    @State private var creando = false
    @State private var nombreNuevo = ""
    @State private var cuantos: [String: Int] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Un grupo es un negocio, o tu casa. Lo que creas dentro lo ve la gente del grupo sin que tengas que compartirlo cosa por cosa.")
                    .font(tema.texto(15))
                    .foregroundStyle(tema.neutral700)
                    .fixedSize(horizontal: false, vertical: true)

                if grupos.isEmpty {
                    Tarjeta {
                        Text("Todavía no tienes ninguno").font(tema.texto(16, .bold))
                        Text("Hasta que crees uno, todo lo que anotas es solo tuyo.")
                            .font(tema.texto(14)).foregroundStyle(tema.neutral700)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                ForEach(grupos) { g in
                    NavigationLink { NegocioView(grupo: g) } label: {
                        HStack(spacing: 14) {
                            LogoDelNegocio(grupo: g, lado: 46)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.nombre).font(tema.texto(16, .bold))
                                Text(detalle(g)).font(tema.texto(13)).foregroundStyle(tema.neutral700)
                            }
                            Spacer(minLength: 6)
                            IconoView(icono: .chevron, tamano: 16, grosor: 3)
                                .foregroundStyle(tema.neutral500)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(tema.superficie, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .foregroundStyle(tema.texto)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    nombreNuevo = ""
                    creando = true
                } label: {
                    HStack(spacing: 8) {
                        IconoView(icono: .mas, tamano: 18)
                        Text("Crear un grupo")
                    }
                }
                .buttonStyle(BotonSuave())
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .fondoDelTema(tema)
        .navigationTitle("Grupos")
        .navigationBarTitleDisplayMode(.inline)
        .alert("¿Cómo se llama?", isPresented: $creando) {
            TextField("Mi negocio", text: $nombreNuevo)
            Button("Crear") { crea() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Por ejemplo «Pescadería», «La casa» o el nombre de tu socio.")
        }
        .task { await cuenta() }
    }

    private func detalle(_ g: Grupo) -> String {
        let gente = cuantos[g.id] ?? 0
        let listas = ((try? ctx.fetch(FetchDescriptor<Lista>())) ?? [])
            .filter { $0.vivo && $0.grupoId == g.id }.count
        let piezas = [
            gente > 1 ? "\(gente) personas" : "solo tú",
            listas > 0 ? "\(listas) lista\(listas == 1 ? "" : "s")" : nil,
        ].compactMap { $0 }
        return piezas.joined(separator: " · ")
    }

    private func crea() {
        let n = nombreNuevo.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        let g = Grupo(nombre: n, color: grupos.count % ColorLista.cuantos)
        ctx.insert(g)
        try? ctx.save()
        Task {
            await sincronizador?.sincroniza()
            await cuenta()
        }
    }

    /// Cuánta gente hay en cada grupo. Lo sabe el servidor, no el teléfono: los
    /// miembros no son datos que se sincronicen, son permisos.
    private func cuenta() async {
        guard let r = try? await Compartir.grupos() else { return }
        cuantos = Dictionary(uniqueKeysWithValues: r.map { ($0.id, $0.miembros) })
    }
}
