import Foundation

/// DÍA, SEMANA O MES.
///
/// El cuadre nació siendo de un día, que es cuando se hace de verdad: se cierra
/// el mostrador y se cuenta. Pero «¿cómo fue la semana?» y «¿cuánto llevo este
/// mes?» son preguntas que también se hacen, y contestarlas sumando siete
/// pantallas a mano no es contestarlas.
enum Periodo: String, CaseIterable, Identifiable {
    case dia, semana, mes
    var id: String { rawValue }

    var etiqueta: String {
        switch self {
        case .dia: return "Día"
        case .semana: return "Semana"
        case .mes: return "Mes"
        }
    }

    /// La unidad con la que se mueve hacia atrás y hacia adelante.
    var paso: Calendar.Component {
        switch self {
        case .dia: return .day
        case .semana: return .weekOfYear
        case .mes: return .month
        }
    }

    /// El tramo que contiene esa fecha: desde incluido, hasta excluido.
    func rango(de fecha: Date, _ cal: Calendar = .current) -> (desde: Date, hasta: Date) {
        let inicio: Date
        switch self {
        case .dia:
            inicio = cal.startOfDay(for: fecha)
        case .semana:
            inicio = cal.dateInterval(of: .weekOfYear, for: fecha)?.start
                ?? cal.startOfDay(for: fecha)
        case .mes:
            inicio = cal.dateInterval(of: .month, for: fecha)?.start
                ?? cal.startOfDay(for: fecha)
        }
        let fin = cal.date(byAdding: paso, value: 1, to: inicio) ?? inicio
        return (inicio, fin)
    }

    /// Cómo se llama ese tramo cuando se lee. «Hoy» y «esta semana» antes que
    /// la fecha: al abrir la pantalla, lo que se está mirando es el presente.
    func titulo(_ fecha: Date, _ cal: Calendar = .current) -> String {
        let r = rango(de: fecha, cal)
        switch self {
        case .dia:
            return Formato.diaLargo(fecha)
        case .semana:
            if r.desde == rango(de: .now, cal).desde { return "Esta semana" }
            let hasta = cal.date(byAdding: .day, value: -1, to: r.hasta) ?? r.hasta
            return "Del \(Formato.diaCorto(r.desde)) al \(Formato.diaCorto(hasta))"
        case .mes:
            if r.desde == rango(de: .now, cal).desde { return "Este mes" }
            return Formato.mesLargo(r.desde)
        }
    }

    /// Cuántos días tiene el tramo. Es lo que dibuja el gráfico.
    func dias(de fecha: Date, _ cal: Calendar = .current) -> [Date] {
        let r = rango(de: fecha, cal)
        var v: [Date] = []
        var d = r.desde
        while d < r.hasta {
            v.append(d)
            d = cal.date(byAdding: .day, value: 1, to: d) ?? r.hasta
        }
        return v
    }
}
