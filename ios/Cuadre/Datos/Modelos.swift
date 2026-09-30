import Foundation
import SwiftData
import SwiftUI

/// LOS DATOS.
///
/// Todo vive primero en el teléfono. La app tiene que funcionar entera en el
/// pasillo del súper, donde no hay señal, así que el servidor no es la fuente:
/// es el sitio donde se guarda copia y por donde pasan los otros dispositivos.
///
/// Por eso cada fila lleva tres marcas y no una:
///   · `actualizado` — cuándo se tocó. Es lo que decide quién gana al juntar dos
///     versiones, y lo pone quien escribe, no el servidor: lo que anotaste a las
///     10:05 sin señal pasó a las 10:05.
///   · `borrado` — una lápida. Borrar de verdad la fila haría que reapareciera
///     en cuanto otro teléfono suba lo que él tenía.
///   · `subido` — hasta dónde llegó lo que ya viajó. Si es menor que
///     `actualizado`, esta fila tiene algo que contar.
///
/// No hay relaciones de SwiftData entre modelos, sino identificadores sueltos
/// (`listaId`). Una relación sería más bonita de leer aquí y un problema al
/// sincronizar: el servidor guarda filas planas, y dos formas distintas de lo
/// mismo es la manera de que un borrado deje huérfanos.

protocol Sincronizable: AnyObject {
    var id: String { get }
    var actualizado: Date { get set }
    var borrado: Date? { get set }
    var subido: Date? { get set }
}

extension Sincronizable {
    var pendiente: Bool { subido == nil || subido! < actualizado }
    var vivo: Bool { borrado == nil }

    /// Tocar una fila es marcarla, no guardarla: SwiftData ya guarda.
    func toco(_ cuando: Date = .now) { actualizado = cuando }

    func entierro(_ cuando: Date = .now) {
        borrado = cuando
        actualizado = cuando
    }
}

@Model final class Lista: Sincronizable {
    @Attribute(.unique) var id: String = ""
    var nombre: String = ""
    var tienda: String = ""
    var presupuesto: Double = 0
    var fecha: Date = .now
    /// Índice en la paleta del tema: el color se resuelve al pintar, para que
    /// cambiar de tema cambie también los colores de las listas.
    var color: Int = 0
    /// «activa» mientras se compra, «cerrada» cuando cuadró.
    var estado: String = ""
    var cerradaEn: Date? = nil
    var notaCierre: String = ""
    /// Qué se hizo con el gasto: el texto que se enseña en la lista cerrada.
    var chinolaNota: String = ""
    var orden: Int = 0
    /// A qué grupo pertenece. Vacío = solo tuya.
    var grupoId: String = ""
    var actualizado: Date = .now
    var borrado: Date? = nil
    var subido: Date? = nil

    init(id: String = UUID().uuidString, nombre: String, tienda: String = "",
         presupuesto: Double = 0, fecha: Date = .now, color: Int = 0,
         estado: String = "activa", orden: Int = 0) {
        self.id = id
        self.nombre = nombre
        self.tienda = tienda
        self.presupuesto = presupuesto
        self.fecha = fecha
        self.color = color
        self.estado = estado
        self.cerradaEn = nil
        self.notaCierre = ""
        self.chinolaNota = ""
        self.orden = orden
        self.grupoId = ""
        self.actualizado = .now
    }

    var cerrada: Bool { estado == "cerrada" }
}

@Model final class Articulo: Sincronizable {
    @Attribute(.unique) var id: String = ""
    var listaId: String = ""
    var nombre: String = ""
    var unidad: String = ""
    var cantidad: Double = 0
    var precio: Double = 0
    var hecho: Bool = false
    var nota: String = ""
    var categoria: String = ""
    var orden: Int = 0
    /// Quién lo echó al carrito, cuando la lista es de dos. Se guarda el nombre
    /// y no el identificador: lo que hay que enseñar es «lo cogió Ana», y pedirle
    /// el nombre al servidor por cada fila para eso sería absurdo.
    var hechoPor: String = ""
    var actualizado: Date = .now
    var borrado: Date? = nil
    var subido: Date? = nil

    init(id: String = UUID().uuidString, listaId: String, nombre: String = "",
         unidad: String = "ud", cantidad: Double = 1, precio: Double = 0,
         hecho: Bool = false, nota: String = "", categoria: String = Categoria.porDefecto,
         orden: Int = 0) {
        self.id = id
        self.listaId = listaId
        self.nombre = nombre
        self.unidad = unidad
        self.cantidad = cantidad
        self.precio = precio
        self.hecho = hecho
        self.nota = nota
        self.categoria = categoria
        self.orden = orden
        self.hechoPor = ""
        self.actualizado = .now
    }

    var total: Double { cantidad * precio }

    /// Marcar o desmarcar, dejando dicho quién fue. En una lista de una sola
    /// persona el nombre sobra y no se enseña; en una de dos es lo importante.
    func marca(_ puesto: Bool, quien: String) {
        hecho = puesto
        hechoPor = puesto ? quien : ""
        toco()
    }
}

@Model final class Evento: Sincronizable {
    @Attribute(.unique) var id: String = ""
    var titulo: String = ""
    var fecha: Date = .now
    /// «abierto» mientras se despacha, «cerrado» cuando se cuadró el día.
    var estado: String = ""
    var grupoId: String = ""
    /// A nombre de qué negocio se despacha este día. Sale del grupo al crear
    /// la venta, pero se puede cambiar: un sábado se vende en el mercado y el
    /// otro en la parada, y el comprobante no dice lo mismo.
    var negocio: String = ""
    var actualizado: Date = .now
    var borrado: Date? = nil
    var subido: Date? = nil

    init(id: String = UUID().uuidString, titulo: String, fecha: Date = .now, estado: String = "abierto") {
        self.id = id
        self.titulo = titulo
        self.fecha = fecha
        self.estado = estado
        self.grupoId = ""
        self.negocio = ""
        self.actualizado = .now
    }
}

@Model final class Encargo: Sincronizable {
    @Attribute(.unique) var id: String = ""
    var eventoId: String = ""
    var cliente: String = ""
    var telefono: String = ""
    var producto: String = ""
    var unidad: String = ""
    /// Lo que pidió, que no tiene por qué ser lo que se le despachó.
    var pedido: Double = 0
    var cantidad: Double = 0
    var tarifa: String = ""
    var precioDetal: Double = 0
    var precioMayor: Double = 0
    var precioEspecial: Double = 0
    /// Lo que te costó a ti la libra. Es lo que hace que el cuadre sepa la ganancia.
    var costo: Double = 0
    /// «pendiente» o «cobrado».
    var estado: String = ""
    /// Qué clase de salida es. No todo lo que sale del negocio se cobra: hay
    /// regalos, donaciones, consumo propio y rebajas. Contarlas como ventas de
    /// cero pesos falsea el margen; no contarlas hace que el inventario no cuadre.
    var clase: String = ""
    var metodo: String = ""
    var nota: String = ""
    /// Quién lo anotó. En una venta a varias manos es la mitad de la
    /// información: saber que se vendieron treinta libras no dice nada si no se
    /// sabe quién las despachó.
    var registradoPor: String = ""
    var cobradoEn: Date? = nil
    var actualizado: Date = .now
    var borrado: Date? = nil
    var subido: Date? = nil

    init(id: String = UUID().uuidString, eventoId: String, cliente: String,
         producto: String, unidad: String = "lb", pedido: Double = 1,
         precioDetal: Double = 0, precioMayor: Double = 0, precioEspecial: Double = 0,
         costo: Double = 0) {
        self.id = id
        self.eventoId = eventoId
        self.cliente = cliente
        self.telefono = ""
        self.producto = producto
        self.unidad = unidad
        self.pedido = pedido
        self.cantidad = pedido
        self.tarifa = Tarifa.detal.rawValue
        self.precioDetal = precioDetal
        self.precioMayor = precioMayor
        self.precioEspecial = precioEspecial
        self.costo = costo
        self.estado = "pendiente"
        self.clase = Salida.venta.rawValue
        self.metodo = ""
        self.nota = ""
        self.registradoPor = ""
        self.actualizado = .now
    }

    var salida: Salida { Salida(rawValue: clase) ?? .venta }

    /// El precio de la tarifa elegida. Lo que se cobra de verdad es `total`.
    var precioAplicado: Double {
        switch Tarifa(rawValue: tarifa) ?? .detal {
        case .detal: return precioDetal
        case .mayor: return precioMayor
        case .especial: return precioEspecial
        }
    }

    /// Lo que entra. Un regalo o una donación no entran, aunque la mercancía
    /// salga igual y cueste lo mismo.
    var total: Double { salida.cobra ? cantidad * precioAplicado : 0 }
    var costoTotal: Double { cantidad * costo }
    var cobrado: Bool { estado == "cobrado" }
}

@Model final class Producto: Sincronizable {
    @Attribute(.unique) var id: String = ""
    var nombre: String = ""
    var categoria: String = ""
    var unidad: String = ""
    var costo: Double = 0
    var precioDetal: Double = 0
    var precioMayor: Double = 0
    var precioEspecial: Double = 0
    var actualizado: Date = .now
    var borrado: Date? = nil
    var subido: Date? = nil

    init(id: String = UUID().uuidString, nombre: String, categoria: String = Categoria.porDefecto,
         unidad: String = "lb", costo: Double = 0, precioDetal: Double = 0,
         precioMayor: Double = 0, precioEspecial: Double = 0) {
        self.id = id
        self.nombre = nombre
        self.categoria = categoria
        self.unidad = unidad
        self.costo = costo
        self.precioDetal = precioDetal
        self.precioMayor = precioMayor
        self.precioEspecial = precioEspecial
        self.actualizado = .now
    }
}

@Model final class Cliente: Sincronizable {
    @Attribute(.unique) var id: String = ""
    var nombre: String = ""
    var telefono: String = ""
    var grupoId: String = ""
    var actualizado: Date = .now
    var borrado: Date? = nil
    var subido: Date? = nil

    init(id: String = UUID().uuidString, nombre: String, telefono: String = "") {
        self.id = id
        self.nombre = nombre
        self.telefono = telefono
        self.grupoId = ""
        self.actualizado = .now
    }
}

/// UN PASILLO.
///
/// Las categorías con las que se agrupa la lista. Son datos y no una lista fija
/// porque cada quien compra en un sitio distinto y lo recorre en otro orden: un
/// colmado no tiene «Ferretería», y quien vende pescado querrá «Nevera» antes
/// que «Víveres». Las que trae la app son un punto de partida, no una regla.
@Model final class Pasillo: Sincronizable {
    @Attribute(.unique) var id: String = ""
    var nombre: String = ""
    /// En qué orden se recorren. Es lo que de verdad ahorra pasos en el súper.
    var orden: Int = 0
    var grupoId: String = ""
    var actualizado: Date = .now
    var borrado: Date? = nil
    var subido: Date? = nil

    init(id: String = UUID().uuidString, nombre: String, orden: Int = 0, grupoId: String = "") {
        self.id = id
        self.nombre = nombre
        self.orden = orden
        self.grupoId = grupoId
        self.actualizado = .now
    }
}

/// UN GRUPO.
///
/// «Mi negocio», «El otro negocio», «Casa». Lo que se crea dentro de un grupo lo
/// ve la gente del grupo, sin compartirlo cosa por cosa.
/// UN GRUPO ES UN NEGOCIO.
///
/// Empezó siendo solo una manera de compartir, pero es lo que la gente tiene en
/// la cabeza: «la pescadería», «el colmado», «la casa». Así que lleva lo que
/// lleva un negocio —su nombre, su logo, su portada— y todo lo que se despacha
/// dentro sale con esa cara: el comprobante del cliente, el reporte del día.
///
/// Las imágenes NO se guardan aquí: aquí va su dirección. Un logo en base64
/// dentro de la fila se mandaría entero en cada sincronización de cada teléfono
/// del grupo, por una foto que cambia una vez al año.
@Model final class Grupo: Sincronizable {
    @Attribute(.unique) var id: String = ""
    var nombre: String = ""
    var color: Int = 0
    /// La dirección del logo, cuadrado. Vacío = se usa la inicial.
    var logo: String = ""
    /// La dirección de la portada, apaisada. Vacío = un degradado del color.
    var portada: String = ""
    /// El teléfono que sale en el comprobante, para que el cliente sepa a
    /// dónde llamar si algo no cuadra.
    var telefono: String = ""
    var actualizado: Date = .now
    var borrado: Date? = nil
    var subido: Date? = nil

    init(id: String = UUID().uuidString, nombre: String, color: Int = 0) {
        self.id = id
        self.nombre = nombre
        self.color = color
        self.logo = ""
        self.portada = ""
        self.telefono = ""
        self.actualizado = .now
    }
}

@Model final class Tienda: Sincronizable {
    @Attribute(.unique) var id: String = ""
    var nombre: String = ""
    var actualizado: Date = .now
    var borrado: Date? = nil
    var subido: Date? = nil

    init(id: String = UUID().uuidString, nombre: String) {
        self.id = id
        self.nombre = nombre
        self.actualizado = .now
    }
}

/// Los ajustes son una sola fila, y su `id` es el de la persona: así el
/// sincronizador los trata igual que a todo lo demás sin un caso aparte.
@Model final class Ajustes: Sincronizable {
    @Attribute(.unique) var id: String = ""
    var tema: String = ""
    var moneda: String = ""
    var unidadPorDefecto: String = ""
    var modoVendedor: Bool = false
    var nombreNegocio: String = ""
    var verCantidad: Bool = false
    var verPrecio: Bool = false
    var verTotal: Bool = false
    var verNota: Bool = false
    var nombreDetal: String = ""
    var nombreMayor: String = ""
    var nombreEspecial: String = ""
    /// Agrupar la lista por categoría para recorrer el súper en orden en vez de
    /// ir y volver por los pasillos.
    var agrupar: Bool = false
    /// El modelo de IA que eligió esta persona. Vacío = el que traiga el servidor.
    var modeloIA: String = ""
    /// Cómo se ven los encargos: «tarjetas», «tabla» o «compacta».
    var vistaVentas: String = ""
    /// Recordar las listas con fecha.
    var avisarListas: Bool = false
    /// Preguntar antes de dar algo por cobrado. Viene encendido: marcar a
    /// alguien como que pagó cuando no ha pagado cuesta dinero de verdad, y el
    /// error se descubre cuando ya se fue.
    var confirmarCobro: Bool = false
    var actualizado: Date = .now
    var borrado: Date? = nil
    var subido: Date? = nil

    init(id: String) {
        self.id = id
        self.tema = Tema.Clave.barro.rawValue
        self.moneda = "RD$"
        self.unidadPorDefecto = "lb"
        self.modoVendedor = false
        self.nombreNegocio = ""
        self.verCantidad = true
        self.verPrecio = true
        self.verTotal = true
        self.verNota = false
        self.nombreDetal = "Detal"
        self.nombreMayor = "Mayor"
        self.nombreEspecial = "Especial"
        self.agrupar = true
        self.modeloIA = ""
        self.vistaVentas = VistaVentas.tarjetas.rawValue
        self.avisarListas = true
        self.confirmarCobro = true
        self.actualizado = .now
    }

    var claveTema: Tema.Clave { Tema.Clave(rawValue: tema) ?? .barro }
    var vista: VistaVentas { VistaVentas(rawValue: vistaVentas) ?? .tarjetas }
    func nombreTarifa(_ t: Tarifa) -> String {
        switch t {
        case .detal: return nombreDetal
        case .mayor: return nombreMayor
        case .especial: return nombreEspecial
        }
    }
}

/// La paleta con la que se pintan las listas. Cinco, como en el diseño.
enum ColorLista {
    static func color(_ i: Int, _ tema: Tema) -> Color {
        switch i % 5 {
        case 1: return tema.acento2
        case 2: return tema.acento300
        case 3: return tema.acento2_300
        case 4: return tema.neutral900
        default: return tema.acento
        }
    }
    static let cuantos = 5
}

/// QUÉ CLASE DE SALIDA ES.
///
/// La mercancía sale igual y cuesta igual; lo que cambia es si entra dinero. Sin
/// esto, un regalo hay que anotarlo como una venta de cero pesos —y entonces el
/// margen sale mal— o no anotarlo —y entonces el inventario no cuadra.
enum Salida: String, CaseIterable, Codable, Identifiable {
    case venta, regalo, donacion, consumo, rebaja
    var id: String { rawValue }

    var etiqueta: String {
        switch self {
        case .venta: return "Venta"
        case .regalo: return "Regalo"
        case .donacion: return "Donación"
        case .consumo: return "Para la casa"
        case .rebaja: return "Rebaja"
        }
    }

    /// Si entra dinero. La rebaja sí cobra: cobra menos.
    var cobra: Bool { self == .venta || self == .rebaja }

    /// Cómo se llama en el cuadre y en el reporte.
    var enElCuadre: String {
        switch self {
        case .venta, .rebaja: return "Vendiste"
        case .regalo: return "Regalaste"
        case .donacion: return "Donaste"
        case .consumo: return "Para la casa"
        }
    }

    var explicacion: String {
        switch self {
        case .venta: return "Entra el dinero completo."
        case .regalo: return "Sale la mercancía y no entra nada. Cuenta en lo que te costó."
        case .donacion: return "Igual que un regalo, pero se cuenta aparte para poder sumarlo."
        case .consumo: return "Se lo llevó el negocio o la casa. No es una venta."
        case .rebaja: return "Se cobra menos de la tarifa. La diferencia se ve en el cuadre."
        }
    }
}

/// CÓMO SE VEN LOS ENCARGOS.
///
/// Tres formas de mirar lo mismo, porque no se mira siempre igual: despachando
/// hace falta el botón grande de cobrar; repasando al final del día hace falta
/// verlos todos de un vistazo.
enum VistaVentas: String, CaseIterable, Identifiable, Codable {
    case tarjetas, tabla, compacta
    var id: String { rawValue }

    var etiqueta: String {
        switch self {
        case .tarjetas: return "Tarjetas"
        case .tabla: return "Tabla"
        case .compacta: return "Compacta"
        }
    }
    var explicacion: String {
        switch self {
        case .tarjetas: return "Para despachar: cada encargo con su peso, su tarifa y el botón de cobrar."
        case .tabla: return "Para repasar: una fila por encargo, en columnas."
        case .compacta: return "Lo máximo en pantalla, sin botones."
        }
    }
    var icono: String {
        switch self {
        case .tarjetas: return "rectangle.grid.1x2"
        case .tabla: return "tablecells"
        case .compacta: return "list.bullet"
        }
    }
}
