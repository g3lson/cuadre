import AppIntents
import SwiftData
import Foundation

/// SIRI Y LOS ATAJOS.
///
/// Dos cosas se piden con las manos ocupadas y son justo las que pasan en el
/// súper: añadir algo que se acaba de recordar, y saber cuánto se lleva gastado.
/// Todo lo demás se hace mejor mirando la pantalla.
///
/// Los intents abren su propio contenedor de SwiftData contra el mismo archivo
/// que la app: no hay dos verdades, hay una base y dos maneras de llegar a ella.

/// El contenedor, compartido por todos los atajos.
@MainActor
enum BaseDeAtajos {
    static let contenedor: ModelContainer? = try? ModelContainer(
        for: Grupo.self, Pasillo.self, Lista.self, Articulo.self, Evento.self,
             Encargo.self, Producto.self, Cliente.self, Tienda.self, Ajustes.self)

    /// La compra que está abierta ahora: la que tiene algo en el carrito, o si
    /// no la más reciente sin cerrar.
    static func compraAbierta(_ ctx: ModelContext) -> Lista? {
        let d = FetchDescriptor<Lista>(
            predicate: #Predicate { $0.borrado == nil && $0.estado == "activa" },
            sortBy: [SortDescriptor<Lista>(\.orden), SortDescriptor<Lista>(\.fecha, order: .reverse)])
        let abiertas = (try? ctx.fetch(d)) ?? []
        return abiertas.first { !Almacen.articulos(ctx, de: $0.id).filter(\.hecho).isEmpty } ?? abiertas.first
    }

    static func moneda(_ ctx: ModelContext) -> String {
        ((try? ctx.fetch(FetchDescriptor<Ajustes>()))?.first?.moneda) ?? "RD$"
    }
}

/// «Oye Siri, agrega leche a la lista de Cuadre.»
struct AgregarALaLista: AppIntent {
    static var title: LocalizedStringResource = "Agregar a la lista"
    static var description = IntentDescription("Añade un producto a la compra que tengas abierta.")
    /// No abre la app: se dice y se sigue caminando.
    static var openAppWhenRun = false

    @Parameter(title: "Qué", requestValueDialog: "¿Qué le agrego?")
    var producto: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let contenedor = BaseDeAtajos.contenedor else {
            return .result(dialog: "No pude abrir tus listas.")
        }
        let ctx = contenedor.mainContext
        guard let lista = BaseDeAtajos.compraAbierta(ctx) else {
            return .result(dialog: "No tienes ninguna compra abierta. Crea una lista primero.")
        }

        let nombre = producto.trimmingCharacters(in: .whitespaces)
        guard !nombre.isEmpty else { return .result(dialog: "No entendí qué agregar.") }

        let orden = (Almacen.articulos(ctx, de: lista.id).map(\.orden).max() ?? 0) + 1
        let a = Articulo(listaId: lista.id, nombre: nombre,
                         unidad: ((try? ctx.fetch(FetchDescriptor<Ajustes>()))?.first?.unidadPorDefecto) ?? "ud",
                         categoria: Categoria.adivina(nombre), orden: orden)
        // Si ya se compró antes, entra con su último precio puesto.
        if let (p, u) = Almacen.ultimoPrecio(ctx, de: nombre) {
            a.precio = p
            a.unidad = u
        }
        ctx.insert(a)
        lista.toco()
        try? ctx.save()

        return .result(dialog: "Listo, \(nombre) va en \(lista.nombre).")
    }
}

/// «Oye Siri, cuánto llevo gastado.»
struct CuantoLlevoGastado: AppIntent {
    static var title: LocalizedStringResource = "Cuánto llevo gastado"
    static var description = IntentDescription("Dice lo que llevas en el carrito y lo que te queda del presupuesto.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let contenedor = BaseDeAtajos.contenedor else {
            return .result(dialog: "No pude abrir tus listas.")
        }
        let ctx = contenedor.mainContext
        guard let lista = BaseDeAtajos.compraAbierta(ctx) else {
            return .result(dialog: "No tienes ninguna compra abierta.")
        }
        let moneda = BaseDeAtajos.moneda(ctx)
        let gastado = Almacen.gastado(ctx, en: lista)
        guard lista.presupuesto > 0 else {
            return .result(dialog: "Llevas \(Formato.pesos(gastado, moneda: moneda)).")
        }
        let queda = lista.presupuesto - gastado
        return .result(dialog: queda < 0
            ? "Llevas \(Formato.pesos(gastado, moneda: moneda)): te pasaste por \(Formato.pesos(-queda, moneda: moneda))."
            : "Llevas \(Formato.pesos(gastado, moneda: moneda)). Te quedan \(Formato.pesos(queda, moneda: moneda)).")
    }
}

/// «Oye Siri, qué me falta comprar.»
struct QueMeFalta: AppIntent {
    static var title: LocalizedStringResource = "Qué me falta"
    static var description = IntentDescription("Dice qué queda por echar al carrito.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let contenedor = BaseDeAtajos.contenedor,
              let lista = BaseDeAtajos.compraAbierta(contenedor.mainContext) else {
            return .result(dialog: "No tienes ninguna compra abierta.")
        }
        let faltan = Almacen.articulos(contenedor.mainContext, de: lista.id)
            .filter { !$0.hecho && !$0.nombre.isEmpty }
        guard !faltan.isEmpty else { return .result(dialog: "Ya lo tienes todo.") }

        // Tres y «y tantos más»: una lista de quince leída en voz alta no la
        // sigue nadie.
        let primeros = faltan.prefix(3).map(\.nombre).joined(separator: ", ")
        let resto = faltan.count - min(3, faltan.count)
        return .result(dialog: resto > 0
            ? "Te faltan \(primeros) y \(resto) más."
            : "Te falta \(primeros).")
    }
}

/// Los atajos que Siri aprende solo con instalar la app, sin que nadie los
/// configure. Las frases van en español y en inglés porque el idioma de Siri no
/// tiene por qué ser el del teléfono.
struct AtajosDeCuadre: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AgregarALaLista(),
            phrases: [
                "Agrega a la lista de \(.applicationName)",
                "Apunta en \(.applicationName)",
                "Add to my \(.applicationName) list",
            ],
            shortTitle: "Agregar a la lista",
            systemImageName: "plus.circle")

        AppShortcut(
            intent: CuantoLlevoGastado(),
            phrases: [
                "Cuánto llevo gastado en \(.applicationName)",
                "How much have I spent in \(.applicationName)",
            ],
            shortTitle: "Cuánto llevo",
            systemImageName: "dollarsign.circle")

        AppShortcut(
            intent: QueMeFalta(),
            phrases: [
                "Qué me falta en \(.applicationName)",
                "What's left in \(.applicationName)",
            ],
            shortTitle: "Qué me falta",
            systemImageName: "checklist")
    }
}
