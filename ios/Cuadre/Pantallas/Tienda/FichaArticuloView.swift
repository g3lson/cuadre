import SwiftUI
import SwiftData

/// 04 · FICHA DE PRODUCTO.
///
/// La cuenta que nadie hace de cabeza en el mostrador, hecha en los dos
/// sentidos: pones cantidad y precio y sale el total, o escribes lo que te
/// cobraron y sale el precio por libra. Lo segundo es lo que más se usa —el
/// cartel del súper dice el total de la bandeja, no el precio por libra— y por
/// eso el campo del total es tan grande como el del precio.
struct FichaArticuloView: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var cerrar

    @Bindable var articulo: Articulo
    let moneda: String
    var alGuardar: () -> Void

    /// Cuál de los dos números se está calculando. Es lo único que hace falta
    /// recordar para que escribir en uno no se pise con el otro.
    private enum Derivado { case total, precio }

    @State private var cantidad = ""
    @State private var precio = ""
    @State private var total = ""
    @State private var derivado: Derivado = .total
    @State private var menuUnidad = false
    @State private var viendoHistorial = false
    @State private var sugerencias: [String] = []
    /// Si la persona la eligió a mano, no se vuelve a adivinar: corregir algo y
    /// que se corrija solo otra vez al escribir una letra es lo más molesto que
    /// puede hacer una app.
    @State private var categoriaAMano = false
    @FocusState private var foco: Foco?
    /// El nombre es `Foco` y no `Campo` porque `Campo` ya es el campo de texto de
    /// la app: dos cosas con el mismo nombre en el mismo archivo es cómo se
    /// acaba escribiendo la una donde iba la otra.
    private enum Foco: Hashable { case nombre, cantidad, precio, total, nota }

    private var unidad: Unidad { Unidad.de(articulo.unidad) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("¿Qué vas a comprar?", text: $articulo.nombre)
                        .font(tema.titulo(28))
                        .foregroundStyle(tema.texto)
                        .focused($foco, equals: .nombre)
                        .submitLabel(.next)
                        .onChange(of: articulo.nombre) { _, nuevo in
                            articulo.toco()
                            sugerencias = Almacen.sugerencias(ctx, para: nuevo)
                            if !categoriaAMano {
                                let adivinada = Categoria.adivina(nuevo)
                                if adivinada != articulo.categoria { articulo.categoria = adivinada }
                            }
                        }
                        .onSubmit { foco = .cantidad }

                    if !sugerencias.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(sugerencias, id: \.self) { s in
                                    Button { usa(s) } label: {
                                        Text(s)
                                            .font(tema.texto(13, .bold))
                                            .padding(.horizontal, 13).padding(.vertical, 9)
                                            .background(tema.superficie, in: Capsule())
                                            .foregroundStyle(tema.texto)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .frame(height: 40)
                    }

                    numeros
                    comparacion
                    Text(pista)
                        .font(tema.texto(13))
                        .foregroundStyle(tema.neutral700)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                        .padding(.top, -6)

                    Campo(marcador: "Nota (marca, tamaño, «bien fresco»…)", valor: $articulo.nota, tamano: 15)
                        .focused($foco, equals: .nota)
                        .onChange(of: articulo.nota) { _, _ in articulo.toco() }

                    clasificaciones

                    HStack(spacing: 10) {
                        Button("Quitar", role: .destructive) {
                            articulo.entierro()
                            guarda()
                        }
                        .buttonStyle(BotonSuave())
                        .frame(width: 110)

                        Button(articulo.hecho ? "Sacar del carrito" : "Poner en el carrito") {
                            articulo.hecho.toggle()
                            articulo.toco()
                            guarda()
                        }
                        .buttonStyle(BotonPrincipal(alto: 52))
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .fondoDelTema(tema)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { guarda() }.font(tema.texto(16, .bold))
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Listo") { foco = nil }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear { carga() }
        .sheet(isPresented: $viendoHistorial) {
            HistorialDePreciosView(nombre: articulo.nombre, moneda: moneda,
                                   compras: Almacen.historial(ctx, de: articulo.nombre))
                .hojaDeCuadre(tema)
        }
    }

    // MARK: - Los tres números

    /// LO QUE PAGASTE LA ÚLTIMA VEZ.
    ///
    /// Ninguna cadena de aquí publica sus ofertas de forma que una app pueda
    /// leerlas. Pero el precio que importa para tu bolsillo —el tuyo— ya lo
    /// llevas apuntado, y compararlo cuesta cero: si hoy está más caro, se dice
    /// aquí mismo, mientras todavía se puede dejar en el estante.
    @ViewBuilder
    private var comparacion: some View {
        if let (antes, cambio) = Almacen.comparaPrecio(ctx, de: articulo) {
            Button { viendoHistorial = true } label: {
                HStack(spacing: 8) {
                    IconoView(icono: .reloj, tamano: 16, grosor: 2.6)
                    Text(textoDeLaComparacion(antes, cambio))
                        .font(tema.texto(13, .semibold))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    IconoView(icono: .chevron, tamano: 13, grosor: 2.6)
                }
                .foregroundStyle(cambio > 0.02 ? tema.acento800 : tema.acento2_800)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cambio > 0.02 ? tema.acento200 : tema.acento2_200,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, -2)
        }
    }

    private func textoDeLaComparacion(_ antes: Almacen.Compra, _ cambio: Double) -> String {
        let cuanto = Formato.precio(antes.precio, moneda: moneda)
        let donde = antes.tienda.isEmpty ? "" : " en \(antes.tienda)"
        let porciento = Int((abs(cambio) * 100).rounded())
        if porciento < 2 { return "Igual que la última vez: \(cuanto)\(donde)" }
        let verbo = cambio > 0 ? "más caro" : "más barato"
        return "\(porciento)% \(verbo) que la última vez (\(cuanto)\(donde))"
    }

    /// LAS CLASIFICACIONES QUE HAYAS ENCENDIDO.
    ///
    /// Antes aquí había una fila de «Pasillo» fija que no se podía quitar. Si
    /// no clasificas por pasillos —y mucha gente no— era una casilla de más en
    /// cada producto que anotas. Ahora no hay ninguna hasta que enciendas la
    /// que te sirva, y puedes inventarte las tuyas: «Marca», «Talla», lo que
    /// necesites.
    @ViewBuilder
    private var clasificaciones: some View {
        ForEach(Almacen.clasificacionesActivas(ctx)) { c in
            HStack(spacing: 10) {
                Text(c.nombre).font(tema.texto(15, .bold))
                Spacer()
                Menu {
                    Button("Sin poner") { pon("", en: c) }
                    ForEach(Almacen.valoresDe(ctx, c.id)) { v in
                        Button {
                            pon(v.nombre, en: c)
                        } label: {
                            if valorDe(c) == v.nombre {
                                Label(v.nombre, systemImage: "checkmark")
                            } else { Text(v.nombre) }
                        }
                    }
                } label: {
                    ValorYChevron(texto: valorDe(c).isEmpty ? "Sin poner" : valorDe(c))
                }
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 50)
            .background(tema.superficie, in: Capsule())
        }
    }

    private func valorDe(_ c: Clasificacion) -> String {
        c.id == Clasificacion.pasillos ? articulo.categoria : articulo.etiqueta(c.id)
    }

    private func pon(_ valor: String, en c: Clasificacion) {
        if c.id == Clasificacion.pasillos {
            articulo.categoria = valor
            categoriaAMano = true
        } else {
            articulo.pon(valor, en: c.id)
        }
        articulo.toco()
    }

    /// EL ANCHO DE LA COLUMNA DE LA DERECHA.
    ///
    /// Los tres controles —el contador con su unidad, el precio y el total—
    /// miden lo mismo y empiezan donde mismo. Antes cada uno pedía el ancho que
    /// necesitaba su contenido y quedaban tres bordes escalonados: la fila de
    /// arriba corta y las dos de abajo largas. Alinear tres cajas es gratis y
    /// es la diferencia entre una pantalla ordenada y una que parece a medio
    /// hacer.
    private let anchoDeControl: CGFloat = 196

    @ViewBuilder
    private var numeros: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text("Cantidad").font(tema.texto(15, .bold)).lineLimit(1).layoutPriority(-1)
                Spacer(minLength: 4)
                HStack(spacing: 6) {
                    HStack(spacing: 0) {
                        Button { paso(-1) } label: {
                            Text("−").font(tema.texto(20, .bold)).frame(width: 36, height: 38)
                        }
                        TextField("1", text: $cantidad)
                            .font(tema.texto(17, .heavy))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .focused($foco, equals: .cantidad)
                            .onChange(of: cantidad) { _, _ in cambióCantidad() }
                        Button { paso(1) } label: {
                            Text("+").font(tema.texto(20, .bold)).frame(width: 36, height: 38)
                        }
                    }
                    .foregroundStyle(tema.texto)
                    .frame(maxWidth: .infinity)
                    .padding(3)
                    .background(tema.fondo, in: Capsule())

                    Button { withAnimation(.snappy) { menuUnidad.toggle() } } label: {
                        HStack(spacing: 4) {
                            Text(unidad.id).font(tema.texto(14, .heavy)).lineLimit(1)
                            IconoView(icono: .abajo, tamano: 14, grosor: 3)
                        }
                        // Sin `fixedSize`, la fila aprieta y el texto se queda en
                        // cero: el botón sale como un círculo con una flecha.
                        .fixedSize()
                        .foregroundStyle(tema.oscuro ? tema.texto : tema.neutral100)
                        .padding(.horizontal, 13)
                        .frame(height: 44)
                        .background(tema.neutral900, in: Capsule())
                    }
                    .fixedSize()
                    .accessibilityLabel("Unidad: \(unidad.etiqueta)")
                }
                .frame(width: anchoDeControl)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            if menuUnidad {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(Unidad.todas) { u in
                        Button {
                            articulo.unidad = u.id
                            articulo.toco()
                            withAnimation(.snappy) { menuUnidad = false }
                        } label: {
                            Text(u.etiqueta)
                                .font(tema.texto(14, .bold))
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(articulo.unidad == u.id ? tema.neutral900 : tema.fondo, in: Capsule())
                                .foregroundStyle(articulo.unidad == u.id ? (tema.oscuro ? tema.texto : tema.neutral100) : tema.texto)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 10)
            }

            filaNumero(titulo: "Precio por \(unidad.nombre)",
                       aviso: derivado == .precio ? "Calculado del total" : nil,
                       texto: $precio, campo: .precio, resaltada: derivado == .precio) {
                cambióPrecio()
            }
            filaNumero(titulo: "Total",
                       aviso: derivado == .total ? "Cantidad × precio" : nil,
                       texto: $total, campo: .total, resaltada: derivado == .total) {
                cambióTotal()
            }
        }
        .padding(6)
        .background(tema.superficie, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func filaNumero(titulo: String, aviso: String?, texto: Binding<String>,
                            campo: Foco, resaltada: Bool, alCambiar: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(tema.texto(15, .bold))
                    .lineLimit(1).minimumScaleFactor(0.75)
                if let aviso {
                    Text(aviso).font(tema.texto(12, .heavy)).foregroundStyle(tema.acento2_800)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Text(moneda).font(tema.texto(14, .bold)).foregroundStyle(tema.neutral700)
                TextField("0", text: texto)
                    .font(tema.texto(17, .heavy))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity)
                    .focused($foco, equals: campo)
                    .onChange(of: texto.wrappedValue) { _, _ in alCambiar() }
            }
            .padding(.horizontal, 14)
            .frame(width: anchoDeControl, height: 44)
            .background(tema.fondo, in: Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(resaltada ? tema.acento2_200 : .clear,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// La ayuda de abajo cambia según lo que haya puesto: si la unidad pesa y ya
    /// hay precio, dice a cuánto sale la libra y el kilo, que es la comparación
    /// que se hace de pie frente a dos bandejas.
    private var pista: String {
        if unidad.pesa, let enLibras = unidad.enLibras, let p = Double(limpia(precio)), p > 0 {
            let porLibra = p / enLibras
            return "Equivale a \(Formato.precio(porLibra, moneda: moneda))/lb · "
                 + "\(Formato.precio(porLibra * 2.20462, moneda: moneda))/kg. Escribe el total y te saco el precio."
        }
        return "Pon cantidad y precio y te doy el total — o escribe lo que te cobraron y te saco el precio por \(unidad.nombre)."
    }

    // MARK: - Las cuentas

    private func limpia(_ t: String) -> String { t.replacingOccurrences(of: ",", with: ".") }
    private func num(_ t: String) -> Double { Double(limpia(t)) ?? 0 }

    private func carga() {
        // Un producto que ya tiene categoría distinta de la que se adivinaría es
        // que alguien la puso: no se toca.
        categoriaAMano = !articulo.nombre.isEmpty
            && articulo.categoria != Categoria.adivina(articulo.nombre)
            && articulo.categoria != Categoria.porDefecto
        cantidad = Formato.cantidad(articulo.cantidad)
        precio = articulo.precio > 0 ? Formato.cantidad(articulo.precio) : ""
        total = articulo.precio > 0 ? Formato.cantidad(articulo.total) : ""
        derivado = .total
        // Sin teclado automático: se abre cuando se toca el campo. En un
        // producto nuevo tapa la unidad y los precios, que es justo lo que hay
        // que ver antes de escribir.
    }

    private func cambióCantidad() {
        let q = num(cantidad)
        articulo.cantidad = q
        if derivado == .precio {
            // El total manda: si cambia la cantidad, lo que se recalcula es el precio.
            let t = num(total)
            let p = q > 0 ? t / q : 0
            articulo.precio = p
            precio = p > 0 ? Formato.cantidad(p) : ""
        } else {
            total = articulo.precio > 0 ? Formato.cantidad(q * articulo.precio) : ""
        }
        articulo.toco()
    }

    private func cambióPrecio() {
        guard foco == .precio else { return }
        derivado = .total
        let p = num(precio)
        articulo.precio = p
        total = p > 0 ? Formato.cantidad(num(cantidad) * p) : ""
        articulo.toco()
    }

    private func cambióTotal() {
        guard foco == .total else { return }
        derivado = .precio
        let t = num(total)
        let q = num(cantidad)
        let p = q > 0 ? t / q : 0
        articulo.precio = p
        precio = p > 0 ? Formato.cantidad(p) : ""
        articulo.toco()
    }

    private func paso(_ signo: Double) {
        let nuevo = max(0, ((num(cantidad) + signo * unidad.paso) * 100).rounded() / 100)
        cantidad = Formato.cantidad(nuevo)
        cambióCantidad()
    }

    /// Reusar un nombre que ya se escribió trae su último precio y su unidad.
    private func usa(_ nombre: String) {
        articulo.nombre = nombre
        if !categoriaAMano { articulo.categoria = Categoria.adivina(nombre) }
        if let (p, u) = Almacen.ultimoPrecio(ctx, de: nombre) {
            articulo.precio = p
            articulo.unidad = u
            precio = Formato.cantidad(p)
            derivado = .total
            total = Formato.cantidad(num(cantidad) * p)
        }
        articulo.toco()
        sugerencias = []
        foco = .cantidad
    }

    private func guarda() {
        // Un producto sin nombre y sin precio es alguien que abrió la ficha y se
        // arrepintió: se va solo en vez de dejar una fila vacía en la lista.
        if articulo.nombre.trimmingCharacters(in: .whitespaces).isEmpty, articulo.precio == 0 {
            articulo.entierro()
        }
        alGuardar()
        cerrar()
    }
}
