import SwiftUI
import SwiftData

/// 07 · PASAR EL GASTO A CHINOLA.
///
/// La compra ya cerrada se anota como movimiento en la libreta de Chinola. Se
/// elige libreta, de dónde salió el dinero y en qué categoría entra; y si la
/// compra fue de cosas muy distintas, se parte por categorías y entran varios
/// movimientos en vez de uno gordo llamado «Supermercado».
///
/// El identificador de la lista viaja como idempotencia: tocar «Enviar» dos
/// veces no anota el gasto dos veces, y eso importa porque el botón está en una
/// pantalla que se abre una y otra vez.
struct ChinolaEnvio: View {
    @Environment(\.tema) private var tema
    @Environment(\.modelContext) private var ctx
    @Environment(\.openURL) private var abre
    @Environment(Sesion.self) private var sesion

    let lista: Lista
    let pagado: Double
    let porCategoria: [(String, Double)]
    var alVolver: () -> Void

    @State private var libretas: [ChinolaApi.Libreta] = []
    @State private var cargando = false
    @State private var libreta: ChinolaApi.Libreta?
    @State private var medio: ChinolaApi.Libreta.Medio?
    @State private var categoria = ""
    @State private var partir = false
    @State private var enviando = false
    @State private var error: String?
    @State private var hecho = false

    private var ajustes: Ajustes { Almacen.ajustes(ctx, de: sesion.usuario?.id ?? "") }
    private var conectada: Bool { sesion.chinola != nil }

    var body: some View {
        Group {
            if hecho || !lista.chinolaNota.isEmpty {
                yaEsta
            } else if !conectada {
                sinConectar
            } else {
                formulario
            }
        }
        .task { await carga() }
    }

    // MARK: - Sin conectar

    @ViewBuilder
    private var sinConectar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Conecta Chinola").font(tema.titulo(32)).foregroundStyle(tema.texto)
            Text("Chinola es donde llevas tus finanzas. Conéctala una vez y cada compra que cierres se anota sola en la libreta que tú digas.")
                .font(tema.texto(15)).foregroundStyle(tema.neutral700)
                .fixedSize(horizontal: false, vertical: true)
        }

        Tarjeta(fondo: tema.acento2_200) {
            fila("Entras con tu cuenta de Chinola, no con esta.")
            fila("Tú eliges qué le dejas tocar antes de confirmar.")
            fila("Se desconecta desde Ajustes, o desde la propia Chinola.")
        }
        .foregroundStyle(tema.acento2_800)

        Button { Task { await conecta() } } label: {
            if enviando { ProgressView().tint(tema.sobreAcento) } else { Text("Conectar Chinola") }
        }
        .buttonStyle(BotonPrincipal())
        .disabled(enviando)

        if let error { mensajeError(error) }
    }

    private func fila(_ texto: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            IconoView(icono: .check, tamano: 16, grosor: 3.2).padding(.top, 2)
            Text(texto).font(tema.texto(14, .medium)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - El formulario

    @ViewBuilder
    private var formulario: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pasar a Chinola").font(tema.titulo(32)).foregroundStyle(tema.texto)
            Text("Se anota como un gasto de \(Formato.pesos(pagado, moneda: ajustes.moneda)).")
                .font(tema.texto(15)).foregroundStyle(tema.neutral700)
        }

        if cargando && libretas.isEmpty {
            HStack(spacing: 10) {
                ProgressView()
                Text("Buscando tus libretas…").font(tema.texto(14)).foregroundStyle(tema.neutral700)
            }
            .padding(.vertical, 20)
        }

        if !libretas.isEmpty {
            Rotulo("Libreta")
            VStack(spacing: 6) {
                ForEach(libretas) { l in
                    opcion(titulo: l.nombre,
                           detalle: l.puedeEscribir ? nil : "Tu rol aquí no permite anotar",
                           elegida: libreta?.id == l.id,
                           activa: l.puedeEscribir) {
                        libreta = l
                        medio = l.medios.first
                        categoria = l.categorias.first(where: { $0.lowercased().contains("super") })
                            ?? l.categorias.first ?? ""
                    }
                }
            }

            if let l = libreta {
                if !l.medios.isEmpty {
                    Rotulo("¿De dónde salió?").padding(.top, 6)
                    VStack(spacing: 6) {
                        ForEach(l.medios) { m in
                            opcion(titulo: m.nombre, detalle: nil, elegida: medio?.id == m.id, activa: true) {
                                medio = m
                            }
                        }
                    }
                }

                Rotulo("Categoría").padding(.top, 6)
                if partir {
                    Tarjeta {
                        ForEach(porCategoria, id: \.0) { par in
                            HStack {
                                Text(par.0).font(tema.texto(15, .medium))
                                Spacer()
                                Text(Formato.pesos(par.1, moneda: ajustes.moneda)).font(tema.texto(15, .bold))
                            }
                        }
                    }
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(l.categorias, id: \.self) { c in
                                Button { categoria = c } label: {
                                    Text(c)
                                        .font(tema.texto(14, .bold))
                                        .padding(.horizontal, 14).padding(.vertical, 11)
                                        .background(categoria == c ? tema.neutral900 : tema.superficie, in: Capsule())
                                        .foregroundStyle(categoria == c ? (tema.oscuro ? tema.texto : tema.neutral100) : tema.texto)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.hidden)
                }

                Grupo {
                    FilaAjuste(titulo: "Partir por categorías",
                               detalle: "Entran \(porCategoria.count) movimientos en vez de uno",
                               ultima: true) {
                        Interruptor(encendido: $partir)
                    }
                }
                .padding(.top, 4)
                .disabled(porCategoria.count < 2)
                .opacity(porCategoria.count < 2 ? 0.5 : 1)

                Button { Task { await manda() } } label: {
                    if enviando { ProgressView().tint(tema.sobreAcento) }
                    else { Text("Enviar \(Formato.pesos(pagado, moneda: ajustes.moneda))") }
                }
                .buttonStyle(BotonPrincipal())
                .disabled(enviando || !l.puedeEscribir)
                .padding(.top, 6)
            }
        }

        if let error { mensajeError(error) }
    }

    private func opcion(titulo: String, detalle: String?, elegida: Bool, activa: Bool,
                        al: @escaping () -> Void) -> some View {
        Button(action: al) {
            HStack(spacing: 12) {
                Radio(elegido: elegida)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo).font(tema.texto(15, .bold))
                    if let detalle {
                        Text(detalle).font(tema.texto(13)).foregroundStyle(tema.neutral700)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(elegida ? tema.acento2_200 : tema.superficie,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .foregroundStyle(tema.texto)
        }
        .buttonStyle(.plain)
        .disabled(!activa)
        .opacity(activa ? 1 : 0.55)
    }

    // MARK: - Ya está

    @ViewBuilder
    private var yaEsta: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Circle().fill(tema.acento2_700)
                IconoView(icono: .check, tamano: 32, grosor: 3).foregroundStyle(tema.fondo)
            }
            .frame(width: 64, height: 64)
            Text("Registrado en Chinola").font(tema.titulo(32)).foregroundStyle(tema.texto)
            Text(lista.chinolaNota.isEmpty
                 ? "El gasto ya está anotado."
                 : "El gasto ya está anotado: \(lista.chinolaNota).")
                .font(tema.texto(15)).foregroundStyle(tema.neutral700)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 10)

        Button("Volver al resumen") { alVolver() }
            .buttonStyle(BotonSuave())
            .padding(.top, 10)
    }

    private func mensajeError(_ t: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            IconoView(icono: .aviso, tamano: 16, grosor: 3)
            Text(t).font(tema.texto(14, .medium)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tema.acento800)
        .padding(14)
        .background(tema.acento100, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Lo que hace

    private func carga() async {
        guard conectada, libretas.isEmpty, !hecho, lista.chinolaNota.isEmpty else { return }
        cargando = true
        defer { cargando = false }
        do {
            libretas = try await ChinolaApi.libretas()
            // Se preselecciona lo que la persona eligió la última vez; si no, la
            // primera donde pueda escribir.
            let guardada = sesion.chinola?.libreta ?? ""
            libreta = libretas.first { $0.id == guardada || $0.nombre == guardada }
                ?? libretas.first(where: \.puedeEscribir)
            if let l = libreta {
                let medioGuardado = sesion.chinola?.medio ?? ""
                medio = l.medios.first { $0.id == medioGuardado } ?? l.medios.first
                categoria = l.categorias.first { $0.lowercased().contains("super") } ?? l.categorias.first ?? ""
            }
        } catch {
            error = (error as? LocalizedError)?.errorDescription ?? "No pude hablar con Chinola."
        }
    }

    private func conecta() async {
        enviando = true
        error = nil
        defer { enviando = false }
        do {
            let url = try await ChinolaApi.urlParaConectar()
            // Se abre en el navegador del sistema: así se ve el dominio de
            // Chinola y el candado, que es lo único que distingue una pantalla
            // de permiso de verdad de una copiada dentro de una app.
            abre(url)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "No pude empezar la conexión."
        }
    }

    private func manda() async {
        guard let l = libreta else { return }
        enviando = true
        error = nil
        defer { enviando = false }

        let lineas: [ChinolaApi.Linea] = partir && porCategoria.count > 1
            ? porCategoria.map { par in
                .init(concepto: "\(lista.nombre) · \(par.0)", monto: par.1, categoria: par.0,
                      tipo: "Gasto Variable", idempotencia: "cuadre:\(lista.id):\(par.0)")
              }
            : [.init(concepto: lista.tienda.isEmpty ? lista.nombre : "\(lista.nombre) · \(lista.tienda)",
                     monto: pagado, categoria: categoria.isEmpty ? nil : categoria,
                     tipo: "Gasto Variable", idempotencia: "cuadre:\(lista.id)")]

        do {
            _ = try await ChinolaApi.anota(lineas, fecha: lista.cerradaEn ?? lista.fecha,
                                           libreta: l.id, medio: medio?.id)
            // Se recuerda a dónde fue para no volver a preguntarlo la próxima vez.
            try? await ChinolaApi.fija(libreta: l.id, medio: medio?.id ?? "", cuenta: medio?.nombre ?? "")
            lista.chinolaNota = [l.nombre, medio?.nombre].compactMap { $0 }.joined(separator: " · ")
            lista.toco()
            try? ctx.save()
            await sesion.refresca()
            withAnimation(.snappy) { hecho = true }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Chinola no aceptó el movimiento."
        }
    }
}
