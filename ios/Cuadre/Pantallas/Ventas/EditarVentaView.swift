import SwiftUI
import SwiftData

/// EDITAR UNA VENTA.
///
/// Una venta se crea de prisa, en el mostrador, y el nombre sale mal o la fecha
/// se queda en hoy cuando era para el sábado. Antes no había manera de
/// arreglarlo: había que borrarla con sus encargos dentro y volver a empezar.
struct EditarVentaView: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(\.sincronizador) private var sincronizador
    @Environment(\.dismiss) private var cerrar

    @Bindable var evento: Evento

    @Query(filter: #Predicate<Grupo> { $0.borrado == nil }, sort: \Grupo.nombre)
    private var grupos: [Grupo]
    @FocusState private var enElTitulo: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cómo se llama").font(tema.texto(15, .bold))
                        Campo(marcador: "Pescado del viernes", valor: $evento.titulo,
                              peso: .bold, tamano: 18)
                            .focused($enElTitulo)
                    }

                    Bloque {
                        FilaAjuste(titulo: "Fecha") {
                            DatePicker("", selection: $evento.fecha, displayedComponents: .date)
                                .labelsHidden()
                        }
                        if !grupos.isEmpty {
                            FilaAjuste(titulo: "Negocio",
                                       detalle: evento.grupoId.isEmpty
                                           ? "Solo tuya" : "La ve la gente del negocio") {
                                Menu {
                                    Button("Solo mía") { evento.grupoId = "" }
                                    ForEach(grupos) { g in
                                        Button(g.nombre) {
                                            evento.grupoId = g.id
                                            if evento.negocio.isEmpty { evento.negocio = g.nombre }
                                        }
                                    }
                                } label: {
                                    ValorYChevron(texto: grupos.first { $0.id == evento.grupoId }?.nombre
                                                  ?? "Ninguno")
                                }
                            }
                        }
                        FilaAjuste(titulo: "Estado",
                                   detalle: evento.estado == "abierto"
                                       ? "Se puede seguir anotando" : "No entra en el cuadre de hoy",
                                   ultima: true) {
                            Interruptor(encendido: Binding(
                                get: { evento.estado == "abierto" },
                                set: { evento.estado = $0 ? "abierto" : "cerrada" }))
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("A nombre de").font(tema.texto(15, .bold))
                        Text("Es lo que va arriba del comprobante del cliente.")
                            .font(tema.texto(13)).foregroundStyle(tema.neutral700)
                        Campo(marcador: "Pescadería El Muelle", valor: $evento.negocio)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .fondoDelTema(tema)
            .navigationTitle("Editar la venta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { guarda() }.font(tema.texto(16, .bold))
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Listo") { enElTitulo = false } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func guarda() {
        evento.titulo = evento.titulo.trimmingCharacters(in: .whitespaces)
        evento.negocio = evento.negocio.trimmingCharacters(in: .whitespaces)
        evento.toco()
        try? ctx.save()
        Task { await sincronizador?.sincroniza() }
        cerrar()
    }
}
