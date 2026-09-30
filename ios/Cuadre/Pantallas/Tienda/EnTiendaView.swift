import SwiftUI
import SwiftData
import UIKit

/// 03 · EN TIENDA.
///
/// La pantalla que se usa de pie, con una mano y el carrito en la otra. Por eso
/// es una lista de verdad —una fila por producto, con cantidad, precio y total
/// al lado— y no tarjetas: de un vistazo se ve qué falta y cuánto llevas.
///
/// Las columnas se eligen: quien solo quiere ir marcando las apaga todas y ve
/// nombres; quien está cuadrando al céntimo las enciende.
struct EnTiendaView: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(\.sincronizador) private var sincronizador
    @Environment(Sesion.self) private var sesion

    @Binding var listaId: String?
    @Binding var pestana: Pestana

    @Query(filter: #Predicate<Lista> { $0.borrado == nil },
           sort: [SortDescriptor<Lista>(\.orden), SortDescriptor<Lista>(\.fecha, order: .reverse)])
    private var listas: [Lista]
    @Query(filter: #Predicate<Articulo> { $0.borrado == nil },
           sort: [SortDescriptor<Articulo>(\.orden), SortDescriptor<Articulo>(\.nombre)])
    private var todos: [Articulo]

    @State private var abierto: Articulo?
    @State private var columnasAbiertas = false
    @State private var cerrando = false
    @State private var asistente = false

    private var lista: Lista? {
        if let id = listaId, let l = listas.first(where: { $0.id == id }) { return l }
        return listas.first { !$0.cerrada }
    }
    private var articulos: [Articulo] { todos.filter { $0.listaId == lista?.id } }
    private var faltan: [Articulo] { articulos.filter { !$0.hecho } }
    private var enCarrito: [Articulo] { articulos.filter(\.hecho) }
    private var gastado: Double { enCarrito.reduce(0) { $0 + $1.total } }
    private var ajustes: Ajustes { Almacen.ajustes(ctx, de: sesion.usuario?.id ?? "") }

    var body: some View {
        NavigationStack {
            Group {
                if let lista {
                    contenido(lista)
                } else {
                    sinLista
                }
            }
            .fondoDelTema(tema)
        }
        .sheet(item: $abierto) { a in
            FichaArticuloView(articulo: a, moneda: ajustes.moneda) {
                try? ctx.save()
                Task { await sincronizador?.sincroniza() }
            }
            .hojaDeCuadre(tema)
        }
        .sheet(isPresented: $columnasAbiertas) {
            ColumnasView(ajustes: ajustes).hojaDeCuadre(tema)
        }
        .sheet(isPresented: $asistente) {
            if let lista {
                AsistenteView(lista: lista).hojaDeCuadre(tema)
            }
        }
        .fullScreenCover(isPresented: $cerrando) {
            if let lista {
                CerrarCompraView(lista: lista) {
                    listaId = nil
                    pestana = .listas
                }
            }
        }
    }

    // MARK: - Contenido

    @ViewBuilder
    private func contenido(_ l: Lista) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                barraSuperior(l)
                titulo(l)

                if l.cerrada {
                    bannerCerrada(l)
                } else {
                    tarjetaCarrito(l)
                }

                cabeceraTabla(rotulo: l.cerrada ? "Comprado" : "Por comprar")

                ForEach(l.cerrada ? enCarrito : faltan) { a in
                    fila(a, tachado: l.cerrada)
                }

                if !l.cerrada {
                    Button { agrega(a: l) } label: {
                        HStack(spacing: 12) {
                            IconoView(icono: .mas, tamano: 20)
                            Text("Agregar producto").font(tema.texto(15, .bold))
                            Spacer()
                        }
                        .foregroundStyle(tema.acento700)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                    }
                    .buttonStyle(.plain)

                    if !enCarrito.isEmpty {
                        Rotulo("En el carrito · \(enCarrito.count)")
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 6)
                        ForEach(enCarrito) { a in fila(a, tachado: true) }
                    }

                    Button("Listo, cerrar compra · \(Formato.pesos(gastado, moneda: ajustes.moneda))") {
                        cerrando = true
                    }
                    .buttonStyle(BotonPrincipal())
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .disabled(enCarrito.isEmpty)
                }
            }
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .refreshable { await sincronizador?.sincroniza() }
    }

    private func barraSuperior(_ l: Lista) -> some View {
        HStack {
            Button { pestana = .listas } label: {
                HStack(spacing: 4) {
                    IconoView(icono: .atras, tamano: 20)
                    Text("Listas").font(tema.texto(15, .bold))
                }
                .foregroundStyle(tema.acento700)
                .frame(minHeight: 44)
            }
            Spacer()
            if !l.cerrada {
                HStack(spacing: 8) {
                    if sesion.hayIA {
                        Button { asistente = true } label: { IconoView(icono: .chispa, tamano: 20) }
                            .buttonStyle(BotonRedondo())
                            .accessibilityLabel("Dictar o leer un recibo")
                    }
                    Button { columnasAbiertas = true } label: { IconoView(icono: .columnas, tamano: 20) }
                        .buttonStyle(BotonRedondo())
                        .accessibilityLabel("Columnas")
                    Button { agrega(a: l) } label: { IconoView(icono: .mas, tamano: 20) }
                        .buttonStyle(BotonRedondo(relleno: tema.acento, tinta: tema.sobreAcento))
                        .accessibilityLabel("Agregar producto")
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func titulo(_ l: Lista) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(l.nombre).font(tema.titulo(30)).foregroundStyle(tema.texto)
            Text([l.tienda, "\(articulos.count) producto\(articulos.count == 1 ? "" : "s")"]
                .filter { !$0.isEmpty }.joined(separator: " · "))
                .font(tema.texto(14))
                .foregroundStyle(tema.neutral700)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    private func tarjetaCarrito(_ l: Lista) -> some View {
        let queda = l.presupuesto - gastado
        let pct = l.presupuesto > 0 ? gastado / l.presupuesto : 0

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("En el carrito").font(tema.texto(13, .bold)).foregroundStyle(tema.neutral500)
                Spacer()
                if l.presupuesto > 0 {
                    Text(queda < 0 ? "Te pasaste \(Formato.pesos(-queda, moneda: ajustes.moneda))"
                                   : "Te quedan \(Formato.pesos(queda, moneda: ajustes.moneda))")
                        .font(tema.texto(13, .bold))
                        .foregroundStyle(queda < 0 ? tema.acento300 : tema.acento2_300)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Formato.pesos(gastado, moneda: ajustes.moneda))
                    .font(tema.titulo(34))
                    .foregroundStyle(tema.sobreOscuro)
                if l.presupuesto > 0 {
                    Text("de \(Formato.pesos(l.presupuesto, moneda: ajustes.moneda))")
                        .font(tema.texto(13))
                        .foregroundStyle(tema.neutral500)
                }
            }
            if l.presupuesto > 0 {
                Barra(porcentaje: pct,
                      color: queda < 0 ? tema.acento : (pct > 0.8 ? tema.acento300 : tema.acento2_400),
                      pista: tema.neutral700.opacity(0.35), alto: 8)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tema.neutral900, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private func bannerCerrada(_ l: Lista) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(tema.acento2_700)
                IconoView(icono: .check, tamano: 18, grosor: 3).foregroundStyle(tema.fondo)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Compra cerrada · \(Formato.pesos(gastado, moneda: ajustes.moneda))")
                    .font(tema.texto(15, .bold))
                if !l.notaCierre.isEmpty {
                    Text(l.notaCierre).font(tema.texto(13)).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(tema.acento2_800)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tema.acento2_200, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    // MARK: - La tabla

    /// Los anchos son fijos y no proporcionales: así los números de todas las
    /// filas quedan en la misma vertical y la columna se lee de un vistazo.
    private var anchos: (cantidad: CGFloat, precio: CGFloat, total: CGFloat) { (52, 50, 58) }

    private func cabeceraTabla(rotulo: String) -> some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: 30)
            Text(rotulo.uppercased()).frame(maxWidth: .infinity, alignment: .leading)
            if ajustes.verCantidad { Text("CANT.").frame(width: anchos.cantidad, alignment: .trailing) }
            if ajustes.verPrecio { Text("PRECIO").frame(width: anchos.precio, alignment: .trailing) }
            if ajustes.verTotal { Text("TOTAL").frame(width: anchos.total, alignment: .trailing) }
        }
        .font(tema.texto(11, .heavy))
        .tracking(0.8)
        .foregroundStyle(tema.neutral700)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private func fila(_ a: Articulo, tachado: Bool) -> some View {
        Button { abierto = a } label: {
            HStack(spacing: 6) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    a.hecho.toggle()
                    a.toco()
                    try? ctx.save()
                } label: {
                    Marcador(puesto: a.hecho)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: 30, alignment: .leading)
                .accessibilityLabel(a.hecho ? "Sacar del carrito" : "Poner en el carrito")

                VStack(alignment: .leading, spacing: 1) {
                    Text(a.nombre.isEmpty ? "Producto nuevo" : a.nombre)
                        .font(tema.texto(15, a.hecho ? .regular : .semibold))
                        .strikethrough(a.hecho)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if ajustes.verNota, !a.nota.isEmpty {
                        Text(a.nota).font(tema.texto(12)).foregroundStyle(tema.neutral700).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)

                if ajustes.verCantidad {
                    Text("\(Formato.cantidad(a.cantidad)) \(a.unidad)")
                        .font(tema.texto(14, .semibold))
                        .foregroundStyle(a.hecho ? tema.neutral700 : tema.neutral700)
                        .frame(width: anchos.cantidad, alignment: .trailing)
                }
                if ajustes.verPrecio {
                    Text(a.precio > 0 ? Formato.entero(a.precio) : "—")
                        .font(tema.texto(14))
                        .foregroundStyle(tema.neutral700)
                        .frame(width: anchos.precio, alignment: .trailing)
                }
                if ajustes.verTotal {
                    Text(a.precio > 0 ? Formato.entero(a.total) : "—")
                        .font(tema.texto(15, a.hecho ? .bold : .heavy))
                        .frame(width: anchos.total, alignment: .trailing)
                }
            }
            .foregroundStyle(a.hecho ? tema.neutral700 : tema.texto)
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(tema.divisor).frame(height: 1).padding(.leading, 16)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                a.entierro()
                try? ctx.save()
            } label: { Label("Quitar", systemImage: "trash") }
        }
    }

    private var sinLista: some View {
        VStack(spacing: 14) {
            IconoView(icono: .bolsa, tamano: 44, grosor: 2)
                .foregroundStyle(tema.neutral500)
            Text("No hay ninguna compra abierta").font(tema.titulo(24)).foregroundStyle(tema.texto)
            Text("Crea una lista en la pestaña Listas y vuelve aquí cuando estés en la tienda.")
                .font(tema.texto(15))
                .foregroundStyle(tema.neutral700)
                .multilineTextAlignment(.center)
            Button("Ir a mis listas") { pestana = .listas }
                .buttonStyle(BotonSuave())
                .frame(maxWidth: 260)
        }
        .padding(30)
    }

    private func agrega(a l: Lista) {
        let nuevo = Articulo(listaId: l.id, unidad: ajustes.unidadPorDefecto,
                             orden: (articulos.map(\.orden).max() ?? 0) + 1)
        ctx.insert(nuevo)
        l.toco()
        abierto = nuevo
    }
}
