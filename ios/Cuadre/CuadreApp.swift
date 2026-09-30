import SwiftUI
import SwiftData

@main
struct CuadreApp: App {
    @State private var sesion = Sesion()
    private let contenedor: ModelContainer

    init() {
        do {
            contenedor = try ModelContainer(
                for: Lista.self, Articulo.self, Evento.self, Encargo.self,
                     Producto.self, Cliente.self, Tienda.self, Ajustes.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: false))
        } catch {
            // Si la base local no abre, la app no puede hacer nada útil: mejor
            // caerse aquí con el motivo que arrancar y fallar en cada pantalla.
            fatalError("No pude abrir la base local: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Raiz()
                .environment(sesion)
                .task { await sesion.arranca() }
                .task { if Demo.encendido { Demo.siembra(contenedor.mainContext) } }
        }
        .modelContainer(contenedor)
    }
}
