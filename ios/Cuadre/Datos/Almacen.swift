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

    // MARK: - Pasillos

    /// Los pasillos de esta persona, en el orden en que recorre la tienda.
    ///
    /// La primera vez se siembran con los que trae la app. Son un punto de
    /// partida: se renombran, se reordenan y se borran.
    @MainActor
    static func pasillos(_ ctx: ModelContext, sembrandoSiHaceFalta sembrar: Bool = true) -> [Pasillo] {
        let d = FetchDescriptor<Pasillo>(
            predicate: #Predicate { $0.borrado == nil },
            sortBy: [SortDescriptor<Pasillo>(\.orden), SortDescriptor<Pasillo>(\.nombre)])
        let hay = (try? ctx.fetch(d)) ?? []
        guard hay.isEmpty, sembrar else { return hay }

        for (i, nombre) in Categoria.dePartida.enumerated() {
            ctx.insert(Pasillo(nombre: nombre, orden: i))
        }
        try? ctx.save()
        return (try? ctx.fetch(d)) ?? []
    }

    /// Dónde va una categoría en el recorrido. Lo que no está, al final.
    @MainActor
    static func ordenDePasillo(_ ctx: ModelContext, _ nombre: String) -> Int {
        pasillos(ctx).firstIndex { $0.nombre == nombre } ?? 999
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

        /// Para la columna de la derecha del resumen, donde no cabe una frase.
        var corto: String {
            switch self {
            case .proxima: return "a la próxima"
            case .otroSitio: return "a «Faltantes»"
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
    /// Lo que de verdad faltó: sin los que alguien empezó a escribir y dejó
    /// vacíos. Un producto sin nombre y sin precio no es un producto, y meterlo
    /// en el resumen produce líneas como «: pasó a la próxima compra».
    @MainActor
    static func faltaronDeVerdad(_ ctx: ModelContext, en lista: Lista) -> [Articulo] {
        articulos(ctx, de: lista.id).filter {
            !$0.hecho && !$0.nombre.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    @MainActor
    static func cierra(_ ctx: ModelContext, lista: Lista, destinos: [String: Destino]) {
        let todos = articulos(ctx, de: lista.id)
        let cuando = Date()

        // Los que quedaron sin nombre se van con la compra: no hay nada que
        // pasar a la próxima lista ni que buscar en otro sitio.
        for vacio in todos where !vacio.hecho && vacio.nombre.trimmingCharacters(in: .whitespaces).isEmpty {
            vacio.entierro(cuando)
        }
        let faltaron = todos.filter { !$0.hecho && !$0.nombre.trimmingCharacters(in: .whitespaces).isEmpty }

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
        // Ya se compró: recordarlo mañana sería recordar algo que ya pasó.
        Avisos.olvida(lista.id)
        lista.notaCierre = faltaron.isEmpty
            ? "Compraste todo"
            : "Faltó " + faltaron.map(\.nombre).joined(separator: ", ")
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
            // Sin los que se quedaron sin nombre: arrastrar una ficha vacía a la
            // lista siguiente es arrastrar el error, no el producto.
            let pendientes = articulos(ctx, de: l.id).filter {
                !$0.hecho && !$0.nombre.trimmingCharacters(in: .whitespaces).isEmpty
            }
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
        /// Lo que salió sin cobrarse, a lo que te costó: regalos, donaciones y
        /// lo que se llevó la casa. La mercancía sale igual y cuesta igual.
        var regalado: Double = 0
        var cobrados: [Encargo] = []
        var pendientes: [Encargo] = []
        var salidas: [Encargo] = []

        /// Lo que te costó lo que sí vendiste y lo que regalaste, juntos: el
        /// dinero que salió del negocio en mercancía.
        var costoTotal: Double { costo + regalado }
        var ganancia: Double { vendido - costoTotal }
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
                // Lo que no se cobra cuenta igual: sale del inventario y costó
                // dinero. Meterlo como una venta de cero pesos falsearía el
                // margen; no meterlo haría que el inventario no cuadrara.
                guard o.salida.cobra else {
                    if o.cobrado {
                        c.regalado += o.costoTotal
                        c.salidas.append(o)
                    }
                    continue
                }
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
