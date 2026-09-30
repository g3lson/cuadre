import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
import WidgetKit

/// EL DÍA DE VENTA EN LA PANTALLA BLOQUEADA Y EN LA ISLA.
///
/// Quien despacha por libra no tiene las manos libres para desbloquear el
/// teléfono cada vez que quiere saber cuánto lleva. Esto lo pone donde se ve de
/// un vistazo mientras el día esté abierto, y se va solo cuando se cierra.
@available(iOS 16.2, *)
struct ActividadDeVenta: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VentaEnVivo.self) { ctx in
            // La pantalla bloqueada.
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ctx.attributes.negocio.isEmpty
                         ? ctx.attributes.titulo : ctx.attributes.negocio)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(pesosCortos(ctx.state.cobrado, ctx.attributes.moneda))
                        .font(.system(size: 28, weight: .heavy))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if !ctx.state.ultimo.isEmpty {
                        Text(ctx.state.ultimo)
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    Text("\(ctx.state.porDespachar)")
                        .font(.system(size: 30, weight: .heavy))
                    Text("por despachar")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .activityBackgroundTint(nil)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Cobrado").font(.caption2).foregroundStyle(.secondary)
                        Text(pesosCortos(ctx.state.cobrado, ctx.attributes.moneda))
                            .font(.system(size: 20, weight: .heavy))
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Faltan").font(.caption2).foregroundStyle(.secondary)
                        Text("\(ctx.state.porDespachar)")
                            .font(.system(size: 20, weight: .heavy))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(ctx.state.ultimo.isEmpty
                         ? ctx.attributes.titulo : ctx.state.ultimo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "scalemass.fill")
            } compactTrailing: {
                Text("\(ctx.state.porDespachar)").font(.system(size: 14, weight: .heavy))
            } minimal: {
                Text("\(ctx.state.porDespachar)").font(.system(size: 13, weight: .heavy))
            }
            .widgetURL(URL(string: "cuadre://ventas"))
        }
    }
}
#endif
