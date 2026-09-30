import SwiftUI

/// CUANDO NO HAY NADA.
///
/// Una pantalla vacía es la primera que ve alguien, y es la única que puede
/// explicar para qué sirve la que va a ver después. Por eso no dice «sin datos»:
/// dice qué es esto y qué hacer ahora.
///
/// Está en un solo sitio porque antes cada pantalla se lo inventaba, y se
/// notaba: una centrada, otra pegada arriba, y ninguna llenando el fondo.
struct PantallaVacia<Accion: View>: View {
    @Environment(\.tema) private var tema

    let icono: Icono
    let titulo: String
    let texto: String
    @ViewBuilder var accion: Accion

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 16) {
                ZStack {
                    Circle().fill(tema.superficie)
                    IconoView(icono: icono, tamano: 40, grosor: 2.2)
                        .foregroundStyle(tema.neutral500)
                }
                .frame(width: 92, height: 92)

                VStack(spacing: 8) {
                    Text(titulo)
                        .font(tema.titulo(26))
                        .foregroundStyle(tema.texto)
                        .multilineTextAlignment(.center)
                    Text(texto)
                        .font(tema.texto(15))
                        .foregroundStyle(tema.neutral700)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                accion
                    .frame(maxWidth: 300)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 0)
            // El aire de abajo es el de la barra de pestañas: sin él, el texto
            // queda centrado respecto a la pantalla pero torcido respecto a lo
            // que se ve.
            Color.clear.frame(height: 90)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fondoDelTema(tema)
    }
}
