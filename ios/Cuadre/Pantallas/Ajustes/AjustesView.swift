import SwiftUI
import SwiftData

/// 14 · AJUSTES.
///
/// Está detrás del avatar y no en una pestaña: se entra dos veces al mes y no
/// merece una quinta parte de la barra de abajo.
struct AjustesView: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var cerrar
    @Environment(\.sincronizador) private var sincronizador
    @Environment(Sesion.self) private var sesion

    @State private var editandoNombre = false
    @State private var nombre = ""
    @State private var camino: [Destino] = {
        for d in [Destino.catalogo, .tarifas, .chinola, .cuenta, .ia, .grupos, .pasillos]
            where Demo.abre(String(describing: d)) {
            return [d]
        }
        // La pantalla de un negocio cuelga de la lista de negocios: para
        // fotografiarla hay que pasar por ahí.
        if Demo.abre("negocio") { return [.grupos] }
        return []
    }()

    private var ajustes: Ajustes { Almacen.ajustes(ctx, de: sesion.usuario?.id ?? "") }

    var body: some View {
        NavigationStack(path: $camino) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    perfil
                    negocio
                    conexiones
                    preferencias
                    pie
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .fondoDelTema(tema)
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { cerrar() }.font(tema.texto(16, .bold))
                }
            }
            .navigationDestination(for: Destino.self) { d in
                switch d {
                case .catalogo: CatalogoView()
                case .tarifas: TarifasView(ajustes: ajustes)
                case .chinola: ChinolaAjustesView()
                case .cuenta: CuentaView()
                case .ia: ModelosIAView(ajustes: ajustes)
                case .pasillos: PasillosView()
                case .grupos: GruposView()
                }
            }
        }
        .alert("¿Cómo te llamas?", isPresented: $editandoNombre) {
            TextField("Tu nombre", text: $nombre)
            Button("Guardar") { Task { await sesion.renombra(nombre) } }
            Button("Dejarlo", role: .cancel) {}
        } message: {
            Text("Es el nombre con el que te saluda la app y el que sale en los reportes.")
        }
    }

    enum Destino: Hashable { case catalogo, tarifas, chinola, cuenta, ia, pasillos, grupos }

    // MARK: - Trozos

    private var perfil: some View {
        Button {
            nombre = sesion.usuario?.nombre ?? ""
            editandoNombre = true
        } label: {
            HStack(spacing: 14) {
                Text(sesion.usuario?.inicial ?? "?")
                    .font(tema.texto(20, .heavy))
                    .foregroundStyle(tema.acento2_800)
                    .frame(width: 56, height: 56)
                    .background(tema.acento2_200, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(sesion.usuario?.nombre.isEmpty == false ? sesion.usuario!.nombre : "Ponle tu nombre")
                        .font(tema.texto(17, .heavy))
                    Text(sesion.usuario?.email ?? "")
                        .font(tema.texto(13)).foregroundStyle(tema.neutral700).lineLimit(1)
                }
                Spacer(minLength: 6)
                IconoView(icono: .lapiz, tamano: 18).foregroundStyle(tema.neutral500)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(tema.superficie, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .foregroundStyle(tema.texto)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var negocio: some View {
        Rotulo("Mi negocio").padding(.top, 6)
        Bloque {
            FilaAjuste(titulo: "Modo vendedor", detalle: "Activa la pestaña Ventas") {
                Interruptor(encendido: Binding(
                    get: { ajustes.modoVendedor },
                    set: { ajustes.modoVendedor = $0; ajustes.toco() }))
            }
            NavigationLink(value: Destino.catalogo) {
                FilaAjuste(titulo: "Catálogo de precios") {
                    ValorYChevron(texto: "\(cuantosProductos) producto\(cuantosProductos == 1 ? "" : "s")")
                }
            }
            .buttonStyle(.plain)

            NavigationLink(value: Destino.pasillos) {
                FilaAjuste(titulo: "Pasillos", detalle: "El orden en que recorres la tienda") {
                    ValorYChevron(texto: "\(cuantosPasillos)")
                }
            }
            .buttonStyle(.plain)

            NavigationLink(value: Destino.tarifas) {
                FilaAjuste(titulo: "Tarifas", ultima: true) {
                    ValorYChevron(texto: [ajustes.nombreDetal, ajustes.nombreMayor, ajustes.nombreEspecial]
                        .joined(separator: " · "))
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var cuantosPasillos: Int {
        ((try? ctx.fetch(FetchDescriptor<Pasillo>())) ?? []).filter(\.vivo).count
    }

    private var cuantosProductos: Int {
        ((try? ctx.fetch(FetchDescriptor<Producto>())) ?? []).filter(\.vivo).count
    }

    @ViewBuilder
    private var conexiones: some View {
        Rotulo("Conexiones").padding(.top, 6)
        Bloque {
            NavigationLink(value: Destino.grupos) {
                FilaAjuste(titulo: "Negocios", detalle: "Su nombre, su logo y con quién lo llevas") {
                    IconoView(icono: .chevron, tamano: 16, grosor: 3).foregroundStyle(tema.neutral500)
                }
            }
            .buttonStyle(.plain)

            NavigationLink(value: Destino.chinola) {
                FilaAjuste(titulo: "Chinola", detalle: chinolaDetalle) {
                    IconoView(icono: .chevron, tamano: 16, grosor: 3).foregroundStyle(tema.neutral500)
                }
            }
            .buttonStyle(.plain)

            NavigationLink(value: Destino.ia) {
                FilaAjuste(titulo: "La IA", detalle: detalleIA, ultima: true) {
                    IconoView(icono: .chevron, tamano: 16, grosor: 3).foregroundStyle(tema.neutral500)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var chinolaDetalle: String {
        guard let c = sesion.chinola else { return "Sin conectar" }
        let donde = [c.cuenta.isEmpty ? nil : c.cuenta].compactMap { $0 }.joined()
        return donde.isEmpty ? "Conectada" : "Conectada · \(donde)"
    }

    private var detalleIA: String {
        if !sesion.hayIA { return "Apagada en el servidor" }
        if !ajustes.modeloIA.isEmpty { return ajustes.modeloIA }
        return LectorDeRecibos.todoAquí
            ? "En tu iPhone, y modelos gratuitos"
            : "Modelos gratuitos"
    }

    @ViewBuilder
    private var preferencias: some View {
        Rotulo("Preferencias").padding(.top, 6)
        Bloque {
            FilaAjuste(titulo: "Moneda") {
                Menu {
                    ForEach(["RD$", "US$", "€"], id: \.self) { m in
                        Button(m) { ajustes.moneda = m; ajustes.toco() }
                    }
                } label: {
                    ValorYChevron(texto: ajustes.moneda == "RD$" ? "Peso dominicano (RD$)" : ajustes.moneda)
                }
            }
            FilaAjuste(titulo: "Recordar mis listas",
                       detalle: "Un aviso la víspera de cada compra con fecha") {
                Interruptor(encendido: Binding(
                    get: { ajustes.avisarListas },
                    set: { nuevo in
                        ajustes.avisarListas = nuevo
                        ajustes.toco()
                        Task { if nuevo { await Avisos.pidePermiso() } }
                    }))
            }
            FilaAjuste(titulo: "Proteger la pantalla de ventas",
                       detalle: "Preguntar antes de dar un encargo por cobrado") {
                Interruptor(encendido: Binding(
                    get: { ajustes.confirmarCobro },
                    set: { ajustes.confirmarCobro = $0; ajustes.toco() }))
            }
            FilaAjuste(titulo: "Unidad por defecto") {
                Menu {
                    ForEach(Unidad.todas) { u in
                        Button(u.etiqueta) { ajustes.unidadPorDefecto = u.id; ajustes.toco() }
                    }
                } label: {
                    ValorYChevron(texto: Unidad.de(ajustes.unidadPorDefecto).etiqueta)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Tema").font(tema.texto(15, .bold))
                HStack(spacing: 6) {
                    ForEach(Tema.todos) { t in
                        Button {
                            withAnimation(.snappy) { ajustes.tema = t.id.rawValue; ajustes.toco() }
                        } label: {
                            HStack(spacing: 6) {
                                Circle().fill(t.muestra).frame(width: 14, height: 14)
                                Text(t.nombre).font(tema.texto(13, .heavy))
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(ajustes.tema == t.id.rawValue ? tema.neutral900 : tema.fondo, in: Capsule())
                            .foregroundStyle(ajustes.tema == t.id.rawValue
                                             ? (tema.oscuro ? tema.texto : tema.neutral100)
                                             : tema.texto)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var pie: some View {
        Rotulo("Tu cuenta").padding(.top, 6)
        Bloque {
            NavigationLink(value: Destino.cuenta) {
                FilaAjuste(titulo: "Sesiones, datos y borrar la cuenta", ultima: true) {
                    IconoView(icono: .chevron, tamano: 16, grosor: 3).foregroundStyle(tema.neutral500)
                }
            }
            .buttonStyle(.plain)
        }

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Marca(tamano: 28)
                Text("cuadre").font(tema.titulo(20)).foregroundStyle(tema.texto)
                Spacer()
                Text(version).font(tema.texto(12)).foregroundStyle(tema.neutral700)
            }
            HStack(spacing: 14) {
                Link("Privacidad", destination: URL(string: "https://cuadre.fente.com.do/legal/privacidad.html")!)
                Link("Términos", destination: URL(string: "https://cuadre.fente.com.do/legal/terminos.html")!)
                Link("Soporte", destination: URL(string: "https://cuadre.fente.com.do/legal/soporte.html")!)
            }
            .font(tema.texto(13, .bold))
            if let u = sincronizador?.ultima {
                Text("Sincronizado \(Formato.dia(u)) a las \(Formato.hora(u))")
                    .font(tema.texto(12)).foregroundStyle(tema.neutral700)
            }
        }
        .padding(.top, 18)
    }

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "v\(v) (\(b))"
    }
}
