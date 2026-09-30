import SwiftUI
import SwiftData

/// 11 · NUEVO ENCARGO.
///
/// Cliente, producto, cuánto y a qué tarifa. Los clientes de siempre salen como
/// pastillas para no escribirlos otra vez, y el producto sale del catálogo con
/// sus tres precios ya puestos: el encargo se anota mientras se habla por
/// teléfono, y ahí no hay tiempo de rellenar un formulario.
struct NuevoEncargoView: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var cerrar
    @Environment(\.sincronizador) private var sincronizador
    @Environment(Sesion.self) private var sesion

    let evento: Evento

    @Query(filter: #Predicate<Cliente> { $0.borrado == nil }, sort: \Cliente.nombre) private var clientes: [Cliente]
    @Query(filter: #Predicate<Producto> { $0.borrado == nil }, sort: \Producto.nombre) private var catalogo: [Producto]

    @State private var cliente = ""
    @State private var telefono = ""
    @State private var producto: Producto?
    @State private var cantidad: Double = 1
    @State private var tarifa: Tarifa = .detal
    @State private var nota = ""
    @FocusState private var enElCliente: Bool

    private var ajustes: Ajustes { Almacen.ajustes(ctx, de: sesion.usuario?.id ?? "") }
    private var precio: Double {
        guard let p = producto else { return 0 }
        switch tarifa {
        case .detal: return p.precioDetal
        case .mayor: return p.precioMayor
        case .especial: return p.precioEspecial
        }
    }
    private var total: Double { cantidad * precio }
    private var unidad: Unidad { Unidad.de(producto?.unidad ?? ajustes.unidadPorDefecto) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Nuevo encargo").font(tema.titulo(32)).foregroundStyle(tema.texto)

                    Campo(marcador: "Nombre del cliente", valor: $cliente, peso: .bold, tamano: 16)
                        .focused($enElCliente)
                        .onChange(of: cliente) { _, nuevo in
                            if let c = clientes.first(where: { $0.nombre == nuevo }) { telefono = c.telefono }
                        }

                    if !clientes.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 6) {
                                ForEach(clientes.prefix(12)) { c in
                                    Button {
                                        cliente = c.nombre
                                        telefono = c.telefono
                                    } label: {
                                        Text(c.nombre)
                                            .font(tema.texto(13, .bold))
                                            .padding(.horizontal, 12).padding(.vertical, 9)
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

                    Campo(marcador: "WhatsApp (opcional)", valor: $telefono, tamano: 15, teclado: .phonePad)

                    Rotulo("Producto").padding(.top, 4)
                    if catalogo.isEmpty {
                        Tarjeta {
                            Text("Todavía no tienes productos con precio.")
                                .font(tema.texto(15, .bold))
                            Text("Ponlos en Ajustes → Catálogo de precios, con su costo y sus tres tarifas. Así cada encargo sale solo.")
                                .font(tema.texto(14)).foregroundStyle(tema.neutral700)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Grupo {
                            ForEach(Array(catalogo.enumerated()), id: \.element.id) { i, p in
                                Button {
                                    producto = p
                                    cantidad = max(cantidad, 1)
                                } label: {
                                    HStack(spacing: 10) {
                                        Radio(elegido: producto?.id == p.id)
                                        Text(p.nombre).font(tema.texto(15, .bold))
                                        Spacer(minLength: 6)
                                        Text("\(Formato.precio(p.precioDetal, moneda: ajustes.moneda))/\(p.unidad)")
                                            .font(tema.texto(14)).foregroundStyle(tema.neutral700)
                                    }
                                    .frame(minHeight: 54)
                                    .overlay(alignment: .bottom) {
                                        if i < catalogo.count - 1 {
                                            Rectangle().fill(tema.divisor).frame(height: 1)
                                        }
                                    }
                                    .foregroundStyle(tema.texto)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        HStack(spacing: 0) {
                            Button { cantidad = max(0, ((cantidad - unidad.paso) * 100).rounded() / 100) } label: {
                                Text("−").font(tema.texto(20, .bold)).frame(width: 38, height: 38)
                            }
                            Text("\(Formato.cantidad(cantidad)) \(unidad.id)")
                                .font(tema.texto(14, .heavy)).frame(minWidth: 64)
                            Button { cantidad = ((cantidad + unidad.paso) * 100).rounded() / 100 } label: {
                                Text("+").font(tema.texto(20, .bold)).frame(width: 38, height: 38)
                            }
                        }
                        .foregroundStyle(tema.texto)
                        .padding(3)
                        .background(tema.superficie, in: Capsule())

                        Spacer(minLength: 0)

                        HStack(spacing: 2) {
                            ForEach(Tarifa.allCases, id: \.self) { t in
                                Button { tarifa = t } label: {
                                    Text(ajustes.nombreTarifa(t))
                                        .font(tema.texto(12, .heavy))
                                        .lineLimit(1)
                                        .fixedSize()
                                        .padding(.horizontal, 10)
                                        .frame(height: 38)
                                        .background(tarifa == t ? tema.neutral900 : .clear, in: Capsule())
                                        .foregroundStyle(tarifa == t
                                                         ? (tema.oscuro ? tema.texto : tema.neutral100)
                                                         : tema.neutral700)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(3)
                        .background(tema.superficie, in: Capsule())
                    }

                    Campo(marcador: "Nota (escamado, hora de retiro…)", valor: $nota, tamano: 15)

                    HStack {
                        Text("Le cobras").font(tema.texto(15, .bold))
                        Spacer()
                        Text(Formato.pesos(total, moneda: ajustes.moneda)).font(tema.titulo(28))
                    }
                    .foregroundStyle(tema.acento2_800)
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(tema.acento2_200, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                    Button("Guardar encargo") { guarda() }
                        .buttonStyle(BotonPrincipal())
                        .disabled(cliente.trimmingCharacters(in: .whitespaces).isEmpty || producto == nil)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .fondoDelTema(tema)
            .navigationTitle(evento.titulo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { cerrar() }.foregroundStyle(tema.acento700)
                }
            }
        }
        .onAppear {
            producto = catalogo.first
        }
    }

    private func guarda() {
        guard let p = producto else { return }
        let nombre = cliente.trimmingCharacters(in: .whitespaces)
        let o = Encargo(eventoId: evento.id, cliente: nombre, producto: p.nombre,
                        unidad: p.unidad, pedido: cantidad,
                        precioDetal: p.precioDetal, precioMayor: p.precioMayor,
                        precioEspecial: p.precioEspecial, costo: p.costo)
        o.tarifa = tarifa.rawValue
        o.nota = nota.trimmingCharacters(in: .whitespaces)
        o.telefono = telefono.trimmingCharacters(in: .whitespaces)
        ctx.insert(o)

        // El cliente se queda guardado para la próxima vez sin que nadie lo
        // meta en una agenda aparte.
        if let ya = clientes.first(where: { $0.nombre == nombre }) {
            if ya.telefono != o.telefono, !o.telefono.isEmpty { ya.telefono = o.telefono; ya.toco() }
        } else {
            ctx.insert(Cliente(nombre: nombre, telefono: o.telefono))
        }
        evento.toco()
        try? ctx.save()
        Task { await sincronizador?.sincroniza() }
        cerrar()
    }
}
