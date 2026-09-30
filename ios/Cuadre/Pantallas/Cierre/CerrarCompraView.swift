import SwiftUI
import SwiftData

/// 05–09 · CERRAR LA COMPRA.
///
/// El final del recorrido, en dos pasos y ni uno más: qué hacer con lo que no
/// había, y el resumen. Desde el resumen salen las dos cosas que se hacen
/// después —pasar el gasto a Chinola y compartir el reporte— y no antes: quien
/// solo quiere cerrar y seguir, cierra y sigue.
struct CerrarCompraView: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var cerrarPantalla
    @Environment(\.sincronizador) private var sincronizador
    @Environment(Sesion.self) private var sesion

    let lista: Lista
    var alTerminar: () -> Void

    private enum Paso { case faltantes, resumen, chinola, reporte }
    @State private var paso: Paso = .faltantes
    @State private var destinos: [String: Almacen.Destino] = [:]
    @State private var yaCerrada = false

    @State private var reporte: Reportes.Compartible?
    @State private var haciendoReporte = false
    @State private var errorReporte: String?

    private var articulos: [Articulo] { Almacen.articulos(ctx, de: lista.id) }
    private var comprados: [Articulo] { articulos.filter(\.hecho) }
    /// Sin los que se quedaron sin nombre: esos no son productos que faltaron,
    /// son fichas que alguien abrió y cerró.
    private var faltaron: [Articulo] {
        articulos.filter { !$0.hecho && !$0.nombre.trimmingCharacters(in: .whitespaces).isEmpty }
    }
    private var pagado: Double { comprados.reduce(0) { $0 + $1.total } }
    private var diferencia: Double { lista.presupuesto - pagado }
    private var ajustes: Ajustes { Almacen.ajustes(ctx, de: sesion.usuario?.id ?? "") }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch paso {
                    case .faltantes: pasoFaltantes
                    case .resumen: pasoResumen
                    case .chinola: ChinolaEnvio(lista: lista, pagado: pagado,
                                                porCategoria: porCategoria,
                                                alVolver: { paso = .resumen })
                    case .reporte: pasoReporte
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .fondoDelTema(tema)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        switch paso {
                        case .faltantes: cerrarPantalla()
                        case .resumen: if faltaron.isEmpty && !yaCerrada { cerrarPantalla() } else { paso = .faltantes }
                        case .chinola, .reporte: paso = .resumen
                        }
                    } label: {
                        HStack(spacing: 4) {
                            IconoView(icono: .atras, tamano: 18)
                            Text(rotuloAtras).font(tema.texto(15, .bold))
                        }
                        .foregroundStyle(tema.acento700)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(rotuloPaso).font(tema.texto(13, .heavy)).foregroundStyle(tema.neutral700)
                }
            }
        }
        .onAppear {
            // Si no faltó nada, el primer paso sobra.
            if faltaron.isEmpty { paso = .resumen; cierra() }
        }
    }

    private var rotuloAtras: String {
        switch paso {
        case .faltantes: return "Lista"
        case .resumen: return faltaron.isEmpty && !yaCerrada ? "Lista" : "Faltantes"
        case .chinola, .reporte: return "Resumen"
        }
    }
    private var rotuloPaso: String {
        switch paso {
        case .faltantes: return "Cerrar compra · 1 de 2"
        case .resumen: return "Cerrar compra · 2 de 2"
        case .chinola: return "Chinola"
        case .reporte: return "Reporte"
        }
    }

    // MARK: - Paso 1 · te faltó algo

    @ViewBuilder
    private var pasoFaltantes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Te faltó algo").font(tema.titulo(34)).foregroundStyle(tema.texto)
            Text("Compraste \(comprados.count) de \(articulos.count). ¿Qué hacemos con lo que no había?")
                .font(tema.texto(15))
                .foregroundStyle(tema.neutral700)
                .fixedSize(horizontal: false, vertical: true)
        }

        ForEach(faltaron) { a in
            Tarjeta {
                HStack(alignment: .firstTextBaseline) {
                    Text(a.nombre.isEmpty ? "Producto nuevo" : a.nombre).font(tema.texto(18, .heavy))
                    Spacer(minLength: 8)
                    Text("\(Formato.cantidad(a.cantidad)) \(a.unidad) · \(Formato.pesos(a.total, moneda: ajustes.moneda))")
                        .font(tema.texto(14))
                        .foregroundStyle(tema.neutral700)
                }
                ForEach(Almacen.Destino.allCases) { d in
                    Button {
                        withAnimation(.snappy(duration: 0.18)) { destinos[a.id] = d }
                    } label: {
                        HStack(spacing: 12) {
                            Radio(elegido: (destinos[a.id] ?? .proxima) == d)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.titulo).font(tema.texto(15, .bold))
                                Text(d.detalle(tienda: lista.tienda))
                                    .font(tema.texto(13))
                                    .foregroundStyle(tema.neutral700)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background((destinos[a.id] ?? .proxima) == d ? tema.acento2_200 : tema.fondo,
                                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .foregroundStyle(tema.texto)
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        Button("Seguir") {
            cierra()
            withAnimation(.snappy) { paso = .resumen }
        }
        .buttonStyle(BotonPrincipal())
    }

    // MARK: - Paso 2 · el resumen

    @ViewBuilder
    private var pasoResumen: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Circle().fill(tema.acento2_700)
                IconoView(icono: .check, tamano: 36, grosor: 3).foregroundStyle(tema.fondo)
            }
            .frame(width: 72, height: 72)
            Text("¡Cuadró!").font(tema.titulo(40)).foregroundStyle(tema.texto)
            Text("Pagaste \(Formato.pesos(pagado, moneda: ajustes.moneda))"
                 + (lista.tienda.isEmpty ? "" : " en \(lista.tienda)")
                 + " · \(comprados.count) producto\(comprados.count == 1 ? "" : "s")")
                .font(tema.texto(15))
                .foregroundStyle(tema.neutral700)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)

        HStack(spacing: 8) {
            cifra("Presupuesto", lista.presupuesto > 0 ? Formato.pesos(lista.presupuesto, moneda: ajustes.moneda) : "—")
            cifra("Pagaste", Formato.pesos(pagado, moneda: ajustes.moneda))
            if lista.presupuesto > 0 {
                cifra(diferencia >= 0 ? "Te sobró" : "Te pasaste",
                      Formato.pesos(abs(diferencia), moneda: ajustes.moneda),
                      fondo: diferencia >= 0 ? tema.acento2_200 : tema.acento200,
                      tinta: diferencia >= 0 ? tema.acento2_800 : tema.acento800)
            } else {
                cifra("Productos", "\(comprados.count)")
            }
        }

        if !faltaron.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Rotulo("Lo que faltó", color: tema.acento800)
                ForEach(faltaron) { a in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(a.nombre).font(tema.texto(15, .bold))
                        Spacer(minLength: 8)
                        Text((destinos[a.id] ?? .proxima).corto)
                            .font(tema.texto(13, .semibold))
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .foregroundStyle(tema.acento800)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tema.acento100, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }

        Grupo {
            Button { paso = .chinola } label: {
                FilaAjuste(titulo: "Pasar el gasto a Chinola",
                           detalle: sesion.chinola == nil ? "Sin conectar" : (lista.chinolaNota.isEmpty ? "Pendiente" : lista.chinolaNota)) {
                    IconoView(icono: .chevron, tamano: 16, grosor: 3).foregroundStyle(tema.neutral500)
                }
            }
            .buttonStyle(.plain)

            Button { paso = .reporte } label: {
                FilaAjuste(titulo: "Reporte de la compra",
                           detalle: "Para ti o para quien te mandó a comprar", ultima: true) {
                    IconoView(icono: .chevron, tamano: 16, grosor: 3).foregroundStyle(tema.neutral500)
                }
            }
            .buttonStyle(.plain)
        }

        Button("Listo") {
            Task { await sincronizador?.sincroniza() }
            alTerminar()
            cerrarPantalla()
        }
        .buttonStyle(BotonPrincipal())
        .padding(.top, 4)
    }

    private func cifra(_ rotulo: String, _ valor: String, fondo: Color? = nil, tinta: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(rotulo.uppercased()).font(tema.texto(11, .heavy)).tracking(0.6)
                .foregroundStyle(tinta ?? tema.neutral700)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(valor).font(tema.texto(16, .heavy)).foregroundStyle(tinta ?? tema.texto)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fondo ?? tema.superficie, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - El reporte

    @ViewBuilder
    private var pasoReporte: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reporte de la compra").font(tema.titulo(30)).foregroundStyle(tema.texto)
            Text("Una página con lo que compraste, lo que te costó y lo que faltó. Se abre con un enlace o se guarda en PDF.")
                .font(tema.texto(15)).foregroundStyle(tema.neutral700)
                .fixedSize(horizontal: false, vertical: true)
        }

        Tarjeta {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tema.acento200)
                    IconoView(icono: .documento, tamano: 20).foregroundStyle(tema.acento800)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lista.nombre).font(tema.texto(16, .bold))
                    Text("\(comprados.count) productos · \(Formato.pesos(pagado, moneda: ajustes.moneda))")
                        .font(tema.texto(13)).foregroundStyle(tema.neutral700)
                }
                Spacer(minLength: 0)
            }
        }

        if let reporte {
            ShareLink(item: reporte.web) {
                Text("Compartir el enlace").frame(maxWidth: .infinity)
            }
            .buttonStyle(BotonPrincipal())

            ShareLink(item: reporte.pdf) {
                Text("Compartir el PDF").frame(maxWidth: .infinity)
            }
            .buttonStyle(BotonSuave())

            Link(destination: reporte.web) {
                Text("Verlo primero").frame(maxWidth: .infinity)
            }
            .buttonStyle(BotonFantasma())
        } else {
            Button {
                Task { await haz() }
            } label: {
                if haciendoReporte { ProgressView().tint(tema.sobreAcento) } else { Text("Crear el reporte") }
            }
            .buttonStyle(BotonPrincipal())
            .disabled(haciendoReporte)
        }

        if let errorReporte {
            Text(errorReporte).font(tema.texto(14)).foregroundStyle(tema.acento800)
        }
    }

    private func haz() async {
        haciendoReporte = true
        errorReporte = nil
        defer { haciendoReporte = false }
        do {
            reporte = try await Reportes.deCompra(.init(
                titulo: lista.nombre,
                tienda: lista.tienda,
                fecha: Formato.fechaCorta(lista.cerradaEn ?? lista.fecha),
                presupuesto: lista.presupuesto,
                pagado: pagado,
                productos: comprados.map {
                    .init(nombre: $0.nombre, nota: $0.nota, unidad: $0.unidad,
                          cantidad: $0.cantidad, precio: $0.precio)
                },
                faltantes: faltaron.map {
                    .init(nombre: $0.nombre, unidad: $0.unidad, cantidad: $0.cantidad,
                          destino: (destinos[$0.id] ?? .proxima).hecho)
                },
                chinola: lista.chinolaNota.isEmpty ? nil : lista.chinolaNota))
        } catch {
            errorReporte = (error as? LocalizedError)?.errorDescription
                ?? "No pude crear el reporte. Hace falta conexión."
        }
    }

    // MARK: - Lo que se guarda

    /// El gasto partido por categoría, por si se manda así a Chinola.
    private var porCategoria: [(String, Double)] {
        var suma: [String: Double] = [:]
        for a in comprados { suma[a.categoria, default: 0] += a.total }
        return suma.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    private func cierra() {
        guard !yaCerrada, !lista.cerrada else { yaCerrada = true; return }
        Almacen.cierra(ctx, lista: lista, destinos: destinos)
        try? ctx.save()
        yaCerrada = true
        Task { await sincronizador?.sincroniza() }
    }
}
