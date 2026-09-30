import SwiftUI
import SwiftData

/// LOS PASILLOS.
///
/// El orden de esta lista es el orden en que se recorre la tienda, y por eso
/// importa más de lo que parece: la pantalla de «En tienda» agrupa por esto, así
/// que arrastrar «Nevera» arriba del todo cambia el recorrido de la próxima
/// compra.
///
/// Son datos, no una lista fija: un colmado no tiene «Ferretería», y quien vende
/// pescado querrá «Nevera» antes que «Víveres».
struct PasillosView: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(\.sincronizador) private var sincronizador

    @Query(filter: #Predicate<Pasillo> { $0.borrado == nil },
           sort: [SortDescriptor<Pasillo>(\.orden), SortDescriptor<Pasillo>(\.nombre)])
    private var pasillos: [Pasillo]

    @State private var nuevo = ""
    @State private var editando: Pasillo?
    @State private var nombreEditado = ""
    @FocusState private var enElNuevo: Bool

    var body: some View {
        List {
            Section {
                Text("El orden es el del recorrido: lo de arriba es lo que se coge primero. Arrastra para cambiarlo.")
                    .font(tema.texto(14))
                    .foregroundStyle(tema.neutral700)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section {
                ForEach(pasillos) { p in
                    Button {
                        editando = p
                        nombreEditado = p.nombre
                    } label: {
                        HStack(spacing: 12) {
                            Text("\(numero(p))")
                                .font(tema.texto(12, .heavy))
                                .foregroundStyle(tema.neutral700)
                                .frame(width: 22)
                            Text(p.nombre).font(tema.texto(16, .semibold))
                            Spacer()
                            Text("\(cuantos(p))")
                                .font(tema.texto(13))
                                .foregroundStyle(tema.neutral500)
                        }
                        .foregroundStyle(tema.texto)
                        .frame(minHeight: 46)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(tema.superficie)
                }
                .onMove(perform: mueve)
                .onDelete(perform: borra)
            } header: {
                Rotulo("Tus pasillos · \(pasillos.count)")
            }

            Section {
                HStack(spacing: 8) {
                    TextField("Otro pasillo", text: $nuevo)
                        .font(tema.texto(16))
                        .focused($enElNuevo)
                        .submitLabel(.done)
                        .onSubmit { agrega() }
                    Button { agrega() } label: {
                        IconoView(icono: .mas, tamano: 18, grosor: 3)
                            .foregroundStyle(tema.acento700)
                    }
                    .buttonStyle(.plain)
                    .disabled(nuevo.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .frame(minHeight: 46)
                .listRowBackground(tema.superficie)
            }

            Section {
                Button("Volver a los de siempre") { restaura() }
                    .font(tema.texto(15, .bold))
                    .foregroundStyle(tema.acento700)
                    .listRowBackground(tema.superficie)
            } footer: {
                Text("Borrar un pasillo no borra los productos: pasan al último de la lista.")
                    .font(tema.texto(13))
                    .foregroundStyle(tema.neutral700)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .fondoDelTema(tema)
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Pasillos")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Cómo se llama", isPresented: .init(get: { editando != nil }, set: { if !$0 { editando = nil } })) {
            TextField("Nombre", text: $nombreEditado)
            Button("Guardar") { renombra() }
            Button("Cancelar", role: .cancel) { editando = nil }
        }
        .onAppear { _ = Almacen.pasillos(ctx) }
    }

    private func numero(_ p: Pasillo) -> Int { (pasillos.firstIndex(of: p) ?? 0) + 1 }

    private func cuantos(_ p: Pasillo) -> Int {
        let nombre = p.nombre
        let d = FetchDescriptor<Articulo>(predicate: #Predicate { $0.categoria == nombre && $0.borrado == nil })
        return (try? ctx.fetchCount(d)) ?? 0
    }

    private func guarda() {
        try? ctx.save()
        Task { await sincronizador?.sincroniza() }
    }

    private func agrega() {
        let n = nuevo.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !pasillos.contains(where: { $0.nombre.caseInsensitiveCompare(n) == .orderedSame }) else {
            nuevo = ""
            return
        }
        ctx.insert(Pasillo(nombre: n, orden: (pasillos.map(\.orden).max() ?? 0) + 1))
        nuevo = ""
        guarda()
    }

    private func mueve(_ desde: IndexSet, _ hasta: Int) {
        var lista = pasillos
        lista.move(fromOffsets: desde, toOffset: hasta)
        for (i, p) in lista.enumerated() where p.orden != i {
            p.orden = i
            p.toco()
        }
        guarda()
    }

    /// Borrar un pasillo no borra lo que había dentro: esos productos pasan al
    /// último. Llevarse los productos por delante sería una sorpresa cara.
    private func borra(_ indices: IndexSet) {
        let ultimo = pasillos.last { !indices.contains(pasillos.firstIndex(of: $0) ?? -1) }?.nombre
            ?? Categoria.porDefecto
        for i in indices {
            let p = pasillos[i]
            let nombre = p.nombre
            let d = FetchDescriptor<Articulo>(predicate: #Predicate { $0.categoria == nombre && $0.borrado == nil })
            for a in (try? ctx.fetch(d)) ?? [] {
                a.categoria = ultimo
                a.toco()
            }
            p.entierro()
        }
        guarda()
    }

    private func renombra() {
        guard let p = editando else { return }
        let n = nombreEditado.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != p.nombre else { editando = nil; return }

        // Los productos guardan el NOMBRE del pasillo, así que renombrarlo sin
        // moverlos los dejaría huérfanos en un grupo que ya no existe.
        let viejo = p.nombre
        let d = FetchDescriptor<Articulo>(predicate: #Predicate { $0.categoria == viejo && $0.borrado == nil })
        for a in (try? ctx.fetch(d)) ?? [] {
            a.categoria = n
            a.toco()
        }
        p.nombre = n
        p.toco()
        editando = nil
        guarda()
    }

    private func restaura() {
        for p in pasillos { p.entierro() }
        for (i, nombre) in Categoria.dePartida.enumerated() {
            ctx.insert(Pasillo(nombre: nombre, orden: i))
        }
        guarda()
    }
}
