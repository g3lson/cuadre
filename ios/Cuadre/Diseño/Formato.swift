import Foundation

/// CÓMO SE ESCRIBEN LOS NÚMEROS Y LAS FECHAS.
///
/// Todo en un sitio porque la app enseña la misma cifra en seis pantallas y
/// basta con que una la escriba distinta para que parezca que no cuadra.
enum Formato {
    /// Pesos, sin decimales y con coma de millares: «RD$1,234».
    ///
    /// Sin decimales a propósito: en el súper nadie paga 38.50 y ver «RD$38.00»
    /// en cada fila es ruido. Los centavos existen por dentro —el precio por
    /// libra sí los tiene— pero no se enseñan en las cifras grandes.
    static func pesos(_ n: Double, moneda: String = "RD$") -> String {
        moneda + entero(n.rounded())
    }

    static func entero(_ n: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")   // coma de millares, como se escribe en RD
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: n)) ?? String(Int(n))
    }

    /// Cantidades: «2», «5.2», «1.75». Hasta dos decimales y sin ceros de relleno.
    static func cantidad(_ n: Double) -> String {
        let r = (n * 100).rounded() / 100
        if r == r.rounded() { return String(Int(r)) }
        return String(format: "%g", r)
    }

    /// El precio unitario sí lleva decimales cuando los tiene: RD$38.50/lb.
    static func precio(_ n: Double, moneda: String = "RD$") -> String {
        let r = (n * 100).rounded() / 100
        if r == r.rounded() { return pesos(r, moneda: moneda) }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return moneda + (f.string(from: NSNumber(value: r)) ?? String(r))
    }

    private static let esDO = Locale(identifier: "es_DO")

    /// «hoy», «ayer», «sábado» si es de esta semana, «24 sep» si no.
    static func dia(_ f: Date, ahora: Date = .now) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(f) { return "hoy" }
        if cal.isDateInYesterday(f) { return "ayer" }
        if cal.isDateInTomorrow(f) { return "mañana" }
        let dias = abs(cal.dateComponents([.day], from: f, to: ahora).day ?? 99)
        let df = DateFormatter()
        df.locale = esDO
        df.setLocalizedDateFormatFromTemplate(dias < 7 ? "EEEE" : "d MMM")
        return df.string(from: f)
    }

    /// «Viernes 29 de septiembre», para el encabezado del cuadre.
    static func diaLargo(_ f: Date) -> String {
        let df = DateFormatter()
        df.locale = esDO
        df.dateFormat = "EEEE d 'de' MMMM"
        return df.string(from: f).prefix(1).uppercased() + df.string(from: f).dropFirst()
    }

    static func hora(_ f: Date) -> String {
        let df = DateFormatter()
        df.locale = esDO
        df.setLocalizedDateFormatFromTemplate("h:mm a")
        return df.string(from: f)
    }

    /// El saludo de la portada, según la hora que sea de verdad.
    static func saludo(_ ahora: Date = .now) -> String {
        switch Calendar.current.component(.hour, from: ahora) {
        case 0..<12: return "Buen día"
        case 12..<19: return "Buenas tardes"
        default: return "Buenas noches"
        }
    }

    /// La inicial del avatar. «Doña Carmen» es Carmen, no una D.
    static func inicial(_ nombre: String) -> String {
        let limpio = nombre
            .replacingOccurrences(of: #"^(doña|don|sr\.?|sra\.?|srta\.?)\s+"#,
                                  with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
        return String(limpio.first ?? "?").uppercased()
    }

    /// Las fechas que viajan al servidor: ISO con milisegundos y en UTC, que es
    /// exactamente lo que escribe el servidor. Se comparan como texto allá, así
    /// que un formato distinto aquí rompería el «qué cambió desde cuándo».
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Solo el día, para el movimiento de Chinola.
    static func fechaCorta(_ f: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: f)
    }
}
