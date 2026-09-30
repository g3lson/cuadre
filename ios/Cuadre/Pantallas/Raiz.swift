import SwiftUI
import SwiftData

/// LA RAÍZ.
///
/// Decide tres cosas y nada más: si hay que entrar, qué tema se pinta, y qué
/// pestaña se ve. Todo lo demás cuelga de aquí.
struct Raiz: View {
    @Environment(Sesion.self) private var sesion
    @Environment(\.modelContext) private var ctx
    @Environment(\.scenePhase) private var fase

    @State private var pestana: Pestana = .listas
    @State private var sincronizador: Sincronizador?
    /// La lista que se está comprando ahora. Es lo que enseña la pestaña «En
    /// tienda»: sin ella, esa pestaña no tiene de qué hablar.
    @State private var enTienda: String?

    @Query(filter: #Predicate<Ajustes> { $0.borrado == nil }) private var todosLosAjustes: [Ajustes]

    private var ajustes: Ajustes? {
        guard let id = sesion.usuario?.id else { return nil }
        return todosLosAjustes.first { $0.id == id }
    }
    private var tema: Tema { Tema.de(ajustes?.claveTema ?? .barro) }

    var body: some View {
        ZStack {
            if sesion.comprobando {
                Portada()
            } else if !sesion.dentro {
                EntrarView()
            } else {
                principal
            }
        }
        .environment(\.tema, tema)
        .fondoDelTema(tema)
        .preferredColorScheme(tema.oscuro ? .dark : .light)
        .tint(tema.acento700)
        .overlay(alignment: .top) { avisos }
        .animation(.snappy(duration: 0.25), value: sesion.dentro)
        .animation(.snappy(duration: 0.25), value: tema.id)
        .onChange(of: sesion.usuario?.id) { _, nuevo in
            guard let nuevo else { return }
            // Los ajustes se crean al entrar, no al arrancar la app: antes de
            // entrar no se sabe de quién son.
            _ = Almacen.ajustes(ctx, de: nuevo)
            Task { await sincronizador?.sincroniza() }
        }
        .onAppear {
            if sincronizador == nil { sincronizador = Sincronizador(contexto: ctx) }
        }
        .onChange(of: fase) { _, nueva in
            // Al volver a la app se sincroniza: es cuando hay más probabilidad
            // de que otro dispositivo haya escrito algo.
            if nueva == .active { Task { await sincronizador?.sincroniza() } }
        }
        .onOpenURL { url in
            // La vuelta de Chinola: `cuadre://chinola?ok=1`.
            guard url.scheme == "cuadre", url.host == "chinola" else { return }
            Task { await sesion.refresca() }
        }
    }

    @ViewBuilder
    private var principal: some View {
        let mostrarVentas = ajustes?.modoVendedor ?? false

        ZStack(alignment: .bottom) {
            Group {
                switch pestana {
                case .listas:
                    ListasView(enTienda: $enTienda, pestana: $pestana)
                case .tienda:
                    EnTiendaView(listaId: $enTienda, pestana: $pestana)
                case .ventas:
                    VentasView()
                case .cuadre:
                    CuadreView()
                }
            }
            .environment(\.sincronizador, sincronizador)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            BarraDePestanas(activa: $pestana, conVentas: mostrarVentas)
                .padding(.bottom, 8)
        }
        .onChange(of: mostrarVentas) { _, hay in
            if !hay, pestana == .ventas { pestana = .listas }
        }
    }

    @ViewBuilder
    private var avisos: some View {
        VStack(spacing: 8) {
            ForEach(sesion.avisos) { AvisoView(aviso: $0) }
        }
        .padding(.top, 6)
    }
}

/// La pantalla de medio segundo mientras se comprueba la sesión. Es la marca y
/// nada más: un indicador de carga girando aquí solo consigue que medio segundo
/// parezca dos.
struct Portada: View {
    @Environment(\.tema) private var tema

    var body: some View {
        VStack(spacing: 18) {
            Marca(tamano: 64)
            Text("cuadre").font(tema.titulo(34))
        }
        .foregroundStyle(tema.texto)
    }
}

// MARK: - El sincronizador, a mano en cualquier pantalla

private struct ClaveSincronizador: EnvironmentKey {
    static let defaultValue: Sincronizador? = nil
}

extension EnvironmentValues {
    var sincronizador: Sincronizador? {
        get { self[ClaveSincronizador.self] }
        set { self[ClaveSincronizador.self] = newValue }
    }
}
