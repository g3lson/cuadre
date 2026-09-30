import SwiftUI
import SwiftData

/// CÓMO ORDENAS TUS PRODUCTOS.
///
/// «Pasillo» venía metido a la fuerza en cada producto y no se podía quitar.
/// Pero clasificar por pasillos solo le sirve a quien recorre un súper grande:
/// quien vende ropa quiere «Marca» y «Talla», y quien vende pescado no quiere
/// ninguna, y le sobraba una casilla en cada producto que anotaba.
///
/// Aquí se inventan las que hagan falta y se encienden las que se usen. Todas
/// vienen apagadas: lo que no se enciende no existe en la ficha del producto.
struct ClasificacionesView: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(\.sincronizador) private var sincronizador

    @Query(filter: #Predicate<Clasificacion> { $0.borrado == nil },
           sort: [SortDescriptor<Clasificacion>(\.orden), SortDescriptor<Clasificacion>(\.nombre)])
    private var clasificaciones: [Clasificacion]

    @State private var creando = false
    @State private var nombreNuevo = ""
    @State private var abierta: Clasificacion?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Una clasificación es una manera de ordenar lo que compras o vendes. «Pasillo» sirve para recorrer el súper sin dar vueltas; «Marca» o «Talla» sirven para otra cosa. Enciende solo las que uses: cada una es una casilla más al anotar un producto.")
                    .font(tema.texto(15))
                    .foregroundStyle(tema.neutral700)
                    .fixedSize(horizontal: false, vertical: true)

                Bloque {
                    ForEach(Array(clasificaciones.enumerated()), id: \.element.id) { i, c in
                        FilaAjuste(titulo: c.nombre,
                                   detalle: detalle(c),
                                   ultima: i == clasificaciones.count - 1) {
                            HStack(spacing: 10) {
                                Button { abierta = c } label: {
                                    IconoView(icono: .lapiz, tamano: 17, grosor: 2.4)
                                        .foregroundStyle(tema.neutral700)
                                        .frame(width: 38, height: 38)
                                        .background(tema.fondo, in: Circle())
                                }
                                .buttonStyle(.plain)

                                Interruptor(encendido: Binding(
                                    get: { c.activa },
                                    set: { enciende(c, $0) }))
                            }
                        }
                    }
                }

                Button {
                    nombreNuevo = ""
                    creando = true
                } label: {
                    HStack(spacing: 8) {
                        IconoView(icono: .mas, tamano: 18)
                        Text("Crear una clasificación")
                    }
                }
                .buttonStyle(BotonSuave())

                if let agrupa = clasificaciones.first(where: { $0.activa && $0.agrupa }) {
                    Text("La lista de la compra se agrupa por **\(agrupa.nombre)**. Solo una puede hacerlo: dos agrupaciones cruzadas no son una lista, son una tabla.")
                        .font(tema.texto(13))
                        .foregroundStyle(tema.neutral700)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .fondoDelTema(tema)
        .navigationTitle("Clasificaciones")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $abierta) { c in
            ValoresView(clasificacion: c)
        }
        .alert("¿Cómo se llama?", isPresented: $creando) {
            TextField("Marca", text: $nombreNuevo)
            Button("Crear") { crea() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Por ejemplo «Marca», «Talla» o «Proveedor». Después le pones sus valores.")
        }
        .onAppear { _ = Almacen.clasificaciones(ctx) }
    }

    private func detalle(_ c: Clasificacion) -> String {
        let cuantos = Almacen.valoresDe(ctx, c.id).count
        let piezas = [
            c.activa ? "Encendida" : "Apagada",
            cuantos > 0 ? "\(cuantos) valor\(cuantos == 1 ? "" : "es")" : "sin valores",
            c.agrupa && c.activa ? "agrupa la lista" : nil,
        ].compactMap { $0 }
        return piezas.joined(separator: " · ")
    }

    /// Encender una que agrupa apaga la agrupación de las demás: la lista solo
    /// se puede partir de una manera a la vez.
    private func enciende(_ c: Clasificacion, _ puesta: Bool) {
        c.activa = puesta
        if !puesta { c.agrupa = false }
        c.toco()
        guarda()
    }

    private func crea() {
        let n = nombreNuevo.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        let c = Clasificacion(nombre: n, orden: clasificaciones.count)
        c.activa = true      // se acaba de crear a mano: se quiere usar
        ctx.insert(c)
        guarda()
        abierta = c
    }

    private func guarda() {
        try? ctx.save()
        Task { await sincronizador?.sincroniza() }
    }
}
