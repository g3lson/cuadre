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
    /// En el iPad en horizontal la pastilla de abajo queda a un palmo del
    /// pulgar y se come el ancho: ahí las pestañas van a un raíl de lado.
    @Environment(\.horizontalSizeClass) private var ancho

    @State private var pestana: Pestana = Pestana(rawValue: Demo.pestana ?? "") ?? .listas
    @State private var sincronizador: Sincronizador?
    /// La lista que se está comprando ahora. Es lo que enseña la pestaña «En
    /// tienda»: sin ella, esa pestaña no tiene de qué hablar.
    @State private var enTienda: String?
    /// La venta que se está despachando. Mientras haya una, el menú de abajo se
    /// quita: ese menú es para saltar entre pantallas generales, y despachando
    /// solo quita sitio justo donde está la mano.
    @State private var enLaVenta: String?
    /// Solo en modo demo: abrir Ajustes de una vez, para poder fotografiarla.
    @State private var invitacion: Invitacion?

    /// El código de una invitación que llegó por enlace. Es un tipo y no un
    /// `String?` porque `sheet(item:)` necesita algo identificable.
    struct Invitacion: Identifiable { let id = UUID(); let codigo: String }

    @Query(filter: #Predicate<Ajustes> { $0.borrado == nil }) private var todosLosAjustes: [Ajustes]
    @Query(filter: #Predicate<Lista> { $0.borrado == nil }) private var listas: [Lista]

    private var ajustes: Ajustes? {
        guard let id = sesion.usuario?.id else { return nil }
        return todosLosAjustes.first { $0.id == id }
    }
    private var tema: Tema { Tema.de(ajustes?.claveTema ?? .barro) }

    // EL CUERPO, EN TRES TRAMOS.
    //
    // Quince modificadores encadenados en una sola expresión y el compilador se
    // rinde: «unable to type-check this expression in reasonable time». No es
    // que sea complicado, es que cada `.onChange` con su cierre multiplica las
    // combinaciones de tipos que tiene que probar. Partirlo en tramos con un
    // tipo ya resuelto en medio lo deja en segundos.
    var body: some View {
        conLosEnlaces
    }

    private var pintado: some View {
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
    }

    private var conLoQueEscucha: some View {
        pintado
        .onChange(of: sesion.usuario?.id) { _, nuevo in
            guard let nuevo else { return }
            // Los ajustes se crean al entrar, no al arrancar la app: antes de
            // entrar no se sabe de quién son.
            _ = Almacen.ajustes(ctx, de: nuevo)
            Task { await sincronizador?.sincroniza() }
        }
        .onAppear {
            if sincronizador == nil { sincronizador = Sincronizador(contexto: ctx) }
            tema.aplicaALaBarra()
            // Para las capturas: «-pestana tienda» ya no es una pestaña, es
            // estar dentro de la lista que se está comprando.
            if Demo.pestana == "tienda", enTienda == nil { enTienda = laQueSeEstaComprando }
        }
        .onChange(of: tema.id) { _, _ in tema.aplicaALaBarra() }
        .onChange(of: fase) { _, nueva in
            // Al volver a la app se sincroniza: es cuando hay más probabilidad
            // de que otro dispositivo haya escrito algo.
            if nueva == .active {
                Task {
                    await sincronizador?.sincroniza()
                    await repasaAvisos()
                }
            }
        }
        .onChange(of: sincronizador?.ultima) { _, _ in
            // Una lista creada en el otro teléfono también tiene que avisar aquí.
            Task { await repasaAvisos() }
        }
    }

    private var conLosEnlaces: some View {
        conLoQueEscucha
        .onOpenURL { url in
            manda(url)
        }
        .onChange(of: sesion.pulso) { _, _ in
            // Alguien tocó una lista compartida desde otro teléfono.
            Task { await sincronizador?.sincroniza() }
        }
        .sheet(item: $invitacion) { inv in
            InvitacionView(codigo: inv.codigo) { listaId in
                // Aceptar una invitación lleva derecho a comprar esa lista.
                pestana = .listas
                enTienda = listaId
                Task { await sincronizador?.sincroniza() }
            }
            .hojaDeCuadre(tema)
        }
    }

    @ViewBuilder
    private var principal: some View {
        let mostrarVentas = ajustes?.modoVendedor ?? false

        Group {
            if ancho == .regular {
                HStack(spacing: 0) {
                    // En el iPad el raíl se queda incluso dentro de una lista o
                    // de una venta: hay ancho de sobra y quitarlo dejaría media
                    // pantalla vacía para no ganar nada.
                    RailDePestanas(activa: $pestana, conVentas: mostrarVentas)
                    pantalla
                }
            } else {
                ZStack(alignment: .bottom) {
                    pantalla
                    if !aSolas {
                        BarraDePestanas(activa: $pestana, conVentas: mostrarVentas)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .overlay(alignment: .top) { veloDeArriba }
        .animation(.snappy(duration: 0.2), value: aSolas)
        .onChange(of: mostrarVentas) { _, hay in
            if !hay, pestana == .ventas { pestana = .listas }
        }
    }

    /// La compra abierta más reciente. Es a la que lleva el widget y a la que se
    /// vuelve al entrar en la pestaña.
    private var laQueSeEstaComprando: String? {
        listas.filter { $0.estado == "activa" }
            .max(by: { $0.actualizado < $1.actualizado })?.id
    }

    /// Cuando se está DENTRO de algo —comprando una lista o despachando una
    /// venta— la barra sobra: es para saltar entre pantallas generales, y ahí
    /// solo quita sitio justo donde está la mano. Solo en el iPhone: en el iPad
    /// el raíl no estorba.
    private var aSolas: Bool {
        (pestana == .ventas && enLaVenta != nil) || (pestana == .listas && enTienda != nil)
    }

    /// EL VELO DE LA BARRA DE ESTADO.
    ///
    /// Al desplazar, el contenido pasa por detrás de la hora y de la batería, y
    /// un título grande cruzando ahí deja los dos ilegibles medio segundo. Un
    /// difuminado del ancho de la pantalla y del alto justo del margen superior
    /// separa las dos cosas sin tapar nada: lo de debajo se sigue viendo,
    /// borroso, que es lo que dice que la pantalla sigue hacia arriba.
    private var veloDeArriba: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .frame(height: Pantalla.margenDeArriba)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var pantalla: some View {
        Group {
            switch pestana {
            case .listas:
                // Listas es la pantalla general; dentro de una lista se compra
                // a pantalla completa, igual que dentro de una venta.
                if enTienda != nil {
                    EnTiendaView(listaId: $enTienda, pestana: $pestana)
                } else {
                    ListasView(enTienda: $enTienda, pestana: $pestana)
                }
            case .ventas:
                VentasView(abierta: $enLaVenta)
            case .cuadre:
                CuadreView()
            case .ajustes:
                AjustesView(enUnaPestana: true)
            }
        }
        .environment(\.sincronizador, sincronizador)
        // Una lista estirada a mil puntos de ancho es un nombre a la izquierda,
        // un precio a la derecha y un desierto en medio: el ojo pierde el
        // renglón. La de ventas aguanta más porque sus columnas quieren ancho.
        .anchoDeLectura(ancho == .regular ? (pestana == .ventas ? 1100 : 780) : .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

extension Raiz {
    /// A dónde lleva cada enlace que abre la app.
    ///
    ///   · `cuadre://chinola?ok=1`           — la vuelta del permiso de Chinola.
    ///   · `cuadre://invitacion/<codigo>`    — alguien compartió una lista.
    ///   · `https://cuadre.fente.com.do/invitacion/<codigo>` — lo mismo, desde WhatsApp.
    fileprivate func manda(_ url: URL) {
        let trozos = url.pathComponents.filter { $0 != "/" }
        if url.scheme == "cuadre", url.host == "chinola" {
            Task { await sesion.refresca() }
            return
        }
        if trozos.first == "invitacion" || url.host == "invitacion", let codigo = trozos.last, codigo != "invitacion" {
            invitacion = Invitacion(codigo: codigo)
            return
        }
        // Los widgets y la actividad en vivo. Tocar el que dice cuánto llevas
        // gastado tiene que abrir justo esa pantalla, no la portada.
        guard url.scheme == "cuadre" else { return }
        if url.host == "tienda" {
            // «En tienda» dejó de ser una pestaña: es estar dentro de la lista
            // que se está comprando. El enlace viejo sigue valiendo.
            pestana = .listas
            enTienda = laQueSeEstaComprando
            return
        }
        if let destino = Pestana(rawValue: url.host ?? "") { pestana = destino }
    }
}

extension Raiz {
    fileprivate func repasaAvisos() async {
        guard ajustes?.avisarListas ?? true else { return }
        await Avisos.repasa(listas)
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
