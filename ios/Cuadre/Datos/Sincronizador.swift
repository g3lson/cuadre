import Foundation
import SwiftData

/// SINCRONIZAR.
///
/// Sube lo que cambió aquí, baja lo que cambió allá, y eso es todo. En una sola
/// llamada: en el súper con dos barras de señal, cada viaje de ida y vuelta
/// cuenta, y partirlo en «subir» y «bajar» duplicaría la única parte cara.
///
/// La regla para juntar dos versiones de la misma fila es la más simple que
/// funciona: gana la más reciente. No es un documento a cuatro manos —son tus
/// listas en tus dispositivos— y cualquier cosa más lista que esto sería
/// complejidad pagada por un caso que no ocurre.
///
/// El contenido de cada fila viaja como un objeto `datos`. El servidor lo guarda
/// tal cual sin mirarlo dentro, así que añadir un campo a un modelo no obliga a
/// migrar la base del servidor ni a desplegar nada.
@Observable
@MainActor
final class Sincronizador {
    enum Estado: Equatable {
        case quieto
        case trabajando
        case fallo(String)
    }

    private(set) var estado: Estado = .quieto
    private(set) var ultima: Date?

    private let contexto: ModelContext
    private var enMarcha = false

    /// Hasta dónde se bajó la última vez. Es una marca del servidor, no del
    /// teléfono: si el reloj del teléfono va cinco minutos adelantado, usar la
    /// hora de aquí se saltaría cinco minutos de cambios ajenos.
    private var hasta: String {
        get { UserDefaults.standard.string(forKey: "sincronizadoHasta") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "sincronizadoHasta") }
    }

    init(contexto: ModelContext) {
        self.contexto = contexto
    }

    // MARK: - El viaje

    func sincroniza() async {
        guard await Api.shared.hayTestigo(), !enMarcha else { return }
        enMarcha = true
        estado = .trabajando
        defer { enMarcha = false }

        do {
            let (cambios, enviados) = reúneLoPendiente()
            let peticion = Subida(desde: hasta, cambios: cambios)
            let r: Bajada = try await Api.shared.pide("api/sync", metodo: "POST", cuerpo: peticion)

            marcaSubido(enviados, cuando: .now)
            aplica(r.cambios)
            hasta = r.ahora
            try contexto.save()
            ultima = .now
            estado = .quieto
        } catch is CancellationError {
            estado = .quieto
        } catch let e as Api.Fallo {
            // Sin red no es un fallo que enseñar: lo pendiente sigue marcado y
            // sube en el siguiente intento.
            estado = e.esPasajero ? .quieto : .fallo(e.localizedDescription)
        } catch {
            estado = .fallo(error.localizedDescription)
        }
    }

    // MARK: - Subir

    private func pendientes<T: PersistentModel & Sincronizable>(_ tipo: T.Type) -> [T] {
        ((try? contexto.fetch(FetchDescriptor<T>())) ?? []).filter(\.pendiente)
    }

    private func reúneLoPendiente() -> (CambiosJSON, Enviados) {
        let grupos = pendientes(Grupo.self)
        let pasillos = pendientes(Pasillo.self)
        let listas = pendientes(Lista.self)
        let articulos = pendientes(Articulo.self)
        let eventos = pendientes(Evento.self)
        let encargos = pendientes(Encargo.self)
        let catalogo = pendientes(Producto.self)
        let clientes = pendientes(Cliente.self)
        let tiendas = pendientes(Tienda.self)
        let ajustes = pendientes(Ajustes.self)

        let c = CambiosJSON(
            grupos: grupos.map { Fila(id: $0.id, actualizado: $0.actualizado, borrado: $0.borrado, datos: .init($0)) },
            pasillos: pasillos.map { Fila(id: $0.id, actualizado: $0.actualizado, borrado: $0.borrado, datos: .init($0)) },
            listas: listas.map { Fila(id: $0.id, actualizado: $0.actualizado, borrado: $0.borrado, datos: .init($0)) },
            articulos: articulos.map { Fila(id: $0.id, actualizado: $0.actualizado, borrado: $0.borrado, datos: .init($0)) },
            eventos: eventos.map { Fila(id: $0.id, actualizado: $0.actualizado, borrado: $0.borrado, datos: .init($0)) },
            encargos: encargos.map { Fila(id: $0.id, actualizado: $0.actualizado, borrado: $0.borrado, datos: .init($0)) },
            catalogo: catalogo.map { Fila(id: $0.id, actualizado: $0.actualizado, borrado: $0.borrado, datos: .init($0)) },
            clientes: clientes.map { Fila(id: $0.id, actualizado: $0.actualizado, borrado: $0.borrado, datos: .init($0)) },
            tiendas: tiendas.map { Fila(id: $0.id, actualizado: $0.actualizado, borrado: $0.borrado, datos: .init($0)) },
            ajustes: ajustes.map { Fila(id: $0.id, actualizado: $0.actualizado, borrado: $0.borrado, datos: .init($0)) }
        )
        return (c, Enviados(grupos: grupos, pasillos: pasillos, listas: listas, articulos: articulos, eventos: eventos, encargos: encargos,
                            catalogo: catalogo, clientes: clientes, tiendas: tiendas, ajustes: ajustes))
    }

    private struct Enviados {
        let grupos: [Grupo], pasillos: [Pasillo]
        let listas: [Lista], articulos: [Articulo], eventos: [Evento], encargos: [Encargo]
        let catalogo: [Producto], clientes: [Cliente], tiendas: [Tienda], ajustes: [Ajustes]
    }

    /// Se marca lo enviado con la hora de ANTES de mandarlo: si alguien tocó la
    /// fila mientras el mensaje viajaba, `actualizado` queda por delante de
    /// `subido` y esa fila vuelve a salir en el siguiente viaje.
    private func marcaSubido(_ e: Enviados, cuando: Date) {
        e.grupos.forEach { $0.subido = cuando }
        e.pasillos.forEach { $0.subido = cuando }
        e.listas.forEach { $0.subido = cuando }
        e.articulos.forEach { $0.subido = cuando }
        e.eventos.forEach { $0.subido = cuando }
        e.encargos.forEach { $0.subido = cuando }
        e.catalogo.forEach { $0.subido = cuando }
        e.clientes.forEach { $0.subido = cuando }
        e.tiendas.forEach { $0.subido = cuando }
        e.ajustes.forEach { $0.subido = cuando }
    }

    // MARK: - Bajar

    private func aplica(_ c: CambiosJSON) {
        funde(c.grupos) { Grupo(id: $0, nombre: "") }
        funde(c.pasillos) { Pasillo(id: $0, nombre: "") }
        funde(c.listas) { Lista(id: $0, nombre: "") }
        funde(c.articulos) { Articulo(id: $0, listaId: "") }
        funde(c.eventos) { Evento(id: $0, titulo: "") }
        funde(c.encargos) { Encargo(id: $0, eventoId: "", cliente: "", producto: "") }
        funde(c.catalogo) { Producto(id: $0, nombre: "") }
        funde(c.clientes) { Cliente(id: $0, nombre: "") }
        funde(c.tiendas) { Tienda(id: $0, nombre: "") }
        funde(c.ajustes) { Ajustes(id: $0) }
    }

    private func funde<M: PersistentModel & Sincronizable, D: DatosDe>(
        _ filas: [Fila<D>], nuevo: (String) -> M
    ) where D.Modelo == M {
        guard !filas.isEmpty else { return }
        let ids = Set(filas.map(\.id))
        let existentes = ((try? contexto.fetch(FetchDescriptor<M>())) ?? [])
            .filter { ids.contains($0.id) }
        var porId = Dictionary(uniqueKeysWithValues: existentes.map { ($0.id, $0) })

        for f in filas {
            let m: M
            if let ya = porId[f.id] {
                // Lo de aquí es más nuevo: lo que bajó ya está viejo y se
                // ignora. En el siguiente viaje sube lo nuestro y gana allá.
                if ya.actualizado > f.actualizado { continue }
                m = ya
            } else {
                m = nuevo(f.id)
                contexto.insert(m)
                porId[f.id] = m
            }
            f.datos.vuelca(en: m)
            m.actualizado = f.actualizado
            m.borrado = f.borrado
            // Viene del servidor: ya está allá, no hay nada que subir.
            m.subido = f.actualizado
        }
    }
}

// MARK: - Lo que viaja

private struct Subida: Encodable {
    let desde: String
    let cambios: CambiosJSON
}

private struct Bajada: Decodable {
    let ahora: String
    let cambios: CambiosJSON
}

struct Fila<D: Codable>: Codable {
    var id: String
    var actualizado: Date
    var borrado: Date?
    var datos: D
}

struct CambiosJSON: Codable {
    var grupos: [Fila<DatosGrupo>] = []
    var pasillos: [Fila<DatosPasillo>] = []
    var listas: [Fila<DatosLista>] = []
    var articulos: [Fila<DatosArticulo>] = []
    var eventos: [Fila<DatosEvento>] = []
    var encargos: [Fila<DatosEncargo>] = []
    var catalogo: [Fila<DatosProducto>] = []
    var clientes: [Fila<DatosCliente>] = []
    var tiendas: [Fila<DatosTienda>] = []
    var ajustes: [Fila<DatosAjustes>] = []
}

/// Leer un campo que puede no estar.
///
/// Swift no usa el valor por defecto de una propiedad cuando falta su clave al
/// decodificar: lanza. Y faltar va a faltar —una versión vieja de la app
/// escribió filas sin los campos que se añadieron después—, así que cada
/// `init(from:)` se escribe a mano con esto y un campo nuevo nunca rompe la
/// bajada entera por una fila antigua.
extension KeyedDecodingContainer {
    func v<T: Decodable>(_ k: Key, _ pordefecto: T) -> T {
        (try? decodeIfPresent(T.self, forKey: k)) .flatMap { $0 } ?? pordefecto
    }
    func opcional<T: Decodable>(_ k: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: k)) ?? nil
    }
}

/// El puente entre el modelo guardado y lo que viaja. Se escribe a mano y no con
/// `Codable` sobre el propio `@Model` porque lo que viaja no debe incluir las
/// marcas de sincronización: esas son del sobre, no de la carta.
protocol DatosDe: Codable {
    associatedtype Modelo: AnyObject
    init(_ m: Modelo)
    func vuelca(en m: Modelo)
}

struct DatosGrupo: DatosDe {
    var nombre = ""; var color = 0
    init(_ m: Grupo) { nombre = m.nombre; color = m.color }
    init(from dec: Decoder) throws {
        let c = try dec.container(keyedBy: CodingKeys.self)
        nombre = c.v(.nombre, ""); color = c.v(.color, 0)
    }
    func vuelca(en m: Grupo) { m.nombre = nombre; m.color = color }
}

struct DatosPasillo: DatosDe {
    var nombre = ""; var orden = 0; var grupoId = ""
    init(_ m: Pasillo) { nombre = m.nombre; orden = m.orden; grupoId = m.grupoId }
    init(from dec: Decoder) throws {
        let c = try dec.container(keyedBy: CodingKeys.self)
        nombre = c.v(.nombre, ""); orden = c.v(.orden, 0); grupoId = c.v(.grupoId, "")
    }
    func vuelca(en m: Pasillo) { m.nombre = nombre; m.orden = orden; m.grupoId = grupoId }
}

struct DatosLista: DatosDe {
    var nombre = ""; var tienda = ""; var presupuesto: Double = 0
    var fecha = Date(); var color = 0; var estado = "activa"
    var cerradaEn: Date?; var notaCierre = ""; var chinolaNota = ""; var orden = 0
    var grupoId = ""

    init(_ m: Lista) {
        nombre = m.nombre; tienda = m.tienda; presupuesto = m.presupuesto; fecha = m.fecha
        color = m.color; estado = m.estado; cerradaEn = m.cerradaEn
        notaCierre = m.notaCierre; chinolaNota = m.chinolaNota; orden = m.orden
        grupoId = m.grupoId
    }
    init(from dec: Decoder) throws {
        let c = try dec.container(keyedBy: CodingKeys.self)
        nombre = c.v(.nombre, ""); tienda = c.v(.tienda, ""); presupuesto = c.v(.presupuesto, 0)
        fecha = c.v(.fecha, Date()); color = c.v(.color, 0); estado = c.v(.estado, "activa")
        cerradaEn = c.opcional(.cerradaEn); notaCierre = c.v(.notaCierre, "")
        chinolaNota = c.v(.chinolaNota, ""); orden = c.v(.orden, 0); grupoId = c.v(.grupoId, "")
    }

    func vuelca(en m: Lista) {
        m.nombre = nombre; m.tienda = tienda; m.presupuesto = presupuesto; m.fecha = fecha
        m.color = color; m.estado = estado; m.cerradaEn = cerradaEn
        m.notaCierre = notaCierre; m.chinolaNota = chinolaNota; m.orden = orden
        m.grupoId = grupoId
    }
}

struct DatosArticulo: DatosDe {
    var listaId = ""; var nombre = ""; var unidad = "ud"; var cantidad: Double = 1
    var precio: Double = 0; var hecho = false; var nota = ""; var categoria = Categoria.porDefecto
    var orden = 0; var tienda = ""; var hechoPor = ""

    init(_ m: Articulo) {
        listaId = m.listaId; nombre = m.nombre; unidad = m.unidad; cantidad = m.cantidad
        precio = m.precio; hecho = m.hecho; nota = m.nota; categoria = m.categoria
        orden = m.orden; hechoPor = m.hechoPor
    }
    init(from dec: Decoder) throws {
        let c = try dec.container(keyedBy: CodingKeys.self)
        listaId = c.v(.listaId, ""); nombre = c.v(.nombre, ""); unidad = c.v(.unidad, "ud")
        cantidad = c.v(.cantidad, 1); precio = c.v(.precio, 0); hecho = c.v(.hecho, false)
        nota = c.v(.nota, ""); categoria = c.v(.categoria, Categoria.porDefecto)
        orden = c.v(.orden, 0); tienda = c.v(.tienda, ""); hechoPor = c.v(.hechoPor, "")
    }

    func vuelca(en m: Articulo) {
        m.listaId = listaId; m.nombre = nombre; m.unidad = unidad; m.cantidad = cantidad
        m.precio = precio; m.hecho = hecho; m.nota = nota; m.categoria = categoria
        m.orden = orden; m.hechoPor = hechoPor
    }
}

struct DatosEvento: DatosDe {
    var titulo = ""; var fecha = Date(); var estado = "abierto"
    init(_ m: Evento) { titulo = m.titulo; fecha = m.fecha; estado = m.estado }
    init(from dec: Decoder) throws {
        let c = try dec.container(keyedBy: CodingKeys.self)
        titulo = c.v(.titulo, ""); fecha = c.v(.fecha, Date()); estado = c.v(.estado, "abierto")
    }

    func vuelca(en m: Evento) { m.titulo = titulo; m.fecha = fecha; m.estado = estado }
}

struct DatosEncargo: DatosDe {
    var eventoId = ""; var cliente = ""; var telefono = ""; var producto = ""
    var unidad = "lb"; var pedido: Double = 1; var cantidad: Double = 1; var tarifa = "detal"
    var precioDetal: Double = 0; var precioMayor: Double = 0; var precioEspecial: Double = 0
    var costo: Double = 0; var estado = "pendiente"; var metodo = ""; var nota = ""
    var clase = "venta"; var registradoPor = ""
    var cobradoEn: Date?

    init(_ m: Encargo) {
        eventoId = m.eventoId; cliente = m.cliente; telefono = m.telefono; producto = m.producto
        unidad = m.unidad; pedido = m.pedido; cantidad = m.cantidad; tarifa = m.tarifa
        precioDetal = m.precioDetal; precioMayor = m.precioMayor; precioEspecial = m.precioEspecial
        costo = m.costo; estado = m.estado; metodo = m.metodo; nota = m.nota
        clase = m.clase; registradoPor = m.registradoPor; cobradoEn = m.cobradoEn
    }
    init(from dec: Decoder) throws {
        let c = try dec.container(keyedBy: CodingKeys.self)
        eventoId = c.v(.eventoId, ""); cliente = c.v(.cliente, ""); telefono = c.v(.telefono, "")
        producto = c.v(.producto, ""); unidad = c.v(.unidad, "lb"); pedido = c.v(.pedido, 1)
        cantidad = c.v(.cantidad, 1); tarifa = c.v(.tarifa, "detal")
        precioDetal = c.v(.precioDetal, 0); precioMayor = c.v(.precioMayor, 0)
        precioEspecial = c.v(.precioEspecial, 0); costo = c.v(.costo, 0)
        estado = c.v(.estado, "pendiente"); metodo = c.v(.metodo, ""); nota = c.v(.nota, "")
        clase = c.v(.clase, "venta"); registradoPor = c.v(.registradoPor, "")
        cobradoEn = c.opcional(.cobradoEn)
    }

    func vuelca(en m: Encargo) {
        m.eventoId = eventoId; m.cliente = cliente; m.telefono = telefono; m.producto = producto
        m.unidad = unidad; m.pedido = pedido; m.cantidad = cantidad; m.tarifa = tarifa
        m.precioDetal = precioDetal; m.precioMayor = precioMayor; m.precioEspecial = precioEspecial
        m.costo = costo; m.estado = estado; m.metodo = metodo; m.nota = nota
        m.clase = clase; m.registradoPor = registradoPor; m.cobradoEn = cobradoEn
    }
}

struct DatosProducto: DatosDe {
    var nombre = ""; var categoria = Categoria.porDefecto; var unidad = "lb"
    var costo: Double = 0; var precioDetal: Double = 0; var precioMayor: Double = 0
    var precioEspecial: Double = 0

    init(_ m: Producto) {
        nombre = m.nombre; categoria = m.categoria; unidad = m.unidad; costo = m.costo
        precioDetal = m.precioDetal; precioMayor = m.precioMayor; precioEspecial = m.precioEspecial
    }
    init(from dec: Decoder) throws {
        let c = try dec.container(keyedBy: CodingKeys.self)
        nombre = c.v(.nombre, ""); categoria = c.v(.categoria, Categoria.porDefecto)
        unidad = c.v(.unidad, "lb"); costo = c.v(.costo, 0)
        precioDetal = c.v(.precioDetal, 0); precioMayor = c.v(.precioMayor, 0)
        precioEspecial = c.v(.precioEspecial, 0)
    }

    func vuelca(en m: Producto) {
        m.nombre = nombre; m.categoria = categoria; m.unidad = unidad; m.costo = costo
        m.precioDetal = precioDetal; m.precioMayor = precioMayor; m.precioEspecial = precioEspecial
    }
}

struct DatosCliente: DatosDe {
    var nombre = ""; var telefono = ""
    init(_ m: Cliente) { nombre = m.nombre; telefono = m.telefono }
    init(from dec: Decoder) throws {
        let c = try dec.container(keyedBy: CodingKeys.self)
        nombre = c.v(.nombre, ""); telefono = c.v(.telefono, "")
    }

    func vuelca(en m: Cliente) { m.nombre = nombre; m.telefono = telefono }
}

struct DatosTienda: DatosDe {
    var nombre = ""
    init(_ m: Tienda) { nombre = m.nombre }
    init(from dec: Decoder) throws {
        let c = try dec.container(keyedBy: CodingKeys.self)
        nombre = c.v(.nombre, "")
    }

    func vuelca(en m: Tienda) { m.nombre = nombre }
}

struct DatosAjustes: DatosDe {
    var tema = "barro"; var moneda = "RD$"; var unidadPorDefecto = "lb"
    var modoVendedor = false; var nombreNegocio = ""
    var verCantidad = true; var verPrecio = true; var verTotal = true; var verNota = false
    var nombreDetal = "Detal"; var nombreMayor = "Mayor"; var nombreEspecial = "Especial"
    var agrupar = true; var modeloIA = ""
    var vistaVentas = "tarjetas"; var avisarListas = true; var confirmarCobro = true

    init(_ m: Ajustes) {
        tema = m.tema; moneda = m.moneda; unidadPorDefecto = m.unidadPorDefecto
        modoVendedor = m.modoVendedor; nombreNegocio = m.nombreNegocio
        verCantidad = m.verCantidad; verPrecio = m.verPrecio; verTotal = m.verTotal; verNota = m.verNota
        nombreDetal = m.nombreDetal; nombreMayor = m.nombreMayor; nombreEspecial = m.nombreEspecial
        agrupar = m.agrupar; modeloIA = m.modeloIA
        vistaVentas = m.vistaVentas; avisarListas = m.avisarListas
        confirmarCobro = m.confirmarCobro
    }
    init(from dec: Decoder) throws {
        let c = try dec.container(keyedBy: CodingKeys.self)
        tema = c.v(.tema, "barro"); moneda = c.v(.moneda, "RD$")
        unidadPorDefecto = c.v(.unidadPorDefecto, "lb"); modoVendedor = c.v(.modoVendedor, false)
        nombreNegocio = c.v(.nombreNegocio, "")
        verCantidad = c.v(.verCantidad, true); verPrecio = c.v(.verPrecio, true)
        verTotal = c.v(.verTotal, true); verNota = c.v(.verNota, false)
        nombreDetal = c.v(.nombreDetal, "Detal"); nombreMayor = c.v(.nombreMayor, "Mayor")
        nombreEspecial = c.v(.nombreEspecial, "Especial")
        agrupar = c.v(.agrupar, true); modeloIA = c.v(.modeloIA, "")
        vistaVentas = c.v(.vistaVentas, "tarjetas"); avisarListas = c.v(.avisarListas, true)
        confirmarCobro = c.v(.confirmarCobro, true)
    }

    func vuelca(en m: Ajustes) {
        m.tema = tema; m.moneda = moneda; m.unidadPorDefecto = unidadPorDefecto
        m.modoVendedor = modoVendedor; m.nombreNegocio = nombreNegocio
        m.verCantidad = verCantidad; m.verPrecio = verPrecio; m.verTotal = verTotal; m.verNota = verNota
        m.nombreDetal = nombreDetal; m.nombreMayor = nombreMayor; m.nombreEspecial = nombreEspecial
        m.agrupar = agrupar; m.modeloIA = modeloIA
        m.vistaVentas = vistaVentas; m.avisarListas = avisarListas
        m.confirmarCobro = confirmarCobro
    }
}
