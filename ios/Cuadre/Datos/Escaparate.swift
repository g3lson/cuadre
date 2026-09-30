import Foundation
import SwiftData
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(ActivityKit)
import ActivityKit
#endif

/// LO QUE SE VE DESDE FUERA DE LA APP.
///
/// El widget y la actividad en vivo son otro proceso: no ven la base de datos y
/// no pueden abrirla cuando quieran. Lo que hacemos aquí es dejarles un resumen
/// diminuto en la carpeta compartida cada vez que algo cambia, y pedirle al
/// sistema que los repinte.
///
/// Se calcula de golpe y no cifra a cifra a propósito: recorrer la base entera
/// tres veces al día es nada, y tener una sola función es lo que hace que el
/// widget y la actividad no digan cosas distintas.
enum Escaparate {

    /// Recalcula y publica. Se llama cuando cambia algo que se ve desde fuera:
    /// al sincronizar, al marcar un producto, al cobrar y al cerrar.
    @MainActor
    static func actualiza(_ ctx: ModelContext) {
        var r = Resumen()

        let ajustes = ((try? ctx.fetch(FetchDescriptor<Ajustes>())) ?? []).first
        r.moneda = ajustes?.moneda ?? "RD$"

        // La compra abierta: la más reciente que siga activa.
        let listas = ((try? ctx.fetch(FetchDescriptor<Lista>())) ?? [])
            .filter { $0.vivo && $0.estado == "activa" }
            .sorted { $0.actualizado > $1.actualizado }
        if let l = listas.first {
            let suyos = Almacen.articulos(ctx, de: l.id)
            r.lista = l.nombre
            r.faltan = suyos.filter { !$0.hecho }.count
            r.llevados = suyos.filter(\.hecho).count
            r.gastado = suyos.filter(\.hecho).reduce(0) { $0 + $1.total }
            r.presupuesto = l.presupuesto
        }

        // El día de venta abierto.
        let eventos = ((try? ctx.fetch(FetchDescriptor<Evento>())) ?? [])
            .filter { $0.vivo && $0.estado == "abierto" }
            .sorted { $0.fecha > $1.fecha }
        if let e = eventos.first {
            let suyos = Almacen.encargos(ctx, de: e.id)
            r.venta = e.titulo
            let grupos = ((try? ctx.fetch(FetchDescriptor<Grupo>())) ?? []).filter(\.vivo)
            r.negocio = e.negocio.isEmpty
                ? (grupos.first { $0.id == e.grupoId }?.nombre ?? "") : e.negocio
            r.porDespachar = suyos.filter { !$0.cobrado }.count
            r.cobrado = suyos.filter(\.cobrado).reduce(0) { $0 + $1.total }
        }

        r.cuando = .now
        Puente.guarda(r)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        enVivo(r)
    }

    // MARK: - La actividad en vivo

    #if canImport(ActivityKit)
    /// Arranca, actualiza o termina la actividad del día de venta según lo que
    /// diga el resumen. No se lleva estado propio: se mira lo que hay puesto y
    /// se pone de acuerdo con la realidad, que es lo único que sobrevive a que
    /// el sistema mate la app.
    @available(iOS 16.2, *)
    private static func gestiona(_ r: Resumen) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let puestas = Activity<VentaEnVivo>.activities

        guard r.hayVenta else {
            for a in puestas {
                Task { await a.end(nil, dismissalPolicy: .immediate) }
            }
            return
        }

        let estado = VentaEnVivo.ContentState(porDespachar: r.porDespachar,
                                              cobrado: r.cobrado)
        if let a = puestas.first(where: { $0.attributes.titulo == r.venta }) {
            Task { await a.update(ActivityContent(state: estado, staleDate: nil)) }
            // Si quedó alguna de un día anterior, se cierra: dos actividades a
            // la vez en la pantalla bloqueada es peor que ninguna.
            for otra in puestas where otra.id != a.id {
                Task { await otra.end(nil, dismissalPolicy: .immediate) }
            }
            return
        }

        for otra in puestas { Task { await otra.end(nil, dismissalPolicy: .immediate) } }
        _ = try? Activity.request(
            attributes: VentaEnVivo(titulo: r.venta, negocio: r.negocio, moneda: r.moneda),
            content: ActivityContent(state: estado, staleDate: nil))
    }
    #endif

    private static func enVivo(_ r: Resumen) {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) { gestiona(r) }
        #endif
    }
}
