import SwiftUI
import SwiftData

/// LO QUE HAS PAGADO POR ESTO.
///
/// Ninguna cadena de aquí publica sus ofertas de manera que una app pueda
/// leerlas, y raspar sus páginas se rompe cada vez que las cambian. Pero el
/// precio que de verdad importa —el tuyo— ya lo llevas apuntado desde hace
/// meses en cada compra que cerraste.
///
/// Esto lo enseña junto: cada vez que lo compraste, a cuánto y dónde. De un
/// vistazo se ve si hoy te están cobrando de más y en qué tienda sale mejor,
/// que es lo que una oferta de la semana intenta decirte y casi nunca acierta.
struct HistorialDePreciosView: View {
    @Environment(\.tema) private var tema
    @Environment(\.dismiss) private var cerrar

    let nombre: String
    let moneda: String
    let compras: [Almacen.Compra]

    private var precios: [Double] { compras.map(\.precio) }
    private var barato: Double { precios.min() ?? 0 }
    private var caro: Double { precios.max() ?? 0 }
    private var promedio: Double {
        precios.isEmpty ? 0 : precios.reduce(0, +) / Double(precios.count)
    }
    /// Dónde ha salido más barato. Solo si hay más de una tienda con nombre:
    /// decir «más barato en Bravo» cuando solo compras en Bravo no dice nada.
    private var mejorTienda: (String, Double)? {
        var porTienda: [String: [Double]] = [:]
        for c in compras where !c.tienda.isEmpty { porTienda[c.tienda, default: []].append(c.precio) }
        guard porTienda.count > 1 else { return nil }
        let medias = porTienda.map { ($0.key, $0.value.reduce(0, +) / Double($0.value.count)) }
        return medias.min { $0.1 < $1.1 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if compras.count < 2 {
                        conPoco
                    } else {
                        resumen
                        grafico
                        if let (tienda, precio) = mejorTienda {
                            HStack(spacing: 8) {
                                IconoView(icono: .bolsa, tamano: 18, grosor: 2.4)
                                Text("Más barato en **\(tienda)**, a \(Formato.precio(precio, moneda: moneda)) de media")
                                    .font(tema.texto(14))
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(tema.acento2_800)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(tema.acento2_200,
                                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                    }

                    Rotulo("Cada vez que lo compraste")
                    Bloque {
                        ForEach(Array(compras.enumerated()), id: \.element.id) { i, c in
                            FilaAjuste(titulo: Formato.diaCorto(c.fecha),
                                       detalle: [c.tienda.isEmpty ? nil : c.tienda,
                                                 "\(Formato.cantidad(c.cantidad)) \(c.unidad)"]
                                        .compactMap { $0 }.joined(separator: " · "),
                                       ultima: i == compras.count - 1) {
                                Text(Formato.precio(c.precio, moneda: moneda))
                                    .font(tema.texto(16, .bold))
                                    .foregroundStyle(tinta(c.precio))
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .fondoDelTema(tema)
            .navigationTitle(nombre)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { cerrar() }.font(tema.texto(16, .bold))
                }
            }
        }
    }

    /// Verde el más barato que has pagado, naranja el más caro. Con dos precios
    /// iguales no se pinta nada: señalar todo es no señalar nada.
    private func tinta(_ p: Double) -> Color {
        guard caro > barato else { return tema.texto }
        if p == barato { return tema.acento2_700 }
        if p == caro { return tema.acento700 }
        return tema.texto
    }

    private var resumen: some View {
        HStack(spacing: 0) {
            cifra("Más barato", Formato.precio(barato, moneda: moneda), tema.acento2_700)
            Rectangle().fill(tema.divisor).frame(width: 1, height: 30)
            cifra("De media", Formato.precio(promedio, moneda: moneda), tema.texto)
            Rectangle().fill(tema.divisor).frame(width: 1, height: 30)
            cifra("Más caro", Formato.precio(caro, moneda: moneda), tema.acento700)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(tema.superficie, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func cifra(_ rotulo: String, _ valor: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(rotulo).font(tema.texto(11, .bold)).foregroundStyle(tema.neutral700)
            Text(valor).font(tema.titulo(19)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    /// Las barras van de lo más viejo a lo más nuevo, al revés que la lista:
    /// un precio se lee de izquierda a derecha como pasa el tiempo.
    private var grafico: some View {
        let enOrden = compras.reversed().suffix(14)
        let techo = caro > 0 ? caro : 1
        let suelo = barato * 0.8
        return VStack(alignment: .leading, spacing: 8) {
            Text("Cómo ha ido").font(tema.texto(13, .bold)).foregroundStyle(tema.neutral700)
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(enOrden.enumerated()), id: \.element.id) { _, c in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(c.precio == barato ? tema.acento2_700
                                  : (c.precio == caro ? tema.acento700 : tema.neutral500.opacity(0.5)))
                            .frame(height: max(4, 76 * ((c.precio - suelo) / max(techo - suelo, 1))))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tema.superficie, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var conPoco: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Todavía no hay con qué comparar").font(tema.texto(16, .bold))
            Text("En cuanto cierres otra compra con este producto, aquí verás si subió o bajó, y en qué tienda sale mejor.")
                .font(tema.texto(14)).foregroundStyle(tema.neutral700)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tema.superficie, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
