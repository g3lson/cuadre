import SwiftUI

/// ANTES DE DAR ALGO POR COBRADO.
///
/// Marcar a alguien como que pagó cuando no ha pagado cuesta dinero de verdad,
/// y el error se descubre cuando el cliente ya se fue. Por eso esto no es una
/// alerta del sistema con dos botones del mismo tamaño: enseña **lo que hay que
/// mirar antes de decir que sí** —quién, cuánto y cómo— en grande, y el «sí»
/// vive lejos del pulgar que venía tocando la lista.
///
/// Aquí también se elige **quién lo cobra**, porque en el mostrador uno marca
/// por el compañero que tiene las manos llenas, y después ese cobro tiene que
/// aparecer a nombre de él y no del que tocó el botón.
///
/// Se puede apagar entera en Ajustes: quien despacha cincuenta encargos al día
/// no quiere confirmar cincuenta veces.
struct ConfirmarCobroView: View {
    @Environment(\.tema) private var tema
    @Environment(\.dismiss) private var cerrar

    let encargo: Encargo
    let metodo: String
    let moneda: String
    /// Los nombres entre los que se puede repartir el cobro.
    var gente: [String] = []
    @State var aNombreDe: String
    /// Recibe a nombre de quién quedó. Vacío = no tocar lo que ya tenía.
    var alConfirmar: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    Text(encargo.salida.cobra ? "¿Ya te pagó?" : "¿Anotar la salida?")
                        .font(tema.titulo(30))
                        .foregroundStyle(tema.texto)
                        .padding(.top, 4)

                    Text(encargo.salida.cobra
                         ? Formato.pesos(encargo.total, moneda: moneda)
                         : encargo.salida.etiqueta)
                        .font(tema.titulo(encargo.salida.cobra ? 52 : 34))
                        .foregroundStyle(encargo.salida.cobra ? tema.acento2_700 : tema.acento700)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)

                    HStack(spacing: 12) {
                        Text(Formato.inicial(encargo.cliente))
                            .font(tema.texto(17, .heavy))
                            .foregroundStyle(tema.acento2_800)
                            .frame(width: 44, height: 44)
                            .background(tema.acento2_200, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(encargo.cliente).font(tema.texto(17, .heavy))
                            Text("\(encargo.producto) · \(Formato.cantidad(encargo.cantidad)) \(encargo.unidad)"
                                 + (encargo.precioAplicado > 0
                                    ? " × \(Formato.precio(encargo.precioAplicado, moneda: moneda))" : ""))
                                .font(tema.texto(13))
                                .foregroundStyle(tema.neutral700)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(tema.superficie, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                    if encargo.salida.cobra {
                        HStack(spacing: 8) {
                            IconoView(icono: metodo == "Transferencia" ? .enlace : .circuloCheck,
                                      tamano: 18, grosor: 2.6)
                            Text("Paga en \(metodo.lowercased())").font(tema.texto(15, .bold))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(tema.acento2_800)
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(tema.acento2_200, in: Capsule())
                    }

                    // A nombre de quién queda. Solo aparece si hay con quién
                    // repartirlo: solo, el menú sobra.
                    if gente.count > 1 {
                        Menu {
                            ForEach(gente, id: \.self) { quien in
                                Button {
                                    aNombreDe = quien
                                } label: {
                                    if quien == aNombreDe {
                                        Label(quien, systemImage: "checkmark")
                                    } else {
                                        Text(quien)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Text("Lo cobra").font(tema.texto(15))
                                    .foregroundStyle(tema.neutral700)
                                Spacer(minLength: 0)
                                Text(aNombreDe.isEmpty ? "Yo" : aNombreDe)
                                    .font(tema.texto(15, .bold))
                                    .foregroundStyle(tema.texto)
                                IconoView(icono: .chevron, tamano: 14, grosor: 2.4)
                                    .foregroundStyle(tema.neutral500)
                                    .rotationEffect(.degrees(90))
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .background(tema.superficie, in: Capsule())
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 10) {
                Button(encargo.salida.cobra ? "Sí, ya pagó" : "Sí, anótalo") {
                    alConfirmar(aNombreDe)
                    cerrar()
                }
                .buttonStyle(BotonPrincipal(alto: 56))

                Button("Todavía no") { cerrar() }
                    .buttonStyle(BotonFantasma())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .fondoDelTema(tema)
        .presentationDetents([.height(gente.count > 1 ? 500 : 430)])
        .presentationDragIndicator(.visible)
    }
}
