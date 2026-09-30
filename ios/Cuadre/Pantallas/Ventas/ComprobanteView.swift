import SwiftUI

/// 12 · COMPROBANTE.
///
/// El papelito de siempre, en la pantalla: quién, qué, cuánto pesó, a qué
/// precio y cuánto pagó. Se manda por WhatsApp porque es por donde se habla con
/// los clientes aquí, y se comparte como imagen para quien no tenga WhatsApp.
///
/// El recibo se pinta siempre en claro, aunque la app esté en tema Noche: un
/// recibo es blanco, y en la foto que le llega al cliente se lee mejor.
struct ComprobanteView: View {
    @Environment(\.tema) private var tema
    @Environment(\.dismiss) private var cerrar
    @Environment(\.openURL) private var abre

    let encargo: Encargo
    let moneda: String

    private let papel = Color(hex: 0xffffff)
    private let tinta = Color(hex: 0x201e1d)
    private let suave = Color(hex: 0x645c50)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    recibo
                        .padding(.horizontal, 20)

                    VStack(spacing: 10) {
                        if !encargo.telefono.isEmpty {
                            Button("Enviar por WhatsApp") { porWhatsApp() }
                                .buttonStyle(BotonPrincipal())
                        }
                        ShareLink(item: texto) {
                            Text("Compartir o imprimir").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BotonSuave())
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 12)
            }
            .fondoDelTema(tema)
            .navigationTitle("Comprobante")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { cerrar() }.font(tema.texto(16, .bold))
                }
            }
        }
        .presentationDetents([.large])
    }

    private var recibo: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: 0xc67139)).frame(width: 14, height: 14)
                    Text("cuadre").font(.custom("Caprasimo-Regular", size: 17))
                }
                Spacer()
                Text("#" + String(encargo.id.suffix(4)).uppercased())
                    .font(.system(size: 12)).foregroundStyle(suave)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Cliente").font(.system(size: 12)).foregroundStyle(suave)
                Text(encargo.cliente).font(.system(size: 18, weight: .heavy))
            }

            VStack(spacing: 8) {
                HStack {
                    Text(encargo.producto)
                    Spacer()
                    Text("\(Formato.cantidad(encargo.cantidad)) \(encargo.unidad)")
                }
                HStack {
                    Text("Precio \(Tarifa(rawValue: encargo.tarifa)?.etiqueta.lowercased() ?? "")")
                    Spacer()
                    Text("\(Formato.precio(encargo.precioAplicado, moneda: moneda))/\(encargo.unidad)")
                }
                .foregroundStyle(suave)
            }
            .font(.system(size: 14))
            .padding(.vertical, 12)
            .overlay(alignment: .top) { linea }
            .overlay(alignment: .bottom) { linea }

            HStack(alignment: .firstTextBaseline) {
                Text("Total").font(.system(size: 15, weight: .bold))
                Spacer()
                Text(Formato.pesos(encargo.total, moneda: moneda))
                    .font(.custom("Caprasimo-Regular", size: 30))
            }

            HStack {
                Text("\(encargo.metodo.isEmpty ? "Pendiente" : encargo.metodo)\(encargo.cobrado ? " · Pagado" : "")")
                Spacer()
                if let f = encargo.cobradoEn {
                    Text("\(Formato.dia(f)) · \(Formato.hora(f))")
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(suave)

            Text("¡Gracias por su compra!")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: 0x56633f))
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(Color(hex: 0xf0fae1), in: Capsule())
        }
        .foregroundStyle(tinta)
        .padding(22)
        .background(papel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }

    /// Punteada, como el papel de un recibo de verdad. Es un detalle tonto y es
    /// justo lo que hace que se lea como un recibo y no como una tarjeta.
    private var linea: some View {
        Rayita()
            .stroke(Color(hex: 0xc0b6a5),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .frame(height: 1)
    }

    private var texto: String {
        var t = "Comprobante de \(encargo.cliente)\n"
        t += "\(encargo.producto) · \(Formato.cantidad(encargo.cantidad)) \(encargo.unidad)"
        t += " × \(Formato.precio(encargo.precioAplicado, moneda: moneda))\n"
        t += "Total: \(Formato.pesos(encargo.total, moneda: moneda))"
        if encargo.cobrado { t += " · \(encargo.metodo) · pagado" }
        t += "\n¡Gracias por su compra!"
        return t
    }

    /// WhatsApp abre con el texto ya escrito; enviar lo hace la persona. Mandar
    /// un mensaje en nombre de alguien sin que lo vea es pasarse.
    private func porWhatsApp() {
        let numero = encargo.telefono.filter { $0.isNumber }
        let cuerpo = texto.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let u = URL(string: "https://wa.me/\(numero)?text=\(cuerpo)") { abre(u) }
    }
}

/// Una raya horizontal. `Rectangle` no se puede puntear: el guion se aplica al
/// contorno, y el contorno de un rectángulo de un punto de alto son cuatro lados.
private struct Rayita: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        return p
    }
}
