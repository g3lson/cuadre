import SwiftUI
import SwiftData

/// 10 · VENTAS — LA PANTALLA GENERAL.
///
/// Antes esta pestaña abría directamente dentro de un día de venta, y las demás
/// ventas vivían escondidas en un menú del título. Eso hacía dos cosas mal: no
/// había dónde ver de un vistazo cómo van los negocios, y el menú de abajo
/// —que es para saltar entre pantallas generales— se quedaba puesto mientras se
/// despachaba, comiéndose el sitio donde está la mano.
///
/// Así que esto es la portada: tus ventas, la de hoy arriba y con lo suyo a la
/// vista. Entrar en una la abre a pantalla completa, sin barra abajo, como
/// pasar de «Listas» a «En tienda».
struct VentasView: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(\.sincronizador) private var sincronizador
    @Environment(Sesion.self) private var sesion

    /// Cuál se está despachando. Vive en la raíz porque es lo que decide si el
    /// menú de abajo se ve o no.
    @Binding var abierta: String?

    @Query(filter: #Predicate<Evento> { $0.borrado == nil },
           sort: [SortDescriptor<Evento>(\.fecha, order: .reverse)])
    private var eventos: [Evento]
    @Query(filter: #Predicate<Encargo> { $0.borrado == nil })
    private var todos: [Encargo]

    @State private var nuevoEvento = Demo.abre("evento")
    @State private var aBorrar: Evento?
    @State private var editando: Evento?

    private var ajustes: Ajustes { Almacen.ajustes(ctx, de: sesion.usuario?.id ?? "") }
    private var abiertos: [Evento] { eventos.filter { $0.estado == "abierto" } }
    private var cerrados: [Evento] { eventos.filter { $0.estado != "abierto" } }

    var body: some View {
        Group {
            if let id = abierta, let e = eventos.first(where: { $0.id == id }) {
                EnLaVentaView(evento: e, ajustes: ajustes) { abierta = nil }
            } else {
                portada
            }
        }
        .onAppear {
            // Al entrar en la pestaña, si hay un día abierto se entra en él: es
            // donde se estaba y a lo que se vuelve cien veces al día.
            if abierta == nil, let hoy = laDeHoy { abierta = hoy.id }
        }
    }

    /// La venta en la que se está despachando ahora: la última que ya empezó.
    private var laDeHoy: Evento? {
        let manana = Calendar.current.startOfDay(for: .now).addingTimeInterval(86400)
        return abiertos.first { $0.fecha < manana }
    }

    // MARK: - La portada

    private var portada: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    encabezado

                    if eventos.isEmpty {
                        sinNada
                    } else {
                        if !abiertos.isEmpty {
                            ForEach(abiertos) { e in tarjetaDeVenta(e, abierta: true) }
                        }

                        Button { nuevoEvento = true } label: {
                            HStack(spacing: 8) {
                                IconoView(icono: .mas, tamano: 18)
                                Text("Empezar una venta")
                            }
                        }
                        .buttonStyle(BotonSuave())
                        .padding(.top, 2)

                        if !cerrados.isEmpty {
                            Rotulo("Ya cerradas").padding(.top, 8)
                            ForEach(cerrados.prefix(20)) { e in tarjetaDeVenta(e, abierta: false) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            .refreshable { await sincronizador?.sincroniza() }
            .fondoDelTema(tema)
        }
        .sheet(isPresented: $nuevoEvento) { NuevoEventoView().hojaDeCuadre(tema) }
        .sheet(item: $editando) { e in
            EditarVentaView(evento: e).hojaDeCuadre(tema)
        }
        .confirmationDialog("¿Borrar «\(aBorrar?.titulo ?? "")»?",
                            isPresented: .init(get: { aBorrar != nil },
                                               set: { if !$0 { aBorrar = nil } }),
                            titleVisibility: .visible) {
            Button("Borrar la venta", role: .destructive) { borra() }
            Button("Dejarla", role: .cancel) { aBorrar = nil }
        } message: {
            Text("Se va con todos sus encargos, cobrados o no. No hay papelera.")
        }
    }

    private var encabezado: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(saludo)
                    .font(tema.texto(15)).foregroundStyle(tema.neutral700)
                Text("Tus ventas").font(tema.titulo(34)).foregroundStyle(tema.texto)
            }
            Spacer(minLength: 8)
            Button { nuevoEvento = true } label: { IconoView(icono: .mas, tamano: 20) }
                .buttonStyle(BotonRedondo(relleno: tema.acento, tinta: tema.sobreAcento))
                .accessibilityLabel("Empezar una venta")
        }
        .padding(.top, 8)
    }

    /// El compilador tarda una eternidad si esto se escribe dentro de la
    /// vista: son cuatro operaciones encadenadas sobre opcionales y se pone a
    /// probar combinaciones de tipos.
    private var saludo: String {
        let nombre = sesion.usuario?.nombre ?? ""
        let pila = nombre.split(separator: " ").first.map(String.init) ?? ""
        return pila.isEmpty ? Formato.saludo() : "\(Formato.saludo()), \(pila)"
    }

    /// UNA VENTA, DESDE FUERA.
    ///
    /// Lo que se quiere saber sin entrar es siempre lo mismo: cuánto llevo
    /// cobrado y cuánta gente falta. Eso va en grande; el resto es contexto.
    private func tarjetaDeVenta(_ e: Evento, abierta esta: Bool) -> some View {
        let suyos = todos.filter { $0.eventoId == e.id }
        let cobrado = suyos.filter(\.cobrado).reduce(0) { $0 + $1.total }
        let faltan = suyos.filter { !$0.cobrado }.count
        let g = negocioDe(e)

        return Button {
            withAnimation(.snappy(duration: 0.2)) { abierta = e.id }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    if let g { LogoDelNegocio(grupo: g, lado: 26) }
                    Text(e.negocio.isEmpty ? (g?.nombre ?? Formato.dia(e.fecha)) : e.negocio)
                        .font(tema.texto(12, .heavy))
                        .foregroundStyle(esta ? tema.acento2_700 : tema.neutral700)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if esta {
                        Etiqueta(texto: "En vivo", punto: tema.acento2_700)
                    }
                }

                Text(e.titulo)
                    .font(tema.titulo(22))
                    .foregroundStyle(tema.texto)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Formato.pesos(cobrado, moneda: ajustes.moneda))
                        .font(tema.titulo(26))
                        .foregroundStyle(tema.texto)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text("cobrado").font(tema.texto(13)).foregroundStyle(tema.neutral700)
                    Spacer(minLength: 6)
                    Text(faltan == 0
                         ? (suyos.isEmpty ? "Sin encargos" : "Todo despachado")
                         : "\(faltan) por despachar")
                        .font(tema.texto(13, .bold))
                        .foregroundStyle(faltan == 0 ? tema.acento2_700 : tema.acento700)
                        .lineLimit(1)
                }

                Text(Formato.dia(e.fecha))
                    .font(tema.texto(12))
                    .foregroundStyle(tema.neutral500)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tema.superficie, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                if esta {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(tema.acento2_700.opacity(0.35), lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { editando = e } label: { Label("Editar la venta", systemImage: "pencil") }
            Button {
                e.estado = esta ? "cerrada" : "abierto"
                e.toco(); try? ctx.save()
                Task { await sincronizador?.sincroniza() }
            } label: {
                Label(esta ? "Cerrar la venta" : "Volver a abrirla",
                      systemImage: esta ? "lock" : "lock.open")
            }
            Button(role: .destructive) { aBorrar = e } label: {
                Label("Borrar la venta", systemImage: "trash")
            }
        }
    }

    private var sinNada: some View {
        PantallaVacia(icono: .balanza,
                      titulo: "Empieza un día de venta",
                      texto: "Una venta es un día de despacho: «Pescado del viernes», «Pollo del sábado». Dentro van los encargos de cada cliente, con su peso y su tarifa.") {
            Button("Empezar una venta") { nuevoEvento = true }
                .buttonStyle(BotonPrincipal())
        }
    }

    private func negocioDe(_ e: Evento) -> Grupo? {
        guard !e.grupoId.isEmpty else { return nil }
        return ((try? ctx.fetch(FetchDescriptor<Grupo>())) ?? [])
            .first { $0.vivo && $0.id == e.grupoId }
    }

    private func borra() {
        if let e = aBorrar {
            for o in Almacen.encargos(ctx, de: e.id) { o.entierro() }
            e.entierro()
            if abierta == e.id { abierta = nil }
            try? ctx.save()
            Task { await sincronizador?.sincroniza() }
        }
        aBorrar = nil
    }
}
