import SwiftUI
import SwiftData

/// 01 · LISTAS.
///
/// La portada. Arriba lo que está pasando ahora —la compra a medias, con lo que
/// llevas gastado— y debajo lo demás. Quien abre la app en el parqueo del súper
/// tiene que poder seguir con un toque.
struct ListasView: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(\.sincronizador) private var sincronizador
    @Environment(Sesion.self) private var sesion

    @Binding var enTienda: String?
    @Binding var pestana: Pestana

    @Query(filter: #Predicate<Lista> { $0.borrado == nil },
           sort: [SortDescriptor<Lista>(\.orden), SortDescriptor<Lista>(\.fecha, order: .reverse)])
    private var listas: [Lista]

    @State private var creando = Demo.abre("nueva")
    @State private var abriendoAjustes = false
    @State private var aBorrar: Lista?

    private var activas: [Lista] { listas.filter { !$0.cerrada } }
    private var cerradas: [Lista] { listas.filter(\.cerrada).sorted { ($0.cerradaEn ?? .distantPast) > ($1.cerradaEn ?? .distantPast) } }

    /// La que se está comprando: la que quedó abierta en «En tienda», o si no la
    /// que tenga algo ya en el carrito.
    private var comprando: Lista? {
        if let id = enTienda, let l = activas.first(where: { $0.id == id }) { return l }
        return activas.first { Almacen.articulos(ctx, de: $0.id).contains(where: \.hecho) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    cabecera
                    saludo

                    if let comprando {
                        tarjetaEnMarcha(comprando)
                    }

                    ForEach(activas.filter { $0.id != comprando?.id }) { l in
                        filaLista(l)
                    }

                    Button {
                        creando = true
                    } label: {
                        HStack(spacing: 8) {
                            IconoView(icono: .mas, tamano: 18, grosor: 2.75)
                            Text("Nueva lista")
                        }
                    }
                    .buttonStyle(BotonSuave())

                    if !cerradas.isEmpty {
                        Rotulo("Ya cuadradas").padding(.top, 6)
                        ForEach(cerradas.prefix(12)) { l in filaCerrada(l) }
                    }

                    if activas.isEmpty && cerradas.isEmpty { vacio }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            .refreshable { await sincronizador?.sincroniza() }
            .fondoDelTema(tema)
            .navigationDestination(for: Lista.self) { l in
                DetalleLista(lista: l, enTienda: $enTienda, pestana: $pestana)
            }
        }
        .sheet(isPresented: $creando) {
            NuevaListaView { nueva in
                enTienda = nueva.id
                pestana = .listas
            }
            .hojaDeCuadre(tema)
        }
        .sheet(isPresented: $abriendoAjustes) {
            AjustesView().hojaDeCuadre(tema)
        }
        .confirmationDialog("¿Borrar «\(aBorrar?.nombre ?? "")»?",
                            isPresented: .init(get: { aBorrar != nil }, set: { if !$0 { aBorrar = nil } }),
                            titleVisibility: .visible) {
            Button("Borrar la lista", role: .destructive) {
                if let l = aBorrar {
                    for a in Almacen.articulos(ctx, de: l.id) { a.entierro() }
                    l.entierro()
                    Avisos.olvida(l.id)
                    if enTienda == l.id { enTienda = nil }
                    Task { await sincronizador?.sincroniza() }
                }
                aBorrar = nil
            }
            Button("Dejarla", role: .cancel) { aBorrar = nil }
        } message: {
            Text("Se va con todos sus productos. No hay papelera.")
        }
    }

    // MARK: - Trozos

    private var cabecera: some View {
        HStack {
            HStack(spacing: 10) {
                Marca(tamano: 34)
                Text("cuadre").font(tema.titulo(22)).foregroundStyle(tema.texto)
            }
            Spacer()
            Button { abriendoAjustes = true } label: {
                Text(sesion.usuario?.inicial ?? "?")
                    .font(tema.texto(15, .heavy))
                    .foregroundStyle(tema.acento2_800)
                    .frame(width: 44, height: 44)
                    .background(tema.acento2_200, in: Circle())
            }
            .accessibilityLabel("Ajustes")
        }
        .padding(.top, 8)
    }

    private var saludo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(nombreCorto.isEmpty ? Formato.saludo() : "\(Formato.saludo()), \(nombreCorto)")
                .font(tema.texto(15))
                .foregroundStyle(tema.neutral700)
            Text("Tus listas").font(tema.titulo(38)).foregroundStyle(tema.texto)
        }
    }

    private var nombreCorto: String {
        let n = sesion.usuario?.nombre ?? ""
        return n.split(separator: " ").first.map(String.init) ?? ""
    }

    private func tarjetaEnMarcha(_ l: Lista) -> some View {
        let arts = Almacen.articulos(ctx, de: l.id)
        let hechos = arts.filter(\.hecho)
        let gastado = hechos.reduce(0) { $0 + $1.total }
        let queda = l.presupuesto - gastado
        let porcentaje = l.presupuesto > 0 ? gastado / l.presupuesto : 0

        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                Etiqueta(texto: "Comprando ahora", fondo: .clear,
                         tinta: tema.acento300, punto: tema.acento)
                .padding(.horizontal, -12)
                Spacer()
                Text("\(hechos.count)/\(arts.count)")
                    .font(tema.texto(13))
                    .foregroundStyle(tema.neutral500)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(l.nombre).font(tema.titulo(24)).foregroundStyle(tema.sobreOscuro)
                if !l.tienda.isEmpty {
                    Text(l.tienda).font(tema.texto(14)).foregroundStyle(tema.neutral500)
                }
            }
            if l.presupuesto > 0 {
                Barra(porcentaje: porcentaje,
                      color: queda < 0 ? tema.acento : (porcentaje > 0.8 ? tema.acento300 : tema.acento2_400),
                      pista: tema.neutral700.opacity(0.35))
                HStack(alignment: .firstTextBaseline) {
                    (Text(Formato.pesos(gastado, moneda: moneda)).font(tema.texto(18, .heavy))
                        + Text(" de \(Formato.pesos(l.presupuesto, moneda: moneda))").font(tema.texto(14)))
                    .foregroundStyle(tema.sobreOscuro)
                    Spacer()
                    Text(queda < 0 ? "Te pasaste \(Formato.pesos(-queda, moneda: moneda))"
                                   : "Quedan \(Formato.pesos(queda, moneda: moneda))")
                        .font(tema.texto(14, .bold))
                        .foregroundStyle(queda < 0 ? tema.acento300 : tema.acento2_300)
                }
            } else {
                Text("\(Formato.pesos(gastado, moneda: moneda)) en el carrito")
                    .font(tema.texto(16, .heavy))
                    .foregroundStyle(tema.sobreOscuro)
            }
            Button("Seguir comprando") {
                enTienda = l.id
                pestana = .listas
            }
            .buttonStyle(BotonPrincipal(alto: 48))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tema.neutral900, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func filaLista(_ l: Lista) -> some View {
        let arts = Almacen.articulos(ctx, de: l.id)
        let esFaltantes = l.nombre == "Faltantes"
        let estimado = arts.reduce(0) { $0 + $1.total }

        return Button {
            enTienda = l.id
            pestana = .listas
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(esFaltantes ? tema.acento : ColorLista.color(l.color, tema).opacity(0.28))
                    if esFaltantes {
                        Text("\(arts.count)").font(tema.texto(18, .heavy)).foregroundStyle(tema.sobreAcento)
                    } else {
                        IconoView(icono: .lista, tamano: 22)
                            .foregroundStyle(tema.acento800)
                    }
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(l.nombre).font(tema.texto(16, .bold))
                    Text(subtitulo(l, arts.count))
                        .font(tema.texto(13))
                        .foregroundStyle(esFaltantes ? tema.acento800 : tema.neutral700)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if esFaltantes {
                    IconoView(icono: .chevron, tamano: 18)
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        if estimado > 0 {
                            Text(Formato.pesos(estimado, moneda: moneda)).font(tema.texto(15, .heavy))
                        }
                        Text(Formato.dia(l.fecha)).font(tema.texto(12)).foregroundStyle(tema.neutral700)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(esFaltantes ? tema.acento100 : tema.superficie,
                        in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .foregroundStyle(esFaltantes ? tema.acento800 : tema.texto)
        }
        .buttonStyle(.plain)
        .contextMenu {
            NavigationLink(value: l) { Label("Ver la lista", systemImage: "list.bullet") }
            Button(role: .destructive) { aBorrar = l } label: { Label("Borrar", systemImage: "trash") }
        }
    }

    private func subtitulo(_ l: Lista, _ cuantos: Int) -> String {
        if l.nombre == "Faltantes" {
            let nombres = Almacen.articulos(ctx, de: l.id).prefix(2).map(\.nombre).joined(separator: ", ")
            return nombres.isEmpty ? "Nada pendiente" : nombres
        }
        let piezas = [l.tienda, "\(cuantos) producto\(cuantos == 1 ? "" : "s")"].filter { !$0.isEmpty }
        return piezas.joined(separator: " · ")
    }

    private func filaCerrada(_ l: Lista) -> some View {
        NavigationLink(value: l) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(tema.acento2_200)
                    IconoView(icono: .check, tamano: 18, grosor: 3)
                        .foregroundStyle(tema.acento2_800)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(l.nombre).font(tema.texto(15, .bold))
                    Text([Formato.dia(l.cerradaEn ?? l.fecha), l.chinolaNota]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(tema.texto(13))
                        .foregroundStyle(tema.neutral700)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(Formato.pesos(Almacen.gastado(ctx, en: l), moneda: moneda))
                    .font(tema.texto(15, .heavy))
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
            .foregroundStyle(tema.texto)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { aBorrar = l } label: { Label("Borrar", systemImage: "trash") }
        }
    }

    private var vacio: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Empieza por una lista").font(tema.titulo(24)).foregroundStyle(tema.texto)
            Text("Ponle nombre, la tienda y cuánto piensas gastar. Después, en el súper, vas marcando lo que echas al carrito y la app lleva la cuenta.")
                .font(tema.texto(15))
                .foregroundStyle(tema.neutral700)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tema.superficie, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.top, 4)
    }

    private var moneda: String {
        Almacen.ajustes(ctx, de: sesion.usuario?.id ?? "").moneda
    }
}

/// La lista ya cerrada, en solo lectura, con su botón de compartir el reporte.
struct DetalleLista: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var cerrar

    let lista: Lista
    @Binding var enTienda: String?
    @Binding var pestana: Pestana

    var body: some View {
        if lista.cerrada {
            ResumenCerrada(lista: lista)
        } else {
            // Una lista abierta no tiene pantalla propia: es la de «En tienda».
            Color.clear.onAppear {
                enTienda = lista.id
                pestana = .listas
                cerrar()
            }
        }
    }
}
