import SwiftUI
import SwiftData
import UIKit

/// 10 · VENTAS.
///
/// Despachar por libra. El cliente pidió cinco y la balanza dice 5.2: se ajusta
/// ahí mismo con el paso de media libra y el total se recalcula solo. Cobrar es
/// un botón que ya lleva escrito cuánto, porque en el mostrador nadie quiere
/// leer «Marcar entregado y cobrado» y después buscar el monto.
struct VentasView: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(\.sincronizador) private var sincronizador
    @Environment(Sesion.self) private var sesion

    @Query(filter: #Predicate<Evento> { $0.borrado == nil },
           sort: [SortDescriptor<Evento>(\.fecha, order: .reverse)])
    private var eventos: [Evento]
    @Query(filter: #Predicate<Encargo> { $0.borrado == nil },
           sort: [SortDescriptor<Encargo>(\.actualizado)])
    private var todos: [Encargo]

    @State private var nuevoEncargo = Demo.abre("encargo")
    @State private var nuevoEvento = false
    @State private var comprobante: Encargo?
    @State private var aBorrar: Evento?
    @State private var abierto: Encargo?
    /// Por quién se filtra. Vacío = todos. Se pueden marcar varios: «los míos y
    /// los de Carlos» es una pregunta que se hace de verdad.
    @State private var vendedores: Set<String> = []

    /// Cuál se está mirando. Por defecto, la última abierta; si se elige otra,
    /// esa. Sin esto solo se veía una venta y las demás no existían.
    @State private var elegido: String?
    private var abiertos: [Evento] { eventos.filter { $0.estado == "abierto" } }
    private var evento: Evento? {
        if let id = elegido, let e = eventos.first(where: { $0.id == id }) { return e }
        return abiertos.first ?? eventos.first
    }
    private var todosLosDeLaVenta: [Encargo] { todos.filter { $0.eventoId == evento?.id } }
    /// Quiénes han anotado algo en esta venta.
    private var quienes: [String] {
        Array(Set(todosLosDeLaVenta.map(\.registradoPor).filter { !$0.isEmpty })).sorted()
    }
    private var encargos: [Encargo] {
        guard !vendedores.isEmpty else { return todosLosDeLaVenta }
        return todosLosDeLaVenta.filter { vendedores.contains($0.registradoPor) }
    }
    private var pendientes: [Encargo] { encargos.filter { !$0.cobrado } }
    private var cobrados: [Encargo] { encargos.filter(\.cobrado) }
    private var ajustes: Ajustes { Almacen.ajustes(ctx, de: sesion.usuario?.id ?? "") }

    var body: some View {
        NavigationStack {
            Group {
                if let evento { contenido(evento) } else { sinEvento }
            }
            .fondoDelTema(tema)
            .onAppear {
                if Demo.abre("comprobante"), comprobante == nil { comprobante = cobrados.first }
            }
        }
        .sheet(isPresented: $nuevoEncargo) {
            if let evento {
                NuevoEncargoView(evento: evento).hojaDeCuadre(tema)
            }
        }
        .sheet(isPresented: $nuevoEvento) {
            NuevoEventoView().hojaDeCuadre(tema)
        }
        .sheet(item: $abierto) { o in
            FichaEncargoView(encargo: o, ajustes: ajustes) { cobrado in comprobante = cobrado }
                .hojaDeCuadre(tema)
        }
        .sheet(item: $comprobante) { o in
            ComprobanteView(encargo: o, moneda: ajustes.moneda).hojaDeCuadre(tema)
        }
        .confirmationDialog("¿Borrar «\(aBorrar?.titulo ?? "")»?",
                            isPresented: .init(get: { aBorrar != nil }, set: { if !$0 { aBorrar = nil } }),
                            titleVisibility: .visible) {
            Button("Borrar la venta", role: .destructive) {
                if let e = aBorrar {
                    for o in Almacen.encargos(ctx, de: e.id) { o.entierro() }
                    e.entierro()
                    if elegido == e.id { elegido = nil }
                    try? ctx.save()
                    Task { await sincronizador?.sincroniza() }
                }
                aBorrar = nil
            }
            Button("Dejarla", role: .cancel) { aBorrar = nil }
        } message: {
            Text("Se va con todos sus encargos, cobrados o no. No hay papelera.")
        }
    }

    @ViewBuilder
    private func contenido(_ e: Evento) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Etiqueta(texto: e.estado == "abierto" ? "Despachando en vivo" : "Cerrada",
                                 fondo: e.estado == "abierto" ? nil : tema.superficie,
                                 tinta: e.estado == "abierto" ? nil : tema.neutral700,
                                 punto: e.estado == "abierto" ? tema.acento2_700 : nil)

                        // El título es el selector: con más de una venta abierta,
                        // cambiar de una a otra tiene que ser un toque donde ya
                        // se está mirando, no un botón en otra esquina.
                        Menu {
                            if eventos.count > 1 {
                                Section("Tus ventas") {
                                    ForEach(eventos.prefix(15)) { otro in
                                        Button {
                                            elegido = otro.id
                                        } label: {
                                            let cuantos = Almacen.encargos(ctx, de: otro.id).count
                                            Label("\(otro.titulo) · \(Formato.dia(otro.fecha)) · \(cuantos)",
                                                  systemImage: otro.id == e.id ? "checkmark" :
                                                    (otro.estado == "abierto" ? "circle" : "checkmark.circle"))
                                        }
                                    }
                                }
                            }
                            Section {
                                Button { nuevoEvento = true } label: {
                                    Label("Empezar otra venta", systemImage: "plus")
                                }
                                Button {
                                    e.estado = e.estado == "abierto" ? "cerrada" : "abierto"
                                    e.toco(); try? ctx.save()
                                } label: {
                                    Label(e.estado == "abierto" ? "Cerrar esta venta" : "Volver a abrirla",
                                          systemImage: e.estado == "abierto" ? "lock" : "lock.open")
                                }
                                Button(role: .destructive) { aBorrar = e } label: {
                                    Label("Borrar esta venta", systemImage: "trash")
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(e.titulo).font(tema.titulo(30)).multilineTextAlignment(.leading)
                                IconoView(icono: .abajo, tamano: 18, grosor: 3)
                                    .padding(.top, 4)
                            }
                            .foregroundStyle(tema.texto)
                        }

                        if eventos.count > 1 {
                            Text("\(abiertos.count) abierta\(abiertos.count == 1 ? "" : "s") de \(eventos.count)")
                                .font(tema.texto(13))
                                .foregroundStyle(tema.neutral700)
                        }
                    }
                    Spacer(minLength: 8)
                    Button { nuevoEvento = true } label: { IconoView(icono: .mas, tamano: 20) }
                        .buttonStyle(BotonRedondo())
                        .accessibilityLabel("Nueva venta")
                }
                .padding(.top, 8)

                resumen
                barraDeVista

                if !pendientes.isEmpty {
                    Rotulo("Por despachar · \(pendientes.count)").padding(.top, 4)
                    porDespachar
                }

                Button {
                    nuevoEncargo = true
                } label: {
                    HStack(spacing: 8) {
                        IconoView(icono: .mas, tamano: 18)
                        Text("Nuevo encargo")
                    }
                }
                .buttonStyle(BotonSuave())
                .padding(.top, 4)

                if !cobrados.isEmpty {
                    Rotulo("Cobrados · \(cobrados.count)").padding(.top, 8)
                    yaCobrados
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .refreshable { await sincronizador?.sincroniza() }
    }

    private var resumen: some View {
        let cobrado = cobrados.reduce(0) { $0 + $1.total }
        let pesado = cobrados.reduce(0) { $0 + $1.cantidad }

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Cobrado").font(tema.texto(12, .bold))
                Text(Formato.pesos(cobrado, moneda: ajustes.moneda))
                    .font(tema.titulo(21)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(tema.oscuro ? tema.acento2_800 : tema.fondo)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tema.acento2_700, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            cuadrito("Pesado", "\(Formato.cantidad(pesado)) lb")
            cuadrito("Listos", "\(cobrados.count)/\(encargos.count)")
        }
    }

    /// Cómo se mira y de quién. Las dos preguntas van juntas porque se hacen
    /// juntas: «enséñame los de Carlos, en tabla».
    @ViewBuilder
    private var barraDeVista: some View {
        HStack(spacing: 8) {
            Picker("", selection: Binding(
                get: { ajustes.vista },
                set: { ajustes.vistaVentas = $0.rawValue; ajustes.toco(); try? ctx.save() })) {
                ForEach(VistaVentas.allCases) { v in
                    Image(systemName: v.icono).tag(v)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 132)

            if quienes.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        pastilla("Todos", puesta: vendedores.isEmpty) { vendedores = [] }
                        ForEach(quienes, id: \.self) { quien in
                            pastilla(quien, puesta: vendedores.contains(quien)) {
                                if vendedores.contains(quien) { vendedores.remove(quien) }
                                else { vendedores.insert(quien) }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
            Spacer(minLength: 0)
        }
    }

    private func pastilla(_ texto: String, puesta: Bool, al: @escaping () -> Void) -> some View {
        Button(action: al) {
            Text(texto)
                .font(tema.texto(13, .bold))
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(puesta ? tema.neutral900 : tema.superficie, in: Capsule())
                .foregroundStyle(puesta ? (tema.oscuro ? tema.texto : tema.neutral100) : tema.texto)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Las tres maneras de mirar lo mismo

    @ViewBuilder
    private var porDespachar: some View {
        switch ajustes.vista {
        case .tarjetas: ForEach(pendientes) { o in tarjeta(o) }
        case .tabla:
            cabeceraTabla
            ForEach(pendientes) { o in filaTabla(o) }
        case .compacta: ForEach(pendientes) { o in filaCompacta(o) }
        }
    }

    @ViewBuilder
    private var yaCobrados: some View {
        switch ajustes.vista {
        case .tarjetas: ForEach(cobrados) { o in filaCobrado(o) }
        case .tabla:
            cabeceraTabla
            ForEach(cobrados) { o in filaTabla(o) }
        case .compacta: ForEach(cobrados) { o in filaCompacta(o) }
        }
    }

    private var cabeceraTabla: some View {
        HStack(spacing: 8) {
            Text("CLIENTE").frame(maxWidth: .infinity, alignment: .leading)
            Text("CANT.").frame(width: 58, alignment: .trailing)
            Text("PRECIO").frame(width: 58, alignment: .trailing)
            Text("TOTAL").frame(width: 68, alignment: .trailing)
        }
        .font(tema.texto(10, .heavy))
        .tracking(0.7)
        .foregroundStyle(tema.neutral700)
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
    }

    private func filaTabla(_ o: Encargo) -> some View {
        Button { abierto = o } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(o.cliente).font(tema.texto(14, .bold)).lineLimit(1)
                        if !o.salida.cobra { marcaDeSalida(o) }
                    }
                    Text([o.producto, o.registradoPor.isEmpty ? nil : o.registradoPor]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(tema.texto(11.5)).foregroundStyle(tema.neutral700).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(Formato.cantidad(o.cantidad)) \(o.unidad)")
                    .font(tema.texto(13, .semibold)).foregroundStyle(tema.neutral700)
                    .frame(width: 58, alignment: .trailing)
                Text(o.precioAplicado > 0 ? Formato.entero(o.precioAplicado) : "—")
                    .font(tema.texto(13)).foregroundStyle(tema.neutral700)
                    .frame(width: 58, alignment: .trailing)
                Text(o.salida.cobra ? Formato.entero(o.total) : "—")
                    .font(tema.texto(14, .heavy))
                    .frame(width: 68, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .foregroundStyle(o.cobrado ? tema.neutral700 : tema.texto)
            .background(tema.superficie.opacity(o.cobrado ? 0.5 : 1),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func filaCompacta(_ o: Encargo) -> some View {
        Button { abierto = o } label: {
            HStack(spacing: 10) {
                Marcador(puesto: o.cobrado, tamano: 20)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(o.cliente).font(tema.texto(15, .semibold)).lineLimit(1)
                        if !o.salida.cobra { marcaDeSalida(o) }
                    }
                    Text([o.producto + " · " + Formato.cantidad(o.cantidad) + " " + o.unidad,
                          o.registradoPor.isEmpty ? nil : o.registradoPor]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(tema.texto(12)).foregroundStyle(tema.neutral700).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(o.salida.cobra ? Formato.pesos(o.total, moneda: ajustes.moneda) : "—")
                    .font(tema.texto(14, .heavy))
            }
            .padding(.horizontal, 4)
            .frame(minHeight: 44)
            .foregroundStyle(o.cobrado ? tema.neutral700 : tema.texto)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(tema.divisor).frame(height: 1).padding(.leading, 30)
            }
        }
        .buttonStyle(.plain)
    }

    private func marcaDeSalida(_ o: Encargo) -> some View {
        Text(o.salida.etiqueta.uppercased())
            .font(tema.texto(9, .heavy)).tracking(0.5)
            .foregroundStyle(tema.acento800)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tema.acento200, in: Capsule())
    }

    private func cuadrito(_ rotulo: String, _ valor: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(rotulo).font(tema.texto(12, .bold)).foregroundStyle(tema.neutral700)
            Text(valor).font(tema.titulo(21)).foregroundStyle(tema.texto)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tema.superficie, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Una fila por despachar

    private func tarjeta(_ o: Encargo) -> some View {
        Tarjeta {
            Button { abierto = o } label: {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(o.cliente).font(tema.texto(17, .heavy))
                            if !o.salida.cobra {
                                Text(o.salida.etiqueta.uppercased())
                                    .font(tema.texto(10, .heavy)).tracking(0.6)
                                    .foregroundStyle(tema.acento800)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(tema.acento200, in: Capsule())
                            }
                        }
                        Text([
                            "\(o.producto) · pidió \(Formato.cantidad(o.pedido)) \(o.unidad)",
                            o.registradoPor.isEmpty ? nil : "lo anotó \(o.registradoPor)",
                        ].compactMap { $0 }.joined(separator: " · "))
                            .font(tema.texto(13)).foregroundStyle(tema.neutral700)
                        if !o.nota.isEmpty {
                            Text("«\(o.nota)»").font(tema.texto(13)).italic().foregroundStyle(tema.acento700)
                        }
                    }
                    Spacer(minLength: 6)
                    Text(Formato.pesos(o.total, moneda: ajustes.moneda))
                        .font(tema.titulo(24))
                        .foregroundStyle(o.salida.cobra ? tema.acento2_700 : tema.neutral500)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .foregroundStyle(tema.texto)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    Button { ajusta(o, -1) } label: {
                        Text("−").font(tema.texto(20, .bold)).frame(width: 36, height: 36)
                    }
                    // Tocar el número lleva a la ficha, que es donde se puede
                    // escribir 4.2 o pedir «doscientos pesos de eso».
                    Button { abierto = o } label: {
                        Text("\(Formato.cantidad(o.cantidad)) \(o.unidad)")
                            .font(tema.texto(14, .heavy))
                            .lineLimit(1)
                            .frame(minWidth: 52, minHeight: 36)
                    }
                    Button { ajusta(o, 1) } label: {
                        Text("+").font(tema.texto(20, .bold)).frame(width: 36, height: 36)
                    }
                }
                .foregroundStyle(tema.texto)
                .padding(3)
                .background(tema.fondo, in: Capsule())

                Spacer(minLength: 0)

                HStack(spacing: 2) {
                    ForEach(Tarifa.allCases, id: \.self) { t in
                        Button {
                            o.tarifa = t.rawValue
                            o.toco()
                            try? ctx.save()
                        } label: {
                            Text(ajustes.nombreTarifa(t))
                                .font(tema.texto(12, .heavy))
                                .lineLimit(1)
                                .fixedSize()
                                .padding(.horizontal, 9)
                                .frame(height: 36)
                                .background(o.tarifa == t.rawValue ? tema.neutral900 : .clear, in: Capsule())
                                .foregroundStyle(o.tarifa == t.rawValue
                                                 ? (tema.oscuro ? tema.texto : tema.neutral100)
                                                 : tema.neutral700)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(tema.fondo, in: Capsule())
            }

            HStack(spacing: 8) {
                if o.salida.cobra {
                    Button("Cobrar \(Formato.pesos(o.total, moneda: ajustes.moneda))") {
                        cobra(o, "Efectivo")
                    }
                    .buttonStyle(BotonPrincipal(alto: 48))

                    Button("Transf.") { cobra(o, "Transferencia") }
                        .buttonStyle(BotonSuave(alto: 48))
                        .frame(width: 92)
                } else {
                    Button("Anotar la salida") { cobra(o, o.salida.etiqueta) }
                        .buttonStyle(BotonPrincipal(alto: 48))
                }
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                o.entierro(); try? ctx.save()
            } label: { Label("Quitar el encargo", systemImage: "trash") }
        }
    }

    private func filaCobrado(_ o: Encargo) -> some View {
        Button { comprobante = o } label: {
            HStack(spacing: 12) {
                Text(Formato.inicial(o.cliente))
                    .font(tema.texto(15, .heavy))
                    .foregroundStyle(tema.acento2_800)
                    .frame(width: 40, height: 40)
                    .background(tema.acento2_200, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(o.cliente).font(tema.texto(15, .bold))
                    Text("\(o.producto) · \(Formato.cantidad(o.cantidad)) \(o.unidad) × \(Formato.precio(o.precioAplicado, moneda: ajustes.moneda))")
                        .font(tema.texto(13)).foregroundStyle(tema.neutral700).lineLimit(1)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Formato.pesos(o.total, moneda: ajustes.moneda)).font(tema.texto(15, .heavy))
                    Text([o.metodo, o.cobradoEn.map(Formato.hora)].compactMap { $0 }.joined(separator: " · "))
                        .font(tema.texto(12)).foregroundStyle(tema.neutral700)
                }
            }
            .padding(.vertical, 4)
            .foregroundStyle(tema.texto)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sinEvento: some View {
        PantallaVacia(icono: .balanza,
              titulo: "Empieza un día de venta",
              texto: "Una venta es un día de despacho: «Pescado del viernes», «Pollo del sábado». Dentro van los encargos de cada cliente, con su peso y su tarifa.") {
            Button("Empezar una venta") { nuevoEvento = true }
                .buttonStyle(BotonPrincipal())
        }
    }

    // MARK: - Lo que hace

    private func ajusta(_ o: Encargo, _ signo: Double) {
        let paso = Unidad.de(o.unidad).paso
        o.cantidad = max(0, ((o.cantidad + signo * paso) * 100).rounded() / 100)
        o.toco()
        try? ctx.save()
    }

    private func cobra(_ o: Encargo, _ metodo: String) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        o.estado = "cobrado"
        o.metodo = metodo
        o.cobradoEn = .now
        o.toco()
        try? ctx.save()
        Task { await sincronizador?.sincroniza() }
        comprobante = o
    }
}

/// Empezar un día de venta.
struct NuevoEventoView: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var cerrar

    @State private var titulo = ""
    @State private var fecha = Date()
    @State private var grupoId = ""
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
                        FilaAjuste(titulo: "Grupo",
                                   detalle: grupoId.isEmpty ? "Solo tuya" : "La verá la gente del grupo",
                                   ultima: true) {
                            Menu {
                                Button("Solo mía") { grupoId = "" }
                                ForEach(grupos) { g in Button(g.nombre) { grupoId = g.id } }
                            } label: {
                                ValorYChevron(texto: grupos.first { $0.id == grupoId }?.nombre ?? "Ninguno")
                            }
                        }
                    }
                }

                Text("Dentro de la venta van los encargos de cada cliente. Al final del día, el cuadre suma lo que cobraste y lo que te costó la mercancía.")
                    .font(tema.texto(14)).foregroundStyle(tema.neutral700)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Empezar") {
                    let e = Evento(titulo: titulo.trimmingCharacters(in: .whitespaces), fecha: fecha)
                    e.grupoId = grupoId
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
        .presentationDetents([.medium])
    }
}
