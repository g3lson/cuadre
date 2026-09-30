import SwiftUI
import SwiftData
import UIKit

/// 03 · EN TIENDA.
///
/// La pantalla que se usa de pie, con una mano y el carrito en la otra. Por eso
/// es una lista de verdad —una fila por producto, con cantidad, precio y total
/// al lado— y no tarjetas: de un vistazo se ve qué falta y cuánto llevas.
///
/// Y por eso va **agrupada por pasillo**. Una lista en el orden en que se
/// escribió obliga a cruzar el súper cuatro veces; agrupada por categoría, en el
/// orden en que están los pasillos, se recorre una vez. Es el cambio que más
/// tiempo ahorra de toda la app y no se ve en ninguna captura.
struct EnTiendaView: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(\.sincronizador) private var sincronizador
    @Environment(Sesion.self) private var sesion

    @Binding var listaId: String?
    @Binding var pestana: Pestana

    @Query(filter: #Predicate<Lista> { $0.borrado == nil },
           sort: [SortDescriptor<Lista>(\.orden), SortDescriptor<Lista>(\.fecha, order: .reverse)])
    private var listas: [Lista]
    @Query(filter: #Predicate<Articulo> { $0.borrado == nil },
           sort: [SortDescriptor<Articulo>(\.orden), SortDescriptor<Articulo>(\.nombre)])
    private var todos: [Articulo]

    @State private var abierto: Articulo?
    @State private var columnasAbiertas = Demo.abre("columnas")
    @State private var cerrando = Demo.abre("cerrar")
    @State private var asistente = Demo.abre("asistente")
    @State private var compartiendo = Demo.abre("compartir")
    @State private var busca = ""
    @State private var buscando = false
    @State private var miembros: [Compartir.Miembro] = []
    @FocusState private var enLaBusqueda: Bool

    private var lista: Lista? {
        if let id = listaId, let l = listas.first(where: { $0.id == id }) { return l }
        return listas.first { !$0.cerrada }
    }
    private var articulos: [Articulo] { todos.filter { $0.listaId == lista?.id } }
    private var enCarrito: [Articulo] { filtrados.filter(\.hecho) }
    private var gastado: Double { articulos.filter(\.hecho).reduce(0) { $0 + $1.total } }
    private var ajustes: Ajustes { Almacen.ajustes(ctx, de: sesion.usuario?.id ?? "") }
    private var compartida: Bool { miembros.count > 1 }
    private var yo: String {
        let n = sesion.usuario?.nombre ?? ""
        return n.split(separator: " ").first.map(String.init) ?? (sesion.usuario?.inicial ?? "")
    }

    /// Lo que se ve, después de buscar.
    private var filtrados: [Articulo] {
        let t = busca.folding(options: .diacriticInsensitive, locale: nil).lowercased()
        guard !t.isEmpty else { return articulos }
        return articulos.filter {
            let n = ($0.nombre + " " + $0.nota).folding(options: .diacriticInsensitive, locale: nil).lowercased()
            return n.contains(t)
        }
    }
    private var faltan: [Articulo] { filtrados.filter { !$0.hecho } }

    /// Por comprar, repartido por pasillo y en el orden del recorrido.
    private var porPasillo: [(categoria: String, articulos: [Articulo])] {
        Dictionary(grouping: faltan, by: \.categoria)
            .map { (categoria: $0.key, articulos: $0.value.sorted { $0.orden < $1.orden }) }
            .sorted { Categoria.orden($0.categoria) < Categoria.orden($1.categoria) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let lista { contenido(lista) } else { sinLista }
            }
            .fondoDelTema(tema)
        }
        .sheet(item: $abierto) { a in
            FichaArticuloView(articulo: a, moneda: ajustes.moneda) {
                try? ctx.save()
                Task { await sincronizador?.sincroniza() }
            }
            .hojaDeCuadre(tema)
        }
        .sheet(isPresented: $columnasAbiertas) { ColumnasView(ajustes: ajustes).hojaDeCuadre(tema) }
        .sheet(isPresented: $asistente) {
            if let lista { AsistenteView(lista: lista).hojaDeCuadre(tema) }
        }
        .sheet(isPresented: $compartiendo) {
            if let lista {
                CompartirListaView(lista: lista, miembros: $miembros).hojaDeCuadre(tema)
            }
        }
        .fullScreenCover(isPresented: $cerrando) {
            if let lista {
                CerrarCompraView(lista: lista) { listaId = nil; pestana = .listas }
            }
        }
        .task(id: lista?.id) { await traeMiembros() }
        .onChange(of: sesion.pulso) { _, _ in
            // Alguien tocó esta lista desde otro teléfono.
            Task { await sincronizador?.sincroniza() }
        }
    }

    // MARK: - Contenido

    @ViewBuilder
    private func contenido(_ l: Lista) -> some View {
        // La barra va en un VStack y no en un `safeAreaInset`: metida ahí se
        // colaba debajo del reloj y la isla dinámica, y «Listas» quedaba encima
        // de la hora.
        VStack(spacing: 0) {
            barraSuperior(l)
            lista(l)
        }
    }

    @ViewBuilder
    private func lista(_ l: Lista) -> some View {
        List {
            Section {
                titulo(l)
                if l.cerrada { bannerCerrada(l) } else { tarjetaCarrito(l) }
            }
            .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            if l.cerrada {
                seccion(rotulo: "Comprado", articulos: enCarrito, tachado: true, lista: l)
            } else if ajustes.agrupar && busca.isEmpty {
                ForEach(porPasillo, id: \.categoria) { grupo in
                    seccion(rotulo: grupo.categoria, articulos: grupo.articulos, tachado: false, lista: l)
                }
            } else {
                seccion(rotulo: busca.isEmpty ? "Por comprar" : "Encontrado · \(faltan.count)",
                        articulos: faltan, tachado: false, lista: l)
            }

            if !l.cerrada {
                Section {
                    Button { agrega(a: l) } label: {
                        HStack(spacing: 12) {
                            IconoView(icono: .mas, tamano: 20)
                            Text("Agregar producto").font(tema.texto(15, .bold))
                            Spacer()
                        }
                        .foregroundStyle(tema.acento700)
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                if !enCarrito.isEmpty {
                    seccion(rotulo: "En el carrito · \(enCarrito.count)", articulos: enCarrito,
                            tachado: true, lista: l)
                }

                Section {
                    Button("Listo, cerrar compra · \(Formato.pesos(gastado, moneda: ajustes.moneda))") {
                        cerrando = true
                    }
                    .buttonStyle(BotonPrincipal())
                    .disabled(articulos.filter(\.hecho).isEmpty)
                    .padding(.top, 12)
                    .padding(.bottom, 110)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                Color.clear.frame(height: 110)
                    .listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await sincronizador?.sincroniza() }
    }

    // MARK: - Arriba

    private func barraSuperior(_ l: Lista) -> some View {
        VStack(spacing: 8) {
            HStack {
                Button { pestana = .listas } label: {
                    HStack(spacing: 4) {
                        IconoView(icono: .atras, tamano: 20)
                        Text("Listas").font(tema.texto(15, .bold))
                    }
                    .foregroundStyle(tema.acento700)
                    .frame(minHeight: 44)
                }
                Spacer()
                if !l.cerrada {
                    HStack(spacing: 6) {
                        Button {
                            withAnimation(.snappy) { buscando.toggle() }
                            if buscando { enLaBusqueda = true } else { busca = "" }
                        } label: { IconoView(icono: .buscar, tamano: 20) }
                            .buttonStyle(BotonRedondo(relleno: buscando ? tema.acento200 : nil))
                            .accessibilityLabel("Buscar")

                        Menu {
                            Toggle(isOn: Binding(
                                get: { ajustes.agrupar },
                                set: { ajustes.agrupar = $0; ajustes.toco(); try? ctx.save() })) {
                                Label("Agrupar por pasillo", systemImage: "list.bullet.indent")
                            }
                            Button { columnasAbiertas = true } label: {
                                Label("Qué columnas ver", systemImage: "slider.horizontal.3")
                            }
                            if sesion.hayIA {
                                Button { asistente = true } label: {
                                    Label("Dictar o leer un recibo", systemImage: "sparkles")
                                }
                            }
                            Divider()
                            Button { compartiendo = true } label: {
                                Label(compartida ? "Quién está en la lista" : "Compartir la lista",
                                      systemImage: "person.2")
                            }
                        } label: {
                            IconoView(icono: .columnas, tamano: 20).frame(width: 44, height: 44)
                                .background(tema.superficie, in: Circle())
                                .foregroundStyle(tema.texto)
                        }
                        .accessibilityLabel("Más")

                        Button { agrega(a: l) } label: { IconoView(icono: .mas, tamano: 20) }
                            .buttonStyle(BotonRedondo(relleno: tema.acento, tinta: tema.sobreAcento))
                            .accessibilityLabel("Agregar producto")
                    }
                }
            }
            .padding(.horizontal, 16)

            if buscando {
                HStack(spacing: 8) {
                    IconoView(icono: .buscar, tamano: 16).foregroundStyle(tema.neutral500)
                    TextField("Buscar en la lista", text: $busca)
                        .font(tema.texto(16))
                        .focused($enLaBusqueda)
                        .submitLabel(.search)
                    if !busca.isEmpty {
                        Button { busca = "" } label: {
                            IconoView(icono: .equis, tamano: 15).foregroundStyle(tema.neutral500)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(tema.superficie, in: Capsule())
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.bottom, 8)
        .background(tema.fondo)
    }

    private func titulo(_ l: Lista) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l.nombre).font(tema.titulo(30)).foregroundStyle(tema.texto)
            HStack(spacing: 8) {
                Text([l.tienda, "\(articulos.count) producto\(articulos.count == 1 ? "" : "s")"]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(tema.texto(14))
                    .foregroundStyle(tema.neutral700)
                if compartida {
                    Button { compartiendo = true } label: { avatares }
                        .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }

    /// Quién más está en la lista, en pequeño. Tocarlo abre el panel.
    private var avatares: some View {
        HStack(spacing: -6) {
            ForEach(miembros.prefix(3)) { m in
                Text(m.inicial)
                    .font(tema.texto(10, .heavy))
                    .foregroundStyle(tema.acento2_800)
                    .frame(width: 22, height: 22)
                    .background(tema.acento2_200, in: Circle())
                    .overlay(Circle().strokeBorder(tema.fondo, lineWidth: 1.5))
            }
            if miembros.count > 3 {
                Text("+\(miembros.count - 3)")
                    .font(tema.texto(10, .heavy))
                    .foregroundStyle(tema.neutral700)
                    .padding(.leading, 8)
            }
        }
    }

    private func tarjetaCarrito(_ l: Lista) -> some View {
        let queda = l.presupuesto - gastado
        let pct = l.presupuesto > 0 ? gastado / l.presupuesto : 0

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("En el carrito").font(tema.texto(13, .bold)).foregroundStyle(tema.neutral500)
                Spacer()
                if l.presupuesto > 0 {
                    Text(queda < 0 ? "Te pasaste \(Formato.pesos(-queda, moneda: ajustes.moneda))"
                                   : "Te quedan \(Formato.pesos(queda, moneda: ajustes.moneda))")
                        .font(tema.texto(13, .bold))
                        .foregroundStyle(queda < 0 ? tema.acento300 : tema.acento2_300)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Formato.pesos(gastado, moneda: ajustes.moneda))
                    .font(tema.titulo(34))
                    .foregroundStyle(tema.sobreOscuro)
                    .contentTransition(.numericText())
                if l.presupuesto > 0 {
                    Text("de \(Formato.pesos(l.presupuesto, moneda: ajustes.moneda))")
                        .font(tema.texto(13))
                        .foregroundStyle(tema.neutral500)
                }
            }
            if l.presupuesto > 0 {
                Barra(porcentaje: pct,
                      color: queda < 0 ? tema.acento : (pct > 0.8 ? tema.acento300 : tema.acento2_400),
                      pista: tema.neutral700.opacity(0.35), alto: 8)
            }
        }
        .animation(.snappy, value: gastado)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tema.neutral900, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.top, 10)
    }

    private func bannerCerrada(_ l: Lista) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(tema.acento2_700)
                IconoView(icono: .check, tamano: 18, grosor: 3).foregroundStyle(tema.fondo)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Compra cerrada · \(Formato.pesos(gastado, moneda: ajustes.moneda))")
                    .font(tema.texto(15, .bold))
                if !l.notaCierre.isEmpty {
                    Text(l.notaCierre).font(tema.texto(13)).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(tema.acento2_800)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tema.acento2_200, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.top, 10)
    }

    // MARK: - Una sección de la lista

    private var anchos: (cantidad: CGFloat, precio: CGFloat, total: CGFloat) { (52, 50, 58) }

    @ViewBuilder
    private func seccion(rotulo: String, articulos listaArts: [Articulo], tachado: Bool, lista l: Lista) -> some View {
        if !listaArts.isEmpty {
            Section {
                ForEach(listaArts) { a in fila(a, tachado: tachado) }
                    .onMove { desde, hasta in mueve(listaArts, desde, hasta) }
            } header: {
                cabeceraSeccion(rotulo, listaArts, cerrada: l.cerrada)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    private func cabeceraSeccion(_ rotulo: String, _ arts: [Articulo], cerrada: Bool) -> some View {
        HStack(spacing: 6) {
            Text(rotulo.uppercased())
                .font(tema.texto(11, .heavy)).tracking(0.8)
                .foregroundStyle(tema.neutral700)
            Text("\(arts.count)")
                .font(tema.texto(11, .heavy))
                .foregroundStyle(tema.neutral500)
            Spacer()
            if ajustes.verCantidad { Text("CANT.").frame(width: anchos.cantidad, alignment: .trailing) }
            if ajustes.verPrecio { Text("PRECIO").frame(width: anchos.precio, alignment: .trailing) }
            if ajustes.verTotal { Text("TOTAL").frame(width: anchos.total, alignment: .trailing) }
        }
        .font(tema.texto(11, .heavy))
        .tracking(0.8)
        .foregroundStyle(tema.neutral700)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tema.fondo)
        .contextMenu {
            if !cerrada, !arts.allSatisfy(\.hecho) {
                Button {
                    for a in arts where !a.hecho { a.marca(true, quien: yo) }
                    guarda()
                } label: { Label("Poner todo en el carrito", systemImage: "checkmark.circle") }
            }
            if !cerrada, arts.contains(where: \.hecho) {
                Button {
                    for a in arts where a.hecho { a.marca(false, quien: yo) }
                    guarda()
                } label: { Label("Sacarlo todo del carrito", systemImage: "circle") }
            }
        }
    }

    private func fila(_ a: Articulo, tachado: Bool) -> some View {
        Button { abierto = a } label: {
            HStack(spacing: 6) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.snappy(duration: 0.2)) { a.marca(!a.hecho, quien: yo) }
                    guarda()
                } label: {
                    Marcador(puesto: a.hecho)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: 30, alignment: .leading)
                .accessibilityLabel(a.hecho ? "Sacar del carrito" : "Poner en el carrito")

                VStack(alignment: .leading, spacing: 1) {
                    Text(a.nombre.isEmpty ? "Producto nuevo" : a.nombre)
                        .font(tema.texto(15, a.hecho ? .regular : .semibold))
                        .strikethrough(a.hecho)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    // En una lista de dos, saber QUIÉN lo cogió es la mitad del
                    // asunto: si no, ella ve la leche marcada y no sabe si fue él
                    // o si la marcó sin querer.
                    if compartida, a.hecho, !a.hechoPor.isEmpty {
                        Text("lo cogió \(a.hechoPor)")
                            .font(tema.texto(12, .semibold))
                            .foregroundStyle(tema.acento2_700)
                    } else if ajustes.verNota, !a.nota.isEmpty {
                        Text(a.nota).font(tema.texto(12)).foregroundStyle(tema.neutral700).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)

                if ajustes.verCantidad {
                    Text("\(Formato.cantidad(a.cantidad)) \(a.unidad)")
                        .font(tema.texto(14, .semibold))
                        .foregroundStyle(tema.neutral700)
                        .frame(width: anchos.cantidad, alignment: .trailing)
                }
                if ajustes.verPrecio {
                    Text(a.precio > 0 ? Formato.entero(a.precio) : "—")
                        .font(tema.texto(14))
                        .foregroundStyle(tema.neutral700)
                        .frame(width: anchos.precio, alignment: .trailing)
                }
                if ajustes.verTotal {
                    Text(a.precio > 0 ? Formato.entero(a.total) : "—")
                        .font(tema.texto(15, a.hecho ? .bold : .heavy))
                        .frame(width: anchos.total, alignment: .trailing)
                }
            }
            .foregroundStyle(a.hecho ? tema.neutral700 : tema.texto)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(tema.divisor).frame(height: 1).padding(.leading, 30)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { quita(a) } label: { Label("Quitar", systemImage: "trash") }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                withAnimation(.snappy) { a.marca(!a.hecho, quien: yo) }
                guarda()
            } label: {
                Label(a.hecho ? "Sacar" : "Al carrito", systemImage: a.hecho ? "circle" : "checkmark")
            }
            .tint(tema.acento2_700)
        }
    }

    private var sinLista: some View {
        PantallaVacia(icono: .bolsa,
              titulo: "No hay ninguna compra abierta",
              texto: "Aquí se lleva la compra en vivo: vas marcando lo que echas al carrito y la app suma sola. Crea una lista y vuelve cuando estés en la tienda.") {
            Button("Ir a mis listas") { pestana = .listas }
                .buttonStyle(BotonPrincipal())
        }
    }

    // MARK: - Lo que hace

    private func guarda() {
        try? ctx.save()
        Task { await sincronizador?.sincroniza() }
    }

    private func agrega(a l: Lista) {
        let nuevo = Articulo(listaId: l.id, unidad: ajustes.unidadPorDefecto,
                             orden: (articulos.map(\.orden).max() ?? 0) + 1)
        ctx.insert(nuevo)
        l.toco()
        abierto = nuevo
    }

    /// Quitar con posibilidad de arrepentirse. Un producto quitado sin querer en
    /// medio del pasillo se nota cinco segundos después, no cinco minutos.
    private func quita(_ a: Articulo) {
        let nombre = a.nombre.isEmpty ? "el producto" : a.nombre
        withAnimation(.snappy) { a.entierro() }
        guarda()
        sesion.avisa("Quitaste \(nombre)", .info, accion: "Deshacer") {
            a.borrado = nil
            a.toco()
            guarda()
        }
    }

    /// Reordenar dentro de un grupo. Se renumera solo ese grupo, dejando los
    /// huecos que ya tenían los demás: tocar el orden de toda la lista para
    /// mover un producto haría que se resincronizara entera.
    private func mueve(_ grupo: [Articulo], _ desde: IndexSet, _ hasta: Int) {
        var nuevos = grupo
        nuevos.move(fromOffsets: desde, toOffset: hasta)
        let base = grupo.map(\.orden).min() ?? 0
        for (i, a) in nuevos.enumerated() where a.orden != base + i {
            a.orden = base + i
            a.toco()
        }
        guarda()
    }

    private func traeMiembros() async {
        guard let id = lista?.id else { miembros = []; return }
        miembros = (try? await Compartir.miembros(de: id)) ?? []
    }
}
