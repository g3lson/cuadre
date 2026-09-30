import Foundation

/// LAS UNIDADES.
///
/// Las nueve con las que se compra en RD. Las tres primeras pesan, y eso
/// importa: si una unidad pesa, la app puede decirte a cuánto te sale la libra
/// aunque hayas comprado en kilos, que es la cuenta que nadie hace de cabeza en
/// el mostrador.
struct Unidad: Identifiable, Hashable {
    let id: String          // «lb», «kg», … el mismo texto que viaja al servidor
    let nombre: String      // «libra», para «precio por libra»
    let etiqueta: String    // «Libra», para el menú
    /// Cuántas libras es una de estas. `nil` si no es cuestión de peso.
    let enLibras: Double?

    var pesa: Bool { enLibras != nil }

    static let todas: [Unidad] = [
        .init(id: "lb", nombre: "libra", etiqueta: "Libra", enLibras: 1),
        .init(id: "kg", nombre: "kilo", etiqueta: "Kilo", enLibras: 2.20462),
        .init(id: "oz", nombre: "onza", etiqueta: "Onza", enLibras: 0.0625),
        .init(id: "ud", nombre: "unidad", etiqueta: "Unidad", enLibras: nil),
        .init(id: "doc", nombre: "docena", etiqueta: "Docena", enLibras: nil),
        .init(id: "paq", nombre: "paquete", etiqueta: "Paquete", enLibras: nil),
        .init(id: "saco", nombre: "saco", etiqueta: "Saco", enLibras: nil),
        .init(id: "gal", nombre: "galón", etiqueta: "Galón", enLibras: nil),
        .init(id: "L", nombre: "litro", etiqueta: "Litro", enLibras: nil),
    ]

    /// La unidad de una clave. Si la clave no existe —porque vino de un
    /// servidor más nuevo— se cae a «unidad», que es la que no promete nada.
    static func de(_ clave: String) -> Unidad {
        todas.first { $0.id == clave } ?? todas[3]
    }

    /// El paso del botón de más y menos: media libra cuando pesa, una unidad
    /// cuando no. Nadie compra media docena de huevos tocando un botón.
    var paso: Double { pesa ? 0.5 : 1 }
}

/// LAS CATEGORÍAS.
///
/// Sirven para dos cosas distintas y por eso llevan dos órdenes: agrupar el
/// gasto al mandarlo a Chinola, y **recorrer el súper sin dar vueltas**. El
/// orden de `todas` es el del pasillo, no el alfabético: se entra por los
/// vegetales, se pasa por la carne y la nevera, y los víveres y la limpieza
/// quedan para el final porque pesan y van debajo en el carrito.
enum Categoria {
    static let todas = [
        "Frutas y vegetales",
        "Carnes y pescados",
        "Lácteos y huevos",
        "Panadería",
        "Bebidas",
        "Víveres",
        "Limpieza",
        "Higiene",
        "Ferretería",
        "Otros",
    ]
    static let porDefecto = "Otros"

    /// Dónde va en el recorrido. Lo que no se reconoce va al final.
    static func orden(_ c: String) -> Int {
        todas.firstIndex(of: c) ?? todas.count
    }

    /// QUÉ ES ESTO, SIN PREGUNTARLE A NADIE.
    ///
    /// Una tabla de palabras, no un modelo: adivinar la categoría de «pollo» no
    /// necesita una llamada a la red, y si la necesitara la función no serviría
    /// en el pasillo del súper, que es donde se usa. Se equivoca alguna vez y se
    /// corrige tocando; lo que no puede es tardar.
    ///
    /// Las palabras son las de aquí: chillo, catibía, auyama, sazón.
    static func adivina(_ nombre: String) -> String {
        let n = nombre.folding(options: .diacriticInsensitive, locale: nil).lowercased()
        guard !n.isEmpty else { return porDefecto }
        for (categoria, palabras) in tabla {
            for p in palabras where n.contains(p) { return categoria }
        }
        return porDefecto
    }

    /// Orden importante: lo más específico primero. «Queso de freír» tiene que
    /// caer en lácteos antes de que «freír» lo mande a otro sitio.
    private static let tabla: [(String, [String])] = [
        ("Lácteos y huevos", [
            "leche", "queso", "yogur", "yogurt", "mantequilla", "margarina", "crema",
            "huevo", "suero", "requeson", "cuajada",
        ]),
        ("Carnes y pescados", [
            "pollo", "res", "cerdo", "puerco", "chuleta", "costilla", "carne", "molida",
            "bistec", "filete", "higado", "salchicha", "salami", "jamon", "tocineta", "chicharron",
            "pescado", "chillo", "mero", "carite", "bacalao", "atun", "sardina", "camaron",
            "langosta", "cangrejo", "pulpo", "calamar", "lambi", "pavo", "chivo", "conejo",
        ]),
        ("Frutas y vegetales", [
            "platano", "guineo", "yuca", "batata", "name", "yautia", "auyama", "catibia",
            "tomate", "cebolla", "ajo", "aji", "pimiento", "cilantro", "cilantrico", "perejil",
            "lechuga", "repollo", "zanahoria", "papa", "pepino", "berenjena", "molondron",
            "aguacate", "limon", "naranja", "china", "mango", "lechosa", "papaya", "pina",
            "guayaba", "chinola", "maracuya", "coco", "melon", "sandia", "uva", "manzana",
            "fresa", "banana", "apio", "brocoli", "espinaca", "remolacha", "vegetal", "verdura",
            "fruta", "ensalada", "mazorca", "maiz tierno",
        ]),
        ("Panadería", [
            "pan ", "pan", "sobao", "agua de pan", "galleta", "bizcocho", "pastel", "tarta",
            "dona", "croissant", "tostada", "panecillo", "reglete",
        ]),
        ("Bebidas", [
            "agua", "refresco", "jugo", "cerveza", "ron", "vino", "whisky", "malta", "soda",
            "cola", "gatorade", "energizante", "cafe", "te ", "chocolate en polvo", "leche de coco",
        ]),
        ("Víveres", [
            "arroz", "habichuela", "frijol", "guandul", "lenteja", "garbanzo", "azucar", "sal",
            "aceite", "vinagre", "harina", "maiz", "avena", "pasta", "espagueti", "espagueti",
            "macarron", "fideo", "salsa", "pasta de tomate", "sazon", "adobo", "oregano",
            "canela", "clavo", "sopita", "consome", "caldo", "miel", "mermelada", "manteca",
            "maizena", "bicarbonato", "polvo de hornear", "cacao", "gelatina", "enlatado",
        ]),
        ("Limpieza", [
            "detergente", "jabon de cuaba", "jabon de lavar", "cloro", "suavizante", "desinfectante",
            "mistolin", "ace ", "fabuloso", "esponja", "escoba", "trapeador", "servilleta",
            "papel toalla", "bolsa de basura", "ambientador", "limpia", "lavaplatos",
        ]),
        ("Higiene", [
            "papel higienico", "papel sanitario", "pasta dental", "crema dental", "cepillo de diente",
            "desodorante", "shampoo", "champu", "acondicionador", "jabon de bano", "jabon de tocador",
            "toalla sanitaria", "panal", "afeitar", "alcohol", "algodon", "curita", "pastilla",
        ]),
        ("Ferretería", [
            "cemento", "varilla", "arena", "block", "clavo", "tornillo", "tuerca", "pintura",
            "brocha", "alambre", "tuberia", "tubo", "cable", "bombillo", "interruptor", "candado",
            "martillo", "destornillador", "alicate", "cinta", "silicon", "lija", "madera", "zinc",
        ]),
    ]
}

/// Las tres tarifas de venta. El nombre lo puede cambiar quien vende.
enum Tarifa: String, CaseIterable, Codable {
    case detal, mayor, especial

    var etiqueta: String {
        switch self {
        case .detal: return "Detal"
        case .mayor: return "Mayor"
        case .especial: return "Especial"
        }
    }
}
