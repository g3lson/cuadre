import SwiftUI
import SwiftData

/// Empezar un día de venta.
struct NuevoEventoView: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var cerrar

    @State private var titulo = ""
    @State private var fecha = Date()
    @State private var grupoId = ""
    /// A nombre de qué negocio se despacha. Sale solo del grupo, y se puede
    /// cambiar: un sábado se vende en el mercado y otro en la parada, y el
    /// comprobante del cliente no dice lo mismo.
    @State private var negocio = ""
    @State private var negocioAMano = false
    @Query(filter: #Predicate<Grupo> { $0.borrado == nil }, sort: \Grupo.nombre) private var grupos: [Grupo]
    @FocusState private var enElTitulo: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Pescado del viernes", text: $titulo)
                    .font(tema.titulo(30))
                    .foregroundStyle(tema.texto)
                    .focused($enElTitulo)

                Bloque {
                    FilaAjuste(titulo: "Fecha", ultima: grupos.isEmpty) {
                        DatePicker("", selection: $fecha, displayedComponents: .date).labelsHidden()
                    }
                    if !grupos.isEmpty {
                        FilaAjuste(titulo: "Negocio",
                                   detalle: grupoId.isEmpty ? "Solo tuya" : "La verá la gente del negocio") {
                            Menu {
                                Button("Solo mía") { elige("") }
                                ForEach(grupos) { g in Button(g.nombre) { elige(g.id) } }
                            } label: {
                                ValorYChevron(texto: grupos.first { $0.id == grupoId }?.nombre ?? "Ninguno")
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("A nombre de").font(tema.texto(15, .bold))
                        Text("Es lo que va arriba del comprobante del cliente.")
                            .font(tema.texto(13)).foregroundStyle(tema.neutral700)
                        Campo(marcador: "Pescadería El Muelle", valor: Binding(
                            get: { negocio },
                            set: { negocio = $0; negocioAMano = true }))
                    }
                    .padding(.vertical, 14)
                }

                Text("Dentro de la venta van los encargos de cada cliente. Al final del día, el cuadre suma lo que cobraste y lo que te costó la mercancía.")
                    .font(tema.texto(14)).foregroundStyle(tema.neutral700)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Empezar") {
                    let e = Evento(titulo: titulo.trimmingCharacters(in: .whitespaces), fecha: fecha)
                    e.grupoId = grupoId
                    e.negocio = negocio.trimmingCharacters(in: .whitespaces)
                    ctx.insert(e)
                    try? ctx.save()
                    cerrar()
                }
                .buttonStyle(BotonPrincipal())
                .disabled(titulo.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .fondoDelTema(tema)
            .navigationTitle("Nueva venta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { cerrar() }.foregroundStyle(tema.acento700)
                }
            }
        }
        .presentationDetents([.large])
    }

    /// Elegir negocio rellena el nombre, salvo que ya se hubiera escrito otro a
    /// mano: lo que tecleó una persona no lo pisa un menú.
    private func elige(_ id: String) {
        grupoId = id
        guard !negocioAMano else { return }
        negocio = grupos.first { $0.id == id }?.nombre ?? ""
    }
}
