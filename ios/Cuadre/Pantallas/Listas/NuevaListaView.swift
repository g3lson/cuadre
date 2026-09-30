import SwiftUI
import SwiftData

/// 02 · NUEVA LISTA.
///
/// Nombre, tienda, presupuesto y fecha. Y la parte que de verdad ahorra
/// trabajo: empezar repitiendo la compra del mes pasado —con sus precios— o
/// trayéndose lo que faltó la última vez.
struct NuevaListaView: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var cerrar
    @Environment(\.sincronizador) private var sincronizador
    @Environment(Sesion.self) private var sesion

    var alCrear: (Lista) -> Void

    @Query(filter: #Predicate<Lista> { $0.borrado == nil },
           sort: [SortDescriptor<Lista>(\.fecha, order: .reverse)])
    private var listas: [Lista]
    @Query(filter: #Predicate<Tienda> { $0.borrado == nil }) private var tiendas: [Tienda]
    @Query(filter: #Predicate<Grupo> { $0.borrado == nil }, sort: \Grupo.nombre) private var grupos: [Grupo]

    @State private var nombre = ""
    @State private var tienda = ""
    @State private var presupuesto = ""
    @State private var fecha = Date()
    @State private var color = 0
    @State private var grupoId = ""
    @State private var arranque: Arranque = .blanco
    @State private var eligiendoTienda = false
    @FocusState private var enElNombre: Bool

    private enum Arranque: Hashable { case blanco, repetir(String), faltantes }

    /// La última compra cerrada, que es la candidata a repetirse.
    private var ultima: Lista? {
        listas.first { $0.cerrada && $0.nombre != "Faltantes" }
    }
    private var pendientes: [Articulo] {
        Almacen.faltantesPendientes(ctx, tienda: "")
    }
    private var ajustes: Ajustes { Almacen.ajustes(ctx, de: sesion.usuario?.id ?? "") }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Nombre de la lista", text: $nombre)
                        .font(tema.titulo(32))
                        .foregroundStyle(tema.texto)
                        .focused($enElNombre)
                        .submitLabel(.done)
                        .padding(.top, 4)

                    Bloque {
                        FilaAjuste(titulo: "Tienda") {
                            Button { eligiendoTienda = true } label: {
                                ValorYChevron(texto: tienda.isEmpty ? "Elegir" : tienda)
                            }
                        }
                        FilaAjuste(titulo: "Presupuesto") {
                            HStack(spacing: 2) {
                                Text(ajustes.moneda)
                                    .font(tema.texto(14, .bold))
                                    .foregroundStyle(tema.neutral700)
                                TextField("0", text: $presupuesto)
                                    .font(tema.texto(17, .heavy))
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 110)
                            }
                        }
                        FilaAjuste(titulo: "Fecha", ultima: grupos.isEmpty) {
                            DatePicker("", selection: $fecha, displayedComponents: .date)
                                .labelsHidden()
                        }
                        if !grupos.isEmpty {
                            // Elegir grupo ES compartir: lo que se crea dentro lo
                            // ve esa gente sin invitarla a esta lista en concreto.
                            FilaAjuste(titulo: "Grupo",
                                       detalle: grupoId.isEmpty ? "Solo tuya" : "La verá la gente del grupo",
                                       ultima: true) {
                                Menu {
                                    Button("Solo mía") { grupoId = "" }
                                    ForEach(grupos) { g in
                                        Button(g.nombre) { grupoId = g.id }
                                    }
                                } label: {
                                    ValorYChevron(texto: grupos.first { $0.id == grupoId }?.nombre ?? "Ninguno")
                                }
                            }
                        }
                    }

                    Rotulo("Color")
                    HStack(spacing: 12) {
                        ForEach(0..<ColorLista.cuantos, id: \.self) { i in
                            Button { color = i } label: {
                                Circle()
                                    .fill(ColorLista.color(i, tema))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Circle().strokeBorder(tema.texto, lineWidth: color == i ? 2 : 0)
                                            .padding(-4))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Color \(i + 1)")
                        }
                    }

                    Rotulo("Empezar con")
                    VStack(spacing: 6) {
                        opcion(.blanco, titulo: "Lista en blanco", detalle: nil)
                        if let u = ultima {
                            let cuantos = Almacen.articulos(ctx, de: u.id).count
                            opcion(.repetir(u.id), titulo: "Repetir «\(u.nombre)»",
                                   detalle: "\(cuantos) producto\(cuantos == 1 ? "" : "s") con sus últimos precios")
                        }
                        if !pendientes.isEmpty {
                            opcion(.faltantes, titulo: "Traer los faltantes",
                                   detalle: pendientes.prefix(3)
                                       .map { "\($0.nombre) · \(Formato.cantidad($0.cantidad)) \($0.unidad)" }
                                       .joined(separator: "  ·  ")
                                       + (pendientes.count > 3 ? " y \(pendientes.count - 3) más" : ""))
                        }
                    }

                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .fondoDelTema(tema)
            .navigationTitle("Nueva lista")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { cerrar() }.foregroundStyle(tema.acento700)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") { crea() }
                        .font(tema.texto(16, .bold))
                        .disabled(nombre.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .sheet(isPresented: $eligiendoTienda) {
            EligeTienda(elegida: $tienda).hojaDeCuadre(tema)
        }
        .onAppear {
            // El nombre no se autocompleta: lo que se sugiere es la tienda de la
            // última compra, que casi siempre es la misma.
            if tienda.isEmpty { tienda = ultima?.tienda ?? "" }
            if presupuesto.isEmpty, let u = ultima, u.presupuesto > 0 {
                presupuesto = String(Int(u.presupuesto))
            }
            // El teclado NO se abre solo: tapa media pantalla antes de que a
            // nadie le haya dado tiempo de ver qué hay debajo.
        }
    }

    private func opcion(_ cual: Arranque, titulo: String, detalle: String?) -> some View {
        Button { arranque = cual } label: {
            HStack(spacing: 12) {
                Radio(elegido: arranque == cual)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo).font(tema.texto(15, .bold))
                    if let detalle {
                        Text(detalle).font(tema.texto(13)).foregroundStyle(tema.neutral700)
                            .lineLimit(2).multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(arranque == cual ? tema.acento2_200 : tema.superficie,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .foregroundStyle(tema.texto)
        }
        .buttonStyle(.plain)
    }

    private func crea() {
        let limpio = nombre.trimmingCharacters(in: .whitespaces)
        guard !limpio.isEmpty else { return }

        var origen: Lista?
        var traer: [Articulo] = []
        switch arranque {
        case .blanco: break
        case .repetir(let id): origen = listas.first { $0.id == id }
        case .faltantes: traer = pendientes
        }

        let nueva = Almacen.creaLista(
            ctx, nombre: limpio, tienda: tienda,
            presupuesto: Double(presupuesto.filter(\.isNumber)) ?? 0,
            fecha: fecha, color: color, copiandoDe: origen, faltantesDe: traer)
        nueva.grupoId = grupoId

        // La tienda se recuerda para la próxima vez sin que nadie la escriba dos veces.
        if !tienda.isEmpty, !tiendas.contains(where: { $0.nombre == tienda && $0.vivo }) {
            ctx.insert(Tienda(nombre: tienda))
        }
        try? ctx.save()
        Task {
            await sincronizador?.sincroniza()
            if ajustes.avisarListas { await Avisos.recuerda(nueva) }
        }
        alCrear(nueva)
        cerrar()
    }
}

/// Elegir tienda: las que ya usaste, o escribir una nueva.
struct EligeTienda: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var cerrar
    @Binding var elegida: String

    @Query(filter: #Predicate<Tienda> { $0.borrado == nil }, sort: \Tienda.nombre) private var tiendas: [Tienda]
    @State private var nueva = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Campo(marcador: "Otra tienda", valor: $nueva)
                        Button {
                            let t = nueva.trimmingCharacters(in: .whitespaces)
                            guard !t.isEmpty else { return }
                            elegida = t
                            cerrar()
                        } label: {
                            IconoView(icono: .check, tamano: 20, grosor: 3)
                        }
                        .buttonStyle(BotonRedondo(relleno: tema.acento, tinta: tema.sobreAcento))
                        .disabled(nueva.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if !tiendas.isEmpty {
                        Bloque {
                            ForEach(Array(tiendas.enumerated()), id: \.element.id) { i, t in
                                Button {
                                    elegida = t.nombre
                                    cerrar()
                                } label: {
                                    FilaAjuste(titulo: t.nombre, ultima: i == tiendas.count - 1) {
                                        if elegida == t.nombre {
                                            IconoView(icono: .check, tamano: 18, grosor: 3)
                                                .foregroundStyle(tema.acento2_700)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .fondoDelTema(tema)
            .navigationTitle("Tienda")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
