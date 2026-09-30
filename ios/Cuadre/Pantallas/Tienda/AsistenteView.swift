import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// LLENAR LA LISTA SIN TECLEAR.
///
/// Un cuadro y dos botones. No hay pestañas que elegir antes de empezar: se
/// escribe, o se dicta, o se le toma una foto al recibo, y la app hace lo que
/// corresponda. Obligar a decidir «texto o foto» antes de saber qué se quiere
/// hacer es un paso que no hacía falta.
///
/// Nada entra en la lista sin verse antes: el modelo propone y la persona elige
/// qué se queda. Meter diez filas porque «seguro están bien» es como se acaba
/// con una compra que no cuadra y sin saber por qué.
struct AsistenteView: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var cerrar
    @Environment(\.sincronizador) private var sincronizador
    @Environment(Sesion.self) private var sesion

    let lista: Lista

    @State private var texto = ""
    @State private var foto: PhotosPickerItem?
    @State private var imagen: UIImage?
    @State private var leidos: [IA.ProductoLeido] = []
    @State private var elegidos: Set<String> = []
    @State private var trabajando = false
    @State private var error: String?
    @State private var quienLoLeyo = ""
    @State private var dictado = Dictado()
    @FocusState private var escribiendo: Bool

    private var ajustes: Ajustes { Almacen.ajustes(ctx, de: sesion.usuario?.id ?? "") }
    private var hayAlgoQueLeer: Bool {
        imagen != nil || texto.trimmingCharacters(in: .whitespaces).count >= 3
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if leidos.isEmpty { entrada } else { propuesta }
                    if let error { mensaje(error) }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .fondoDelTema(tema)
            .navigationTitle(leidos.isEmpty ? "Llenar la lista" : "¿Cuáles pongo?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dictado.para(); cerrar() }.foregroundStyle(tema.acento700)
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Listo") { escribiendo = false } }
            }
        }
        .onDisappear { dictado.para() }
    }

    // MARK: - Antes

    @ViewBuilder
    private var entrada: some View {
        // El cuadro. Lo que puede hacer se dice DENTRO, donde se va a escribir,
        // y no en un párrafo encima que nadie lee.
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $texto)
                    .font(tema.texto(17))
                    .scrollContentBackground(.hidden)
                    .focused($escribiendo)
                    .frame(minHeight: 150)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)

                if texto.isEmpty && !dictado.escuchando {
                    pista
                        .padding(.horizontal, 17)
                        .padding(.top, 18)
                        .allowsHitTesting(false)
                }
            }

            if let imagen {
                HStack(spacing: 12) {
                    Image(uiImage: imagen)
                        .resizable().scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Foto del recibo").font(tema.texto(14, .bold))
                        Text(LectorDeRecibos.comoSeHace)
                            .font(tema.texto(12)).foregroundStyle(tema.neutral700)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Button { self.imagen = nil; foto = nil } label: {
                        IconoView(icono: .equis, tamano: 16, grosor: 3).foregroundStyle(tema.neutral500)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(tema.fondo, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(10)
            }

            // Los dos atajos, dentro del mismo cuadro: no son dos modos, son dos
            // maneras de llenarlo.
            HStack(spacing: 10) {
                Button { dictado.alterna { texto = $0 } } label: {
                    HStack(spacing: 7) {
                        IconoView(icono: .microfono, tamano: 19, grosor: 2.6)
                        if dictado.escuchando { Text("Escuchando…").font(tema.texto(14, .bold)) }
                    }
                    .foregroundStyle(dictado.escuchando ? tema.sobreAcento : tema.acento700)
                    .padding(.horizontal, dictado.escuchando ? 16 : 0)
                    .frame(width: dictado.escuchando ? nil : 44, height: 44)
                    .background(dictado.escuchando ? tema.acento : tema.fondo,
                                in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(dictado.escuchando ? "Parar de dictar" : "Dictar")

                PhotosPicker(selection: $foto, matching: .images, photoLibrary: .shared()) {
                    IconoView(icono: .camara, tamano: 19, grosor: 2.6)
                        .foregroundStyle(tema.acento700)
                        .frame(width: 44, height: 44)
                        .background(tema.fondo, in: Circle())
                }
                .accessibilityLabel("Foto del recibo")

                Spacer(minLength: 0)

                if !texto.isEmpty {
                    Button("Borrar") { texto = "" }
                        .font(tema.texto(14, .bold))
                        .foregroundStyle(tema.neutral700)
                }
            }
            .padding(10)
        }
        .background(tema.superficie, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onChange(of: foto) { _, nueva in
            Task {
                guard let d = try? await nueva?.loadTransferable(type: Data.self),
                      let i = UIImage(data: d) else { return }
                imagen = i
                escribiendo = false
            }
        }

        if let e = dictado.error { mensaje(e) }

        Button { Task { await lee() } } label: {
            if trabajando { ProgressView().tint(tema.sobreAcento) }
            else { Text(imagen != nil ? "Leer el recibo" : "Convertir en productos") }
        }
        .buttonStyle(BotonPrincipal())
        .disabled(trabajando || !hayAlgoQueLeer)

        Text(imagen != nil
             ? "El texto del recibo lo lee tu iPhone. Solo sale de aquí si hace falta ordenarlo fuera, y en ese caso va el texto, no la foto."
             : "Lo que escribas se manda al servidor de Cuadre y de ahí a un modelo que lo convierte en filas. No se guarda después.")
            .font(tema.texto(12))
            .foregroundStyle(tema.neutral700)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Lo que se puede hacer, escrito donde se va a escribir.
    private var pista: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Escríbelo como lo dirías:")
                .font(tema.texto(17))
                .foregroundStyle(tema.neutral500)
            Text("«dos galones de leche rica, cinco libras de azúcar crema, un saco de arroz selecto, una docena de huevos»")
                .font(tema.texto(15))
                .foregroundStyle(tema.neutral500)
            HStack(spacing: 6) {
                IconoView(icono: .microfono, tamano: 13, grosor: 3)
                Text("dícalo").font(tema.texto(13, .bold))
                Text("·").foregroundStyle(tema.neutral300)
                IconoView(icono: .camara, tamano: 13, grosor: 3)
                Text("o fotografía el recibo y los precios entran solos")
                    .font(tema.texto(13, .bold))
            }
            .foregroundStyle(tema.neutral500)
            .padding(.top, 2)
        }
    }

    // MARK: - Después

    @ViewBuilder
    private var propuesta: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !quienLoLeyo.isEmpty {
                Etiqueta(texto: quienLoLeyo, punto: tema.acento2_700)
            }
            Text("Toca para quitar lo que no va. Lo demás entra en «\(lista.nombre)».")
                .font(tema.texto(15)).foregroundStyle(tema.neutral700)
                .fixedSize(horizontal: false, vertical: true)
        }

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
            leidos = []; elegidos = []; error = nil; quienLoLeyo = ""
        }
        .buttonStyle(BotonFantasma())
    }

    private func mensaje(_ t: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            IconoView(icono: .aviso, tamano: 16, grosor: 3)
            Text(t).font(tema.texto(14, .medium)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tema.acento800)
        .padding(14)
        .background(tema.acento100, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Lo que hace

    private func lee() async {
        dictado.para()
        trabajando = true; error = nil
        defer { trabajando = false }
        if imagen != nil { await leeRecibo() } else { await leeTexto() }
    }

    private func leeTexto() async {
        do {
            let conocidos = Almacen.articulos(ctx, de: lista.id).filter { $0.precio > 0 }
                .map { ($0.nombre, $0.unidad, $0.precio) }
            let r = try await IA.lista(de: texto, tienda: lista.tienda,
                                       conocidos: conocidos, modelo: ajustes.modeloIA)
            quienLoLeyo = r.modelo.isEmpty ? "" : "Leído con \(r.modelo)"
            acepta(r.productos)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "No pude leerlo."
        }
    }

    /// EL RECIBO, DE FUERA HACIA DENTRO.
    ///
    /// Primero el teléfono: saca el texto con Vision y, si tiene Apple
    /// Intelligence, lo ordena él mismo sin que nada salga de aquí. Si no lo
    /// tiene, se manda solo el TEXTO. Y solo si no se leyeron letras —foto
    /// movida, mala luz— se manda la foto entera, que es lo caro.
    private func leeRecibo() async {
        guard let imagen else { return }
        do {
            let texto = try await LectorDeRecibos.texto(de: imagen)
            if let r = await LectorDeRecibos.productos(deTexto: texto, moneda: ajustes.moneda) {
                quienLoLeyo = "Leído en tu iPhone, con Apple Intelligence"
                acepta(r, fuera: false)
                return
            }
            let r = try await IA.recibo(deTexto: texto, modelo: ajustes.modeloIA)
            quienLoLeyo = "Lo leyó tu iPhone · lo ordenó \(r.modelo.isEmpty ? "el servidor" : r.modelo)"
            acepta(r, fuera: true)
        } catch is LectorDeRecibos.Fallo {
            do {
                let r = try await IA.recibo(imagen, modelo: ajustes.modeloIA)
                quienLoLeyo = "No se leyeron letras aquí · lo leyó \(r.modelo.isEmpty ? "el servidor" : r.modelo)"
                acepta(r, fuera: true)
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? "No pude leer el recibo."
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "No pude leer el recibo."
        }
    }

    private func acepta(_ r: IA.Recibo, fuera: Bool) {
        if lista.tienda.isEmpty, !r.tienda.isEmpty {
            lista.tienda = r.tienda
            lista.toco()
        }
        acepta(r.productos)
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
        let yaComprado = imagen != nil
        let quien = (sesion.usuario?.nombre ?? "").split(separator: " ").first.map(String.init) ?? ""
        for (i, p) in leidos.enumerated() where elegidos.contains(p.id) {
            let a = Articulo(listaId: lista.id, nombre: p.nombre, unidad: p.unidad,
                             cantidad: p.cantidad, precio: p.precio, hecho: yaComprado,
                             nota: p.nota,
                             categoria: p.categoria == Categoria.porDefecto
                                 ? Categoria.adivina(p.nombre) : p.categoria,
                             orden: desde + i)
            if yaComprado { a.hechoPor = quien }
            ctx.insert(a)
        }
        lista.toco()
        try? ctx.save()
        Task { await sincronizador?.sincroniza() }
        sesion.avisa("\(elegidos.count) producto\(elegidos.count == 1 ? "" : "s") en la lista", .bien)
        cerrar()
    }
}
