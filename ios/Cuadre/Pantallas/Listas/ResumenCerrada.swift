import SwiftUI
import SwiftData

/// UNA COMPRA YA CUADRADA.
///
/// Solo lectura: lo que se compró, lo que costó y dónde acabó el gasto. Y dos
/// salidas que se siguen usando después —compartir el reporte y pasarlo a
/// Chinola si se dejó pendiente—, porque eso casi nunca se hace en el momento.
struct ResumenCerrada: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(Sesion.self) private var sesion

    let lista: Lista
    @State private var reporte: Reportes.Compartible?
    @State private var haciendo = false
    @State private var error: String?
    @State private var aChinola = false

    private var articulos: [Articulo] { Almacen.articulos(ctx, de: lista.id).filter(\.hecho) }
    private var pagado: Double { articulos.reduce(0) { $0 + $1.total } }
    private var ajustes: Ajustes { Almacen.ajustes(ctx, de: sesion.usuario?.id ?? "") }
    private var porCategoria: [(String, Double)] {
        var suma: [String: Double] = [:]
        for a in articulos { suma[a.categoria, default: 0] += a.total }
        return suma.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lista.nombre).font(tema.titulo(32)).foregroundStyle(tema.texto)
                    Text([lista.tienda, Formato.dia(lista.cerradaEn ?? lista.fecha)]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(tema.texto(14)).foregroundStyle(tema.neutral700)
                }

                HStack(spacing: 8) {
                    cifra("Pagaste", Formato.pesos(pagado, moneda: ajustes.moneda))
                    if lista.presupuesto > 0 {
                        let d = lista.presupuesto - pagado
                        cifra(d >= 0 ? "Te sobró" : "Te pasaste",
                              Formato.pesos(abs(d), moneda: ajustes.moneda),
                              fondo: d >= 0 ? tema.acento2_200 : tema.acento200,
                              tinta: d >= 0 ? tema.acento2_800 : tema.acento800)
                    }
                    cifra("Productos", "\(articulos.count)")
                }

                if !lista.notaCierre.isEmpty, lista.notaCierre != "Compraste todo" {
                    VStack(alignment: .leading, spacing: 6) {
                        Rotulo("Faltó", color: tema.acento800)
                        Text(lista.notaCierre).font(tema.texto(15))
                    }
                    .foregroundStyle(tema.acento800)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(tema.acento100, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }

                Rotulo("Lo que compraste")
                VStack(spacing: 0) {
                    ForEach(articulos) { a in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(a.nombre).font(tema.texto(15, .semibold))
                                if !a.nota.isEmpty {
                                    Text(a.nota).font(tema.texto(12)).foregroundStyle(tema.neutral700)
                                }
                            }
                            Spacer(minLength: 6)
                            Text("\(Formato.cantidad(a.cantidad)) \(a.unidad)")
                                .font(tema.texto(13)).foregroundStyle(tema.neutral700)
                            Text(Formato.pesos(a.total, moneda: ajustes.moneda))
                                .font(tema.texto(15, .heavy))
                                .frame(minWidth: 72, alignment: .trailing)
                        }
                        .padding(.vertical, 11)
                        .overlay(alignment: .bottom) { Rectangle().fill(tema.divisor).frame(height: 1) }
                    }
                }

                Bloque {
                    Button { aChinola = true } label: {
                        FilaAjuste(titulo: "Chinola",
                                   detalle: lista.chinolaNota.isEmpty ? "Sin pasar todavía" : lista.chinolaNota) {
                            IconoView(icono: .chevron, tamano: 16, grosor: 3).foregroundStyle(tema.neutral500)
                        }
                    }
                    .buttonStyle(.plain)

                    if let reporte {
                        ShareLink(item: reporte.web) {
                            FilaAjuste(titulo: "Compartir el reporte", detalle: "Enlace o PDF", ultima: true) {
                                IconoView(icono: .compartir, tamano: 18).foregroundStyle(tema.acento700)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button { Task { await haz() } } label: {
                            FilaAjuste(titulo: "Crear el reporte",
                                       detalle: "Para ti o para quien te mandó a comprar", ultima: true) {
                                if haciendo { ProgressView() }
                                else { IconoView(icono: .documento, tamano: 18).foregroundStyle(tema.acento700) }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(haciendo)
                    }
                }

                if let error {
                    Text(error).font(tema.texto(14)).foregroundStyle(tema.acento800)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .fondoDelTema(tema)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $aChinola) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ChinolaEnvio(lista: lista, pagado: pagado, porCategoria: porCategoria) {
                            aChinola = false
                        }
                    }
                    .padding(.horizontal, 20)
                    // Despegado del agarradero de la hoja: sin esto, el título
                    // grande le pasa por encima.
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
                .fondoDelTema(tema)
                .navigationBarTitleDisplayMode(.inline)
            }
            .hojaDeCuadre(tema)
        }
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

    private func haz() async {
        haciendo = true
        error = nil
        defer { haciendo = false }
        do {
            reporte = try await Reportes.deCompra(.init(
                titulo: lista.nombre, tienda: lista.tienda,
                fecha: Formato.fechaCorta(lista.cerradaEn ?? lista.fecha),
                presupuesto: lista.presupuesto, pagado: pagado,
                productos: articulos.map {
                    .init(nombre: $0.nombre, nota: $0.nota, unidad: $0.unidad,
                          cantidad: $0.cantidad, precio: $0.precio)
                },
                faltantes: [],
                chinola: lista.chinolaNota.isEmpty ? nil : lista.chinolaNota))
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription
                ?? "No pude crear el reporte. Hace falta conexión."
        }
    }
}
