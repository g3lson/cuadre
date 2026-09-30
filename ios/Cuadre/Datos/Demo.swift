import Foundation
import SwiftData

/// EL MODO DEMO.
///
/// Llena la app con un día de trabajo creíble y entra sin servidor. No se llega
/// aquí desde ninguna pantalla: hace falta arrancar el proceso con `-demo`, que
/// es lo que hace la integración continua para poder sacar capturas de las
/// catorce pantallas, y lo que se usa para las imágenes de la ficha del App Store.
///
/// Sin sesión de verdad no hay testigo, así que el sincronizador no intenta
/// subir nada: los datos de mentira no pueden acabar en la cuenta de nadie.
enum Demo {
    static var encendido: Bool {
        ProcessInfo.processInfo.arguments.contains("-demo")
    }

    /// Con qué pestaña arrancar, para que la integración continua pueda
    /// fotografiar las cuatro sin tocar la pantalla: `-pestana ventas`.
    static var pestana: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-pestana"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// Con qué tema arrancar: `-tema noche`. Sirve para fotografiar los tres
    /// sin tocar Ajustes.
    static var tema: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-tema"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// El identificador de la persona de mentira. Fijo, para que al reabrir la
    /// app en el simulador se encuentre lo que ya había en vez de duplicarlo.
    static let usuarioId = "demo"

    static func usuario() -> Sesion.Usuario {
        .init(id: usuarioId, email: "gelson@fente.com.do", nombre: "Gelson",
              inicial: "G", conApple: false)
    }

    @MainActor
    static func siembra(_ ctx: ModelContext) {
        let ajustes = Almacen.ajustes(ctx, de: usuarioId)
        // El tema sí se pisa en cada arranque: es lo que permite fotografiar los
        // tres seguidos sin borrar la app entre medias.
        if let t = tema, Tema.Clave(rawValue: t) != nil { ajustes.tema = t }

        // Lo demás solo se siembra una vez.
        let hay = ((try? ctx.fetch(FetchDescriptor<Lista>())) ?? []).contains(where: \.vivo)
        guard !hay else { return }

        ajustes.modoVendedor = true
        ajustes.nombreNegocio = "Compras y ventas · Santo Domingo"

        for nombre in ["Supermercado Bravo", "Ferretería Americana", "Mercado de Villa Consuelo"] {
            ctx.insert(Tienda(nombre: nombre))
        }

        // ── La compra a medias, que es lo que se ve al abrir ──
        let semanal = Lista(nombre: "Supermercado Semanal", tienda: "Supermercado Bravo",
                            presupuesto: 6500, fecha: .now, color: 0, orden: -3)
        ctx.insert(semanal)
        let productos: [(String, String, Double, Double, Bool, String, String)] = [
            ("Leche entera", "gal", 2, 245, true, "Rica, la azul", "Lácteos y huevos"),
            ("Queso de freír", "lb", 1.5, 220, true, "", "Lácteos y huevos"),
            ("Pescado chillo", "lb", 10, 135, true, "Bien fresco y escamado", "Carnes y pescados"),
            ("Filete de res", "lb", 6, 270, true, "", "Carnes y pescados"),
            ("Azúcar crema", "lb", 5, 38, false, "", "Víveres"),
            ("Arroz selecto", "saco", 1, 1250, false, "50 lb", "Víveres"),
            ("Aceite vegetal", "gal", 2, 380, false, "", "Víveres"),
            ("Plátanos barahoneros", "ud", 12, 25, false, "Verdes", "Frutas y vegetales"),
            ("Huevos", "doc", 2, 110, false, "", "Lácteos y huevos"),
            ("Pan sobao", "paq", 1, 95, false, "", "Panadería"),
        ]
        for (i, p) in productos.enumerated() {
            ctx.insert(Articulo(listaId: semanal.id, nombre: p.0, unidad: p.1, cantidad: p.2,
                                precio: p.3, hecho: p.4, nota: p.5, categoria: p.6, orden: i))
        }

        // ── Una lista por empezar y una ya cuadrada ──
        let ferreteria = Lista(nombre: "Materiales Ferretería", tienda: "Ferretería Americana",
                               presupuesto: 4000, fecha: .now.addingTimeInterval(2 * 86400),
                               color: 2, orden: -2)
        ctx.insert(ferreteria)
        ctx.insert(Articulo(listaId: ferreteria.id, nombre: "Cemento gris", unidad: "saco",
                            cantidad: 4, precio: 520, categoria: "Ferretería", orden: 0))
        ctx.insert(Articulo(listaId: ferreteria.id, nombre: "Varilla 3/8", unidad: "ud",
                            cantidad: 10, precio: 142, categoria: "Ferretería", orden: 1))

        let pescados = Lista(nombre: "Abastecimiento de Pescados", tienda: "Mercado de Villa Consuelo",
                             presupuesto: 8000, fecha: .now.addingTimeInterval(-6 * 86400),
                             color: 1, orden: -1)
        pescados.estado = "cerrada"
        pescados.cerradaEn = .now.addingTimeInterval(-6 * 86400)
        pescados.notaCierre = "Compraste todo"
        pescados.chinolaNota = "Personal · Banco Popular ·4120"
        ctx.insert(pescados)
        for (i, p) in [("Chillo entero", 30.0, 130.0), ("Mero criollo", 18.0, 150.0),
                       ("Camarones 21/25", 12.0, 220.0)].enumerated() {
            ctx.insert(Articulo(listaId: pescados.id, nombre: p.0, unidad: "lb", cantidad: p.1,
                                precio: p.2, hecho: true, categoria: "Carnes y pescados", orden: i))
        }

        // ── El catálogo, que es lo que hace que un encargo salga en cuatro toques ──
        let catalogo: [(String, Double, Double, Double, Double)] = [
            ("Chillo entero", 130, 210, 175, 160),
            ("Mero criollo", 150, 240, 200, 185),
            ("Camarones 21/25", 220, 330, 280, 260),
        ]
        var porNombre: [String: Producto] = [:]
        for c in catalogo {
            let p = Producto(nombre: c.0, categoria: "Carnes y pescados", unidad: "lb",
                             costo: c.1, precioDetal: c.2, precioMayor: c.3, precioEspecial: c.4)
            ctx.insert(p)
            porNombre[c.0] = p
        }

        // ── El día de venta, a medio despachar ──
        let venta = Evento(titulo: "Pescado del viernes", fecha: .now)
        ctx.insert(venta)
        let encargos: [(String, String, String, Double, Tarifa, String, String, String)] = [
            ("Juan Pérez", "+1 (809) 555-0110", "Chillo entero", 5.2, .detal, "cobrado", "Efectivo", ""),
            ("María Gómez", "", "Chillo entero", 7, .mayor, "cobrado", "Transferencia", ""),
            ("Carlos Díaz", "", "Mero criollo", 6.1, .detal, "cobrado", "Efectivo", ""),
            ("Doña Carmen Rosa", "", "Chillo entero", 4.5, .especial, "pendiente", "", "Viene a buscarlo a las 2:00"),
            ("Roberto Medina", "", "Camarones 21/25", 3.5, .detal, "pendiente", "", "Confirmó por WhatsApp"),
        ]
        for (i, e) in encargos.enumerated() {
            guard let p = porNombre[e.2] else { continue }
            let o = Encargo(eventoId: venta.id, cliente: e.0, producto: p.nombre, unidad: "lb",
                            pedido: e.3, precioDetal: p.precioDetal, precioMayor: p.precioMayor,
                            precioEspecial: p.precioEspecial, costo: p.costo)
            o.telefono = e.1
            o.tarifa = e.4.rawValue
            o.estado = e.5
            o.metodo = e.6
            o.nota = e.7
            if e.5 == "cobrado" {
                o.cobradoEn = Calendar.current.date(byAdding: .minute, value: -(120 - i * 25), to: .now)
            }
            ctx.insert(o)
            ctx.insert(Cliente(nombre: e.0, telefono: e.1))
        }

        try? ctx.save()
    }
}
