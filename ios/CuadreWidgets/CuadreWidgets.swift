import WidgetKit
import SwiftUI

/// LOS WIDGETS DE CUADRE.
///
/// Dos, y ninguno pide tocar nada: el de la compra, que dice cuánto llevas
/// gastado sin sacar el teléfono del bolsillo del delantal, y el del día de
/// venta, que dice cuántos encargos faltan.
///
/// El widget es otro proceso y no ve la base de datos de la app. Lee el resumen
/// que la app le deja en la carpeta compartida cada vez que algo cambia, y por
/// eso nunca tarda ni gasta batería: no calcula nada.
@main
struct CuadreWidgets: WidgetBundle {
    var body: some Widget {
        WidgetDeCompra()
        WidgetDeVenta()
        if #available(iOS 16.2, *) { ActividadDeVenta() }
    }
}

// MARK: - De dónde salen los datos

struct Entrada: TimelineEntry {
    let date: Date
    let r: Resumen
}

struct Proveedor: TimelineProvider {
    func placeholder(in: Context) -> Entrada { Entrada(date: .now, r: Resumen.muestra) }

    func getSnapshot(in ctx: Context, completion: @escaping (Entrada) -> Void) {
        completion(Entrada(date: .now, r: ctx.isPreview ? .muestra : (Puente.lee() ?? Resumen())))
    }

    func getTimeline(in: Context, completion: @escaping (Timeline<Entrada>) -> Void) {
        // Una sola entrada y «nunca»: quien manda aquí es la app, que refresca
        // el widget cuando cambia algo. Pedir refrescos por tiempo sería gastar
        // el presupuesto del sistema para no enterarse de nada nuevo.
        completion(Timeline(entries: [Entrada(date: .now, r: Puente.lee() ?? Resumen())],
                            policy: .never))
    }
}

extension Resumen {
    static var muestra: Resumen {
        var r = Resumen()
        r.lista = "Supermercado"; r.faltan = 7; r.llevados = 12
        r.gastado = 3240; r.presupuesto = 5000
        r.venta = "Pescado del viernes"; r.negocio = "El Muelle"
        r.porDespachar = 4; r.cobrado = 8750
        return r
    }
}

// MARK: - La compra

struct WidgetDeCompra: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CuadreCompra", provider: Proveedor()) { e in
            CaraDeCompra(r: e.r).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("La compra")
        .description("Cuánto llevas gastado y qué te falta por coger.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct CaraDeCompra: View {
    @Environment(\.widgetFamily) private var familia
    let r: Resumen

    var body: some View {
        if !r.hayCompra {
            Vacia(texto: "Sin compra abierta")
        } else if familia == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 1) {
                Text(r.lista).font(.headline).lineLimit(1)
                Text(pesosCortos(r.gastado, r.moneda)).font(.title3.bold())
                Text("Faltan \(r.faltan)").font(.caption)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(r.lista.uppercased())
                    .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(pesosCortos(r.gastado, r.moneda))
                    .font(.system(size: familia == .systemMedium ? 34 : 26, weight: .heavy))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                if r.presupuesto > 0 {
                    ProgressView(value: r.parte)
                        .tint(r.parte > 0.9 ? .orange : .green)
                    Text("de \(pesosCortos(r.presupuesto, r.moneda))")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 11))
                    Text("\(r.llevados) llevados · faltan \(r.faltan)")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(URL(string: "cuadre://tienda"))
        }
    }
}

// MARK: - La venta

struct WidgetDeVenta: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CuadreVenta", provider: Proveedor()) { e in
            CaraDeVenta(r: e.r).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("El día de venta")
        .description("Cuántos encargos faltan por despachar y cuánto llevas cobrado.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct CaraDeVenta: View {
    @Environment(\.widgetFamily) private var familia
    let r: Resumen

    var body: some View {
        if !r.hayVenta {
            Vacia(texto: "Sin venta abierta")
        } else if familia == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 1) {
                Text(r.venta).font(.headline).lineLimit(1)
                Text(pesosCortos(r.cobrado, r.moneda)).font(.title3.bold())
                Text("Faltan \(r.porDespachar)").font(.caption)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text((r.negocio.isEmpty ? r.venta : r.negocio).uppercased())
                    .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(pesosCortos(r.cobrado, r.moneda))
                    .font(.system(size: familia == .systemMedium ? 34 : 26, weight: .heavy))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("cobrado").font(.system(size: 11)).foregroundStyle(.secondary)

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Image(systemName: "scalemass.fill").font(.system(size: 11))
                    Text(r.porDespachar == 0 ? "Todo despachado"
                         : "\(r.porDespachar) por despachar")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .foregroundStyle(r.porDespachar == 0 ? .green : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(URL(string: "cuadre://ventas"))
        }
    }
}

/// Un widget sin nada que enseñar dice qué hacer, no se queda en blanco.
struct Vacia: View {
    let texto: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "bag").font(.system(size: 20)).foregroundStyle(.secondary)
            Text(texto).font(.system(size: 12, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
