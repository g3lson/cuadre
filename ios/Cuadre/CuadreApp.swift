import SwiftUI
import SwiftData

@main
struct CuadreApp: App {
    /// Los tipos que viven en la base local. En un sitio, porque hay que
    /// nombrarlos dos veces y que se queden desparejados no da error: da una
    /// tabla que desaparece.
    private static let tipos: [any PersistentModel.Type] = [
        Grupo.self, Clasificacion.self, Pasillo.self, Lista.self, Articulo.self, Evento.self,
        Encargo.self, Producto.self, Cliente.self, Tienda.self, Ajustes.self,
    ]

    /// ABRIR LA BASE, PASE LO QUE PASE.
    ///
    /// Si una versión nueva añade un campo sin valor por defecto, la migración
    /// automática falla y la base no abre. Antes eso era un `fatalError`: la
    /// app se cerraba al arrancar, una y otra vez, y la única salida era
    /// borrarla e instalarla de nuevo. En una instalación limpia no pasaba
    /// nada, así que el fallo solo aparecía en el teléfono de quien ya la
    /// tenía — que es el de todo el mundo menos el primero.
    ///
    /// Aquí, si no abre, se aparta la base vieja y se empieza de cero. Se
    /// puede hacer porque el servidor tiene todo: la primera sincronización lo
    /// devuelve. Lo único que se pierde es lo que se hubiera anotado sin
    /// conexión desde la última vez, y perder eso es mejor que una app que no
    /// abre.
    private static func abreLaBase() -> ModelContainer {
        let esquema = Schema(tipos)
        let config = ModelConfiguration(schema: esquema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: esquema, configurations: config)
        } catch {
            print("La base no abrió (\(error)). Se aparta y se empieza de nuevo.")
            apartaLaBase(config.url)
            // Y se olvida hasta dónde se había sincronizado: con una base
            // vacía, pedir «lo que cambió desde el martes» devuelve nada y la
            // app se queda en blanco con todo intacto en el servidor.
            Sincronizador.empiezaDeCero()
        }
        do {
            return try ModelContainer(for: esquema, configurations: config)
        } catch {
            // Ni con la base recién hecha. Esto ya no es un problema de datos,
            // y en memoria al menos la app abre y se puede entrar y sincronizar.
            print("Tampoco con una base nueva (\(error)). Se trabaja en memoria.")
            return try! ModelContainer(
                for: esquema,
                configurations: ModelConfiguration(schema: esquema, isStoredInMemoryOnly: true))
        }
    }

    /// Se mueve a un lado en vez de borrarse: si algún día hay que recuperar
    /// algo de ahí, todavía está. Se lleva los tres archivos de SQLite.
    private static func apartaLaBase(_ url: URL) {
        let fm = FileManager.default
        let sello = Int(Date().timeIntervalSince1970)
        for sufijo in ["", "-wal", "-shm"] {
            let de = URL(fileURLWithPath: url.path + sufijo)
            guard fm.fileExists(atPath: de.path) else { continue }
            let a = URL(fileURLWithPath: url.path + ".vieja-\(sello)" + sufijo)
            try? fm.moveItem(at: de, to: a)
        }
    }

    @Environment(\.scenePhase) private var fase
    @State private var sesion = Sesion()
    private let contenedor: ModelContainer

    init() {
        contenedor = CuadreApp.abreLaBase()

        // Se siembra aquí y no en un `.task`: en un `.task` la primera pantalla
        // ya se pintó vacía antes de que llegaran los datos, y la captura de la
        // integración continua salía en blanco.
        if Demo.encendido { Demo.siembra(contenedor.mainContext) }

        // La tipografía de las barras de navegación se pide a UIKit, y UIKit
        // solo la aplica a las barras que se creen DESPUÉS. Hacerlo en un
        // `.onAppear` llega tarde para la primera pantalla que se abra.
        let guardados = try? contenedor.mainContext.fetch(FetchDescriptor<Ajustes>())
        Tema.de(guardados?.first?.claveTema ?? .barro).aplicaALaBarra()
    }

    var body: some Scene {
        WindowGroup {
            Raiz()
                .environment(sesion)
                .task { await sesion.arranca() }
        }
        .modelContainer(contenedor)
        // Al salir de la app es cuando se mira el widget. Republicar aquí es
        // lo que hace que lo que se acaba de marcar esté puesto al soltar el
        // teléfono, sin esperar a la siguiente sincronización.
        .onChange(of: fase) { _, nueva in
            if nueva != .active { Escaparate.actualiza(contenedor.mainContext) }
        }
    }
}
