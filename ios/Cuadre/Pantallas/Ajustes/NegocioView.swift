import SwiftUI
import SwiftData
import PhotosUI

/// EL NEGOCIO.
///
/// Un grupo empezó siendo una manera de compartir, pero lo que la gente tiene
/// en la cabeza es «la pescadería», «el colmado», «la casa». Aquí se le pone
/// cara: su nombre, su logo y su portada. Con eso, todo lo que se despacha
/// dentro sale con esa cara —el comprobante que le llega al cliente por
/// WhatsApp, el reporte del día— y deja de parecer un papelito genérico.
///
/// El logo es cuadrado y la portada apaisada, y ninguno de los dos hace falta:
/// sin logo va la inicial sobre el color del grupo, y sin portada un degradado
/// de ese mismo color. Nada se ve roto por no haber subido nada.
struct NegocioView: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(\.sincronizador) private var sincronizador
    @Environment(Sesion.self) private var sesion

    @Bindable var grupo: Grupo

    @State private var compartiendo = false
    @State private var miembros: [Compartir.Miembro] = []
    @State private var eligiendo: Cual?
    @State private var subiendo: Cual?
    @State private var escogida: PhotosPickerItem?

    /// Cuál de las dos se está cambiando.
    private enum Cual: String, Identifiable {
        case logo, portada
        var id: String { rawValue }
        var titulo: String { self == .logo ? "Logo" : "Portada" }
        /// A cuántos puntos de lado se reduce antes de subirla.
        var lado: CGFloat { self == .logo ? 512 : 1400 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                muestra

                Bloque {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cómo se llama").font(tema.texto(15, .bold))
                        Campo(marcador: "Pescadería El Muelle", valor: $grupo.nombre)
                    }
                    .padding(.vertical, 14)

                    Rectangle().fill(tema.divisor).frame(height: 1)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Teléfono").font(tema.texto(15, .bold))
                        Text("Sale en el comprobante, para que el cliente sepa a dónde llamar si algo no cuadra.")
                            .font(tema.texto(13)).foregroundStyle(tema.neutral700)
                            .fixedSize(horizontal: false, vertical: true)
                        Campo(marcador: "809 555 0000", valor: $grupo.telefono, teclado: .phonePad)
                    }
                    .padding(.vertical, 14)
                }

                Rotulo("La cara del negocio")

                Bloque {
                    fila(.logo, detalle: "Cuadrado. Sale en el comprobante y en la lista de ventas.")
                    fila(.portada, detalle: "Apaisada. Es la franja de arriba del día de venta.", ultima: true)
                }

                Text("Las imágenes se guardan en el servidor y las ve toda la gente del negocio. Cámbialas cuando quieras: la anterior se borra sola.")
                    .font(tema.texto(13))
                    .foregroundStyle(tema.neutral700)
                    .fixedSize(horizontal: false, vertical: true)

                Rotulo("La gente")
                Bloque {
                    Button { compartiendo = true } label: {
                        FilaAjuste(titulo: "Quién trabaja aquí",
                                   detalle: gentePuesta, ultima: true) {
                            ValorYChevron(texto: "")
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(tema.texto)
                }

                Rotulo("El color")
                colores
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .fondoDelTema(tema)
        .navigationTitle(grupo.nombre.isEmpty ? "El negocio" : grupo.nombre)
        .navigationBarTitleDisplayMode(.inline)
        .photosPicker(isPresented: Binding(get: { eligiendo != nil },
                                           set: { if !$0 { eligiendo = nil } }),
                      selection: $escogida, matching: .images)
        .onChange(of: escogida) { _, nueva in
            guard let nueva, let cual = subiendo else { return }
            escogida = nil
            Task { await pon(nueva, en: cual) }
        }
        .sheet(isPresented: $compartiendo) {
            CompartirListaView(grupo: grupo, miembros: $miembros).hojaDeCuadre(tema)
        }
        .task {
            miembros = (try? await Compartir.miembros(de: grupo.id, .grupo)) ?? []
        }
        .onDisappear { guarda() }
    }

    private var gentePuesta: String {
        guard !miembros.isEmpty else { return "Solo tú" }
        if miembros.count == 1 { return "Solo tú" }
        return miembros.map(\.comoSeLlama).joined(separator: ", ")
    }

    // MARK: - Trozos

    /// Cómo va a verse. Es la misma franja que corona el día de venta, así que
    /// lo que se ve aquí es exactamente lo que verá el compañero.
    private var muestra: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if grupo.portada.isEmpty {
                    LinearGradient(colors: [ColorLista.color(grupo.color, tema).opacity(0.75),
                                            ColorLista.color(grupo.color, tema).opacity(0.35)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                } else {
                    ImagenDelNegocio(url: grupo.portada) {
                        ColorLista.color(grupo.color, tema).opacity(0.4)
                    }
                }
            }
            .frame(height: 132)
            .frame(maxWidth: .infinity)
            .clipped()

            // Un velo bajo el nombre: una portada clara se come el texto.
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.55)],
                           startPoint: .center, endPoint: .bottom)
                .frame(height: 132)
                .allowsHitTesting(false)

            HStack(spacing: 10) {
                LogoDelNegocio(grupo: grupo, lado: 44)
                Text(grupo.nombre.isEmpty ? "Sin nombre" : grupo.nombre)
                    .font(tema.titulo(20))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                Spacer(minLength: 0)
            }
            .padding(12)
        }
        .frame(height: 132)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            if subiendo != nil {
                ZStack {
                    Color.black.opacity(0.35)
                    ProgressView().tint(.white)
                }
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
        }
    }

    private func fila(_ cual: Cual, detalle: String, ultima: Bool = false) -> some View {
        let puesta = cual == .logo ? grupo.logo : grupo.portada
        return FilaAjuste(titulo: cual.titulo, detalle: detalle, ultima: ultima) {
            HStack(spacing: 8) {
                if !puesta.isEmpty {
                    Button {
                        quita(cual)
                    } label: {
                        IconoView(icono: .papelera, tamano: 18, grosor: 2.4)
                            .foregroundStyle(tema.neutral700)
                            .frame(width: 40, height: 40)
                            .background(tema.fondo, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                Button(puesta.isEmpty ? "Subir" : "Cambiar") {
                    subiendo = cual
                    eligiendo = cual
                }
                .buttonStyle(BotonSuave(alto: 40))
                .fixedSize()
            }
        }
    }

    private var colores: some View {
        HStack(spacing: 8) {
            ForEach(0..<ColorLista.cuantos, id: \.self) { i in
                Button {
                    grupo.color = i
                    guarda()
                } label: {
                    Circle()
                        .fill(ColorLista.color(i, tema))
                        .frame(height: 38)
                        .overlay {
                            if grupo.color == i {
                                Circle().stroke(tema.texto, lineWidth: 2.5).padding(-4)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Lo que hace

    private func pon(_ item: PhotosPickerItem, en cual: Cual) async {
        defer { subiendo = nil }
        guard let datos = try? await item.loadTransferable(type: Data.self),
              let imagen = UIImage(data: datos) else {
            sesion.avisa("No se pudo leer esa imagen", .mal)
            return
        }
        do {
            let url = try await Imagenes.sube(imagen, aGrupo: grupo.id, lado: cual.lado)
            if cual == .logo { grupo.logo = url } else { grupo.portada = url }
            grupo.toco()
            guarda()
            sesion.avisa("\(cual.titulo) puesto", .bien)
        } catch Api.Fallo.sinRed {
            sesion.avisa("Sin conexión: la imagen se sube cuando vuelva", .mal)
        } catch {
            sesion.avisa("No se pudo subir la imagen", .mal)
        }
    }

    private func quita(_ cual: Cual) {
        if cual == .logo { grupo.logo = "" } else { grupo.portada = "" }
        grupo.toco()
        guarda()
    }

    private func guarda() {
        grupo.toco()
        try? ctx.save()
        Task { await sincronizador?.sincroniza() }
    }
}

/// El logo, o la inicial sobre el color del grupo si no hay logo. Se usa en la
/// pantalla del negocio, en la de grupos y en el comprobante, y tiene que verse
/// igual en las tres.
struct LogoDelNegocio: View {
    @Environment(\.tema) private var tema
    let grupo: Grupo
    var lado: CGFloat = 46

    var body: some View {
        Group {
            if grupo.logo.isEmpty {
                ZStack {
                    Circle().fill(ColorLista.color(grupo.color, tema).opacity(0.35))
                    Text(Formato.inicial(grupo.nombre))
                        .font(tema.texto(lado * 0.36, .heavy))
                        .foregroundStyle(tema.texto)
                }
            } else {
                ImagenDelNegocio(url: grupo.logo) {
                    Circle().fill(ColorLista.color(grupo.color, tema).opacity(0.35))
                }
                .clipShape(Circle())
            }
        }
        .frame(width: lado, height: lado)
        .overlay { Circle().stroke(.white.opacity(0.65), lineWidth: 1.5) }
    }
}
