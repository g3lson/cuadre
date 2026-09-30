import Foundation
import UserNotifications

/// LOS RECORDATORIOS.
///
/// Una lista con fecha es una cita: «la compra del sábado». Si la app no avisa,
/// la lista se queda hecha y la compra se hace de memoria, que es exactamente lo
/// que venía a evitar.
///
/// Todo es local: no hay servidor de notificaciones ni tokens que registrar. El
/// teléfono se lo recuerda a sí mismo, así que funciona sin señal y no hay nada
/// que pueda filtrarse.
enum Avisos {
    private static let centro = UNUserNotificationCenter.current()

    /// Se pide permiso la primera vez que hay algo que recordar, no al arrancar.
    /// Pedirlo antes de que sirva para nada es la manera más rápida de que
    /// alguien diga que no para siempre.
    @discardableResult
    static func pidePermiso() async -> Bool {
        let estado = await centro.notificationSettings().authorizationStatus
        if estado == .authorized || estado == .provisional { return true }
        if estado == .denied { return false }
        return (try? await centro.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func permitido() async -> Bool {
        let e = await centro.notificationSettings().authorizationStatus
        return e == .authorized || e == .provisional
    }

    private static func identificador(_ listaId: String) -> String { "lista-" + listaId }

    /// Programa —o reprograma— el recordatorio de una lista.
    ///
    /// Avisa la víspera por la tarde y no la mañana del día: una compra se
    /// prepara antes, y un aviso a las ocho del sábado llega cuando ya se salió
    /// de casa.
    static func recuerda(_ lista: Lista) async {
        olvida(lista.id)
        guard !lista.cerrada, lista.vivo else { return }

        let cal = Calendar.current
        guard let vispera = cal.date(byAdding: .day, value: -1, to: lista.fecha),
              var cuando = cal.date(bySettingHour: 18, minute: 0, second: 0, of: vispera),
              cuando > .now || cal.isDateInToday(lista.fecha) else { return }

        // Si la víspera ya pasó pero la compra es hoy, se avisa dentro de un rato.
        if cuando <= .now { cuando = Date().addingTimeInterval(3600) }
        guard cuando > .now, await pidePermiso() else { return }

        let c = UNMutableNotificationContent()
        c.title = lista.nombre
        c.body = lista.tienda.isEmpty
            ? "Tu compra es \(Formato.dia(lista.fecha)). La lista está lista."
            : "Tu compra en \(lista.tienda) es \(Formato.dia(lista.fecha)). La lista está lista."
        c.sound = .default
        c.userInfo = ["lista": lista.id]

        let disparo = UNCalendarNotificationTrigger(
            dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: cuando),
            repeats: false)
        try? await centro.add(UNNotificationRequest(identifier: identificador(lista.id),
                                                    content: c, trigger: disparo))
    }

    static func olvida(_ listaId: String) {
        centro.removePendingNotificationRequests(withIdentifiers: [identificador(listaId)])
    }

    /// Repasa todas las listas y deja los recordatorios como deben estar. Se
    /// llama al arrancar y después de sincronizar: una lista creada en el otro
    /// teléfono también tiene que avisar en este.
    @MainActor
    static func repasa(_ listas: [Lista]) async {
        guard await permitido() else { return }
        let pendientes = await centro.pendingNotificationRequests()
        let puestos = Set(pendientes.map(\.identifier))

        for l in listas {
            let id = identificador(l.id)
            let debe = l.vivo && !l.cerrada && l.fecha > Date().addingTimeInterval(-86400)
            if debe { await recuerda(l) } else if puestos.contains(id) { olvida(l.id) }
        }
    }
}
