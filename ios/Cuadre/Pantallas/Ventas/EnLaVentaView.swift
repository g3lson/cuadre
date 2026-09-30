import SwiftUI
import SwiftData
import UIKit

/// 11 · DENTRO DE UNA VENTA.
///
/// Aquí se despacha. Ocupa la pantalla entera, sin el menú de abajo: ese menú
/// es para saltar entre pantallas generales, y mientras se pesa y se cobra solo
/// quita sitio justo donde está la mano.
///
/// Arriba, tres botones y ninguno hace lo mismo que otro: **+** añade un
/// encargo —que es lo que se hace cien veces al día, y por eso va en el color
/// de la marca—, el de la cuadrícula cambia cómo se ve la lista, y los tres
/// puntos guardan lo que se hace una vez: editar la venta, cerrarla, borrarla.
struct EnLaVentaView: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(\.sincronizador) private var sincronizador
    @Environment(Sesion.self) private var sesion

    @Bindable var evento: Evento
    let ajustes: Ajustes
    var salir: () -> Void

    @Query(filter: #Predicate<Encargo> { $0.borrado == nil },
           sort: [SortDescriptor<Encargo>(\.actualizado)])
    private var todos: [Encargo]

    @State private var nuevoEncargo = Demo.abre("encargo")
    @State private var comprobante: Encargo?
    @State private var abierto: Encargo?
    @State private var editando = Demo.abre("editar")
    @State private var aBorrar = false
    @State private var vendedores: Set<String> = []
    @State private var porConfirmar: PorCobrar?
    @State private var companeros: [String] = []

    private struct PorCobrar: Identifiable {
        let encargo: Encargo
        let metodo: String
        var id: String { encargo.id + metodo }
    }

    // MARK: - Lo que hay

    private var todosLosDeLaVenta: [Encargo] { todos.filter { $0.eventoId == evento.id } }
    private var quienes: [String] {
        Array(Set(todosLosDeLaVenta.map(\.registradoPor).filter { !$0.isEmpty })).sorted()
    }
    private var encargos: [Encargo] {
        guard !vendedores.isEmpty else { return todosLosDeLaVenta }
        return todosLosDeLaVenta.filter { vendedores.contains($0.registradoPor) }
    }
    private var pendientes: [Encargo] { encargos.filter { !$0.cobrado } }
    /// Del más nuevo al más viejo: lo último que pasó por el mostrador es lo que
    /// se quiere ver sin bajar, y lo que se deshace cuando fue un error.
    private var cobrados: [Encargo] {
        encargos.filter(\.cobrado).sorted {
            ($0.cobradoEn ?? .distantPast) > ($1.cobradoEn ?? .distantPast)
        }
    }
    private var negocio: Grupo? {
        guard !evento.grupoId.isEmpty else { return nil }
        return ((try? ctx.fetch(FetchDescriptor<Grupo>())) ?? [])
            .first { $0.vivo && $0.id == evento.grupoId }
    }
    private var nombreDelNegocio: String {
        evento.negocio.isEmpty ? (negocio?.nombre ?? "") : evento.negocio
    }

    var body: some View {
        VStack(spacing: 0) {
            barraDeArriba
            lista
        }
        .fondoDelTema(tema)
        .onAppear {
            if Demo.abre("comprobante"), comprobante == nil { comprobante = cobrados.first }
            if Demo.abre("confirmar"), porConfirmar == nil, let o = pendientes.first {
                porConfirmar = PorCobrar(encargo: o, metodo: "Efectivo")
            }
        }
        .task(id: evento.id) { await cargaCompaneros() }
        .sheet(isPresented: $nuevoEncargo) {
            NuevoEncargoView(evento: evento).hojaDeCuadre(tema)
        }
        .sheet(isPresented: $editando) {
            EditarVentaView(evento: evento).hojaDeCuadre(tema)
        }
        .sheet(item: $abierto) { o in
            FichaEncargoView(encargo: o, ajustes: ajustes, gente: gente,
                             yo: yo) { cobrado in comprobante = cobrado }
                .hojaDeCuadre(tema)
        }
        .sheet(item: $porConfirmar) { p in
            ConfirmarCobroView(encargo: p.encargo, metodo: p.metodo,
                               moneda: ajustes.moneda, gente: gente,
                               aNombreDe: p.encargo.registradoPor.isEmpty
                                   ? yo : p.encargo.registradoPor) { quien in
                cobraYa(p.encargo, p.metodo, aNombreDe: quien)
            }
        }
        .sheet(item: $comprobante) { o in
            ComprobanteView(encargo: o, moneda: ajustes.moneda,
                            negocio: nombreDelNegocio,
                            logo: negocio?.logo ?? "",
                            telefonoNegocio: negocio?.telefono ?? "")
                .hojaDeCuadre(tema)
        }
        .confirmationDialog("¿Borrar «\(evento.titulo)»?", isPresented: $aBorrar,
                            titleVisibility: .visible) {
            Button("Borrar la venta", role: .destructive) {
                for o in Almacen.encargos(ctx, de: evento.id) { o.entierro() }
                evento.entierro()
                try? ctx.save()
                Task { await sincronizador?.sincroniza() }
                salir()
            }
            Button("Dejarla", role: .cancel) {}
        } message: {
            Text("Se va con todos sus encargos, cobrados o no. No hay papelera.")
        }
    }

    // MARK: - La barra de arriba

    private var barraDeArriba: some View {
        HStack(spacing: 8) {
            Button { salir() } label: { IconoView(icono: .atras, tamano: 20) }
                .buttonStyle(BotonRedondo())
                .accessibilityLabel("Volver a tus ventas")

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    if let g = negocio { LogoDelNegocio(grupo: g, lado: 16) }
                    Text(nombreDelNegocio.isEmpty ? Formato.dia(evento.fecha) : nombreDelNegocio)
                        .font(tema.texto(11, .heavy))
                        .foregroundStyle(tema.neutral700)
                        .lineLimit(1)
                }
                Text(evento.titulo)
                    .font(tema.titulo(20))
                    .foregroundStyle(tema.texto)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Cambiar de vista. Un menú y no un botón que rota: con tres
            // opciones, rotar obliga a pasar por la que no se quiere.
            Menu {
                Picker("", selection: Binding(
                    get: { ajustes.vista },
                    set: { ajustes.vistaVentas = $0.rawValue; ajustes.toco(); try? ctx.save() })) {
                    ForEach(VistaVentas.allCases) { v in
                        Label(v.etiqueta, systemImage: v.icono).tag(v)
                    }
                }
            } label: {
                IconoView(icono: .columnas, tamano: 20)
                    .foregroundStyle(tema.texto)
                    .frame(width: 44, height: 44)
                    .background(tema.superficie, in: Circle())
            }
            .accessibilityLabel("Cómo se ve la lista")

            Menu {
                Button { editando = true } label: {
                    Label("Editar la venta", systemImage: "pencil")
                }
                Button {
                    evento.estado = evento.estado == "abierto" ? "cerrada" : "abierto"
                    evento.toco(); try? ctx.save()
                    Task { await sincronizador?.sincroniza() }
                } label: {
                    Label(evento.estado == "abierto" ? "Cerrar la venta" : "Volver a abrirla",
                          systemImage: evento.estado == "abierto" ? "lock" : "lock.open")
                }
                Button(role: .destructive) { aBorrar = true } label: {
                    Label("Borrar la venta", systemImage: "trash")
                }
            } label: {
                IconoView(icono: .mas, tamano: 20)
                    .rotationEffect(.degrees(45))
                    .foregroundStyle(tema.texto)
                    .frame(width: 44, height: 44)
                    .background(tema.superficie, in: Circle())
                    .rotationEffect(.degrees(45))
            }
            .accessibilityLabel("Más cosas de la venta")

            // El + es para un encargo nuevo, que es lo que se hace cien veces
            // al día. Va en el color de la marca porque es LA acción de esta
            // pantalla, y porque antes se confundía con empezar otra venta.
            Button { nuevoEncargo = true } label: { IconoView(icono: .mas, tamano: 22) }
                .buttonStyle(BotonRedondo(relleno: tema.acento, tinta: tema.sobreAcento))
                .accessibilityLabel("Nuevo encargo")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - La lista

    private var lista: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                resumen
                if quienes.count > 1 { filtroDeVendedores }

                if todosLosDeLaVenta.isEmpty {
                    sinEncargos
                } else {
                    if !pendientes.isEmpty {
                        Rotulo("Por despachar · \(pendientes.count)").padding(.top, 2)
                        porDespachar
                    }
                    if !cobrados.isEmpty {
                        Rotulo("Cobrados · \(cobrados.count)").padding(.top, 6)
                        yaCobrados
                    }
                }
            }
            .padding(.horizontal, ajustes.vista == .compacta ? 16 : 20)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .refreshable { await sincronizador?.sincroniza() }
    }

    /// Las tres cifras, en una fila y sin tarjetas: en la pantalla de despachar
    /// lo que tiene que ocupar sitio son los encargos.
    private var resumen: some View {
        let cobrado = cobrados.reduce(0) { $0 + $1.total }
        let pesado = cobrados.reduce(0) { $0 + $1.cantidad }
        return HStack(spacing: 0) {
            cifra("Cobrado", Formato.pesos(cobrado, moneda: ajustes.moneda), fuerte: true)
            raya
            cifra("Pesado", Formato.cantidad(pesado) + " lb")
            raya
            cifra("Listos", "\(cobrados.count)/\(encargos.count)")
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(tema.superficie, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func cifra(_ rotulo: String, _ valor: String, fuerte: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(rotulo).font(tema.texto(11, .bold)).foregroundStyle(tema.neutral700)
            Text(valor)
                .font(tema.titulo(fuerte ? 22 : 18))
                .foregroundStyle(fuerte ? tema.acento2_700 : tema.texto)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private var raya: some View {
        Rectangle().fill(tema.divisor).frame(width: 1, height: 28)
    }

    private var filtroDeVendedores: some View {
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
        }
        .scrollIndicators(.hidden)
    }

    private func pastilla(_ texto: String, puesta: Bool, al: @escaping () -> Void) -> some View {
        Button(action: al) {
            Text(texto)
                .font(tema.texto(13, .heavy))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(puesta ? tema.neutral900 : tema.superficie, in: Capsule())
                .foregroundStyle(puesta ? (tema.oscuro ? tema.texto : tema.neutral100) : tema.neutral700)
        }
        .buttonStyle(.plain)
    }

    private var sinEncargos: some View {
        PantallaVacia(icono: .balanza,
                      titulo: "Nadie ha encargado todavía",
                      texto: "Anota el primero: cliente, producto y cuánto pidió. El precio sale del catálogo y el total se calcula solo cuando lo peses.") {
            Button("Anotar un encargo") { nuevoEncargo = true }
                .buttonStyle(BotonPrincipal())
        }
    }

    // MARK: - Las tres maneras de mirar lo mismo

    @ViewBuilder
    private var porDespachar: some View {
        switch ajustes.vista {
        case .tarjetas: ForEach(pendientes) { o in tarjeta(o) }
        case .tabla:
            cabeceraTabla
            VStack(spacing: 4) { ForEach(pendientes) { o in filaTabla(o) } }
        case .compacta:
            VStack(spacing: 0) { ForEach(pendientes) { o in filaCompacta(o) } }
        }
    }

    @ViewBuilder
    private var yaCobrados: some View {
        switch ajustes.vista {
        case .tarjetas: VStack(spacing: 0) { ForEach(cobrados) { o in filaCobrado(o) } }
        case .tabla:
            cabeceraTabla
            VStack(spacing: 4) { ForEach(cobrados) { o in filaTabla(o) } }
        case .compacta:
            VStack(spacing: 0) { ForEach(cobrados) { o in filaCompacta(o) } }
        }
    }

    private var cabeceraTabla: some View {
        HStack(spacing: 8) {
            Text("CLIENTE").frame(maxWidth: .infinity, alignment: .leading)
            Text("CANT.").frame(width: 54, alignment: .trailing)
            Text("TOTAL").frame(width: 66, alignment: .trailing)
            Color.clear.frame(width: 38)
        }
        .font(tema.texto(10, .heavy))
        .tracking(0.7)
        .foregroundStyle(tema.neutral700)
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
    }

    /// LA TABLA.
    ///
    /// Se quitó la columna de precio: es la que menos se mira y la que más
    /// ancho comía, y sigue estando en la ficha. Lo que gana ese sitio es el
    /// botón de cobrar, que antes obligaba a abrir el encargo.
    private func filaTabla(_ o: Encargo) -> some View {
        HStack(spacing: 8) {
            Button { abierto = o } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(o.cliente).font(tema.texto(15, .bold)).lineLimit(1)
                            if !o.salida.cobra { marcaDeSalida(o) }
                        }
                        Text([o.producto,
                              o.precioAplicado > 0 ? "\(Formato.entero(o.precioAplicado))/\(o.unidad)" : nil,
                              o.registradoPor.isEmpty ? nil : o.registradoPor]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(tema.texto(11.5)).foregroundStyle(tema.neutral700).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("\(Formato.cantidad(o.cantidad)) \(o.unidad)")
                        .font(tema.texto(13, .semibold)).foregroundStyle(tema.neutral700)
                        .frame(width: 54, alignment: .trailing)
                    Text(o.salida.cobra ? Formato.entero(o.total) : "—")
                        .font(tema.texto(15, .heavy))
                        .frame(width: 66, alignment: .trailing)
                }
                .foregroundStyle(o.cobrado ? tema.neutral700 : tema.texto)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            botonDeCobro(o)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(minHeight: 52)
        .background(tema.superficie.opacity(o.cobrado ? 0.45 : 1),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contextMenu { if o.cobrado { menuDeCobrado(o) } }
    }

    private func filaCompacta(_ o: Encargo) -> some View {
        HStack(spacing: 10) {
            Button { abierto = o } label: {
                HStack(spacing: 10) {
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
                        .font(tema.texto(15, .heavy))
                }
                .foregroundStyle(o.cobrado ? tema.neutral700 : tema.texto)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            botonDeCobro(o, pequeno: true)
        }
        .padding(.vertical, 6)
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) {
            Rectangle().fill(tema.divisor).frame(height: 1)
        }
        .contextMenu { if o.cobrado { menuDeCobrado(o) } }
    }

    /// EL BOTÓN DE COBRAR, EN TODAS LAS VISTAS.
    ///
    /// Cobrar es lo que se hace con un encargo, y tenerlo solo dentro de la
    /// ficha convertía un toque en tres. Aquí está siempre a la derecha, donde
    /// cae el pulgar: sin cobrar es un círculo vacío, cobrado es el visto.
    private func botonDeCobro(_ o: Encargo, pequeno: Bool = false) -> some View {
        let lado: CGFloat = pequeno ? 30 : 34
        return Group {
            if o.cobrado {
                Menu { menuDeCobrado(o) } label: {
                    Marcador(puesto: true, tamano: lado)
                }
            } else {
                Button {
                    cobra(o, "Efectivo")
                } label: {
                    Marcador(puesto: false, tamano: lado)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 38, height: 44)
        .accessibilityLabel(o.cobrado ? "Cobrado a \(o.cliente)" : "Cobrar a \(o.cliente)")
    }

    private func marcaDeSalida(_ o: Encargo) -> some View {
        Text(o.salida.etiqueta.uppercased())
            .font(tema.texto(9, .heavy)).tracking(0.5)
            .foregroundStyle(tema.acento800)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tema.acento200, in: Capsule())
    }

    // MARK: - La tarjeta

    private func tarjeta(_ o: Encargo) -> some View {
        Tarjeta {
            Button { abierto = o } label: {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(o.cliente).font(tema.texto(17, .heavy))
                            if !o.salida.cobra { marcaDeSalida(o) }
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
                    Button("Anotar la \(o.salida.etiqueta.lowercased())") { cobra(o, o.salida.etiqueta) }
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
        HStack(spacing: 10) {
            Button { comprobante = o } label: {
                HStack(spacing: 12) {
                    Text(Formato.inicial(o.cliente))
                        .font(tema.texto(15, .heavy))
                        .foregroundStyle(tema.acento2_800)
                        .frame(width: 38, height: 38)
                        .background(tema.acento2_200, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(o.cliente).font(tema.texto(15, .bold))
                        Text("\(o.producto) · \(Formato.cantidad(o.cantidad)) \(o.unidad) × \(Formato.precio(o.precioAplicado, moneda: ajustes.moneda))")
                            .font(tema.texto(12)).foregroundStyle(tema.neutral700).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Formato.pesos(o.total, moneda: ajustes.moneda)).font(tema.texto(15, .heavy))
                        Text([o.metodo, o.cobradoEn.map(Formato.hora)].compactMap { $0 }.joined(separator: " · "))
                            .font(tema.texto(11)).foregroundStyle(tema.neutral700)
                    }
                }
                .foregroundStyle(tema.texto)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            botonDeCobro(o, pequeno: true)
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Rectangle().fill(tema.divisor).frame(height: 1).padding(.leading, 50)
        }
        .contextMenu { menuDeCobrado(o) }
    }

    @ViewBuilder
    private func menuDeCobrado(_ o: Encargo) -> some View {
        Button { descobra(o) } label: {
            Label("Volver a dejarlo pendiente", systemImage: "arrow.uturn.backward")
        }
        if gente.count > 1 {
            Menu {
                ForEach(gente, id: \.self) { quien in
                    Button { anota(o, aNombreDe: quien) } label: {
                        if quien == o.registradoPor {
                            Label(quien, systemImage: "checkmark")
                        } else { Text(quien) }
                    }
                }
            } label: { Label("Lo cobró…", systemImage: "person.2") }
        }
        Button { comprobante = o } label: { Label("Ver el comprobante", systemImage: "doc.text") }
    }

    // MARK: - Lo que hace

    private func ajusta(_ o: Encargo, _ signo: Double) {
        let paso = Unidad.de(o.unidad).paso
        o.cantidad = max(0, ((o.cantidad + signo * paso) * 100).rounded() / 100)
        o.toco()
        try? ctx.save()
    }

    private func cobra(_ o: Encargo, _ metodo: String) {
        if ajustes.confirmarCobro {
            porConfirmar = PorCobrar(encargo: o, metodo: metodo)
        } else {
            cobraYa(o, metodo, aNombreDe: "")
        }
    }

    private func cobraYa(_ o: Encargo, _ metodo: String, aNombreDe quien: String) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let antes = (o.estado, o.metodo, o.cobradoEn, o.registradoPor)
        o.estado = "cobrado"
        o.metodo = metodo
        o.cobradoEn = .now
        if !quien.isEmpty { o.registradoPor = quien }
        o.toco()
        try? ctx.save()
        Escaparate.actualiza(ctx)
        Task { await sincronizador?.sincroniza() }
        comprobante = o

        sesion.avisa(o.salida.cobra ? "Cobrado a \(o.cliente)" : "\(o.salida.etiqueta) anotada",
                     .bien, accion: "Deshacer") {
            o.estado = antes.0; o.metodo = antes.1
            o.cobradoEn = antes.2; o.registradoPor = antes.3
            o.toco()
            try? ctx.save()
            Task { await sincronizador?.sincroniza() }
        }
    }

    private func descobra(_ o: Encargo) {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        o.estado = "pendiente"
        o.metodo = ""
        o.cobradoEn = nil
        o.toco()
        try? ctx.save()
        Escaparate.actualiza(ctx)
        Task { await sincronizador?.sincroniza() }
        sesion.avisa("\(o.cliente) vuelve a quedar pendiente")
    }

    private func anota(_ o: Encargo, aNombreDe quien: String) {
        o.registradoPor = quien
        o.toco()
        try? ctx.save()
        Task { await sincronizador?.sincroniza() }
    }

    private var gente: [String] {
        var v = [yo]
        for n in (companeros + quienes) where !n.isEmpty && !v.contains(n) { v.append(n) }
        return v
    }
    private var yo: String {
        let n = sesion.usuario?.nombre ?? ""
        return n.isEmpty ? "Yo" : n
    }

    private func cargaCompaneros() async {
        guard !evento.grupoId.isEmpty else { companeros = []; return }
        companeros = (try? await Compartir.miembros(de: evento.grupoId, .grupo))?
            .map(\.comoSeLlama) ?? []
    }
}
