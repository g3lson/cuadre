import SwiftUI
import SwiftData

/// EL CATÁLOGO DE PRECIOS.
///
/// Lo que vendes, con lo que te cuesta y tus tres tarifas. Es lo que hace que
/// un encargo se anote en cuatro toques y que el cuadre sepa la ganancia: sin
/// el costo, la app puede decirte cuánto cobraste pero no cuánto ganaste.
struct CatalogoView: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(Sesion.self) private var sesion

    @Query(filter: #Predicate<Producto> { $0.borrado == nil }, sort: \Producto.nombre)
    private var productos: [Producto]

    @State private var editando: Producto?

    private var ajustes: Ajustes { Almacen.ajustes(ctx, de: sesion.usuario?.id ?? "") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if productos.isEmpty {
                    Tarjeta {
                        Text("Todavía no hay productos").font(tema.texto(16, .bold))
                        Text("Pon lo que vendes con su costo y sus tres precios. Después, cada encargo es elegirlo y poner la cantidad.")
                            .font(tema.texto(14)).foregroundStyle(tema.neutral700)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                ForEach(productos) { p in
                    Button { editando = p } label: {
                        Tarjeta {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.nombre).font(tema.texto(16, .heavy))
                                    Text("\(p.categoria) · por \(Unidad.de(p.unidad).nombre)")
                                        .font(tema.texto(13)).foregroundStyle(tema.neutral700)
                                }
                                Spacer(minLength: 6)
                                if p.costo > 0 {
                                    Text("cuesta \(Formato.precio(p.costo, moneda: ajustes.moneda))")
                                        .font(tema.texto(12)).foregroundStyle(tema.neutral700)
                                }
                            }
                            HStack(spacing: 6) {
                                precio(ajustes.nombreDetal, p.precioDetal)
                                precio(ajustes.nombreMayor, p.precioMayor)
                                precio(ajustes.nombreEspecial, p.precioEspecial)
                            }
                        }
                        .foregroundStyle(tema.texto)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { p.entierro(); try? ctx.save() } label: {
                            Label("Quitar del catálogo", systemImage: "trash")
                        }
                    }
                }

                Button {
                    let p = Producto(nombre: "", unidad: ajustes.unidadPorDefecto)
                    ctx.insert(p)
                    editando = p
                } label: {
                    HStack(spacing: 8) {
                        IconoView(icono: .mas, tamano: 18)
                        Text("Agregar producto")
                    }
                }
                .buttonStyle(BotonSuave())
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .fondoDelTema(tema)
        .navigationTitle("Catálogo")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editando) { p in
            FichaProductoView(producto: p, moneda: ajustes.moneda, ajustes: ajustes).hojaDeCuadre(tema)
        }
    }

    private func precio(_ rotulo: String, _ valor: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(rotulo.uppercased()).font(tema.texto(10, .heavy)).tracking(0.6)
                .foregroundStyle(tema.neutral700)
            Text(valor > 0 ? Formato.precio(valor, moneda: ajustes.moneda) : "—")
                .font(tema.texto(14, .heavy))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tema.fondo, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Un producto del catálogo.
struct FichaProductoView: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var cerrar

    @Bindable var producto: Producto
    let moneda: String
    let ajustes: Ajustes

    @State private var costo = ""
    @State private var detal = ""
    @State private var mayor = ""
    @State private var especial = ""
    @FocusState private var enElNombre: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("¿Qué vendes?", text: $producto.nombre)
                        .font(tema.titulo(28))
                        .foregroundStyle(tema.texto)
                        .focused($enElNombre)
                        .onChange(of: producto.nombre) { _, _ in producto.toco() }

                    Grupo {
                        FilaAjuste(titulo: "Se vende por") {
                            Menu {
                                ForEach(Unidad.todas) { u in
                                    Button(u.etiqueta) { producto.unidad = u.id; producto.toco() }
                                }
                            } label: {
                                ValorYChevron(texto: Unidad.de(producto.unidad).etiqueta)
                            }
                        }
                        FilaAjuste(titulo: "Categoría", ultima: true) {
                            Menu {
                                ForEach(Categoria.todas, id: \.self) { c in
                                    Button(c) { producto.categoria = c; producto.toco() }
                                }
                            } label: {
                                ValorYChevron(texto: producto.categoria)
                            }
                        }
                    }

                    Rotulo("Lo que te cuesta a ti")
                    campoPrecio("Costo por \(Unidad.de(producto.unidad).nombre)", $costo) {
                        producto.costo = num(costo); producto.toco()
                    }
                    Text("Sin esto el cuadre puede decirte cuánto cobraste, pero no cuánto ganaste.")
                        .font(tema.texto(13)).foregroundStyle(tema.neutral700)
                        .fixedSize(horizontal: false, vertical: true)

                    Rotulo("Lo que cobras").padding(.top, 4)
                    VStack(spacing: 8) {
                        campoPrecio(ajustes.nombreDetal, $detal) { producto.precioDetal = num(detal); producto.toco() }
                        campoPrecio(ajustes.nombreMayor, $mayor) { producto.precioMayor = num(mayor); producto.toco() }
                        campoPrecio(ajustes.nombreEspecial, $especial) { producto.precioEspecial = num(especial); producto.toco() }
                    }

                    if producto.costo > 0, producto.precioDetal > 0 {
                        let margen = (producto.precioDetal - producto.costo) / producto.precioDetal
                        Text("A \(ajustes.nombreDetal.lowercased()) ganas \(Formato.precio(producto.precioDetal - producto.costo, moneda: moneda)) por \(Unidad.de(producto.unidad).nombre) · \(Int((margen * 100).rounded()))% de margen")
                            .font(tema.texto(14, .bold))
                            .foregroundStyle(tema.acento2_800)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(tema.acento2_200, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    Button("Quitar del catálogo", role: .destructive) {
                        producto.entierro()
                        try? ctx.save()
                        cerrar()
                    }
                    .buttonStyle(BotonSuave())
                    .padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .fondoDelTema(tema)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { guarda() }.font(tema.texto(16, .bold))
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Listo") { enElNombre = false } }
            }
        }
        .onAppear {
            costo = producto.costo > 0 ? Formato.cantidad(producto.costo) : ""
            detal = producto.precioDetal > 0 ? Formato.cantidad(producto.precioDetal) : ""
            mayor = producto.precioMayor > 0 ? Formato.cantidad(producto.precioMayor) : ""
            especial = producto.precioEspecial > 0 ? Formato.cantidad(producto.precioEspecial) : ""
            if producto.nombre.isEmpty { enElNombre = true }
        }
    }

    private func campoPrecio(_ rotulo: String, _ valor: Binding<String>, alCambiar: @escaping () -> Void) -> some View {
        HStack {
            Text(rotulo).font(tema.texto(15, .bold))
            Spacer()
            HStack(spacing: 4) {
                Text(moneda).font(tema.texto(14, .bold)).foregroundStyle(tema.neutral700)
                TextField("0", text: valor)
                    .font(tema.texto(17, .heavy))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 92)
                    .onChange(of: valor.wrappedValue) { _, _ in alCambiar() }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(tema.fondo, in: Capsule())
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(tema.superficie, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func num(_ t: String) -> Double { Double(t.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    private func guarda() {
        if producto.nombre.trimmingCharacters(in: .whitespaces).isEmpty { producto.entierro() }
        try? ctx.save()
        cerrar()
    }
}

/// Cómo se llaman tus tres tarifas.
struct TarifasView: View {
    @Environment(\.tema) private var tema
    @Bindable var ajustes: Ajustes

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Tus tres precios pueden llamarse como tú los llames: «Detal, Mayor, Especial», o «Vecino, Colmado, Mi gente».")
                    .font(tema.texto(15)).foregroundStyle(tema.neutral700)
                    .fixedSize(horizontal: false, vertical: true)

                Grupo {
                    fila("Tarifa 1", $ajustes.nombreDetal)
                    fila("Tarifa 2", $ajustes.nombreMayor)
                    fila("Tarifa 3", $ajustes.nombreEspecial, ultima: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .fondoDelTema(tema)
        .navigationTitle("Tarifas")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func fila(_ rotulo: String, _ valor: Binding<String>, ultima: Bool = false) -> some View {
        FilaAjuste(titulo: rotulo, ultima: ultima) {
            TextField(rotulo, text: valor)
                .font(tema.texto(15, .bold))
                .multilineTextAlignment(.trailing)
                .frame(width: 150)
                .onChange(of: valor.wrappedValue) { _, _ in ajustes.toco() }
        }
    }
}
