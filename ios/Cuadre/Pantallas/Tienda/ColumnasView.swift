import SwiftUI

/// ¿QUÉ VER EN LA LISTA?
///
/// Cuatro interruptores. Se guarda en los ajustes de la cuenta y no por lista:
/// quien quiere ver precios los quiere ver siempre.
struct ColumnasView: View {
    @Environment(\.tema) private var tema
    @Environment(\.dismiss) private var cerrar
    @Bindable var ajustes: Ajustes

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("¿Qué ver en la lista?").font(tema.titulo(26)).foregroundStyle(tema.texto)
            Text("Elige las columnas al lado de cada producto.")
                .font(tema.texto(14))
                .foregroundStyle(tema.neutral700)
                .padding(.bottom, 8)

            fila("Cantidad", "2 gal · 1.5 lb", $ajustes.verCantidad)
            fila("Precio", "Por libra, unidad, galón…", $ajustes.verPrecio)
            fila("Total", "Cantidad × precio", $ajustes.verTotal)
            fila("Nota", "Marca, tamaño, detalles", $ajustes.verNota, ultima: true)

            Button("Listo") { cerrar() }
                .buttonStyle(BotonPrincipal(alto: 52))
                .padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.height(430)])
    }

    private func fila(_ titulo: String, _ ejemplo: String, _ valor: Binding<Bool>, ultima: Bool = false) -> some View {
        FilaAjuste(titulo: titulo, detalle: ejemplo, ultima: ultima) {
            Interruptor(encendido: valor)
        }
        .onChange(of: valor.wrappedValue) { _, _ in ajustes.toco() }
    }
}
