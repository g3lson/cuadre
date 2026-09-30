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
    }
}
