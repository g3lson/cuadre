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
    @Attribute(.unique) var id: String
    var nombre: String
    var tienda: String
    var presupuesto: Double
    var fecha: Date
    /// Índice en la paleta del tema: el color se resuelve al pintar, para que
    /// cambiar de tema cambie también los colores de las listas.
    var color: Int
    /// «activa» mientras se compra, «cerrada» cuando cuadró.
    var estado: String
    var cerradaEn: Date?
    var notaCierre: String
    /// Qué se hizo con el gasto: el texto que se enseña en la lista cerrada.
    var chinolaNota: String
    var orden: Int
    var actualizado: Date
    var borrado: Date?
    var subido: Date?

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
        self.actualizado = .now
    }

    var cerrada: Bool { estado == "cerrada" }
}

@Model final class Articulo: Sincronizable {
    @Attribute(.unique) var id: String
    var listaId: String
    var nombre: String
    var unidad: String
    var cantidad: Double
    var precio: Double
    var hecho: Bool
    var nota: String
    var categoria: String
    var orden: Int
    /// Quién lo echó al carrito, cuando la lista es de dos. Se guarda el nombre
    /// y no el identificador: lo que hay que enseñar es «lo cogió Ana», y pedirle
    /// el nombre al servidor por cada fila para eso sería absurdo.
    var hechoPor: String
    var actualizado: Date
    var borrado: Date?
    var subido: Date?

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
    @Attribute(.unique) var id: String
    var titulo: String
    var fecha: Date
    /// «abierto» mientras se despacha, «cerrado» cuando se cuadró el día.
    var estado: String
    var actualizado: Date
    var borrado: Date?
    var subido: Date?

    init(id: String = UUID().uuidString, titulo: String, fecha: Date = .now, estado: String = "abierto") {
        self.id = id
        self.titulo = titulo
        self.fecha = fecha
        self.estado = estado
        self.actualizado = .now
    }
}

@Model final class Encargo: Sincronizable {
    @Attribute(.unique) var id: String
    var eventoId: String
    var cliente: String
    var telefono: String
    var producto: String
    var unidad: String
    /// Lo que pidió, que no tiene por qué ser lo que se le despachó.
    var pedido: Double
    var cantidad: Double
    var tarifa: String
    var precioDetal: Double
    var precioMayor: Double
    var precioEspecial: Double
    /// Lo que te costó a ti la libra. Es lo que hace que el cuadre sepa la ganancia.
    var costo: Double
    /// «pendiente» o «cobrado».
    var estado: String
    var metodo: String
    var nota: String
    var cobradoEn: Date?
    var actualizado: Date
    var borrado: Date?
    var subido: Date?

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
        self.metodo = ""
        self.nota = ""
        self.actualizado = .now
    }

    var precioAplicado: Double {
        switch Tarifa(rawValue: tarifa) ?? .detal {
        case .detal: return precioDetal
        case .mayor: return precioMayor
        case .especial: return precioEspecial
        }
    }
    var total: Double { cantidad * precioAplicado }
    var costoTotal: Double { cantidad * costo }
    var cobrado: Bool { estado == "cobrado" }
}

@Model final class Producto: Sincronizable {
    @Attribute(.unique) var id: String
    var nombre: String
    var categoria: String
    var unidad: String
    var costo: Double
    var precioDetal: Double
    var precioMayor: Double
    var precioEspecial: Double
    var actualizado: Date
    var borrado: Date?
    var subido: Date?

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
    @Attribute(.unique) var id: String
    var nombre: String
    var telefono: String
    var actualizado: Date
    var borrado: Date?
    var subido: Date?

    init(id: String = UUID().uuidString, nombre: String, telefono: String = "") {
        self.id = id
        self.nombre = nombre
        self.telefono = telefono
        self.actualizado = .now
    }
}

@Model final class Tienda: Sincronizable {
    @Attribute(.unique) var id: String
    var nombre: String
    var actualizado: Date
    var borrado: Date?
    var subido: Date?

    init(id: String = UUID().uuidString, nombre: String) {
        self.id = id
        self.nombre = nombre
        self.actualizado = .now
    }
}

/// Los ajustes son una sola fila, y su `id` es el de la persona: así el
/// sincronizador los trata igual que a todo lo demás sin un caso aparte.
@Model final class Ajustes: Sincronizable {
    @Attribute(.unique) var id: String
    var tema: String
    var moneda: String
    var unidadPorDefecto: String
    var modoVendedor: Bool
    var nombreNegocio: String
    var verCantidad: Bool
    var verPrecio: Bool
    var verTotal: Bool
    var verNota: Bool
    var nombreDetal: String
    var nombreMayor: String
    var nombreEspecial: String
    /// Agrupar la lista por categoría para recorrer el súper en orden en vez de
    /// ir y volver por los pasillos.
    var agrupar: Bool
    /// El modelo de IA que eligió esta persona. Vacío = el que traiga el servidor.
    var modeloIA: String
    var actualizado: Date
    var borrado: Date?
    var subido: Date?

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
        self.actualizado = .now
    }

    var claveTema: Tema.Clave { Tema.Clave(rawValue: tema) ?? .barro }
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
