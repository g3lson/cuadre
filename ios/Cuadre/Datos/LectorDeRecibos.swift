import Foundation
import UIKit
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

/// LEER EL RECIBO EN EL PROPIO TELÉFONO.
///
/// El orden importa y es a propósito:
///
///   1. **El texto lo saca el teléfono.** El marco Vision hace OCR desde iOS 13,
///      sin conexión, gratis, en medio segundo y sin que la foto salga de aquí.
///      Mandar una foto de 120 KB a un servidor para que un modelo la mire es
///      pagar por hacer peor lo que el aparato ya hace bien.
///   2. **La estructura, también, si se puede.** Con Apple Intelligence
///      (iOS 26 en un iPhone que lo lleve) el modelo del sistema convierte ese
///      texto en filas sin salir del teléfono, sin cuota y sin costo.
///   3. **Y si no, el servidor** — pero mandando el TEXTO, no la foto: son dos
///      kilobytes en vez de ciento veinte, y así también funciona en un iPhone
///      viejo o con el idioma del sistema sin Apple Intelligence.
///
/// La foto solo viaja si el OCR no encontró nada legible, que es el caso raro.
enum LectorDeRecibos {

    /// ¿Puede hacerlo todo el teléfono, sin servidor?
    static var todoAquí: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Cómo explicárselo a quien lo va a usar.
    static var comoSeHace: String {
        todoAquí
            ? "Se lee aquí mismo, en tu iPhone. La foto no sale del teléfono."
            : "El texto se lee aquí en tu iPhone; solo ese texto se manda para ordenarlo."
    }

    // MARK: - 1 · El texto, con Vision

    enum Fallo: LocalizedError {
        case sinTexto
        var errorDescription: String? {
            "No pude leer letras en esa foto. Prueba con más luz y el recibo derecho."
        }
    }

    /// El texto del recibo, línea por línea y de arriba abajo.
    ///
    /// `usesLanguageCorrection` va apagado: un recibo está lleno de
    /// abreviaturas y códigos («PLATANO BARAHONERO UD», «B0100000457»), y el
    /// corrector los «arregla» hasta dejarlos irreconocibles.
    static func texto(de imagen: UIImage) async throws -> String {
        guard let cg = imagen.cgImage else { throw Fallo.sinTexto }

        let lineas: [String] = try await withCheckedThrowingContinuation { sigue in
            let peticion = VNRecognizeTextRequest { peticion, error in
                if let error { sigue.resume(throwing: error); return }
                let obs = (peticion.results as? [VNRecognizedTextObservation]) ?? []
                // De arriba abajo y de izquierda a derecha: el orden del papel.
                let ordenadas = obs.sorted {
                    abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.006
                        ? $0.boundingBox.midY > $1.boundingBox.midY
                        : $0.boundingBox.minX < $1.boundingBox.minX
                }
                sigue.resume(returning: ordenadas.compactMap { $0.topCandidates(1).first?.string })
            }
            peticion.recognitionLevel = .accurate
            peticion.usesLanguageCorrection = false
            peticion.recognitionLanguages = ["es-ES", "en-US"]

            do {
                try VNImageRequestHandler(cgImage: cg, options: [:]).perform([peticion])
            } catch {
                sigue.resume(throwing: error)
            }
        }

        let texto = lineas.joined(separator: "\n")
        guard texto.count >= 20 else { throw Fallo.sinTexto }
        return texto
    }

    // MARK: - 2 · Las filas, con Apple Intelligence

    /// Convierte el texto en productos usando el modelo del sistema.
    /// Devuelve `nil` si este iPhone no lo tiene: entonces se usa el servidor.
    static func productos(deTexto texto: String, moneda: String) async -> IA.Recibo? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            do {
                return try await conElModeloDelSistema(texto, moneda: moneda)
            } catch {
                // Si el modelo del sistema se atraganta, no se enseña un error:
                // se sigue por el servidor, que es lo que la persona esperaba.
                return nil
            }
        }
        #endif
        return nil
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func conElModeloDelSistema(_ texto: String, moneda: String) async throws -> IA.Recibo {
        let sesion = LanguageModelSession(instructions: Instructions(reglas))
        let salida = try await sesion.respond(
            to: Prompt("Este es el texto de un recibo de compra dominicano:\n\n\(texto)"),
            generating: ReciboGenerado.self)
        let r = salida.content
        return IA.Recibo(
            tienda: r.tienda,
            total: r.total,
            productos: r.productos.map {
                IA.ProductoLeido(
                    nombre: $0.nombre,
                    unidad: Unidad.todas.map(\.id).contains($0.unidad) ? $0.unidad : "ud",
                    cantidad: max(0, $0.cantidad),
                    precio: max(0, $0.precioPorUnidad),
                    nota: $0.nota,
                    categoria: $0.categoria.isEmpty ? Categoria.porDefecto : $0.categoria)
            })
    }

    // Sin `private`: el macro `@Generable` genera código que nombra el tipo
    // desde fuera, y con `private` no lo alcanza.
    @available(iOS 26.0, *)
    @Generable
    struct ReciboGenerado {
        @Guide(description: "El nombre del supermercado o la tienda, tal como sale arriba del recibo.")
        var tienda: String
        @Guide(description: "El total que se pagó, solo el número.")
        var total: Double
        @Guide(description: "Una entrada por cada producto. Ni impuestos, ni propinas, ni descuentos, ni el total.")
        var productos: [ProductoGenerado]
    }

    @available(iOS 26.0, *)
    @Generable
    struct ProductoGenerado {
        @Guide(description: "El producto entero, con su variedad: «Azúcar crema», «Arroz selecto», «Leche entera».")
        var nombre: String
        @Guide(description: "Una de: lb, kg, oz, ud, doc, paq, saco, gal, L.")
        var unidad: String
        @Guide(description: "Cuántas unidades de esas.")
        var cantidad: Double
        @Guide(description: "Lo que cuesta UNA unidad. Si el recibo trae el importe de la línea, divídelo entre la cantidad.")
        var precioPorUnidad: Double
        @Guide(description: "Marca, tamaño o detalle. Vacío si no hay.")
        var nota: String
        @Guide(description: "Una de: Víveres, Carnes y pescados, Lácteos y huevos, Frutas y vegetales, Panadería, Limpieza, Higiene, Bebidas, Ferretería, Otros.")
        var categoria: String
    }
    #endif

    /// Las mismas reglas que usa el servidor, para que la app dé lo mismo se lea
    /// donde se lea. Si se cambian aquí, se cambian allá.
    private static let reglas = """
        Conviertes el texto de un recibo dominicano en la lista de lo que se compró.

        - Los precios son pesos dominicanos, números sin símbolo ni separadores.
        - «precioPorUnidad» es lo que cuesta UNA unidad. Los recibos suelen traer el
          importe de la línea entera: divídelo entre la cantidad.
        - El nombre lleva la variedad dentro: «Azúcar crema», no «Azúcar».
        - Habla dominicano: plátanos barahoneros, pan sobao, queso de freír, chillo.
        - Un saco de arroz es 1 saco, no 50 libras.
        - No incluyas ITBIS, propinas, descuentos, subtotales ni el total como productos.
        """
}
