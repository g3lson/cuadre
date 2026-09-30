import Foundation
import SwiftData

/// LAS OPERACIONES.
///
/// Las cuentas y los cambios que no son de una sola pantalla. Están aquí y no
/// dentro de las vistas porque «cerrar la compra» toca cuatro modelos a la vez y
/// tiene que hacer lo mismo se llegue desde donde se llegue.
enum Almacen {

    // MARK: - Ajustes

    /// Los ajustes de esta persona, creándolos si es la primera vez. Su `id` es
    /// el de la cuenta, así que cambiar de cuenta en el mismo teléfono trae los
    /// suyos y no los del anterior.
    @MainActor
    static func ajustes(_ ctx: ModelContext, de usuarioId: String) -> Ajustes {
        let d = FetchDescriptor<Ajustes>(predicate: #Predicate { $0.id == usuarioId })
        if let ya = try? ctx.fetch(d).first { return ya }
        let nuevos = Ajustes(id: usuarioId)
        ctx.insert(nuevos)
        return nuevos
    }

    // MARK: - Listas

    @MainActor
    static func articulos(_ ctx: ModelContext, de listaId: String) -> [Articulo] {
        let d = FetchDescriptor<Articulo>(
            predicate: #Predicate { $0.listaId == listaId && $0.borrado == nil },
            sortBy: [SortDescriptor(\.orden), SortDescriptor(\.nombre)])
        return (try? ctx.fetch(d)) ?? []
    }

    @MainActor
    static func lista(_ ctx: ModelContext, id: String) -> Lista? {
        let d = FetchDescriptor<Lista>(predicate: #Predicate { $0.id == id })
        return try? ctx.fetch(d).first
    }

    /// Lo gastado y lo que queda. Solo cuenta lo que ya está en el carrito: el
    /// presupuesto se lleva contra lo que llevas puesto, no contra lo que
    /// piensas comprar.
    @MainActor
    static func gastado(_ ctx: ModelContext, en lista: Lista) -> Double {
        articulos(ctx, de: lista.id).filter(\.hecho).reduce(0) { $0 + $1.total }
    }

    /// Crear una lista nueva, opcionalmente repitiendo otra o trayéndose lo que faltó.
    @MainActor
    @discardableResult
    static func creaLista(_ ctx: ModelContext, nombre: String, tienda: String,
                          presupuesto: Double, fecha: Date, color: Int,
                          copiandoDe origen: Lista? = nil,
                          faltantesDe pendientes: [Articulo] = []) -> Lista {
        let l = Lista(nombre: nombre, tienda: tienda, presupuesto: presupuesto,
                      fecha: fecha, color: color, orden: -Int(Date().timeIntervalSince1970))
        ctx.insert(l)

        if let origen {
            // Se copia lo que había, sin marcar y con el último precio pagado:
            // la lista de la semana que viene es la de esta con los precios de
            // esta, que es lo que ahorra el trabajo de verdad.
            for (i, a) in articulos(ctx, de: origen.id).enumerated() {
                let copia = Articulo(listaId: l.id, nombre: a.nombre, unidad: a.unidad,
                                     cantidad: a.cantidad, precio: a.precio, hecho: false,
                                     nota: a.nota, categoria: a.categoria, orden: i)
                ctx.insert(copia)
            }
        }
        for (i, a) in pendientes.enumerated() {
            let copia = Articulo(listaId: l.id, nombre: a.nombre, unidad: a.unidad,
                                 cantidad: a.cantidad, precio: a.precio, hecho: false,
                                 nota: a.nota, categoria: a.categoria,
                                 orden: (origen == nil ? 0 : 1000) + i)
            ctx.insert(copia)
        }
        return l
    }

    /// Qué hacer con lo que no había.
    enum Destino: String, CaseIterable, Identifiable {
        case proxima, otroSitio, quitar
        var id: String { rawValue }

        var titulo: String {
            switch self {
            case .proxima: return "Pasarlo a la próxima compra"
            case .otroSitio: return "Buscarlo en otro lado"
            case .quitar: return "Ya no hace falta"
            }
        }
        func detalle(tienda: String) -> String {
            switch self {
            case .proxima: return tienda.isEmpty ? "Aparece solo en tu próxima lista" : "Aparece solo en tu próxima lista de \(tienda)"
            case .otroSitio: return "Te creo la lista «Faltantes» para el colmado"
            case .quitar: return "Se quita de la lista"
            }
        }
        var hecho: String {
            switch self {
            case .proxima: return "pasó a la próxima compra"
            case .otroSitio: return "lista «Faltantes» creada"
            case .quitar: return "quitado"
            }
        }
    }

    /// CERRAR LA COMPRA.
    ///
    /// Lo que faltó no se pierde: o espera a la próxima lista de esta misma
    /// tienda, o se va a una lista «Faltantes» para buscarlo en otro sitio, o se
    /// quita porque ya no hace falta. La lista se queda solo con lo que de
    /// verdad se compró, que es lo que tiene que cuadrar con lo que se pagó.
    @MainActor
    static func cierra(_ ctx: ModelContext, lista: Lista, destinos: [String: Destino]) {
        let todos = articulos(ctx, de: lista.id)
        let faltaron = todos.filter { !$0.hecho }
        let cuando = Date()

        let aOtroSitio = faltaron.filter { (destinos[$0.id] ?? .proxima) == .otroSitio }
        if !aOtroSitio.isEmpty {
            let faltantes = listaDeFaltantes(ctx, lista: lista)
            let desde = articulos(ctx, de: faltantes.id).count
            for (i, a) in aOtroSitio.enumerated() {
                let copia = Articulo(listaId: faltantes.id, nombre: a.nombre, unidad: a.unidad,
                                     cantidad: a.cantidad, precio: a.precio, hecho: false,
                                     nota: a.nota.isEmpty ? "no había en \(lista.tienda)" : a.nota,
                                     categoria: a.categoria, orden: desde + i)
                ctx.insert(copia)
            }
            faltantes.toco(cuando)
        }

        // Lo que pasa a la próxima se queda guardado en la lista cerrada, sin
        // marcar: de ahí lo saca «Traer los faltantes» al crear la siguiente.
        for a in faltaron where (destinos[a.id] ?? .proxima) != .proxima {
            a.entierro(cuando)
        }

        lista.estado = "cerrada"
        lista.cerradaEn = cuando
        lista.notaCierre = faltaron.isEmpty
            ? "Compraste todo"
            : faltaron.map { "\($0.nombre): \((destinos[$0.id] ?? .proxima).hecho)" }.joined(separator: " · ")
        lista.toco(cuando)
    }

    /// La lista «Faltantes» es una sola y se reutiliza: dos listas con el mismo
    /// nombre y dos productos cada una es peor que una con cuatro.
    @MainActor
    private static func listaDeFaltantes(_ ctx: ModelContext, lista: Lista) -> Lista {
        let d = FetchDescriptor<Lista>(
            predicate: #Predicate { $0.nombre == "Faltantes" && $0.estado == "activa" && $0.borrado == nil })
        if let ya = try? ctx.fetch(d).first { return ya }
        let nueva = Lista(nombre: "Faltantes", tienda: "", presupuesto: 0,
                          fecha: .now, color: 0, orden: -Int(Date().timeIntervalSince1970))
        ctx.insert(nueva)
        return nueva
    }

    /// Lo que quedó pendiente de la última compra cerrada de esa tienda, para
    /// ofrecerlo al crear la siguiente.
    @MainActor
    static func faltantesPendientes(_ ctx: ModelContext, tienda: String) -> [Articulo] {
        let d = FetchDescriptor<Lista>(
            predicate: #Predicate { $0.estado == "cerrada" && $0.borrado == nil },
            sortBy: [SortDescriptor(\.cerradaEn, order: .reverse)])
        guard let cerradas = try? ctx.fetch(d) else { return [] }
        for l in cerradas where tienda.isEmpty || l.tienda == tienda {
            let pendientes = articulos(ctx, de: l.id).filter { !$0.hecho }
            if !pendientes.isEmpty { return pendientes }
        }
        return []
    }

    // MARK: - Ventas

    @MainActor
    static func encargos(_ ctx: ModelContext, de eventoId: String) -> [Encargo] {
        let d = FetchDescriptor<Encargo>(
            predicate: #Predicate { $0.eventoId == eventoId && $0.borrado == nil },
            sortBy: [SortDescriptor(\.actualizado)])
        return (try? ctx.fetch(d)) ?? []
    }

    // MARK: - El cuadre

    /// Las cifras del día. Se calculan aquí y no en cada tarjeta para que la
    /// ganancia de arriba y el desglose de abajo no puedan discrepar.
    struct Cuentas {
        var vendido: Double = 0
        var costo: Double = 0
        var comprado: Double = 0
        var porCobrar: Double = 0
        var efectivo: Double = 0
        var transferencia: Double = 0
        var cobrados: [Encargo] = []
        var pendientes: [Encargo] = []

        var ganancia: Double { vendido - costo }
        var margen: Double { vendido > 0 ? ganancia / vendido : 0 }
    }

    @MainActor
    static func cuentas(_ ctx: ModelContext, del dia: Date) -> Cuentas {
        let cal = Calendar.current
        var c = Cuentas()

        let eventos = ((try? ctx.fetch(FetchDescriptor<Evento>())) ?? [])
            .filter { $0.vivo && cal.isDate($0.fecha, inSameDayAs: dia) }
        for e in eventos {
            for o in encargos(ctx, de: e.id) {
                if o.cobrado {
                    c.vendido += o.total
                    c.costo += o.costoTotal
                    if o.metodo == "Transferencia" { c.transferencia += o.total } else { c.efectivo += o.total }
                    c.cobrados.append(o)
                } else {
                    c.porCobrar += o.total
                    c.pendientes.append(o)
                }
            }
        }

        let listas = ((try? ctx.fetch(FetchDescriptor<Lista>())) ?? [])
            .filter { $0.vivo && $0.cerrada && cal.isDate($0.cerradaEn ?? .distantPast, inSameDayAs: dia) }
        for l in listas { c.comprado += gastado(ctx, en: l) }

        return c
    }

    // MARK: - Memoria de precios

    /// El último precio que se pagó por algo con ese nombre. Es lo que hace que
    /// escribir «Leche entera» en una lista nueva ya traiga RD$245 puesto.
    @MainActor
    static func ultimoPrecio(_ ctx: ModelContext, de nombre: String) -> (precio: Double, unidad: String)? {
        let llano = nombre.folding(options: .diacriticInsensitive, locale: nil).lowercased()
        guard !llano.isEmpty else { return nil }
        let d = FetchDescriptor<Articulo>(
            predicate: #Predicate { $0.hecho && $0.precio > 0 && $0.borrado == nil },
            sortBy: [SortDescriptor(\.actualizado, order: .reverse)])
        guard let todos = try? ctx.fetch(d) else { return nil }
        for a in todos where a.nombre.folding(options: .diacriticInsensitive, locale: nil).lowercased() == llano {
            return (a.precio, a.unidad)
        }
        return nil
    }

    /// Nombres que ya se han escrito, para sugerir al teclear.
    @MainActor
    static func sugerencias(_ ctx: ModelContext, para texto: String, limite: Int = 6) -> [String] {
        let busca = texto.folding(options: .diacriticInsensitive, locale: nil).lowercased()
        guard busca.count >= 2 else { return [] }
        let d = FetchDescriptor<Articulo>(
            predicate: #Predicate { $0.borrado == nil },
            sortBy: [SortDescriptor(\.actualizado, order: .reverse)])
        guard let todos = try? ctx.fetch(d) else { return [] }
        var vistos = Set<String>()
        var fuera: [String] = []
        for a in todos {
            let llano = a.nombre.folding(options: .diacriticInsensitive, locale: nil).lowercased()
            guard llano.contains(busca), llano != busca, !vistos.contains(llano), !a.nombre.isEmpty else { continue }
            vistos.insert(llano)
            fuera.append(a.nombre)
            if fuera.count >= limite { break }
        }
        return fuera
    }
}
