import SwiftUI
import SwiftData
import PhotosUI

/// LA AYUDA PARA NO TECLEAR.
///
/// Dos atajos y los dos opcionales: pegar o dictar la lista en lenguaje normal,
/// y leer la foto del recibo para que los precios entren solos. La app entera
/// funciona sin esto; es un ahorro de tiempo, no una dependencia.
///
/// Nada entra en la lista sin que se vea antes: el modelo propone y la persona
/// elige qué se queda. Meter diez filas directamente porque «seguro están bien»
/// es cómo se acaba con una compra que no cuadra y sin saber por qué.
struct AsistenteView: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var cerrar
    @Environment(\.sincronizador) private var sincronizador
    @Environment(Sesion.self) private var sesion

    let lista: Lista

    private enum Modo: String, CaseIterable { case dictar, recibo }
    @State private var modo: Modo = .dictar
    @State private var texto = ""
    @State private var foto: PhotosPickerItem?
    @State private var imagen: UIImage?
    @State private var leidos: [IA.ProductoLeido] = []
    @State private var elegidos: Set<String> = []
    @State private var trabajando = false
    @State private var error: String?
    @FocusState private var escribiendo: Bool

    private var ajustes: Ajustes { Almacen.ajustes(ctx, de: sesion.usuario?.id ?? "") }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if leidos.isEmpty { entrada } else { propuesta }
                    if let error {
                        HStack(alignment: .top, spacing: 8) {
                            IconoView(icono: .aviso, tamano: 16, grosor: 3)
                            Text(error).font(tema.texto(14, .medium)).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(tema.acento800)
                        .padding(14)
                        .background(tema.acento100, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .fondoDelTema(tema)
            .navigationTitle(leidos.isEmpty ? "Llenar la lista" : "¿Cuáles pongo?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { cerrar() }.foregroundStyle(tema.acento700)
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Listo") { escribiendo = false } }
            }
        }
    }

    // MARK: - Antes

    @ViewBuilder
    private var entrada: some View {
        Picker("", selection: $modo) {
            Text("Dictar o pegar").tag(Modo.dictar)
            Text("Foto del recibo").tag(Modo.recibo)
        }
        .pickerStyle(.segmented)
        .padding(.top, 4)

        if modo == .dictar {
            Text("Escríbelo como lo dirías, o toca el micrófono del teclado y díctalo.")
                .font(tema.texto(15)).foregroundStyle(tema.neutral700)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $texto)
                .font(tema.texto(16))
                .scrollContentBackground(.hidden)
                .focused($escribiendo)
                .frame(minHeight: 180)
                .padding(12)
                .background(tema.superficie, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if texto.isEmpty {
                        Text("dos galones de leche rica, cinco libras de azúcar crema, un saco de arroz selecto, una docena de huevos…")
                            .font(tema.texto(16))
                            .foregroundStyle(tema.neutral500)
                            .padding(18)
                            .allowsHitTesting(false)
                    }
                }

            Button { Task { await leeTexto() } } label: {
                if trabajando { ProgressView().tint(tema.sobreAcento) } else { Text("Convertir en productos") }
            }
            .buttonStyle(BotonPrincipal())
            .disabled(trabajando || texto.trimmingCharacters(in: .whitespaces).count < 3)

        } else {
            Text("Una foto del recibo, derecha y con luz. Se leen las líneas y se saca el precio por unidad.")
                .font(tema.texto(15)).foregroundStyle(tema.neutral700)
                .fixedSize(horizontal: false, vertical: true)

            if let imagen {
                Image(uiImage: imagen)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }

            PhotosPicker(selection: $foto, matching: .images, photoLibrary: .shared()) {
                HStack(spacing: 8) {
                    IconoView(icono: .camara, tamano: 20)
                    Text(imagen == nil ? "Elegir la foto" : "Cambiar la foto")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(BotonSuave())
            .onChange(of: foto) { _, nueva in
                Task {
                    guard let d = try? await nueva?.loadTransferable(type: Data.self),
                          let i = UIImage(data: d) else { return }
                    imagen = i
                }
            }

            Button { Task { await leeRecibo() } } label: {
                if trabajando { ProgressView().tint(tema.sobreAcento) } else { Text("Leer el recibo") }
            }
            .buttonStyle(BotonPrincipal())
            .disabled(trabajando || imagen == nil)
        }

        Text("Lo que escribas o la foto se manda al servidor de Cuadre y de ahí a un modelo que lo convierte en filas. No se guarda después.")
            .font(tema.texto(12))
            .foregroundStyle(tema.neutral700)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    // MARK: - Después

    @ViewBuilder
    private var propuesta: some View {
        Text("Toca para quitar lo que no va. Lo demás entra en «\(lista.nombre)».")
            .font(tema.texto(15)).foregroundStyle(tema.neutral700)
            .fixedSize(horizontal: false, vertical: true)

        ForEach(leidos) { p in
            Button {
                if elegidos.contains(p.id) { elegidos.remove(p.id) } else { elegidos.insert(p.id) }
            } label: {
                HStack(spacing: 12) {
                    Marcador(puesto: elegidos.contains(p.id))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.nombre).font(tema.texto(16, .bold))
                        Text([
                            "\(Formato.cantidad(p.cantidad)) \(p.unidad)",
                            p.precio > 0 ? "\(Formato.precio(p.precio, moneda: ajustes.moneda))/\(p.unidad)" : "sin precio",
                            p.nota.isEmpty ? nil : p.nota,
                        ].compactMap { $0 }.joined(separator: " · "))
                            .font(tema.texto(13)).foregroundStyle(tema.neutral700)
                    }
                    Spacer(minLength: 6)
                    if p.precio > 0 {
                        Text(Formato.pesos(p.cantidad * p.precio, moneda: ajustes.moneda))
                            .font(tema.texto(15, .heavy))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(elegidos.contains(p.id) ? tema.superficie : tema.superficie.opacity(0.4),
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .foregroundStyle(elegidos.contains(p.id) ? tema.texto : tema.neutral700)
            }
            .buttonStyle(.plain)
        }

        Button("Agregar \(elegidos.count) producto\(elegidos.count == 1 ? "" : "s")") { agrega() }
            .buttonStyle(BotonPrincipal())
            .disabled(elegidos.isEmpty)
            .padding(.top, 6)

        Button("Volver a empezar") {
            leidos = []; elegidos = []; error = nil
        }
        .buttonStyle(BotonFantasma())
    }

    // MARK: - Lo que hace

    private func leeTexto() async {
        trabajando = true; error = nil
        defer { trabajando = false }
        do {
            let conocidos = Almacen.articulos(ctx, de: lista.id).filter { $0.precio > 0 }
                .map { ($0.nombre, $0.unidad, $0.precio) }
            let r = try await IA.lista(de: texto, tienda: lista.tienda, conocidos: conocidos)
            acepta(r)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "No pude leerlo."
        }
    }

    private func leeRecibo() async {
        guard let imagen else { return }
        trabajando = true; error = nil
        defer { trabajando = false }
        do {
            let r = try await IA.recibo(imagen)
            // Si el recibo dice de qué tienda es y la lista no lo sabía, se toma.
            if lista.tienda.isEmpty, !r.tienda.isEmpty {
                lista.tienda = r.tienda
                lista.toco()
            }
            acepta(r.productos)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "No pude leer el recibo."
        }
    }

    private func acepta(_ productos: [IA.ProductoLeido]) {
        guard !productos.isEmpty else {
            error = "No encontré productos ahí. Prueba a escribirlo de otra forma."
            return
        }
        withAnimation(.snappy) {
            leidos = productos
            elegidos = Set(productos.map(\.id))
        }
    }

    private func agrega() {
        let desde = (Almacen.articulos(ctx, de: lista.id).map(\.orden).max() ?? 0) + 1
        // Lo que vino del recibo ya se compró: entra marcado. Lo que se dictó es
        // la lista de la compra, así que entra por comprar.
        let yaComprado = modo == .recibo
        for (i, p) in leidos.enumerated() where elegidos.contains(p.id) {
            let a = Articulo(listaId: lista.id, nombre: p.nombre, unidad: p.unidad,
                             cantidad: p.cantidad, precio: p.precio, hecho: yaComprado,
                             nota: p.nota, categoria: p.categoria, orden: desde + i)
            ctx.insert(a)
        }
        lista.toco()
        try? ctx.save()
        Task { await sincronizador?.sincroniza() }
        sesion.avisa("\(elegidos.count) producto\(elegidos.count == 1 ? "" : "s") en la lista", .bien)
        cerrar()
    }
}
