import SwiftUI
import SwiftData

/// LOS VALORES DE UNA CLASIFICACIÓN.
///
/// Los pasillos de un súper, las marcas que vendes, las tallas. El orden
/// importa cuando la clasificación agrupa la lista: es el orden del recorrido,
/// así que arrastrar «Nevera» arriba del todo cambia por dónde se empieza.
///
/// Son datos, no una lista fija: un colmado no tiene «Ferretería», y quien
/// vende pescado querrá «Nevera» antes que «Víveres».
struct ValoresView: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(\.sincronizador) private var sincronizador

    @Bindable var clasificacion: Clasificacion

    @Query(filter: #Predicate<Pasillo> { $0.borrado == nil },
           sort: [SortDescriptor<Pasillo>(\.orden), SortDescriptor<Pasillo>(\.nombre)])
    private var todos: [Pasillo]

    /// Solo los de esta clasificación. La de fábrica se queda además con los
    /// que no llevan dueño escrito: son los pasillos de antes de que esto
    /// existiera.
    private var pasillos: [Pasillo] {
        todos.filter { $0.deQuien == clasificacion.id }
    }
    private var esDeFabrica: Bool { clasificacion.id == Clasificacion.pasillos }

    @State private var nuevo = ""
    @State private var editando: Pasillo?
    @State private var nombreEditado = ""
    @FocusState private var enElNuevo: Bool

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(get: { clasificacion.activa },
                                     set: { clasificacion.activa = $0
                                            if !$0 { clasificacion.agrupa = false }
                                            clasificacion.toco(); guarda() })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Usarla").font(tema.texto(16, .semibold))
                        Text("Sale como una casilla al anotar un producto")
                            .font(tema.texto(13)).foregroundStyle(tema.neutral700)
                    }
                }
                .tint(tema.acento2_700)
                .listRowBackground(tema.superficie)

                Toggle(isOn: Binding(get: { clasificacion.agrupa },
                                     set: { agrupaSolo($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Agrupar la compra por esto").font(tema.texto(16, .semibold))
                        Text("La lista se parte en secciones y se recorre en este orden")
                            .font(tema.texto(13)).foregroundStyle(tema.neutral700)
                    }
                }
                .tint(tema.acento2_700)
                .disabled(!clasificacion.activa)
                .listRowBackground(tema.superficie)
            }

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
                Rotulo("\(clasificacion.nombre) · \(pasillos.count)")
            }

            Section {
                HStack(spacing: 8) {
                    TextField("Otro valor", text: $nuevo)
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
                if esDeFabrica {
                    Button("Volver a los de siempre") { restaura() }
                        .font(tema.texto(15, .bold))
                        .foregroundStyle(tema.acento700)
                        .listRowBackground(tema.superficie)
                }
            } footer: {
                Text("Borrar un valor no borra los productos: pasan al último de la lista.")
                    .font(tema.texto(13))
                    .foregroundStyle(tema.neutral700)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .fondoDelTema(tema)
        .environment(\.editMode, .constant(.active))
        .navigationTitle(clasificacion.nombre)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Cómo se llama", isPresented: .init(get: { editando != nil }, set: { if !$0 { editando = nil } })) {
            TextField("Nombre", text: $nombreEditado)
            Button("Guardar") { renombra() }
            Button("Cancelar", role: .cancel) { editando = nil }
        }
        .onAppear { _ = Almacen.valoresDe(ctx, clasificacion.id) }
    }

    private func numero(_ p: Pasillo) -> Int { (pasillos.firstIndex(of: p) ?? 0) + 1 }

    private func cuantos(_ p: Pasillo) -> Int {
        let nombre = p.nombre
        if esDeFabrica {
            let d = FetchDescriptor<Articulo>(
                predicate: #Predicate { $0.categoria == nombre && $0.borrado == nil })
            return (try? ctx.fetchCount(d)) ?? 0
        }
        // Las demás guardan su valor dentro de `etiquetas`, que no se puede
        // consultar desde un predicado: se cuenta a mano.
        let d = FetchDescriptor<Articulo>(predicate: #Predicate { $0.borrado == nil })
        let id = clasificacion.id
        return ((try? ctx.fetch(d)) ?? []).filter { $0.etiqueta(id) == nombre }.count
    }

    /// Solo una clasificación puede agrupar la compra: dos agrupaciones
    /// cruzadas no son una lista, son una tabla.
    private func agrupaSolo(_ puesta: Bool) {
        if puesta {
            for otra in Almacen.clasificaciones(ctx) where otra.agrupa && otra.id != clasificacion.id {
                otra.agrupa = false
                otra.toco()
            }
        }
        clasificacion.agrupa = puesta
        clasificacion.toco()
        guarda()
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
        ctx.insert(Pasillo(nombre: n, orden: (pasillos.map(\.orden).max() ?? 0) + 1,
                           clasificacionId: clasificacion.id))
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
            mueveLosProductos(de: p.nombre, a: ultimo)
            p.entierro()
        }
        guarda()
    }

    private func renombra() {
        guard let p = editando else { return }
        let n = nombreEditado.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != p.nombre else { editando = nil; return }

        // Los productos guardan el NOMBRE, así que renombrarlo sin moverlos los
        // dejaría huérfanos en un grupo que ya no existe.
        mueveLosProductos(de: p.nombre, a: n)
        p.nombre = n
        p.toco()
        editando = nil
        guarda()
    }

    private func restaura() {
        for p in pasillos { p.entierro() }
        for (i, nombre) in Categoria.dePartida.enumerated() {
            ctx.insert(Pasillo(nombre: nombre, orden: i, clasificacionId: Clasificacion.pasillos))
        }
        guarda()
    }

    /// Los productos guardan el nombre del valor, no su identificador. Es lo
    /// que hace que un producto siga clasificado cuando se sincroniza desde
    /// otro teléfono que todavía no ha bajado los valores.
    private func mueveLosProductos(de viejo: String, a nuevo: String) {
        let d = FetchDescriptor<Articulo>(predicate: #Predicate { $0.borrado == nil })
        let id = clasificacion.id
        for a in (try? ctx.fetch(d)) ?? [] {
            if esDeFabrica {
                guard a.categoria == viejo else { continue }
                a.categoria = nuevo
            } else {
                guard a.etiqueta(id) == viejo else { continue }
                a.pon(nuevo, en: id)
            }
            a.toco()
        }
    }
}
