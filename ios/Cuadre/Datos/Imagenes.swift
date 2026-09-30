import SwiftUI
import UIKit

/// EL LOGO Y LA PORTADA DE UN NEGOCIO.
///
/// Se suben una vez y lo que se guarda en el grupo es la dirección, no la
/// imagen: el contenido de cada fila viaja entero en cada sincronización de
/// cada teléfono del grupo, y un logo en base64 ahí dentro se pagaría cien
/// veces por una foto que cambia una vez al año.
///
/// El nombre del archivo en el servidor es el hash de su contenido, así que una
/// imagen distinta tiene otra dirección: se puede guardar en disco para siempre
/// sin preguntar nunca si cambió. Por eso el caché de aquí no caduca.
enum Imagenes {
    struct Subida: Decodable { let url: String; var bytes: Int = 0 }

    /// Sube una imagen al negocio y devuelve su dirección.
    ///
    /// Se reduce antes: la cámara de un iPhone da doce megapíxeles y un logo se
    /// ve a cuarenta y cuatro puntos. Subir el original sería mandar tres
    /// megabytes por una miniatura, y pagarlo cada vez que alguien abre la app.
    static func sube(_ imagen: UIImage, aGrupo id: String, lado: CGFloat) async throws -> String {
        guard let jpeg = comprime(imagen, lado: lado) else { throw Api.Fallo.respuestaRara }
        let r: Subida = try await Api.shared.sube(jpeg, a: "api/grupos/\(id)/imagen")
        // Se deja ya en el disco: quien acaba de elegir la foto la ve al
        // instante y sin volver a bajarla.
        guarda(jpeg, en: r.url)
        return r.url
    }

    private static func comprime(_ imagen: UIImage, lado: CGFloat) -> Data? {
        let mayor = max(imagen.size.width, imagen.size.height)
        let escala = mayor > lado ? lado / mayor : 1
        let tamano = CGSize(width: (imagen.size.width * escala).rounded(),
                            height: (imagen.size.height * escala).rounded())
        let r = UIGraphicsImageRenderer(size: tamano)
        let reducida = r.image { _ in imagen.draw(in: CGRect(origin: .zero, size: tamano)) }
        return reducida.jpegData(compressionQuality: 0.82)
    }

    // MARK: - El disco

    private static let carpeta: URL = {
        let c = URL.cachesDirectory.appending(path: "negocios")
        try? FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)
        return c
    }()

    private static func archivo(_ url: String) -> URL? {
        guard let nombre = url.split(separator: "/").last, !nombre.isEmpty else { return nil }
        return carpeta.appending(path: String(nombre))
    }

    static func guarda(_ datos: Data, en url: String) {
        guard let a = archivo(url) else { return }
        try? datos.write(to: a, options: .atomic)
    }

    static func delDisco(_ url: String) -> UIImage? {
        guard let a = archivo(url), let d = try? Data(contentsOf: a) else { return nil }
        return UIImage(data: d)
    }

    /// La baja si no estaba, y la deja guardada. Devuelve `nil` sin ruido: que
    /// no se vea el logo no es un error que haya que enseñarle a nadie.
    static func trae(_ url: String) async -> UIImage? {
        if let ya = delDisco(url) { return ya }
        guard let u = URL(string: url) else { return nil }
        guard let (d, r) = try? await URLSession.shared.data(from: u),
              (r as? HTTPURLResponse)?.statusCode == 200,
              let img = UIImage(data: d) else { return nil }
        guarda(d, en: url)
        return img
    }
}

/// Una imagen del negocio, del disco si ya está y de la red si no.
///
/// No se usa `AsyncImage` porque vuelve a bajar la imagen cada vez que la vista
/// se reconstruye, y la portada de la venta se reconstruye con cada encargo que
/// se marca. Esto la lee del disco, que es donde vive desde la primera vez.
struct ImagenDelNegocio<Mientras: View>: View {
    let url: String
    var contentMode: ContentMode = .fill
    @ViewBuilder var mientras: Mientras

    @State private var imagen: UIImage?

    var body: some View {
        Group {
            if let imagen {
                Image(uiImage: imagen)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                mientras
            }
        }
        .task(id: url) {
            guard !url.isEmpty else { imagen = nil; return }
            if let ya = Imagenes.delDisco(url) { imagen = ya; return }
            imagen = await Imagenes.trae(url)
        }
    }
}
