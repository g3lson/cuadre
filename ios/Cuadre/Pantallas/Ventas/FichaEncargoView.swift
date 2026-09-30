import SwiftUI
import SwiftData

/// UN ENCARGO, DE CERCA.
///
/// En el mostrador pasan dos cosas que la fila de la lista no resuelve: la
/// balanza dice 4.2 y no 4.5, y el cliente dice «dame doscientos pesos de eso».
/// Aquí se puede **escribir** la cantidad, o escribir el total y que salga la
/// cantidad que corresponde — la misma cuenta de dos sentidos que hay al
/// comprar, porque es la misma pregunta al revés.
///
/// Y aquí se marca lo que sale sin cobrarse: un regalo, una donación, lo que se
/// llevó la casa. La mercancía sale igual y cuesta igual; lo que cambia es si
/// entra dinero, y el cuadre tiene que poder decirlo.
struct FichaEncargoView: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var cerrar
    @Environment(\.sincronizador) private var sincronizador

    @Bindable var encargo: Encargo
    let ajustes: Ajustes
    /// Entre quiénes se puede repartir este cobro.
    var gente: [String] = []
    var yo: String = ""
    var alCobrar: (Encargo) -> Void

    /// El método con el que se iba a cobrar, esperando un «sí».
    @State private var porConfirmar: String?

    private enum Derivado { case total, cantidad }
    @State private var cantidad = ""
    @State private var precio = ""
    @State private var total = ""
    @State private var derivado: Derivado = .total
    @FocusState private var foco: Foco?
    private enum Foco: Hashable { case cantidad, precio, total, nota }

    private var unidad: Unidad { Unidad.de(encargo.unidad) }
    private var moneda: String { ajustes.moneda }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    cabecera
                    clase
                    numeros
                    Text(pista)
                        .font(tema.texto(13))
                        .foregroundStyle(tema.neutral700)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                        .padding(.top, -6)

                    Campo(marcador: "Nota (escamado, hora de retiro…)", valor: $encargo.nota, tamano: 15)
                        .focused($foco, equals: .nota)
                        .onChange(of: encargo.nota) { _, _ in encargo.toco() }

                    acciones
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .fondoDelTema(tema)
            .navigationTitle(encargo.cliente)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { guarda(); cerrar() }.font(tema.texto(16, .bold))
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Listo") { foco = nil } }
            }
        }
        .onAppear { carga() }
        .sheet(item: Binding(get: { porConfirmar.map(Metodo.init) },
                             set: { porConfirmar = $0?.nombre })) { m in
            ConfirmarCobroView(encargo: encargo, metodo: m.nombre, moneda: moneda,
                               gente: gente,
                               aNombreDe: encargo.registradoPor.isEmpty
                                   ? yo : encargo.registradoPor) { quien in
                cobraYa(m.nombre, quien)
            }
        }
    }

    /// Un `String` no es `Identifiable` y `sheet(item:)` lo pide.
    private struct Metodo: Identifiable {
        let nombre: String
        var id: String { nombre }
        init(_ nombre: String) { self.nombre = nombre }
    }

    // MARK: - Trozos

    private var cabecera: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(encargo.producto).font(tema.titulo(28)).foregroundStyle(tema.texto)
            Text("Pidió \(Formato.cantidad(encargo.pedido)) \(encargo.unidad)")
                .font(tema.texto(14)).foregroundStyle(tema.neutral700)
        }
    }

    @ViewBuilder
    private var clase: some View {
        Rotulo("Qué es esta salida")
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(Salida.allCases) { s in
                    Button {
                        encargo.clase = s.rawValue
                        encargo.toco()
                        recalcula()
                    } label: {
                        Text(s.etiqueta)
                            .font(tema.texto(13, .heavy))
                            .lineLimit(1).fixedSize()
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .background(encargo.clase == s.rawValue ? tema.neutral900 : tema.superficie, in: Capsule())
                            .foregroundStyle(encargo.clase == s.rawValue
                                             ? (tema.oscuro ? tema.texto : tema.neutral100) : tema.texto)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        Text(encargo.salida.explicacion)
            .font(tema.texto(13))
            .foregroundStyle(encargo.salida.cobra ? tema.neutral700 : tema.acento800)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var numeros: some View {
        VStack(spacing: 4) {
            // La cantidad se escribe. Los botones siguen ahí para los ajustes de
            // medio en medio, pero la balanza dice 4.2 y eso hay que poder teclearlo.
            HStack(spacing: 8) {
                Text("Cantidad").font(tema.texto(15, .bold)).lineLimit(1).layoutPriority(-1)
                Spacer(minLength: 4)
                HStack(spacing: 6) {
                    HStack(spacing: 0) {
                        Button { paso(-1) } label: {
                            Text("−").font(tema.texto(20, .bold)).frame(width: 38, height: 38)
                        }
                        TextField("0", text: $cantidad)
                            .font(tema.texto(17, .heavy))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 58)
                            .focused($foco, equals: .cantidad)
                            .onChange(of: cantidad) { _, _ in cambióCantidad() }
                        Button { paso(1) } label: {
                            Text("+").font(tema.texto(20, .bold)).frame(width: 38, height: 38)
                        }
                    }
                    .foregroundStyle(tema.texto)
                    .padding(3)
                    .background(tema.fondo, in: Capsule())

                    Text(unidad.id)
                        .font(tema.texto(14, .heavy))
                        .lineLimit(1).fixedSize()
                        .foregroundStyle(tema.oscuro ? tema.texto : tema.neutral100)
                        .padding(.horizontal, 13)
                        .frame(height: 44)
                        .background(tema.neutral900, in: Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            HStack(spacing: 6) {
                Text("Tarifa").font(tema.texto(15, .bold))
                Spacer()
                HStack(spacing: 2) {
                    ForEach(Tarifa.allCases, id: \.self) { t in
                        Button {
                            encargo.tarifa = t.rawValue
                            encargo.toco()
                            recalcula()
                        } label: {
                            Text(ajustes.nombreTarifa(t))
                                .font(tema.texto(12, .heavy))
                                .lineLimit(1).fixedSize()
                                .padding(.horizontal, 9)
                                .frame(height: 36)
                                .background(encargo.tarifa == t.rawValue ? tema.neutral900 : .clear, in: Capsule())
                                .foregroundStyle(encargo.tarifa == t.rawValue
                                                 ? (tema.oscuro ? tema.texto : tema.neutral100) : tema.neutral700)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(tema.fondo, in: Capsule())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            filaNumero(titulo: "Precio por \(unidad.nombre)",
                       aviso: nil, texto: $precio, campo: .precio, resaltada: false) { cambióPrecio() }

            filaNumero(titulo: encargo.salida.cobra ? "Le cobras" : "Vale",
                       aviso: derivado == .cantidad ? "De aquí salió la cantidad" : nil,
                       texto: $total, campo: .total, resaltada: derivado == .cantidad) { cambióTotal() }
        }
        .padding(6)
        .background(tema.superficie, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func filaNumero(titulo: String, aviso: String?, texto: Binding<String>,
                            campo: Foco, resaltada: Bool, alCambiar: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(tema.texto(15, .bold))
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
                    .frame(width: 92)
                    .focused($foco, equals: campo)
                    .onChange(of: texto.wrappedValue) { _, _ in alCambiar() }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(tema.fondo, in: Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(resaltada ? tema.acento2_200 : .clear,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// A nombre de quién queda. En el mostrador uno anota por el compañero que
    /// tiene las manos llenas; el cuadre de la noche tiene que decir quién
    /// despachó, no quién tocó el botón.
    @ViewBuilder
    private var quienLoAnoto: some View {
        if gente.count > 1 {
            Menu {
                ForEach(gente, id: \.self) { quien in
                    Button {
                        encargo.registradoPor = quien
                        encargo.toco()
                        guarda()
                    } label: {
                        if quien == encargo.registradoPor {
                            Label(quien, systemImage: "checkmark")
                        } else { Text(quien) }
                    }
                }
            } label: {
                Bloque {
                    FilaAjuste(titulo: "Lo anotó", ultima: true) {
                        ValorYChevron(texto: encargo.registradoPor.isEmpty
                                      ? yo : encargo.registradoPor)
                    }
                }
                .foregroundStyle(tema.texto)
            }
        }
    }

    @ViewBuilder
    private var acciones: some View {
        quienLoAnoto

        if encargo.cobrado {
            Button("Volver a dejarlo pendiente") {
                encargo.estado = "pendiente"
                encargo.metodo = ""
                encargo.cobradoEn = nil
                encargo.toco()
                guarda()
            }
            .buttonStyle(BotonSuave())
        } else if encargo.salida.cobra {
            HStack(spacing: 8) {
                Button("Cobrar \(Formato.pesos(encargo.total, moneda: moneda))") { cobra("Efectivo") }
                    .buttonStyle(BotonPrincipal(alto: 52))
                Button("Transf.") { cobra("Transferencia") }
                    .buttonStyle(BotonSuave(alto: 52))
                    .frame(width: 100)
            }
        } else {
            Button("Anotar la salida") { cobra(encargo.salida.etiqueta) }
                .buttonStyle(BotonPrincipal())
        }

        Button("Quitar el encargo", role: .destructive) {
            encargo.entierro()
            guarda()
            cerrar()
        }
        .buttonStyle(BotonFantasma())
    }

    private var pista: String {
        if !encargo.salida.cobra {
            return "No entra dinero, pero la mercancía sale: te cuesta "
                 + "\(Formato.pesos(encargo.costoTotal, moneda: moneda)) y sale en el cuadre aparte."
        }
        if derivado == .cantidad {
            return "Escribiste el total y salió la cantidad. Escribe la cantidad y hará lo contrario."
        }
        return "Escribe la cantidad que marcó la balanza, o escribe lo que te pidieron en dinero y te doy la cantidad."
    }

    // MARK: - Las cuentas

    private func limpia(_ t: String) -> String { t.replacingOccurrences(of: ",", with: ".") }
    private func num(_ t: String) -> Double { Double(limpia(t)) ?? 0 }

    private func carga() {
        cantidad = Formato.cantidad(encargo.cantidad)
        precio = encargo.precioAplicado > 0 ? Formato.cantidad(encargo.precioAplicado) : ""
        total = Formato.cantidad(encargo.cantidad * encargo.precioAplicado)
        derivado = .total
    }

    private func recalcula() {
        precio = encargo.precioAplicado > 0 ? Formato.cantidad(encargo.precioAplicado) : ""
        if derivado == .total {
            total = Formato.cantidad(num(cantidad) * encargo.precioAplicado)
        } else {
            let p = encargo.precioAplicado
            let q = p > 0 ? num(total) / p : 0
            cantidad = Formato.cantidad(q)
            encargo.cantidad = q
            encargo.toco()
        }
    }

    private func cambióCantidad() {
        guard foco == .cantidad else { return }
        derivado = .total
        let q = num(cantidad)
        encargo.cantidad = q
        total = Formato.cantidad(q * encargo.precioAplicado)
        encargo.toco()
    }

    /// Cambiar el precio a mano cambia la tarifa que se está usando, no crea una
    /// cuarta: si alguien escribe otro número, ese es el precio de esta venta.
    private func cambióPrecio() {
        guard foco == .precio else { return }
        let p = num(precio)
        switch Tarifa(rawValue: encargo.tarifa) ?? .detal {
        case .detal: encargo.precioDetal = p
        case .mayor: encargo.precioMayor = p
        case .especial: encargo.precioEspecial = p
        }
        total = Formato.cantidad(num(cantidad) * p)
        derivado = .total
        encargo.toco()
    }

    /// «Dame doscientos pesos de eso». Se escribe el total y sale la cantidad.
    private func cambióTotal() {
        guard foco == .total else { return }
        derivado = .cantidad
        let p = encargo.precioAplicado
        guard p > 0 else { return }
        let q = (num(total) / p * 100).rounded() / 100
        cantidad = Formato.cantidad(q)
        encargo.cantidad = q
        encargo.toco()
    }

    private func paso(_ signo: Double) {
        let nuevo = max(0, ((num(cantidad) + signo * unidad.paso) * 100).rounded() / 100)
        cantidad = Formato.cantidad(nuevo)
        derivado = .total
        encargo.cantidad = nuevo
        total = Formato.cantidad(nuevo * encargo.precioAplicado)
        encargo.toco()
    }

    /// Con la pantalla protegida esto no cobra: pregunta.
    private func cobra(_ metodo: String) {
        if ajustes.confirmarCobro { porConfirmar = metodo } else { cobraYa(metodo, "") }
    }

    private func cobraYa(_ metodo: String, _ quien: String) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if !quien.isEmpty { encargo.registradoPor = quien }
        encargo.estado = "cobrado"
        encargo.metodo = metodo
        encargo.cobradoEn = .now
        encargo.toco()
        guarda()
        alCobrar(encargo)
        cerrar()
    }

    private func guarda() {
        try? ctx.save()
        Task { await sincronizador?.sincroniza() }
    }
}
