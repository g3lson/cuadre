import SwiftUI
import SwiftData

/// 13 · EL CUADRE.
///
/// El final del día. Antes se llamaba «Historial y métricas» y era una pantalla
/// que nadie abría; ahora contesta la única pregunta que se hace de verdad al
/// cerrar: cuánto me quedó, y dónde está.
struct CuadreView: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(\.sincronizador) private var sincronizador
    @Environment(Sesion.self) private var sesion

    @State private var dia = Date()
    @State private var reporte: Reportes.Compartible?
    @State private var haciendo = false
    @State private var error: String?
    @State private var mandando = false

    // Sin usarlas directamente, pero SwiftData necesita ver las consultas para
    // volver a pintar cuando cambie un encargo o se cierre una compra.
    @Query(filter: #Predicate<Encargo> { $0.borrado == nil }) private var encargos: [Encargo]
    @Query(filter: #Predicate<Lista> { $0.borrado == nil }) private var listas: [Lista]

    private var ajustes: Ajustes { Almacen.ajustes(ctx, de: sesion.usuario?.id ?? "") }
    private var c: Almacen.Cuentas { Almacen.cuentas(ctx, del: dia) }
    private var hayAlgo: Bool { c.vendido > 0 || c.comprado > 0 || c.porCobrar > 0 || c.regalado > 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    cabecera
                    if hayAlgo {
                        tarjetaGanancia
                        desglose
                        loQueSalioSinCobrar
                        dondeEsta
                        acciones
                    } else {
                        vacio
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            .refreshable { await sincronizador?.sincroniza() }
            .fondoDelTema(tema)
        }
        .onChange(of: dia) { _, _ in reporte = nil }
    }

    // MARK: - Trozos

    private var cabecera: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Formato.diaLargo(dia)).font(tema.texto(15)).foregroundStyle(tema.neutral700)
                Text("El cuadre").font(tema.titulo(38)).foregroundStyle(tema.texto)
            }
            Spacer()
            HStack(spacing: 4) {
                Button { mueve(-1) } label: {
                    IconoView(icono: .atras, tamano: 18)
                }
                .buttonStyle(BotonRedondo())
                .accessibilityLabel("Día anterior")

                Button { mueve(1) } label: {
                    IconoView(icono: .chevron, tamano: 18)
                }
                .buttonStyle(BotonRedondo())
                .disabled(Calendar.current.isDateInToday(dia))
                .opacity(Calendar.current.isDateInToday(dia) ? 0.4 : 1)
                .accessibilityLabel("Día siguiente")
            }
        }
        .padding(.top, 10)
    }

    private var tarjetaGanancia: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(tema.fondo.opacity(0.14))
                .frame(width: 150, height: 150)
                .offset(x: 42, y: -42)

            VStack(alignment: .leading, spacing: 6) {
                Text("Te quedó de ganancia").font(tema.texto(14, .bold))
                Text(Formato.pesos(c.ganancia, moneda: ajustes.moneda))
                    .font(tema.titulo(52))
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(c.vendido > 0
                     ? "Margen de \(Int((c.margen * 100).rounded()))% sobre lo vendido"
                     : "Todavía no has cobrado nada hoy")
                    .font(tema.texto(14))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .foregroundStyle(tema.oscuro ? tema.acento2_800 : tema.fondo)
        .background(tema.acento2_700, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private var desglose: some View {
        Bloque {
            linea("Vendiste", Formato.pesos(c.vendido, moneda: ajustes.moneda))
            linea("Te costó la mercancía", "− " + Formato.pesos(c.costo, moneda: ajustes.moneda))
            if c.regalado > 0 {
                linea("Regalaste y donaste", "− " + Formato.pesos(c.regalado, moneda: ajustes.moneda),
                      tinta: tema.acento700)
            }
            linea("Gastaste en compras", "− " + Formato.pesos(c.comprado, moneda: ajustes.moneda))
            linea("Falta por cobrar", Formato.pesos(c.porCobrar, moneda: ajustes.moneda),
                  tinta: c.porCobrar > 0 ? tema.acento700 : nil, ultima: true)
        }
    }

    private func linea(_ rotulo: String, _ valor: String, tinta: Color? = nil, ultima: Bool = false) -> some View {
        FilaAjuste(titulo: rotulo, ultima: ultima) {
            Text(valor).font(tema.texto(16, .bold)).foregroundStyle(tinta ?? tema.texto)
        }
    }

    /// Lo que salió sin cobrarse, con nombre y apellido: el cuadre tiene que
    /// poder decir a quién se le regaló qué.
    @ViewBuilder
    private var loQueSalioSinCobrar: some View {
        if !c.salidas.isEmpty {
            Rotulo("Salió sin cobrarse · \(c.salidas.count)").padding(.top, 6)
            Bloque {
                ForEach(Array(c.salidas.enumerated()), id: \.element.id) { i, o in
                    FilaAjuste(titulo: o.cliente,
                               detalle: "\(o.salida.etiqueta) · \(o.producto) · \(Formato.cantidad(o.cantidad)) \(o.unidad)",
                               ultima: i == c.salidas.count - 1) {
                        Text("− " + Formato.pesos(o.costoTotal, moneda: ajustes.moneda))
                            .font(tema.texto(15, .bold))
                            .foregroundStyle(tema.acento700)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var dondeEsta: some View {
        if c.vendido > 0 {
            Rotulo("¿Dónde está el dinero?").padding(.top, 6)
            VStack(spacing: 12) {
                barra("Efectivo en mano", c.efectivo, tema.acento)
                barra("Transferencias", c.transferencia, tema.acento2)
            }
            .padding(.horizontal, 4)
        }
    }

    private func barra(_ rotulo: String, _ monto: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(rotulo).font(tema.texto(15, .bold))
                Spacer()
                Text(Formato.pesos(monto, moneda: ajustes.moneda)).font(tema.texto(15, .heavy))
            }
            Barra(porcentaje: c.vendido > 0 ? monto / c.vendido : 0, color: color, alto: 12)
        }
        .foregroundStyle(tema.texto)
    }

    @ViewBuilder
    private var acciones: some View {
        VStack(spacing: 10) {
            if c.vendido > 0 {
                Button {
                    Task { await mandaAChinola() }
                } label: {
                    if mandando { ProgressView().tint(tema.sobreAcento) }
                    else { Text(sesion.chinola == nil ? "Conectar Chinola para anotarlo" : "Enviar a Chinola") }
                }
                .buttonStyle(BotonPrincipal())
                .disabled(mandando || sesion.chinola == nil)
            }

            if let reporte {
                ShareLink(item: reporte.web) {
                    Text("Compartir el resumen").frame(maxWidth: .infinity)
                }
                .buttonStyle(BotonSuave())
                ShareLink(item: reporte.pdf) {
                    Text("Compartir el PDF").frame(maxWidth: .infinity)
                }
                .buttonStyle(BotonFantasma())
            } else {
                Button {
                    Task { await haz() }
                } label: {
                    if haciendo { ProgressView() } else { Text("Crear el resumen en PDF") }
                }
                .buttonStyle(BotonSuave())
                .disabled(haciendo)
            }

            if let error {
                Text(error).font(tema.texto(14)).foregroundStyle(tema.acento800)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 8)
    }

    private var vacio: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Calendar.current.isDateInToday(dia) ? "Hoy todavía no hay nada" : "Ese día no hubo movimiento")
                .font(tema.titulo(24)).foregroundStyle(tema.texto)
            Text("Aquí sale lo que cobraste, lo que te costó la mercancía y lo que gastaste comprando. Se llena solo según vas cerrando compras y cobrando encargos.")
                .font(tema.texto(15)).foregroundStyle(tema.neutral700)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tema.superficie, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.top, 8)
    }

    // MARK: - Lo que hace

    /// A nombre de qué negocio se despachó el día. Si el día tuvo ventas de
    /// dos negocios distintos no se inventa uno: el reporte sale como Cuadre.
    private var negocioDelDia: String {
        let eventos = ((try? ctx.fetch(FetchDescriptor<Evento>())) ?? []).filter(\.vivo)
        let grupos = ((try? ctx.fetch(FetchDescriptor<Grupo>())) ?? []).filter(\.vivo)
        let suyos = Set((c.cobrados + c.salidas).map(\.eventoId))
        let nombres = Set(eventos.filter { suyos.contains($0.id) }.map { e -> String in
            e.negocio.isEmpty ? (grupos.first { $0.id == e.grupoId }?.nombre ?? "") : e.negocio
        }.filter { !$0.isEmpty })
        return nombres.count == 1 ? (nombres.first ?? "") : ""
    }

    private func mueve(_ dias: Int) {
        guard let nuevo = Calendar.current.date(byAdding: .day, value: dias, to: dia) else { return }
        if dias > 0, nuevo > Date() { return }
        withAnimation(.snappy(duration: 0.2)) { dia = nuevo }
    }

    private func haz() async {
        haciendo = true
        error = nil
        defer { haciendo = false }
        do {
            reporte = try await Reportes.delCuadre(.init(
                fecha: Formato.fechaCorta(dia),
                vendido: c.vendido, costo: c.costo, comprado: c.comprado,
                porCobrar: c.porCobrar, regalado: c.regalado,
                negocio: negocioDelDia,
                encargos: (c.cobrados + c.salidas).map {
                    .init(cliente: $0.cliente, producto: $0.producto, unidad: $0.unidad,
                          metodo: $0.salida.cobra ? $0.metodo : $0.salida.etiqueta,
                          cantidad: $0.cantidad, total: $0.total)
                }))
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription
                ?? "No pude crear el resumen. Hace falta conexión."
        }
    }

    /// La venta del día entra en Chinola como un ingreso, no como un gasto: la
    /// compra ya entró por su lado cuando se cerró la lista.
    private func mandaAChinola() async {
        mandando = true
        error = nil
        defer { mandando = false }
        let sello = Formato.fechaCorta(dia)
        do {
            _ = try await ChinolaApi.anota(
                [.init(concepto: "Ventas del día", monto: c.vendido, categoria: nil,
                       tipo: "Ingreso", idempotencia: "cuadre:ventas:\(sello)")],
                fecha: dia, libreta: sesion.chinola?.libreta, medio: sesion.chinola?.medio)
            sesion.avisa("Ventas del día anotadas en Chinola", .bien)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Chinola no aceptó el movimiento."
        }
    }
}
